import Foundation
import SwiftUI
import WebKit
import SloppyClientUI

@MainActor
struct BrowserWorkspaceView: View {
    @Bindable var state: BrowserWorkspaceState
    let onAskAgent: (String) -> Void
    let onCollect: ([BrowserTabRecord]) -> Void
    var onSettings: () -> Void = {}
    var onAnnotateSelection: BrowserTextAnnotationTarget?
    var agentChat: BrowserAgentChatState?
    @State private var librarySection: BrowserLibrarySection?
    @Environment(\.theme) private var theme
    @State private var compactColumn = NavigationSplitViewColumn.detail

    var body: some View {
#if os(macOS)
        // Disabling hit testing on the native split view drops its titlebar safe area.
        // The search overlay already intercepts clicks on the content underneath.
        browserSurface
            .task { await state.extensions.restore() }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .accessibilityHidden(state.isSearchPresented)
            .overlay {
                if state.isSearchPresented {
                    BrowserSearchOverlay(state: state, onAskAgent: onAskAgent)
                }
            }
            .onDisappear { state.isSearchPresented = false }
#elseif os(iOS)
        MobileBrowserWorkspaceView(state: state, onAskAgent: onAskAgent, onCollect: onCollect,
                                   onSettings: onSettings, onAnnotateSelection: onAnnotateSelection,
                                   agentChat: agentChat)
#else
        browserSurface
            .sheet(isPresented: $state.isSearchPresented) {
                BrowserSearchSheet(state: state, onAskAgent: onAskAgent, maximumResultsHeight: 220)
                    .presentationBackground(.clear)
                    .presentationDetents([.height(searchHeight)])
                    .presentationDragIndicator(.visible)
            }
#endif
    }

    private var searchHeight: CGFloat {
        let count = BrowserSearchResult.make(query: state.searchText, engine: state.searchEngine, tabs: state.tabs,
                                             bookmarks: state.library.bookmarks, history: state.history.sites).count
        return 112 + min(220, CGFloat(count) * 50 + 16)
    }

    private var browserSurface: some View {
        NavigationSplitView(columnVisibility: $state.columnVisibility, preferredCompactColumn: $compactColumn) {
            BrowserSidebar(state: state, onLibrary: { librarySection = $0 }, onSettings: onSettings, onCollect: onCollect)
            .navigationTitle("Browse")
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
#else
            .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 360)
#endif
        } detail: {
            BrowserAgentChatContainer(state: agentChat, browser: state) { toolbarInset in
                browserPageSurface(toolbarInset: toolbarInset)
            }
            .navigationTitle(state.selectedTab?.title ?? "Browse")
            .toolbar {
                if let agentChat {
#if os(macOS)
                    ToolbarSpacer(.flexible, placement: .primaryAction)
#endif
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: agentChat.toggle) {
                            Label("Assistant", systemImage: "sidebar.right")
                        }
                        .labelStyle(.titleAndIcon)
                        .help(agentChat.panel.isPresented ? "Hide assistant" : "Show assistant")
                        .accessibilityIdentifier("browser-agent-toggle")
                        .accessibilityValue(agentChat.panel.isPresented ? "Expanded" : "Collapsed")
                    }
                }
            }
#if os(macOS)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 0) {
                        BrowserNavigationButtons(state: state, group: .history)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .frame(height: 36)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.bottom, 8)
                }
                .sharedBackgroundVisibility(.hidden)
                if let split = state.activeSplit, let member = split.tabIDs.first {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Separate Split View", systemImage: "rectangle") { state.separateSplit(containing: member) }
                            .accessibilityIdentifier("browser-separate-split")
                    }
                }
            }
#endif
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { state.presentSearch(newTab: false) } label: { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel("Search or enter an address")
                }
            }
#endif
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: state.selectedID) { _, _ in compactColumn = .detail }
        .sheet(item: $librarySection) { BrowserLibrarySheet(section: $0, state: state) }
    }

    private func browserPageSurface(toolbarInset: CGFloat) -> some View {
        GeometryReader { geometry in
            ZStack {
#if os(macOS)
                if let split = state.activeSplit {
                    BrowserSplitWorkspaceView(state: state, split: split) { tab in
                        pageView(tab, topContentInset: 0)
                    }
                    .padding(.top, toolbarInset)
                    .ignoresSafeArea(.container, edges: [.bottom, .trailing])
                }
#endif
                if !isShowingSplit, let tab = state.selectedTab {
                    pageView(tab, topContentInset: max(toolbarInset, pageTopInset(geometry)))
#if os(macOS)
                        .ignoresSafeArea(.container, edges: [.top, .bottom, .trailing])
#else
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.colors.border, lineWidth: 1) }
                        .padding(8)
#endif
                }
                if state.selectedID == nil {
                    BrowserHomeView(
                        state: state,
                        onAskAgent: onAskAgent,
                        showsComposer: agentChat?.panel.isPresented != true,
                        onComposerDismissed: {
                            if state.isBrowsing { agentChat?.finishHomeComposerHandoff() }
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
#if os(macOS)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(theme.colors.border)
                    .frame(width: 1)
                    .ignoresSafeArea(.container, edges: [.top, .bottom])
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 12)
#endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.colors.background)
    }

    private func pageTopInset(_ geometry: GeometryProxy) -> CGFloat {
#if os(macOS)
        geometry.safeAreaInsets.top
#else
        0
#endif
    }

    private var isShowingSplit: Bool {
#if os(macOS)
        state.activeSplit != nil
#else
        false
#endif
    }

    @ViewBuilder
    private func pageView(_ tab: BrowserTabRecord, topContentInset: CGFloat) -> some View {
        if let page = state.pages[tab.id] {
            BrowserWorkspacePage(page: page, restoredState: tab.interactionState,
                                 topContentInset: topContentInset, onAsk: { onAskAgent($0) },
                                 annotationTarget: onAnnotateSelection,
                                 onFocus: focusHandler(for: tab.id))
                .id(ObjectIdentifier(page))
        }
    }

    private func focusHandler(for id: UUID) -> (@MainActor () -> Void)? {
        guard isShowingSplit else { return nil }
        return { if state.selectedID != id { state.select(id) } }
    }
}

@MainActor
struct BrowserWorkspacePage: View {
    let page: WorkspaceWebViewModel
    let restoredState: Data?
    var topContentInset: CGFloat = 0
    var onAsk: (@MainActor (String) -> Void)?
    var annotationTarget: BrowserTextAnnotationTarget?
    var onFocus: (@MainActor () -> Void)?
    var onScroll: (@MainActor (BrowserScrollSample) -> Void)?
    var showsNavigationError = true
    @State private var hasRestored = false
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            webContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("browser-web-page")
                .overlay(alignment: .top) {
                    if showsNavigationError {
                        BrowserNavigationErrorBanner(page: page)
                        .padding(12)
                        .padding(.top, topContentInset)
                    }
                }
                .onAppear {
                    page.textSelection.onAsk = onAsk
                    page.textSelection.annotationTarget = annotationTarget
                    guard !hasRestored else { return }
                    hasRestored = true
                    guard page.nativeWebView?.url == nil, page.nativeWebView?.isLoading != true else { return }
                    if let restoredState, let webView = page.nativeWebView {
                        webView.interactionState = restoredState
                        if webView.backForwardList.currentItem != nil { return }
                    }
                    page.openAddress()
                }
                .onDisappear {
                    page.textSelection.dismiss()
                    page.textSelection.onAsk = nil
                    page.textSelection.annotationTarget = nil
                }
        }
    }

    private var webContent: some View {
#if os(macOS)
        WorkspaceWebView(viewModel: page, topContentInset: topContentInset, onFocus: onFocus)
            .overlay {
                if page.annotations.isSelecting || page.annotations.isCapturing {
                    WorkspaceBrowserAnnotationPicker(model: page.annotations)
                } else if let draft = page.annotations.draft {
                    WorkspaceBrowserAnnotationOverlay(model: page.annotations, draft: draft)
                }
            }
            .overlay(alignment: .top) {
                if let error = page.annotations.errorMessage {
                    Text(error).font(.caption).foregroundStyle(theme.colors.statusBlocked)
                        .padding(10).background(theme.colors.surfaceRaised)
                        .padding(.top, topContentInset)
                }
            }
            .onDisappear { page.annotations.cancel() }
#elseif os(iOS)
        WorkspaceWebView(viewModel: page, onScroll: onScroll)
#else
        WorkspaceWebView(viewModel: page)
#endif
    }
}
