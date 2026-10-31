import SwiftUI
import SloppyClientUI
import SloppyFeatureChat

@MainActor
struct BrowserAgentChatPanel: View {
    let state: BrowserAgentChatState
    let browser: BrowserWorkspaceState
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
#if os(iOS)
            NavigationStack {
                panelContent
                    .navigationTitle("Assistant")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            GlassEffectContainer(spacing: 8) {
                                HStack(spacing: 8) {
                                    conversationsMenu
                                        .glassEffect(.regular.tint(.white.opacity(0.16)).interactive(), in: Circle())
                                    closeButton
                                        .glassEffect(.regular.tint(.white.opacity(0.16)).interactive(), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.white)
                                .tint(.white)
                            }
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
            }
#else
            panelContent
#endif
        }
#if os(macOS)
        .onChange(of: browser.selectedID) { _, _ in state.cancelElementAnnotation() }
        .onChange(of: state.chat.selectedSessionId) { _, _ in state.cancelElementAnnotation() }
        .onChange(of: state.chat.selectedAgent?.id) { _, _ in state.cancelElementAnnotation() }
        .onDisappear { state.cancelElementAnnotation() }
#endif
        .environment(\.chatUsesCompactLayout, true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-agent-panel")
    }

    private var panelContent: some View {
        VStack(spacing: 0) {
#if !os(iOS)
            HStack(spacing: 10) {
                Label("Assistant", systemImage: "bubble.left.and.bubble.right")
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
                conversationsMenu
#if os(macOS)
                    .menuStyle(.borderlessButton)
#endif
                    .fixedSize()
                closeButton
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()
#endif
            if let tab = browser.selectedTab, tab.url != nil {
                Button {
                    Task { await state.addCurrentPage(from: browser) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                        Text("Add page: \(browser.selectedPage?.pageTitle ?? tab.title)").lineLimit(1)
                        Spacer(minLength: 0)
                        if state.isAddingPage { ProgressView().controlSize(.mini) }
                    }
                    .font(.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(state.isAddingPage || browser.selectedPage?.isLoading == true)
                .accessibilityIdentifier("browser-agent-add-page")
            }
#if os(macOS)
            if let page = browser.selectedPage, BrowserSearchEngine.websiteURL(page.currentURL) != nil {
                let active = page.annotations.isSelecting || page.annotations.draft != nil
                Button {
                    Task { await state.toggleElementAnnotation(in: browser) }
                } label: {
                    Label(active ? "Cancel annotation" : "Annotate element", systemImage: "cursorarrow.click.2")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(active ? theme.colors.textPrimary : theme.colors.textSecondary)
                .disabled(page.isLoading || page.annotations.isCapturing)
                .help("Select a page element and add its HTML details to this chat")
                .accessibilityIdentifier("browser-agent-annotate")
            }
#endif
            if let error = state.contextError {
                Text(error).font(.caption).foregroundStyle(theme.colors.statusBlocked)
                    .padding(.horizontal, 16).padding(.vertical, 6)
            }
            GeometryReader { geometry in
#if os(iOS)
                let composerWidth = geometry.size.width
                let composerInset: CGFloat? = 0
#else
                let composerWidth = max(0, geometry.size.width - 24)
                let composerInset: CGFloat? = nil
#endif
                ZStack(alignment: .bottom) {
                    ChatScreen(viewModel: state.chat, showsContextToolbar: false, showsNavigationToolbar: false)
                    ChatComposerOverlay(
                        viewModel: state.chat,
                        contentWidth: composerWidth,
                        composerHorizontalInset: composerInset,
                        composerBottomInset: theme.spacing.m,
                        tabs: [],
                        tabActions: nil
                    )
                }
            }
        }
        .background(theme.colors.background)
    }

    private var conversationsMenu: some View {
        Menu {
            Button("New chat", systemImage: "square.and.pencil") { state.chat.pickNewSession() }
                .disabled(state.chat.selectedAgent == nil || state.chat.isSending)
            if !state.chat.sessions.isEmpty {
                Section("Recent chats") {
                    ForEach(state.chat.sessions.prefix(12)) { session in
                        Button(session.title) { state.chat.pickSession(session) }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis").frame(width: headerButtonSize, height: headerButtonSize)
        }
        .accessibilityLabel("Assistant conversations")
        .accessibilityIdentifier("browser-agent-conversations")
    }

    private var closeButton: some View {
        Button(action: state.hide) {
            Image(systemName: "xmark").frame(width: headerButtonSize, height: headerButtonSize)
        }
        .accessibilityLabel("Hide assistant")
        .accessibilityIdentifier("browser-agent-close")
    }

    private var headerButtonSize: CGFloat {
#if os(iOS)
        44
#else
        28
#endif
    }
}

/// The browser's native sidebar stays outside the chat's resizing boundary.
@MainActor
struct BrowserAgentChatContainer<Content: View>: View {
    let state: BrowserAgentChatState?
    let browser: BrowserWorkspaceState
    @ViewBuilder let content: (CGFloat) -> Content

    var body: some View {
        if let state {
#if os(macOS)
            GeometryReader { geometry in
                let toolbarInset = geometry.safeAreaInsets.top
                WorkspaceResizableSidePanel(state: state.panel, minimumPanelWidth: 340) {
                    content(toolbarInset)
                } panel: {
                    BrowserAgentChatPanel(state: state, browser: browser)
                        .padding(.top, toolbarInset)
                }
                .ignoresSafeArea(.container, edges: .top)
            }
#else
            content(0)
                .inspector(isPresented: Binding(get: { state.panel.isPresented }, set: { if $0 { state.show() } else { state.hide() } })) {
                    BrowserAgentChatPanel(state: state, browser: browser)
                        .inspectorColumnWidth(min: 320, ideal: 420, max: 600)
                        .presentationDetents([.large])
                }
#endif
        } else {
            content(0)
        }
    }
}
