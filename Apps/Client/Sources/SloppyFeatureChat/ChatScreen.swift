import AdaEngine
import SloppyClientCore
import SloppyClientUI

@MainActor
public struct ChatScreen: View {
    let apiClient: SloppyAPIClient
    let settings: ClientSettings
    let connectionMonitor: ConnectionMonitor
    let onOpenSettings: () -> Void

    @State private var agents: [APIAgentRecord] = []
    @State private var selectedAgent: APIAgentRecord?
    @State private var sessions: [ChatSessionSummary] = []
    @State private var selectedSessionId: String?
    @State private var messages: [ChatMessage] = []
    @State private var isLoadingSessions = false
    @State private var isSending = false
    @State private var showAgentPicker = false
    @State private var showSessionPicker = false
    @State private var socketManager: SessionSocketManager?
    @State private var streamTask: Task<Void, Never>?

    @Environment(\.theme) private var theme

    public init(
        apiClient: SloppyAPIClient,
        settings: ClientSettings,
        connectionMonitor: ConnectionMonitor,
        onOpenSettings: @escaping () -> Void
    ) {
        self.apiClient = apiClient
        self.settings = settings
        self.connectionMonitor = connectionMonitor
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        let c = theme.colors

        return ZStack(anchor: .topLeading) {
            c.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                topBar
                connectionBar
                contentArea
                composerBar
            }

            if showAgentPicker {
                overlayDim
                    .overlay(anchor: .topLeading) {
                        AgentPickerView(
                            agents: agents,
                            selectedAgent: selectedAgent,
                            onSelect: { agent in
                                showAgentPicker = false
                                switchAgent(agent)
                            },
                            onDismiss: { showAgentPicker = false }
                        )
                        .frame(width: 320)
                    }
            }

            if showSessionPicker {
                overlayDim
                    .overlay(anchor: .topLeading) {
                        SessionPickerView(
                            sessions: sessions,
                            selectedSessionId: selectedSessionId,
                            isLoading: isLoadingSessions,
                            onSelect: { session in
                                showSessionPicker = false
                                selectSession(session.id)
                            },
                            onNewSession: {
                                showSessionPicker = false
                                startNewSession()
                            },
                            onDismiss: { showSessionPicker = false }
                        )
                        .frame(width: 320)
                    }
            }
        }
        .onAppear { loadInitialData() }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return HStack(spacing: sp.m) {
            Button(action: { showAgentPicker = true }) {
                HStack(spacing: sp.s) {
                    Text(selectedAgent?.displayName ?? "Select Agent")
                        .font(.system(size: ty.body))
                        .foregroundColor(c.textPrimary)
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

            if selectedSessionId != nil {
                Button(action: { showSessionPicker = true }) {
                    Text("Sessions")
                        .font(.system(size: ty.caption))
                        .foregroundColor(c.textMuted)
                }
                .padding(.horizontal, sp.s)
                .padding(.vertical, sp.xs)
            }

            Button(action: onOpenSettings) {
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
        if connectionMonitor.state != .connected {
            HStack {
                Spacer()
                ConnectionBanner(state: connectionMonitor.state)
                Spacer()
            }
        }
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if messages.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                ChatGreetingView(agentName: selectedAgent?.displayName ?? "Agent")
                Spacer()
            }
            .frame(height: 500)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let sp = theme.spacing
                    ForEach(messages) { msg in
                        ChatBubbleView(message: msg)
                            .padding(.horizontal, sp.m)
                            .padding(.vertical, sp.xs)
                    }
                }
                .padding(.vertical, theme.spacing.m)
            }
        }
    }

    // MARK: - Composer

    @ViewBuilder
    private var composerBar: some View {
        if let agent = selectedAgent {
            ChatComposerView(agentName: agent.displayName) { content in
                sendMessage(content: content)
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
                showAgentPicker = false
                showSessionPicker = false
            }
    }

    // MARK: - Data Loading

    private func loadInitialData() {
        Task { @MainActor in
            let fetched = (try? await apiClient.fetchAgents()) ?? []
            agents = fetched

            let lastId = settings.lastAgentId
            let agent = fetched.first(where: { $0.id == lastId }) ?? fetched.first
            if let agent {
                selectedAgent = agent
                await loadSessions(for: agent)

                if let lastSessionId = settings.lastSessionId,
                   sessions.contains(where: { $0.id == lastSessionId }) {
                    selectSession(lastSessionId)
                }
            }
        }
    }

    private func loadSessions(for agent: APIAgentRecord) async {
        isLoadingSessions = true
        sessions = (try? await apiClient.fetchAgentSessions(agentId: agent.id)) ?? []
        isLoadingSessions = false
    }

    // MARK: - Actions

    private func switchAgent(_ agent: APIAgentRecord) {
        disconnectCurrentSession()
        selectedAgent = agent
        selectedSessionId = nil
        messages = []
        settings.lastAgentId = agent.id
        settings.lastSessionId = nil
        Task { @MainActor in
            await loadSessions(for: agent)
        }
    }

    private func startNewSession() {
        guard let agent = selectedAgent else { return }
        disconnectCurrentSession()
        messages = []
        selectedSessionId = nil
        Task { @MainActor in
            guard let summary = try? await apiClient.createAgentSession(
                agentId: agent.id,
                title: "Chat with \(agent.displayName)"
            ) else { return }
            sessions.insert(summary, at: 0)
            selectedSessionId = summary.id
            settings.lastSessionId = summary.id
            connectToSession(agentId: agent.id, sessionId: summary.id)
        }
    }

    private func selectSession(_ sessionId: String) {
        guard let agent = selectedAgent else { return }
        disconnectCurrentSession()
        messages = []
        selectedSessionId = sessionId
        settings.lastSessionId = sessionId
        connectToSession(agentId: agent.id, sessionId: sessionId)
    }

    private func disconnectCurrentSession() {
        streamTask?.cancel()
        streamTask = nil
        socketManager = nil
    }

    private func connectToSession(agentId: String, sessionId: String) {
        Task { @MainActor in
            if let detail = try? await apiClient.fetchAgentSession(agentId: agentId, sessionId: sessionId) {
                messages = detail.messages
            }

            let manager = SessionSocketManager(baseURL: apiClient.baseURL, agentId: agentId, sessionId: sessionId)
            socketManager = manager
            let stream = await manager.connect()

            streamTask = Task { @MainActor in
                for await update in stream {
                    await handleStreamUpdate(update, agentId: agentId, sessionId: sessionId)
                }
            }
        }
    }

    private func handleStreamUpdate(
        _ update: ChatStreamUpdate,
        agentId: String,
        sessionId: String
    ) async {
        switch update.kind {
        case .sessionReady:
            if let detail = try? await apiClient.fetchAgentSession(agentId: agentId, sessionId: sessionId) {
                messages = detail.messages
            }
        case .sessionEvent, .sessionDelta:
            if let msg = update.message {
                if let idx = messages.firstIndex(where: { $0.id == msg.id }) {
                    messages[idx] = msg
                } else {
                    messages.append(msg)
                }
            }
        case .sessionClosed, .sessionError, .heartbeat:
            break
        }
    }

    private func sendMessage(content: String) {
        guard let agent = selectedAgent, !isSending else { return }

        if selectedSessionId == nil {
            Task { @MainActor in
                guard let summary = try? await apiClient.createAgentSession(
                    agentId: agent.id,
                    title: "Chat with \(agent.displayName)"
                ) else { return }
                sessions.insert(summary, at: 0)
                selectedSessionId = summary.id
                settings.lastSessionId = summary.id
                connectToSession(agentId: agent.id, sessionId: summary.id)
                await postMessage(content: content, agentId: agent.id, sessionId: summary.id)
            }
            return
        }

        guard let sessionId = selectedSessionId else { return }
        Task { @MainActor in
            await postMessage(content: content, agentId: agent.id, sessionId: sessionId)
        }
    }

    private func postMessage(content: String, agentId: String, sessionId: String) async {
        isSending = true
        let optimistic = ChatMessage(
            id: UUID().uuidString,
            role: .user,
            segments: [ChatMessageSegment(kind: .text, text: content)]
        )
        messages.append(optimistic)
        _ = try? await apiClient.postSessionMessage(agentId: agentId, sessionId: sessionId, content: content)
        isSending = false
    }
}
