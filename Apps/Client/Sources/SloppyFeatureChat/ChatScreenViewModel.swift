import AdaEngine
import Observation
import SloppyClientCore

@Observable
@MainActor
public final class ChatScreenViewModel {
    public private(set) var agents: [APIAgentRecord] = []
    public private(set) var selectedAgent: APIAgentRecord?
    public private(set) var sessions: [ChatSessionSummary] = []
    public var selectedSessionId: String?
    public private(set) var messages: [ChatMessage] = []
    public private(set) var isLoadingSessions = false
    public private(set) var isSending = false
    public var showAgentPicker = false
    public var showSessionPicker = false

    private let apiClient: SloppyAPIClient
    private let settings: ClientSettings
    public let connectionMonitor: ConnectionMonitor
    private let onOpenSettings: () -> Void

    private var socketManager: SessionSocketManager?
    private var streamTask: Task<Void, Never>?

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

    public func openSettings() {
        onOpenSettings()
    }

    public func dismissOverlays() {
        showAgentPicker = false
        showSessionPicker = false
    }

    public func loadInitialData() {
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

    public func loadSessions(for agent: APIAgentRecord) async {
        isLoadingSessions = true
        sessions = (try? await apiClient.fetchAgentSessions(agentId: agent.id)) ?? []
        isLoadingSessions = false
    }

    public func pickAgent(_ agent: APIAgentRecord) {
        showAgentPicker = false
        switchAgent(agent)
    }

    public func pickSession(_ session: ChatSessionSummary) {
        showSessionPicker = false
        selectSession(session.id)
    }

    public func pickNewSession() {
        showSessionPicker = false
        startNewSession()
    }

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

    public func sendMessage(content: String) {
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
