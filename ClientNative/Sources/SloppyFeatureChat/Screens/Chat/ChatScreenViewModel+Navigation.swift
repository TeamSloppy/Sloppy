import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import UniformTypeIdentifiers

extension ChatScreenViewModel {
    public func applyNavigationRequest(_ request: ChatNavigationRequest?) {
        guard let request else { return }
        guard lastAppliedNavigationRequestId != request.id else { return }

        if agents.isEmpty {
            // Show the requested context immediately; bind its agent after bootstrap.
            pendingNavigationRequest = request
        } else {
            pendingNavigationRequest = nil
            lastAppliedNavigationRequestId = request.id
        }

        switch request.context {
        case .blank:
            routeToBlankChat()
        case .project(let projectId, let projectName, _):
            routeToContext(
                request,
                projectId: projectId,
                title: "Project: \(projectName)",
                opensPreferredSession: request.opensPreferredSession
            )
        case .task(let projectId, let projectName, let taskId, let taskTitle, _):
            routeToContext(
                request,
                projectId: projectId,
                title: "\(projectName) / \(taskTitle)",
                preferredSessionTitle: taskTitle,
                preferredTaskId: taskId,
                opensPreferredSession: request.opensPreferredSession
            )
        }
    }

    func switchAgent(_ agent: APIAgentRecord) {
        disconnectCurrentSession()
        saveActiveComposerDraft()
        selectedAgent = agent
        selectedSessionId = nil
        restoreModelSelection(agentId: agent.id, sessionId: nil)
        transcript.clear()
        activeContextTitle = nil
        activeProjectId = nil
        activeTaskId = nil
        settings.lastAgentId = agent.id
        settings.lastSessionId = nil
        syncComposerDraft(toSessionId: nil, projectId: nil, taskId: nil, agentId: agent.id)
        Task { @MainActor in
            await loadSessions(for: agent)
        }
    }

    func startNewSession() {
        guard let agent = selectedAgent else { return }
        disconnectCurrentSession()
        let contextTitle = activeContextTitle
        let projectId = activeProjectId
        let taskId = activeTaskId
        saveActiveComposerDraft()
        transcript.clear()
        selectedSessionId = nil
        restoreModelSelection(agentId: agent.id, sessionId: nil)
        activeContextTitle = contextTitle
        activeProjectId = projectId
        activeTaskId = taskId
        syncComposerDraft(toSessionId: nil, projectId: projectId, taskId: taskId, agentId: agent.id)
        Task { @MainActor in
            let sessionTitle = taskId.map(taskSessionTitle(for:))
            guard let summary = try? await apiClient.createAgentSession(
                agentId: agent.id,
                title: sessionTitle,
                projectId: projectId,
                taskId: taskId,
                separateChat: true
            ) else { return }
            upsertSessionSummary(summary)
            selectedSessionId = summary.id
            rememberCurrentModelSelection(agentId: agent.id, sessionId: summary.id)
            settings.lastSessionId = summary.id
            await connectToSession(agentId: agent.id, sessionId: summary.id)
        }
    }

    func openSession(_ session: ChatSessionSummary) {
        let nextAgent = agents.first {
            $0.id.caseInsensitiveCompare(session.agentId) == .orderedSame
        } ?? selectedAgent

        if let nextAgent, selectedAgent?.id != nextAgent.id {
            disconnectCurrentSession()
            selectedAgent = nextAgent
            settings.lastAgentId = nextAgent.id
        }

        selectSession(
            session.id,
            contextTitle: displayTitle(for: session),
            projectId: session.projectId,
            taskId: session.taskId
        )
    }

    func selectSession(
        _ sessionId: String,
        contextTitle: String? = nil,
        projectId: String? = nil,
        taskId: String? = nil
    ) {
        guard let agent = selectedAgent else { return }
        let session = sessions.first(where: { $0.id == sessionId })
            ?? sessionCatalog.first(where: { $0.id == sessionId })
        let resolvedContextTitle = contextTitle ?? session.map(displayTitle) ?? activeContextTitle
        let resolvedProjectId = session?.projectId ?? projectId
        let resolvedTaskId = session?.taskId ?? taskId
        saveActiveComposerDraft()
        disconnectCurrentSession()
        transcript.clear()
        isLoadingTranscript = true
        selectedSessionId = sessionId
        restoreModelSelection(agentId: agent.id, sessionId: sessionId)
        rememberCurrentModelSelection(agentId: agent.id, sessionId: sessionId)
        activeContextTitle = resolvedContextTitle
        activeProjectId = resolvedProjectId
        activeTaskId = resolvedTaskId
        settings.lastSessionId = sessionId
        if let resolvedProjectId {
            settings.lastProjectId = resolvedProjectId
        }
        syncComposerDraft(
            toSessionId: sessionId,
            projectId: resolvedProjectId,
            taskId: resolvedTaskId,
            agentId: agent.id
        )
        requestTranscriptScrollToEnd()
        requestComposerFocus()
        Task { @MainActor in
            await connectToSession(agentId: agent.id, sessionId: sessionId)
        }
    }

    func routeToBlankChat() {
        let agent = selectedAgent ?? agents.first
        guard let agent else {
            selectedAgent = nil
            selectedSessionId = nil
            transcript.clear()
            activeContextTitle = nil
            activeProjectId = nil
            activeTaskId = nil
            requestComposerFocus()
            return
        }

        activateDraft(agent: agent, contextTitle: nil)
    }

    private func routeToContext(
        _ request: ChatNavigationRequest,
        projectId: String,
        title: String,
        preferredSessionTitle: String? = nil,
        preferredTaskId: String? = nil,
        opensPreferredSession: Bool = true
    ) {
        let agent = agentForNavigation(request) ?? selectedAgent ?? agents.first
        guard let agent else {
            selectedAgent = nil
            selectedSessionId = nil
            transcript.clear()
            activeContextTitle = title
            activeProjectId = projectId
            activeTaskId = preferredTaskId
            requestComposerFocus()
            return
        }

        activateProjectContext(
            agent: agent,
            projectId: projectId,
            contextTitle: title,
            preferredSessionTitle: preferredSessionTitle,
            preferredTaskId: preferredTaskId,
            opensPreferredSession: opensPreferredSession
        )
    }

    private func agentForNavigation(_ request: ChatNavigationRequest) -> APIAgentRecord? {
        guard let preferredAgentId = request.preferredAgentId else { return nil }
        return agents.first {
            $0.id.caseInsensitiveCompare(preferredAgentId) == .orderedSame
        }
    }

    func activateDraft(agent: APIAgentRecord, contextTitle: String?) {
        createsSeparateProjectChat = false
        disconnectCurrentSession()
        saveActiveComposerDraft()
        selectedAgent = agent
        selectedSessionId = nil
        restoreModelSelection(agentId: agent.id, sessionId: nil)
        transcript.clear()
        activeContextTitle = contextTitle
        activeProjectId = nil
        activeTaskId = nil
        settings.lastAgentId = agent.id
        settings.lastSessionId = nil
        syncComposerDraft(toSessionId: nil, projectId: nil, taskId: nil, agentId: agent.id)
        requestComposerFocus()

        Task { @MainActor in
            await loadSessions(for: agent)
        }
    }

    func selectProjectLongChat(_ session: ChatSessionSummary, contextTitle: String?) {
        // Preserve text entered while the project chat was opening.
        saveActiveComposerDraft()
        let draftKey = activeComposerDraftKey
        if let draftKey, let draft = composerDraftsByKey[draftKey] {
            composerDraftsByKey["session:\(session.id)"] = draft
        }
        selectSession(session.id, contextTitle: contextTitle, projectId: session.projectId)
        if let draftKey { composerDraftsByKey.removeValue(forKey: draftKey) }
    }

    func activateProjectContext(
        agent: APIAgentRecord,
        projectId: String,
        contextTitle: String,
        preferredSessionTitle: String?,
        preferredTaskId: String?,
        opensPreferredSession: Bool = true
    ) {
        disconnectCurrentSession()
        saveActiveComposerDraft()
        createsSeparateProjectChat = false
        selectedAgent = agent
        selectedSessionId = nil
        restoreModelSelection(agentId: agent.id, sessionId: nil)
        transcript.clear()
        activeContextTitle = contextTitle
        activeProjectId = projectId
        activeTaskId = preferredTaskId
        settings.lastAgentId = agent.id
        settings.lastProjectId = projectId
        settings.lastSessionId = nil
        syncComposerDraft(
            toSessionId: nil,
            projectId: projectId,
            taskId: preferredTaskId,
            agentId: agent.id
        )

        requestComposerFocus()
        Task { @MainActor in
            await loadSessions(for: agent, projectId: preferredTaskId == nil ? projectId : nil)
            guard selectedAgent?.id == agent.id,
                  activeProjectId == projectId,
                  activeTaskId == preferredTaskId,
                  !createsSeparateProjectChat,
                  selectedSessionId == nil else {
                return
            }

            guard opensPreferredSession else {
                return
            }

            if preferredTaskId == nil {
                do {
                    let session = try await apiClient.openLongChat(agentId: agent.id, projectId: projectId)
                    guard selectedAgent?.id == agent.id, activeProjectId == projectId,
                          activeTaskId == nil, !createsSeparateProjectChat,
                          selectedSessionId == nil else { return }
                    upsertSessionSummary(session)
                    selectProjectLongChat(session, contextTitle: contextTitle)
                } catch let error as APIError where error.statusCode == 400 {
                    // ACP runtimes do not support server-enforced coordinator tools yet.
                    if let session = preferredSession(in: sessions, title: nil, taskId: nil,
                                                      projectId: projectId, allowsFallback: true) {
                        selectSession(session.id, contextTitle: contextTitle, projectId: projectId)
                    }
                } catch { sendErrorMessage = error.localizedDescription }
                return
            }

            guard let session = preferredSession(
                in: sessions,
                title: preferredSessionTitle,
                taskId: preferredTaskId,
                projectId: projectId,
                allowsFallback: preferredTaskId == nil
            ) else {
                return
            }

            selectSession(session.id, contextTitle: contextTitle, projectId: projectId, taskId: preferredTaskId)
        }
    }
}
