import Foundation
import Protocols

@MainActor
extension SloppyTUIScreen {
    func resetSessionRunActivity() {
        dismissPromptSuggestion()
        promptSuggestionRunID = nil
        latestSessionRunStatus = nil
        pendingToolCalls.removeAll()
        liveRunStage = nil
        liveRunStatusLine = nil
        sessionStreamTurnCompleted = false
    }

    var hasEmptyPromptComposer: Bool {
        editor.getText().isEmpty && pendingUploads.isEmpty && queuedMessages.messages.isEmpty
            && pendingPlanInputRequest == nil && pendingToolApproval == nil && !shellModeEnabled
    }

    var visiblePromptSuggestion: String? {
        guard hasEmptyPromptComposer, !isPosting, sessionListMode == .hidden,
              promptSuggestion?.sourceRunId == latestSessionRunStatus?.id else { return nil }
        return promptSuggestion?.text
    }

    func dismissPromptSuggestion() {
        promptSuggestionTask?.cancel()
        promptSuggestionTask = nil
        promptSuggestion = nil
    }

    func updatePromptSuggestion(for status: AgentRunStatusEvent) {
        guard status.stage == .done else { dismissPromptSuggestion(); return }
        guard hasPersistedSession, hasEmptyPromptComposer, promptSuggestionRunID != status.id else { return }
        dismissPromptSuggestion()
        promptSuggestionRunID = status.id
        let agentID = agent.id
        let sessionID = session.id
        let key = currentSessionStreamKey()
        promptSuggestionTask = Task { [weak self, service] in
            let suggestion = try? await service.suggestPrompt(agentID: agentID, sessionID: sessionID, sourceRunID: status.id)
            guard let self, !Task.isCancelled, self.currentSessionStreamKey() == key,
                  self.latestSessionRunStatus?.id == status.id, self.hasEmptyPromptComposer else { return }
            self.promptSuggestion = suggestion
            self.requestRender()
        }
    }

    func trackPendingToolCall(_ event: AgentSessionEvent, replaying: Bool = false) {
        guard event.importOrigin == nil, replaying || !sessionStreamTurnCompleted else { return }
        if event.toolCall != nil, !pendingToolCalls.contains(where: { $0.id == event.id }) {
            pendingToolCalls.append(event)
        }
        if let callID = event.toolResult?.callEventId {
            pendingToolCalls.removeAll { $0.id == callID }
        }
    }

    func toolActivityStatusLine(now: Date = Date()) -> String? {
        guard liveRunStage == .searching, let event = pendingToolCalls.last, let call = event.toolCall else { return nil }
        let display = SloppyTUITimelineDisplay.toolCallDisplay(tool: call.tool, arguments: call.arguments)
        let elapsed = SloppyTUITheme.elapsed(max(0, now.timeIntervalSince(event.createdAt)))
        let base = liveRunStatusLine ?? "Executing tool"
        let others = pendingToolCalls.count > 1 ? " · \(pendingToolCalls.count) tools" : ""
        return "\(base) · tool elapsed: \(elapsed)\(others) · \(display.summary ?? call.tool)"
    }

    func restoreSessionRunStatusAfterSend() {
        // Finishing a send (including a rejected send) says nothing about a run
        // already executing in Core. Only runtime events settle that run.
        if let status = latestSessionRunStatus {
            applySessionRunStatus(status)
        }
    }
}
