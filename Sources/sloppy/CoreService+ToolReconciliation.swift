import Foundation
import Protocols
import SloppyRuntime

extension CoreService {
    enum ToolReconciliationError: Error {
        case invalidEvidence
        case callNotFound
        case notInterrupted
        case callStillRunning
    }

    /// Owner-facing API action. This is deliberately not exposed as an agent tool.
    public func reconcileToolCall(agentID: String, sessionID: String, callEventID: String, request: ToolCallReconciliationRequest) async throws -> AgentSessionMessageResponse {
        await waitForStartup()
        let evidence = request.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !evidence.isEmpty, evidence.utf8.count <= 16_384 else { throw ToolReconciliationError.invalidEvidence }
        let detail = try getAgentSession(agentID: agentID, sessionID: sessionID)
        guard let call = detail.events.first(where: { $0.id == callEventID })?.toolCall else { throw ToolReconciliationError.callNotFound }
        guard !activeSessionToolCallIDs.contains(callEventID) else { throw ToolReconciliationError.callStillRunning }
        guard let prior = SessionToolRecovery.result(for: callEventID, in: detail.events),
              prior.executionOutcome?.requiresReconciliation == true else { throw ToolReconciliationError.notInterrupted }
        let notExecuted = request.decision == .notExecuted
        let outcome = ExecutionOutcome(state: request.decision == .completed ? .completed : .failed, category: notExecuted ? .unavailable : nil, code: notExecuted ? "tool_not_executed" : "tool_reconciled", retryable: notExecuted)
        let event = AgentSessionEvent(
            agentId: detail.summary.agentId, sessionId: detail.summary.id, type: .toolResult,
            toolResult: .init(tool: call.tool, ok: request.decision == .completed,
                data: .object(["reconciliation": .string(request.decision.rawValue), "evidence": .string(evidence)]),
                error: request.decision == .completed ? nil : .init(code: outcome.code ?? "tool_reconciled", message: evidence, retryable: notExecuted),
                callEventId: callEventID, executionOutcome: outcome)
        )
        // Serialize validation and commit with the Core actor's tool result writer.
        let agentID = detail.summary.agentId
        let sessionID = detail.summary.id
        let summary = try sessionStore.appendEvents(agentID: agentID, sessionID: sessionID, events: [event])
        publishLiveSessionEvents(agentID: agentID, sessionID: sessionID, summary: summary, events: [event])
        await applyPetProgressForAgentSessionEvents(agentID: agentID, sessionID: sessionID, summary: summary, events: [event])
        return .init(summary: summary, appendedEvents: [event], routeDecision: nil)
    }
}
