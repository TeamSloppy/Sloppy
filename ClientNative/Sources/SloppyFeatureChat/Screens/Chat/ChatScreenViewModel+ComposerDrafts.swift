import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import UniformTypeIdentifiers

extension ChatScreenViewModel {
    func syncComposerDraft(
        toSessionId sessionId: String?,
        projectId: String?,
        taskId: String?,
        agentId: String?
    ) {
        let nextKey = composerDraftKey(
            sessionId: sessionId,
            projectId: projectId,
            taskId: taskId,
            agentId: agentId
        )
        // Cache/network bootstrap may resolve the same context more than once.
        // The live composer (including selection) is authoritative until we leave it.
        if activeComposerDraftKey != nextKey {
            saveActiveComposerDraft()
            activeComposerDraftKey = nextKey
            let storedDraft = composerDraftsByKey[nextKey]
            composerDraft.text = storedDraft?.text ?? ""
            composerAttachments = storedDraft?.attachments ?? []
            composerQuotes = storedDraft?.quotes ?? []
            if sessionId == nil, let agentId,
               let delivery = suspendedDeliveries.removeValue(forKey: deliveryKey(agentId: agentId, sessionId: nextKey)) {
                messageQueue = delivery.queue
                queuedMessages = delivery.queue.messages
                isSending = delivery.isSending
                isAwaitingAgentResponse = delivery.isAwaitingResponse
                sendErrorMessage = delivery.errorMessage
                for message in delivery.optimisticMessages { transcript.upsert(message) }
            }
        }
        if !pendingComposerQuotes.isEmpty {
            composerQuotes.append(contentsOf: pendingComposerQuotes)
            pendingComposerQuotes = []
            saveActiveComposerDraft()
        }
        if let pendingComposerTextMutation {
            self.pendingComposerTextMutation = nil
            applyComposerTextMutation(pendingComposerTextMutation)
        }
    }

    func saveActiveComposerDraft() {
        guard let activeComposerDraftKey else { return }
        if composerDraft.text.isEmpty && composerAttachments.isEmpty && composerQuotes.isEmpty {
            composerDraftsByKey.removeValue(forKey: activeComposerDraftKey)
        } else {
            composerDraftsByKey[activeComposerDraftKey] = StoredComposerDraft(
                text: composerDraft.text,
                attachments: composerAttachments,
                quotes: composerQuotes
            )
        }
    }

    func clearActiveComposerDraft() {
        guard let activeComposerDraftKey else {
            composerDraft.text = ""
            composerAttachments = []
            composerQuotes = []
            return
        }
        composerDraft.text = ""
        composerAttachments = []
        composerQuotes = []
        composerDraftsByKey.removeValue(forKey: activeComposerDraftKey)
    }

    func restoreComposerDraft(
        content: String,
        attachments: [ChatComposerAttachment],
        quotes: [ChatComposerQuote]
    ) {
        composerDraft.text = content
        composerAttachments = attachments
        composerQuotes = quotes
        saveActiveComposerDraft()
    }

    private func composerDraftKey(
        sessionId: String?,
        projectId: String?,
        taskId: String?,
        agentId: String?
    ) -> String {
        if let sessionId, !sessionId.isEmpty {
            return "session:\(sessionId)"
        }

        let resolvedAgentId = agentId ?? selectedAgent?.id ?? "none"
        return "draft:\(resolvedAgentId):\(projectId ?? "-"):\(taskId ?? "-")"
    }
}
