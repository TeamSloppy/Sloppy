import Foundation
import SloppyClientCore

extension ChatScreenViewModel {
    func restoreApprovalMode(agentId: String, sessionId: String?) {
        let revision = UUID()
        approvalModeRevision = revision
        isSavingApprovalMode = false
        approvalModeErrorMessage = nil
        selectedApprovalMode = .askForApproval
        guard let sessionId else {
            isLoadingApprovalMode = false
            return
        }
        selectedApprovalMode = approvalModesBySession[deliveryKey(agentId: agentId, sessionId: sessionId)] ?? .askForApproval
        isLoadingApprovalMode = true
        let pendingSave = approvalModeSaveTask
        Task { @MainActor in
            defer {
                if approvalModeRevision == revision {
                    isLoadingApprovalMode = false
                    Task { @MainActor in await sendNextQueuedMessageIfIdle() }
                }
            }
            do {
                // Returning to a chat must observe the result of an in-flight save.
                if let pendingSave { _ = try? await pendingSave.value }
                let policy = try await apiClient.fetchChatApprovalPolicy(agentId: agentId, sessionId: sessionId)
                guard approvalModeRevision == revision, isCurrentSession(agentId: agentId, sessionId: sessionId) else { return }
                selectedApprovalMode = policy.mode
                approvalModesBySession[deliveryKey(agentId: agentId, sessionId: sessionId)] = policy.mode
            } catch {
                guard approvalModeRevision == revision else { return }
                approvalModeErrorMessage = approvalPolicyError(error)
            }
        }
    }

    public func reloadApprovalMode() {
        guard let agentId = selectedAgent?.id else { return }
        restoreApprovalMode(agentId: agentId, sessionId: selectedSessionId)
    }

    public func selectApprovalMode(_ mode: ChatApprovalMode) {
        guard !isSavingApprovalMode, !isLoadingApprovalMode, !isSending,
              let agentId = selectedAgent?.id else { return }
        approvalModeErrorMessage = nil
        guard let sessionId = selectedSessionId else {
            selectedApprovalMode = mode
            return
        }
        let revision = UUID()
        approvalModeRevision = revision
        isSavingApprovalMode = true
        let saveTask = Task { @MainActor [apiClient] in
            try await apiClient.setChatApprovalPolicy(agentId: agentId, sessionId: sessionId, mode: mode)
        }
        approvalModeSaveTask = saveTask
        Task { @MainActor in
            defer {
                if approvalModeRevision == revision {
                    isSavingApprovalMode = false
                    Task { @MainActor in await sendNextQueuedMessageIfIdle() }
                }
            }
            do {
                let policy = try await saveTask.value
                approvalModesBySession[deliveryKey(agentId: agentId, sessionId: sessionId)] = policy.mode
                guard approvalModeRevision == revision, isCurrentSession(agentId: agentId, sessionId: sessionId) else { return }
                selectedApprovalMode = policy.mode
            } catch {
                guard approvalModeRevision == revision else { return }
                approvalModeErrorMessage = approvalPolicyError(error)
            }
        }
    }

    private func approvalPolicyError(_ error: Error) -> String {
        if (error as? APIError)?.statusCode == 404 {
            return "Update Sloppy Core to use chat approval modes."
        }
        return "Could not load or save the approval mode: \(error.localizedDescription)"
    }
}
