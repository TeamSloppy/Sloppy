import AdaEngine
import Foundation
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
    @State private var didLoadSessions = false
    @State private var isSending = false
    @State private var composerDraft = ChatComposerDraft()
    @State private var socketManager: SessionSocketManager?
    @State private var streamTask: Task<Void, Never>?
    @State private var streamingFlushTask: Task<Void, Never>?
    @State private var pendingStreamingSessionId: String?
    @State private var pendingStreamingAssistantText: String?
    @Environment(\.theme) private var theme

    var body: some View {
        sessionListView
            .fullScreenCover(isPresented: $showTranscript) {
                if let sessionId = selectedSessionId {
                    ChatTranscriptView(
                        sessionId: sessionId,
                        agentId: agent.id,
                        messages: $messages,
                        composerDraft: composerDraft,
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

        return VStack(alignment: .leading, spacing: sp.m) {
            HStack {
                SectionHeader("Chat Sessions", accentColor: c.accentCyan)
                Spacer()
                Button("REFRESH") { loadSessions(force: true) }
                    .foregroundColor(c.accentCyan)
                    .font(.system(size: ty.caption))
                Button("NEW CHAT") { createSession() }
                    .foregroundColor(c.accentCyan)
                    .font(.system(size: ty.caption))
            }
            .padding(.horizontal, sp.l)

            if sessions.isEmpty {
                EmptyStateView(isLoadingSessions ? "Loading..." : "No sessions")
                    .padding(.vertical, sp.xl)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: sp.s) {
                        ForEach(sessions) { session in
                            EntityCard(
                                title: session.title.isEmpty ? "Session" : session.title,
                                subtitle: "\(session.messageCount) messages",
                                accentColor: c.accentCyan,
                                onTap: { selectSession(session.id) }
                            )
                            .frame(width: 200) // Give cards a fixed width so they scroll nicely
                        }
                    }
                    .padding(.horizontal, sp.l)
                }
            }
        }
        .padding(.top, sp.l)
        .padding(.bottom, sp.m)
        .onAppear { loadSessions() }
    }

    // MARK: - Session management

    private func selectSession(_ sessionId: String) {
        disconnectSocket()
        messages = []
        selectedSessionId = sessionId
        showTranscript = true
        loadSessionAndConnect(sessionId: sessionId)
    }

    private func disconnectAndClearSession() {
        disconnectSocket()
        messages = []
        selectedSessionId = nil
        showTranscript = false
    }

    private func disconnectSocket() {
        let manager = socketManager
        streamTask?.cancel()
        streamTask = nil
        cancelPendingStreamingAssistantText()
        socketManager = nil
        if let manager {
            Task { await manager.disconnect() }
        }
    }

    // MARK: - Actions

    private func loadSessions(force: Bool = false) {
        guard force || !didLoadSessions else { return }
        guard !isLoadingSessions else { return }

        isLoadingSessions = true
        Task { @MainActor in
            defer {
                didLoadSessions = true
                isLoadingSessions = false
            }
            sessions = (try? await apiClient.fetchAgentSessions(agentId: agent.id)) ?? []
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
        let manager = SessionSocketManager(baseURL: apiClient.baseURL, agentId: agent.id, sessionId: sessionId)
        socketManager = manager

        streamTask = Task { @MainActor in
            defer {
                Task { await manager.disconnect() }
            }

            if let detail = try? await apiClient.fetchAgentSession(agentId: agent.id, sessionId: sessionId) {
                guard selectedSessionId == sessionId else { return }
                messages = detail.messages
            }

            let stream = await manager.connect()

            for await update in stream {
                guard selectedSessionId == sessionId else { return }
                await handleStreamUpdate(update, agentId: agent.id, sessionId: sessionId)
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
            if update.kind == .sessionDelta, let text = update.messageText {
                scheduleStreamingAssistantText(text, sessionId: sessionId)
            } else if let msg = update.message {
                upsertMessage(msg, sessionId: sessionId)
            }
        case .sessionClosed, .sessionError:
            flushPendingStreamingAssistantText()
        case .heartbeat:
            break
        }
    }

    private func upsertMessage(_ message: ChatMessage, sessionId: String) {
        if message.role == .assistant {
            cancelPendingStreamingAssistantText(for: sessionId)
            messages.removeAll { $0.id == streamingAssistantMessageId(for: sessionId) }
        } else if message.role == .user {
            messages.removeAll { $0.id.hasPrefix("optimistic-user-") }
        }

        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
            messages[idx] = message
        } else {
            messages.append(message)
        }
    }

    private func scheduleStreamingAssistantText(_ text: String, sessionId: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pendingStreamingSessionId = sessionId
        pendingStreamingAssistantText = text

        guard streamingFlushTask == nil else {
            return
        }

        streamingFlushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            flushPendingStreamingAssistantText()
        }
    }

    private func flushPendingStreamingAssistantText() {
        guard let sessionId = pendingStreamingSessionId,
              let text = pendingStreamingAssistantText else {
            streamingFlushTask = nil
            return
        }

        pendingStreamingSessionId = nil
        pendingStreamingAssistantText = nil
        streamingFlushTask = nil
        applyStreamingAssistantText(text, sessionId: sessionId)
    }

    private func cancelPendingStreamingAssistantText(for sessionId: String? = nil) {
        guard sessionId == nil || pendingStreamingSessionId == sessionId else {
            return
        }

        streamingFlushTask?.cancel()
        streamingFlushTask = nil
        pendingStreamingSessionId = nil
        pendingStreamingAssistantText = nil
    }

    private func applyStreamingAssistantText(_ text: String, sessionId: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let id = streamingAssistantMessageId(for: sessionId)
        let message = ChatMessage(
            id: id,
            role: .assistant,
            segments: [ChatMessageSegment(kind: .text, text: text)]
        )

        if let idx = messages.firstIndex(where: { $0.id == id }) {
            messages[idx] = message
        } else {
            messages.append(message)
        }
    }

    private func streamingAssistantMessageId(for sessionId: String) -> String {
        "streaming-assistant-\(sessionId)"
    }

    private func sendMessage(agentId: String, sessionId: String, content: String) {
        guard !isSending else { return }
        isSending = true

        let optimisticId = "optimistic-user-\(UUID().uuidString)"
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
    let composerDraft: ChatComposerDraft
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

            ZStack(anchor: .bottom) {
                ScrollViewReader { proxy in
                    ScrollView {
                        if messages.isEmpty {
                            EmptyStateView("No messages yet")
                                .padding(.vertical, sp.xl)
                                .padding(sp.m)
                                .padding(.bottom, composerScrollInset)
                        } else {
                            LazyVStack(
                                messages,
                                alignment: .leading,
                                spacing: sp.s,
                                estimatedRowHeight: 156,
                                overscan: 8
                            ) { msg in
                                ChatBubbleView(message: msg)
                                    .frame(minWidth: 0, maxWidth: .infinity)
                                    .allowsHitTesting(false)
                            }
                            .padding(sp.m)
                            .padding(.bottom, composerScrollInset)
                        }
                    }
                    .onChange(of: messages.count) { oldCount, newCount in
                        guard newCount > oldCount,
                              oldCount == 0 || proxy.isNearBottom(threshold: 220),
                              let lastMessageId = messages.last?.id else {
                            return
                        }

                        Task { @MainActor in
                            proxy.scrollTo(lastMessageId, anchor: .bottom)
                        }
                    }
                    .onChange(of: latestAssistantMessageLayoutKey) { _, _ in
                        guard proxy.isNearBottom(threshold: 480),
                              let lastMessage = messages.last,
                              lastMessage.role == .assistant else {
                            return
                        }

                        Task { @MainActor in
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }

                HStack {
                    Spacer(minLength: 0)
                    ChatComposerView(draft: composerDraft, agentName: agentId) { content in
                        onSend(content)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, sp.m)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(c.background)
    }

    private var composerScrollInset: Float {
        ChatComposerView.panelHeight + theme.spacing.xxl
    }

    private var latestAssistantMessageLayoutKey: String {
        guard let message = messages.last,
              message.role == .assistant else {
            return ""
        }
        return "\(message.id):\(message.textContent.count)"
    }
}
