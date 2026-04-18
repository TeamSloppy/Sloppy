import AdaEngine
import SloppyClientCore
import SloppyClientUI

@MainActor
public struct ChatScreen: View {
    @State private var viewModel: ChatScreenViewModel

    public init(
        apiClient: SloppyAPIClient,
        settings: ClientSettings,
        connectionMonitor: ConnectionMonitor,
        onOpenSettings: @escaping () -> Void
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
            VStack(alignment: .leading, spacing: 0) {
                topBar
                connectionBar

                contentArea
                    .frame(maxWidth: 600)
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)

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
        .overlay(anchor: .bottom, content: {
            composerBar
                .frame(maxWidth: 600)
                .padding(.bottom, theme.spacing.l)

        })
        .onAppear { viewModel.loadInitialData() }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return HStack(spacing: sp.m) {
            Button(action: { viewModel.showAgentPicker = true }) {
                HStack(spacing: sp.s) {
                    Text(viewModel.selectedAgent?.displayName ?? "Select Agent")
                        .font(.system(size: ty.body))
                        .foregroundColor(c.accent)
                    Text("▾")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.textMuted)
                }
                .padding(.horizontal, sp.m)
                .padding(.vertical, sp.s)
                .background(c.surface)
                .border(c.border, lineWidth: bo.thin)
            }

            Spacer()

            if viewModel.selectedSessionId != nil {
                Button(action: { viewModel.showSessionPicker = true }) {
                    Text("Sessions")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.textMuted)
                }
                .padding(.horizontal, sp.s)
                .padding(.vertical, sp.xs)
            }

            Button(action: { viewModel.openSettings() }) {
                Text("···")
                    .font(.system(size: ty.heading))
                    .foregroundColor(c.textMuted)
            }
            .padding(.horizontal, sp.s)
        }
        .padding(.horizontal, sp.l)
        .padding(.vertical, sp.m)
        .background(c.background)
        .border(c.border, lineWidth: bo.thin)
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
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                ChatGreetingView(agentName: viewModel.selectedAgent?.displayName ?? "Agent")
                Spacer()
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let sp = theme.spacing
                    ForEach(viewModel.messages) { msg in
                        ChatBubbleView(message: msg)
                            .padding(.horizontal, sp.m)
                            .padding(.vertical, sp.xs)
                    }
                }
                .padding(.vertical, theme.spacing.m)
            }
            .frame(minHeight: 0, maxHeight: .infinity)
        }
    }

    // MARK: - Composer

    @ViewBuilder
    private var composerBar: some View {
        if let agent = viewModel.selectedAgent {
            ChatComposerView(agentName: agent.displayName) { content in
                viewModel.sendMessage(content: content)
            }
        } else {
            ChatComposerView(agentName: "Agent") { _ in }
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
