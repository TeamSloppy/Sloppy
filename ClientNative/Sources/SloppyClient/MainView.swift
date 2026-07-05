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
        contentView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                if viewModel.tabs.isEmpty {
                    viewModel.createBlankChatTab(select: true)
                }
                viewModel.chatViewModel.loadInitialData()
                Task { await viewModel.loadProjects() }
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
        NavigationSplitView {
            sidebarView(isOverlay: true)
                .navigationSplitViewColumnWidth(
                    min: viewModel.sidebarMinimumWidth,
                    ideal: viewModel.sidebarWidth,
                    max: viewModel.sidebarMaximumWidth
                )
        } detail: {
            desktopContentArea()
        }
        .navigationSplitViewStyle(.balanced)
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
    private func desktopContentArea() -> some View {
        ZStack(alignment: .top) {
            #if os(visionOS)
            workspaceContentHost(showsFloatingTabChrome: true)
            #else
            workspaceContentHost(showsFloatingTabChrome: false)
            #endif

            if idiom == .phone, viewModel.isMobileTabsOverviewPresented {
                MobileWorkspaceTabsOverview(
                    tabs: viewModel.tabs,
                    selectedTabID: viewModel.selectedTabID,
                    onSelect: { tabID in
                        viewModel.selectTab(tabID)
                        viewModel.dismissMobileTabsOverview()
                    },
                    onClose: { tabID in
                        viewModel.closeTab(tabID)
                    },
                    onCreate: {
                        viewModel.createBlankChatTab()
                        viewModel.dismissMobileTabsOverview()
                    },
                    onDismiss: {
                        viewModel.dismissMobileTabsOverview()
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                desktopTabContent(for: activeDesktopTab)
            } else {
                DesktopTabsEmptyState()
            }
        }
    }

    @ViewBuilder
    private func desktopTabContent(for tab: WorkspaceTab) -> some View {
        switch tab.kind {
        case .chat:
            if let chatState = viewModel.chatTabStates[tab.id] {
                ChatScreen(
                    viewModel: chatState.viewModel,
                    rootSafeAreaInsets: rootSafeAreaInsets,
                    onOpenSidebar: nil,
                    composerTabActions: idiom == .phone
                        ? ChatComposerTabActions(
                            previousTab: { viewModel.selectAdjacentTab(offset: -1) },
                            nextTab: { viewModel.selectAdjacentTab(offset: 1) },
                            showOverview: { viewModel.presentMobileTabsOverview() },
                            createTab: { viewModel.createBlankChatTab() }
                        )
                        : nil
                )
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
            } else {
                DesktopTabPlaceholderView(
                    title: tab.title,
                    detail: "Kanban tab state is unavailable."
                )
            }
        case .taskDetail:
            if let detailState = viewModel.taskDetailTabStates[tab.id],
               case .taskDetail(let context) = tab.payload {
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
            } else {
                DesktopTabPlaceholderView(
                    title: tab.title,
                    detail: "Task detail state is unavailable."
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

#if os(visionOS)
    @ViewBuilder
    private func desktopTabPreviewContent(for tab: WorkspaceTab) -> some View {
        desktopTabContent(for: tab)
            .allowsHitTesting(false)
            .clipped()
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
