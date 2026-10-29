import AdaEngine
import Observation
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat
import SloppyFeatureAgents
import SloppyFeatureProjects

@Observable
@MainActor
final class MainViewModel {
    let baseURL: URL
    let settings: ClientSettings
    let connectionMonitor: ConnectionMonitor
    let onOpenSettings: @MainActor () -> Void
    let onOpenWorkspace: @MainActor () -> Void
    let surface: WorkspaceSurfaceModel
    let terminal = WorkspaceTerminalSession()
    private var browsers: [UUID: WorkspaceBrowserModel] = [:]
    var browser: WorkspaceBrowserModel {
        if let model = browsers[navigation.selectedTabID] { return model }
        let model = WorkspaceBrowserModel()
        browsers[navigation.selectedTabID] = model
        return model
    }
    var workspaceProject: APIProjectRecord?
    var showsInspector = true
    var activeProject: APIProjectRecord? {
        if navigation.section == .project { return workspaceProject }
        return projects.first { $0.id == chatViewModel.selectedProjectId }
    }
    
    var projects: [APIProjectRecord] = []
    var isLoadingProjects = false
    var didLoadProjects = false
    var expandedTaskLists: Set<String> = []
    var selectedSidebarItem: MainSidebarSelection? = nil
    private var tabSidebarSelections: [UUID: MainSidebarSelection] = [:]
    var isSidebarCollapsed = false
    var isMobileSidebarPresented = false
    var navigation = WorkspaceNavigation()
    var searchText = ""
    var catalogSessions: [ChatSessionSummary] = []
    var catalogError: String?
    private let initialChatModel: ChatScreenViewModel
    var chatModels: [UUID: ChatScreenViewModel] = [:]
    var chatViewModel: ChatScreenViewModel {
        chatModels[navigation.selectedTabID] ?? initialChatModel
    }
    var sidebarContent: ChatSidebarContent {
        var sessions = catalogSessions
        for model in chatModels.values {
            for session in model.sessions {
                if let index = sessions.firstIndex(where: { $0.id == session.id && $0.agentId == session.agentId }) {
                    if session.updatedAt >= sessions[index].updatedAt { sessions[index] = session }
                } else {
                    sessions.append(session)
                }
            }
        }
        return ChatSidebarContent(sessions: sessions, pinnedIDs: settings.pinnedSessionIds, query: searchText)
    }
    var visibleProjects: [APIProjectRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return projects.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || !sidebarContent.sessions(in: $0.id).isEmpty }
    }
    var chatNavigationSerial = 0
    
    var sidebarWidth: Float {
        isSidebarCollapsed ? MainSidebarView.collapsedWidth : MainSidebarView.expandedWidth
    }
    
    var sidebarMinimumWidth: Float {
        isSidebarCollapsed ? MainSidebarView.collapsedWidth : MainSidebarView.minimumWidth
    }
    
    var sidebarMaximumWidth: Float {
        isSidebarCollapsed ? MainSidebarView.collapsedWidth : MainSidebarView.maximumWidth
    }
    
    init(
        baseURL: URL,
        settings: ClientSettings,
        connectionMonitor: ConnectionMonitor,
        onOpenSettings: @Sendable @escaping @MainActor () -> Void,
        onOpenWorkspace: @escaping @MainActor () -> Void
    ) {
        self.baseURL = baseURL
        self.settings = settings
        self.connectionMonitor = connectionMonitor
        self.onOpenSettings = onOpenSettings
        self.onOpenWorkspace = onOpenWorkspace
        surface = WorkspaceSurfaceModel(api: SloppyAPIClient(baseURL: baseURL))
        initialChatModel = ChatScreenViewModel(apiClient: SloppyAPIClient(baseURL: baseURL), settings: settings,
                                              connectionMonitor: connectionMonitor, onOpenSettings: onOpenSettings)
        chatModels[navigation.selectedTabID] = initialChatModel
    }

    private func makeChatModel(restoresLastSession: Bool) -> ChatScreenViewModel {
        ChatScreenViewModel(
            apiClient: SloppyAPIClient(baseURL: baseURL),
            settings: settings,
            connectionMonitor: connectionMonitor,
            onOpenSettings: onOpenSettings,
            restoresLastSession: restoresLastSession
        )
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
        let id = navigation.createChat()
        chatModels[id] = makeChatModel(restoresLastSession: false)
        updateSelectedSidebarItem(.chats)
        dismissMobileSidebar()
        navigateChat(.blank)
    }

    func openCanvasChat() {
        guard let canvas = surface.canvas.workspace else { return }
        Task {
            do {
                if let session = surface.canvas.chatSession { selectChatSession(session); return }
                let agents = try await surface.api.fetchAgents()
                guard let agentID = chatViewModel.selectedAgent?.id ?? agents.first?.id else { return }
                let session = try await surface.api.createAgentSession(agentId: agentID, title: canvas.title,
                    projectId: canvas.projectId, workspaceId: canvas.id)
                surface.canvas.chatSession = session
                selectChatSession(session)
            } catch { surface.canvas.error = error.localizedDescription }
        }
    }
    
    func selectChatSession(_ session: ChatSessionSummary) {
        if let existing = navigation.tabs.first(where: {
            chatModels[$0.id]?.selectedSessionId == session.id
                && chatModels[$0.id]?.selectedAgent?.id == session.agentId
        }) {
            navigation.selectChat(existing.id)
        } else {
            let id = navigation.createChat(title: session.title.isEmpty ? "Chat" : session.title)
            let model = makeChatModel(restoresLastSession: false)
            chatModels[id] = model
            model.openSessionWhenReady(session)
        }
        updateSelectedSidebarItem(.chats)
        dismissMobileSidebar()
    }
    
    func deleteChatSession(_ session: ChatSessionSummary) {
        Task {
            do {
                try await SloppyAPIClient(baseURL: baseURL).deleteAgentSession(agentId: session.agentId, sessionId: session.id)
                catalogSessions.removeAll { $0.id == session.id && $0.agentId == session.agentId }
                settings.setSessionPinned(session.id, isPinned: false)
                let matching = navigation.tabs.filter {
                    chatModels[$0.id]?.selectedSessionId == session.id && chatModels[$0.id]?.selectedAgent?.id == session.agentId
                }
                for tab in matching { closeTab(tab.id) }
                for model in chatModels.values { model.removeDeletedSession(session) }
                await refreshCatalog()
            } catch {
                catalogError = error.localizedDescription
            }
        }
    }
    
    func togglePinChatSession(_ session: ChatSessionSummary) {
        chatViewModel.toggleSessionPinned(session)
    }
    
    func copyDebugSessionFileLink(_ session: ChatSessionSummary) {
        chatViewModel.copyDebugSessionFileLink(session)
    }
    
    func selectProject(_ project: APIProjectRecord) {
        if workspaceProject?.id != project.id { surface.canvas.close(); surface.automationRuns = [] }
        workspaceProject = project
        surface.canvases = []
        surface.automations = []
        surface.projectSection = .kanban
        updateSelectedSidebarItem(.project(project.id))
        selectSection(.project)
    }

    func newProjectChat(_ project: APIProjectRecord) {
        let id = navigation.createChat(title: project.name)
        chatModels[id] = makeChatModel(restoresLastSession: false)
        updateSelectedSidebarItem(.project(project.id))
        dismissMobileSidebar()
        navigateChat(
            .project(
                projectId: project.id,
                projectName: project.name,
                agentId: project.actors?.first
            )
        )
    }
    
    func selectTask(
        projectId: String,
        projectName: String,
        task: APIProjectTask,
        fallbackAgentId: String?
    ) {
        let id = navigation.createChat(title: task.title)
        chatModels[id] = makeChatModel(restoresLastSession: false)
        updateSelectedSidebarItem(.task(projectId: projectId, taskId: task.id))
        dismissMobileSidebar()
        navigateChat(
            .task(
                projectId: projectId,
                projectName: projectName,
                taskId: task.id,
                taskTitle: task.title,
                agentId: task.actorId ?? fallbackAgentId
            )
        )
    }
    
    func toggleTaskList(projectId: String) {
        if expandedTaskLists.contains(projectId) {
            expandedTaskLists.remove(projectId)
        } else {
            expandedTaskLists.insert(projectId)
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
        do {
            projects = try await client.fetchProjects()
            catalogError = nil
        } catch {
            catalogError = error.localizedDescription
        }
        await refreshCatalog()
        chatViewModel.loadInitialData()
        
        if selectedSidebarItem == nil {
            selectedSidebarItem = .chats
        }
    }

    func refreshCatalog() async {
        do {
            let client = SloppyAPIClient(baseURL: baseURL)
            let agents = try await client.fetchAgents()
            var sessions: [ChatSessionSummary] = []
            for agent in agents {
                sessions += try await client.fetchAgentSessions(agentId: agent.id)
            }
            catalogSessions = sessions
        } catch {
            catalogError = error.localizedDescription
        }
    }

    func selectSection(_ section: WorkspaceSection) {
        navigation.section = section
        surface.query = ""
        Task { await surface.load(section, project: workspaceProject) }
        dismissMobileSidebar()
    }

    func selectProjectSection(_ section: ProjectWorkspaceSection) {
        guard let project = activeProject else { return }
        workspaceProject = project
        surface.projectSection = section
        selectSection(.project)
    }

    func beginCreation(_ kind: WorkspaceCreation) {
        surface.beginCreation(kind, agentID: chatViewModel.selectedAgent?.id,
                              channelID: activeProject?.channels?.first?.channelId)
    }

    func selectAgent(_ agent: APIAgentRecord) {
        selectNewChat()
        chatViewModel.loadInitialData()
        chatViewModel.applyNavigationRequest(ChatNavigationRequest(
            id: chatNavigationSerial + 1,
            context: .agent(agent.id)
        ))
        chatNavigationSerial += 1
    }

    func selectTab(_ id: UUID) {
        guard navigation.tabs.contains(where: { $0.id == id }) else { return }
        navigation.selectChat(id)
        selectedSidebarItem = tabSidebarSelections[id] ?? .chats
    }

    func closeTab(_ id: UUID) {
        if let browser = browsers.removeValue(forKey: id) { browser.bridgeTask?.cancel(); browser.stop() }
        guard navigation.tabs.contains(where: { $0.id == id }) else { return }
        chatModels[id]?.stop()
        chatModels.removeValue(forKey: id)
        tabSidebarSelections.removeValue(forKey: id)
        navigation.closeChat(id)
        selectedSidebarItem = tabSidebarSelections[navigation.selectedTabID] ?? .chats
        if chatModels[navigation.selectedTabID] == nil {
            chatModels[navigation.selectedTabID] = makeChatModel(restoresLastSession: false)
        }
    }

    func updateActiveTabTitle() {
        let model = chatViewModel
        let title = model.activeContextTitle
            ?? model.sessions.first(where: { $0.id == model.selectedSessionId })?.title
            ?? "New chat"
        navigation.renameChat(navigation.selectedTabID, title: title)
    }
    
    private func updateSelectedSidebarItem(_ selection: MainSidebarSelection) {
        guard selectedSidebarItem != selection else {
            return
        }
        selectedSidebarItem = selection
        tabSidebarSelections[navigation.selectedTabID] = selection
    }

    func stop() {
        for model in chatModels.values { model.stop() }
    }
    
    private func navigateChat(_ context: ChatNavigationRequest.Context) {
        chatNavigationSerial += 1
        chatViewModel.applyNavigationRequest(
            ChatNavigationRequest(id: chatNavigationSerial, context: context)
        )
    }
}

@MainActor
struct MainView: View {
    let rootSafeAreaInsets: EdgeInsets
    
    @State private var viewModel: MainViewModel
    
    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme
    
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
                fullScreenCompactLayout()
            } else {
                regularSplitLayout()
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                Task { await viewModel.loadProjects() }
            }
            .onDisappear { viewModel.stop() }
            .keyboardShortcuts([
                KeyboardShortcutAction(.t, modifiers: workspaceModifiers, action: viewModel.selectNewChat),
                KeyboardShortcutAction(.w, modifiers: workspaceModifiers, action: {
                    viewModel.closeTab(viewModel.navigation.selectedTabID)
                }),
            ])
            .background(theme.colors.background)
    }

    private var workspaceModifiers: KeyModifier {
        #if os(Windows) || os(Linux)
        .control
        #else
        .command
        #endif
    }
    
    private func regularSplitLayout() -> some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                sidebarView(isOverlay: false).frame(width: MainSidebarView.expandedWidth, height: geometry.size.height)
                theme.colors.border.frame(width: 1, height: geometry.size.height)
                workspaceContent(showsSidebarControl: false)
                    .frame(width: max(0, geometry.size.width - MainSidebarView.expandedWidth - 1), height: geometry.size.height)
            }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }

    private func fullScreenCompactLayout() -> some View {
        ZStack {
            if viewModel.isMobileSidebarPresented {
                sidebarView(isOverlay: true)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            } else {
                workspaceContent(showsSidebarControl: true)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            }
        }
    }

    private func workspaceContent(showsSidebarControl: Bool) -> some View {
        VStack(spacing: 0) {
            WorkspaceToolbar(viewModel: viewModel, showsSidebarControl: showsSidebarControl)
            if viewModel.navigation.tabs.count > 1 { WorkspaceTabStrip(viewModel: viewModel) }
            GeometryReader { geometry in
                let inspectorWidth: Float = viewModel.showsInspector && geometry.size.width >= 920 ? 280 : 0
                let toolWidth: Float = viewModel.surface.tool == nil ? 0 : min(420, geometry.size.width * 0.4)
                HStack(spacing: 0) {
                    workspaceBody(showsSidebarControl: showsSidebarControl)
                        .frame(width: max(0, geometry.size.width - inspectorWidth - toolWidth), height: geometry.size.height)
                    if inspectorWidth > 0 {
                        WorkspaceInspector(viewModel: viewModel).frame(width: 280)
                    }
                    if viewModel.surface.tool != nil {
                        WorkspaceToolPanel(viewModel: viewModel).frame(width: toolWidth)
                    }
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .onChange(of: viewModel.chatViewModel.selectedSessionId) { _, _ in viewModel.updateActiveTabTitle() }
        .onChange(of: viewModel.chatViewModel.activeContextTitle) { _, _ in viewModel.updateActiveTabTitle() }
        .onChange(of: viewModel.activeProject?.id) { _, _ in
            viewModel.surface.tool = nil
            Task { await viewModel.surface.loadSourceControl(project: viewModel.activeProject) }
        }
        .overlay {
            if viewModel.surface.creation != nil { WorkspaceCreationForm(viewModel: viewModel) }
        }
    }

    @ViewBuilder
    private func workspaceBody(showsSidebarControl: Bool) -> some View {
        switch viewModel.navigation.section {
            case .chats:
                chatScreen(showsSidebarControl: showsSidebarControl)
                    .id(viewModel.navigation.selectedTabID)
            case .projects:
                sectionContent(showsSidebarControl: showsSidebarControl) {
                    ProjectsScreen(apiClient: SloppyAPIClient(baseURL: viewModel.baseURL))
                }
            case .agents:
                sectionContent(showsSidebarControl: showsSidebarControl) {
                    AgentsScreen(apiClient: SloppyAPIClient(baseURL: viewModel.baseURL))
                }
            case .attention, .sites, .pullRequests, .scheduled, .project:
                WorkspaceScreens(viewModel: viewModel)
        }
    }

    private func sectionContent<Content: View>(showsSidebarControl: Bool, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(spacing: 0) {
            if showsSidebarControl {
                Button(action: viewModel.openMobileSidebar) {
                    HStack(spacing: 8) {
                        Icons.symbol(.menu, size: 18)
                        Text("Inbox")
                        Spacer()
                    }
                    .foregroundColor(theme.colors.textPrimary)
                    .padding(16)
                }
            }
            content().navigationBarHidden(false)
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
}
