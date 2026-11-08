import Foundation
import Testing
import AgentRuntime
import PluginSDK
import Protocols
import SloppyRuntime

private actor EffectLifetimeProbe {
    private(set) var entered = false
    private(set) var returned: AgentLoopToolOutcome?
    private(set) var late: [ToolInvocationResult] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var entryWaiters: [CheckedContinuation<Bool, Never>] = []
    private var lateWaiters: [CheckedContinuation<Void, Never>] = []
    private let origin = ContinuousClock.now
    private var expired = false
    func now() -> ContinuousClock.Instant { expired ? origin + .seconds(60) : origin }
    func expire() { expired = true }
    func waitForEntry() async -> Bool {
        if entered { return true }
        if returned != nil { return false }
        return await withCheckedContinuation { entryWaiters.append($0) }
    }
    func waitForLate() async {
        if late.isEmpty { await withCheckedContinuation { lateWaiters.append($0) } }
    }
    func hold() async {
        entered = true
        for waiter in entryWaiters { waiter.resume(returning: true) }
        entryWaiters.removeAll()
        await withCheckedContinuation { releaseContinuation = $0 }
    }
    func release() { releaseContinuation?.resume(); releaseContinuation = nil }
    func finish(_ value: AgentLoopToolOutcome) {
        returned = value
        for waiter in entryWaiters { waiter.resume(returning: entered) }
        entryWaiters.removeAll()
    }
    func recordLate(_ value: ToolInvocationResult) {
        late.append(value)
        for waiter in lateWaiters { waiter.resume() }
        lateWaiters.removeAll()
    }
}

@Suite("Owned effect lifetime")
struct ToolEffectRunnerTests {
    @Test(.timeLimit(.minutes(3)), arguments: [false, true])
    func interruptedEffectsKeepTheirActualLateOutcome(cancel: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("effect-lifetime-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("effect.txt")
        let probe = EffectLifetimeProbe()
        let invocation = Task {
            let result = await ToolEffectRunner.run(toolID: "files.write", timeoutMilliseconds: cancel ? 5_000 : 30,
                now: { await probe.now() },
                onLateResult: { await probe.recordLate($0) }, operation: {
                    await probe.hold() // Models an external operation that cannot guarantee cancellation.
                    do {
                        try Data("one effect".utf8).write(to: file)
                        return .init(result: .init(tool: "files.write", ok: true, data: .string("actual outcome")),
                            completion: .init(disposition: .completed, summary: "Late completion has no authority",
                                verification: [], verificationEvidence: [], limitations: []))
                    } catch {
                        return .init(result: .init(tool: "files.write", ok: false,
                            error: .init(code: "fixture_write_failed", message: error.localizedDescription, retryable: false)))
                    }
                })
            await probe.finish(result)
        }
        try #require(await probe.waitForEntry())
        if cancel { invocation.cancel() } else { await probe.expire() }
        await invocation.value
        let interrupted = await probe.returned
        #expect(interrupted != nil)
        #expect(interrupted?.result.error?.code == "tool_execution_interrupted")
        #expect(interrupted?.result.error?.retryable == false)
        #expect(interrupted?.result.data?.asObject?["requiresReconciliation"]?.asBool == true)
        #expect(interrupted?.completion == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        await probe.release()
        await invocation.value
        await probe.waitForLate()
        #expect(await probe.late.count == 1)
        #expect(await probe.late.first?.ok == true)
        #expect(try String(contentsOf: file, encoding: .utf8) == "one effect")
    }

    @Test(arguments: [false, true])
    func anUnknownPlaceholderCannotOverwriteAnActualResult(knownFirst: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("late-result-order-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        let definition = ModelStepToolDefinition(name: "files_write", toolId: "files.write", parameters: .object(["type": .string("object")]))
        let frame = ModelStepRequest(runId: "run", userTurnId: "turn", stepId: "step", attemptId: "attempt",
            model: "script:model", projectionRevision: "", cacheScope: session.id, messages: [], tools: [definition])
        let call = AgentLoopCall(sourceOrder: 0, call: .init(id: "call", name: definition.name, rawArguments: "{}"))
        try await journal.appendResponse(.init(toolCalls: [call.call], stopReason: .toolCalls), request: frame)
        try await journal.appendRequested([call], request: frame)
        try await journal.appendStarted(call, request: frame)
        let known = ToolInvocationResult(tool: "files.write", ok: true, data: .string("actual settled result"))
        let unknown = ToolInvocationResult(tool: "files.write", ok: false,
            error: .init(code: "tool_execution_interrupted", message: "Unknown at the deadline", retryable: false))
        for value in knownFirst ? [known, unknown] : [unknown, known] {
            try await journal.appendResult(value, call: call, request: frame)
        }
        let fresh = AgentSessionFileStore(agentsRootURL: root)
        let detail = try fresh.loadSession(agentID: "agent", sessionID: session.id)
        #expect(SessionToolRecovery.unknownEffectCallIDs(in: detail.events).isEmpty)
        let projection = try SessionProjection.load(store: fresh, agentID: "agent", sessionID: session.id)
        let messages = try projection.modelMessages()
        #expect(messages.last?.toolOutput?.content.contains("actual settled result") == true)
        #expect(detail.events.last(where: { $0.type == .toolResult })?.toolResult?.ok == true)
    }
}
