import Foundation
import Protocols

/// Owns the lifetime of one authorized effect; a late result carries observations only.
public enum ToolEffectRunner {
    public static func run(
        toolID: String, timeoutMilliseconds: Int,
        onLateResult: @escaping @Sendable (ToolInvocationResult) async -> Void,
        operation: @escaping @Sendable () async -> AgentLoopToolOutcome
    ) async -> AgentLoopToolOutcome {
        await run(toolID: toolID, timeoutMilliseconds: timeoutMilliseconds, now: { .now },
            onLateResult: onLateResult, operation: operation)
    }

    /// Injected time keeps effect-lifetime evidence independent of unrelated scheduler load.
    public static func run(
        toolID: String, timeoutMilliseconds: Int,
        now: @escaping @Sendable () async -> ContinuousClock.Instant,
        onLateResult: @escaping @Sendable (ToolInvocationResult) async -> Void,
        operation: @escaping @Sendable () async -> AgentLoopToolOutcome
    ) async -> AgentLoopToolOutcome {
        if Task.isCancelled { return notStarted(toolID) }
        let result = EffectResultBox()
        let cancellation = EffectCancellation()
        let startedAt = await now()
        let deadline = timeoutMilliseconds > 0 ? startedAt + .milliseconds(timeoutMilliseconds) : nil
        return await withTaskCancellationHandler {
            // Install cancellation ownership before allowing the operation to acquire its effect permit.
            let start = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let task = Task {
                for await _ in start.stream { break }
                let outcome = Task.isCancelled ? notStarted(toolID) : await operation()
                if await result.complete(outcome) { await onLateResult(outcome.result) }
            }
            cancellation.install(task)
            start.continuation.yield(())
            start.continuation.finish()
            while true {
                if let known = await result.value { return known }
                var expired = false
                if let deadline { expired = await now() >= deadline }
                if Task.isCancelled || expired {
                    // complete/abandon are one atomic decision; exactly one path owns the actual result.
                    if let raced = await result.abandon() { return raced }
                    cancellation.cancel()
                    return .init(result: .init(tool: toolID, ok: false,
                        data: .object(["requiresReconciliation": .bool(true), "cancelled": .bool(Task.isCancelled),
                            "timedOut": .bool(!Task.isCancelled)]),
                        error: .init(code: "tool_execution_interrupted",
                            message: Task.isCancelled ? "Cancellation was requested while the effect was active. Its outcome is not yet known."
                                : "The effect deadline expired before its outcome became known.", retryable: false)))
                }
                do { try await Task.sleep(for: .milliseconds(5)) }
                catch { /* The next iteration settles a known result or records the interrupted outcome. */ }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func notStarted(_ toolID: String) -> AgentLoopToolOutcome {
        .init(result: .init(tool: toolID, ok: false,
            error: .init(code: "not_executed_cancelled", message: "The invocation was cancelled before execution.", retryable: false)))
    }
}

private actor EffectResultBox {
    private(set) var value: AgentLoopToolOutcome?
    private var abandoned = false

    /// True transfers observation-only ownership to the late-result writer.
    func complete(_ outcome: AgentLoopToolOutcome) -> Bool {
        if abandoned { return true }
        value = outcome
        return false
    }

    func abandon() -> AgentLoopToolOutcome? {
        if let value { return value }
        abandoned = true
        return nil
    }
}

/// Cancellation handlers are synchronous. This per-invocation lock bridges installation to Task.cancel;
/// effect state and result arbitration remain actor-owned.
private final class EffectCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var task: Task<Void, Never>?

    func install(_ task: Task<Void, Never>) {
        lock.lock()
        self.task = task
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let active = task
        lock.unlock()
        active?.cancel()
    }
}
