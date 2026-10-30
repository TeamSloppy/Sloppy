import SwiftUI
import SloppyClientUI
import SloppyFeatureChat

@MainActor
struct BrowserAgentChatPanel: View {
    let state: BrowserAgentChatState
    let browser: BrowserWorkspaceState
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("Assistant", systemImage: "bubble.left.and.bubble.right")
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
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
                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }
#if os(macOS)
                .menuStyle(.borderlessButton)
#endif
                .fixedSize()
                .accessibilityLabel("Assistant conversations")
                Button(action: state.hide) { Image(systemName: "xmark").frame(width: 28, height: 28) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hide assistant")
                    .accessibilityIdentifier("browser-agent-close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()
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
            if let error = state.contextError {
                Text(error).font(.caption).foregroundStyle(theme.colors.statusBlocked)
                    .padding(.horizontal, 16).padding(.vertical, 6)
            }
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    ChatScreen(viewModel: state.chat, showsContextToolbar: false, showsNavigationToolbar: false)
                    ChatComposerOverlay(viewModel: state.chat, contentWidth: max(0, geometry.size.width - 24),
                        composerBottomInset: theme.spacing.m, tabs: [], tabActions: nil)
                }
            }
        }
        .environment(\.chatUsesCompactLayout, true)
        .background(theme.colors.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-agent-panel")
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
