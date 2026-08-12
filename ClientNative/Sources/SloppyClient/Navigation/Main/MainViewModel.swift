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
    case scheduled
    case artifacts
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
    let onOpenSettings: @MainActor (ClientSettingsDestination) -> Void
    let onOpenWorkspace: @MainActor () -> Void
    let cacheStore: ClientCacheStore

    var projects: [APIProjectRecord] = []
    var isLoadingProjects = false
    var isProjectEditorPresented = false
    var projectBeingEdited: APIProjectRecord?
    var didLoadProjects = false
    var collapsedProjectIds: Set<String> = []
    var expandedTaskLists: Set<String> = []
    var visibleProjectCount = 5
    var selectedAppSection: MainAppSection = .chats
    var selectedSidebarItem: MainSidebarSelection? = nil
    var isSidebarCollapsed = false
    var columnVisibility: NavigationSplitViewVisibility
    var isMobileTabsOverviewPresented = false
    var isVisionTabsOverviewPresented = false
    var tabs: [WorkspaceTab] = []
    var selectedTabID: WorkspaceTab.ID?
    var desktopSplitState: DesktopTabSplitState?
    var tabStates: [WorkspaceTab.ID: WorkspaceTabState] = [:]
    var terminalSessions: [WorkspaceTab.ID: WorkspaceTerminalSession] = [:]
    var terminalHosts: [WorkspaceTab.ID: WorkspaceTerminalHosting] = [:]
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

    var hasLoadedInitialContent: Bool {
        didLoadProjects && chatViewModel.didLoadInitialData
    }

    var workspaceContext: WorkspacePanelContext? {
        guard let context = activeWorkspaceFilesContext() else {
            return nil
        }
        return WorkspacePanelContext(
            projectId: context.projectId,
            projectName: context.projectName
        )
    }

    var activeCanvasProjectID: String? {
        activeWorkspaceFilesContext()?.projectId
    }

    var activeCanvasWorkspaceID: String? {
        guard let selectedTabID else {
            return nil
        }
        return tabStates[selectedTabID]?.chatState?.viewModel.activeWorkspaceIdForCanvas
    }

    var selectedChatSessionID: String? {
        guard let selectedTabID,
              tabs.first(where: { $0.id == selectedTabID })?.kind == .chat else {
            return nil
        }
        return tabStates[selectedTabID]?.chatState?.viewModel.selectedSessionId
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
        onOpenSettings: @Sendable @escaping @MainActor (ClientSettingsDestination) -> Void,
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
            loadsGlobalSessionCatalog: true,
            onOpenSettings: onOpenSettings
        )
        self.workspacePanelViewModel = WorkspacePanelViewModel(apiClient: apiClient)
        self.apiClient = apiClient
        self.columnVisibility = {
            #if os(macOS)
            .automatic
            #else
            .detailOnly
            #endif
        }()
    }

    func openMobileSidebar() {
        isSidebarCollapsed = false
        columnVisibility = .all
    }

    func dismissMobileSidebar() {
//        #if os(iOS)
//        columnVisibility = .detailOnly
//        #endif
    }

    func selectNewChat() {
        selectAppSection(.chats)
        updateSelectedSidebarItem(.chats)
        dismissMobileSidebar()
        showBlankChatInSelectedTab()
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

        let chatState = makeChatTabState()
        chatState.viewModel.openSessionFromSummary(session)
        let tab = WorkspaceTab(
            key: .chatSession(session.id),
            kind: .chat,
            title: session.title,
            payload: .chatSession(sessionID: session.id, title: session.title)
        )
        showInSelectedTab(
            tab,
            state: WorkspaceTabState(contentState: .chat(chatState))
        )
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

        let kanbanState = makeProjectKanbanTabState()
        Task { @MainActor in
            await kanbanState.viewModel.load(projectId: project.id)
        }
        let tab = WorkspaceTab(
            key: key,
            kind: .projectKanban,
            title: project.name,
            payload: .projectKanban(
                ProjectKanbanTabContext(
                    projectId: project.id,
                    projectName: project.name,
                    projectRootPath: project.projectRootPath
                )
            )
        )
        showInSelectedTab(
            tab,
            state: WorkspaceTabState(contentState: .projectKanban(kanbanState))
        )
    }

    func presentProjectCreator() {
        projectBeingEdited = nil
        isProjectEditorPresented = true
    }

    func presentProjectEditor(_ project: APIProjectRecord) {
        projectBeingEdited = project
        isProjectEditorPresented = true
    }

    func didSaveProject(_ project: APIProjectRecord) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
            persistProjectOrder()
            openProjectKanbanTab(project: project)
        } else {
            projects.insert(project, at: 0)
            persistProjectOrder()
            showNewProjectChat(project: project)
        }
        Task { await cacheStore.cacheProjects(projects) }
        Task { await loadProjects(force: true) }
    }

    func showNewProjectChat(project: APIProjectRecord) {
        selectAppSection(.projects)
        updateSelectedSidebarItem(.project(project.id))
        dismissMobileSidebar()

        let chatState = makeChatTabState()
        chatNavigationSerial += 1
        applyNavigationRequestOnNextTurn(
            ChatNavigationRequest(
                id: chatNavigationSerial,
                context: .project(
                    projectId: project.id,
                    projectName: project.name,
                    agentId: project.actors?.first
                ),
                opensPreferredSession: false
            ),
            to: chatState.viewModel,
            loadInitialData: true
        )

        let draftID = "draft-\(UUID().uuidString)"
        let tab = WorkspaceTab(
            key: .chatSession(draftID),
            kind: .chat,
            title: "New Chat",
            payload: .chatSession(sessionID: draftID, title: "New Chat")
        )
        showInSelectedTab(
            tab,
            state: WorkspaceTabState(contentState: .chat(chatState))
        )
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
                projectRootPath: project.projectRootPath,
                taskId: task.id,
                taskTitle: task.title,
                fallbackAgentId: task.actorId ?? fallbackAgentId
            )
        )
        showInSelectedTab(
            tab,
            state: WorkspaceTabState(contentState: .chat(chatState))
        )
    }

    func openTaskDetailTab(project: APIProjectRecord, task: APIProjectTask, fallbackAgentId: String?) {
        selectAppSection(.projects)
        updateSelectedSidebarItem(.task(projectId: project.id, taskId: task.id))
        dismissMobileSidebar()
        let key = WorkspaceTabKey.taskDetail(projectId: project.id, taskId: task.id)

        let detailState = makeTaskDetailTabState()
        let tab = WorkspaceTab(
            key: key,
            kind: .taskDetail,
            title: task.title,
            payload: .taskDetail(
                TaskDetailTabContext(
                    projectId: project.id,
                    projectName: project.name,
                    projectRootPath: project.projectRootPath,
                    taskId: task.id,
                    taskTitle: task.title,
                    fallbackAgentId: task.actorId ?? fallbackAgentId
                )
            )
        )
        showInSelectedTab(
            tab,
            state: WorkspaceTabState(contentState: .taskDetail(detailState))
        )
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

    func showMoreProjects() {
        visibleProjectCount += 5
    }

    @discardableResult
    func moveProject(_ projectID: String, relativeTo targetProjectID: String) -> Bool {
        guard projectID != targetProjectID,
              let sourceIndex = projects.firstIndex(where: { $0.id == projectID }),
              let targetIndex = projects.firstIndex(where: { $0.id == targetProjectID }) else {
            return false
        }

        let project = projects.remove(at: sourceIndex)
        guard let remainingTargetIndex = projects.firstIndex(where: { $0.id == targetProjectID }) else {
            projects.insert(project, at: sourceIndex)
            return false
        }
        let destinationIndex = sourceIndex < targetIndex
            ? remainingTargetIndex + 1
            : remainingTargetIndex
        projects.insert(project, at: destinationIndex)
        persistProjectOrder()
        Task { await cacheStore.cacheProjects(projects) }
        return true
    }

    func refreshContent() async {
        await loadProjects(force: true)
        if chatViewModel.selectedAgent == nil {
            chatViewModel.loadInitialData()
        } else {
            await chatViewModel.refreshCurrentContext()
        }
    }

    func requestChatScrollToEnd(for tabID: WorkspaceTab.ID) {
        tabStates[tabID]?.chatState?.viewModel.requestTranscriptScrollToEnd()
    }

    func loadProjects(force: Bool = false) async {
        guard force || !didLoadProjects else { return }
        guard !isLoadingProjects else { return }

        isLoadingProjects = true
        if !force {
            projects = reconcileProjectOrder(await cacheStore.loadProjects())
            didLoadProjects = true
            visibleProjectCount = 5
        }

        defer {
            didLoadProjects = true
            isLoadingProjects = false
        }

        do {
            let list = try await apiClient.fetchProjects()
            projects = reconcileProjectOrder(list)
            await cacheStore.cacheProjects(projects)
        } catch {
            // The cached project snapshot remains available while offline.
        }
        visibleProjectCount = 5
    }

    private func reconcileProjectOrder(_ availableProjects: [APIProjectRecord]) -> [APIProjectRecord] {
        let projectsByID = Dictionary(uniqueKeysWithValues: availableProjects.map { ($0.id, $0) })
        let savedIDs = settings.projectOrderIDs.filter { projectsByID[$0] != nil }
        let savedIDSet = Set(savedIDs)
        let newProjects = availableProjects.filter { !savedIDSet.contains($0.id) }
        let orderedProjects = newProjects + savedIDs.compactMap { projectsByID[$0] }
        settings.projectOrderIDs = orderedProjects.map(\.id)
        return orderedProjects
    }

    private func persistProjectOrder() {
        settings.projectOrderIDs = projects.map(\.id)
    }

    func selectAppSection(_ section: MainAppSection) {
        guard selectedAppSection != section else {
            return
        }
        selectedAppSection = section
        dismissMobileSidebar()
    }

    func selectScheduled() {
        selectedSidebarItem = .scheduled
        selectAppSection(.scheduled)
    }

    func selectArtifacts() {
        selectedSidebarItem = .artifacts
        selectAppSection(.artifacts)
    }

    func selectWorkspace() {
        selectedSidebarItem = nil
        selectAppSection(.workspace)
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

    func showBlankChatInSelectedTab() {
        let chatState = makeChatTabState()
        let draftID = "draft-\(UUID().uuidString)"
        let tab = WorkspaceTab(
            key: .chatSession(draftID),
            kind: .chat,
            title: "New Chat",
            payload: .chatSession(sessionID: draftID, title: "New Chat")
        )
        showInSelectedTab(
            tab,
            state: WorkspaceTabState(contentState: .chat(chatState))
        )
    }

    func synchronizeChatTab(_ tabID: WorkspaceTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].kind == .chat,
              let chatViewModel = tabStates[tabID]?.chatState?.viewModel else {
            return
        }

        guard let sessionID = chatViewModel.selectedSessionId else {
            tabs[index] = WorkspaceTab(
                id: tabs[index].id,
                key: tabs[index].key,
                kind: .chat,
                title: "New Chat",
                payload: tabs[index].payload
            )
            return
        }

        let title = chatViewModel.activeSessionTitle
        tabs[index] = WorkspaceTab(
            id: tabs[index].id,
            key: .chatSession(sessionID),
            kind: .chat,
            title: title,
            payload: .chatSession(sessionID: sessionID, title: title)
        )
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

    func toggleTerminalForSelectedTab() {
        guard let selectedTabID,
              let terminalState = tabStates[selectedTabID]?.terminalState else {
            return
        }

        if terminalState.isPresented {
            closeTerminalForSelectedTab()
        } else {
            openTerminalForSelectedTab()
        }
    }

    func openTerminalForSelectedTab() {
        guard let selectedTabID,
              let terminalState = tabStates[selectedTabID]?.terminalState else {
            return
        }

        terminalState.isPresented = true
        ensureTerminalSessionStarted(for: selectedTabID)
    }

    func closeTerminalForSelectedTab() {
        guard let selectedTabID,
              let terminalState = tabStates[selectedTabID]?.terminalState else {
            return
        }

        terminalState.isPresented = false
    }

    func ensureTerminalSessionStarted(for tabID: WorkspaceTab.ID) {
        guard terminalSessions[tabID] == nil,
              let terminalState = tabStates[tabID]?.terminalState else {
            return
        }

        let workingDirectory = terminalWorkingDirectory(for: tabID)
        terminalState.workingDirectory = workingDirectory
        let session = WorkspaceTerminalSession(
            id: terminalState.sessionID,
            workingDirectory: workingDirectory
        )
        session.startIfNeeded()
        terminalSessions[tabID] = session
    }

    func registerTerminalHost(_ host: WorkspaceTerminalHosting, for tabID: WorkspaceTab.ID) {
        terminalHosts[tabID] = host
    }

    func makeTerminalHostView(for tabID: WorkspaceTab.ID) -> AnyView {
        guard let session = terminalSessions[tabID] else {
            return AnyView(
                Text("Project directory unavailable")
            )
        }

        #if os(macOS)
        return AnyView(
            WorkspaceTerminalMacHostView(session: session) { host in
                self.registerTerminalHost(host, for: tabID)
                host.focus()
            }
        )
        #else
        return AnyView(
            Text("Terminal host is not available on this platform yet.")
        )
        #endif
    }

    func closeTab(_ tabID: WorkspaceTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            return
        }

        terminalSessions[tabID]?.terminate()
        terminalSessions.removeValue(forKey: tabID)
        terminalHosts.removeValue(forKey: tabID)

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
        let viewModel = ChatScreenViewModel(
            apiClient: apiClient,
            cacheStore: cacheStore,
            settings: settings,
            connectionMonitor: connectionMonitor,
            restoresLastSession: false,
            onSessionSummaryChange: { [weak self] summary in
                self?.chatViewModel.mergeSessionSummary(summary)
            },
            onOpenSettings: { destination in self.onOpenSettings(destination) }
        )
        viewModel.loadInitialData()
        return ChatTabState(viewModel: viewModel)
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
        let workspaceState = makeWorkspaceFilesTabState()
        let tab = WorkspaceTab(
            key: key,
            kind: .workspaceFiles,
            title: "\(context.projectName) Files",
            payload: .workspaceFiles(context)
        )
        showInSelectedTab(
            tab,
            state: WorkspaceTabState(contentState: .workspaceFiles(workspaceState))
        )
    }

    func resolveWorkingDirectory(for tabID: WorkspaceTab.ID) -> URL? {
        guard let tab = tabs.first(where: { $0.id == tabID }) else {
            return nil
        }

        let projectRootPath: String?
        switch tab.payload {
        case .workspaceFiles(let context):
            projectRootPath = context.projectRootPath
        case .projectKanban(let context):
            projectRootPath = context.projectRootPath
        case .chatTask(_, _, let payloadProjectRootPath, _, _, _):
            projectRootPath = payloadProjectRootPath
        case .taskDetail(let context):
            projectRootPath = context.projectRootPath
        case .chatSession:
            guard let chatState = tabStates[tab.id]?.chatState,
                  let projectId = chatState.viewModel.activeProjectIdForWorkspacePanel else {
                return nil
            }
            projectRootPath = projects.first(where: { $0.id == projectId })?.projectRootPath
        }

        guard let projectRootPath, !projectRootPath.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: projectRootPath, isDirectory: true)
    }

    func terminalWorkingDirectory(for tabID: WorkspaceTab.ID) -> URL {
        resolveWorkingDirectory(for: tabID)
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
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

    private func showInSelectedTab(_ tab: WorkspaceTab, state: WorkspaceTabState) {
        guard let selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else {
            tabs.append(tab)
            tabStates[tab.id] = state
            self.selectedTabID = tab.id
            return
        }

        clearDesktopSplit()
        terminalSessions[selectedTabID]?.terminate()
        terminalSessions.removeValue(forKey: selectedTabID)
        terminalHosts.removeValue(forKey: selectedTabID)

        tabs[index] = WorkspaceTab(
            id: selectedTabID,
            key: tab.key,
            kind: tab.kind,
            title: tab.title,
            payload: tab.payload
        )
        tabStates[selectedTabID] = state
    }

    private func activeWorkspaceFilesContext() -> WorkspaceFilesTabContext? {
        guard let selectedTabID,
              let tab = tabs.first(where: { $0.id == selectedTabID }) else {
            return nil
        }

        switch tab.payload {
        case .projectKanban(let context):
            return WorkspaceFilesTabContext(
                projectId: context.projectId,
                projectName: context.projectName,
                projectRootPath: context.projectRootPath
            )
        case .workspaceFiles(let context):
            return context
        case .chatTask(let projectId, let projectName, let projectRootPath, _, _, _):
            return WorkspaceFilesTabContext(
                projectId: projectId,
                projectName: projectName,
                projectRootPath: projectRootPath
            )
        case .taskDetail(let context):
            return WorkspaceFilesTabContext(
                projectId: context.projectId,
                projectName: context.projectName,
                projectRootPath: context.projectRootPath
            )
        case .chatSession:
            guard let chatState = tabStates[tab.id]?.chatState,
                  let projectId = chatState.viewModel.activeProjectIdForWorkspacePanel,
                  let projectName = chatState.viewModel.activeProjectNameForWorkspacePanel else {
                return nil
            }
            return WorkspaceFilesTabContext(
                projectId: projectId,
                projectName: projectName,
                projectRootPath: projects.first(where: { $0.id == projectId })?.projectRootPath
            )
        }
    }
}
