import Foundation
import SwiftUI
import Observation
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureAgents
import SloppyFeatureChat
import SloppyFeatureProjects
import SloppyFeatureSettings

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
    var selectedAppSection: MainAppSection = .projects
    var selectedSidebarItem: MainSidebarSelection? = nil
    var isSidebarCollapsed = false
    var isMobileSidebarPresented = false
    var tabs: [WorkspaceTab] = []
    var selectedTabID: WorkspaceTab.ID?
    var chatTabStates: [WorkspaceTab.ID: ChatTabState] = [:]
    var projectKanbanTabStates: [WorkspaceTab.ID: ProjectKanbanTabState] = [:]
    var workspaceTabStates: [WorkspaceTab.ID: WorkspaceFilesTabState] = [:]
    var chatViewModel: ChatScreenViewModel
    var workspacePanelViewModel: WorkspacePanelViewModel
    var chatNavigationSerial = 0

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
    }

    func openMobileSidebar() {
        isSidebarCollapsed = false
        isMobileSidebarPresented = true
    }

    func dismissMobileSidebar() {
        guard isMobileSidebarPresented else {
            return
        }
        isMobileSidebarPresented = false
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
        chatTabStates[tab.id] = chatState
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
        projectKanbanTabStates[tab.id] = kanbanState
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
        let key = WorkspaceTabKey.chatTask(projectId: project.id, taskId: task.id)
        if let existing = tabs.first(where: { $0.key == key }) {
            selectedTabID = existing.id
            return
        }

        let chatState = makeChatTabState()
        chatState.viewModel.applyNavigationRequest(
            ChatNavigationRequest(
                id: Int.random(in: Int.min ... Int.max),
                context: .task(
                    projectId: project.id,
                    projectName: project.name,
                    taskId: task.id,
                    taskTitle: task.title,
                    agentId: task.actorId ?? fallbackAgentId
                )
            )
        )
        chatState.viewModel.loadInitialData()
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
        chatTabStates[tab.id] = chatState
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
        await chatViewModel.refreshCurrentContext()
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
        selectedTabID = tabID
    }

    func closeTab(_ tabID: WorkspaceTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            return
        }

        let wasSelected = selectedTabID == tabID
        tabs.remove(at: index)
        chatTabStates.removeValue(forKey: tabID)
        projectKanbanTabStates.removeValue(forKey: tabID)
        workspaceTabStates.removeValue(forKey: tabID)

        guard wasSelected else {
            return
        }

        if tabs.isEmpty {
            selectedTabID = nil
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
        workspaceTabStates[tab.id] = workspaceState
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
        chatViewModel.applyNavigationRequest(
            ChatNavigationRequest(id: chatNavigationSerial, context: context)
        )
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
        case .chatSession:
            guard let chatState = chatTabStates[tab.id],
                  let projectId = chatState.viewModel.activeProjectIdForWorkspacePanel,
                  let projectName = chatState.viewModel.activeProjectNameForWorkspacePanel else {
                return nil
            }
            return WorkspaceFilesTabContext(projectId: projectId, projectName: projectName)
        }
    }
}

@MainActor
struct MainView: View {
    let rootSafeAreaInsets: EdgeInsets

    @State private var viewModel: MainViewModel

    @Environment(\.userInterfaceIdiom) private var idiom

    private var activeDesktopTab: WorkspaceTab? {
        guard let selectedTabID = viewModel.selectedTabID else {
            return nil
        }
        return viewModel.tabs.first(where: { $0.id == selectedTabID })
    }

    init(
        baseURL: URL,
        settings: ClientSettings,
        connectionMonitor: ConnectionMonitor,
        rootSafeAreaInsets: EdgeInsets = EdgeInsets(),
        onOpenSettings: @Sendable @escaping @MainActor () -> Void,
        onOpenWorkspace: @escaping @MainActor () -> Void
    ) {
        self.rootSafeAreaInsets = rootSafeAreaInsets
        _viewModel = State(
            initialValue: MainViewModel(
                baseURL: baseURL,
                settings: settings,
                connectionMonitor: connectionMonitor,
                onOpenSettings: onOpenSettings,
                onOpenWorkspace: onOpenWorkspace
            )
        )
    }

    var body: some View {
        Group {
            if idiom == .phone {
                phoneTabLayout()
            } else {
                regularSplitLayout()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            Task { await viewModel.loadProjects() }
        }
        .background {
            Button("") {
                Task { await viewModel.refreshContent() }
            }
            .keyboardShortcut("r", modifiers: [.command])
            .opacity(0.001)
            .allowsHitTesting(false)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(
                    action: {
                        viewModel.openWorkspaceTabForSelectedContext()
                    },
                    label: {
                        Image(systemName: "sidebar.right")
                    }
                )
            }
        }
    }

    private func regularSplitLayout() -> some View {
        return NavigationSplitView {
            sidebarView(isOverlay: false)
                .navigationSplitViewColumnWidth(
                    min: viewModel.sidebarMinimumWidth,
                    ideal: viewModel.sidebarWidth,
                    max: viewModel.sidebarMaximumWidth
                )
        } detail: {
            switch viewModel.selectedAppSection {
            case .projects, .chats, .workspace:
                desktopContentArea()
            case .agents:
                AgentsScreen(apiClient: SloppyAPIClient(baseURL: viewModel.baseURL))
            case .settings:
                SettingsScreen(settings: viewModel.settings)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func desktopContentArea() -> some View {
        VStack(spacing: 0) {
            DesktopTabStripView(viewModel: viewModel)
            Divider()

            if let activeDesktopTab {
                desktopTabContent(for: activeDesktopTab)
            } else {
                DesktopTabsEmptyState()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func desktopTabContent(for tab: WorkspaceTab) -> some View {
        switch tab.kind {
        case .chat:
            if let chatState = viewModel.chatTabStates[tab.id] {
                ChatScreen(viewModel: chatState.viewModel, rootSafeAreaInsets: rootSafeAreaInsets, onOpenSidebar: nil)
            } else {
                DesktopTabPlaceholderView(
                    title: tab.title,
                    detail: "Chat tab state is unavailable."
                )
            }
        case .projectKanban:
            if let kanbanState = viewModel.projectKanbanTabStates[tab.id],
               case .projectKanban(let context) = tab.payload {
                ProjectKanbanView(
                    viewModel: kanbanState.viewModel,
                    projectId: context.projectId,
                    projectName: context.projectName
                )
            } else {
                DesktopTabPlaceholderView(
                    title: tab.title,
                    detail: "Kanban tab state is unavailable."
                )
            }
        case .workspaceFiles:
            if let workspaceState = viewModel.workspaceTabStates[tab.id],
               case .workspaceFiles(let context) = tab.payload {
                WorkspacePanelView(
                    viewModel: workspaceState.viewModel,
                    context: WorkspacePanelContext(projectId: context.projectId, projectName: context.projectName)
                )
            } else {
                DesktopTabPlaceholderView(
                    title: tab.title,
                    detail: "Workspace tab state is unavailable."
                )
            }
        }
    }

    private func phoneTabLayout() -> some View {
        TabView(selection: $viewModel.selectedAppSection) {
            ProjectsScreen(apiClient: SloppyAPIClient(baseURL: viewModel.baseURL))
                .tabItem {
                    Image(systemName: "folder")
                    Text("Projects")
                }
                .tag(MainAppSection.projects)

            AgentsScreen(apiClient: SloppyAPIClient(baseURL: viewModel.baseURL))
                .tabItem {
                    Image(systemName: "sparkles")
                    Text("Agents")
                }
                .tag(MainAppSection.agents)

            chatScreen(showsSidebarControl: false)
                .tabItem {
                    Image(systemName: "message")
                    Text("Chats")
                }
                .tag(MainAppSection.chats)

            SettingsScreen(settings: viewModel.settings)
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .tag(MainAppSection.settings)
        }
    }

    private func chatScreen(showsSidebarControl: Bool) -> some View {
        let openSidebar: (@MainActor () -> Void)? = showsSidebarControl ? viewModel.openMobileSidebar : nil
        return ChatScreen(
            viewModel: viewModel.chatViewModel,
            rootSafeAreaInsets: rootSafeAreaInsets,
            onOpenSidebar: openSidebar
        )
    }

    private func sidebarView(isOverlay: Bool) -> some View {
        MainSidebarView(
            viewModel: viewModel,
            isOverlay: isOverlay
        )
    }

    @ViewBuilder
    private func workspaceScreen() -> some View {
        if let workspaceContext = viewModel.workspaceContext {
            WorkspacePanelView(
                viewModel: viewModel.workspacePanelViewModel,
                context: workspaceContext
            )
        } else {
            WorkspaceUnavailableView()
        }
    }
}

#Preview {
    RootShellView()
}

@MainActor
private struct DesktopTabStripView: View {
    let viewModel: MainViewModel

    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing.s) {
                ForEach(viewModel.tabs) { tab in
                    Button {
                        viewModel.selectTab(tab.id)
                    } label: {
                        Text(tab.title)
                            .font(.system(size: theme.typography.caption))
                            .foregroundColor(
                                viewModel.selectedTabID == tab.id
                                    ? theme.colors.textPrimary
                                    : theme.colors.textSecondary
                            )
                            .lineLimit(1)
                            .padding(.horizontal, theme.spacing.m)
                            .padding(.vertical, theme.spacing.s)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        viewModel.selectedTabID == tab.id
                                            ? theme.colors.surfaceRaised
                                            : theme.colors.surface
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, theme.spacing.m)
            .padding(.vertical, theme.spacing.s)
        }
        .background(theme.colors.surface.opacity(0.78 as CGFloat))
    }
}

@MainActor
private struct DesktopTabsEmptyState: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.m) {
            Icons.symbol(.folder, size: theme.typography.title)
                .foregroundColor(theme.colors.textMuted)
            Text("No tabs open")
                .font(.system(size: theme.typography.body))
                .foregroundColor(theme.colors.textPrimary)
            Text("Open a project, task, or recent chat from the sidebar.")
                .font(.system(size: theme.typography.caption))
                .foregroundColor(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private struct DesktopTabPlaceholderView: View {
    let title: String
    let detail: String

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.m) {
            Text(title)
                .font(.system(size: theme.typography.title))
                .foregroundColor(theme.colors.textPrimary)
            Text(detail)
                .font(.system(size: theme.typography.body))
                .foregroundColor(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private struct WorkspaceUnavailableView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.m) {
            Icons.symbol(.folder, size: theme.typography.title)
                .foregroundColor(theme.colors.textMuted)
            Text("Workspace is available when a project chat is active.")
                .font(.system(size: theme.typography.body))
                .foregroundColor(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
