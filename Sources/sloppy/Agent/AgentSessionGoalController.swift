import Foundation
import Protocols

actor AgentSessionGoalController {
    private var goals: [String: AgentSessionGoalRecord] = [:]
    private var startRequestIDs: [String: String] = [:]

    func start(
        agentID: String,
        sessionID: String,
        objective: String,
        maxAttempts: Int = 8,
        requestID: String? = nil,
        now: Date = Date()
    ) -> AgentSessionGoalRecord {
        let storageKey = key(agentID: agentID, sessionID: sessionID)
        if let requestID, startRequestIDs[storageKey] == requestID, let existing = goals[storageKey] { return existing }
        startRequestIDs[storageKey] = requestID
        let normalizedMaxAttempts = max(1, maxAttempts)
        let record = AgentSessionGoalRecord(
            agentId: agentID,
            sessionId: sessionID,
            objective: objective.trimmingCharacters(in: .whitespacesAndNewlines),
            status: .active,
            attemptCount: 0,
            maxAttempts: normalizedMaxAttempts,
            createdAt: now,
            updatedAt: now
        )
        goals[key(agentID: agentID, sessionID: sessionID)] = record
        return record
    }

    func restore(_ goal: AgentSessionGoalRecord) {
        let storageKey = key(agentID: goal.agentId, sessionID: goal.sessionId)
        if goals[storageKey] == nil { goals[storageKey] = goal }
    }

    func goal(agentID: String, sessionID: String) -> AgentSessionGoalRecord? {
        goals[key(agentID: agentID, sessionID: sessionID)]
    }

    func pause(agentID: String, sessionID: String, now: Date = Date()) -> AgentSessionGoalRecord? {
        update(agentID: agentID, sessionID: sessionID, now: now) { goal in
            guard !goal.status.isTerminal else { return }
            goal.status = .paused
        }
    }

    func resume(agentID: String, sessionID: String, now: Date = Date()) -> AgentSessionGoalRecord? {
        update(agentID: agentID, sessionID: sessionID, now: now) { goal in
            guard goal.status == .paused || goal.status == .waitingInput else { return }
            goal.status = .active
        }
    }

    func clear(agentID: String, sessionID: String, now: Date = Date()) -> AgentSessionGoalRecord? {
        let storageKey = key(agentID: agentID, sessionID: sessionID)
        guard var goal = goals.removeValue(forKey: storageKey) else {
            return nil
        }
        goal.status = .cleared
        goal.updatedAt = now
        return goal
    }

    func evaluateTurn(
        agentID: String,
        sessionID: String,
        events: [AgentSessionEvent],
        hasPendingWork: Bool = false,
        expectedGoalID: String? = nil,
        now: Date = Date()
    ) -> AgentSessionGoalEvaluation? {
        let storageKey = key(agentID: agentID, sessionID: sessionID)
        guard var goal = goals[storageKey],
              goal.status == .active,
              expectedGoalID == nil || goal.id == expectedGoalID
        else {
            return nil
        }

        if !hasPendingWork { goal.attemptCount += 1 }
        let evaluation = evaluation(for: goal, events: events, hasPendingWork: hasPendingWork)
        goal.status = evaluation.status
        goal.lastEvaluation = evaluation
        goal.updatedAt = now
        goals[storageKey] = goal
        return evaluation
    }

    private func evaluation(
        for goal: AgentSessionGoalRecord,
        events: [AgentSessionEvent],
        hasPendingWork: Bool
    ) -> AgentSessionGoalEvaluation {
        if events.contains(where: { $0.type == .inputRequest }) {
            return AgentSessionGoalEvaluation(
                status: .waitingInput,
                reason: "The turn is waiting for user input.",
                shouldContinue: false
            )
        }

        if let completion = successfulSessionCompletion(in: events) {
            switch completion.status {
            case "waiting_input":
                return AgentSessionGoalEvaluation(
                    status: .waitingInput,
                    reason: completion.summary ?? "The agent needs user input to continue.",
                    shouldContinue: false
                )
            case "blocked":
                return AgentSessionGoalEvaluation(
                    status: .blocked,
                    reason: completion.summary ?? "The agent reported a blocker.",
                    shouldContinue: false
                )
            default:
                break
            }
        }

        if let interrupted = events.last(where: { $0.runStatus?.stage == .interrupted })?.runStatus {
            return AgentSessionGoalEvaluation(
                status: .blocked,
                reason: interrupted.details ?? "The turn was interrupted before the goal could be completed.",
                shouldContinue: false
            )
        }

        if hasPendingWork {
            return AgentSessionGoalEvaluation(status: .active, reason: "Waiting for delegated tasks.", shouldContinue: false)
        }

        if let completion = successfulSessionCompletion(in: events),
           completion.status == "completed" || completion.completed
        {
            return AgentSessionGoalEvaluation(
                status: .completed,
                reason: "The agent explicitly completed the goal with `session.complete`.",
                shouldContinue: false
            )
        }

        if goal.attemptCount >= goal.maxAttempts {
            return AgentSessionGoalEvaluation(
                status: .exhausted,
                reason: "The goal reached its automatic continuation limit.",
                shouldContinue: false
            )
        }

        return AgentSessionGoalEvaluation(
            status: .active,
            reason: "The goal is not complete yet.",
            shouldContinue: true,
            continuationPrompt: SloppyTUIGoalPromptFormatter.continuationPrompt(goal: goal)
        )
    }

    private func successfulSessionCompletion(
        in events: [AgentSessionEvent]
    ) -> (status: String?, completed: Bool, summary: String?)? {
        events.lazy.compactMap { event -> (String?, Bool, String?)? in
            guard event.type == .toolResult,
                  let result = event.toolResult,
                  result.tool == SessionCompleteTool.toolName,
                  result.ok,
                  let data = result.data?.asObject
            else {
                return nil
            }
            return (
                data["status"]?.asString,
                data["completed"]?.asBool == true,
                data["summary"]?.asString
            )
        }.last
    }

    private func update(
        agentID: String,
        sessionID: String,
        now: Date,
        mutate: (inout AgentSessionGoalRecord) -> Void
    ) -> AgentSessionGoalRecord? {
        let storageKey = key(agentID: agentID, sessionID: sessionID)
        guard var goal = goals[storageKey] else {
            return nil
        }
        mutate(&goal)
        goal.updatedAt = now
        goals[storageKey] = goal
        return goal
    }

    private func key(agentID: String, sessionID: String) -> String {
        "\(agentID)\u{0}\(sessionID)"
    }
}
