import Foundation
import Protocols

actor AgentSessionGoalController {
    private var goals: [String: AgentSessionGoalRecord] = [:]

    func start(
        agentID: String,
        sessionID: String,
        objective: String,
        maxAttempts: Int = 8,
        now: Date = Date()
    ) -> AgentSessionGoalRecord {
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
        now: Date = Date()
    ) -> AgentSessionGoalEvaluation? {
        let storageKey = key(agentID: agentID, sessionID: sessionID)
        guard var goal = goals[storageKey],
              goal.status == .active
        else {
            return nil
        }

        goal.attemptCount += 1
        let evaluation = evaluation(for: goal, events: events)
        goal.status = evaluation.status
        goal.lastEvaluation = evaluation
        goal.updatedAt = now
        goals[storageKey] = goal
        return evaluation
    }

    private func evaluation(
        for goal: AgentSessionGoalRecord,
        events: [AgentSessionEvent]
    ) -> AgentSessionGoalEvaluation {
        if events.contains(where: { $0.type == .inputRequest }) {
            return AgentSessionGoalEvaluation(
                status: .waitingInput,
                reason: "The turn is waiting for user input.",
                shouldContinue: false
            )
        }

        if let interrupted = events.last(where: { $0.runStatus?.stage == .interrupted })?.runStatus {
            return AgentSessionGoalEvaluation(
                status: .blocked,
                reason: interrupted.details ?? "The turn was interrupted before the goal could be completed.",
                shouldContinue: false
            )
        }

        if hasSuccessfulSessionCompletion(in: events) {
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

    private func hasSuccessfulSessionCompletion(in events: [AgentSessionEvent]) -> Bool {
        events.contains { event in
            guard event.type == .toolResult,
                  let result = event.toolResult,
                  result.tool == SessionCompleteTool.toolName,
                  result.ok
            else {
                return false
            }
            return result.data?.asObject?["completed"]?.asBool == true
        }
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
