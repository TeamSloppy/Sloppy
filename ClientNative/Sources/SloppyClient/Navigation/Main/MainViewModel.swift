//
//  MainViewModel.swift
//  SloppyClient
//
//  Created by Vladislav Prusakov on 05.07.2026.
//

import Observation
import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat
import SloppyFeatureProjects

enum MainAppSection: String, CaseIterable, Hashable {
    case scheduled
    case artifacts
    case sites
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
    let endpoint: SloppyInstanceEndpoint
    let settings: ClientSettings
    let connectionMonitor: ConnectionMonitor
    let onOpenSettings: @MainActor (ClientSettingsDestination) -> Void
    let onOpenWorkspace: @MainActor () -> Void
    let cacheStore: ClientCacheStore

    var projects: [APIProjectRecord] = []
    var isLoadingProjects = false
    var isProjectEditorPresented = false
    var isNewChatInstancePickerPresented = false
    var projectBeingEdited: APIProjectRecord?
    var didLoadProjects = false
    var collapsedProjectIds: Set<String> = []
    var expandedTaskLists: Set<String> = []
    var visibleProjectCount = 6
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
    var projectModeStates: [String: ProjectKanbanTabState] = [:]
    var terminalSessions: [WorkspaceTab.ID: WorkspaceTerminalSession] = [:]
    var terminalHosts: [WorkspaceTab.ID: WorkspaceTerminalHosting] = [:]
    var tabEndpoints: [WorkspaceTab.ID: SloppyInstanceEndpoint] = [:]
    var chatViewModel: ChatScreenViewModel
    var workspacePanelViewModel: WorkspacePanelViewModel
    var chatNavigationSerial = 0
    var projectActionStatus: String?
    private var pendingNewChatStarterPrompt: String?
    var currentAuthUser: AuthUserProfile?
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

    var selectedChatStorageID: String? {
        guard let selectedTabID,
              let sessionID = tabStates[selectedTabID]?.chatState?.viewModel.selectedSessionId else {
            return nil
        }
        let tabEndpoint = tabEndpoints[selectedTabID] ?? endpoint
        return chatViewModel.sessionCatalog.first {
            $0.id == sessionID
                && ($0.sourceInstanceID.flatMap(endpoint(for:)) ?? endpoint) == tabEndpoint
        }?.storageID ?? sessionID
    }

    var projectEditorEndpoint: SloppyInstanceEndpoint {
        projectBeingEdited?.sourceInstanceID.flatMap(endpoint(for:)) ?? endpoint
    }

    var sidebarSessionCatalog: [ChatSessionSummary] {
        chatViewModel.sessionCatalog.filter { !settings.isSessionArchived($0.storageID) }
    }

    var chatSidebarMode: ChatSidebarListMode {
        get { settings.chatSidebarMode }
        set { settings.chatSidebarMode = newValue }
    }

    init(
        endpoint: SloppyInstanceEndpoint,
        settings: ClientSettings,
        connectionMonitor: ConnectionMonitor,
        cacheStore: ClientCacheStore = ClientCacheStore(),
        onOpenSettings: @Sendable @escaping @MainActor (ClientSettingsDestination) -> Void,
        onOpenWorkspace: @escaping @MainActor () -> Void
    ) {
        let apiClient = SloppyAPIClient(endpoint: endpoint)
        self.endpoint = endpoint
        self.baseURL = endpoint.coordinatorBaseURL
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

    var selectedInstanceTitle: String {
        switch settings.instanceSelection {
        case .all:
            return "All"
        case .instance(let id):
            return settings.discoveredInstances.first(where: { $0.id == id })?.displayName ?? id
        }
    }

    var selectedInstance: SloppyInstance? {
        settings.selectedInstance
    }

    func instanceTitle(for sourceInstanceID: String?) -> String? {
        guard settings.instanceSelection == .all,
              let sourceInstanceID else { return nil }
        return settings.discoveredInstances.first { $0.id == sourceInstanceID }?.displayName
            ?? sourceInstanceID
    }

    func selectInstance(_ selection: SloppyInstanceSelection) {
        settings.instanceSelection = selection
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
        if settings.instanceSelection == .all,
           settings.discoveredInstances.count > 1 {
            isNewChatInstancePickerPresented = true
        } else {
            showBlankChatInSelectedTab(endpoint: endpoint)
            applyPendingNewChatStarterPrompt()
        }
    }

    func selectNewChat(on instance: SloppyInstance) {
        isNewChatInstancePickerPresented = false
        showBlankChatInSelectedTab(endpoint: instance.endpoint)
        applyPendingNewChatStarterPrompt()
        requestSelectedComposerFocus()
    }

    func selectChatSession(_ session: ChatSessionSummary) {
        selectAppSection(.chats)
        updateSelectedSidebarItem(.chats)
        dismissMobileSidebar()
        openSessionChatTab(session)
    }

    func deleteChatSession(_ session: ChatSessionSummary) {
        guard let instanceID = session.sourceInstanceID,
              let sourceEndpoint = endpoint(for: instanceID),
              sourceEndpoint != endpoint else {
            chatViewModel.deleteSession(session)
            return
        }
        Task {
            do {
                try await SloppyAPIClient(endpoint: sourceEndpoint).deleteAgentSession(
                    agentId: session.agentId,
                    sessionId: session.id
                )
                chatViewModel.removeSessionFromCatalog(session)
            } catch {
                projectActionStatus = "Could not delete remote chat: \(error.localizedDescription)"
            }
        }
    }

    func togglePinChatSession(_ session: ChatSessionSummary) {
        let nextPinned = !settings.isSessionPinned(session.storageID)
        settings.setSessionPinned(session.storageID, isPinned: nextPinned)
    }

    func copyDebugSessionFileLink(_ session: ChatSessionSummary) {
        chatViewModel.copyDebugSessionFileLink(session)
    }

    func hasVisibleChats(in project: APIProjectRecord) -> Bool {
        chatViewModel.sessionCatalog.contains {
            $0.projectId == project.id
                && $0.sourceInstanceID == project.sourceInstanceID
                && !settings.isSessionArchived($0.storageID)
        }
    }

    func hasArchivedChats(in project: APIProjectRecord) -> Bool {
        chatViewModel.sessionCatalog.contains {
            $0.projectId == project.id
                && $0.sourceInstanceID == project.sourceInstanceID
                && settings.isSessionArchived($0.storageID)
        }
    }

    func toggleProjectChatsArchived(_ project: APIProjectRecord) {
        let projectSessions = chatViewModel.sessionCatalog.filter {
            $0.projectId == project.id && $0.sourceInstanceID == project.sourceInstanceID
        }
        guard !projectSessions.isEmpty else {
            projectActionStatus = "No chats to archive in \(project.name)"
            return
        }

        let shouldArchive = projectSessions.contains { !settings.isSessionArchived($0.storageID) }
        for session in projectSessions {
            settings.setSessionArchived(session.storageID, isArchived: shouldArchive)
        }
        projectActionStatus = shouldArchive
            ? "Archived chats in \(project.name)"
            : "Restored chats in \(project.name)"
    }

    func openSessionChatTab(_ session: ChatSessionSummary) {
        selectAppSection(.chats)
        updateSelectedSidebarItem(.chats)
        dismissMobileSidebar()

        let sourceEndpoint = session.sourceInstanceID.flatMap(endpoint(for:)) ?? endpoint
        let chatState = makeChatTabState(endpoint: sourceEndpoint)
        chatState.viewModel.openSessionFromSummary(session)
        let tab = WorkspaceTab(
            key: .chatSession(session.storageID),
            kind: .chat,
            title: session.title,
            payload: .chatSession(sessionID: session.id, title: session.title)
        )
        showInSelectedTab(
            tab,
            state: WorkspaceTabState(contentState: .chat(chatState)),
            endpoint: sourceEndpoint
        )
    }

    func selectProject(_ project: APIProjectRecord) {
        openProjectKanbanTab(project: project)
    }

    func openProjectKanbanTab(project: APIProjectRecord) {
        selectAppSection(.projects)
        updateSelectedSidebarItem(.project(scopedProjectID(project)))
        dismissMobileSidebar()
        let key = WorkspaceTabKey.projectKanban(scopedProjectID(project))

        let kanbanState = projectModeState(for: project)
        activateProjectModeSection(kanbanState.selectedSection, project: project, state: kanbanState)
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
            state: WorkspaceTabState(contentState: .projectKanban(kanbanState)),
            endpoint: project.sourceInstanceID.flatMap(endpoint(for:)) ?? endpoint
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

    func toggleProjectPinned(_ project: APIProjectRecord) {
        Task {
            do {
                let client = apiClient(for: project)
                var updated = try await client.updateProject(
                    id: project.id,
                    request: APIProjectUpdateRequest(isFavorite: !project.isFavorite)
                )
                updated.sourceInstanceID = project.sourceInstanceID
                replaceProject(updated)
                prioritizeFavoriteProjects()
                projectActionStatus = updated.isFavorite
                    ? "Pinned \(updated.name)"
                    : "Unpinned \(updated.name)"
            } catch {
                projectActionStatus = "Could not update \(project.name): \(error.localizedDescription)"
            }
        }
    }

    func revealProjectInFinder(_ project: APIProjectRecord) {
        #if os(macOS)
        guard let path = project.projectRootPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            projectActionStatus = "No local folder configured for \(project.name)"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: path, isDirectory: true)
        ])
        #else
        projectActionStatus = "Reveal in Finder is only available on macOS"
        #endif
    }

    func createPermanentWorktree(for project: APIProjectRecord) {
        let worktreeID = "permanent-\(UUID().uuidString.lowercased())"
        Task {
            do {
                let worktree = try await apiClient(for: project).createPermanentWorktree(
                    projectId: project.id,
                    taskId: worktreeID
                )
                projectActionStatus = "Created worktree \(worktree.branchName)"
                #if os(macOS)
                NSWorkspace.shared.activateFileViewerSelecting([
                    URL(fileURLWithPath: worktree.worktreePath, isDirectory: true)
                ])
                #endif
            } catch {
                projectActionStatus = "Could not create worktree: \(error.localizedDescription)"
            }
        }
    }

    func removeProject(_ project: APIProjectRecord) {
        Task {
            do {
                try await apiClient(for: project).deleteProject(id: project.id)
                let scopedID = scopedProjectID(project)
                let projectEndpoint = project.sourceInstanceID.flatMap(endpoint(for:)) ?? endpoint
                let tabIDs = tabs.filter {
                    $0.key == .projectKanban(scopedID)
                        || (tabEndpoints[$0.id] == projectEndpoint && tabBelongsToProject($0, projectID: project.id))
                }.map(\.id)
                for tabID in tabIDs {
                    closeTab(tabID)
                }
                projects.removeAll { scopedProjectID($0) == scopedID }
                collapsedProjectIds.remove(scopedID)
                expandedTaskLists.remove(scopedID)
                projectModeStates.removeValue(forKey: scopedID)
                settings.projectModeSections.removeValue(forKey: scopedID)
                persistProjectOrder()
                await cacheStore.cacheProjects(projects)
                if selectedSidebarItem == .project(scopedID) {
                    selectedSidebarItem = .chats
                    selectedAppSection = .chats
                }
                projectActionStatus = "Removed \(project.name)"
            } catch {
                projectActionStatus = "Could not remove \(project.name): \(error.localizedDescription)"
            }
        }
    }

    func didSaveProject(_ project: APIProjectRecord) {
        if let index = projects.firstIndex(where: { scopedProjectID($0) == scopedProjectID(project) }) {
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

        let projectEndpoint = project.sourceInstanceID.flatMap(endpoint(for:)) ?? endpoint
        let chatState = makeChatTabState(endpoint: projectEndpoint)
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
            state: WorkspaceTabState(contentState: .chat(chatState)),
            endpoint: projectEndpoint
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
        let projectEndpoint = project.sourceInstanceID.flatMap(endpoint(for:)) ?? endpoint
        let key = WorkspaceTabKey.chatTask(projectId: project.storageID, taskId: task.id)

        let chatState = makeChatTabState(endpoint: projectEndpoint)
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
            state: WorkspaceTabState(contentState: .chat(chatState)),
            endpoint: projectEndpoint
        )
    }

    func openTaskDetailTab(project: APIProjectRecord, task: APIProjectTask, fallbackAgentId: String?) {
        selectAppSection(.projects)
        updateSelectedSidebarItem(.task(projectId: project.id, taskId: task.id))
        dismissMobileSidebar()
        let projectEndpoint = project.sourceInstanceID.flatMap(endpoint(for:)) ?? endpoint
        let key = WorkspaceTabKey.taskDetail(projectId: project.storageID, taskId: task.id)

        let detailState = makeTaskDetailTabState(endpoint: projectEndpoint)
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
            state: WorkspaceTabState(contentState: .taskDetail(detailState)),
            endpoint: projectEndpoint
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
        visibleProjectCount += 6
    }

    @discardableResult
    func moveProject(_ projectID: String, relativeTo targetProjectID: String) -> Bool {
        guard projectID != targetProjectID,
              let sourceIndex = projects.firstIndex(where: { scopedProjectID($0) == projectID }),
              let targetIndex = projects.firstIndex(where: { scopedProjectID($0) == targetProjectID }) else {
            return false
        }

        let project = projects.remove(at: sourceIndex)
        guard let remainingTargetIndex = projects.firstIndex(where: { scopedProjectID($0) == targetProjectID }) else {
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
        await loadCurrentAccount()
        if chatViewModel.selectedAgent == nil {
            chatViewModel.loadInitialData()
        } else {
            await chatViewModel.refreshCurrentContext()
        }
        await loadAggregatedChatCatalogIfNeeded()
    }

    func loadCurrentAccount() async {
        currentAuthUser = await AuthSessionStore.shared.session(for: baseURL)?.user
    }

    func requestChatScrollToEnd(for tabID: WorkspaceTab.ID) {
        tabStates[tabID]?.chatState?.viewModel.requestTranscriptScrollToEnd()
    }

    func requestSelectedComposerFocus() {
        guard let selectedTabID,
              let chatViewModel = tabStates[selectedTabID]?.chatState?.viewModel else {
            return
        }
        chatViewModel.requestComposerFocus()
    }

    func loadProjects(force: Bool = false) async {
        guard force || !didLoadProjects else { return }
        guard !isLoadingProjects else { return }

        isLoadingProjects = true
        if !force {
            projects = reconcileProjectOrder(await cacheStore.loadProjects())
            didLoadProjects = true
            visibleProjectCount = 6
        }

        defer {
            didLoadProjects = true
            isLoadingProjects = false
        }

        do {
            let list = try await fetchProjectsForCurrentSelection()
            projects = reconcileProjectOrder(list)
            await cacheStore.cacheProjects(projects)
        } catch {
            // The cached project snapshot remains available while offline.
        }
        visibleProjectCount = 6
    }

    func loadAggregatedChatCatalogIfNeeded() async {
        let catalogInstances: [SloppyInstance]
        switch settings.instanceSelection {
        case .all:
            catalogInstances = settings.discoveredInstances
        case .instance(let instanceID):
            catalogInstances = settings.discoveredInstances.filter { $0.id == instanceID }
        }
        guard !catalogInstances.isEmpty else { return }

        let batches = await withTaskGroup(of: [ChatSessionSummary].self) { group in
            for instance in catalogInstances {
                group.addTask {
                    let client = SloppyAPIClient(endpoint: instance.endpoint)
                    guard let agents = try? await client.fetchAgents() else { return [] }
                    var summaries: [ChatSessionSummary] = []
                    for agent in agents {
                        guard let sessions = try? await client.fetchAgentSessions(agentId: agent.id) else {
                            continue
                        }
                        summaries += sessions.map { session in
                            var tagged = session
                            tagged.sourceInstanceID = instance.id
                            return tagged
                        }
                    }
                    return summaries
                }
            }

            var result: [[ChatSessionSummary]] = []
            for await batch in group { result.append(batch) }
            return result
        }
        chatViewModel.installAggregatedSessionCatalog(ChatSessionCatalog.merge(batches))
    }

    private func fetchProjectsForCurrentSelection() async throws -> [APIProjectRecord] {
        guard settings.instanceSelection == .all,
              settings.discoveredInstances.count > 1 else {
            return try await apiClient.fetchProjects()
        }

        return await withTaskGroup(of: [APIProjectRecord].self) { group in
            for instance in settings.discoveredInstances {
                group.addTask {
                    let client = SloppyAPIClient(endpoint: instance.endpoint)
                    guard let projects = try? await client.fetchProjects() else { return [] }
                    return projects.map { project in
                        var tagged = project
                        tagged.sourceInstanceID = instance.id
                        return tagged
                    }
                }
            }
            var result: [APIProjectRecord] = []
            for await projects in group { result += projects }
            return result
        }
    }

    private func endpoint(for instanceID: String) -> SloppyInstanceEndpoint? {
        settings.discoveredInstances.first(where: { $0.id == instanceID })?.endpoint
    }

    private func apiClient(for project: APIProjectRecord) -> SloppyAPIClient {
        guard let instanceID = project.sourceInstanceID,
              let sourceEndpoint = endpoint(for: instanceID) else {
            return apiClient
        }
        return SloppyAPIClient(endpoint: sourceEndpoint)
    }

    func project(for tabID: WorkspaceTab.ID, localProjectID: String) -> APIProjectRecord? {
        let sourceEndpoint = tabEndpoints[tabID] ?? endpoint
        return projects.first { project in
            guard project.id == localProjectID else { return false }
            let projectEndpoint = project.sourceInstanceID.flatMap(endpoint(for:)) ?? endpoint
            return projectEndpoint == sourceEndpoint
        }
    }

    private func scopedProjectID(_ project: APIProjectRecord) -> String {
        project.storageID
    }

    private func reconcileProjectOrder(_ availableProjects: [APIProjectRecord]) -> [APIProjectRecord] {
        let projectsByID = Dictionary(uniqueKeysWithValues: availableProjects.map { (scopedProjectID($0), $0) })
        let savedIDs = settings.projectOrderIDs.filter { projectsByID[$0] != nil }
        let savedIDSet = Set(savedIDs)
        let newProjects = availableProjects.filter { !savedIDSet.contains(scopedProjectID($0)) }
        let orderedProjects = newProjects + savedIDs.compactMap { projectsByID[$0] }
        let prioritizedProjects = orderedProjects.filter(\.isFavorite) + orderedProjects.filter { !$0.isFavorite }
        settings.projectOrderIDs = prioritizedProjects.map(scopedProjectID)
        return prioritizedProjects
    }

    private func persistProjectOrder() {
        settings.projectOrderIDs = projects.map(scopedProjectID)
    }

    private func replaceProject(_ project: APIProjectRecord) {
        guard let index = projects.firstIndex(where: { scopedProjectID($0) == scopedProjectID(project) }) else {
            projects.append(project)
            return
        }
        projects[index] = project
    }

    private func prioritizeFavoriteProjects() {
        projects = projects.filter(\.isFavorite) + projects.filter { !$0.isFavorite }
        persistProjectOrder()
        Task { await cacheStore.cacheProjects(projects) }
    }

    private func tabBelongsToProject(_ tab: WorkspaceTab, projectID: String) -> Bool {
        switch tab.payload {
        case .projectKanban(let context):
            return context.projectId == projectID
        case .workspaceFiles(let context):
            return context.projectId == projectID
        case .chatTask(let tabProjectID, _, _, _, _, _):
            return tabProjectID == projectID
        case .taskDetail(let context):
            return context.projectId == projectID
        case .chatSession:
            return tabStates[tab.id]?.chatState?.viewModel.activeProjectIdForWorkspacePanel == projectID
        }
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

    func selectSites() {
        selectedSidebarItem = .sites
        selectAppSection(.sites)
    }

    func createSiteFromChat() {
        pendingNewChatStarterPrompt = "Help me build this project as a static website and publish it with Sloppy Sites. Keep it private unless I explicitly choose public access."
        selectNewChat()
    }

    private func applyPendingNewChatStarterPrompt() {
        guard let prompt = pendingNewChatStarterPrompt,
              let selectedTabID,
              let chatViewModel = tabStates[selectedTabID]?.chatState?.viewModel else {
            return
        }
        pendingNewChatStarterPrompt = nil
        chatViewModel.useStarterPrompt(prompt)
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

    func showBlankChatInSelectedTab(endpoint: SloppyInstanceEndpoint? = nil) {
        let sourceEndpoint = endpoint ?? self.endpoint
        let chatState = makeChatTabState(endpoint: sourceEndpoint)
        let draftID = "draft-\(UUID().uuidString)"
        let tab = WorkspaceTab(
            key: .chatSession(draftID),
            kind: .chat,
            title: "New Chat",
            payload: .chatSession(sessionID: draftID, title: "New Chat")
        )
        showInSelectedTab(
            tab,
            state: WorkspaceTabState(contentState: .chat(chatState)),
            endpoint: sourceEndpoint
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
        let sourceInstanceID = (tabEndpoints[tabID] ?? endpoint).targetNodeID
            ?? settings.discoveredInstances.first(where: { $0.endpoint == (tabEndpoints[tabID] ?? endpoint) })?.id
        let storageSessionID = sourceInstanceID.map {
            InstanceScopedID(instanceID: $0, localID: sessionID).description
        } ?? sessionID
        tabs[index] = WorkspaceTab(
            id: tabs[index].id,
            key: .chatSession(storageSessionID),
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

        if terminalState.isPresented,
           terminalState.selectedPanel == .terminal {
            closeTerminalForSelectedTab()
        } else {
            openTerminalForSelectedTab()
        }
    }

    func openTerminalForSelectedTab() {
        openBottomPanel(.terminal)
    }

    func openBottomPanel(_ panel: WorkspaceBottomPanelKind) {
        guard let selectedTabID,
              let terminalState = tabStates[selectedTabID]?.terminalState else {
            return
        }

        terminalState.selectedPanel = panel
        terminalState.isPresented = true
        if panel == .terminal {
            ensureTerminalSessionStarted(for: selectedTabID)
        }
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
        let remoteConfiguration: WorkspaceTerminalSession.RemoteConfiguration?
        let tabEndpoint = tabEndpoints[tabID] ?? endpoint
        if case .relay(let coordinatorBaseURL, let targetNodeID) = tabEndpoint {
            remoteConfiguration = WorkspaceTerminalSession.RemoteConfiguration(
                apiClient: apiClient,
                coordinatorBaseURL: coordinatorBaseURL,
                targetNodeID: targetNodeID,
                projectID: projectID(for: tabID)
            )
        } else {
            remoteConfiguration = nil
        }
        let session = WorkspaceTerminalSession(
            id: terminalState.sessionID,
            workingDirectory: workingDirectory,
            remoteConfiguration: remoteConfiguration
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
        if session.remoteConfiguration != nil {
            return AnyView(
                WorkspaceRemoteTerminalMacHostView(session: session) { host in
                    self.registerTerminalHost(host, for: tabID)
                    host.focus()
                }
            )
        }
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
        tabEndpoints.removeValue(forKey: tabID)

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

    func makeChatTabState(endpoint: SloppyInstanceEndpoint? = nil) -> ChatTabState {
        let resolvedEndpoint = endpoint ?? self.endpoint
        let sourceInstanceID = settings.discoveredInstances.first(where: { $0.endpoint == resolvedEndpoint })?.id
        let apiClient = SloppyAPIClient(endpoint: resolvedEndpoint)
        let viewModel = ChatScreenViewModel(
            apiClient: apiClient,
            cacheStore: resolvedEndpoint == self.endpoint
                ? cacheStore
                : ClientCacheStore(namespace: resolvedEndpoint.cacheNamespace),
            settings: settings,
            connectionMonitor: connectionMonitor,
            restoresLastSession: false,
            onSessionSummaryChange: { [weak self] summary in
                var tagged = summary
                tagged.sourceInstanceID = sourceInstanceID
                self?.chatViewModel.mergeSessionSummary(tagged)
            },
            onOpenSettings: { destination in self.onOpenSettings(destination) }
        )
        viewModel.loadInitialData()
        return ChatTabState(viewModel: viewModel)
    }

    func selectProjectModeSection(_ section: ProjectModeSection, project: APIProjectRecord) {
        let state = projectModeState(for: project)
        guard state.selectedSection != section else { return }

        state.selectedSection = section
        settings.projectModeSections[scopedProjectID(project)] = section.rawValue
        activateProjectModeSection(section, project: project, state: state)
    }

    private func projectModeState(for project: APIProjectRecord) -> ProjectKanbanTabState {
        let projectStateID = scopedProjectID(project)
        if let state = projectModeStates[projectStateID] {
            return state
        }

        let projectEndpoint = project.sourceInstanceID.flatMap(endpoint(for:)) ?? endpoint
        let chatState = makeChatTabState(endpoint: projectEndpoint)
        chatNavigationSerial += 1
        applyNavigationRequestOnNextTurn(
            ChatNavigationRequest(
                id: chatNavigationSerial,
                context: .project(
                    projectId: project.id,
                    projectName: project.name,
                    agentId: project.actors?.first
                )
            ),
            to: chatState.viewModel,
            loadInitialData: true
        )

        let selectedSection = settings.projectModeSections[projectStateID]
            .flatMap(ProjectModeSection.init(rawValue:)) ?? .kanban
        let state = ProjectKanbanTabState(
            viewModel: ProjectKanbanViewModel(
                apiClient: SloppyAPIClient(endpoint: projectEndpoint),
                availableInstances: settings.discoveredInstances,
                preferredExecutionNodeID: project.sourceInstanceID ?? settings.instanceSelection.instanceID
            ),
            workspaceViewModel: CanvasWorkspaceViewModel(
                baseURL: baseURL,
                apiClient: SloppyAPIClient(endpoint: projectEndpoint)
            ),
            automationViewModel: ProjectAutomationViewModel(
                apiClient: SloppyAPIClient(endpoint: projectEndpoint)
            ),
            chatViewModel: chatState.viewModel,
            selectedSection: selectedSection
        )
        projectModeStates[projectStateID] = state
        return state
    }

    private func activateProjectModeSection(
        _ section: ProjectModeSection,
        project: APIProjectRecord,
        state: ProjectKanbanTabState
    ) {
        switch section {
        case .kanban:
            Task { await state.viewModel.load(projectId: project.id) }
        case .workspaces:
            Task {
                await state.workspaceViewModel.resolve(
                    workspaceID: nil,
                    projectID: project.id,
                    projectName: project.name
                )
            }
        case .automation:
            Task { await state.automationViewModel.load(projectId: project.id) }
        case .chats:
            break
        }
    }

    func makeWorkspaceFilesTabState(endpoint: SloppyInstanceEndpoint? = nil) -> WorkspaceFilesTabState {
        let apiClient = SloppyAPIClient(endpoint: endpoint ?? self.endpoint)
        return WorkspaceFilesTabState(viewModel: WorkspacePanelViewModel(apiClient: apiClient))
    }

    func makeTaskDetailTabState(endpoint: SloppyInstanceEndpoint? = nil) -> TaskDetailTabState {
        let apiClient = SloppyAPIClient(endpoint: endpoint ?? self.endpoint)
        return TaskDetailTabState(viewModel: TaskDetailViewModel(apiClient: apiClient))
    }

    func openWorkspaceTabForSelectedContext() {
        guard let context = activeWorkspaceFilesContext() else {
            return
        }

        let sourceEndpoint = selectedTabID.flatMap { tabEndpoints[$0] } ?? endpoint
        let sourceInstanceID = settings.discoveredInstances.first(where: { $0.endpoint == sourceEndpoint })?.id
        let scopedProjectID = sourceInstanceID.map {
            InstanceScopedID(instanceID: $0, localID: context.projectId).description
        } ?? context.projectId
        let key = WorkspaceTabKey.workspaceFiles(scopedProjectID)
        let workspaceState = makeWorkspaceFilesTabState(endpoint: sourceEndpoint)
        let tab = WorkspaceTab(
            key: key,
            kind: .workspaceFiles,
            title: "\(context.projectName) Files",
            payload: .workspaceFiles(context)
        )
        showInSelectedTab(
            tab,
            state: WorkspaceTabState(contentState: .workspaceFiles(workspaceState)),
            endpoint: sourceEndpoint
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
        let fallback = {
            #if os(macOS)
            return FileManager.default.homeDirectoryForCurrentUser
            #else
            return URL.applicationDirectory 
            #endif
        }()
        return resolveWorkingDirectory(for: tabID) ?? fallback
    }

    private func projectID(for tabID: WorkspaceTab.ID) -> String? {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return nil }
        switch tab.payload {
        case .projectKanban(let context):
            return context.projectId
        case .workspaceFiles(let context):
            return context.projectId
        case .chatTask(let projectId, _, _, _, _, _):
            return projectId
        case .taskDetail(let context):
            return context.projectId
        case .chatSession:
            return tabStates[tabID]?.chatState?.viewModel.activeProjectIdForWorkspacePanel
        }
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

    private func showInSelectedTab(
        _ tab: WorkspaceTab,
        state: WorkspaceTabState,
        endpoint sourceEndpoint: SloppyInstanceEndpoint? = nil
    ) {
        guard let selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else {
            tabs.append(tab)
            tabStates[tab.id] = state
            if let sourceEndpoint {
                tabEndpoints[tab.id] = sourceEndpoint
            }
            self.selectedTabID = tab.id
            return
        }

        clearDesktopSplit()
        terminalSessions[selectedTabID]?.terminate()
        terminalSessions.removeValue(forKey: selectedTabID)
        terminalHosts.removeValue(forKey: selectedTabID)
        if let sourceEndpoint {
            tabEndpoints[selectedTabID] = sourceEndpoint
        } else {
            tabEndpoints.removeValue(forKey: selectedTabID)
        }

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
