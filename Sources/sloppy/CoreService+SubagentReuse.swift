import Foundation
import Protocols
import SloppyRuntime

extension CoreService {
    enum SubagentReuseError: Error {
        case unavailable, wrongParent, scopeMismatch
    }

    /// Persist the original execution boundary once; later iterations may only narrow it.
    func rememberSubagentContext(
        session: AgentSessionSummary, parentSessionID: String, workingDirectory: String?, extraRoots: [String],
        tools: Set<String>, resourceKeys: [String], readOnly: Bool, sourceTaskID: String? = nil
    ) throws {
        let storage = try longChats()
        guard storage.state.workerContexts?[session.id] == nil else { return }
        let context = LongChatFileStore.WorkerContext(
            agentId: session.agentId, parentSessionId: parentSessionID, projectId: session.projectId,
            workingDirectory: workingDirectory, extraRoots: extraRoots, toolIDs: tools,
            resourceKeys: resourceKeys, readOnly: readOnly, sourceTaskId: sourceTaskID)
        try storage.transaction {
            if $0.workerContexts == nil { $0.workerContexts = [:] }
            $0.workerContexts?[session.id] = context
        }
    }

    func delegatedSubagentSessionID(agentID: String, parentSessionID: String, taskID: String) throws -> String? {
        try longChats().state.workerContexts?.first {
            $0.value.agentId == agentID && $0.value.parentSessionId == parentSessionID && $0.value.sourceTaskId == taskID
        }?.key
    }

    func reusableSubagent(agentID: String, parentSessionID: String, sessionID: String) throws -> LongChatFileStore.WorkerContext {
        guard let saved = try longChats().state.workerContexts?[sessionID],
              let session = try? getAgentSession(agentID: agentID, sessionID: sessionID).summary
        else { throw SubagentReuseError.unavailable }
        guard saved.agentId == agentID, saved.parentSessionId == parentSessionID,
              session.parentSessionId == parentSessionID else { throw SubagentReuseError.wrongParent }
        _ = try getAgentSession(agentID: agentID, sessionID: parentSessionID)
        return saved
    }

    func validateSubagentReuse(agentID: String, parentSessionID: String, task: LongChatTaskRequest) throws {
        guard let sessionID = task.reuseSessionId else { return }
        let saved = try reusableSubagent(agentID: agentID, parentSessionID: parentSessionID, sessionID: sessionID)
        guard task.projectId == saved.projectId, Set(task.resourceKeys) == Set(saved.resourceKeys),
              !saved.readOnly || (task.readOnly ?? task.resourceKeys.isEmpty) else { throw SubagentReuseError.scopeMismatch }
    }

    func continuedSubagentTools(agentID: String, task: LongChatTask, tools: Set<String>) throws -> Set<String> {
        guard let sessionID = task.reuseSessionId else { return tools }
        guard let saved = try longChats().state.workerContexts?[sessionID], saved.agentId == agentID else {
            throw SubagentReuseError.unavailable
        }
        return tools.intersection(saved.toolIDs)
    }

    /// Ordinary delegation keeps its synchronous creation API; explicit continuations use the durable worker queue.
    func continueSubagentTask(agentID: String, parentSessionID: String, sessionID: String, objective: String) async throws -> JSONValue {
        let saved = try reusableSubagent(agentID: agentID, parentSessionID: parentSessionID, sessionID: sessionID)
        let parent = try getAgentSession(agentID: agentID, sessionID: parentSessionID)
        let storage = try longChats()
        if !storage.state.conversations.contains(where: { $0.sessionId == parentSessionID }) {
            try storage.transaction {
                $0.conversations.append(.init(
                    agentId: agentID, userId: parent.events.compactMap(\.message).last(where: { $0.role == .user && $0.peerOrigin == nil })?.userId ?? "local",
                    sessionId: parentSessionID, assignments: [], projectId: parent.summary.projectId))
                $0.workerOnlySessionIds = ($0.workerOnlySessionIds ?? []) + [parentSessionID]
            }
        }
        let assignment = try storage.delegate(
            sessionId: parentSessionID, sourceMessageId: UUID().uuidString,
            request: .init(requestKey: UUID().uuidString, title: "Continue subagent", acceptanceCriteria: objective,
                           tasks: [.init(key: "continue", title: "Continue subagent", objective: objective,
                                         resourceKeys: saved.resourceKeys, projectId: saved.projectId,
                                         readOnly: saved.readOnly, reuseSessionId: sessionID)]))
        for task in assignment.tasks {
            try await publishLongChatTask(sessionID: parentSessionID, taskID: task.id, reason: "accepted")
        }
        Task { [weak self] in await self?.dispatchLongChatWorkers() }
        return encodeJSONValue(assignment)
    }
}
