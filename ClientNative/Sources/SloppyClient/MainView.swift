import Foundation
import SwiftUI
import Observation
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureAgents
import SloppyFeatureChat
import SloppyFeatureProjects
import SloppyFeatureSettings

@MainActor
struct MainView: View {
    let rootSafeAreaInsets: EdgeInsets

    @State private var viewModel: MainViewModel
    @State private var mobileTabPagingDirection = 1

    // iOS
    @State private var pagerSize: CGSize = .zero
    @State private var pagerPosition: ScrollPosition = .init()
    private let pagerOffset: CGFloat = 16

    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme

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
        contentView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                if viewModel.tabs.isEmpty {
                    viewModel.createBlankChatTab(select: true)
                }
                viewModel.chatViewModel.loadInitialData()
                Task {
                    await viewModel.loadProjects()
                }
            }
            .background {
                Group {
                    Button("") {
                        viewModel.createBlankChatTab()
                    }
                    .keyboardShortcut("t", modifiers: [.command])
                    .opacity(0.001)
                    .allowsHitTesting(false)

                    Button("") {
                        viewModel.closeActiveTab()
                    }
                    .keyboardShortcut("w", modifiers: [.command])
                    .opacity(0.001)
                    .allowsHitTesting(false)

                    Button("") {
                        Task { await viewModel.refreshContent() }
                    }
                    .keyboardShortcut("r", modifiers: [.command])
                    .opacity(0.001)
                    .allowsHitTesting(false)
                }
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
            .onChange(of: viewModel.selectedTabID) { oldValue, newValue in
                updateMobileTabPagingDirection(from: oldValue, to: newValue)
            }
    }

    @ViewBuilder
    private var contentView: some View {
#if os(visionOS)
        if viewModel.isVisionTabsOverviewPresented {
            VisionWorkspaceTabsOverview(
                tabs: viewModel.tabs,
                selectedTabID: viewModel.selectedTabID,
                onSelect: { tabID in
                    viewModel.selectTab(tabID)
                    viewModel.dismissVisionTabsOverview()
                },
                onClose: { tabID in
                    viewModel.closeTab(tabID)
                },
                onCreate: {
                    viewModel.createBlankChatTab()
                },
                onDismiss: {
                    viewModel.dismissVisionTabsOverview()
                },
                previewContent: { tab in
                    desktopTabPreviewContent(for: tab)
                }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else {
            navigationView
        }
#else
        navigationView
#endif
    }

    private var navigationView: some View {
        NavigationSplitView(columnVisibility: $viewModel.columnVisibility) {
            sidebarView(isOverlay: false)
                .navigationSplitViewColumnWidth(
                    min: viewModel.sidebarMinimumWidth,
                    ideal: viewModel.sidebarWidth,
                    max: viewModel.sidebarMaximumWidth
                )
                .navigationDestination(for: MainSidebarSelection.self) { _ in
                    contentArea()
                        .onAppear {
                            viewModel.dismissMobileSidebar()
                        }
                }
        } detail: {
            contentArea()
        }
        .navigationSplitViewStyle(.balanced)
        .overlay {
            if idiom == .phone, viewModel.isMobileTabsOverviewPresented {
                MobileWorkspaceTabsOverview(
                    tabs: viewModel.tabs,
                    selectedTabID: viewModel.selectedTabID,
                    onSelect: { tabID in
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                            viewModel.selectTab(tabID)
                            viewModel.dismissMobileTabsOverview()
                        }
                    },
                    onClose: { tabID in
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                            viewModel.closeTab(tabID)
                        }
                    },
                    onCreate: {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                            viewModel.createBlankChatTab()
                            viewModel.dismissMobileTabsOverview()
                        }
                    },
                    onDismiss: {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                            viewModel.dismissMobileTabsOverview()
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
            }
        }
#if os(visionOS)
        .ornament(
            attachmentAnchor: .scene(.top),
            contentAlignment: .bottom,
            ornament: {
                VisionFloatingTabBarView(
                    viewModel: viewModel,
                    onOpenOverview: { viewModel.presentVisionTabsOverview() }
                )
                    .padding(.bottom, 12)
            }
        )
#endif
    }

    @ViewBuilder
    private func contentArea() -> some View {
        ZStack(alignment: .top) {
            #if os(visionOS)
            workspaceContentHost(showsFloatingTabChrome: true)
            #else
            if idiom == .phone {
                phoneWorkspaceContentHost(showsFloatingTabChrome: false)
            } else {
                workspaceContentHost(showsFloatingTabChrome: false)
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(anchor: .bottom) {
            ChatComposerOverlay(
                viewModel: viewModel.chatViewModel,
                contentWidth: 10,
                composerBottomInset: 0,
                tabs: viewModel.tabs,
                tabActions: idiom == .phone
                ? ChatComposerTabActions(
                    tabProgress: updatePagerPosition,
                    showOverview: { presentMobileTabsOverviewAnimated() },
                    createTab: { createMobileTabAnimated() }
                )
                : nil
            )
        }
    }

    @ViewBuilder
    private func phoneWorkspaceContentHost(showsFloatingTabChrome: Bool) -> some View {
        if !viewModel.tabs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: pagerOffset) {
                    ForEach(viewModel.tabs, id: \.id) { tab in
                        desktopTabContent(for: tab)
                    }
                    .background(theme.colors.background)
                }
            }
            .scrollDisabled(true)
            .scrollPosition($pagerPosition)
            .onScrollGeometryChange(for: CGSize.self) { geometry in
                geometry.containerSize
            } action: { _, newValue in
                updatePagerSize(newValue)
            }
            .background(Color.red)
        } else {
            DesktopTabsEmptyState()
        }
    }

    @ViewBuilder
    private func workspaceContentHost(showsFloatingTabChrome: Bool) -> some View {
        VStack(spacing: 0) {
            #if !os(visionOS)
            if idiom != .phone && !showsFloatingTabChrome {
                DesktopWorkspaceTabStrip(viewModel: viewModel)
                Divider()
            }
            #endif

            if let desktopSplitState = viewModel.desktopSplitState,
               let primaryTab = viewModel.tabs.first(where: { $0.id == desktopSplitState.primaryTabID }),
               let secondaryTab = viewModel.tabs.first(where: { $0.id == desktopSplitState.secondaryTabID }) {
                DesktopSplitContentView(
                    fraction: desktopSplitState.fraction,
                    onFractionChange: viewModel.updateDesktopSplitFraction(_:),
                    onClearSplit: viewModel.clearDesktopSplit,
                    primary: { desktopTabContent(for: primaryTab) },
                    secondary: { desktopTabContent(for: secondaryTab) }
                )
            } else if let activeDesktopTab {
                mountedDesktopTabContent(activeTabID: activeDesktopTab.id)
            } else {
                DesktopTabsEmptyState()
            }
        }
    }

    private func mountedDesktopTabContent(activeTabID: WorkspaceTab.ID) -> some View {
        ZStack {
            ForEach(viewModel.tabs) { tab in
                desktopTabContent(for: tab)
                    .opacity(tab.id == activeTabID ? 1.0 : 0.0)
                    .allowsHitTesting(tab.id == activeTabID)
                    .accessibilityHidden(tab.id != activeTabID)
            }
        }
    }

    @ViewBuilder
    private func desktopTabContent(for tab: WorkspaceTab) -> some View {
        if let content = cachedContent(for: tab) {
            content
        } else {
            DesktopTabPlaceholderView(
                title: tab.title,
                detail: "Tab state is unavailable."
            )
        }
    }

    private func cachedContent(for tab: WorkspaceTab) -> AnyView? {
        guard let tabState = viewModel.tabStates[tab.id] else {
            return nil
        }

        if let content = tabState.content {
            return content
        }

        let content = makeDesktopTabContent(for: tab, tabState: tabState)
        tabState.content = content
        return content
    }

    private func makeDesktopTabContent(for tab: WorkspaceTab, tabState: WorkspaceTabState) -> AnyView {
        switch tab.kind {
        case .chat:
            guard let chatState = tabState.chatState else {
                return placeholderContent(
                    title: tab.title,
                    detail: "Chat tab state is unavailable."
                )
            }
            let openSidebar = idiom == .phone ? viewModel.openMobileSidebar : nil
            return AnyView(
                ChatScreen(
                    viewModel: chatState.viewModel,
                    rootSafeAreaInsets: rootSafeAreaInsets,
                    onOpenSidebar: openSidebar
                )
            )
        case .projectKanban:
            guard let kanbanState = tabState.projectKanbanState,
                  case .projectKanban(let context) = tab.payload else {
                return placeholderContent(
                    title: tab.title,
                    detail: "Kanban tab state is unavailable."
                )
            }
            return AnyView(
                ProjectKanbanView(
                    viewModel: kanbanState.viewModel,
                    projectId: context.projectId,
                    projectName: context.projectName,
                    onOpenTask: { card in
                        let project = APIProjectRecord(
                            id: context.projectId,
                            name: context.projectName,
                            tasks: [
                                APIProjectTask(
                                    id: card.id,
                                    title: card.title,
                                    status: card.status,
                                    priority: card.priority,
                                    actorId: card.actorID
                                )
                            ]
                        )
                        let task = APIProjectTask(
                            id: card.id,
                            title: card.title,
                            status: card.status,
                            priority: card.priority,
                            actorId: card.actorID
                        )
                        viewModel.openTaskDetailTab(
                            project: project,
                            task: task,
                            fallbackAgentId: card.actorID
                        )
                    }
                )
            )
        case .taskDetail:
            guard let detailState = tabState.taskDetailState,
                  case .taskDetail(let context) = tab.payload else {
                return placeholderContent(
                    title: tab.title,
                    detail: "Task detail state is unavailable."
                )
            }
            return AnyView(
                TaskDetailView(
                    viewModel: detailState.viewModel,
                    projectId: context.projectId,
                    taskId: context.taskId,
                    onOpenChat: { task in
                        let project = APIProjectRecord(
                            id: context.projectId,
                            name: context.projectName,
                            tasks: [task]
                        )
                        viewModel.openTaskChatTab(
                            project: project,
                            task: task,
                            fallbackAgentId: context.fallbackAgentId
                        )
                    }
                )
            )
        case .workspaceFiles:
            guard let workspaceState = tabState.workspaceFilesState,
                  case .workspaceFiles(let context) = tab.payload else {
                return placeholderContent(
                    title: tab.title,
                    detail: "Workspace tab state is unavailable."
                )
            }
            return AnyView(
                WorkspacePanelView(
                    viewModel: workspaceState.viewModel,
                    context: WorkspacePanelContext(projectId: context.projectId, projectName: context.projectName)
                )
            )
        }
    }

    private func placeholderContent(title: String, detail: String) -> AnyView {
        AnyView(
            DesktopTabPlaceholderView(
                title: title,
                detail: detail
            )
        )
    }

    private func presentMobileTabsOverviewAnimated() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            viewModel.presentMobileTabsOverview()
        }
    }

    private func createMobileTabAnimated() {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) {
            viewModel.createBlankChatTab()
        }
    }

    private func updatePagerPosition(_ progress: CGFloat) {
        let pagerWidth = pagerSize.width
        guard pagerWidth > 0, progress.isFinite else {
            return
        }

        Task { @MainActor in
            pagerPosition.scrollTo(x: (pagerWidth + pagerOffset) * progress)
        }
    }

    private func updatePagerSize(_ newValue: CGSize) {
        guard pagerSize != newValue else {
            return
        }

        Task { @MainActor in
            pagerSize = newValue
        }
    }

    private func updateMobileTabPagingDirection(from oldValue: WorkspaceTab.ID?, to newValue: WorkspaceTab.ID?) {
        guard let oldValue,
              let newValue,
              let oldIndex = viewModel.tabs.firstIndex(where: { $0.id == oldValue }),
              let newIndex = viewModel.tabs.firstIndex(where: { $0.id == newValue }),
              oldIndex != newIndex else {
            return
        }
        mobileTabPagingDirection = newIndex > oldIndex ? 1 : -1
    }

    private func mobileTabPagingTransition(for tab: WorkspaceTab) -> AnyTransition {
        let insertionEdge: Edge = mobileTabPagingDirection >= 0 ? .trailing : .leading
        let removalEdge: Edge = mobileTabPagingDirection >= 0 ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
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

    @ViewBuilder
    private func mobileTabPreviewContent(for tab: WorkspaceTab) -> some View {
        desktopTabContent(for: tab)
            .allowsHitTesting(false)
            .clipped()
    }

#if os(visionOS)
    @ViewBuilder
    private func desktopTabPreviewContent(for tab: WorkspaceTab) -> some View {
        mobileTabPreviewContent(for: tab)
    }
#endif
}

#Preview {
    MainView(
        baseURL: .debugURL,
        settings: ClientSettings(),
        connectionMonitor: ConnectionMonitor(baseURL: .debugURL),
        onOpenSettings: {},
        onOpenWorkspace: {}
    )
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

@MainActor
private struct DesktopSplitContentView<Primary: View, Secondary: View>: View {
    let fraction: CGFloat
    let onFractionChange: @MainActor (CGFloat) -> Void
    let onClearSplit: @MainActor () -> Void
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let secondary: () -> Secondary

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let clampedFraction = min(0.72, max(0.28, fraction))
            let handleWidth: CGFloat = 24
            let primaryWidth = max(0, width * clampedFraction - handleWidth / 2)
            let secondaryWidth = max(0, width - primaryWidth - handleWidth)

            HStack(spacing: 0) {
                primary()
                    .frame(width: primaryWidth)

                DesktopSplitHandle(
                    onClearSplit: onClearSplit,
                    onDrag: { translationWidth in
                        onFractionChange(clampedFraction + translationWidth / width)
                    }
                )
                .frame(width: handleWidth)

                secondary()
                    .frame(width: secondaryWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@MainActor
private struct DesktopSplitHandle: View {
    let onClearSplit: @MainActor () -> Void
    let onDrag: @MainActor (CGFloat) -> Void

    @Environment(\.theme) private var theme
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: theme.spacing.s) {
            Capsule()
                .fill(theme.colors.border)
                .frame(width: 4, height: 48)

            Button(action: onClearSplit) {
                Image(systemName: "rectangle.compress.horizontal")
                    .font(.system(size: theme.typography.micro, weight: .semibold))
                    .foregroundColor(theme.colors.textSecondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isHovered ? theme.colors.surfaceRaised.opacity(0.32 as CGFloat) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    onDrag(value.translation.width)
                }
        )
    }
}

fileprivate let chatContentWidth: CGFloat = 840
