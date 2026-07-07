//
//  MainViewModel.swift
//  SloppyClient
//
//  Created by Vladislav Prusakov on 05.07.2026.
//

import Observation
import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat
import SloppyFeatureProjects

enum MainAppSection: String, CaseIterable, Hashable {
    case projects
    case agents
    case chats
    case workspace
    case settings
}

@Observable
@MainActor
final class MainViewModel {
    let baseURL: URL
    let settings: ClientSettings
    let connectionMonitor: ConnectionMonitor
    let onOpenSettings: @MainActor () -> Void
    let onOpenWorkspace: @MainActor () -> Void
    let cacheStore: ClientCacheStore

    var projects: [APIProjectRecord] = []
    var isLoadingProjects = false
    var didLoadProjects = false
    var collapsedProjectIds: Set<String> = []
    var expandedTaskLists: Set<String> = []
    var selectedAppSection: MainAppSection = .chats
    var selectedSidebarItem: MainSidebarSelection? = nil
    var isSidebarCollapsed = false
    var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    var isMobileTabsOverviewPresented = false
    var isVisionTabsOverviewPresented = false
    var tabs: [WorkspaceTab] = []
    var selectedTabID: WorkspaceTab.ID?
    var desktopSplitState: DesktopTabSplitState?
    var tabStates: [WorkspaceTab.ID: WorkspaceTabState] = [:]
    var chatViewModel: ChatScreenViewModel
    var workspacePanelViewModel: WorkspacePanelViewModel
    var chatNavigationSerial = 0
    let apiClient: SloppyAPIClient

    var sidebarWidth: CGFloat {
        isSidebarCollapsed ? MainSidebarView.collapsedWidth : MainSidebarView.expandedWidth
    }

    var sidebarMinimumWidth: CGFloat {
        isSidebarCollapsed ? MainSidebarView.collapsedWidth : MainSidebarView.minimumWidth
    }

    var sidebarMaximumWidth: CGFloat {
        isSidebarCollapsed ? MainSidebarView.collapsedWidth : MainSidebarView.maximumWidth
    }

    var workspaceContext: WorkspacePanelContext? {
        guard let projectId = chatViewModel.activeProjectIdForWorkspacePanel,
              let projectName = chatViewModel.activeProjectNameForWorkspacePanel else {
            return nil
        }
        return WorkspacePanelContext(projectId: projectId, projectName: projectName)
    }

    var chatSidebarMode: ChatSidebarListMode {
        get { settings.chatSidebarMode }
        set { settings.chatSidebarMode = newValue }
    }

    init(
        baseURL: URL,
        settings: ClientSettings,
        connectionMonitor: ConnectionMonitor,
        cacheStore: ClientCacheStore = ClientCacheStore(),
        onOpenSettings: @Sendable @escaping @MainActor () -> Void,
        onOpenWorkspace: @escaping @MainActor () -> Void
    ) {
        let apiClient = SloppyAPIClient(baseURL: baseURL)
        self.baseURL = baseURL
        self.settings = settings
        self.connectionMonitor = connectionMonitor
        self.cacheStore = cacheStore
        self.onOpenSettings = onOpenSettings
        self.onOpenWorkspace = onOpenWorkspace
        self.chatViewModel = ChatScreenViewModel(
            apiClient: apiClient,
            cacheStore: cacheStore,
            settings: settings,
            connectionMonitor: connectionMonitor,
            onOpenSettings: onOpenSettings
        )
        self.workspacePanelViewModel = WorkspacePanelViewModel(apiClient: apiClient)
        self.apiClient = apiClient
    }

    func openMobileSidebar() {
        isSidebarCollapsed = false
        columnVisibility = .all
    }

    func dismissMobileSidebar() {
        columnVisibility = .detailOnly
    }

    func selectNewChat() {
        selectAppSection(.chats)
        updateSelectedSidebarItem(.chats)
        dismissMobileSidebar()
        routePrimaryChat(.blank)
    }

    func selectChatSession(_ session: ChatSessionSummary) {
        selectAppSection(.chats)
        updateSelectedSidebarItem(.chats)
        dismissMobileSidebar()
        openSessionChatTab(session)
    }

    func deleteChatSession(_ session: ChatSessionSummary) {
        chatViewModel.deleteSession(session)
    }

    func togglePinChatSession(_ session: ChatSessionSummary) {
        chatViewModel.toggleSessionPinned(session)
    }

    func copyDebugSessionFileLink(_ session: ChatSessionSummary) {
        chatViewModel.copyDebugSessionFileLink(session)
    }

    func openSessionChatTab(_ session: ChatSessionSummary) {
        selectAppSection(.chats)
        updateSelectedSidebarItem(.chats)
        dismissMobileSidebar()
        if retargetSelectedChatTab(to: session) {
            return
        }

        let key = WorkspaceTabKey.chatSession(session.id)
        if let existing = tabs.first(where: { $0.key == key }) {
            selectedTabID = existing.id
            return
        }

        let chatState = makeChatTabState()
        chatState.viewModel.openSessionFromSummary(session)
        let tab = WorkspaceTab(
            key: key,
            kind: .chat,
            title: session.title,
            payload: .chatSession(sessionID: session.id, title: session.title)
        )
        tabs.append(tab)
        tabStates[tab.id] = WorkspaceTabState(contentState: .chat(chatState))
        selectedTabID = tab.id
    }

    func selectProject(_ project: APIProjectRecord) {
        selectAppSection(.projects)
        updateSelectedSidebarItem(.project(project.id))
        dismissMobileSidebar()
        routePrimaryChat(
            .project(
                projectId: project.id,
                projectName: project.name,
                agentId: project.actors?.first
            )
        )
    }

    func openProjectKanbanTab(project: APIProjectRecord) {
        selectAppSection(.projects)
        updateSelectedSidebarItem(.project(project.id))
        dismissMobileSidebar()
        let key = WorkspaceTabKey.projectKanban(project.id)
        if let existing = tabs.first(where: { $0.key == key }) {
            selectedTabID = existing.id
            return
        }

        let kanbanState = makeProjectKanbanTabState()
        Task { @MainActor in
            await kanbanState.viewModel.load(projectId: project.id)
        }
        let tab = WorkspaceTab(
            key: key,
            kind: .projectKanban,
            title: project.name,
            payload: .projectKanban(
                ProjectKanbanTabContext(projectId: project.id, projectName: project.name)
            )
        )
        tabs.append(tab)
        tabStates[tab.id] = WorkspaceTabState(contentState: .projectKanban(kanbanState))
        selectedTabID = tab.id
    }

    func selectTask(
        projectId: String,
        projectName: String,
        task: APIProjectTask,
        fallbackAgentId: String?
    ) {
        selectAppSection(.projects)
        updateSelectedSidebarItem(.task(projectId: projectId, taskId: task.id))
        dismissMobileSidebar()
        routePrimaryChat(
            .task(
                projectId: projectId,
                projectName: projectName,
                taskId: task.id,
                taskTitle: task.title,
                agentId: task.actorId ?? fallbackAgentId
            )
        )
    }

    func openTaskChatTab(project: APIProjectRecord, task: APIProjectTask, fallbackAgentId: String?) {
        selectAppSection(.projects)
        updateSelectedSidebarItem(.task(projectId: project.id, taskId: task.id))
        dismissMobileSidebar()
        let key = WorkspaceTabKey.chatTask(projectId: project.id, taskId: task.id)
        if let existing = tabs.first(where: { $0.key == key }) {
            selectedTabID = existing.id
            return
        }

        let chatState = makeChatTabState()
        applyNavigationRequestOnNextTurn(
            ChatNavigationRequest(
                id: Int.random(in: Int.min ... Int.max),
                context: .task(
                    projectId: project.id,
                    projectName: project.name,
                    taskId: task.id,
                    taskTitle: task.title,
                    agentId: task.actorId ?? fallbackAgentId
                )
            ),
            to: chatState.viewModel,
            loadInitialData: true
        )
        let tab = WorkspaceTab(
            key: key,
            kind: .chat,
            title: task.title,
            payload: .chatTask(
                projectId: project.id,
                projectName: project.name,
                taskId: task.id,
                taskTitle: task.title,
                fallbackAgentId: task.actorId ?? fallbackAgentId
            )
        )
        tabs.append(tab)
        tabStates[tab.id] = WorkspaceTabState(contentState: .chat(chatState))
        selectedTabID = tab.id
    }

    func openTaskDetailTab(project: APIProjectRecord, task: APIProjectTask, fallbackAgentId: String?) {
        selectAppSection(.projects)
        updateSelectedSidebarItem(.task(projectId: project.id, taskId: task.id))
        dismissMobileSidebar()
        let key = WorkspaceTabKey.taskDetail(projectId: project.id, taskId: task.id)
        if let existing = tabs.first(where: { $0.key == key }) {
            selectedTabID = existing.id
            return
        }

        let detailState = makeTaskDetailTabState()
        let tab = WorkspaceTab(
            key: key,
            kind: .taskDetail,
            title: task.title,
            payload: .taskDetail(
                TaskDetailTabContext(
                    projectId: project.id,
                    projectName: project.name,
                    taskId: task.id,
                    taskTitle: task.title,
                    fallbackAgentId: task.actorId ?? fallbackAgentId
                )
            )
        )
        tabs.append(tab)
        tabStates[tab.id] = WorkspaceTabState(contentState: .taskDetail(detailState))
        selectedTabID = tab.id
    }

    func toggleProjectCollapse(projectId: String) {
        if collapsedProjectIds.contains(projectId) {
            collapsedProjectIds.remove(projectId)
        } else {
            collapsedProjectIds.insert(projectId)
        }
    }

    func toggleTaskListExpansion(projectId: String) {
        if expandedTaskLists.contains(projectId) {
            expandedTaskLists.remove(projectId)
        } else {
            expandedTaskLists.insert(projectId)
        }
    }

    func refreshContent() async {
        await loadProjects(force: true)
        if chatViewModel.selectedAgent == nil {
            chatViewModel.loadInitialData()
        } else {
            await chatViewModel.refreshCurrentContext()
        }
    }

    func loadProjects(force: Bool = false) async {
        guard force || !didLoadProjects else { return }
        guard !isLoadingProjects else { return }

        isLoadingProjects = true
        defer {
            didLoadProjects = true
            isLoadingProjects = false
        }

        let client = SloppyAPIClient(baseURL: baseURL)
        let list = (try? await client.fetchProjects()) ?? []
        if list.isEmpty {
            projects = await cacheStore.loadProjects()
        } else {
            projects = list
            await cacheStore.cacheProjects(list)
        }

        if selectedSidebarItem == nil, let firstProject = list.first {
            selectedSidebarItem = .project(firstProject.id)
        }
    }

    func selectAppSection(_ section: MainAppSection) {
        guard selectedAppSection != section else {
            return
        }
        selectedAppSection = section
        dismissMobileSidebar()
    }

    func selectTab(_ tabID: WorkspaceTab.ID) {
        guard tabs.contains(where: { $0.id == tabID }) else {
            return
        }

        if let desktopSplitState,
           tabID != desktopSplitState.primaryTabID,
           tabID != desktopSplitState.secondaryTabID {
            clearDesktopSplit()
        }

        selectedTabID = tabID
    }

    func beginDesktopSplit(source sourceTabID: WorkspaceTab.ID, target targetTabID: WorkspaceTab.ID) {
        guard sourceTabID != targetTabID,
              tabs.contains(where: { $0.id == sourceTabID }),
              tabs.contains(where: { $0.id == targetTabID }) else {
            return
        }

        desktopSplitState = DesktopTabSplitState(
            primaryTabID: targetTabID,
            secondaryTabID: sourceTabID,
            fraction: 0.5
        )
        selectedTabID = targetTabID
    }

    func updateDesktopSplitFraction(_ fraction: CGFloat) {
        guard var desktopSplitState else {
            return
        }
        desktopSplitState.fraction = min(0.72, max(0.28, fraction))
        self.desktopSplitState = desktopSplitState
    }

    func clearDesktopSplit() {
        desktopSplitState = nil
    }

    func createBlankChatTab(select: Bool = true) {
        let chatState = makeChatTabState()
        let draftID = "draft-\(UUID().uuidString)"
        let tab = WorkspaceTab(
            key: .chatSession(draftID),
            kind: .chat,
            title: "New Chat",
            payload: .chatSession(sessionID: draftID, title: "New Chat")
        )
        tabs.append(tab)
        tabStates[tab.id] = WorkspaceTabState(contentState: .chat(chatState))
        if select {
            selectedTabID = tab.id
        }
    }

    func nextTabID(from tabID: WorkspaceTab.ID, offset: Int) -> WorkspaceTab.ID? {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            return nil
        }
        let nextIndex = index + offset
        guard tabs.indices.contains(nextIndex) else {
            return nil
        }
        return tabs[nextIndex].id
    }

    func selectAdjacentTab(offset: Int) {
        guard let selectedTabID,
              let nextID = nextTabID(from: selectedTabID, offset: offset) else {
            return
        }
        self.selectedTabID = nextID
    }

    func presentMobileTabsOverview() {
        isMobileTabsOverviewPresented = true
    }

    func dismissMobileTabsOverview() {
        isMobileTabsOverviewPresented = false
    }

    func presentVisionTabsOverview() {
        isVisionTabsOverviewPresented = true
    }

    func dismissVisionTabsOverview() {
        isVisionTabsOverviewPresented = false
    }

    func closeActiveTab() {
        guard let selectedTabID else {
            return
        }
        closeTab(selectedTabID)
    }

    func closeTab(_ tabID: WorkspaceTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            return
        }

        let splitStateBeforeClose = desktopSplitState
        let wasSelected = selectedTabID == tabID
        tabs.remove(at: index)
        tabStates.removeValue(forKey: tabID)

        if let splitStateBeforeClose {
            if tabID == splitStateBeforeClose.primaryTabID {
                selectedTabID = splitStateBeforeClose.secondaryTabID
                clearDesktopSplit()
            } else if tabID == splitStateBeforeClose.secondaryTabID {
                selectedTabID = splitStateBeforeClose.primaryTabID
                clearDesktopSplit()
            } else if !tabs.contains(where: { $0.id == splitStateBeforeClose.primaryTabID }) ||
                        !tabs.contains(where: { $0.id == splitStateBeforeClose.secondaryTabID }) {
                clearDesktopSplit()
            }
        }

        if tabs.isEmpty {
            selectedTabID = nil
            createBlankChatTab(select: true)
            if isMobileTabsOverviewPresented {
                dismissMobileTabsOverview()
            }
            return
        }

        guard wasSelected else {
            return
        }

        let nextIndex = min(index, tabs.count - 1)
        selectedTabID = tabs[nextIndex].id
    }

    func makeChatTabState() -> ChatTabState {
        let apiClient = SloppyAPIClient(baseURL: baseURL)
        return ChatTabState(
            viewModel: ChatScreenViewModel(
                apiClient: apiClient,
                cacheStore: cacheStore,
                settings: settings,
                connectionMonitor: connectionMonitor,
                onOpenSettings: onOpenSettings
            )
        )
    }

    func makeProjectKanbanTabState() -> ProjectKanbanTabState {
        let apiClient = SloppyAPIClient(baseURL: baseURL)
        return ProjectKanbanTabState(viewModel: ProjectKanbanViewModel(apiClient: apiClient))
    }

    func makeWorkspaceFilesTabState() -> WorkspaceFilesTabState {
        let apiClient = SloppyAPIClient(baseURL: baseURL)
        return WorkspaceFilesTabState(viewModel: WorkspacePanelViewModel(apiClient: apiClient))
    }

    func makeTaskDetailTabState() -> TaskDetailTabState {
        let apiClient = SloppyAPIClient(baseURL: baseURL)
        return TaskDetailTabState(viewModel: TaskDetailViewModel(apiClient: apiClient))
    }

    func openWorkspaceTabForSelectedContext() {
        guard let context = activeWorkspaceFilesContext() else {
            return
        }

        let key = WorkspaceTabKey.workspaceFiles(context.projectId)
        if let existing = tabs.first(where: { $0.key == key }) {
            selectedTabID = existing.id
            return
        }

        let workspaceState = makeWorkspaceFilesTabState()
        let tab = WorkspaceTab(
            key: key,
            kind: .workspaceFiles,
            title: "\(context.projectName) Files",
            payload: .workspaceFiles(context)
        )
        tabs.append(tab)
        tabStates[tab.id] = WorkspaceTabState(contentState: .workspaceFiles(workspaceState))
        selectedTabID = tab.id
    }

    private func updateSelectedSidebarItem(_ selection: MainSidebarSelection) {
        guard selectedSidebarItem != selection else {
            return
        }
        selectedSidebarItem = selection
    }

    private func routePrimaryChat(_ context: ChatNavigationRequest.Context) {
        chatNavigationSerial += 1
        applyNavigationRequestOnNextTurn(
            ChatNavigationRequest(id: chatNavigationSerial, context: context),
            to: chatViewModel,
            loadInitialData: false
        )
    }

    private func applyNavigationRequestOnNextTurn(
        _ request: ChatNavigationRequest,
        to viewModel: ChatScreenViewModel,
        loadInitialData: Bool
    ) {
        Task { @MainActor in
            viewModel.applyNavigationRequest(request)
            if loadInitialData {
                viewModel.loadInitialData()
            }
        }
    }

    private func openOrSelectTab(key: WorkspaceTabKey, makeTab: @autoclosure () -> WorkspaceTab) {
        if let existing = tabs.first(where: { $0.key == key }) {
            selectedTabID = existing.id
            return
        }

        let tab = makeTab()
        tabs.append(tab)
        selectedTabID = tab.id
    }

    @discardableResult
    private func retargetSelectedChatTab(to session: ChatSessionSummary) -> Bool {
        guard let selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == selectedTabID }),
              tabs[index].kind == .chat,
              let chatState = tabStates[selectedTabID]?.chatState else {
            return false
        }

        clearDesktopSplit()
        chatState.viewModel.openSessionFromSummary(session)
        tabs[index] = WorkspaceTab(
            id: tabs[index].id,
            key: .chatSession(session.id),
            kind: .chat,
            title: session.title,
            payload: .chatSession(sessionID: session.id, title: session.title)
        )
        return true
    }

    private func activeWorkspaceFilesContext() -> WorkspaceFilesTabContext? {
        guard let selectedTabID,
              let tab = tabs.first(where: { $0.id == selectedTabID }) else {
            return nil
        }

        switch tab.payload {
        case .projectKanban(let context):
            return WorkspaceFilesTabContext(projectId: context.projectId, projectName: context.projectName)
        case .workspaceFiles(let context):
            return context
        case .chatTask(let projectId, let projectName, _, _, _):
            return WorkspaceFilesTabContext(projectId: projectId, projectName: projectName)
        case .taskDetail(let context):
            return WorkspaceFilesTabContext(projectId: context.projectId, projectName: context.projectName)
        case .chatSession:
            guard let chatState = tabStates[tab.id]?.chatState,
                  let projectId = chatState.viewModel.activeProjectIdForWorkspacePanel,
                  let projectName = chatState.viewModel.activeProjectNameForWorkspacePanel else {
                return nil
            }
            return WorkspaceFilesTabContext(projectId: projectId, projectName: projectName)
        }
    }
}
