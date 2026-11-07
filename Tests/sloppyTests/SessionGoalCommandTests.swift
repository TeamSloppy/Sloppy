import Foundation
import Protocols
import Testing
@testable import sloppy

@Suite("Graphical chat goal commands")
struct SessionGoalCommandTests {
    @Test func longChatGoalStartsWithoutLosingOwnerModelOrReferencesAndRetriesDoNotResetIt() async throws {
        let (service, chat) = try await fixture()
        defer { Task { await service.stop() } }
        let reference = AgentSessionReference(agentId: chat.agentId, sessionId: "reference")
        let request = AgentSessionPostMessageRequest(
            userId: "owner", content: "/goal finish the workflow\nwith verification", selectedModel: "test:model",
            clientMessageId: UUID().uuidString, sessionReferences: [reference])
        _ = try await service.postAgentSessionMessage(agentID: chat.agentId, sessionID: chat.id, request: request)
        let goal = try #require(try await service.getAgentSessionGoal(agentID: chat.agentId, sessionID: chat.id))
        #expect(goal.objective == "finish the workflow\nwith verification")
        #expect(goal.status == .active)
        let queued = try #require(try await service.goalTestQueuedRequest(chat.id))
        #expect(queued.userId == "owner")
        #expect(queued.selectedModel == request.selectedModel)
        #expect(queued.sessionReferences == [reference])
        _ = try await service.postAgentSessionMessage(agentID: chat.agentId, sessionID: chat.id, request: request)
        #expect(try await service.getAgentSessionGoal(agentID: chat.agentId, sessionID: chat.id)?.id == goal.id)
    }

    @Test func lifecycleCommandsRunWithoutModelAndStayOutOfCoordinatorInbox() async throws {
        let (service, chat) = try await fixture()
        defer { Task { await service.stop() } }
        for (command, status) in [("start something", AgentSessionGoalStatus.active), ("pause", .paused), ("resume", .active)] {
            _ = try await service.postAgentSessionMessage(agentID: chat.agentId, sessionID: chat.id,
                request: .init(userId: "owner", content: "/goal " + command))
            #expect(try await service.getAgentSessionGoal(agentID: chat.agentId, sessionID: chat.id)?.status == status)
        }
        let count = try await service.goalTestQueuedCount(chat.id)
        let response = try await service.postAgentSessionMessage(agentID: chat.agentId, sessionID: chat.id,
            request: .init(userId: "owner", content: "/goal status"))
        #expect(response.appendedEvents.contains { $0.message?.role == .assistant })
        #expect(try await service.goalTestQueuedCount(chat.id) == count)
        _ = try await service.postAgentSessionMessage(agentID: chat.agentId, sessionID: chat.id,
            request: .init(userId: "owner", content: "/goal clear"))
        #expect(try await service.getAgentSessionGoal(agentID: chat.agentId, sessionID: chat.id) == nil)
        let catalog = try await service.buildAgentChatSlashCommands(agentID: chat.agentId)
        #expect(catalog.commands.contains { $0.name == "goal" && $0.source == "channel" })
    }

    @Test func wrongOwnerCannotStartOrPauseGoal() async throws {
        let (service, chat) = try await fixture()
        defer { Task { await service.stop() } }
        for command in ["work", "pause", "clear"] {
            await #expect(throws: CoreService.AgentSessionError.self) {
                try await service.postAgentSessionMessage(agentID: chat.agentId, sessionID: chat.id,
                    request: .init(userId: "other", content: "/goal " + command))
            }
        }
        #expect(try await service.getAgentSessionGoal(agentID: chat.agentId, sessionID: chat.id) == nil)
    }

    @Test func plainMentionAndInvalidCommandDoNotCreateGoal() async throws {
        let (service, chat) = try await fixture()
        defer { Task { await service.stop() } }
        for content in ["explain /goal work", "/goal", "/goal pause extra"] {
            _ = try await service.postAgentSessionMessage(agentID: chat.agentId, sessionID: chat.id,
                request: .init(userId: "owner", content: content))
        }
        #expect(try await service.getAgentSessionGoal(agentID: chat.agentId, sessionID: chat.id) == nil)
        #expect(try await service.goalTestQueuedCount(chat.id) == 1)
    }

    @Test func goalWaitsForWorkersAndPauseDiscardsQueuedGoalTurns() async throws {
        let (service, chat) = try await fixture()
        defer { Task { await service.stop() } }
        let request = AgentSessionPostMessageRequest(userId: "owner", content: "/goal finish", selectedModel: "test:model")
        _ = try await service.postAgentSessionMessage(agentID: chat.agentId, sessionID: chat.id, request: request)
        let taskID = try await service.addGoalTestTask(chat.id)
        let complete = AgentSessionEvent(agentId: chat.agentId, sessionId: chat.id, type: .toolResult,
            toolResult: .init(tool: "session.complete", ok: true, data: .object([
                "completed": .bool(true), "status": .string("completed"),
            ])))
        await service.scheduleGoalContinuationIfNeeded(agentID: chat.agentId, sessionID: chat.id, request: request,
            response: .init(summary: chat, appendedEvents: [complete], routeDecision: nil))
        #expect(try await service.getAgentSessionGoal(agentID: chat.agentId, sessionID: chat.id)?.status == .active)
        #expect(try await service.goalTestQueuedCount(chat.id) == 1)
        try await service.finishGoalTestTask(chat.id, taskID: taskID)
        await service.scheduleGoalContinuationIfNeeded(agentID: chat.agentId, sessionID: chat.id, request: request,
            response: .init(summary: chat, appendedEvents: [], routeDecision: nil))
        for _ in 0..<100 {
            if try await service.goalTestQueuedCount(chat.id) == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(try await service.goalTestQueuedCount(chat.id) == 2)
        _ = try await service.postAgentSessionMessage(agentID: chat.agentId, sessionID: chat.id,
            request: .init(userId: "owner", content: "/goal pause"))
        await service.releaseGoalTestCoordinator(chat.id)
        for _ in 0..<100 {
            if try await service.goalTestTurnsDelivered(chat.id) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(try await service.goalTestTurnsDelivered(chat.id))
        let history = try await service.getAgentSession(agentID: chat.agentId, sessionID: chat.id)
        #expect(!history.events.contains { $0.runStatus != nil })
    }

    @Test func pausedGoalSurvivesReloadAndClearRemovesPersistedState() async throws {
        let config = CoreConfig.test
        let first = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        _ = try await first.createAgent(.init(id: "goal-agent", displayName: "Goal", role: "Test"))
        await first.holdGoalTestCoordinator()
        let chat = try await first.openLongChat(agentID: "goal-agent", userID: "owner")
        _ = try await first.postAgentSessionMessage(agentID: chat.agentId, sessionID: chat.id,
            request: .init(userId: "owner", content: "/goal finish after reload"))
        _ = try await first.postAgentSessionMessage(agentID: chat.agentId, sessionID: chat.id,
            request: .init(userId: "owner", content: "/goal pause"))
        await first.stop()
        let restored = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        defer { Task { await restored.stop() } }
        await restored.holdGoalTestCoordinator()
        let goal = try await restored.getAgentSessionGoal(agentID: chat.agentId, sessionID: chat.id)
        #expect(goal?.status == .paused)
        #expect(goal?.objective == "finish after reload")
        _ = try await restored.postAgentSessionMessage(agentID: chat.agentId, sessionID: chat.id,
            request: .init(userId: "owner", content: "/goal clear"))
        #expect(try await restored.goalTestPersistedGoal(chat.id) == nil)
    }

    @Test func concurrentRetryKeepsOneGoalGenerationAndTypedAPIPreservesOwner() async throws {
        let (service, chat) = try await fixture()
        defer { Task { await service.stop() } }
        let request = AgentSessionPostMessageRequest(userId: "owner", content: "/goal finish", clientMessageId: UUID().uuidString)
        async let first = service.postAgentSessionMessage(agentID: chat.agentId, sessionID: chat.id, request: request)
        async let second = service.postAgentSessionMessage(agentID: chat.agentId, sessionID: chat.id, request: request)
        _ = try await (first, second)
        let goal = try #require(try await service.getAgentSessionGoal(agentID: chat.agentId, sessionID: chat.id))
        #expect(try await service.goalTestQueuedCount(chat.id) == 1)
        #expect(try await service.goalTestQueuedGeneration(chat.id) == goal.id)
        let next = try await service.startAgentSessionGoal(agentID: chat.agentId, sessionID: chat.id,
            request: .init(objective: "next objective"))
        #expect(next.status == .active)
        #expect(try await service.goalTestQueuedCount(chat.id) == 2)
    }

    private func fixture() async throws -> (CoreService, AgentSessionSummary) {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        _ = try await service.createAgent(.init(id: "goal-agent", displayName: "Goal", role: "Test"))
        await service.holdGoalTestCoordinator()
        let chat = try await service.openLongChat(agentID: "goal-agent", userID: "owner")
        return (service, chat)
    }
}

private extension CoreService {
    func goalTestQueuedGeneration(_ id: String) throws -> String? { try longChats().state.turns.first { $0.sessionId == id }?.goalId }
    func holdGoalTestCoordinator() { longChatIsStopping = true }
    func goalTestPersistedGoal(_ id: String) throws -> AgentSessionGoalRecord? { try longChats().state.sessionGoals?[id] }
    func addGoalTestTask(_ id: String) throws -> String {
        try longChats().delegate(sessionId: id, sourceMessageId: "source", request: .init(
            requestKey: "workers", title: "Work", acceptanceCriteria: "Verified",
            tasks: [.init(key: "work", title: "Work", objective: "Work", readOnly: true)])).tasks[0].id
    }
    func finishGoalTestTask(_ id: String, taskID: String) throws {
        try longChats().updateTask(sessionId: id, taskId: taskID) { $0.attempts[0].status = .completed }
    }
    func releaseGoalTestCoordinator(_ id: String) {
        longChatIsStopping = false
        scheduleLongChatTurns(sessionID: id)
    }
    func goalTestTurnsDelivered(_ id: String) throws -> Bool {
        try longChats().state.turns.filter { $0.sessionId == id }.allSatisfy(\.delivered)
    }
    func goalTestQueuedRequest(_ id: String) throws -> AgentSessionPostMessageRequest? {
        try longChats().state.turns.first { $0.sessionId == id }?.request
    }
    func goalTestQueuedCount(_ id: String) throws -> Int {
        try longChats().state.turns.filter { $0.sessionId == id }.count
    }
}
