import Foundation
import SwiftUI
import Observation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureAgents
import SloppyFeatureChat
import SloppyFeatureProjects
import SloppyFeatureSettings
import SloppyFeatureSites

#if canImport(UIKit)
private typealias MobileTabsSnapshotImage = UIImage
#elseif canImport(AppKit)
private typealias MobileTabsSnapshotImage = NSImage

struct ToggleWorkspaceTerminalAction {
    let perform: @MainActor () -> Void

    @MainActor
    func callAsFunction() {
        perform()
    }
}

extension FocusedValues {
    @Entry var toggleWorkspaceTerminal: ToggleWorkspaceTerminalAction?
}
#endif

@MainActor
struct MainView: View {
    private struct MobileTabsHeroOverlayState {
        var tabID: WorkspaceTab.ID
        var frame: CGRect
        var opacity: Double
        var cornerRadius: CGFloat
    }

    private enum WorkspaceSidePanelDestination: Equatable {
        case picker
        case review
        case browser
        case files
        case sideChat
    }

    #if os(macOS)
    private enum ToolbarSearchResult: Identifiable {
        case chat(ChatSessionSummary)
        case project(APIProjectRecord)

        var id: String {
            switch self {
            case .chat(let session):
                "chat:\(session.id)"
            case .project(let project):
                "project:\(project.id)"
            }
        }
    }

    private struct ToolbarSearchResultRow: View {
        let title: String
        let subtitle: String
        let systemImage: String
        let isSelected: Bool
        let onHover: @MainActor () -> Void
        let action: @MainActor () -> Void

        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    Text(title)
                        .lineLimit(1)

                    Spacer(minLength: 12)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
                .contentShape(Rectangle())
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            isSelected
                                ? Color.accentColor.opacity(0.18)
                                : isHovered ? Color.primary.opacity(0.08) : .clear
                        )
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .onHover {
                isHovered = $0
                if $0 {
                    onHover()
                }
            }
        }
    }
    #endif

    let rootSafeAreaInsets: EdgeInsets
    let menuBarQuickActionRequest: MenuBarQuickActionRequest?
    let onConsumeMenuBarQuickAction: @MainActor (MenuBarQuickActionRequest) -> Void
    let deepLinkRequest: AppDeepLinkRequest?
    let onConsumeDeepLink: @MainActor (AppDeepLinkRequest) -> Void

    @State private var viewModel: MainViewModel
    @State private var mobileTabPagingDirection = 1
    @State private var mobileTabsHeroOverlay: MobileTabsHeroOverlayState?
    @State private var mobileTabsSnapshotImage: MobileTabsSnapshotImage?
    @State private var mobileTabsSnapshotCache: [WorkspaceTab.ID: MobileTabsSnapshotImage] = [:]
    @State private var mobileTabsHiddenSourceTabID: WorkspaceTab.ID?
    @State private var mobileTabsHiddenThumbnailTabID: WorkspaceTab.ID?
    @State private var mobileTabsContentFrame: CGRect = .zero
    @State private var mobileTabsThumbnailFrames: [WorkspaceTab.ID: CGRect] = [:]
    @State private var mobileTabsOverviewProgress: CGFloat = 0
    @State private var isMobileTabsOverviewGestureActive = false
    @State private var isWorkspacePanelPresented = false
    @State private var workspaceSidePanelDestination = WorkspaceSidePanelDestination.picker
    @State private var sideChatViewModel: ChatScreenViewModel?
    @State private var toolbarSearchText = ""
    @State private var isToolbarSearchResultsPresented = false
    @State private var canvasWorkspaceViewModel: CanvasWorkspaceViewModel
    @State private var hasActivatedWorkspaceMode = false
    @SceneStorage("sloppy.main-content-mode") private var mainContentModeRawValue = MainContentMode.coding.rawValue
    #if os(macOS)
    @State private var toolbarSearchSelectionID: ToolbarSearchResult.ID?
    @FocusState private var isToolbarSearchFocused: Bool
    #endif

    // iOS
    @State private var pagerSize: CGSize = .zero
    @State private var pagerPosition: ScrollPosition = .init()
    private let pagerOffset: CGFloat = 16
    private let mobileTabsHeroThumbnailCornerRadius: CGFloat = 20
    private let mobileTabsHeroDuration: Double = 0.42
    private let mobileTabsHeroFadeDuration: Double = 0.14
    private let mobileTabsOverviewCommitThreshold: CGFloat = 0.35
    private let mobileTabsOverviewVelocityThreshold: CGFloat = 120

    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme
    @Environment(\.displayScale) private var displayScale

    private var activeDesktopTab: WorkspaceTab? {
        guard let selectedTabID = viewModel.selectedTabID else {
            return nil
        }
        return viewModel.tabs.first(where: { $0.id == selectedTabID })
    }

    private var activeChatViewModel: ChatScreenViewModel? {
        guard let selectedTabID = viewModel.selectedTabID,
              let tab = viewModel.tabs.first(where: { $0.id == selectedTabID }),
              let tabState = viewModel.tabStates[selectedTabID] else {
            return nil
        }

        if tab.kind == .chat {
            return tabState.chatState?.viewModel
        }
        if tab.kind == .projectKanban,
           let projectState = tabState.projectKanbanState,
           projectState.selectedSection == .chats {
            return projectState.chatViewModel
        }
        return nil
    }

    init(
        baseURL: URL,
        settings: ClientSettings,
        connectionMonitor: ConnectionMonitor,
        rootSafeAreaInsets: EdgeInsets = EdgeInsets(),
        onOpenSettings: @Sendable @escaping @MainActor (ClientSettingsDestination) -> Void,
        onOpenWorkspace: @escaping @MainActor () -> Void,
        menuBarQuickActionRequest: MenuBarQuickActionRequest? = nil,
        onConsumeMenuBarQuickAction: @escaping @MainActor (MenuBarQuickActionRequest) -> Void = { _ in },
        deepLinkRequest: AppDeepLinkRequest? = nil,
        onConsumeDeepLink: @escaping @MainActor (AppDeepLinkRequest) -> Void = { _ in }
    ) {
        self.rootSafeAreaInsets = rootSafeAreaInsets
        self.menuBarQuickActionRequest = menuBarQuickActionRequest
        self.onConsumeMenuBarQuickAction = onConsumeMenuBarQuickAction
        self.deepLinkRequest = deepLinkRequest
        self.onConsumeDeepLink = onConsumeDeepLink
        _canvasWorkspaceViewModel = State(
            initialValue: CanvasWorkspaceViewModel(baseURL: baseURL)
        )
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
            if viewModel.hasLoadedInitialContent {
                workspacePanelContainer
            } else {
                MainLoadingView()
            }
        }
            .onAppear {
                if viewModel.tabs.isEmpty {
                    viewModel.createBlankChatTab(select: true)
                }
                viewModel.chatViewModel.loadInitialData()
                Task {
                    await viewModel.loadProjects()
                }
                Task {
                    await viewModel.loadCurrentAccount()
                }
                handleMenuBarQuickAction(menuBarQuickActionRequest)
                handleDeepLink(deepLinkRequest)
                if mainContentModeRawValue == MainContentMode.workspace.rawValue {
                    viewModel.selectWorkspace()
                    hasActivatedWorkspaceMode = true
                }
            }
            .onChange(of: menuBarQuickActionRequest?.id) { _, _ in
                handleMenuBarQuickAction(menuBarQuickActionRequest)
            }
            .onChange(of: deepLinkRequest?.id) { _, _ in
                handleDeepLink(deepLinkRequest)
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

                    #if os(macOS)
                    Button("") {
                        viewModel.toggleTerminalForSelectedTab()
                    }
                    .keyboardShortcut("j", modifiers: [.command])
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    #endif
                }
            }
            #if os(macOS)
            .focusedSceneValue(
                \.toggleWorkspaceTerminal,
                ToggleWorkspaceTerminalAction {
                    viewModel.toggleTerminalForSelectedTab()
                }
            )
            #endif
            .toolbar {
                if viewModel.hasLoadedInitialContent {
                    if isCanvasWorkspaceSelected,
                       !canvasWorkspaceViewModel.isShowingLibrary {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                returnToCanvasWorkspaceLibrary()
                            } label: {
                                Label("Workspaces", systemImage: "chevron.left")
                            }
                            .help("Back to Workspaces")
                            .accessibilityIdentifier("canvas-workspace-back")
                        }
                    }

                    #if os(macOS)
                    if !isCanvasWorkspaceSelected {
                        ToolbarItem(placement: .principal) {
                            toolbarSearchField
                        }
                    }
                    #endif

                    ToolbarItemGroup(placement: .primaryAction) {
                        #if !os(macOS)
                        if !isCanvasWorkspaceSelected,
                           viewModel.selectedAppSection != .artifacts,
                           viewModel.selectedAppSection != .sites,
                           let activeChatViewModel {
                            ChatContextToolbarMenu(
                                selectedAgent: activeChatViewModel.selectedAgent,
                                agents: activeChatViewModel.agents,
                                selectedModelId: activeChatViewModel.selectedModelId,
                                models: activeChatViewModel.availableModels,
                                onSelectAgent: activeChatViewModel.pickAgent,
                                onSelectModel: activeChatViewModel.pickModel
                            )
                        }
                        #endif

                        if idiom != .phone,
                           !isCanvasWorkspaceSelected,
                           viewModel.selectedAppSection != .artifacts,
                           viewModel.selectedAppSection != .sites {
                            workspaceSidePanelButton
                        }
                    }
                }
            }
            #if os(macOS)
            .overlay(alignment: .top) {
                toolbarSearchResultsOverlay
            }
            #endif
            .sheet(isPresented: $viewModel.isProjectEditorPresented) {
                ProjectEditorSheet(
                    baseURL: viewModel.baseURL,
                    project: viewModel.projectBeingEdited,
                    onSaved: viewModel.didSaveProject
                )
            }
            .onChange(of: viewModel.selectedTabID) { oldValue, newValue in
                if let oldValue,
                   oldValue != newValue,
                   shouldCaptureLiveSnapshotForCache {
                    captureMobileTabsSnapshot(for: oldValue, storeInCache: true)
                }
                updateMobileTabPagingDirection(from: oldValue, to: newValue)
                if let newValue {
                    viewModel.requestChatScrollToEnd(for: newValue)
                }
            }
            .onChange(of: activeChatViewModel?.workingTreeSourceControl?.diff) { _, diff in
                guard diff != nil,
                      let activeChatViewModel,
                      let sourceControl = activeChatViewModel.workingTreeSourceControl,
                      activeChatViewModel.activeProjectIdForWorkspacePanel
                        == viewModel.workspacePanelViewModel.context?.projectId else {
                    return
                }
                viewModel.workspacePanelViewModel.synchronizeSourceControl(sourceControl)
            }
            .onChange(of: viewModel.selectedAppSection) { _, _ in
                mainContentModeRawValue = isCanvasWorkspaceSelected
                    ? MainContentMode.workspace.rawValue
                    : MainContentMode.coding.rawValue
                guard isCanvasWorkspaceSelected else {
                    return
                }
                viewModel.selectedSidebarItem = nil
                hasActivatedWorkspaceMode = true
                isWorkspacePanelPresented = false
                canvasWorkspaceViewModel.showLibrary()
                #if os(macOS)
                dismissToolbarSearch()
                #endif
            }
            .task(id: canvasResolutionKey) {
                guard isCanvasWorkspaceSelected else {
                    return
                }
                await canvasWorkspaceViewModel.resolve(
                    workspaceID: viewModel.activeCanvasWorkspaceID,
                    projectID: viewModel.activeCanvasProjectID,
                    projectName: viewModel.workspaceContext?.projectName,
                    force: true
                )
            }
    }

    @ViewBuilder
    private var workspacePanelContainer: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            contentView
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)

            if isWorkspacePanelPresented {
                Divider()

                workspaceSidePanel
                    .frame(width: 380)
                    .frame(maxHeight: .infinity)
                    .background(theme.colors.surface)
            }
        }
        #else
        contentView
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            .inspector(isPresented: $isWorkspacePanelPresented) {
                workspaceScreen()
                    .inspectorColumnWidth(min: 320, ideal: 380, max: 520)
            }
        #endif
    }

    @ViewBuilder
    private func workspaceBottomPanelOverlay(maximumHeight: CGFloat) -> some View {
        if let selectedTabID = viewModel.selectedTabID,
           let terminalState = viewModel.tabStates[selectedTabID]?.terminalState,
           terminalState.isPresented {
            WorkspaceBottomPanelDrawerView(
                height: min(terminalState.height, maximumHeight),
                maximumHeight: maximumHeight,
                selectedPanel: terminalState.selectedPanel,
                onSelectPanel: { panel in
                    viewModel.openBottomPanel(panel)
                    switch panel {
                    case .review:
                        viewModel.workspacePanelViewModel.switchMode(.environment)
                    case .browser:
                        viewModel.workspacePanelViewModel.switchMode(.webBrowser)
                    case .files:
                        viewModel.workspacePanelViewModel.switchMode(.files)
                    case .terminal:
                        break
                    }
                },
                onClose: viewModel.closeTerminalForSelectedTab,
                onHeightChange: {
                    terminalState.height = min(max($0, 180), maximumHeight)
                }
            ) {
                workspaceBottomPanelContent(
                    selectedPanel: terminalState.selectedPanel,
                    selectedTabID: selectedTabID
                )
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(20)
        }
    }

    @ViewBuilder
    private func workspaceBottomPanelContent(
        selectedPanel: WorkspaceBottomPanelKind,
        selectedTabID: WorkspaceTab.ID
    ) -> some View {
        switch selectedPanel {
        case .terminal:
            if viewModel.terminalSessions[selectedTabID] != nil {
                viewModel.makeTerminalHostView(for: selectedTabID)
            } else {
                WorkspaceBottomPanelUnavailableView(
                    title: "Project directory unavailable",
                    detail: "Open the terminal from a project-backed tab to start a shell."
                )
            }
        case .review, .browser, .files:
            if let workspaceContext = viewModel.workspaceContext {
                WorkspacePanelView(
                    viewModel: viewModel.workspacePanelViewModel,
                    context: workspaceContext,
                    onOpenTerminal: { viewModel.openBottomPanel(.terminal) },
                    showsHeader: false
                )
            } else {
                WorkspaceBottomPanelUnavailableView(
                    title: "Project unavailable",
                    detail: "Open a project-backed tab to use \(selectedPanel.title.lowercased())."
                )
            }
        }
    }

    private var workspaceSidePanelButton: some View {
        Button(action: toggleWorkspaceSidePanelPicker) {
            Image(systemName: "sidebar.right")
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help(isWorkspacePanelPresented ? "Show panel picker" : "Open side panel")
        .accessibilityLabel("Side panel")
    }

    private func openWorkspacePanel(mode: WorkspacePanelMode) {
        viewModel.workspacePanelViewModel.switchMode(mode)
        switch mode {
        case .environment:
            workspaceSidePanelDestination = .review
        case .webBrowser:
            workspaceSidePanelDestination = .browser
        case .files:
            workspaceSidePanelDestination = .files
        }
        isWorkspacePanelPresented = true
    }

    private func toggleWorkspaceSidePanelPicker() {
        if !isWorkspacePanelPresented {
            workspaceSidePanelDestination = .picker
            isWorkspacePanelPresented = true
        } else if workspaceSidePanelDestination == .picker {
            isWorkspacePanelPresented = false
        } else {
            workspaceSidePanelDestination = .picker
        }
    }

    private func selectWorkspaceSidePanelItem(_ item: WorkspaceSidePanelItem) {
        switch item {
        case .review:
            openWorkspacePanel(mode: .environment)
        case .terminal:
            viewModel.openBottomPanel(.terminal)
            isWorkspacePanelPresented = false
        case .browser:
            openWorkspacePanel(mode: .webBrowser)
        case .files:
            openWorkspacePanel(mode: .files)
        case .sideChat:
            if sideChatViewModel == nil {
                sideChatViewModel = viewModel.makeChatTabState().viewModel
            }
            workspaceSidePanelDestination = .sideChat
            isWorkspacePanelPresented = true
        }
    }

    #if os(macOS)
    private var toolbarSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search chats and projects", text: $toolbarSearchText)
                .textFieldStyle(.plain)
                .focused($isToolbarSearchFocused)
                .onKeyPress(.downArrow) {
                    moveToolbarSearchSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveToolbarSearchSelection(by: -1)
                    return .handled
                }
                .onSubmit {
                    openSelectedToolbarSearchResult()
                }
                .onExitCommand {
                    dismissToolbarSearch()
                }

            if !toolbarSearchText.isEmpty {
                Button {
                    dismissToolbarSearch(keepsFocus: true)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 280, idealWidth: 420, maxWidth: 560, minHeight: 30)
        .onChange(of: toolbarSearchText) { _, text in
            isToolbarSearchResultsPresented = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            toolbarSearchSelectionID = toolbarSearchResults.first?.id
        }
        .onChange(of: toolbarSearchResultIDs) { _, resultIDs in
            if let toolbarSearchSelectionID,
               resultIDs.contains(toolbarSearchSelectionID) {
                return
            }
            toolbarSearchSelectionID = resultIDs.first
        }
    }

    private var toolbarSearchQuery: String {
        toolbarSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingToolbarChatSessions: [ChatSessionSummary] {
        guard !toolbarSearchQuery.isEmpty else {
            return []
        }
        return viewModel.chatViewModel.sessionCatalog.filter {
            $0.title.localizedStandardContains(toolbarSearchQuery)
        }
    }

    private var matchingToolbarProjects: [APIProjectRecord] {
        guard !toolbarSearchQuery.isEmpty else {
            return []
        }
        return viewModel.projects.filter {
            $0.name.localizedStandardContains(toolbarSearchQuery)
        }
    }

    private var visibleToolbarChatSessions: [ChatSessionSummary] {
        Array(matchingToolbarChatSessions.prefix(8))
    }

    private var visibleToolbarProjects: [APIProjectRecord] {
        Array(matchingToolbarProjects.prefix(8))
    }

    private var toolbarSearchResults: [ToolbarSearchResult] {
        visibleToolbarChatSessions.map(ToolbarSearchResult.chat)
            + visibleToolbarProjects.map(ToolbarSearchResult.project)
    }

    private var toolbarSearchResultIDs: [ToolbarSearchResult.ID] {
        toolbarSearchResults.map(\.id)
    }

    private var toolbarSearchResultsPanelHeight: CGFloat {
        let resultCount = visibleToolbarChatSessions.count + visibleToolbarProjects.count
        let sectionCount = (matchingToolbarChatSessions.isEmpty ? 0 : 1)
            + (matchingToolbarProjects.isEmpty ? 0 : 1)
        return min(420, max(64, CGFloat(resultCount) * 38 + CGFloat(sectionCount) * 30 + 16))
    }

    @ViewBuilder
    private var toolbarSearchResultsOverlay: some View {
        if isToolbarSearchResultsPresented && !isCanvasWorkspaceSelected {
            toolbarSearchResultsPanel
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
                .animation(.easeOut(duration: 0.14), value: isToolbarSearchResultsPresented)
        }
    }

    private var toolbarSearchResultsPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    toolbarSearchSuggestions
                }
                .padding(8)
            }
            .onChange(of: toolbarSearchSelectionID) { _, selectionID in
                guard let selectionID else {
                    return
                }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(selectionID, anchor: .center)
                }
            }
        }
        .frame(width: 560, height: toolbarSearchResultsPanelHeight)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }

    @ViewBuilder
    private var toolbarSearchSuggestions: some View {
        if !matchingToolbarChatSessions.isEmpty {
            Text("Chats")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .frame(height: 28)

            ForEach(visibleToolbarChatSessions) { session in
                let result = ToolbarSearchResult.chat(session)
                ToolbarSearchResultRow(
                    title: session.title,
                    subtitle: "Chat",
                    systemImage: "bubble.left",
                    isSelected: toolbarSearchSelectionID == result.id,
                    onHover: {
                        toolbarSearchSelectionID = result.id
                    },
                    action: {
                        openToolbarSearchResult(result)
                    }
                )
                .id(result.id)
            }
        }

        if !matchingToolbarProjects.isEmpty {
            Text("Projects")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .frame(height: 28)

            ForEach(visibleToolbarProjects) { project in
                let result = ToolbarSearchResult.project(project)
                ToolbarSearchResultRow(
                    title: project.name,
                    subtitle: project.kind == .workspace ? "Workspace" : "Project",
                    systemImage: project.semanticIconName,
                    isSelected: toolbarSearchSelectionID == result.id,
                    onHover: {
                        toolbarSearchSelectionID = result.id
                    },
                    action: {
                        openToolbarSearchResult(result)
                    }
                )
                .id(result.id)
            }
        }

        if !toolbarSearchQuery.isEmpty,
           matchingToolbarChatSessions.isEmpty,
           matchingToolbarProjects.isEmpty {
            Text("No chats or projects found")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
    }

    private func moveToolbarSearchSelection(by offset: Int) {
        let results = toolbarSearchResults
        guard !results.isEmpty else {
            toolbarSearchSelectionID = nil
            return
        }

        guard let toolbarSearchSelectionID,
              let selectedIndex = results.firstIndex(where: { $0.id == toolbarSearchSelectionID }) else {
            self.toolbarSearchSelectionID = offset < 0 ? results.last?.id : results.first?.id
            return
        }

        let nextIndex = (selectedIndex + offset + results.count) % results.count
        self.toolbarSearchSelectionID = results[nextIndex].id
    }

    private func openSelectedToolbarSearchResult() {
        let result = toolbarSearchResults.first {
            $0.id == toolbarSearchSelectionID
        } ?? toolbarSearchResults.first
        guard let result else {
            return
        }
        openToolbarSearchResult(result)
    }

    private func openToolbarSearchResult(_ result: ToolbarSearchResult) {
        switch result {
        case .chat(let session):
            viewModel.openSessionChatTab(session)
        case .project(let project):
            viewModel.openProjectKanbanTab(project: project)
        }
        dismissToolbarSearch()
    }

    private func dismissToolbarSearch(keepsFocus: Bool = false) {
        toolbarSearchText = ""
        toolbarSearchSelectionID = nil
        isToolbarSearchResultsPresented = false
        if !keepsFocus {
            isToolbarSearchFocused = false
        }
    }
    #endif

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

    private func handleMenuBarQuickAction(_ request: MenuBarQuickActionRequest?) {
        guard let request else { return }
        switch request.action {
        case .newChat:
            viewModel.selectNewChat()
        case .scheduledTasks:
            viewModel.selectScheduled()
        }
        onConsumeMenuBarQuickAction(request)
    }

    private func handleDeepLink(_ request: AppDeepLinkRequest?) {
        guard let request else { return }

        switch request.deepLink {
        case .connect, .open:
            onConsumeDeepLink(request)
        case .project(let id):
            Task { @MainActor in
                await viewModel.loadProjects(force: true)
                if let project = viewModel.projects.first(where: { $0.id == id }) {
                    viewModel.selectProject(project)
                }
                onConsumeDeepLink(request)
            }
        case .session(let agentId, let sessionId):
            Task { @MainActor in
                if let detail = try? await viewModel.apiClient.fetchAgentSession(
                    agentId: agentId,
                    sessionId: sessionId
                ) {
                    viewModel.openSessionChatTab(detail.summary)
                }
                onConsumeDeepLink(request)
            }
        case .dictationToggle(let agentId, let sessionId):
            Task { @MainActor in
                if let detail = try? await viewModel.apiClient.fetchAgentSession(
                    agentId: agentId,
                    sessionId: sessionId
                ) {
                    viewModel.openSessionChatTab(detail.summary)
                    await Task.yield()
                    if let chatViewModel = activeChatViewModel {
                        switch chatViewModel.dictationPhase {
                        case .idle:
                            chatViewModel.startDictation()
                        case .recording:
                            chatViewModel.stopDictation()
                        case .transcribing:
                            break
                        }
                    }
                }
                onConsumeDeepLink(request)
            }
        }
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
            if idiom == .phone,
               viewModel.isMobileTabsOverviewPresented || mobileTabsHeroOverlay != nil || isMobileTabsOverviewGestureActive {
                GeometryReader { proxy in
                    let rootFrame = proxy.frame(in: .global)

                    ZStack {
                        if viewModel.isMobileTabsOverviewPresented || isMobileTabsOverviewGestureActive {
                            MobileWorkspaceTabsOverview(
                                tabs: viewModel.tabs,
                                selectedTabID: viewModel.selectedTabID,
                                snapshotCache: mobileTabsSnapshotCache,
                                hiddenThumbnailTabID: hiddenThumbnailTabIDForOverview,
                                appearanceProgress: mobileTabsOverviewAppearanceProgress,
                                onSelect: { tabID in
                                    Task {
                                        await handleMobileTabsOverviewSelection(tabID)
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
                                    clearMobileTabsHeroState()
                                },
                                onDismiss: {
                                    Task {
                                        await dismissMobileTabsOverviewAnimated()
                                    }
                                },
                                onThumbnailFramesChange: { frames in
                                    mobileTabsThumbnailFrames = frames
                                    if isMobileTabsOverviewGestureActive || mobileTabsOverviewProgress > 0 {
                                        syncMobileTabsOverviewHero()
                                    }
                                }
                            )
                            .allowsHitTesting(viewModel.isMobileTabsOverviewPresented && !isMobileTabsOverviewGestureActive)
                        }

                        mobileTabsHeroOverlayView(rootFrame: rootFrame)
                    }
                }
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
        Group {
            if viewModel.selectedAppSection == .scheduled {
                ScheduledTasksScreen(apiClient: viewModel.apiClient)
            } else if viewModel.selectedAppSection == .sites {
                SitesScreen(
                    apiClient: viewModel.apiClient,
                    onCreate: viewModel.createSiteFromChat
                )
            } else if viewModel.selectedAppSection == .artifacts {
                ArtifactsScreen(
                    apiClient: viewModel.apiClient,
                    cacheStore: viewModel.cacheStore,
                    sessions: viewModel.chatViewModel.sessionCatalog,
                    onOpenSession: viewModel.openSessionChatTab
                )
            } else {
                mainModeContent
            }
        }
        .navigationSplitViewColumnWidth(min: 600, ideal: 940)
        #if os(macOS)
        .overlay(alignment: .bottom) {
            GeometryReader { proxy in
                workspaceBottomPanelOverlay(
                    maximumHeight: max(180, proxy.size.height - 120)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        #endif
    }

    private var mainModeContent: some View {
        ZStack {
            workspaceArea
                .opacity(isCanvasWorkspaceSelected ? 0.0 : 1.0)
                .allowsHitTesting(!isCanvasWorkspaceSelected)
                .accessibilityHidden(isCanvasWorkspaceSelected)

            if hasActivatedWorkspaceMode {
                CanvasWorkspaceSurface(viewModel: canvasWorkspaceViewModel)
                    .opacity(isCanvasWorkspaceSelected ? 1.0 : 0.0)
                    .allowsHitTesting(isCanvasWorkspaceSelected)
                    .accessibilityHidden(!isCanvasWorkspaceSelected)
            }
        }
    }

    private var canvasResolutionKey: String {
        [
            viewModel.selectedAppSection.rawValue,
            viewModel.activeCanvasWorkspaceID ?? "-",
            viewModel.activeCanvasProjectID ?? "-"
        ].joined(separator: "|")
    }

    private var isCanvasWorkspaceSelected: Bool {
        viewModel.selectedAppSection == .workspace
    }

    private func returnToCanvasWorkspaceLibrary() {
        canvasWorkspaceViewModel.showLibrary()
        Task {
            await canvasWorkspaceViewModel.refreshLibrary()
        }
    }

    private var workspaceArea: some View {
        ZStack(alignment: .top) {
            #if os(visionOS)
            workspaceContentHost(showsFloatingTabChrome: true)
            #elseif os(macOS)
            VStack(spacing: 0) {
                if viewModel.tabs.count > 1 {
                    DesktopWorkspaceTabStrip(viewModel: viewModel)
                }
                workspaceContentHost(showsFloatingTabChrome: false)
            }
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
            if let activeChatViewModel {
                ChatComposerOverlay(
                    viewModel: activeChatViewModel,
                    contentWidth: 10,
                    composerBottomInset: {
                        #if os(macOS)
                        24
                        #else
                        theme.spacing.s
                        #endif
                    }(),
                    tabs: viewModel.tabs,
                    tabActions: idiom == .phone
                    ? ChatComposerTabActions(
                        tabProgress: { progress in updatePagerPosition(progress) },
                        showOverview: { presentMobileTabsOverviewAnimated() },
                        beginOverviewGesture: { beginMobileTabsOverviewGesture() },
                        updateOverviewGesture: { progress in
                            updateMobileTabsOverviewGesture(progress: progress)
                        },
                        endOverviewGesture: { progress, velocity in
                            endMobileTabsOverviewGesture(progress: progress, upwardVelocity: velocity)
                        },
                        createTab: { createMobileTabAnimated() }
                    )
                    : nil
                )
                .opacity(shouldHidePhoneComposer ? 0.0 : 1.0)
                .allowsHitTesting(!viewModel.isMobileTabsOverviewPresented)
            }
        }
    }

    @ViewBuilder
    private func phoneWorkspaceContentHost(showsFloatingTabChrome: Bool) -> some View {
        if !viewModel.tabs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: pagerOffset) {
                    ForEach(viewModel.tabs, id: \.id) { tab in
                        desktopTabContent(for: tab)
                            .opacity(shouldHidePhoneContent(for: tab.id) ? 0.0 : 1.0)
                            .allowsHitTesting(!shouldHidePhoneContent(for: tab.id))
                    }
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollDisabled(true)
            .scrollPosition($pagerPosition)
            .onScrollGeometryChange(for: CGSize.self) { geometry in
                geometry.containerSize
            } action: { _, newValue in
                updatePagerSize(newValue)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            mobileTabsContentFrame = proxy.frame(in: .global)
                        }
                        .onChange(of: proxy.frame(in: .global)) { _, newValue in
                            mobileTabsContentFrame = newValue
                        }
                }
            }
            .background(
                LinearGradient(
                    colors: [
                        .black,
                        theme.colors.accent.opacity(0.05),
                        theme.colors.accent.opacity(0.15)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .opacity(shouldHidePhoneBackground ? 0.0 : 1.0)
            )
        } else {
            DesktopTabsEmptyState()
        }
    }

    @ViewBuilder
    private func workspaceContentHost(showsFloatingTabChrome: Bool) -> some View {
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

    private func uncachedContent(for tab: WorkspaceTab) -> AnyView? {
        guard let tabState = viewModel.tabStates[tab.id] else {
            return nil
        }
        return makeDesktopTabContent(for: tab, tabState: tabState)
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
            let openSidebar: (@MainActor @Sendable () -> Void)? = idiom == .phone
                ? { @MainActor @Sendable in viewModel.openMobileSidebar() }
                : nil
            return AnyView(
                ChatScreen(
                    viewModel: chatState.viewModel,
                    rootSafeAreaInsets: rootSafeAreaInsets,
                    onOpenSidebar: openSidebar,
                    showsContextToolbar: false,
                    showsNavigationToolbar: idiom == .phone
                )
                .id(ObjectIdentifier(chatState.viewModel))
                .onChange(of: chatState.viewModel.selectedSessionId) { _, _ in
                    viewModel.synchronizeChatTab(tab.id)
                }
            )
        case .projectKanban:
            guard let kanbanState = tabState.projectKanbanState,
                  case .projectKanban(let context) = tab.payload else {
                return placeholderContent(
                    title: tab.title,
                    detail: "Kanban tab state is unavailable."
                )
            }
            let project = viewModel.projects.first { $0.id == context.projectId }
                ?? APIProjectRecord(
                    id: context.projectId,
                    name: context.projectName,
                    directoryPaths: context.projectRootPath.map { [$0] } ?? []
                )
            return AnyView(
                ProjectModeView(
                    project: project,
                    state: kanbanState,
                    rootSafeAreaInsets: rootSafeAreaInsets,
                    onSelectSection: { section in
                        viewModel.selectProjectModeSection(section, project: project)
                    },
                    onOpenTask: { card in
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
                    onClose: {
                        let project = viewModel.projects.first { $0.id == context.projectId }
                            ?? APIProjectRecord(
                                id: context.projectId,
                                name: context.projectName,
                                directoryPaths: context.projectRootPath.map { [$0] } ?? []
                            )
                        viewModel.openProjectKanbanTab(project: project)
                    },
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
                    context: WorkspacePanelContext(projectId: context.projectId, projectName: context.projectName),
                    onOpenTerminal: { viewModel.toggleTerminalForSelectedTab() }
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
        guard idiom == .phone,
              viewModel.selectedTabID != nil,
              mobileTabsContentFrame != .zero else {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                viewModel.presentMobileTabsOverview()
            }
            return
        }

        Task {
            await MainActor.run {
                beginMobileTabsOverviewGesture()
                withAnimation(.spring(response: mobileTabsHeroDuration, dampingFraction: 0.86)) {
                    mobileTabsOverviewProgress = 1
                    syncMobileTabsOverviewHero()
                }
            }
            try? await Task.sleep(for: .seconds(mobileTabsHeroDuration))
            await MainActor.run {
                isMobileTabsOverviewGestureActive = false
            }
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

    private func shouldHidePhoneContent(for tabID: WorkspaceTab.ID?) -> Bool {
        guard idiom == .phone,
              let tabID,
              let hiddenTabID = mobileTabsHiddenSourceTabID,
              mobileTabsSnapshotImage != nil else {
            return false
        }
        return tabID == hiddenTabID
    }

    private var shouldHidePhoneComposer: Bool {
        idiom == .phone && mobileTabsHiddenSourceTabID != nil && mobileTabsSnapshotImage != nil
    }

    private var shouldHidePhoneBackground: Bool {
        idiom == .phone && mobileTabsHiddenSourceTabID != nil && mobileTabsSnapshotImage != nil
    }

    private var mobileTabsOverviewAppearanceProgress: CGFloat {
        clamp(mobileTabsOverviewProgress)
    }

    private var hiddenThumbnailTabIDForOverview: WorkspaceTab.ID? {
        guard mobileTabsHeroOverlay != nil else {
            return nil
        }
        return mobileTabsSnapshotImage != nil ? mobileTabsHiddenThumbnailTabID : nil
    }

    private var shouldCaptureLiveSnapshotForCache: Bool {
        guard idiom == .phone else {
            return false
        }
        return !viewModel.isMobileTabsOverviewPresented
            && !isMobileTabsOverviewGestureActive
            && mobileTabsHeroOverlay == nil
    }

    @ViewBuilder
    private func mobileTabsHeroOverlayView(rootFrame: CGRect) -> some View {
        if let hero = mobileTabsHeroOverlay {
            let localFrame = hero.frame.offsetBy(dx: -rootFrame.minX, dy: -rootFrame.minY)

            Group {
                if let mobileTabsSnapshotImage {
                    #if canImport(UIKit)
                    Image(uiImage: mobileTabsSnapshotImage)
                        .resizable()
                        .interpolation(.high)
                    #elseif canImport(AppKit)
                    Image(nsImage: mobileTabsSnapshotImage)
                        .resizable()
                        .interpolation(.high)
                    #endif
                } else if let tab = viewModel.tabs.first(where: { $0.id == hero.tabID }) {
                    liveHeroFallbackContent(for: tab)
                }
            }
            .frame(width: max(localFrame.width, 1), height: max(localFrame.height, 1))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: hero.cornerRadius,
                    style: .continuous
                )
            )
            .opacity(hero.opacity)
            .position(x: localFrame.midX, y: localFrame.midY)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func snapshotCaptureContent(for tab: WorkspaceTab) -> some View {
        uncachedContentView(for: tab)
            .frame(width: mobileTabsContentFrame.width, height: mobileTabsContentFrame.height)
            .clipped()
    }

    @ViewBuilder
    private func liveHeroFallbackContent(for tab: WorkspaceTab) -> some View {
        uncachedContentView(for: tab)
    }

    @ViewBuilder
    private func uncachedContentView(for tab: WorkspaceTab) -> some View {
        if let content = uncachedContent(for: tab) {
            content
        } else {
            DesktopTabPlaceholderView(
                title: tab.title,
                detail: "Tab state is unavailable."
            )
        }
    }

    private var phoneWorkspaceBackground: some View {
        LinearGradient(
            colors: [
                .black,
                theme.colors.accent.opacity(0.05),
                theme.colors.accent.opacity(0.15)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func beginMobileTabsOverviewGesture() {
        guard idiom == .phone,
              let selectedTabID = viewModel.selectedTabID,
              mobileTabsContentFrame != .zero else {
            return
        }

        mobileTabsSnapshotImage = captureMobileTabsSnapshot(for: selectedTabID, storeInCache: true)
        isMobileTabsOverviewGestureActive = true
        mobileTabsHiddenSourceTabID = selectedTabID
        mobileTabsHiddenThumbnailTabID = selectedTabID
        if mobileTabsHeroOverlay?.tabID != selectedTabID {
            mobileTabsHeroOverlay = MobileTabsHeroOverlayState(
                tabID: selectedTabID,
                frame: mobileTabsContentFrame,
                opacity: 1,
                cornerRadius: 0
            )
        }
        mobileTabsOverviewProgress = max(mobileTabsOverviewProgress, 0.001)
        syncMobileTabsOverviewHero()
    }

    private func updateMobileTabsOverviewGesture(progress: CGFloat) {
        guard viewModel.isMobileTabsOverviewPresented || isMobileTabsOverviewGestureActive else {
            return
        }

        mobileTabsOverviewProgress = clamp(progress)
        syncMobileTabsOverviewHero()
    }

    private func endMobileTabsOverviewGesture(progress: CGFloat, upwardVelocity: CGFloat) {
        let clampedProgress = clamp(progress)
        mobileTabsOverviewProgress = clampedProgress
        syncMobileTabsOverviewHero()

        let shouldComplete = clampedProgress >= mobileTabsOverviewCommitThreshold || upwardVelocity >= mobileTabsOverviewVelocityThreshold
        Task {
            await animateMobileTabsOverviewProgress(
                to: shouldComplete ? 1 : 0,
                dismissOnCompletion: !shouldComplete
            )
        }
    }

    private func syncMobileTabsOverviewHero() {
        guard idiom == .phone,
              let selectedTabID = viewModel.selectedTabID,
              mobileTabsContentFrame != .zero else {
            return
        }

        let progress = clamp(mobileTabsOverviewProgress)
        let sourceFrame = mobileTabsContentFrame
        let targetFrame = mobileTabsThumbnailFrames[selectedTabID] ?? sourceFrame

        mobileTabsHiddenSourceTabID = selectedTabID
        mobileTabsHiddenThumbnailTabID = selectedTabID
        mobileTabsHeroOverlay = MobileTabsHeroOverlayState(
            tabID: selectedTabID,
            frame: interpolatedRect(from: sourceFrame, to: targetFrame, progress: progress),
            opacity: 1,
            cornerRadius: mobileTabsHeroThumbnailCornerRadius * progress
        )
    }

    private func dismissMobileTabsOverviewAnimated() async {
        guard viewModel.selectedTabID != nil,
              mobileTabsContentFrame != .zero else {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                viewModel.dismissMobileTabsOverview()
            }
            clearMobileTabsHeroState()
            return
        }

        mobileTabsOverviewProgress = 1
        syncMobileTabsOverviewHero()
        await animateMobileTabsOverviewProgress(to: 0, dismissOnCompletion: true)
    }

    private func handleMobileTabsOverviewSelection(_ tabID: WorkspaceTab.ID) async {
        guard let selectedTabID = viewModel.selectedTabID else {
            return
        }

        guard tabID != selectedTabID else {
            await dismissMobileTabsOverviewAnimated()
            return
        }

        if mobileTabsHeroOverlay == nil,
           let currentFrame = mobileTabsThumbnailFrames[selectedTabID] {
            mobileTabsHeroOverlay = MobileTabsHeroOverlayState(
                tabID: selectedTabID,
                frame: currentFrame,
                opacity: 1,
                cornerRadius: mobileTabsHeroThumbnailCornerRadius
            )
        }

        mobileTabsHiddenThumbnailTabID = selectedTabID
        withAnimation(.easeInOut(duration: mobileTabsHeroFadeDuration)) {
            mobileTabsHeroOverlay?.opacity = 0
        }
        try? await Task.sleep(for: .seconds(mobileTabsHeroFadeDuration))

        guard let nextFrame = mobileTabsThumbnailFrames[tabID] else {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                viewModel.selectTab(tabID)
                viewModel.dismissMobileTabsOverview()
            }
            clearMobileTabsHeroState()
            return
        }

        viewModel.selectTab(tabID)
        mobileTabsHiddenSourceTabID = tabID
        mobileTabsHiddenThumbnailTabID = tabID
        mobileTabsHeroOverlay = MobileTabsHeroOverlayState(
            tabID: tabID,
            frame: nextFrame,
            opacity: 1,
            cornerRadius: mobileTabsHeroThumbnailCornerRadius
        )

        withAnimation(.spring(response: mobileTabsHeroDuration, dampingFraction: 0.86)) {
            mobileTabsHeroOverlay?.frame = mobileTabsContentFrame
            mobileTabsHeroOverlay?.cornerRadius = 0
            viewModel.dismissMobileTabsOverview()
        }

        try? await Task.sleep(for: .seconds(mobileTabsHeroDuration))
        clearMobileTabsHeroState()
    }

    private func clearMobileTabsHeroState() {
        mobileTabsHeroOverlay = nil
        mobileTabsSnapshotImage = nil
        mobileTabsHiddenSourceTabID = nil
        mobileTabsHiddenThumbnailTabID = nil
        mobileTabsOverviewProgress = 0
        isMobileTabsOverviewGestureActive = false
    }

    private func animateMobileTabsOverviewProgress(to targetProgress: CGFloat, dismissOnCompletion: Bool) async {
        await MainActor.run {
            withAnimation(.spring(response: mobileTabsHeroDuration, dampingFraction: 0.86)) {
                mobileTabsOverviewProgress = targetProgress
                syncMobileTabsOverviewHero()
            }
        }

        try? await Task.sleep(for: .seconds(mobileTabsHeroDuration))

        await MainActor.run {
            if dismissOnCompletion {
                if viewModel.isMobileTabsOverviewPresented {
                    viewModel.dismissMobileTabsOverview()
                }
                clearMobileTabsHeroState()
            } else {
                if !viewModel.isMobileTabsOverviewPresented {
                    viewModel.presentMobileTabsOverview()
                }
                mobileTabsOverviewProgress = 1
                isMobileTabsOverviewGestureActive = false
                mobileTabsHeroOverlay = nil
                mobileTabsSnapshotImage = nil
            }
        }
    }

    private func interpolatedRect(from source: CGRect, to target: CGRect, progress: CGFloat) -> CGRect {
        let clampedProgress = clamp(progress)
        return CGRect(
            x: source.minX + ((target.minX - source.minX) * clampedProgress),
            y: source.minY + ((target.minY - source.minY) * clampedProgress),
            width: source.width + ((target.width - source.width) * clampedProgress),
            height: source.height + ((target.height - source.height) * clampedProgress)
        )
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    @discardableResult
    private func captureMobileTabsSnapshot(for tabID: WorkspaceTab.ID, storeInCache: Bool) -> MobileTabsSnapshotImage? {
        guard mobileTabsContentFrame.width > 0,
              mobileTabsContentFrame.height > 0 else {
            return nil
        }

        #if canImport(UIKit)
        let image = captureWindowSnapshot()
        #else
        let image: MobileTabsSnapshotImage? = nil
        #endif
        if storeInCache, let image {
            mobileTabsSnapshotCache[tabID] = image
        }
        return image
    }

#if canImport(UIKit)
    private func captureWindowSnapshot() -> UIImage? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: \.isKeyWindow) ?? windowScene.windows.first else {
            return nil
        }

        let frameInWindow = window.convert(mobileTabsContentFrame, from: nil)
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let fullImage = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }

        guard let cgImage = fullImage.cgImage else {
            return nil
        }

        let scale = fullImage.scale
        let cropRect = CGRect(
            x: frameInWindow.minX * scale,
            y: frameInWindow.minY * scale,
            width: frameInWindow.width * scale,
            height: frameInWindow.height * scale
        ).integral

        guard let cropped = cgImage.cropping(to: cropRect) else {
            return nil
        }

        return UIImage(cgImage: cropped, scale: scale, orientation: .up)
    }
#endif

    private func mobileTabPagingTransition(for tab: WorkspaceTab) -> AnyTransition {
        let insertionEdge: Edge = mobileTabPagingDirection >= 0 ? .trailing : .leading
        let removalEdge: Edge = mobileTabPagingDirection >= 0 ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private func chatScreen(showsSidebarControl: Bool) -> some View {
        let openSidebar: (@MainActor @Sendable () -> Void)? = showsSidebarControl
            ? { @MainActor @Sendable in viewModel.openMobileSidebar() }
            : nil
        return ChatScreen(
            viewModel: viewModel.chatViewModel,
            rootSafeAreaInsets: rootSafeAreaInsets,
            onOpenSidebar: openSidebar,
            showsContextToolbar: false
        )
    }

    private func sidebarView(isOverlay: Bool) -> some View {
        MainSidebarView(
            viewModel: viewModel,
            isOverlay: isOverlay,
            canvasWorkspaceViewModel: canvasWorkspaceViewModel
        )
    }

    private var workspaceSidePanel: some View {
        VStack(spacing: 0) {
            workspaceScreen()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Spacer(minLength: 0)

                Button {
                    isWorkspacePanelPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: theme.typography.body))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close side panel")
            }
            .padding(.horizontal, theme.spacing.s)
            .frame(height: 44)
        }
    }

    @ViewBuilder
    private func workspaceScreen() -> some View {
        switch workspaceSidePanelDestination {
        case .picker:
            WorkspaceSidePanelPickerView(
                hasProject: viewModel.workspaceContext != nil,
                onSelect: selectWorkspaceSidePanelItem
            )
        case .review, .browser, .files:
            if let workspaceContext = viewModel.workspaceContext {
                WorkspacePanelView(
                    viewModel: viewModel.workspacePanelViewModel,
                    context: workspaceContext,
                    onOpenTerminal: { viewModel.openBottomPanel(.terminal) }
                )
            } else {
                WorkspaceUnavailableView()
            }
        case .sideChat:
            workspaceSideChat
        }
    }

    @ViewBuilder
    private var workspaceSideChat: some View {
        if let sideChatViewModel {
            ZStack(alignment: .bottom) {
                ChatScreen(
                    viewModel: sideChatViewModel,
                    showsContextToolbar: false,
                    showsNavigationToolbar: false
                )

                ChatComposerOverlay(
                    viewModel: sideChatViewModel,
                    contentWidth: 340,
                    composerBottomInset: theme.spacing.m,
                    tabs: [],
                    tabActions: nil
                )
            }
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


#Preview {
    MainView(
        baseURL: .debugURL,
        settings: ClientSettings(),
        connectionMonitor: ConnectionMonitor(baseURL: .debugURL),
        onOpenSettings: { _ in },
        onOpenWorkspace: {}
    )
#if os(macOS)
    .frame(width: 1024, height: 600)
#endif
}
