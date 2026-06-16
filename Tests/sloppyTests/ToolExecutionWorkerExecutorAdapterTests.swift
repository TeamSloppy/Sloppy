import AgentRuntime
import Protocols
import Testing
@testable import sloppy

@Test
func workerExecutorAdapterPassesSpecToolsToAgentRunner() async throws {
    final class Captured: @unchecked Sendable {
        var toolIDs: [String] = []
    }

    let captured = Captured()
    let adapter = ToolExecutionWorkerExecutorAdapter(
        agentRunner: { _, _, _, _, _, toolIDs in
            captured.toolIDs = toolIDs
            return ToolExecutionWorkerExecutorAdapter.AgentRunnerResult(
                summary: "done",
                payload: [:]
            )
        }
    )
    let spec = WorkerTaskSpec(
        taskId: "task-tools",
        channelId: "channel",
        title: "Tool restricted worker",
        objective: "Use only selected tools",
        agentID: "builder",
        tools: ["files.read", "mcp.github.create_issue"],
        mode: .fireAndForget
    )

    _ = try await adapter.execute(workerId: "worker", spec: spec)

    #expect(captured.toolIDs == ["files.read", "mcp.github.create_issue"])
}
