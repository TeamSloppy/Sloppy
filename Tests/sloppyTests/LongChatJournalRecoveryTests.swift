import Foundation
import Protocols
import Testing

@testable import sloppy

@Suite("Long chat journal recovery")
struct LongChatJournalRecoveryTests {
    private func journal(status: LongChatTaskStatus = .completed, executionStopped: Bool? = nil) throws -> AgentSessionDetail {
        let summary = AgentSessionSummary(id: "session-recovery", agentId: "agent", title: "History", kind: .longChat, projectId: "project")
        let task = LongChatTask(
            id: "task", key: "work", title: "Work", objective: "Verify work", projectId: "project",
            resourceKeys: ["project:project"], dependsOn: [], attempts: [.init(number: 1)])
        let assignment = LongChatAssignment(
            id: "assignment", sourceMessageId: "source", requestKey: "request", title: "Assignment",
            acceptanceCriteria: "Verified", tasks: [task], createdAt: Date())
        var finished = task
        finished.attempts[0].status = status
        finished.attempts[0].executionStopped = executionStopped
        finished.attempts[0].summary = "Preserved result"
        finished.attempts[0].artifacts = ["build.log"]
        let data = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(assignment))
        return .init(summary: summary, events: [
            .init(agentId: "agent", sessionId: summary.id, type: .message,
                  message: .init(role: .user, segments: [], userId: "owner")),
            // Accepted task events can precede the tool result containing assignment metadata.
            .init(agentId: "agent", sessionId: summary.id, type: .longChatTask,
                  longChatTask: .init(assignmentId: assignment.id, task: task, reason: "accepted")),
            .init(agentId: "agent", sessionId: summary.id, type: .toolResult,
                  toolResult: .init(tool: "long_chat.delegate", ok: true, data: data)),
            .init(agentId: "agent", sessionId: summary.id, type: .longChatTask,
                  longChatTask: .init(assignmentId: assignment.id, task: finished, reason: "finished")),
        ])
    }

    @Test func restoresLatestResultsAndOwnershipDurablyWithoutReplacingExistingState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LongChatFileStore(root: root)
        try store.transaction { $0.conversations.append(.init(agentId: "other", userId: "other", sessionId: "unrelated", assignments: [])) }
        let detail = try journal()
        let recovered = try store.recoverConversation(from: detail)
        #expect(recovered.userId == "owner")
        #expect(recovered.projectId == "project")
        #expect(recovered.assignments.first?.sourceMessageId == "source")
        #expect(recovered.assignments.first?.tasks.first?.status == .completed)
        #expect(recovered.assignments.first?.tasks.first?.attempts.last?.artifacts == ["build.log"])
        #expect(try LongChatFileStore(root: root).conversation(sessionId: detail.summary.id) == recovered)
        var stale = detail
        stale.events = []
        #expect(try store.recoverConversation(from: stale) == recovered)
        #expect(store.state.conversations.count == 2)
    }

    @Test(arguments: [LongChatTaskStatus.running, .queued, .waitingInput])
    func refusesToRecreateExecutableWork(status: LongChatTaskStatus) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LongChatFileStore(root: root)
        #expect(throws: LongChatFileStore.StoreError.conflict) {
            try store.recoverConversation(from: journal(status: status))
        }
        #expect(store.state.conversations.isEmpty)
    }

    @Test func refusesIncompleteEvidenceAndUnstoppedExecutions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LongChatFileStore(root: root)
        var detail = try journal()
        detail.events.removeAll { $0.toolResult != nil }
        #expect(throws: LongChatFileStore.StoreError.invalidPayload) { try store.recoverConversation(from: detail) }
        detail = try journal()
        detail.events.removeAll { $0.message != nil }
        #expect(throws: LongChatFileStore.StoreError.notFound) { try store.recoverConversation(from: detail) }
        #expect(throws: LongChatFileStore.StoreError.conflict) {
            try store.recoverConversation(from: journal(status: .failed, executionStopped: false))
        }
        #expect(store.state.conversations.isEmpty)
    }

    @Test func messageEndpointRecoversIndexAndStillRejectsAnotherOwner() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        defer { Task { await service.stop() } }
        let session = try await service.seedOrphanedLongChat()
        let router = CoreRouter(service: service)
        let path = "/v1/agents/agent/sessions/\(session)/messages"
        let body = try JSONEncoder().encode(AgentSessionPostMessageRequest(userId: "spoofed", content: "Continue", clientMessageId: UUID().uuidString))
        let rejected = await router.handle(method: "POST", path: path, body: body)
        #expect(rejected.status == 400) // No identity auth: the router supplies "local", not "owner".
        let conversation = try await service.getLongChat(agentID: "agent", sessionID: session)
        #expect(conversation.userId == "owner")
        let id = UUID().uuidString
        let request = AgentSessionPostMessageRequest(userId: "owner", content: "Continue", clientMessageId: id)
        let receipt = try await service.postAgentSessionMessage(agentID: "agent", sessionID: session, request: request)
        #expect(receipt.appendedEvents.first?.message?.id == id)
        let duplicate = try await service.postAgentSessionMessage(agentID: "agent", sessionID: session, request: request)
        #expect(duplicate.appendedEvents.isEmpty)
    }
}

extension CoreService {
    fileprivate func seedOrphanedLongChat() throws -> String {
        _ = try agentCatalogStore.createAgent(.init(id: "agent", displayName: "Agent", role: "Testing"), availableModels: [])
        let session = try sessionStore.createSession(agentID: "agent", request: .init(kind: .longChat))
        _ = try sessionStore.appendEvents(agentID: "agent", sessionID: session.id, events: [
            .init(agentId: "agent", sessionId: session.id, type: .message,
                  message: .init(role: .user, segments: [.init(kind: .text, text: "History")], userId: "owner"))
        ])
        // Exercise durable receipts without starting a model or tools.
        longChatIsStopping = true
        return session.id
    }
}
