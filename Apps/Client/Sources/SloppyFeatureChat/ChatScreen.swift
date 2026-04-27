import AdaEngine
import SloppyClientCore
import SloppyClientUI

fileprivate let chatHeroWidth: Float = 760
fileprivate let chatContentWidth: Float = 860
fileprivate let chatPanelRadius: Float = 28

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
        ZStack(anchor: .topLeading) {
            VStack {
                topBar
                connectionBar

                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack {
                    Spacer(minLength: 0)
                    composerBar
                        .frame(width: chatContentWidth)
                    Spacer(minLength: 0)
                }
                .padding(.bottom, theme.spacing.l)
//                    quickActionRow
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
                            onSelect: { session in
                                viewModel.pickSession(session)
                            },
                            onNewSession: {
                                viewModel.pickNewSession()
                            },
                            onDismiss: { viewModel.showSessionPicker = false }
                        )
                        .frame(width: 320)
                }
            }
        }
        .onAppear { viewModel.loadInitialData() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return HStack(spacing: sp.m) {
            Button(action: { viewModel.showAgentPicker = true }) {
                HStack(spacing: sp.s) {
                    Text(viewModel.selectedAgent?.displayName ?? "Select Agent")
                        .font(.system(size: ty.body))
                        .foregroundColor(c.textPrimary)
                    Text("▾")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.textMuted)
                }
                .padding(.horizontal, sp.m)
                .padding(.vertical, sp.m)
            }

            Spacer()

            if viewModel.selectedSessionId != nil {
                Button(action: { viewModel.showSessionPicker = true }) {
                    HStack(spacing: sp.s) {
                        Text("Sessions")
                            .font(.system(size: ty.caption))
                            .foregroundColor(c.textSecondary)
                        Text("▾")
                            .font(.system(size: ty.micro))
                            .foregroundColor(c.textMuted)
                    }
                }
                .padding(.horizontal, sp.m)
                .padding(.vertical, sp.m)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
            }

            Button(action: viewModel.openSettings) {
                Text("Settings")
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textSecondary)
            }
            .padding(.horizontal, sp.m)
            .padding(.vertical, sp.m)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
        }
        .padding(.horizontal, sp.l)
        .padding(.top, sp.l)
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
            VStack(spacing: 0) {
                Spacer()
                    ChatGreetingView(agentName: viewModel.selectedAgent?.displayName ?? "Agent")
                        .frame(width: chatHeroWidth)
                Spacer()
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        } else {
            VStack(spacing: theme.spacing.m) {
                ScrollView {
                    VStack(alignment: .leading, spacing: theme.spacing.s) {
                        let sp = theme.spacing
                        ForEach(viewModel.messages) { msg in
                            ChatBubbleView(message: msg)
                                .padding(.horizontal, sp.m)
                        }
                    }
                    .padding(.vertical, theme.spacing.m)
                }
                .frame(width: chatContentWidth)
                .frame(minHeight: 0, maxHeight: .infinity)
                .glassEffect(.regular, in: .rect(cornerRadius: chatPanelRadius))
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
                Text("↗")
                    .font(.system(size: ty.caption))
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
