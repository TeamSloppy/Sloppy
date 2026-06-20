import Foundation
import Protocols

// MARK: - Autodream

extension CoreService {
    struct AutodreamPassResult: Sendable, Equatable {
        var candidatesReviewed: Int
        var sessionsSkipped: Int
    }

    @discardableResult
    func runAutodreamPass(reason: String) async -> AutodreamPassResult {
        await waitForStartup(dispatchReadyTasks: false)

        let limit = max(1, currentConfig.visor.autodream.sessionLimitPerRun)
        let modelOverride = autodreamModelOverride()
        var reviewed = 0
        var skipped = 0

        let agents: [AgentSummary]
        do {
            agents = try listAgents(includeSystem: false)
        } catch {
            logger.warning("autodream.list_agents_failed", metadata: ["error": .string(error.localizedDescription)])
            return AutodreamPassResult(candidatesReviewed: 0, sessionsSkipped: 0)
        }

        for agent in agents {
            let sessions: [AgentSessionSummary]
            do {
                sessions = try listAgentSessions(agentID: agent.id, limit: limit)
            } catch {
                logger.warning(
                    "autodream.list_sessions_failed",
                    metadata: ["agent_id": .string(agent.id), "error": .string(error.localizedDescription)]
                )
                continue
            }

            for session in sessions {
                guard reviewed < limit else {
                    return AutodreamPassResult(candidatesReviewed: reviewed, sessionsSkipped: skipped)
                }
                guard await shouldAutodreamReview(agentID: agent.id, session: session) else {
                    skipped += 1
                    continue
                }

                await store.saveAutodreamSessionReview(AutodreamSessionReviewRecord(
                    agentId: agent.id,
                    sessionId: session.id,
                    status: "running",
                    reason: reason,
                    sessionUpdatedAt: session.updatedAt
                ))

                await runAgentMemoryCheckpoint(
                    agentID: agent.id,
                    sessionID: session.id,
                    reason: "autodream:\(reason)",
                    modelOverride: modelOverride
                )

                await store.saveAutodreamSessionReview(AutodreamSessionReviewRecord(
                    agentId: agent.id,
                    sessionId: session.id,
                    status: "succeeded",
                    reason: reason,
                    sessionUpdatedAt: session.updatedAt
                ))
                reviewed += 1
            }
        }

        return AutodreamPassResult(candidatesReviewed: reviewed, sessionsSkipped: skipped)
    }

    func shouldAutodreamReview(agentID: String, session: AgentSessionSummary) async -> Bool {
        guard session.kind == .chat else { return false }
        guard session.messageCount > 0 else { return false }

        guard let review = await store.autodreamSessionReview(agentId: agentID, sessionId: session.id) else {
            return true
        }
        guard review.status == "succeeded" else {
            return true
        }
        return review.sessionUpdatedAt < session.updatedAt
    }

    private func autodreamModelOverride() -> String? {
        let autodreamModel = currentConfig.visor.autodream.model?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let autodreamModel, !autodreamModel.isEmpty {
            return autodreamModel
        }
        let visorModel = currentConfig.visor.model?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let visorModel, !visorModel.isEmpty {
            return visorModel
        }
        return nil
    }
}
