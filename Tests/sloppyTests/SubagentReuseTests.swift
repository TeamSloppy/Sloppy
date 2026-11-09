import Foundation
import Protocols
import SloppyRuntime
import Testing

@testable import sloppy

@Suite("Subagent reuse")
struct SubagentReuseTests {
    private func store() throws -> (LongChatFileStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reuse-\(UUID().uuidString)")
        let store = try LongChatFileStore(root: root)
        try store.transaction {
            $0.conversations.append(.init(agentId: "agent", userId: "user", sessionId: "parent", assignments: []))
            $0.workerContexts = ["reviewer": .init(
                agentId: "agent", parentSessionId: "parent", workingDirectory: "/tmp", extraRoots: [],
                toolIDs: ["files.read", "agent_delegate.finish"], resourceKeys: [], readOnly: true)]
        }
        return (store, root)
    }

    private func request(_ key: String, dependsOn: [String] = []) -> LongChatTaskRequest {
        .init(key: key, title: key, objective: key, dependsOn: dependsOn, readOnly: true, reuseSessionId: "reviewer")
    }

    private func delegate(_ store: LongChatFileStore, _ tasks: [LongChatTaskRequest], key: String = "request") throws -> LongChatAssignment {
        try store.delegate(sessionId: "parent", sourceMessageId: key, request: .init(
            requestKey: key, title: "Review", acceptanceCriteria: "Verify fixes", tasks: tasks))
    }

    @Test func serializesReadOnlyIterationsAndPreservesResultsAfterReload() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try delegate(store, [request("first")])
        let second = try delegate(store, [request("second")], key: "follow-up")
        #expect(first.tasks[0].id != second.tasks[0].id)
        #expect(try store.runnableTasks(sessionId: "parent").map(\.task.id) == [first.tasks[0].id])
        try store.updateTask(sessionId: "parent", taskId: first.tasks[0].id) {
            $0.attempts[0].status = .running
            $0.attempts[0].sessionId = "reviewer"
        }
        #expect(try store.runnableTasks(sessionId: "parent").isEmpty)
        try store.updateTask(sessionId: "parent", taskId: first.tasks[0].id) {
            $0.attempts[0].status = .completed
            $0.attempts[0].summary = "Original findings"
        }
        let reopened = try LongChatFileStore(root: root)
        #expect(try reopened.runnableTasks(sessionId: "parent").map(\.task.id) == [second.tasks[0].id])
        #expect(try reopened.conversation(sessionId: "parent").assignments[0].tasks[0].attempts[0].summary == "Original findings")
        #expect(reopened.state.workerContexts?["reviewer"]?.toolIDs == ["files.read", "agent_delegate.finish"])
        #expect(try reopened.runnableTasks(sessionId: "parent", busySessionIDs: ["reviewer"]).isEmpty)
    }

    @Test func dependencyBlockedHeadCannotBeOvertakenByLaterIteration() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try delegate(store, [
            .init(key: "implementation", title: "Implementation", objective: "Fix"),
            request("first", dependsOn: ["implementation"]), request("second"),
        ])
        #expect(try store.runnableTasks(sessionId: "parent").map(\.task.key) == ["implementation"])
    }

    @Test func rejectsDependenciesThatContradictSameSessionQueueOrder() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: LongChatFileStore.StoreError.self) {
            try delegate(store, [request("first", dependsOn: ["second"]), request("second")])
        }
    }

    @Test func rejectsMissingForeignAndWiderScopesAtomically() throws {
        let (store, root) = try store()
        defer { try? FileManager.default.removeItem(at: root) }
        var foreign = request("foreign")
        foreign.reuseSessionId = "missing"
        var wider = request("wider")
        wider.readOnly = false
        var resources = request("resources")
        resources.resourceKeys = ["ticket:new"]
        for task in [foreign, wider, resources] {
            #expect(throws: LongChatFileStore.StoreError.self) { try delegate(store, [task]) }
        }
        try store.transaction { $0.workerContexts?["reviewer"]?.parentSessionId = "another-chat" }
        #expect(throws: LongChatFileStore.StoreError.self) { try delegate(store, [request("other-chat")]) }
        #expect(try store.conversation(sessionId: "parent").assignments.isEmpty)
    }

    @Test func legacyWireModelsDecodeAndReuseRoundTrips() throws {
        let legacy = Data(#"{"key":"r","title":"Review","objective":"Inspect","resourceKeys":[],"dependsOn":[]}"#.utf8)
        #expect(try JSONDecoder().decode(LongChatTaskRequest.self, from: legacy).reuseSessionId == nil)
        let value = request("again")
        #expect(try JSONDecoder().decode(LongChatTaskRequest.self, from: JSONEncoder().encode(value)) == value)
    }

    @Test func explicitOrdinaryContinuationRetainsSessionAndDoesNotPromoteParent() async throws {
        let (service, parent, child) = try await fixture()
        defer { Task { await service.stop() } }
        let result = await service.invokeToolFromRuntime(agentID: "reuse-agent", sessionID: parent.id,
            request: .init(tool: "agents.delegate_task", arguments: [
                "sessionId": .string(child.id), "goal": .string("Verify the fixes"),
                "tasks": .array([]), "toolsets": .array([]),
            ]), recordSessionEvents: false)
        #expect(result.ok)
        #expect(result.data?.asObject?["accepted"]?.asBool == true)
        #expect(try await service.getAgentSession(agentID: "reuse-agent", sessionID: parent.id).summary.kind == .chat)
        let state = try await service.reuseState()
        #expect(state.conversations[0].assignments[0].tasks[0].reuseSessionId == child.id)
        #expect(state.conversations[0].assignments[0].tasks[0].status == .queued)
        #expect(try await service.getAgentSession(agentID: "reuse-agent", sessionID: child.id).events.compactMap(\.message).first?.segments.first?.text == "Previous findings")
        let root = await service.workspaceRootURL
        #expect(try LongChatFileStore(root: root).state.conversations[0].assignments[0].tasks[0].reuseSessionId == child.id)
    }

    @Test func workerRejectsDirectUserMessagesAndAppendedUserEvents() async throws {
        let (service, parent, child) = try await fixture()
        defer { Task { await service.stop() } }
        let workflowWorker = try await service.createAgentSession(
            agentID: parent.agentId, request: .init(title: "Workflow worker", kind: .worker)
        )
        let legacySpawn = try await service.createAgentSession(
            agentID: parent.agentId, request: .init(title: "Legacy worker", parentSessionId: parent.id)
        )
        let fork = try await service.createAgentSession(
            agentID: parent.agentId, request: .init(title: "Fork", parentSessionId: parent.id)
        )
        _ = try await service.appendAgentSessionEvents(agentID: parent.agentId, sessionID: parent.id, request: .init(events: [
            .init(agentId: parent.agentId, sessionId: parent.id, type: .toolResult,
                  toolResult: .init(tool: "sessions.spawn", ok: true, data: .object(["id": .string(legacySpawn.id)])))
        ]))
        let router = CoreRouter(service: service)
        for worker in [child, workflowWorker, legacySpawn] {
            let before = try await service.getAgentSession(agentID: worker.agentId, sessionID: worker.id)
            let path = "/v1/agents/\(worker.agentId)/sessions/\(worker.id)"
            let message = AgentSessionMessage(role: .user, segments: [.init(kind: .text, text: "Do other work")])
            let event = AgentSessionEvent(agentId: worker.agentId, sessionId: worker.id, type: .message, message: message)
            let body = try JSONEncoder().encode(AgentSessionPostMessageRequest(userId: "workflow", content: "Do other work"))
            let response = await router.handle(method: "POST", path: path + "/messages", body: body)
            #expect(response.status == 403)
            #expect(String(decoding: response.body, as: UTF8.self).contains("worker_session_read_only"))
            await #expect(throws: CoreService.AgentSessionError.workerSessionReadOnly) {
                try await service.appendAgentSessionEvents(agentID: worker.agentId, sessionID: worker.id, request: .init(events: [event]))
            }
            let after = try await service.getAgentSession(agentID: worker.agentId, sessionID: worker.id)
            #expect(after.events == before.events)
        }
        let forkDetail = try await service.getAgentSession(agentID: fork.agentId, sessionID: fork.id)
        #expect(!forkDetail.summary.isWorker)
        let message = AgentSessionMessage(role: .user, segments: [.init(kind: .text, text: "Continue this fork")])
        let event = AgentSessionEvent(agentId: fork.agentId, sessionId: fork.id, type: .message, message: message)
        let accepted = try await service.appendAgentSessionEvents(
            agentID: fork.agentId, sessionID: fork.id, request: .init(events: [event])
        )
        #expect(accepted.appendedEvents.contains { $0.message?.id == message.id })
    }

    @Test func missingOrForeignSessionReturnsErrorWithoutReplacement() async throws {
        let (service, parent, child) = try await fixture()
        defer { Task { await service.stop() } }
        let other = try await service.createAgentSession(agentID: "reuse-agent", request: .init(separateChat: true))
        for (sender, target) in [(other.id, child.id), (parent.id, "session-deleted")] {
            let result = await service.invokeToolFromRuntime(agentID: "reuse-agent", sessionID: sender,
                request: .init(tool: "agents.delegate_task", arguments: ["sessionId": .string(target), "goal": .string("Review")]),
                recordSessionEvents: false)
            #expect(!result.ok)
            #expect(result.error?.code == "subagent_reuse_failed")
        }
        #expect(try await service.reuseState().conversations.isEmpty)
    }

    @Test func previousFinishDoesNotCompleteNextIterationAndToolsCannotExpand() async throws {
        let (service, parent, child) = try await fixture()
        defer { Task { await service.stop() } }
        let task = try await service.prepareReuseIteration(parent: parent, child: child)
        await service.reconcileLongChatWorker(agentID: "reuse-agent", childID: child.id)
        let updated = try await service.currentLongChatTask(sessionID: parent.id, taskID: task.id)
        #expect(updated.status == .failed)
        #expect(updated.attempts[0].summary?.contains("without a structured") == true)
        let allowed = try await service.continuedSubagentTools(agentID: "reuse-agent", task: task,
            tools: ["files.read", "files.write", "agent_delegate.finish"])
        #expect(allowed == ["files.read", "agent_delegate.finish"])
        let revoked = try await service.continuedSubagentTools(agentID: "reuse-agent", task: task, tools: ["agent_delegate.finish"])
        #expect(revoked == ["agent_delegate.finish"])
    }

    @Test func queuedIterationExecutesInSameSessionAfterCoreRestart() async throws {
        let (first, parent, child) = try await fixture()
        let config = await first.getConfig()
        _ = try await first.continueSubagentTask(agentID: child.agentId, parentSessionID: parent.id,
            sessionID: child.id, objective: "Review fixes after restart")
        await first.stop()
        let restored = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        defer { Task { await restored.stop() } }
        await restored.waitForStartup()
        for _ in 0..<500 {
            let tasks = try await restored.reuseState().conversations.flatMap(\.assignments).flatMap(\.tasks)
            if let task = tasks.first, task.status.isTerminal {
                #expect(task.attempts[0].sessionId == child.id)
                // The mock returns text without finish; an old completed result must not be reused.
                #expect(task.status == .failed)
                let history = try await restored.getAgentSession(agentID: child.agentId, sessionID: child.id)
                let messages = history.events.compactMap(\.message).flatMap(\.segments).compactMap(\.text)
                #expect(messages.contains("Previous findings"))
                #expect(messages.contains { $0.contains("Review fixes after restart") })
                let sessions = try await restored.listAgentSessions(agentID: child.agentId)
                #expect(sessions.filter { $0.parentSessionId == parent.id }.map(\.id) == [child.id])
                #expect(try await restored.getAgentSession(agentID: parent.agentId, sessionID: parent.id).summary.kind == .chat)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Persisted continuation did not finish")
    }

    @Test func newStructuredFinishBelongsToCurrentIteration() async throws {
        let (service, parent, child) = try await fixture()
        defer { Task { await service.stop() } }
        let task = try await service.prepareReuseIteration(parent: parent, child: child)
        _ = try await service.appendAgentSessionEvents(agentID: child.agentId, sessionID: child.id, request: .init(events: [
            .init(agentId: child.agentId, sessionId: child.id, type: .toolResult,
                  toolResult: .init(tool: "agent_delegate.finish", ok: true, data: .object([
                    "status": .string("completed"), "summary": .string("Fixes verified"),
                    "evidence": .array([.string("New checks passed")]),
                  ]))),
        ]))
        await service.reconcileLongChatWorker(agentID: child.agentId, childID: child.id)
        let current = try await service.currentLongChatTask(sessionID: parent.id, taskID: task.id)
        #expect(current.status == .completed)
        #expect(current.attempts[0].summary == "Fixes verified")
        #expect(current.attempts[0].evidence == ["New checks passed"])
        let history = try await service.getAgentSession(agentID: child.agentId, sessionID: child.id)
        #expect(history.events.compactMap(\.toolResult).count == 2)
        #expect(history.events.compactMap(\.toolResult).first?.data?.asObject?["summary"]?.asString == "Old review")
    }

    private func fixture() async throws -> (CoreService, AgentSessionSummary, AgentSessionSummary) {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        _ = try await service.createAgent(.init(id: "reuse-agent", displayName: "Agent", role: "Test"))
        let parent = try await service.createAgentSession(agentID: "reuse-agent", request: .init(separateChat: true))
        let child = try await service.createAgentSession(agentID: "reuse-agent", request: .init(parentSessionId: parent.id))
        try await service.holdReuseFixture(parent: parent, child: child)
        return (service, parent, child)
    }
}

private extension CoreService {
    func reuseState() throws -> LongChatFileStore.State { try longChats().state }

    func holdReuseFixture(parent: AgentSessionSummary, child: AgentSessionSummary) throws {
        ordinarySubagentRuns.insert(child.id)
        activeSessionMessageRuns.insert(parent.id)
        try rememberSubagentContext(session: child, parentSessionID: parent.id, workingDirectory: "/tmp", extraRoots: [],
            tools: ["files.read", "agent_delegate.finish"], resourceKeys: [], readOnly: true)
        _ = try sessionStore.appendEvents(agentID: child.agentId, sessionID: child.id, events: [
            .init(agentId: child.agentId, sessionId: child.id, type: .message,
                  message: .init(role: .user, segments: [.init(kind: .text, text: "Previous findings")], userId: "local")),
            .init(agentId: child.agentId, sessionId: child.id, type: .toolResult,
                  toolResult: .init(tool: "agent_delegate.finish", ok: true, data: .object([
                    "status": .string("completed"), "summary": .string("Old review"),
                  ]))),
        ])
    }

    func prepareReuseIteration(parent: AgentSessionSummary, child: AgentSessionSummary) throws -> LongChatTask {
        let storage = try longChats()
        try storage.transaction {
            $0.conversations.append(.init(agentId: parent.agentId, userId: "local", sessionId: parent.id, assignments: []))
            $0.workerOnlySessionIds = [parent.id]
        }
        let assignment = try storage.delegate(sessionId: parent.id, sourceMessageId: "source", request: .init(
            requestKey: "next", title: "Repeat review", acceptanceCriteria: "Fixes verified",
            tasks: [.init(key: "review", title: "Review", objective: "Check fixes", readOnly: true, reuseSessionId: child.id)]))
        let offset = try getAgentSession(agentID: child.agentId, sessionID: child.id).events.count
        return try storage.updateTask(sessionId: parent.id, taskId: assignment.tasks[0].id) {
            $0.attempts[0].status = .running
            $0.attempts[0].sessionId = child.id
            $0.attempts[0].eventOffset = offset
            return $0
        }
    }
}
