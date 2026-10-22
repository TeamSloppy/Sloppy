import SloppyClientCore
import SloppyFeatureChat

@MainActor
extension MainViewModel {
    func openWorkerSessionInSidePanel(_ session: ChatSessionSummary, from chat: ChatScreenViewModel) {
        let state = selectedTabID.flatMap { tabStates[$0] }
        guard state?.chatState?.viewModel === chat
            || state?.projectKanbanState?.chatViewModel === chat
            || (workspaceDockState.isPresented && workspaceDockState.selectedTab?.chat === chat)
            || (selectedTabID == nil && chatViewModel === chat) else { return }
        openSessionInSidePanel(session, endpoint: chat.sessionEndpoint)
    }

    func openSessionInSidePanel(_ session: ChatSessionSummary, endpoint: SloppyInstanceEndpoint) {
        if selectedTabID == nil { createBlankChatTab() }
        let dock = workspaceDockState
        let reference = ChatComposerReference(rawText: session.id, title: session.displayTitle,
            target: .session(agentId: session.agentId, sessionId: session.id), endpoint: endpoint)
        if let tab = dock.tabs.first(where: {
            $0.referencedObject?.target == reference.target && $0.chat?.sessionEndpoint == endpoint
        }) {
            tab.referencedObject = reference
            if tab.chat?.selectedSessionId != session.id || tab.chat?.selectedAgent?.id != session.agentId {
                tab.chat?.openSessionFromSummary(session)
            }
            dock.select(tab)
        } else {
            let tab = dock.open(.sideChat)
            tab.referencedObject = reference
            tab.chat = makeChatTabState(endpoint: endpoint).viewModel
            tab.chat?.openSessionFromSummary(session)
        }
        markSidebarSessionResultViewed(session)
    }

    func openComposerReference(_ reference: ChatComposerReference, from chat: ChatScreenViewModel) {
        let endpoint = reference.endpoint ?? chat.sessionEndpoint
        let api = endpoint == apiClient.endpoint ? apiClient : SloppyAPIClient(endpoint: endpoint)
        let dock = workspaceDockState
        switch reference.target {
        case .file(let project, let path):
            dock.openSourceFile(SourceFileReference(path: path), apiClient: api, scope: .project(project))
        case .session(let agent, let session):
            if let tab = dock.tabs.first(where: { $0.referencedObject?.target == reference.target && $0.chat?.sessionEndpoint == endpoint }) {
                tab.referencedObject = reference
                if tab.chat?.selectedSessionId != session || tab.chat?.selectedAgent?.id != agent {
                    tab.chat?.openSessionFromSummary(.init(id: session, agentId: agent, title: reference.title))
                }
                dock.select(tab)
                return
            }
            let tab = dock.open(.sideChat)
            tab.referencedObject = reference
            tab.chat = makeChatTabState(endpoint: endpoint).viewModel
            tab.chat?.openSessionFromSummary(.init(id: session, agentId: agent, title: reference.title))
        case .website(let url):
            guard url.scheme == "https" || url.scheme == "http" else { return }
            let tab = openWorkspaceDockTab(.browser)
            tab.browser?.addressText = url.absoluteString
            tab.browser?.openAddress()
        case .command, .skill, .task:
            dock.openReferencePreview(reference, apiClient: api)
        }
    }

    func openSourceFile(_ reference: SourceFileReference, from chat: ChatScreenViewModel) {
        let scope: WorkspaceSourceFileViewModel.Scope
        if let projectID = chat.activeProjectIdForWorkspacePanel {
            scope = .project(projectID)
        } else if let agentID = chat.selectedAgent?.id {
            scope = .agent(agentID)
        } else {
            scope = .unavailable
        }
        workspaceDockState.openSourceFile(reference, apiClient: SloppyAPIClient(endpoint: chat.sessionEndpoint), scope: scope)
    }
}
