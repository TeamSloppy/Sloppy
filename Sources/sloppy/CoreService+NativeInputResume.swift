import Foundation
import AgentRuntime
import PluginSDK
import Protocols
import SloppyRuntime

extension CoreService {
    func nativeInputRequest(metadata: AgentRunMetadata, detail: AgentSessionDetail) throws -> AgentSessionPostMessageRequest {
        let messageID = metadata.inputMessageId ?? metadata.userTurnId
        guard let input = try SessionInputLifecycle.states(in: detail.events)[messageID],
              input.owner?.runId == metadata.runId, input.owner?.userTurnId == metadata.userTurnId else {
            throw AgentSessionError.invalidPayload
        }
        return try NativeInputCapture.materialize(input.context, store: sessionStore,
            agentID: detail.summary.agentId, sessionID: detail.summary.id)
    }

    func prepareNativeInputResolution(detail: AgentSessionDetail, response: PlanInputResponse,
        prompt: String) async throws -> (metadata: AgentRunMetadata, request: AgentSessionPostMessageRequest)? {
        let agentID = detail.summary.agentId, sessionID = detail.summary.id
        let journal = SessionLoopJournal(store: sessionStore, agentID: agentID, sessionID: sessionID, authorizeWriter: {})
        guard let state = try await journal.restoreRunState(),
              await state.snapshot().loopConfig?.engine == .unified else { return nil }
        guard !activeSessionMessageRuns.contains(sessionID),
              !sessionMessageControlIsActive(agentID: agentID, sessionID: sessionID),
              await state.completion?.inputRequestId == response.requestId,
              let accepted = detail.events.compactMap({ $0.isHistorical ? nil : $0.runtimeMetadata }).last(where: {
                  $0.runId == state.runID && $0.userTurnId == state.userTurnID && $0.requestFingerprint != nil
              }) else { throw AgentSessionError.invalidPayload }
        let request = try nativeInputRequest(metadata: accepted, detail: detail)
        if response.status == .answered { try await state.resumeAfterInput(requestID: response.requestId) }
        else { await state.cancel() }
        let snapshot = await state.snapshot()
        var context = detail.events.compactMap { event -> [AgentRunInstruction]? in
            guard !event.isHistorical, event.runtimeMetadata?.runId == state.runID,
                  event.runtimeMetadata?.userTurnId == state.userTurnID else { return nil }
            return event.runtimeMetadata?.admissionInstructions
        }.last ?? []
        if response.status == .answered { context += AgentSessionOrchestrator.turnContextInstructions(prompt) }
        var metadata = AgentRunMetadata(runId: state.runID, userTurnId: state.userTurnID,
            generation: snapshot.generation, runState: try JSONValueCoder.encode(snapshot),
            admissionInstructions: context, inputMessageId: accepted.inputMessageId ?? accepted.userTurnId,
            requestFingerprint: accepted.requestFingerprint)
        if response.status != .answered { metadata.admissionInstructions = nil }
        // Recheck after actor awaits; the following journal batch has no suspension point.
        guard !activeSessionMessageRuns.contains(sessionID),
              !sessionMessageControlIsActive(agentID: agentID, sessionID: sessionID) else { throw AgentSessionError.invalidPayload }
        try NativeJournalWriterGuard(directory: agentCatalogStore.directoryURL(agentID: agentID)).authorize(minimumJournalVersion: 3)
        return (metadata, request)
    }
}
