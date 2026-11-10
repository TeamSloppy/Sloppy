import AgentRuntime
import Foundation
import Protocols
import Testing
@testable import sloppy

@Suite("Worker approval inheritance")
struct WorkerApprovalInheritanceTests {
    @Test(arguments: [nil, .askForApproval, .approveForMe] as [SessionApprovalMode?])
    func runtimeWorkerInheritsCallingChat(override: SessionApprovalMode?) async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        defer { Task { await service.stop() } }
        let agentID = "worker-inheritance"
        _ = try await service.createAgent(.init(id: agentID, displayName: "Worker", role: "Test"))
        let parent = try await service.createAgentSession(agentID: agentID, request: .init())
        if let override {
            _ = try await service.setSessionApprovalPolicy(agentID: agentID, sessionID: parent.id, policy: .init(mode: override))
        }
        let mode = override ?? .fullAccess
        let taskID = UUID().uuidString
        _ = await service.runtime.createWorker(spec: .init(
            taskId: taskID, channelId: sessionChannelID(agentID: agentID, sessionID: parent.id),
            title: "Child", objective: "Verify the workspace", agentID: agentID,
            tools: ["files.read"], mode: .fireAndForget))
        var child: AgentSessionSummary?
        for _ in 0..<1_000 {
            child = try await service.listAgentSessions(agentID: agentID).first { $0.title == "task-\(taskID)-attempt-1" }
            if child != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let session = try #require(child)
        #expect(session.parentSessionId == parent.id)
        #expect(try await service.getSessionApprovalPolicy(agentID: agentID, sessionID: session.id).mode == mode)
        if mode == .fullAccess {
            let approval = await service.requestToolApprovalIfNeeded(
                agentID: agentID, sessionID: session.id, channelID: nil, topicID: nil,
                request: .init(tool: "runtime.exec"), requireApproval: true, forcePerInvocation: true,
                timeoutSeconds: 0.1)
            #expect(approval == nil)
            #expect(await service.listPendingToolApprovals().isEmpty)
        }
        _ = try await service.setSessionApprovalPolicy(agentID: agentID, sessionID: parent.id, policy: .init(mode: .askForApproval))
        #expect(try await service.getSessionApprovalPolicy(agentID: agentID, sessionID: session.id).mode == .askForApproval)
    }
}
