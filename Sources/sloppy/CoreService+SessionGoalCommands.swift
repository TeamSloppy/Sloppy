import Foundation
import Protocols
import SloppyRuntime

/// Explicit slash syntax is handled before model inference on every graphical chat surface.
extension CoreService {
    func handleSessionGoalCommand(
        agentID: String, sessionID: String, request: AgentSessionPostMessageRequest
    ) async throws -> (response: AgentSessionMessageResponse?, goalID: String?) {
        let text = request.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        guard parts.first?.lowercased() == "/goal" else { return (nil, nil) }
        guard !request.spawnSubSession else { throw AgentSessionError.invalidPayload }
        let detail = try getAgentSession(agentID: agentID, sessionID: sessionID)
        if detail.summary.kind == .longChat {
            guard try getLongChat(agentID: agentID, sessionID: sessionID).userId == request.userId,
                  !request.spawnSubSession else { throw AgentSessionError.invalidPayload }
        }
        if let id = request.clientMessageId {
            guard UUID(uuidString: id) != nil else { throw AgentSessionError.invalidPayload }
            if let existing = detail.events.first(where: { $0.message?.id == id })?.message {
                guard existing.userId == request.userId,
                      existing.segments.compactMap(\.text).joined() == request.content else { throw AgentSessionError.invalidPayload }
                return (.init(summary: detail.summary, appendedEvents: [], routeDecision: nil), nil)
            }
        }
        _ = try await getAgentSessionGoal(agentID: agentID, sessionID: sessionID)
        let tail = parts.count > 1 ? String(parts[1]) : ""
        let command = SloppyTUIGoalCommand.parse(tail.split(whereSeparator: { $0.isWhitespace }).map(String.init))
        var goal: AgentSessionGoalRecord?
        let reply: String
        switch command {
        case .start:
            goal = await sessionGoalController.start(agentID: agentID, sessionID: sessionID, objective: tail, requestID: request.clientMessageId)
            try persistSessionGoal(goal, sessionID: sessionID)
            return (nil, goal?.id)
        case .status:
            goal = await sessionGoalController.goal(agentID: agentID, sessionID: sessionID)
            reply = goal.map { "Goal: \($0.status.rawValue)\n\($0.objective)\nAttempts: \($0.attemptCount)/\($0.maxAttempts)" }
                ?? "No active goal. Use `/goal <objective>` to start one."
        case .pause:
            goal = await sessionGoalController.pause(agentID: agentID, sessionID: sessionID)
            reply = goal.map { "Goal: \($0.status.rawValue)\n\($0.objective)" } ?? "No goal to pause."
        case .resume:
            let previous = await sessionGoalController.goal(agentID: agentID, sessionID: sessionID)
            goal = await sessionGoalController.resume(agentID: agentID, sessionID: sessionID)
            if goal?.status == .active, previous?.status != .active {
                try persistSessionGoal(goal, sessionID: sessionID)
                return (nil, goal?.id)
            }
            reply = goal.map { "Goal: \($0.status.rawValue)\n\($0.objective)" } ?? "No goal to resume."
        case .clear:
            goal = await sessionGoalController.clear(agentID: agentID, sessionID: sessionID)
            reply = goal == nil ? "No goal to clear." : "Goal cleared."
        case .task, .failure:
            reply = "Usage: `/goal <objective>` or `/goal [status|pause|resume|clear]`. Use `/task` to create a project task."
        }
        if case .clear = command { try persistSessionGoal(nil, sessionID: sessionID) }
        else if goal != nil { try persistSessionGoal(goal, sessionID: sessionID) }
        let id = request.clientMessageId ?? UUID().uuidString
        let attachments = try sessionStore.persistAttachments(agentID: agentID, sessionID: sessionID, uploads: request.attachments)
        let events: [AgentSessionEvent] = [
            .init(agentId: agentID, sessionId: sessionID, type: .message,
                message: .init(id: id, role: .user,
                    segments: [.init(kind: .text, text: request.content)] + attachments.map { .init(kind: .attachment, attachment: $0) },
                    userId: request.userId, sessionReferences: SessionReferenceContext.references(for: request))),
            .init(agentId: agentID, sessionId: sessionID, type: .message,
                message: .init(id: "goal-command-response-" + id, role: .assistant, segments: [.init(kind: .text, text: reply)])),
        ]
        return (try await appendAgentSessionEvents(agentID: agentID, sessionID: sessionID, request: .init(events: events)), nil)
    }

    func persistSessionGoal(_ goal: AgentSessionGoalRecord?, sessionID: String) throws {
        try longChats().transaction { state in
            if state.sessionGoals == nil { state.sessionGoals = [:] }
            state.sessionGoals?[sessionID] = goal
        }
    }

    func sessionGoalContext(agentID: String, sessionID: String) async -> String {
        guard let goal = try? await getAgentSessionGoal(agentID: agentID, sessionID: sessionID), goal.status == .active
        else { return "" }
        return "\n" + SloppyTUIGoalPromptFormatter.initialPrompt(objective: goal.objective)
    }
}
