import Foundation
import Protocols

extension CoreService {
    enum SessionRestoreError: String, Error, LocalizedError {
        case checkpointUnavailable = "restore_checkpoint_unavailable"
        case activeRun = "restore_run_active"
        case pendingInput = "restore_input_pending"
        case pendingApproval = "restore_approval_pending"
        case pendingWatch = "restore_watch_pending"
        case unsupportedSession = "restore_session_unsupported"
        case conflictingInstruction = "restore_instruction_conflict"

        var errorDescription: String? {
            switch self {
            case .checkpointUnavailable: "This turn is no longer available to restore."
            case .activeRun: "Wait for the current run or queued messages to finish before restoring."
            case .pendingInput: "Answer the pending question before restoring the run."
            case .pendingApproval: "Resolve the pending tool approval before restoring the run."
            case .pendingWatch: "Core is still monitoring a job for this session."
            case .unsupportedSession: "Restore is available for native agent chats."
            case .conflictingInstruction: "This checkpoint was already restored with a different instruction."
            }
        }
    }

    /// Continue the latest recoverable attempt of an existing turn, with a durable receipt for retries.
    public func restoreAgentSession(
        agentID: String, sessionID: String, request: AgentSessionRestoreRequest
    ) async throws -> AgentSessionMessageResponse {
        await waitForStartup()
        let instruction = request.instruction?.trimmingCharacters(in: .whitespacesAndNewlines)
        let extra = instruction?.isEmpty == false ? instruction : nil
        guard !request.turnId.isEmpty, !request.checkpointId.isEmpty, (extra?.utf8.count ?? 0) <= 16_384 else {
            throw AgentSessionError.invalidPayload
        }
        let detail = try getAgentSession(agentID: agentID, sessionID: sessionID)
        let agentID = detail.summary.agentId
        let sessionID = detail.summary.id
        guard detail.summary.kind == .chat, !isPeerCommunicationSession(detail),
              try getAgentConfig(agentID: agentID).runtime.type == .native else {
            throw SessionRestoreError.unsupportedSession
        }
        if let receipt = SessionTurnRecovery.receipt(for: request, in: detail.events) {
            guard receipt.runStatus?.turnCheckpoint?.instruction == extra else {
                throw SessionRestoreError.conflictingInstruction
            }
            return .init(summary: detail.summary, appendedEvents: [], routeDecision: nil)
        }
        guard !sessionMessageIsStopping, !activeSessionMessageRuns.contains(sessionID),
              pendingSessionMessageIDs(agentID: agentID, sessionID: sessionID).isEmpty else {
            throw SessionRestoreError.activeRun
        }
        activeSessionMessageRuns.insert(sessionID)
        defer {
            activeSessionMessageRuns.remove(sessionID)
            scheduleSessionInbox(agentID: agentID, sessionID: sessionID)
        }

        let approvals = await toolApprovalService.listPending(includeUnpublished: true)
        guard !approvals.contains(where: { $0.sessionId == sessionID || $0.displaySessionId == sessionID }) else {
            throw SessionRestoreError.pendingApproval
        }
        let current = try getAgentSession(agentID: agentID, sessionID: sessionID)
        guard !sessionHasPendingInput(current) else { throw SessionRestoreError.pendingInput }
        guard !hasPendingSessionWatch(sessionID: sessionID) else { throw SessionRestoreError.pendingWatch }
        guard let recovery = SessionTurnRecovery.latest(in: current.events),
              recovery.checkpoint.turnId == request.turnId, recovery.checkpointID == request.checkpointId else {
            throw SessionRestoreError.checkpointUnavailable
        }
        guard recovery.priorInstructions.reduce(extra?.utf8.count ?? 0, { $0 + $1.utf8.count }) <= 16_384 else {
            throw AgentSessionError.invalidPayload
        }
        await toolLoopGuard.beginTurn(sessionID: sessionID)
        let goalContext = await sessionGoalContext(agentID: agentID, sessionID: sessionID)
        do {
            let scope = recovery.scope(sessionID: sessionID)
            let response = try await SessionTurnRecovery.$active.withValue(scope) {
                try await sessionOrchestrator.restoreMessage(
                    agentID: agentID, sessionID: sessionID, recovery: recovery,
                    instruction: extra, additionalContext: SessionCommunicationPolicy.instructions + goalContext,
                    shouldSteer: { [weak self] in
                        await self?.hasQueuedSteeringMessage(agentID: agentID, sessionID: sessionID) == true
                    }
                )
            }
            if !response.yieldedToSteering {
                await reconcileWorkflowAgentSession(agentID: agentID, sessionID: sessionID, response: response)
            }
            return response
        } catch let error as AgentSessionOrchestrator.OrchestratorError {
            throw mapSessionOrchestratorError(error)
        }
    }
}
