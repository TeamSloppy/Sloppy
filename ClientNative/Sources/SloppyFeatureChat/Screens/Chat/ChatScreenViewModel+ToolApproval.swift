import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import UniformTypeIdentifiers

extension ChatScreenViewModel {
    public func refreshPendingToolApproval() async {
        guard let agentId = selectedAgent?.id,
              let sessionId = selectedSessionId else {
            pendingToolApproval = nil
            return
        }
        await refreshPendingToolApproval(agentId: agentId, sessionId: sessionId)
    }

    func refreshPendingToolApproval(agentId: String, sessionId: String) async {
        guard let approvals = try? await apiClient.fetchPendingToolApprovals(),
              !Task.isCancelled, isCurrentSession(agentId: agentId, sessionId: sessionId) else {
            return
        }
        let previousApprovalID = pendingToolApproval?.id
        pendingToolApproval = approvals.first { approval in
            approval.status == "pending"
                && !resolvedToolApprovalIDs.contains(approval.id)
                && (approval.expiresAt.map { $0 > Date() } ?? true)
                && (approval.displaySessionId == sessionId || approval.sessionId == sessionId)
                && (approval.agentId == nil || approval.agentId == agentId)
        }
        approvalExpirationTask?.cancel()
        if let previousApprovalID, previousApprovalID != pendingToolApproval?.id {
            responseNotificationScheduler.dismissApproval(id: previousApprovalID)
        }
        if let approval = pendingToolApproval {
            if let notification = AgentToolApprovalNotification(approval: approval) {
                await responseNotificationScheduler.scheduleApproval(notification)
            }
            guard isCurrentSession(agentId: agentId, sessionId: sessionId), pendingToolApproval?.id == approval.id else { return }
            if let expiresAt = approval.expiresAt {
                approvalExpirationTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(max(0, expiresAt.timeIntervalSinceNow)))
                    guard !Task.isCancelled, let self,
                          self.isCurrentSession(agentId: agentId, sessionId: sessionId),
                          self.pendingToolApproval?.id == approval.id else { return }
                    self.pendingToolApproval = nil
                    self.toolApprovalErrorMessage = nil
                    self.responseNotificationScheduler.dismissApproval(id: approval.id)
                    self.showSessionStatus("Approval expired. Ask the agent to retry if needed.")
                    await self.refreshPendingToolApproval()
                }
            }
        } else {
            toolApprovalErrorMessage = nil
        }
    }

    public func resolvePendingToolApproval(
        approved: Bool,
        scope: ClientToolApprovalDecisionScope = .once
    ) {
        guard let approval = pendingToolApproval,
              !isResolvingToolApproval else {
            return
        }
        isResolvingToolApproval = true
        toolApprovalErrorMessage = nil
        Task { @MainActor in
            defer { isResolvingToolApproval = false }
            do {
                try await apiClient.resolveToolApproval(id: approval.id, approved: approved, scope: scope)
                resolvedToolApprovalIDs.insert(approval.id)
                responseNotificationScheduler.dismissApproval(id: approval.id)
                guard pendingToolApproval?.id == approval.id else { return }
                approvalExpirationTask?.cancel()
                pendingToolApproval = nil
                isAwaitingAgentResponse = true
            } catch {
                guard pendingToolApproval?.id == approval.id else { return }
                if (error as? APIError)?.statusCode == 404 {
                    resolvedToolApprovalIDs.insert(approval.id)
                    approvalExpirationTask?.cancel()
                    responseNotificationScheduler.dismissApproval(id: approval.id)
                    pendingToolApproval = nil
                    toolApprovalErrorMessage = nil
                    showSessionStatus("Approval is no longer available. Ask the agent to retry if needed.")
                    await refreshPendingToolApproval()
                } else {
                    toolApprovalErrorMessage = error.localizedDescription
                }
            }
        }
    }

    public func stopActiveRun() {
        guard let agentId = selectedAgent?.id,
              let sessionId = selectedSessionId,
              shouldShowStopButton,
              !isStopping else {
            return
        }

        isStopping = true
        Task { @MainActor in
            do {
                try await apiClient.interruptAgentSession(
                    agentId: agentId,
                    sessionId: sessionId,
                    includeSubsessions: true,
                    reason: "Interrupted from Apple client"
                )
            } catch {
                guard isCurrentSession(agentId: agentId, sessionId: sessionId) else { return }
                isStopping = false
            }
        }
    }
}
