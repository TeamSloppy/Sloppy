import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import UniformTypeIdentifiers

extension ChatScreenViewModel {
    func handleRunStatus(_ status: ChatRunStatusEvent, sessionId: String) {
        if let tokenUsage = status.tokenUsage {
            contextTokenUsage = tokenUsage
        }
        if status.stage.isWorking {
            _ = ensureActiveStreamingAssistantTurn(for: sessionId)
            clearWorkingTreeSourceControl()
            if let agentId = selectedAgent?.id {
                scheduleAuxiliaryRefresh(agentId: agentId, sessionId: sessionId)
            }
        }
        activeRunStatus = status
        if status.stage == .interrupted,
           let details = status.details?.trimmingCharacters(in: .whitespacesAndNewlines),
           !details.isEmpty,
           let failedMessage = transcript.messages.last(where: {
               $0.role == .assistant
                   && $0.textContent.trimmingCharacters(in: .whitespacesAndNewlines) == details
           }) {
            providerSettingsRecoveryMessageIDs.insert(failedMessage.id)
        }
        if status.stage == .responding,
           let expandedText = status.expandedText,
           !expandedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scheduleStreamingAssistantText(expandedText, sessionId: sessionId, mode: .replace)
        }

        switch status.stage {
        case .thinking, .searching, .responding:
            isAwaitingAgentResponse = true
        case .paused, .done, .interrupted:
            flushPendingStreamingAssistantText()
            let completedMessageId = streamingTurnTracker.completeNextTurn(for: sessionId)
            isAwaitingAgentResponse = false
            isStopping = false
            if let activity = computerUseActivity, activity.phase == .active {
                computerUseActivity = activity.finishing(
                    failed: status.stage == .interrupted
                )
            }
            refreshWorkingTreeSourceControl()
            if status.stage == .done, let completedMessageId {
                scheduleResponseCompletionNotification(
                    sessionId: sessionId,
                    messageId: completedMessageId
                )
            }
            if status.stage == .paused {
                if let agentId = selectedAgent?.id {
                    Task { @MainActor in
                        await refreshPendingToolApproval(agentId: agentId, sessionId: sessionId)
                        guard isCurrentSession(agentId: agentId, sessionId: sessionId) else { return }
                        await sendNextQueuedMessageIfIdle()
                    }
                }
            } else {
                pendingToolApproval = nil
                if let agentId = selectedAgent?.id {
                    Task { @MainActor in
                        guard isCurrentSession(agentId: agentId, sessionId: sessionId) else { return }
                        await sendNextQueuedMessageIfIdle()
                    }
                }
            }
        }
    }

    func scheduleAuxiliaryRefresh(agentId: String, sessionId: String) {
        let generation = hydrationGeneration
        if approvalRefreshTask == nil {
            approvalRefreshTask = Task { @MainActor in
                defer { if hydrationGeneration == generation { approvalRefreshTask = nil } }
                await refreshPendingToolApproval(agentId: agentId, sessionId: sessionId)
                guard !Task.isCancelled, isCurrentSession(agentId: agentId, sessionId: sessionId) else { return }
                Task { @MainActor in
                    guard isCurrentSession(agentId: agentId, sessionId: sessionId) else { return }
                    await sendNextQueuedMessageIfIdle()
                }
            }
        }
        if usageRefreshTask == nil {
            usageRefreshTask = Task { @MainActor in
                defer { if hydrationGeneration == generation { usageRefreshTask = nil } }
                await refreshSemanticDecisionUsage(agentId: agentId, sessionId: sessionId)
            }
        }
    }

    private func refreshSemanticDecisionUsage(agentId: String, sessionId: String) async {
        guard isCurrentSession(agentId: agentId, sessionId: sessionId) else { return }
        guard let response = try? await apiClient.fetchSessionTokenUsage(
            agentId: agentId,
            sessionId: sessionId
        ) else {
            return
        }
        guard !Task.isCancelled, isCurrentSession(agentId: agentId, sessionId: sessionId) else { return }
        semanticDecisionUsage = response.semanticDecisionUsage
    }

    func clearWorkingTreeSourceControl() {
        workingTreeSourceControlTask?.cancel()
        workingTreeSourceControlTask = nil
        workingTreeSourceControl = nil
    }

    func refreshWorkingTreeSourceControl() {
        workingTreeSourceControlTask?.cancel()
        guard let projectId = activeProjectId,
              let sessionId = selectedSessionId else {
            workingTreeSourceControl = nil
            return
        }
        let taskId = activeTaskId

        workingTreeSourceControlTask = Task { @MainActor in
            let response = try? await apiClient.fetchProjectWorkingTreeSourceControl(
                projectId: projectId,
                taskId: taskId
            )
            guard !Task.isCancelled,
                  activeProjectId == projectId,
                  activeTaskId == taskId,
                  selectedSessionId == sessionId else {
                return
            }
            workingTreeSourceControl = response
        }
    }

    private func scheduleResponseCompletionNotification(
        sessionId: String,
        messageId: String
    ) {
        guard let agent = selectedAgent else { return }
        let responsePreview = transcript.messages.last(where: {
            $0.role == .assistant
                && !$0.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })?.textContent
        let notification = AgentResponseCompletionNotification(
            agentName: agent.displayName,
            sessionTitle: activeSessionTitle,
            responsePreview: responsePreview,
            agentId: agent.id,
            sessionId: sessionId,
            messageId: messageId
        )
        Task { @MainActor [responseNotificationScheduler] in
            await responseNotificationScheduler.schedule(notification)
        }
    }

    @discardableResult
    func beginStreamingAssistantTurn(for sessionId: String) -> String {
        flushPendingStreamingAssistantText()
        if computerUseActivity?.phase != .active {
            computerUseActivity = nil
            isComputerUsePreviewHidden = false
        }
        let messageId = "streaming-assistant-\(sessionId)-\(UUID().uuidString.lowercased())"
        streamingTurnTracker.begin(sessionId: sessionId, messageId: messageId)
        return messageId
    }

    func ensureActiveStreamingAssistantTurn(for sessionId: String) -> String {
        currentStreamingAssistantMessageId(for: sessionId)
            ?? beginStreamingAssistantTurn(for: sessionId)
    }

    func currentStreamingAssistantMessageId(for sessionId: String) -> String? {
        streamingTurnTracker.currentMessageId(for: sessionId)
    }

    func clearActiveStreamingAssistantTurn(for sessionId: String? = nil) {
        streamingTurnTracker.clear(sessionId: sessionId)
    }
}
