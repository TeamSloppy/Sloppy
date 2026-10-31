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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            page
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !state.isSearchPresented {
                        MobileBrowserToolbar(state: state, onNewTab: newTab, onTabs: openTabs,
                                             onMenu: { sheet = .menu }, onAssistant: askAgent,
                                             isCollapsed: toolbarCollapse.isCollapsed, onExpand: toolbarCollapse.expand,
                                             onExpandedHeightChange: { height in
                                                 if height > 0, height != expandedToolbarHeight { expandedToolbarHeight = height }
                                             })
                            .frame(maxWidth: 640)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)
                    }
                }
                .background(pageBackground.ignoresSafeArea(.container))
                .toolbar(.hidden, for: .navigationBar)
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
        }
        .onDisappear { state.checkpoint() }
        .onChange(of: state.selectedID) { _, _ in toolbarCollapse.expand() }
        .onChange(of: state.selectedTab?.url) { _, _ in toolbarCollapse.expand() }
        .onChange(of: state.selectedPage?.isLoading) { _, loading in if loading == true { toolbarCollapse.expand() } }
        .onChange(of: state.isBrowsing) { _, _ in toolbarCollapse.expand() }
        .onChange(of: state.isSearchPresented) { _, shown in
            if shown { pendingAgentPrompt = nil; toolbarCollapse.expand() }
        }
        .onChange(of: showsTabs) { _, shown in if shown { toolbarCollapse.expand() } }
        .preference(key: MobileBrowserChromeSchemePreferenceKey.self, value: chromeScheme)
    }

    @ViewBuilder
    private var page: some View {
        if let tab = state.selectedTab, tab.url != nil, let page = state.pages[tab.id] {
            BrowserWorkspacePage(page: page, restoredState: tab.interactionState,
                                 onAsk: onAskAgent, annotationTarget: onAnnotateSelection,
                                 onScroll: { sample in
                                     guard state.isBrowsing, state.selectedID == tab.id,
                                           !state.isSearchPresented, !showsTabs, sheet == nil,
                                           agentChat?.panel.isPresented != true else { return }
                                     toolbarCollapse.consume(sample, transitionDistance: expandedToolbarHeight)
                                 })
                .id(ObjectIdentifier(page))
        } else {
            MobileBrowserHomeView(state: state, onLibrary: { sheet = .library($0) },
                                  onSearch: { state.presentSearch(newTab: state.selectedID == nil) }, onAskAgent: askAgent)
        }
    }

    private var pageBackground: Color {
        Color(uiColor: state.selectedTab?.url == nil ? .systemGroupedBackground
            : state.selectedPage?.browserBackgroundColor ?? .systemBackground)
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
