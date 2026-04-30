import AdaEngine
import SloppyClientCore
import SloppyClientUI

fileprivate let chatHeroWidth: Float = 720
fileprivate let chatContentWidth: Float = 840

@MainActor
public struct ChatScreen: View {
    @State private var viewModel: ChatScreenViewModel

    public init(
        apiClient: SloppyAPIClient,
        settings: ClientSettings,
        connectionMonitor: ConnectionMonitor,
        onOpenSettings: @escaping @MainActor () -> Void
    ) {
        _viewModel = State(
            initialValue: ChatScreenViewModel(
                apiClient: apiClient,
                settings: settings,
                connectionMonitor: connectionMonitor,
                onOpenSettings: onOpenSettings
            )
        )
    }

    public init(viewModel: ChatScreenViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ChatScreenContent()
            .environment(viewModel)
    }
}

@MainActor
private struct ChatScreenContent: View {
    @Environment(ChatScreenViewModel.self) private var viewModel
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            ZStack(anchor: .topLeading) {
                VStack(spacing: 0) {
                    connectionBar

                    ZStack(anchor: .bottom) {
                        contentArea
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        composerOverlay
//                        quickActionRow
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                            .frame(width: 320)
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
                            .frame(width: 320)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationTitlePosition(.center)
            .navigationBarLeadingItems {
                agentNavigationButton
            }
            .navigationBarTrailingItems {
                navigationActions
            }
        }
        .onAppear { viewModel.loadInitialData() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Navigation Bar

    private var navigationTitle: String {
        if let title = viewModel.activeContextTitle {
            return title
        }

        if viewModel.selectedSessionId != nil {
            return "Chat"
        }

        return "New Chat"
    }

    private var agentNavigationButton: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return Button(action: { viewModel.showAgentPicker = true }) {
            HStack(spacing: sp.s) {
                Text(viewModel.selectedAgent?.displayName ?? "Select Agent")
                    .font(.system(size: ty.body))
                    .foregroundColor(c.textPrimary)
                    .lineLimit(1)
                Icons.symbol(.expandMore, size: ty.caption)
                    .foregroundColor(c.textMuted)
            }
        }
    }

    private var navigationActions: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return HStack(spacing: sp.s) {
            if viewModel.selectedSessionId != nil {
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

            Button(action: viewModel.openSettings) {
                Text("Settings")
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textSecondary)
            }
        }
    }

    // MARK: - Connection Bar

    @ViewBuilder
    private var connectionBar: some View {
        if viewModel.connectionMonitor.state != .connected {
            HStack {
                Spacer()
                ConnectionBanner(state: viewModel.connectionMonitor.state)
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
                    .frame(width: chatHeroWidth)
                Spacer()
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(
                            viewModel.messages,
                            alignment: .leading,
                            spacing: theme.spacing.xl,
                            estimatedRowHeight: 124,
                            overscan: 10
                        ) { msg in
                            ChatBubbleView(message: msg)
                                .frame(minWidth: 0, maxWidth: .infinity)
                        }
                        .padding(.top, theme.spacing.xl)
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
                .frame(width: chatContentWidth)
                .frame(minHeight: 0, maxHeight: .infinity)
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
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
                .frame(width: chatContentWidth)
            Spacer(minLength: 0)
        }
        .padding(.bottom, theme.spacing.m)
    }

    private var composerScrollInset: Float {
        ChatComposerView.panelHeight + theme.spacing.xxl
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
}
