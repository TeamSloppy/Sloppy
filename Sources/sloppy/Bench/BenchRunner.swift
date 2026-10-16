import Foundation
import Protocols

/// Runs one agent turn against a prepared workspace and returns the session events it produced.
protocol BenchAgentDriver: Sendable {
    func run(prompt: String, workspace: URL, model: String?, mode: AgentChatMode) async throws -> [AgentSessionEvent]
}

enum BenchStatus: String, Codable, Sendable {
    /// `check.sh` exited 0.
    case passed
    /// The agent finished but `check.sh` failed.
    case failed
    /// The agent run exceeded the task timeout.
    case timeout
    /// The driver or sandbox failed before a verdict was possible.
    case error
}

struct BenchRunResult: Codable, Sendable, Equatable {
    var taskId: String
    var tags: [String]
    var model: String
    var attempt: Int
    var status: BenchStatus
    var checkExitCode: Int32?
    var checkOutputTail: String?
    var agentSeconds: Double
    var totalSeconds: Double
    var metrics: BenchMetrics
    var diff: String?
    var error: String?

    var passed: Bool { status == .passed }
}

struct BenchRunConfiguration: Sendable {
    var model: String?
    var mode: AgentChatMode = .auto
    var attempts: Int = 1
    var concurrency: Int = 2
    var keepSandboxes: Bool = false
    var includeDiff: Bool = true
}

struct BenchRunner: Sendable {
    let driver: any BenchAgentDriver
    let configuration: BenchRunConfiguration
    var onResult: (@Sendable (BenchRunResult) -> Void)?

    init(
        driver: any BenchAgentDriver,
        configuration: BenchRunConfiguration,
        onResult: (@Sendable (BenchRunResult) -> Void)? = nil
    ) {
        self.driver = driver
        self.configuration = configuration
        self.onResult = onResult
    }

    /// Runs every task `attempts` times with bounded parallelism. Results are sorted by task id and attempt.
    func run(tasks: [BenchTask]) async -> [BenchRunResult] {
        let jobs = tasks.flatMap { task in (1...max(1, configuration.attempts)).map { (task, $0) } }
        let limit = max(1, configuration.concurrency)
        var results: [BenchRunResult] = []
        await withTaskGroup(of: BenchRunResult.self) { group in
            var iterator = jobs.makeIterator()
            var running = 0
            while running < limit, let (task, attempt) = iterator.next() {
                group.addTask { await self.runOne(task: task, attempt: attempt) }
                running += 1
            }
            while let result = await group.next() {
                results.append(result)
                onResult?(result)
                if let (task, attempt) = iterator.next() {
                    group.addTask { await self.runOne(task: task, attempt: attempt) }
                }
            }
        }
        return results.sorted { ($0.taskId, $0.attempt) < ($1.taskId, $1.attempt) }
    }

    func runOne(task: BenchTask, attempt: Int) async -> BenchRunResult {
        let started = Date()
        let modelLabel = configuration.model ?? "default"
        func result(
            _ status: BenchStatus,
            agentSeconds: Double = 0,
            metrics: BenchMetrics = BenchMetrics(),
            checkExit: Int32? = nil,
            checkTail: String? = nil,
            diff: String? = nil,
            error: String? = nil
        ) -> BenchRunResult {
            BenchRunResult(
                taskId: task.id, tags: task.spec.tags, model: modelLabel, attempt: attempt, status: status,
                checkExitCode: checkExit, checkOutputTail: checkTail, agentSeconds: agentSeconds,
                totalSeconds: Date().timeIntervalSince(started), metrics: metrics, diff: diff, error: error
            )
        }

        let sandbox: BenchSandbox
        do {
            sandbox = try BenchSandbox.create(for: task)
        } catch {
            return result(.error, error: "sandbox: \(error.localizedDescription)")
        }
        defer { if !configuration.keepSandboxes { sandbox.destroy() } }

        let agentStarted = Date()
        var events: [AgentSessionEvent] = []
        var agentStatus: BenchStatus?
        var agentError: String?
        do {
            events = try await Self.withTimeout(seconds: TimeInterval(task.spec.timeoutSeconds)) {
                try await driver.run(
                    prompt: task.prompt, workspace: sandbox.workspace,
                    model: configuration.model, mode: configuration.mode
                )
            }
        } catch is BenchTimeoutError {
            agentStatus = .timeout
        } catch {
            agentStatus = .error
            agentError = "agent: \(error.localizedDescription)"
        }
        let agentSeconds = Date().timeIntervalSince(agentStarted)
        let metrics = BenchMetrics.derive(from: events)

        // The check always runs: a timed-out agent may still have produced a correct workspace.
        let check = Self.runCheck(task: task, workspace: sandbox.workspace)
        let diff = configuration.includeDiff ? sandbox.diff() : nil
        let checkPassed = check.map { $0.exitCode == 0 && !$0.timedOut } ?? false
        let status: BenchStatus
        if checkPassed {
            status = .passed
        } else if let agentStatus {
            status = agentStatus
        } else if metrics.turnOutcome == ExecutionState.failed.rawValue {
            // A provider/runtime failure says nothing about harness quality; keep it apart from real task failures.
            status = .error
        } else {
            status = .failed
        }
        return result(
            status, agentSeconds: agentSeconds, metrics: metrics,
            checkExit: check?.exitCode, checkTail: check.map { String($0.output.suffix(2000)) },
            diff: diff,
            error: agentError
                ?? (check == nil ? "check.sh could not be started" : nil)
                ?? (status == .error ? "turn failed: \(metrics.turnFailureCode ?? "unknown")" : nil)
        )
    }

    static func runCheck(task: BenchTask, workspace: URL) -> BenchProcessResult? {
        try? BenchProcess.run(
            ["bash", task.checkScript.path],
            in: workspace,
            timeout: TimeInterval(task.spec.checkTimeoutSeconds),
            environment: ["BENCH_WORKSPACE": workspace.path]
        )
    }

    struct BenchTimeoutError: Error {}

    static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                throw BenchTimeoutError()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw BenchTimeoutError() }
            return first
        }
    }
}
