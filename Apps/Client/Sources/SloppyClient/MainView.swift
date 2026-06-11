import AdaEngine
import Observation
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat

@Observable
@MainActor
final class MainViewModel {
    let baseURL: URL
    let settings: ClientSettings
    let connectionMonitor: ConnectionMonitor
    let onOpenSettings: @MainActor () -> Void
    let onOpenWorkspace: @MainActor () -> Void

    var projects: [APIProjectRecord] = []
    var isLoadingProjects = false
    var didLoadProjects = false
    var expandedTaskLists: Set<String> = []
    var selectedSidebarItem: MainSidebarSelection? = nil
    var isSidebarCollapsed = false
    var isMobileSidebarPresented = false
    var chatViewModel: ChatScreenViewModel
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
        self.chatViewModel = ChatScreenViewModel(
            apiClient: SloppyAPIClient(baseURL: baseURL),
            settings: settings,
            connectionMonitor: connectionMonitor,
            onOpenSettings: onOpenSettings
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
        updateSelectedSidebarItem(.chats)
        dismissMobileSidebar()
        navigateChat(.blank)
    }

    func selectChatSession(_ session: ChatSessionSummary) {
        updateSelectedSidebarItem(.chats)
        dismissMobileSidebar()
        chatViewModel.pickSession(session)
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

    func selectProject(_ project: APIProjectRecord) {
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
        let list = (try? await client.fetchProjects()) ?? []
        projects = list

        if selectedSidebarItem == nil {
            selectedSidebarItem = .chats
        }
    }

    private func updateSelectedSidebarItem(_ selection: MainSidebarSelection) {
        guard selectedSidebarItem != selection else {
            return
        }
        selectedSidebarItem = selection
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
    @Environment(\.safeAreaInsets) private var safeAreaInsets

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

    private var usesFullScreenCompactSidebar: Bool {
#if os(iOS)
        true
#else
        false
#endif
    }

    var body: some View {
        regularSplitLayout()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                Task { await viewModel.loadProjects() }
            }
    }

    private func regularSplitLayout() -> some View {
        return NavigationSplitView {
            sidebarView(isOverlay: false)
                .padding(.all, 4)
                .navigationSplitViewColumnWidth(
                    min: viewModel.sidebarMinimumWidth,
                    ideal: viewModel.sidebarWidth,
                    max: viewModel.sidebarMaximumWidth
                )
        } detail: {
            chatScreen(showsSidebarControl: false)
        }
        .navigationSplitViewSeparators(.hidden)
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
            if viewModel.isMobileSidebarPresented {
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

            if viewModel.isMobileSidebarPresented {
                Color.black
                    .opacity(0.42 as Float)
                    .ignoresSafeArea()
                    .onTap {
                        viewModel.dismissMobileSidebar()
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

    private func mobileSidebarWidth(availableWidth: Float) -> Float {
        min(MainSidebarView.expandedWidth, max(280, availableWidth - theme.spacing.l))
    }
}
