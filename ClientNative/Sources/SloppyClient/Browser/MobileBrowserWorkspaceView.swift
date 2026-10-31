#if os(iOS)
import SwiftUI
import WebKit
import SloppyClientUI

/// iPhone and iPad share browser data with the desktop, with touch navigation of their own.
@MainActor
struct MobileBrowserWorkspaceView: View {
    @Bindable var state: BrowserWorkspaceState
    let onAskAgent: (String) -> Void
    let onCollect: ([BrowserTabRecord]) -> Void
    let onSettings: () -> Void
    var onAnnotateSelection: BrowserTextAnnotationTarget?
    var agentChat: BrowserAgentChatState?
    @State private var sheet: MobileBrowserSheet?
    @State private var showsTabs = false
    @State private var snapshots: [UUID: UIImage] = [:]
    @State private var opensSettingsAfterDismiss = false
    @State private var pendingAgentPrompt: String?
    @State private var toolbarCollapse = MobileBrowserToolbarCollapse()
    @State private var expandedToolbarHeight: CGFloat = 106
    @State private var visibleToolbarHeight: CGFloat = 106
    @State private var tabSwipe: MobileBrowserTabSwipe?
    @State private var pageViewportWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            page
                .overlay {
                    if !state.isSearchPresented {
                        GeometryReader { geometry in
                            MobileBrowserBottomBackdrop(toolbarHeight: visibleToolbarHeight + 4,
                                                        bottomInset: geometry.safeAreaInsets.bottom)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .bottom) {
                    if !state.isSearchPresented {
                        MobileBrowserToolbar(state: state, onNewTab: newTab, onTabs: openTabs,
                                             onMenu: { sheet = .menu }, onAssistant: askAgent,
                                             onTabSwipe: switchTab,
                                             onTabSwipeChanged: updateTabSwipe,
                                             onTabSwipeEnded: endTabSwipe,
                                             onTabSwipeCancelled: cancelTabSwipe,
                                             tabSwipe: tabSwipe,
                                             isCollapsed: toolbarCollapse.isCollapsed, onExpand: toolbarCollapse.expand,
                                             onExpandedHeightChange: { height in
                                                 if height > 0, height != expandedToolbarHeight { expandedToolbarHeight = height }
                                             })
                            .frame(maxWidth: 640)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                if height > 0, height != visibleToolbarHeight { visibleToolbarHeight = height }
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)
                    }
                }
                .background(pageBackground.ignoresSafeArea(.container))
                .navigationTitle("Browse")
                .navigationBarTitleDisplayMode(.inline)
                .mobileWorkBrowseNavigationBar()
                .toolbar(isShowingHome ? .visible : .hidden, for: .navigationBar)
                .toolbar {
                    if isShowingHome {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button { sheet = .library(.history) } label: {
                                Label("History", systemImage: "clock.arrow.circlepath")
                            }
                            .accessibilityIdentifier("browser-home-history")
                            Button { sheet = .library(.bookmarks) } label: {
                                Label("Bookmarks", systemImage: "book")
                            }
                            .accessibilityIdentifier("browser-home-bookmarks")
                        }
                    }
                }
        }
        .allowsHitTesting(!state.isSearchPresented)
        .accessibilityHidden(state.isSearchPresented)
        .background(pageBackground.ignoresSafeArea(.container))
        .overlay {
            if state.isSearchPresented {
                MobileBrowserSearchView(state: state, onAskAgent: { pendingAgentPrompt = $0 })
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: state.isSearchPresented)
        .inspector(isPresented: Binding(
            get: { state.isBrowsing && agentChat?.panel.isPresented == true },
            set: { if !$0 { agentChat?.hide() } }
        )) {
            if let agentChat {
                BrowserAgentChatPanel(state: agentChat, browser: state)
                    .presentationDetents([.large])
            }
        }
        .sheet(item: $sheet, onDismiss: {
            if opensSettingsAfterDismiss {
                opensSettingsAfterDismiss = false
                onSettings()
            }
        }) { destination in
            switch destination {
            case .menu:
                MobileBrowserMenu(state: state, onLibrary: { sheet = .library($0) }, onSettings: {
                    opensSettingsAfterDismiss = true
                    sheet = nil
                }, onWork: {
                    sheet = nil
                    state.isBrowsing = false
                }, onCollect: {
                    sheet = nil
                    onCollect(state.tabs)
                })
            case .library(let section): BrowserLibrarySheet(section: section, state: state)
            }
        }
        .task(id: state.isSearchPresented) {
            guard !state.isSearchPresented, let prompt = pendingAgentPrompt else { return }
            await Task.yield()
            guard !Task.isCancelled, !state.isSearchPresented else { return }
            pendingAgentPrompt = nil
            onAskAgent(prompt)
        }
        .fullScreenCover(isPresented: $showsTabs) {
            MobileBrowserTabsView(state: state, snapshots: snapshots, onNewTab: {
                showsTabs = false
                state.createBlankTab()
            })
        }
        .onChange(of: state.tabs.map(\.id)) { _, ids in
            snapshots = snapshots.filter { ids.contains($0.key) }
            if let target = tabSwipe?.target, case .existing(let id) = target, !ids.contains(id) {
                tabSwipe = nil
            }
        }
        .onDisappear { state.checkpoint(); tabSwipe = nil }
        .onChange(of: state.selectedID) { _, selectedID in
            if let tabSwipe, tabSwipe.sourceID != selectedID { self.tabSwipe = nil }
            toolbarCollapse.expand()
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { tabSwipe = nil } }
        .onChange(of: state.selectedTab?.url) { _, _ in toolbarCollapse.expand() }
        .onChange(of: state.selectedPage?.isLoading) { _, loading in if loading == true { toolbarCollapse.expand() } }
        .onChange(of: state.isBrowsing) { _, _ in toolbarCollapse.expand() }
        .onChange(of: state.isSearchPresented) { _, shown in
            if shown { tabSwipe = nil; pendingAgentPrompt = nil; toolbarCollapse.expand() }
        }
        .onChange(of: showsTabs) { _, shown in if shown { toolbarCollapse.expand() } }
        .preference(key: MobileBrowserChromeSchemePreferenceKey.self, value: chromeScheme)
    }

    private var page: some View {
        MobileBrowserPagePager(state: state, swipe: $tabSwipe, viewportWidth: $pageViewportWidth,
                               onAskAgent: onAskAgent, onHomeAskAgent: askAgent,
                               annotationTarget: onAnnotateSelection) { id, sample in
            guard state.isBrowsing, state.selectedID == id, tabSwipe == nil,
                  !state.isSearchPresented, !showsTabs, sheet == nil,
                  agentChat?.panel.isPresented != true else { return }
            toolbarCollapse.consume(sample, transitionDistance: expandedToolbarHeight)
        }
    }

    private func updateTabSwipe(_ translation: CGSize) {
        guard !reduceMotion, pageViewportWidth > 0, tabSwipe?.isSettling != true else { return }
        if tabSwipe == nil {
            guard let direction = MobileBrowserTabSwipe.dragDirection(
                horizontal: translation.width, vertical: translation.height
            ) else { return }
            captureSelectedPage()
            tabSwipe = MobileBrowserTabSwipe(sourceID: state.selectedID, width: pageViewportWidth,
                                             direction: direction)
        }
        guard var swipe = tabSwipe else { return }
        let direction: BrowserTabSwipeDirection = translation.width < 0 ? .next : .previous
        let target = state.tabSwipeTarget(direction, newTabID: swipe.newTabID)
        if let target, target != swipe.target { state.prepareTabSwipeTarget(target) }
        swipe.update(horizontal: translation.width, target: target)
        tabSwipe = swipe
    }

    private func endTabSwipe(_ translation: CGSize, predicted: CGSize) {
        if reduceMotion {
            if let direction = BrowserTabSwipeDirection.resolve(horizontal: translation.width, vertical: translation.height) {
                switchTab(direction)
            }
            return
        }
        updateTabSwipe(translation)
        guard let swipe = tabSwipe, !swipe.isSettling else { return }
        finishTabSwipe(committing: swipe.shouldCommit(predictedHorizontal: predicted.width))
    }

    private func cancelTabSwipe() {
        guard let tabSwipe, !tabSwipe.isSettling else { return }
        finishTabSwipe(committing: false)
    }

    private func finishTabSwipe(committing: Bool) {
        guard let swipe = tabSwipe else { return }
        tabSwipe?.isSettling = true
        withAnimation(.smooth(duration: 0.3), completionCriteria: .logicallyComplete) {
            tabSwipe?.offset = swipe.destinationOffset(committing: committing)
        } completion: {
            guard tabSwipe?.id == swipe.id else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if committing, state.selectedID == swipe.sourceID, let target = swipe.target {
                    state.activateTabSwipeTarget(target)
                }
                tabSwipe = nil
            }
        }
    }

    private var isShowingHome: Bool { state.selectedTab?.url == nil }

    private var pageBackground: Color {
        if state.selectedTab?.url == nil { return theme.colors.background }
        return Color(uiColor: state.selectedPage?.browserBackgroundColor ?? .systemBackground)
    }

    private var chromeScheme: ColorScheme? {
        guard state.isBrowsing, state.selectedTab?.url != nil,
              !state.isSearchPresented, !showsTabs, sheet == nil,
              agentChat?.panel.isPresented != true,
              let isDark = state.selectedPage?.prefersDarkBrowserChrome else { return nil }
        return isDark ? .dark : .light
    }

    private func newTab() {
        captureSelectedPage()
        state.createBlankTab()
        state.presentSearch(newTab: false)
    }

    private func openTabs() {
        state.checkpoint()
        captureSelectedPage()
        showsTabs = true
    }

    private func switchTab(_ direction: BrowserTabSwipeDirection) {
        tabSwipe = nil
        captureSelectedPage()
        state.selectAdjacentTab(direction)
    }

    private func askAgent() {
        if let agentChat { agentChat.show() } else { onAskAgent("") }
    }

    private func captureSelectedPage() {
        guard let id = state.selectedID, let webView = state.selectedPage?.nativeWebView,
              webView.bounds.width > 0, webView.bounds.height > 0 else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(origin: .zero, size: CGSize(width: webView.bounds.width,
            height: min(webView.bounds.height, webView.bounds.width * 1.3)))
        configuration.snapshotWidth = 360
        webView.takeSnapshot(with: configuration) { image, _ in
            if let image,
               state.tabs.contains(where: { $0.id == id }) {
                snapshots[id] = image
            }
        }
    }
}

/// Web content scrolls beneath the status bar and fades back into focus below it.
struct MobileBrowserTopBackdrop: View {
    let statusBarHeight: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if statusBarHeight > 0 {
            let height = statusBarHeight + 32
            Group {
                if reduceTransparency {
                    Rectangle().fill(.background).frame(height: statusBarHeight)
                } else {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .frame(height: height)
                        .mask {
                            LinearGradient(stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: statusBarHeight / height),
                                .init(color: .clear, location: 1),
                            ], startPoint: .top, endPoint: .bottom)
                        }
                }
            }
                .offset(y: -statusBarHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct MobileBrowserBottomBackdrop: View {
    let toolbarHeight: CGFloat
    let bottomInset: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let coveredHeight = toolbarHeight + bottomInset
        let height = coveredHeight + 32
        Group {
            if reduceTransparency {
                Rectangle().fill(.background).frame(height: coveredHeight)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(height: height)
                    .mask {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 32 / height),
                            .init(color: .black, location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                    }
            }
        }
        .offset(y: bottomInset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum MobileBrowserSheet: Identifiable {
    case menu, library(BrowserLibrarySection)
    var id: String {
        switch self {
        case .menu: "menu"
        case .library(let section): "library-\(section.id)"
        }
    }
}
#endif
