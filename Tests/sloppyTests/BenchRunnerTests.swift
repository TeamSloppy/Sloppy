import Foundation
import Testing
import Protocols
@testable import sloppy

private func makeSuite(tasks: [(id: String, fixed: Bool)]) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("bench-suite-\(UUID().uuidString.prefix(8))", isDirectory: true)
    for task in tasks {
        let dir = root.appendingPathComponent(task.id, isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("repo"), withIntermediateDirectories: true)
        try "{\"title\":\"\(task.id)\",\"tags\":[\"unit\"],\"timeoutSeconds\":5}".write(
            to: dir.appendingPathComponent("task.json"), atomically: true, encoding: .utf8)
        try "Write the word done into result.txt".write(
            to: dir.appendingPathComponent("prompt.md"), atomically: true, encoding: .utf8)
        try "grep -q done result.txt".write(
            to: dir.appendingPathComponent("check.sh"), atomically: true, encoding: .utf8)
        try "pending".write(to: dir.appendingPathComponent("repo/result.txt"), atomically: true, encoding: .utf8)
    }
    return root
}

private func toolEvents(failingCode: String? = nil) -> [AgentSessionEvent] {
    var events = [
        AgentSessionEvent(agentId: "a", sessionId: "s", type: .toolCall,
                          toolCall: AgentToolCallEvent(tool: "files.edit", arguments: [:])),
    ]
    if let failingCode {
        events.append(AgentSessionEvent(
            agentId: "a", sessionId: "s", type: .toolResult,
            toolResult: AgentToolResultEvent(
                tool: "files.edit", ok: false,
                error: ToolErrorPayload(code: failingCode, message: "x", retryable: true))))
    }
    events.append(AgentSessionEvent(
        agentId: "a", sessionId: "s", type: .runStatus,
        runStatus: AgentRunStatusEvent(
            stage: .done, label: "done", tokenUsage: TokenUsage(prompt: 100, completion: 20),
            selectedModel: "fake-model", executionOutcome: ExecutionOutcome(state: .completed))))
    return events
}

private struct FakeDriver: BenchAgentDriver {
    var solveTaskIDs: Set<String>
    var hang = false
    func run(prompt: String, workspace: URL, model: String?, mode: AgentChatMode) async throws -> [AgentSessionEvent] {
        if hang { try await Task.sleep(nanoseconds: 60_000_000_000) }
        if solveTaskIDs.contains(workspace.lastPathComponent) {
            try "done".write(to: workspace.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
        }
        return toolEvents(failingCode: "ambiguous_match")
    }
}

@Test
func benchRunnerScoresByCheckScriptAndCollectsTypedMetrics() async throws {
    let suite = try makeSuite(tasks: [("solved", true), ("unsolved", false)])
    defer { try? FileManager.default.removeItem(at: suite) }
    let tasks = try BenchTaskLoader.loadSuite(at: suite)
    let runner = BenchRunner(
        driver: FakeDriver(solveTaskIDs: ["solved"]),
        configuration: BenchRunConfiguration(model: "fake-model", concurrency: 2)
    )

    let results = await runner.run(tasks: tasks)

    #expect(results.map(\.taskId) == ["solved", "unsolved"])
    #expect(results[0].status == .passed)
    #expect(results[1].status == .failed)
    #expect(results[0].metrics.toolCalls == 1)
    #expect(results[0].metrics.errorCodes["ambiguous_match"] == 1)
    #expect(results[0].metrics.mutationConflicts == 1)
    #expect(results[0].metrics.totalTokens == 120)
    #expect(results[0].metrics.turnOutcome == "completed")
    #expect(results[0].diff?.contains("+done") == true)
}

@Test
func benchRunnerReportsTimeoutWithoutCountingItAsPass() async throws {
    let suite = try makeSuite(tasks: [("slow", false)])
    defer { try? FileManager.default.removeItem(at: suite) }
    let tasks = try BenchTaskLoader.loadSuite(at: suite)
    let runner = BenchRunner(
        driver: FakeDriver(solveTaskIDs: [], hang: true),
        configuration: BenchRunConfiguration()
    )
    var shortened = tasks
    shortened[0].spec.timeoutSeconds = 1

    let results = await runner.run(tasks: shortened)

    #expect(results[0].status == .timeout)
    #expect(!results[0].passed)
}

@Test
func benchRunnerRepeatsAttemptsAndLeavesSourceRepoUntouched() async throws {
    let suite = try makeSuite(tasks: [("solved", true)])
    defer { try? FileManager.default.removeItem(at: suite) }
    let tasks = try BenchTaskLoader.loadSuite(at: suite)
    let runner = BenchRunner(
        driver: FakeDriver(solveTaskIDs: ["solved"]),
        configuration: BenchRunConfiguration(attempts: 3, concurrency: 3)
    )

    let results = await runner.run(tasks: tasks)

    #expect(results.map(\.attempt) == [1, 2, 3])
    #expect(results.allSatisfy { $0.passed })
    let original = try String(contentsOf: tasks[0].repoDirectory.appendingPathComponent("result.txt"), encoding: .utf8)
    #expect(original == "pending")
}

@Test
func benchReportSummarizesPassRateAndRoundTripsThroughJSON() async throws {
    let suite = try makeSuite(tasks: [("solved", true), ("unsolved", false)])
    defer { try? FileManager.default.removeItem(at: suite) }
    let runner = BenchRunner(
        driver: FakeDriver(solveTaskIDs: ["solved"]),
        configuration: BenchRunConfiguration(model: "fake-model")
    )
    let results = await runner.run(tasks: try BenchTaskLoader.loadSuite(at: suite))
    let report = BenchReport(generatedAt: Date(timeIntervalSince1970: 0), suite: "unit", results: results)

    let summary = try #require(report.summaries.first)
    #expect(summary.model == "fake-model")
    #expect(summary.runs == 2)
    #expect(summary.passed == 1)
    #expect(summary.passRate == 0.5)

    let file = FileManager.default.temporaryDirectory.appendingPathComponent("bench-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: file) }
    try report.jsonData().write(to: file)
    #expect(try BenchReport.load(from: file) == report)
    #expect(report.renderComparison(against: report).contains("fake-model/solved: 100% -> 100%"))
}

@Test
func benchTaskLoaderRejectsIncompleteTasksAndFiltersByTag() throws {
    let suite = try makeSuite(tasks: [("ok", true)])
    defer { try? FileManager.default.removeItem(at: suite) }
    #expect(try BenchTaskLoader.loadSuite(at: suite, filter: ["unit"]).count == 1)
    #expect(try BenchTaskLoader.loadSuite(at: suite, filter: ["other"]).isEmpty)

    try FileManager.default.removeItem(at: suite.appendingPathComponent("ok/check.sh"))
    #expect(throws: BenchTaskError.self) { try BenchTaskLoader.loadSuite(at: suite) }
    #expect(throws: BenchTaskError.self) { try BenchTaskLoader.loadSuite(at: suite.appendingPathComponent("missing")) }
}

@Test
func shippedSmokeSuiteLoadsAndEveryBaselineFailsItsCheck() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("bench/suites/smoke")
    let tasks = try BenchTaskLoader.loadSuite(at: root)
    #expect(tasks.count >= 5)
    for task in tasks {
        let result = BenchRunner.runCheck(task: task, workspace: task.repoDirectory)
        #expect(result?.exitCode != 0, "baseline of \(task.id) must fail its check")
    }
}

private struct FailedTurnDriver: BenchAgentDriver {
    func run(prompt: String, workspace: URL, model: String?, mode: AgentChatMode) async throws -> [AgentSessionEvent] {
        [AgentSessionEvent(
            agentId: "a", sessionId: "s", type: .runStatus,
            runStatus: AgentRunStatusEvent(
                stage: .interrupted, label: "failed",
                executionOutcome: ExecutionOutcome(state: .failed, category: .provider, code: "protectedContextExceedsBudget")))]
    }
}

@Test
func benchRunnerKeepsProviderFailuresApartFromTaskFailures() async throws {
    let suite = try makeSuite(tasks: [("t", false)])
    defer { try? FileManager.default.removeItem(at: suite) }
    let runner = BenchRunner(driver: FailedTurnDriver(), configuration: BenchRunConfiguration())

    let results = await runner.run(tasks: try BenchTaskLoader.loadSuite(at: suite))

    #expect(results[0].status == .error)
    #expect(results[0].metrics.turnFailureCode == "protectedContextExceedsBudget")
    #expect(results[0].error == "turn failed: protectedContextExceedsBudget")
}

@Test
func benchMetricsCountRepeatedUsageReportsOnce() {
    func status(_ usage: TokenUsage?) -> AgentSessionEvent {
        AgentSessionEvent(agentId: "a", sessionId: "s", type: .runStatus,
                          runStatus: AgentRunStatusEvent(stage: .responding, label: "r", tokenUsage: usage))
    }
    let first = TokenUsage(prompt: 100, completion: 10)
    let second = TokenUsage(prompt: 50, completion: 5)

    let metrics = BenchMetrics.derive(from: [status(first), status(nil), status(second), status(second)])

    #expect(metrics.promptTokens == 150)
    #expect(metrics.completionTokens == 15)
}

@Test
func benchMetricsDecodeReportsWrittenBeforeNewMetricsExisted() throws {
    let legacy = #"{"toolCalls":4,"toolErrors":1,"errorCodes":{"x":1},"mutationConflicts":0,"promptTokens":1000,"completionTokens":50,"reasoningTokens":0,"models":["m"]}"#

    let metrics = try JSONDecoder().decode(BenchMetrics.self, from: Data(legacy.utf8))

    #expect(metrics.toolCalls == 4)
    #expect(metrics.cachedInputTokens == 0)
    #expect(metrics.promptTokensPerStep == 200)
}

@Test
func benchReportSummarizesCachedInputShare() {
    func result(prompt: Int, cached: Int) -> BenchRunResult {
        var metrics = BenchMetrics()
        metrics.promptTokens = prompt
        metrics.cachedInputTokens = cached
        return BenchRunResult(
            taskId: "t", tags: [], model: "m", attempt: 1, status: .passed, checkExitCode: 0, checkOutputTail: nil,
            agentSeconds: 1, totalSeconds: 1, metrics: metrics, diff: nil, error: nil)
    }
    let report = BenchReport(generatedAt: Date(timeIntervalSince1970: 0), suite: "s",
                             results: [result(prompt: 1000, cached: 900), result(prompt: 1000, cached: 100)])

    #expect(report.summaries.first?.cachedInputFraction == 0.5)
    #expect(report.renderTable().contains("50% cached"))
}
