import AdaEngine
import SloppyClientCore
import SloppyClientUI

struct AgentChatView: View {
    let agent: APIAgentRecord
    let apiClient: SloppyAPIClient

    @State private var sessions: [ChatSessionSummary] = []
    @State private var selectedSessionId: String?
    @State private var messages: [ChatMessage] = []
    @State private var isLoadingSessions = false
    @State private var isSending = false
    @State private var socketManager: SessionSocketManager?
    @State private var streamTask: Task<Void, Never>?

    var body: some View {
        if let sessionId = selectedSessionId {
            transcriptView(sessionId: sessionId)
        } else {
            sessionListView
        }
    }

    // MARK: - Session list

    private var sessionListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingL) {
                HStack {
                    SectionHeader("Chat Sessions", accentColor: Theme.accentCyan)
                    Spacer()
                    Button("REFRESH") { loadSessions() }
                        .foregroundColor(Theme.accentCyan)
                    Button("NEW CHAT") { createSession() }
                        .foregroundColor(Theme.accentCyan)
                }

                if sessions.isEmpty {
                    EmptyStateView(isLoadingSessions ? "Loading..." : "No sessions")
                        .padding(.vertical, Theme.spacingXL)
                } else {
                    VStack(spacing: Theme.spacingS) {
                        ForEach(sessions) { session in
                            EntityCard(
                                title: session.title.isEmpty ? "Session" : session.title,
                                subtitle: "\(session.messageCount) messages",
                                accentColor: Theme.accentCyan,
                                onTap: { selectSession(session.id) }
                            )
                        }
                    }
                }
            }
            .padding(Theme.spacingL)
        }
        .onAppear { loadSessions() }
    }

    // MARK: - Transcript

    private func transcriptView(sessionId: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.spacingM) {
                BackButton("Sessions", action: { disconnectAndClearSession() })
                Spacer()
            }
            .padding(.horizontal, Theme.spacingL)
            .padding(.vertical, Theme.spacingM)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingS) {
                    if messages.isEmpty {
                        EmptyStateView("No messages yet")
                            .padding(.vertical, Theme.spacingXL)
                    } else {
                        ForEach(messages) { msg in
                            ChatBubbleView(message: msg)
                        }
                    }
                }
                .padding(Theme.spacingM)
            }

            ChatComposerView { content in
                sendMessage(agentId: agent.id, sessionId: sessionId, content: content)
            }
        }
    }

    // MARK: - Session management

    private func selectSession(_ sessionId: String) {
        streamTask?.cancel()
        streamTask = nil
        socketManager = nil
        messages = []
        selectedSessionId = sessionId
        loadSessionAndConnect(sessionId: sessionId)
    }

    private func disconnectAndClearSession() {
        streamTask?.cancel()
        streamTask = nil
        socketManager = nil
        messages = []
        selectedSessionId = nil
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

