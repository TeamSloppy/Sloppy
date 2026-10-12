import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import UniformTypeIdentifiers

extension ChatScreenViewModel {
    public func requestRenameActiveSession() {
        sessionToRename = sessions.first { $0.id == selectedSessionId }
    }

    public func renameSession(_ session: ChatSessionSummary, title: String) async throws {
        var summary = try await apiClient.renameAgentSession(agentId: session.agentId, sessionId: session.id, title: title)
        summary.sourceInstanceID = session.sourceInstanceID
        upsertSessionSummary(summary)
        await cacheStore.cacheSessions(agentId: session.agentId, projectId: session.projectId, sessions: sessions)
        showSessionStatus("Renamed chat")
    }

    public func deleteSession(_ session: ChatSessionSummary) {
        Task { @MainActor in
            do {
                try await apiClient.deleteAgentSession(agentId: session.agentId, sessionId: session.id)
                modelPreferences.removeSession(
                    server: apiClient.endpoint.cacheNamespace,
                    agentId: session.agentId,
                    sessionId: session.id
                )
                settings.setSessionPinned(session.storageID, isPinned: false)
                sessions.removeAll { $0.storageID == session.storageID }
                sessionCatalog.removeAll { $0.storageID == session.storageID }

                if selectedSessionId == session.id {
                    disconnectCurrentSession()
                    selectedSessionId = nil
                    restoreModelSelection(agentId: session.agentId, sessionId: nil)
                    settings.lastSessionId = nil
                    transcript.clear()
                    activeContextTitle = nil
                    activeProjectId = nil
                    activeTaskId = nil
                }

                showSessionStatus("Deleted \(displayTitle(for: session))")
            } catch {
                showSessionStatus("Could not delete \(displayTitle(for: session))")
            }
        }
    }


    public func toggleSessionPinned(_ session: ChatSessionSummary) {
        let nextPinned = !settings.isSessionPinned(session.storageID)
        settings.setSessionPinned(session.storageID, isPinned: nextPinned)
        sessions = sortSessions(sessions)
        sessionCatalog = sortSessions(sessionCatalog)
        showSessionStatus(nextPinned ? "Pinned \(displayTitle(for: session))" : "Unpinned \(displayTitle(for: session))")
    }

    public func copyDebugSessionLink(_ session: ChatSessionSummary) {
        copyDebugSessionFileLink(session)
    }

    public func copyDebugSessionFileLink(_ session: ChatSessionSummary) {
        let url = debugSessionFilePathURL(for: session)
        UIClipboard.setString(url.absoluteString)
        showSessionStatus("Copied session file debug link")
    }

    public func openSessionFromSummary(_ session: ChatSessionSummary) {
        if agents.isEmpty {
            pendingSessionSummary = session
            loadInitialData()
            return
        }

        pendingSessionSummary = nil
        openSession(session)
    }

    public func forkSession(from message: ChatMessage) {
        guard !isForkingSession,
              let agent = selectedAgent,
              let parentSessionId = selectedSessionId else {
            return
        }

        let parent = sessions.first { $0.id == parentSessionId }
        let projectId = parent?.projectId ?? activeProjectId
        let workspaceId = parent?.workspaceId
        let responseTitle = message.textContent
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String
        if let responseTitle, !responseTitle.isEmpty {
            title = "Fork: \(String(responseTitle.prefix(48)))"
        } else {
            title = "Fork of \(activeSessionTitle)"
        }

        isForkingSession = true
        sendErrorMessage = nil
        Task { @MainActor in
            defer { isForkingSession = false }
            do {
                let summary = try await apiClient.createAgentSession(
                    agentId: agent.id,
                    title: title,
                    parentSessionId: parentSessionId,
                    projectId: projectId,
                    workspaceId: workspaceId
                )
                upsertSessionSummary(summary)
                selectSession(
                    summary.id,
                    contextTitle: displayTitle(for: summary),
                    projectId: projectId
                )
            } catch {
                sendErrorMessage = "Could not fork session: \(error.localizedDescription)"
            }
        }
    }

    #if DEBUG
    public func downloadSession(_ session: ChatSessionSummary) {
        guard let agent = selectedAgent else { return }
        Task { @MainActor in
            do {
                let data = try await apiClient.fetchAgentSessionData(agentId: agent.id, sessionId: session.id)
                let fileURL = try saveDebugSessionData(data, session: session)
                showSessionStatus("Saved \(fileURL.lastPathComponent)")
            } catch {
                showSessionStatus("Could not save \(displayTitle(for: session))")
            }
        }
    }
    #endif
}
