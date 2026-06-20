import AdaEngine
import SloppyClientCore
import SloppyClientUI

fileprivate let chatHeroWidth: Float = 720
fileprivate let chatContentWidth: Float = 840

@MainActor
public struct ChatScreen: View {
    @State private var viewModel: ChatScreenViewModel
    private let rootSafeAreaInsets: EdgeInsets
    private let onOpenSidebar: (@MainActor () -> Void)?

    public init(
        apiClient: SloppyAPIClient,
        settings: ClientSettings,
        connectionMonitor: ConnectionMonitor,
        onOpenSettings: @escaping @MainActor () -> Void,
        rootSafeAreaInsets: EdgeInsets = EdgeInsets(),
        onOpenSidebar: (@MainActor () -> Void)? = nil
    ) {
        self.rootSafeAreaInsets = rootSafeAreaInsets
        self.onOpenSidebar = onOpenSidebar
        _viewModel = State(
            initialValue: ChatScreenViewModel(
                apiClient: apiClient,
                settings: settings,
                connectionMonitor: connectionMonitor,
                onOpenSettings: onOpenSettings
            )
        )
    }
    
    public init(
        viewModel: ChatScreenViewModel,
        rootSafeAreaInsets: EdgeInsets = EdgeInsets(),
        onOpenSidebar: (@MainActor () -> Void)? = nil
    ) {
        self.rootSafeAreaInsets = rootSafeAreaInsets
        self.onOpenSidebar = onOpenSidebar
        _viewModel = State(initialValue: viewModel)
    }
    
    public var body: some View {
        ChatScreenContent(
            rootSafeAreaInsets: rootSafeAreaInsets,
            onOpenSidebar: onOpenSidebar
        )
        .environment(viewModel)
        .environment(viewModel.connectionMonitor)
    }
}

@MainActor
private struct ChatScreenContent: View {
    let rootSafeAreaInsets: EdgeInsets
    let onOpenSidebar: (@MainActor () -> Void)?
    
    @Environment(ChatScreenViewModel.self) private var viewModel
    @Environment(ConnectionMonitor.self) private var connectionMonitor
    
    var body: some View {
        ChatChrome(
            viewModel: viewModel,
            connectionMonitor: connectionMonitor,
            rootSafeAreaInsets: rootSafeAreaInsets
        )
        .navigationBarLeadingItems {
            ChatNavigationLeadingItems(
                viewModel: viewModel,
                onOpenSidebar: onOpenSidebar
            )
        }
        .navigationBarTrailingItems {
            ChatNavigationActions(viewModel: viewModel)
        }
        .overlay {
            ChatInitialLoadTrigger(viewModel: viewModel)
        }
    }
}

@MainActor
private struct ChatChrome: View {
    let viewModel: ChatScreenViewModel
    let connectionMonitor: ConnectionMonitor
    let rootSafeAreaInsets: EdgeInsets

    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if idiom == .phone {
                chromeLayout(contentWidth: phoneContentWidth)
            } else {
                GeometryReader { proxy in
                    chromeLayout(contentWidth: contentWidth(for: proxy.size.width))
                }
            }
        }

        ChatConnectionBar(connectionMonitor: connectionMonitor)

        ChatOverlayLayer(
            viewModel: viewModel,
            pickerWidth: pickerWidth,
            overlayTopInset: overlayTopInset
        )
    }

    private func chromeLayout(contentWidth: Float) -> some View {
        let heroWidth = heroWidth(for: contentWidth)
        let showsComposer = true

        return ZStack(anchor: .bottom) {
            if viewModel.transcript.isEmpty {
                ChatEmptyChatRegion(
                    viewModel: viewModel,
                    contentWidth: contentWidth,
                    heroWidth: heroWidth,
                    bottomClearance: composerScrollInset
                )
            } else {
                ChatTranscriptRegion(
                    viewModel: viewModel,
                    contentWidth: contentWidth,
                    heroWidth: heroWidth,
                    messagesTopInset: messagesTopInset,
                    composerScrollInset: composerScrollInset
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if showsComposer {
                ChatComposerOverlay(
                    viewModel: viewModel,
                    contentWidth: contentWidth,
                    composerBottomInset: composerBottomInset
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func contentWidth(for availableWidth: Float) -> Float {
        let horizontalInset = idiom == .phone ? theme.spacing.s * 2 : theme.spacing.l * 2
        return max(0, min(chatContentWidth, availableWidth - horizontalInset))
    }

    private func heroWidth(for contentWidth: Float) -> Float {
        min(contentWidth, chatHeroWidth)
    }

    private var pickerWidth: Float {
        if idiom == .phone {
            return max(280, min(320, screenPointWidth - theme.spacing.m * 2))
        }
        return 320
    }

    private var phoneContentWidth: Float {
        let available = max(0, screenPointWidth - rootSafeAreaInsets.leading - rootSafeAreaInsets.trailing)
        return max(0, available - theme.spacing.s * 2)
    }

    private var overlayTopInset: Float {
        ChatOverlayLayout.pickerTopInset(
            isPhone: idiom == .phone,
            rootSafeAreaTop: rootSafeAreaInsets.top,
            effectiveSafeAreaTop: safeAreaInsets.top
        )
    }

    private var composerScrollInset: Float {
        ChatComposerView.panelHeight(for: idiom) + composerScrollGap
    }

    private var composerBottomInset: Float {
        guard idiom == .phone else {
            return theme.spacing.m
        }

        return ChatComposerKeyboardLayout.phoneBottomInset(
            rootSafeAreaBottom: rootSafeAreaInsets.bottom,
            effectiveSafeAreaBottom: safeAreaInsets.bottom,
            normalMinimumSpacing: theme.spacing.s,
            keyboardSpacing: theme.spacing.xs
        )
    }

    private var messagesTopInset: Float {
        idiom == .phone ? theme.spacing.s : theme.spacing.xxl
    }

    private var composerScrollGap: Float {
        idiom == .phone ? theme.spacing.l : theme.spacing.xxl
    }

    private var screenPointWidth: Float {
        guard let screen = Screen.main else {
            return 390
        }
        return max(320, screen.size.width)
    }
}

struct ChatComposerKeyboardLayout {
    private static let keyboardSafeAreaEpsilon: Float = 1

    static func phoneBottomInset(
        rootSafeAreaBottom: Float,
        effectiveSafeAreaBottom: Float,
        normalMinimumSpacing: Float,
        keyboardSpacing: Float
    ) -> Float {
        let keyboardSafeAreaIsActive = effectiveSafeAreaBottom > rootSafeAreaBottom + keyboardSafeAreaEpsilon
        if keyboardSafeAreaIsActive {
            return keyboardSpacing
        }

        return max(normalMinimumSpacing, rootSafeAreaBottom + keyboardSpacing)
    }
}

struct ChatOverlayLayout {
    static func pickerTopInset(
        isPhone: Bool,
        rootSafeAreaTop: Float,
        effectiveSafeAreaTop: Float
    ) -> Float {
        if isPhone {
            return rootSafeAreaTop + 52
        }

        return effectiveSafeAreaTop
    }
}

@MainActor
private struct ChatInitialLoadTrigger: View {
    let viewModel: ChatScreenViewModel

    var body: some View {
        EmptyView()
            .onAppear {
                viewModel.loadInitialData()
            }
    }
}

@MainActor
private struct ChatNavigationLeadingItems: View {
    let viewModel: ChatScreenViewModel
    let onOpenSidebar: (@MainActor () -> Void)?

    @Environment(\.userInterfaceIdiom) private var idiom

    var body: some View {
        if idiom == .phone {
            MobileChatNavigationHeader(
                viewModel: viewModel,
                onOpenSidebar: onOpenSidebar
            )
        } else {
            desktopBody
        }
    }

    private var desktopBody: some View {
        HStack(spacing: 8) {
            if let onOpenSidebar {
                Button(action: onOpenSidebar) {
                    Icons.symbol(.menu, size: 15)
                        .foregroundColor(.white.opacity(0.72 as Float))
                        .frame(width: 30, height: 30)
                }
            }

            agentNavigationButton
        }
    }

    @ViewBuilder
    private var agentNavigationButton: some View {
        Button(action: { viewModel.showAgentPicker = true }) {
            HStack(spacing: 8) {
                Text(viewModel.selectedAgent?.displayName ?? "Select Agent")
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Icons.symbol(.expandMore, size: 12)
                    .foregroundColor(.white.opacity(0.55 as Float))
            }
        }
    }
}

@MainActor
private struct MobileChatNavigationHeader: View {
    let viewModel: ChatScreenViewModel
    let onOpenSidebar: (@MainActor () -> Void)?

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.s) {
            if let onOpenSidebar {
                MobileChatNavigationIconButton(symbol: .menu, action: onOpenSidebar)
            }

            MobileChatNavigationCenterCapsule(viewModel: viewModel)
        }
    }
}

@MainActor
private struct MobileChatNavigationCenterCapsule: View {
    let viewModel: ChatScreenViewModel

    @Environment(\.theme) private var theme
    
    var body: some View {
        HStack(spacing: theme.spacing.s) {
            VStack(alignment: .leading, spacing: 1) {
                Text(compactAgentName)
                    .font(.system(size: theme.typography.caption))
                    .foregroundColor(theme.colors.textPrimary)
                    .lineLimit(1)
                
                Text(sessionLabel)
                    .font(.system(size: theme.typography.micro))
                    .foregroundColor(theme.colors.textMuted)
                    .lineLimit(1)
            }
            
            Icons.symbol(.expandMore, size: theme.typography.caption)
                .foregroundColor(theme.colors.textMuted)
        }
        .padding(.horizontal, theme.spacing.s)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 46, maxHeight: 46, alignment: .leading)
        .onTap {
            viewModel.showAgentPicker = true
        }
    }

    private var compactAgentName: String {
        let name = viewModel.selectedAgent?.displayName ?? "Agent"
        guard name.count > 18 else {
            return name
        }
        return String(name.prefix(17)) + "..."
    }

    private var sessionLabel: String {
        viewModel.selectedSessionId == nil ? "New chat" : "Recent session"
    }

    private var mobileNavigationCapsuleWidth: Float {
        let horizontalMargins = theme.spacing.l * 2
        let leftClusterWidth: Float = 44 + theme.spacing.s
        let rightClusterWidth: Float = 44 * 2 + theme.spacing.xs + theme.spacing.s
        let available: Float = screenPointWidth - horizontalMargins - leftClusterWidth - rightClusterWidth
        return max(150, min(236, available))
    }

    private var screenPointWidth: Float {
        guard let screen = Screen.main else {
            return 390
        }
        return max(320, screen.size.width)
    }
}

@MainActor
private struct MobileChatNavigationIconButton: View {
    let symbol: MaterialSymbol
    let action: @MainActor () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Icons.symbol(symbol, size: theme.typography.heading)
                .foregroundColor(theme.colors.textPrimary)
                .frame(width: 44, height: 44)
        }
    }
}

@MainActor
private struct ChatNavigationActions: View {
    let viewModel: ChatScreenViewModel

    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography
        let isPhone = idiom == .phone

        return HStack(spacing: isPhone ? sp.xs : sp.s) {
            if isPhone {
                MobileChatNavigationIconButton(symbol: .chatAddOn) {
                    viewModel.showSessionPicker = true
                }
            } else {
                Button(action: { viewModel.showSessionPicker = true }) {
                    HStack(spacing: sp.s) {
                        Text("Sessions")
                            .font(.system(size: ty.caption))
                            .foregroundColor(c.textSecondary)
                        Icons.symbol(.expandMore, size: ty.micro)
                            .foregroundColor(c.textMuted)
                    }
                }
            }
        }
    }
}

@MainActor
private struct ChatConnectionBar: View {
    let connectionMonitor: ConnectionMonitor

    @ViewBuilder
    var body: some View {
        if connectionMonitor.state != .connected {
            HStack {
                Spacer()
                ConnectionBanner(
                    state: connectionMonitor.state,
                    endpoint: connectionMonitor.checkedURL?.absoluteString,
                    message: connectionMonitor.lastFailureMessage
                )
                Spacer()
            }
        }
    }
}

@MainActor
private struct ChatOverlayLayer: View {
    let viewModel: ChatScreenViewModel
    let pickerWidth: Float
    let overlayTopInset: Float

    @ViewBuilder
    var body: some View {
        if viewModel.showAgentPicker {
            overlayDim
                .overlay(anchor: .topLeading) {
                    AgentPickerView(
                        agents: viewModel.agents,
                        selectedAgent: viewModel.selectedAgent,
                        onSelect: { agent in
                            viewModel.pickAgent(agent)
                        },
                        onDismiss: { viewModel.showAgentPicker = false }
                    )
                    .frame(width: pickerWidth)
                    .padding(.top, overlayTopInset)
                }
        }

        if viewModel.showSessionPicker {
            overlayDim
                .overlay(anchor: .topLeading) {
                    SessionPickerView(
                        sessions: viewModel.sessions,
                        selectedSessionId: viewModel.selectedSessionId,
                        isLoading: viewModel.isLoadingSessions,
                        actionStatus: viewModel.sessionActionStatus,
                        pinnedSessionIds: viewModel.pinnedSessionIds,
                        onSelect: { session in
                            viewModel.pickSession(session)
                        },
                        onNewSession: {
                            viewModel.pickNewSession()
                        },
                        onDelete: { session in
                            viewModel.deleteSession(session)
                        },
                        onTogglePin: { session in
                            viewModel.toggleSessionPinned(session)
                        },
                        onCopyDebugLink: { session in
                            viewModel.copyDebugSessionLink(session)
                        },
                        onDownloadDebug: { session in
                            #if DEBUG
                            viewModel.downloadSession(session)
                            #endif
                        },
                        onDismiss: { viewModel.showSessionPicker = false }
                    )
                    .frame(width: pickerWidth)
                    .padding(.top, overlayTopInset)
                }
        }
    }

    private var overlayDim: some View {
        Color.black.opacity(0.4 as Float)
            .ignoresSafeArea()
            .onTap {
                viewModel.dismissOverlays()
            }
    }
}

@MainActor
private struct ChatTranscriptRegion: View {
    let viewModel: ChatScreenViewModel
    let contentWidth: Float
    let heroWidth: Float
    let messagesTopInset: Float
    let composerScrollInset: Float

    var body: some View {
        ChatTranscriptPane(
            transcript: viewModel.transcript,
            agentName: viewModel.selectedAgent?.displayName ?? "Agent",
            contentWidth: contentWidth,
            heroWidth: heroWidth,
            messagesTopInset: messagesTopInset,
            composerScrollInset: composerScrollInset
        )
    }
}

@MainActor
private struct ChatEmptyChatRegion: View {
    let viewModel: ChatScreenViewModel
    let contentWidth: Float
    let heroWidth: Float
    let bottomClearance: Float

    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.xl) {
            Spacer(minLength: idiom == .phone ? theme.spacing.xxl : theme.spacing.l)
            ChatGreetingView(agentName: viewModel.selectedAgent?.displayName ?? "Agent")
                .frame(width: heroWidth)
            Spacer(minLength: bottomClearance)
        }
        .padding(.horizontal, idiom == .phone ? theme.spacing.s : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

@MainActor
private struct ChatComposerOverlay: View {
    let viewModel: ChatScreenViewModel
    let contentWidth: Float
    let composerBottomInset: Float

    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            composerBar
                .frame(width: contentWidth)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, idiom == .phone ? theme.spacing.xs : 0)
        .padding(.bottom, composerBottomInset)
    }

    @ViewBuilder
    private var composerBar: some View {
        if let agent = viewModel.selectedAgent {
            ChatComposerView(draft: viewModel.composerDraft, agentName: agent.displayName) { content in
                viewModel.sendMessage(content: content)
            }
        } else {
            ChatComposerView(draft: viewModel.composerDraft, agentName: "Agent") { _ in }
                .disabled(true)
        }
    }
}

@MainActor
private struct ChatTranscriptPane: View {
    let transcript: ChatTranscriptState
    let agentName: String
    let contentWidth: Float
    let heroWidth: Float
    let messagesTopInset: Float
    let composerScrollInset: Float

    @Environment(\.theme) private var theme

    var body: some View {
        if transcript.isEmpty {
            VStack(spacing: theme.spacing.xl) {
                Color.clear
                    .frame(height: 300)
                ChatGreetingView(agentName: agentName)
                    .frame(width: heroWidth)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        if transcript.hasEarlierMessages {
                            revealEarlierButton
                                .padding(.top, messagesTopInset)
                                .padding(.bottom, theme.spacing.m)
                        }

                        LazyVStack(
                            transcript.messages,
                            alignment: .leading,
                            spacing: theme.spacing.xl,
                            estimatedRowHeight: 168,
                            overscan: 8
                        ) { msg in
                            ChatBubbleView(message: msg)
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .allowsHitTesting(false)
                        }
                        .padding(.top, transcript.hasEarlierMessages ? 0 : messagesTopInset)
                        .padding(.bottom, composerScrollInset)
                    }
                    .onChange(of: transcript.messages.count) { oldCount, newCount in
                        guard newCount > oldCount,
                              oldCount == 0 || proxy.isNearBottom(threshold: 220),
                              let lastMessageId = transcript.lastMessage?.id else {
                            return
                        }

                        Task { @MainActor in
                            proxy.scrollTo(lastMessageId, anchor: .bottom)
                        }
                    }
                    .onChange(of: latestAssistantMessageLayoutKey) { _, _ in
                        guard proxy.isNearBottom(threshold: 480),
                              let lastMessage = transcript.lastMessage,
                              lastMessage.role == .assistant else {
                            return
                        }

                        Task { @MainActor in
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .frame(width: contentWidth)
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var latestAssistantMessageLayoutKey: String {
        guard let message = transcript.lastMessage,
              message.role == .assistant else {
            return ""
        }
        return "\(message.id):\(message.textContent.count)"
    }

    private var revealEarlierButton: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography
        let count = min(64, transcript.hiddenMessageCount)

        return HStack {
            Spacer(minLength: 0)
            Button("Show \(count) earlier") {
                transcript.revealEarlierMessages()
            }
            .font(.system(size: ty.caption))
            .foregroundColor(c.textSecondary)
            .padding(.horizontal, sp.m)
            .padding(.vertical, sp.s)
            .background(c.surface.opacity(0.74 as Float))
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            Spacer(minLength: 0)
        }
    }
}
