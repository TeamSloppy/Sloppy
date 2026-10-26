import Foundation
import SloppyClientCore

extension ChatScreenViewModel {
    var approvalModeAllowsSending: Bool {
        guard !isSavingApprovalMode else { return false }
        guard let agentId = selectedAgent?.id, let sessionId = selectedSessionId else { return true }
        // Reading a mode updates its presentation; Core enforces the saved policy.
        // An explicit failed change must be resolved before another turn.
        return !failedApprovalModeSaveKeys.contains(deliveryKey(agentId: agentId, sessionId: sessionId))
    }

    func restoreApprovalMode(agentId: String, sessionId: String?) {
        let revision = UUID()
        approvalModeRevision = revision
        isSavingApprovalMode = false
        approvalModeErrorMessage = nil
        selectedApprovalMode = .askForApproval
        hasDraftApprovalModeOverride = false
        if let sessionId {
            selectedApprovalMode = approvalModesBySession[deliveryKey(agentId: agentId, sessionId: sessionId)] ?? .askForApproval
        }
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
                let policy: ChatApprovalPolicy
                if let sessionId {
                    policy = try await apiClient.fetchChatApprovalPolicy(agentId: agentId, sessionId: sessionId)
                } else {
                    do {
                        policy = try await apiClient.fetchDefaultChatApprovalPolicy()
                    } catch {
                        guard (error as? APIError)?.statusCode == 404 else { throw error }
                        // Older Core versions have no configurable default.
                        policy = .init(mode: .askForApproval)
                    }
                }
                guard approvalModeRevision == revision, selectedAgent?.id == agentId,
                      selectedSessionId == sessionId else { return }
                selectedApprovalMode = policy.mode
                if let sessionId {
                    let key = deliveryKey(agentId: agentId, sessionId: sessionId)
                    approvalModesBySession[key] = policy.mode
                    failedApprovalModeSaveKeys.remove(key)
                }
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
            hasDraftApprovalModeOverride = true
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
                let key = deliveryKey(agentId: agentId, sessionId: sessionId)
                approvalModesBySession[key] = policy.mode
                failedApprovalModeSaveKeys.remove(key)
                guard approvalModeRevision == revision, isCurrentSession(agentId: agentId, sessionId: sessionId) else { return }
                selectedApprovalMode = policy.mode
            } catch {
                failedApprovalModeSaveKeys.insert(deliveryKey(agentId: agentId, sessionId: sessionId))
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
