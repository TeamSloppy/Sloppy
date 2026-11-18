import AgentRuntime
import Protocols
import Testing
@testable import sloppy

@Test
func workerExecutorAdapterPassesSpecToolsToAgentRunner() async throws {
    final class Captured: @unchecked Sendable {
        var toolIDs: [String] = []
        var channelID: String?
    }

    let captured = Captured()
    let adapter = ToolExecutionWorkerExecutorAdapter(
        agentRunner: { _, _, _, _, _, toolIDs, channelID in
            captured.toolIDs = toolIDs
            captured.channelID = channelID
            return ToolExecutionWorkerExecutorAdapter.AgentRunnerResult(
                summary: "done",
                payload: [:]
            )
        }
    )
    let spec = WorkerTaskSpec(
        taskId: "task-tools",
        channelId: sessionChannelID(agentID: "builder", sessionID: "parent"),
        title: "Tool restricted worker",
        objective: "Use only selected tools",
        agentID: "builder",
        tools: ["files.read", "mcp.github.create_issue"],
        mode: .fireAndForget
    )

    _ = try await adapter.execute(workerId: "worker", spec: spec)

    #expect(captured.channelID == spec.channelId)
    #expect(captured.toolIDs == ["files.read", "mcp.github.create_issue"])
}

@Test func workerExecutorFailurePreservesStructuredCompletionEvidence() async throws {
    let finish: JSONValue = .object(["finished": .bool(false), "synthetic": .bool(true), "status": .string("failed")])
    let adapter = ToolExecutionWorkerExecutorAdapter(agentRunner: { _, _, _, _, _, _, _ in
        .init(summary: "No structured completion.", payload: ["delegateFinish": finish],
              executionOutcome: .init(state: .failed))
    })
    let spec = WorkerTaskSpec(taskId: "failed", channelId: "channel", title: "Work",
                              objective: "Inspect", agentID: "builder", tools: [], mode: .fireAndForget)
    do {
        _ = try await adapter.execute(workerId: "worker", spec: spec)
        Issue.record("Expected a structured worker failure")
    } catch let failure as AgentRunnerModelError {
        #expect(failure.workerFailurePayload["delegateFinish"] == finish)
        #expect(failure.workerFailurePayload["executionOutcome"]?.asObject?["state"] == .string("failed"))
    }
}
