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
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme
    @State private var keyboardOccludedHeight: Float = 0

    var body: some View {
        NavigationStack {
            chatChrome
                .background(idiom == .phone ? theme.colors.background.ignoresSafeArea() : Color.clear.ignoresSafeArea())
                .navigationBarLeadingItems {
                    leadingNavigationItems
                }
                .navigationBarTrailingItems {
                    navigationActions
                }
                .onAppear { viewModel.loadInitialData() }
        }
    }

    private var chatChrome: some View {
        ZStack(anchor: .topLeading) {
            ZStack(anchor: .bottom) {
                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                composerOverlay
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            connectionBar
            
            overlayContent
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
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
                        onSelect: { session in
                            viewModel.pickSession(session)
                        },
                        onNewSession: {
                            viewModel.pickNewSession()
                        },
                        onDelete: { session in
                            viewModel.deleteSession(session)
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

    // MARK: - Navigation Bar

    private var leadingNavigationItems: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography
        let isPhone = idiom == .phone

        return HStack(spacing: isPhone ? sp.xs : sp.s) {
            if let onOpenSidebar {
                Button(action: onOpenSidebar) {
                    Icons.symbol(.menu, size: ty.body)
                        .foregroundColor(c.textSecondary)
                        .frame(width: isPhone ? 28 : 30, height: isPhone ? 28 : 30)
                }
            }

            agentNavigationButton
        }
    }

    @ViewBuilder
    private var agentNavigationButton: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography
        let isPhone = idiom == .phone

        let button = Button(action: { viewModel.showAgentPicker = true }) {
            HStack(spacing: isPhone ? sp.xs : sp.s) {
                Text(isPhone ? shortAgentName : (viewModel.selectedAgent?.displayName ?? "Select Agent"))
                    .font(.system(size: isPhone ? ty.caption : ty.body))
                    .foregroundColor(c.textPrimary)
                    .lineLimit(1)
                Icons.symbol(.expandMore, size: isPhone ? ty.micro : ty.caption)
                    .foregroundColor(c.textMuted)
            }
        }

        if isPhone {
            button.frame(width: phoneAgentPickerWidth, alignment: .leading)
        } else {
            button
        }
    }

    private var navigationActions: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography
        let isPhone = idiom == .phone

        return HStack(spacing: isPhone ? sp.xs : sp.s) {
            if viewModel.selectedSessionId != nil {
                Button(action: { viewModel.showSessionPicker = true }) {
                    if isPhone {
                        Icons.symbol(.chatAddOn, size: ty.body)
                            .foregroundColor(c.textMuted)
                            .frame(width: 28, height: 28)
                    } else {
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

            Button(action: viewModel.openSettings) {
                if isPhone {
                    Icons.symbol(.settings, size: ty.body)
                        .foregroundColor(c.textSecondary)
                        .frame(width: 28, height: 28)
                } else {
                    Text("Settings")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.textSecondary)
                }
            }
        }
    }

    // MARK: - Connection Bar

    @ViewBuilder
    private var connectionBar: some View {
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

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.messages.isEmpty {
            VStack(spacing: theme.spacing.xl) {
                Spacer()
                ChatGreetingView(agentName: viewModel.selectedAgent?.displayName ?? "Agent")
                    .frame(width: heroWidth)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: theme.spacing.xl) {
                            ForEach(viewModel.messages) { msg in
                                ChatBubbleView(message: msg)
                                    .frame(minWidth: 0, maxWidth: .infinity)
                                    .allowsHitTesting(false)
                                    .id(msg.id)
                            }
                        }
                        .padding(.top, messagesTopInset)
                        .padding(.bottom, composerScrollInset)
                    }
                    .onChange(of: viewModel.messages.count) { oldCount, newCount in
                        guard newCount > oldCount,
                              oldCount == 0 || proxy.isNearBottom(threshold: 160),
                              let lastMessageId = viewModel.messages.last?.id else {
                            return
                        }

                        Task { @MainActor in
                            proxy.scrollTo(lastMessageId, anchor: .bottom)
                        }
                    }
                }
                .frame(width: contentWidth)
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var quickActionRow: some View {
        let sp = theme.spacing

        return HStack(spacing: sp.s) {
            quickActionButton("Explain this project to me")
            quickActionButton("Review the active tasks in this workspace")
            quickActionButton("Suggest a starter implementation plan")
        }
    }

    private func quickActionButton(_ title: String) -> some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return Button(action: {
            viewModel.sendMessage(content: title)
        }) {
            HStack(spacing: sp.s) {
                Icons.symbol(.openInNew, size: ty.caption)
                    .foregroundColor(c.accentCyan)

                Text(title)
                    .font(.system(size: ty.body))
                    .foregroundColor(c.textSecondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, sp.m)
            .padding(.vertical, sp.m)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
        }
        .frame(width: chatHeroWidth)
    }

    // MARK: - Composer

    @ViewBuilder
    private var composerOverlay: some View {
        HStack {
            Spacer(minLength: 0)
            composerBar
                .frame(width: contentWidth)
            Spacer(minLength: 0)
        }
        .padding(.bottom, composerBottomInset)
    }

    private var composerScrollInset: Float {
        ChatComposerView.panelHeight(for: idiom) + composerScrollGap + keyboardLift
    }

    private var composerBottomInset: Float {
        let base = idiom == .phone ? theme.spacing.s : theme.spacing.m
        guard keyboardLift > 0 else {
            return base
        }
        return keyboardLift + theme.spacing.s
    }

    private var keyboardLift: Float {
        max(0, keyboardOccludedHeight - safeAreaInsets.bottom)
    }

    private var messagesTopInset: Float {
        idiom == .phone ? theme.spacing.s : theme.spacing.xl
    }

    private var composerScrollGap: Float {
        idiom == .phone ? theme.spacing.l : theme.spacing.xxl
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

    // MARK: - Overlay dim

    private var overlayDim: some View {
        Color.black.opacity(0.4 as Float)
            .ignoresSafeArea()
            .onTap {
                viewModel.dismissOverlays()
            }
    }

    private var contentWidth: Float {
        if idiom == .phone {
            return max(280, screenPointWidth - theme.spacing.s * 2)
        }
        return chatContentWidth
    }

    private var heroWidth: Float {
        if idiom == .phone {
            return contentWidth
        }
        return chatHeroWidth
    }

    private var pickerWidth: Float {
        if idiom == .phone {
            return max(280, min(320, screenPointWidth - theme.spacing.m * 2))
        }
        return 320
    }

    private var navigationControlsTopOffset: Float {
        idiom == .phone ? rootSafeAreaInsets.top : 0
    }

    private var overlayTopInset: Float {
        idiom == .phone ? rootSafeAreaInsets.top + 52 : 0
    }

    private var phoneAgentPickerWidth: Float {
        let reservedButtonCount: Float = viewModel.selectedSessionId == nil ? 2 : 3
        let reserved = reservedButtonCount * 36 + reservedButtonCount * theme.spacing.s + theme.spacing.s * 2
        return min(160, max(112, contentWidth - reserved))
    }

    private var shortAgentName: String {
        let name = viewModel.selectedAgent?.displayName ?? "Agent"
        guard name.count > 18 else {
            return name.uppercased()
        }
        return String(name.prefix(17)).uppercased() + "..."
    }

    private var screenPointWidth: Float {
        guard let screen = Screen.main else {
            return 390
        }
        return max(320, screen.size.width)
    }
}
