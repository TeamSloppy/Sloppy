import AdaEngine
import Foundation
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
    public private(set) var activeContextTitle: String?
    public private(set) var sessionActionStatus: String?
    public private(set) var isLoadingSessions = false
    public private(set) var isSending = false
    public var showAgentPicker = false
    public var showSessionPicker = false
    public let composerDraft = ChatComposerDraft()

    private let apiClient: SloppyAPIClient
    private let settings: ClientSettings
    public let connectionMonitor: ConnectionMonitor
    private let onOpenSettings: @MainActor () -> Void

    private var socketManager: SessionSocketManager?
    private var streamTask: Task<Void, Never>?
    private var sessionStatusTask: Task<Void, Never>?
    private var pendingNavigationRequest: ChatNavigationRequest?
    private var lastAppliedNavigationRequestId: Int?

    public init(
        apiClient: SloppyAPIClient,
        settings: ClientSettings,
        connectionMonitor: ConnectionMonitor,
        onOpenSettings: @escaping @MainActor () -> Void
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

            if let pendingNavigationRequest {
                applyNavigationRequest(pendingNavigationRequest)
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

    public func deleteSession(_ session: ChatSessionSummary) {
        guard let agent = selectedAgent else { return }
        Task { @MainActor in
            do {
                try await apiClient.deleteAgentSession(agentId: agent.id, sessionId: session.id)
                sessions.removeAll { $0.id == session.id }

                if selectedSessionId == session.id {
                    disconnectCurrentSession()
                    selectedSessionId = nil
                    settings.lastSessionId = nil
                    messages = []
                    activeContextTitle = nil
                }

                showSessionStatus("Deleted \(displayTitle(for: session))")
            } catch {
                showSessionStatus("Could not delete \(displayTitle(for: session))")
            }
        }
    }

    #if DEBUG
    public func downloadSession(_ session: ChatSessionSummary) {
        guard let agent = selectedAgent else { return }
        Task { @MainActor in
            do {
                let data = try await apiClient.fetchAgentSessionData(agentId: agent.id, sessionId: session.id)
                let fileURL = try saveDebugSessionData(data, session: session)
                showSessionStatus("Saved \(fileURL.lastPathComponent)")
            } catch {
                showSessionStatus("Could not save \(displayTitle(for: session))")
            }
        }
    }
    #endif

    public func applyNavigationRequest(_ request: ChatNavigationRequest?) {
        guard let request else { return }
        guard lastAppliedNavigationRequestId != request.id else { return }

        if agents.isEmpty {
            pendingNavigationRequest = request
            return
        }

        pendingNavigationRequest = nil
        lastAppliedNavigationRequestId = request.id
        dismissOverlays()

        switch request.context {
        case .blank:
            routeToBlankChat()
        case .project(_, let projectName, _):
            routeToContext(request, title: "Project: \(projectName)")
        case .task(_, let projectName, _, let taskTitle, _):
            routeToContext(request, title: "\(projectName) / \(taskTitle)")
        }
    }

    private func switchAgent(_ agent: APIAgentRecord) {
        disconnectCurrentSession()
        selectedAgent = agent
        selectedSessionId = nil
        messages = []
        activeContextTitle = nil
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
        activeContextTitle = nil
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
        activeContextTitle = nil
        selectedSessionId = sessionId
        settings.lastSessionId = sessionId
        connectToSession(agentId: agent.id, sessionId: sessionId)
    }

    private func routeToBlankChat() {
        let agent = selectedAgent ?? agents.first
        guard let agent else {
            selectedAgent = nil
            selectedSessionId = nil
            messages = []
            activeContextTitle = nil
            return
        }

        activateDraft(agent: agent, contextTitle: nil)
    }

    private func routeToContext(_ request: ChatNavigationRequest, title: String) {
        let agent = agentForNavigation(request) ?? selectedAgent ?? agents.first
        guard let agent else {
            selectedAgent = nil
            selectedSessionId = nil
            messages = []
            activeContextTitle = title
            return
        }

        activateDraft(agent: agent, contextTitle: title)
    }

    private func agentForNavigation(_ request: ChatNavigationRequest) -> APIAgentRecord? {
        guard let preferredAgentId = request.preferredAgentId else { return nil }
        return agents.first(where: { $0.id == preferredAgentId })
    }

    private func activateDraft(agent: APIAgentRecord, contextTitle: String?) {
        disconnectCurrentSession()
        selectedAgent = agent
        selectedSessionId = nil
        messages = []
        activeContextTitle = contextTitle
        settings.lastAgentId = agent.id
        settings.lastSessionId = nil

        Task { @MainActor in
            await loadSessions(for: agent)
        }
    }

    private func disconnectCurrentSession() {
        let manager = socketManager
        streamTask?.cancel()
        streamTask = nil
        socketManager = nil
        if let manager {
            Task { await manager.disconnect() }
        }
    }

    private func connectToSession(agentId: String, sessionId: String) {
        let manager = SessionSocketManager(baseURL: apiClient.baseURL, agentId: agentId, sessionId: sessionId)
        socketManager = manager

        streamTask = Task { @MainActor in
            defer {
                Task { await manager.disconnect() }
            }

            if let detail = try? await apiClient.fetchAgentSession(agentId: agentId, sessionId: sessionId) {
                guard isCurrentSession(agentId: agentId, sessionId: sessionId) else { return }
                messages = detail.messages
            }

            let stream = await manager.connect()

            for await update in stream {
                guard isCurrentSession(agentId: agentId, sessionId: sessionId) else { return }
                await handleStreamUpdate(update, agentId: agentId, sessionId: sessionId)
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
                applyStreamingAssistantText(text, sessionId: sessionId)
            } else if let msg = update.message {
                upsertMessage(msg, sessionId: sessionId)
            }
        case .sessionClosed, .sessionError, .heartbeat:
            break
        }
    }

    private func isCurrentSession(agentId: String, sessionId: String) -> Bool {
        selectedAgent?.id == agentId && selectedSessionId == sessionId
    }

    private func upsertMessage(_ message: ChatMessage, sessionId: String) {
        if message.role == .assistant {
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

    private func displayTitle(for session: ChatSessionSummary) -> String {
        session.title.isEmpty ? "Chat" : session.title
    }

    private func showSessionStatus(_ status: String) {
        sessionStatusTask?.cancel()
        sessionActionStatus = status
        sessionStatusTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled {
                sessionActionStatus = nil
            }
        }
    }

    #if DEBUG
    private func saveDebugSessionData(_ data: Data, session: ChatSessionSummary) throws -> URL {
        let fileManager = FileManager.default
        let fileName = "sloppy-session-\(safeFileName(displayTitle(for: session)))-\(session.id).json"
        let searchDirectories: [FileManager.SearchPathDirectory] = [
            .downloadsDirectory,
            .documentDirectory,
        ]

        var lastError: Error?
        for directory in searchDirectories {
            do {
                let directoryURL = try fileManager.url(
                    for: directory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                let fileURL = directoryURL.appendingPathComponent(fileName)
                try data.write(to: fileURL, options: .atomic)
                return fileURL
            } catch {
                lastError = error
            }
        }

        throw lastError ?? CocoaError(.fileWriteUnknown)
    }

    private func safeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitizedScalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(sanitizedScalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "chat" : String(collapsed.prefix(48))
    }
    #endif

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
            id: "optimistic-user-\(UUID().uuidString)",
            role: .user,
            segments: [ChatMessageSegment(kind: .text, text: content)]
        )
        messages.append(optimistic)
        _ = try? await apiClient.postSessionMessage(agentId: agentId, sessionId: sessionId, content: content)
        isSending = false
    }
}
