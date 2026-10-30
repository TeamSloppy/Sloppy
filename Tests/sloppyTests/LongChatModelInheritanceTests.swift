import Foundation
import Protocols
import Testing

@testable import sloppy

@Suite("Long chat model inheritance")
struct LongChatModelInheritanceTests {
    @Test func originatingModelSurvivesRestartAndLaterUserChoices() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("long-chat-model-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LongChatFileStore(root: root)
        try store.transaction {
            $0.turns.append(.init(id: "original", agentId: "agent", sessionId: "parent",
                request: .init(userId: "user", content: "Task", reasoningEffort: .high, selectedModel: "mock:requested"),
                isNotification: false, delivered: true))
        }
        try store.recordResolvedModel("mock:chosen", turnId: "original")
        try store.recordResolvedModel("mock:later-fallback", turnId: "original")
        try store.transaction {
            $0.turns.append(.init(id: "later", agentId: "agent", sessionId: "parent",
                request: .init(userId: "user", content: "New task", selectedModel: "mock:new"),
                isNotification: false, delivered: true))
            $0.turns.append(.init(id: "notification", agentId: "agent", sessionId: "parent",
                request: .init(userId: "user", content: "Worker update", selectedModel: "mock:wrong"),
                isNotification: true, delivered: true))
            $0.turns.append(.init(id: "queued", agentId: "agent", sessionId: "parent",
                request: .init(userId: "user", content: "Not processed yet", selectedModel: "mock:queued"),
                isNotification: false))
        }
        let reopened = try LongChatFileStore(root: root)
        let worker = reopened.inheritingModelSelection(.init(userId: "user", content: "Execute"),
            sessionId: "parent", sourceMessageId: "original")
        #expect(worker.selectedModel == "mock:chosen")
        #expect(worker.reasoningEffort == .high)
        let notification = reopened.inheritingModelSelection(.init(userId: "user", content: "Summarize"), sessionId: "parent")
        #expect(notification.selectedModel == "mock:new")
        let explicit = reopened.inheritingModelSelection(
            .init(userId: "user", content: "Continue", reasoningEffort: .low, selectedModel: "mock:explicit"),
            sessionId: "parent", sourceMessageId: "original")
        #expect(explicit.selectedModel == "mock:explicit")
        #expect(explicit.reasoningEffort == .low)
    }

    @Test func legacyTurnsUseTheirExplicitSelectionAndDefaultChoicesStayEmpty() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("long-chat-legacy-model-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LongChatFileStore(root: root)
        try store.transaction {
            $0.turns.append(.init(id: "original", agentId: "agent", sessionId: "parent",
                request: .init(userId: "user", content: "Task", selectedModel: "mock:chosen"),
                isNotification: false, delivered: true))
            $0.turns.append(.init(id: "default", agentId: "agent", sessionId: "parent",
                request: .init(userId: "user", content: "Use agent settings"), isNotification: false, delivered: true))
        }
        try store.recordResolvedModel("mock:default", turnId: "default")
        let reopened = try LongChatFileStore(root: root)
        let request = AgentSessionPostMessageRequest(userId: "user", content: "Execute")
        #expect(reopened.inheritingModelSelection(request, sessionId: "parent", sourceMessageId: "original").selectedModel == "mock:chosen")
        #expect(reopened.inheritingModelSelection(request, sessionId: "parent").selectedModel == nil)
        #expect(reopened.inheritingModelSelection(request, sessionId: "other").selectedModel == nil)
    }

    @Test func workerDeliveryUsesParentChoiceInsteadOfAgentDefault() async throws {
        let service = try await service()
        defer { Task { await service.stop() } }
        let chat = try await service.openLongChat(agentID: "model-agent", userID: "local")
        let child = try await service.prepareModelInheritanceWorker(parentID: chat.id)
        _ = try await service.postAgentSessionMessage(agentID: "model-agent", sessionID: child,
            request: .init(userId: "local", content: "Execute the assigned task"), longChatWorkerDelivery: true)
        let detail = try await service.getAgentSession(agentID: "model-agent", sessionID: child)
        #expect(detail.events.compactMap(\.runStatus).first?.selectedModel == "mock:chosen")
    }

    @Test func workerNotificationKeepsCoordinatorModel() async throws {
        let service = try await service()
        defer { Task { await service.stop() } }
        let chat = try await service.openLongChat(agentID: "model-agent", userID: "local")
        _ = try await service.prepareModelInheritanceWorker(parentID: chat.id)
        let conversation = try await service.getLongChat(agentID: "model-agent", sessionID: chat.id)
        try await service.publishLongChatTask(sessionID: chat.id, taskID: conversation.assignments[0].tasks[0].id,
            reason: "failed", notify: true)
        for _ in 0..<500 {
            let detail = try await service.getAgentSession(agentID: "model-agent", sessionID: chat.id)
            if let status = detail.events.compactMap(\.runStatus).last, status.stage == .done {
                #expect(status.selectedModel == "mock:chosen")
                #expect(try await service.modelInheritanceNotificationChoice(parentID: chat.id) == "mock:chosen")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Coordinator did not process the worker notification")
    }

    private func service() async throws -> CoreService {
        var config = CoreConfig.test
        config.models = ["mock:default", "mock:chosen"].map {
            .init(title: $0, apiKey: "", apiUrl: "", model: $0)
        }
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        _ = try await service.createAgent(.init(id: "model-agent", displayName: "Model Agent", role: "Testing"))
        let current = try await service.getAgentConfig(agentID: "model-agent")
        _ = try await service.updateAgentConfig(agentID: "model-agent", request: .init(
            role: current.role, selectedModel: "mock:default", documents: current.documents))
        return service
    }
}

private extension CoreService {
    func modelInheritanceNotificationChoice(parentID: String) throws -> String? {
        try longChats().state.turns.last { $0.sessionId == parentID && $0.isNotification }?.request.selectedModel
    }

    func prepareModelInheritanceWorker(parentID: String) throws -> String {
        let storage = try longChats()
        try storage.transaction {
            $0.turns.append(.init(id: "source", agentId: "model-agent", sessionId: parentID,
                request: .init(userId: "local", content: "Task", selectedModel: "mock:chosen"),
                isNotification: false, delivered: true))
        }
        let assignment = try storage.delegate(sessionId: parentID, sourceMessageId: "source", request: .init(
            requestKey: "task", title: "Task", acceptanceCriteria: "Verified",
            tasks: [.init(key: "work", title: "Work", objective: "Do the assigned work")]))
        let child = try sessionStore.createSession(agentID: "model-agent", request: .init(
            title: "Worker", parentSessionId: parentID, kind: .longChatWorker))
        try storage.updateTask(sessionId: parentID, taskId: assignment.tasks[0].id) {
            $0.attempts[0].status = .running
            $0.attempts[0].sessionId = child.id
        }
        return child.id
    }
}
