import AdaEngine
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat

struct AgentChatView: View {
    let agent: APIAgentRecord
    let apiClient: SloppyAPIClient

    @State private var sessions: [ChatSessionSummary] = []
    @State private var selectedSessionId: String?
    @State private var showTranscript = false
    @State private var messages: [ChatMessage] = []
    @State private var isLoadingSessions = false
    @State private var isSending = false
    @State private var socketManager: SessionSocketManager?
    @State private var streamTask: Task<Void, Never>?
    @Environment(\.theme) private var theme

    var body: some View {
        sessionListView
            .fullScreenCover(isPresented: $showTranscript) {
                if let sessionId = selectedSessionId {
                    ChatTranscriptView(
                        sessionId: sessionId,
                        agentId: agent.id,
                        messages: $messages,
                        isSending: isSending,
                        onSend: { content in
                            sendMessage(agentId: agent.id, sessionId: sessionId, content: content)
                        }
                    )
                }
            }
    }

    private var sessionListView: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography

        return ScrollView {
            VStack(alignment: .leading, spacing: sp.l) {
                HStack {
                    SectionHeader("Chat Sessions", accentColor: c.accentCyan)
                    Spacer()
                    Button("REFRESH") { loadSessions() }
                        .foregroundColor(c.accentCyan)
                        .font(.system(size: ty.caption))
                    Button("NEW CHAT") { createSession() }
                        .foregroundColor(c.accentCyan)
                        .font(.system(size: ty.caption))
                }

                if sessions.isEmpty {
                    EmptyStateView(isLoadingSessions ? "Loading..." : "No sessions")
                        .padding(.vertical, sp.xl)
                } else {
                    VStack(spacing: sp.s) {
                        ForEach(sessions) { session in
                            EntityCard(
                                title: session.title.isEmpty ? "Session" : session.title,
                                subtitle: "\(session.messageCount) messages",
                                accentColor: c.accentCyan,
                                onTap: { selectSession(session.id) }
                            )
                        }
                    }
                }
            }
            .padding(sp.l)
        }
        .onAppear { loadSessions() }
    }

    // MARK: - Session management

    private func selectSession(_ sessionId: String) {
        streamTask?.cancel()
        streamTask = nil
        socketManager = nil
        messages = []
        selectedSessionId = sessionId
        showTranscript = true
        loadSessionAndConnect(sessionId: sessionId)
    }

    private func disconnectAndClearSession() {
        streamTask?.cancel()
        streamTask = nil
        socketManager = nil
        messages = []
        selectedSessionId = nil
        showTranscript = false
    }

    // MARK: - Actions

    private func loadSessions() {
        Task { @MainActor in
            isLoadingSessions = true
            sessions = (try? await apiClient.fetchAgentSessions(agentId: agent.id)) ?? []
            isLoadingSessions = false
        }
    }

    private func createSession() {
        Task { @MainActor in
            guard let summary = try? await apiClient.createAgentSession(
                agentId: agent.id,
                title: "Chat with \(agent.displayName)"
            ) else { return }
            sessions.insert(summary, at: 0)
            selectSession(summary.id)
        }
    }

    private func loadSessionAndConnect(sessionId: String) {
        Task { @MainActor in
            if let detail = try? await apiClient.fetchAgentSession(agentId: agent.id, sessionId: sessionId) {
                messages = detail.messages
            }

            let manager = SessionSocketManager(baseURL: apiClient.baseURL, agentId: agent.id, sessionId: sessionId)
            socketManager = manager
            let stream = await manager.connect()

            let task = Task { @MainActor in
                for await update in stream {
                    await handleStreamUpdate(update, agentId: agent.id, sessionId: sessionId)
                }
            }
            streamTask = task
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
        case .sessionClosed:
            break
        case .sessionError:
            break
        case .heartbeat:
            break
        }
    }

    private func sendMessage(agentId: String, sessionId: String, content: String) {
        guard !isSending else { return }
        isSending = true

        let optimisticId = UUID().uuidString
        let optimistic = ChatMessage(
            id: optimisticId,
            role: .user,
            segments: [ChatMessageSegment(kind: .text, text: content)]
        )
        messages.append(optimistic)

        Task { @MainActor in
            _ = try? await apiClient.postSessionMessage(
                agentId: agentId,
                sessionId: sessionId,
                content: content
            )
            isSending = false
        }
    }
}

struct ChatTranscriptView: View {
    let sessionId: String
    let agentId: String
    @Binding var messages: [ChatMessage]
    let isSending: Bool
    let onSend: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: sp.m) {
                BackButton("Sessions", action: { dismiss() })
                Spacer()
            }
            .padding(.horizontal, sp.l)
            .padding(.vertical, sp.m)

            ScrollView {
                VStack(alignment: .leading, spacing: sp.s) {
                    if messages.isEmpty {
                        EmptyStateView("No messages yet")
                            .padding(.vertical, sp.xl)
                    } else {
                        ForEach(messages) { msg in
                            ChatBubbleView(message: msg)
                        }
                    }
                }
                .padding(sp.m)
            }

            ChatComposerView(agentName: agentId) { content in
                onSend(content)
            }
        }
        .background(c.background)
    }
}
