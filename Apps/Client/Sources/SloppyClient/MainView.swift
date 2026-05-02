import AdaEngine
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat

@MainActor
struct MainView: View {
    let baseURL: URL
    let settings: ClientSettings
    let connectionMonitor: ConnectionMonitor
    let rootSafeAreaInsets: EdgeInsets
    let onOpenSettings: @MainActor () -> Void
    let onOpenWorkspace: @MainActor () -> Void

    @State private var projects: [APIProjectRecord] = []
    @State private var isLoadingProjects = false
    @State private var didLoadProjects = false
    @State private var expandedTaskLists: Set<String> = []
    @State private var selectedSidebarItem: MainSidebarSelection? = nil
    @State private var isSidebarCollapsed = false
    @State private var isMobileSidebarPresented = false
    @State private var chatViewModel: ChatScreenViewModel
    @State private var chatNavigationSerial = 0

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
        self.baseURL = baseURL
        self.settings = settings
        self.connectionMonitor = connectionMonitor
        self.rootSafeAreaInsets = rootSafeAreaInsets
        self.onOpenSettings = onOpenSettings
        self.onOpenWorkspace = onOpenWorkspace
        _chatViewModel = State(
            initialValue: ChatScreenViewModel(
                apiClient: SloppyAPIClient(baseURL: baseURL),
                settings: settings,
                connectionMonitor: connectionMonitor,
                onOpenSettings: onOpenSettings
            )
        )
    }

    private var sidebarWidth: Float {
        isSidebarCollapsed ? MainSidebarView.collapsedWidth : MainSidebarView.expandedWidth
    }

    private var sidebarMinimumWidth: Float {
        isSidebarCollapsed ? MainSidebarView.collapsedWidth : MainSidebarView.minimumWidth
    }

    private var sidebarMaximumWidth: Float {
        isSidebarCollapsed ? MainSidebarView.collapsedWidth : MainSidebarView.maximumWidth
    }

    private var usesFullScreenCompactSidebar: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    var body: some View {
        let c = theme.colors

        GeometryReader { proxy in
            let isCompact = idiom == .phone || proxy.size.width < 620

            ZStack {
                c.background
                    .ignoresSafeArea()

                splitLayout(
                    isCompact: isCompact,
                    availableWidth: proxy.size.width
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            Task { await loadProjects() }
        }
        .debugOverlay(isDebugEnabled ? .layoutBounds : .off)
        .keyboardShortcut(.d, modifiers: [.command, .shift]) {
            self.isDebugEnabled.toggle()
        }
    }
    
    @State private var isDebugEnabled = false

    @ViewBuilder
    private func splitLayout(isCompact: Bool, availableWidth: Float) -> some View {
//        if isCompact {
//            compactLayout(availableWidth: availableWidth)
//        } else {
            regularSplitLayout()
//        }
    }

    private func regularSplitLayout() -> some View {
        NavigationSplitView(
            columnVisibility: .constant(.automatic),
            preferredCompactColumn: .constant(.detail)
        ) {
            sidebarView(isOverlay: false)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .navigationSplitViewColumnWidth(
                    min: sidebarMinimumWidth,
                    ideal: sidebarWidth,
                    max: sidebarMaximumWidth
                )
        } detail: {
            chatScreen(showsSidebarControl: false)
        }
    }

    @ViewBuilder
    private func compactLayout(availableWidth: Float) -> some View {
        if usesFullScreenCompactSidebar {
            fullScreenCompactLayout()
        } else {
            compactOverlayLayout(availableWidth: availableWidth)
        }
    }

    private func fullScreenCompactLayout() -> some View {
        ZStack {
            if isMobileSidebarPresented {
                sidebarView(isOverlay: true)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            } else {
                chatScreen(showsSidebarControl: true)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            }
        }
    }

    private func compactOverlayLayout(availableWidth: Float) -> some View {
        ZStack(anchor: .topLeading) {
            chatScreen(showsSidebarControl: true)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)

            if isMobileSidebarPresented {
                Color.black
                    .opacity(0.42 as Float)
                    .ignoresSafeArea()
                    .onTap {
                        dismissMobileSidebar()
                    }

                sidebarView(isOverlay: true)
                    .frame(
                        width: mobileSidebarWidth(availableWidth: availableWidth),
                        alignment: .topLeading
                    )
                    .frame(maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func chatScreen(showsSidebarControl: Bool) -> some View {
        let openSidebar: (@MainActor () -> Void)? = showsSidebarControl ? openMobileSidebar : nil
        return ChatScreen(
            viewModel: chatViewModel,
            rootSafeAreaInsets: rootSafeAreaInsets,
            onOpenSidebar: openSidebar
        )
    }

    private func sidebarView(isOverlay: Bool) -> some View {
        MainSidebarView(
            projects: projects,
            isLoadingProjects: isLoadingProjects,
            expandedTaskLists: $expandedTaskLists,
            selectedItem: $selectedSidebarItem,
            isCollapsed: $isSidebarCollapsed.animation(),
            isOverlay: isOverlay,
            onDismissOverlay: dismissMobileSidebar,
            onOpenSettings: onOpenSettings,
            onOpenWorkspace: onOpenWorkspace,
            onSelectNewChat: selectNewChat,
            onSelectProject: selectProject,
            onSelectTask: selectTask
        )
    }

    private func openMobileSidebar() {
        isSidebarCollapsed = false
        isMobileSidebarPresented = true
    }

    private func dismissMobileSidebar() {
        isMobileSidebarPresented = false
    }

    private func selectNewChat() {
        selectedSidebarItem = .chats
        dismissMobileSidebar()
        navigateChat(.blank)
    }

    private func selectProject(_ project: APIProjectRecord) {
        selectedSidebarItem = .project(project.id)
        dismissMobileSidebar()
        navigateChat(
            .project(
                projectId: project.id,
                projectName: project.name,
                agentId: project.actors?.first
            )
        )
    }

    private func selectTask(
        projectId: String,
        projectName: String,
        task: APIProjectTask,
        fallbackAgentId: String?
    ) {
        selectedSidebarItem = .task(projectId: projectId, taskId: task.id)
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

    private func navigateChat(_ context: ChatNavigationRequest.Context) {
        chatNavigationSerial += 1
        chatViewModel.applyNavigationRequest(
            ChatNavigationRequest(id: chatNavigationSerial, context: context)
        )
    }

    private func loadProjects(force: Bool = false) async {
        guard force || !didLoadProjects else { return }
        guard !isLoadingProjects else { return }

        isLoadingProjects = true
        defer {
            didLoadProjects = true
            isLoadingProjects = false
        }

        let client = SloppyAPIClient(baseURL: baseURL)
        let list = (try? await client.fetchProjects()) ?? []
        projects = list

        if selectedSidebarItem == nil {
            selectedSidebarItem = .chats
        }
    }

    private func mobileSidebarWidth(availableWidth: Float) -> Float {
        min(MainSidebarView.expandedWidth, max(280, availableWidth - theme.spacing.l))
    }
}
