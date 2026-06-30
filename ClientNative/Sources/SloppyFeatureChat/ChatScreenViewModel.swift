import Foundation
import SwiftUI
import Observation
import SloppyClientCore
import SloppyClientUI

@Observable
@MainActor
public final class ChatTranscriptState {
    private static let initialVisibleWindowSize = 64
    private static let revealStep = 64

    private var allMessages: [ChatMessage] = []
    private var visibleStartIndex = 0

    public private(set) var messages: [ChatMessage] = []

    var isEmpty: Bool {
        allMessages.isEmpty
    }

    var lastMessage: ChatMessage? {
        allMessages.last
    }

    var hasEarlierMessages: Bool {
        visibleStartIndex > 0
    }

    var hiddenMessageCount: Int {
        visibleStartIndex
    }

    func replaceAll(_ newMessages: [ChatMessage]) {
        allMessages = newMessages
        visibleStartIndex = max(0, newMessages.count - Self.initialVisibleWindowSize)
        refreshVisibleMessages()
    }

    func clear() {
        allMessages = []
        visibleStartIndex = 0
        messages = []
    }

    func append(_ message: ChatMessage) {
        allMessages.append(message)
        refreshVisibleMessages()
    }

    func removeAll(where shouldBeRemoved: (ChatMessage) -> Bool) {
        allMessages.removeAll(where: shouldBeRemoved)
        visibleStartIndex = min(visibleStartIndex, allMessages.count)
        refreshVisibleMessages()
    }

    func upsert(_ message: ChatMessage) {
        if let idx = allMessages.firstIndex(where: { $0.id == message.id }) {
            allMessages[idx] = message
        } else {
            allMessages.append(message)
        }
        refreshVisibleMessages()
    }

    func revealEarlierMessages() {
        visibleStartIndex = max(0, visibleStartIndex - Self.revealStep)
        refreshVisibleMessages()
    }

    private func refreshVisibleMessages() {
        guard !allMessages.isEmpty else {
            messages = []
            visibleStartIndex = 0
            return
        }

        visibleStartIndex = max(0, min(visibleStartIndex, allMessages.count - 1))
        messages = Array(allMessages[visibleStartIndex...])
    }
}

@Observable
@MainActor
public final class ChatScreenViewModel {
    public private(set) var agents: [APIAgentRecord] = []
    public private(set) var selectedAgent: APIAgentRecord?
    public private(set) var sessions: [ChatSessionSummary] = []
    public var selectedSessionId: String?
    public var pinnedSessionIds: Set<String> { settings.pinnedSessionIds }
    public private(set) var activeContextTitle: String?
    public private(set) var sessionActionStatus: String?
    public private(set) var isLoadingSessions = false
    public private(set) var isSending = false
    public var showAgentPicker = false
    public var showSessionPicker = false
    public let transcript = ChatTranscriptState()
    public let composerDraft = ChatComposerDraft()

    public var messages: [ChatMessage] {
        transcript.messages
    }

    @ObservationIgnored private let apiClient: SloppyAPIClient
    @ObservationIgnored private let cacheStore: ClientCacheStore
    @ObservationIgnored private let settings: ClientSettings
    public let connectionMonitor: ConnectionMonitor
    @ObservationIgnored private let onOpenSettings: @MainActor () -> Void

    @ObservationIgnored private var socketManager: SessionSocketManager?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var sessionStatusTask: Task<Void, Never>?
    @ObservationIgnored private var streamingFlushTask: Task<Void, Never>?
    @ObservationIgnored private var pendingStreamingSessionId: String?
    @ObservationIgnored private var pendingStreamingAssistantText: String?
    @ObservationIgnored private var pendingNavigationRequest: ChatNavigationRequest?
    @ObservationIgnored private var lastAppliedNavigationRequestId: Int?
    @ObservationIgnored private var activeProjectId: String?
    @ObservationIgnored private var activeTaskId: String?
    @ObservationIgnored private var didLoadInitialData = false
    @ObservationIgnored private var isLoadingInitialData = false
    @ObservationIgnored private var sessionLoadGeneration = 0

    public init(
        apiClient: SloppyAPIClient,
        cacheStore: ClientCacheStore = ClientCacheStore(),
        settings: ClientSettings,
        connectionMonitor: ConnectionMonitor,
        onOpenSettings: @escaping @MainActor () -> Void
    ) {
        self.apiClient = apiClient
        self.cacheStore = cacheStore
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
        guard !didLoadInitialData, !isLoadingInitialData else { return }

        isLoadingInitialData = true
        Task { @MainActor in
            defer {
                didLoadInitialData = true
                isLoadingInitialData = false
            }

            let fetched = (try? await apiClient.fetchAgents()) ?? []
            if fetched.isEmpty {
                agents = await cacheStore.loadAgents()
            } else {
                agents = fetched
                await cacheStore.cacheAgents(fetched)
            }

            let availableAgents = agents
            let lastId = settings.lastAgentId
            let agent = availableAgents.first(where: { $0.id == lastId }) ?? availableAgents.first
            if let agent {
                selectedAgent = agent
                await loadSessions(for: agent)

                if let lastSessionId = settings.lastSessionId,
                   sessions.contains(where: { $0.id == lastSessionId }) {
                    selectSession(lastSessionId)
                } else {
                    selectedSessionId = nil
                    transcript.clear()
                    activeContextTitle = nil
                    activeProjectId = nil
                    activeTaskId = nil
                    settings.lastSessionId = nil
                }
            }

            if let pendingNavigationRequest {
                applyNavigationRequest(pendingNavigationRequest)
            }
        }
    }

    public func loadSessions(for agent: APIAgentRecord, projectId: String? = nil) async {
        sessionLoadGeneration += 1
        let generation = sessionLoadGeneration
        isLoadingSessions = true
        let fetched = (try? await apiClient.fetchAgentSessions(agentId: agent.id, projectId: projectId)) ?? []
        guard generation == sessionLoadGeneration else { return }
        if fetched.isEmpty {
            sessions = sortSessions((await cacheStore.loadSessions(agentId: agent.id, projectId: projectId)).filter { $0.kind != "heartbeat" })
        } else {
            let filtered = fetched.filter { $0.kind != "heartbeat" }
            sessions = sortSessions(filtered)
            await cacheStore.cacheSessions(agentId: agent.id, projectId: projectId, sessions: filtered)
        }
        isLoadingSessions = false
    }

    public func refreshCurrentContext() async {
        guard let agent = selectedAgent else {
            return
        }

        await loadSessions(for: agent, projectId: activeTaskId == nil ? activeProjectId : nil)

        if let selectedSessionId,
           let detail = try? await apiClient.fetchAgentSession(agentId: agent.id, sessionId: selectedSessionId) {
            transcript.replaceAll(detail.messages)
            await cacheStore.cacheSessionDetail(agentId: agent.id, detail: detail)
        } else if let selectedSessionId,
                  let cached = await cacheStore.loadSessionDetail(agentId: agent.id, sessionId: selectedSessionId) {
            transcript.replaceAll(cached.messages)
        }
    }

    public func pickAgent(_ agent: APIAgentRecord) {
        showAgentPicker = false
        switchAgent(agent)
    }

    public func pickSession(_ session: ChatSessionSummary) {
        showSessionPicker = false
        openSession(session)
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
                settings.setSessionPinned(session.id, isPinned: false)
                sessions.removeAll { $0.id == session.id }

                if selectedSessionId == session.id {
                    disconnectCurrentSession()
                    selectedSessionId = nil
                    settings.lastSessionId = nil
                    transcript.clear()
                    activeContextTitle = nil
                    activeProjectId = nil
                    activeTaskId = nil
                }

                showSessionStatus("Deleted \(displayTitle(for: session))")
            } catch {
                showSessionStatus("Could not delete \(displayTitle(for: session))")
            }
        }
    }


    public func toggleSessionPinned(_ session: ChatSessionSummary) {
        let nextPinned = !settings.isSessionPinned(session.id)
        settings.setSessionPinned(session.id, isPinned: nextPinned)
        sessions = sortSessions(sessions)
        showSessionStatus(nextPinned ? "Pinned \(displayTitle(for: session))" : "Unpinned \(displayTitle(for: session))")
    }

    public func copyDebugSessionLink(_ session: ChatSessionSummary) {
        copyDebugSessionFileLink(session)
    }

    public func copyDebugSessionFileLink(_ session: ChatSessionSummary) {
        let url = debugSessionFilePathURL(for: session)
        UIClipboard.setString(url.absoluteString)
        showSessionStatus("Copied session file debug link")
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
        case .project(let projectId, let projectName, _):
            routeToContext(request, projectId: projectId, title: "Project: \(projectName)")
        case .task(let projectId, let projectName, let taskId, let taskTitle, _):
            routeToContext(
                request,
                projectId: projectId,
                title: "\(projectName) / \(taskTitle)",
                preferredSessionTitle: taskTitle,
                preferredTaskId: taskId
            )
        }
    }

    private func switchAgent(_ agent: APIAgentRecord) {
        disconnectCurrentSession()
        selectedAgent = agent
        selectedSessionId = nil
        transcript.clear()
        activeContextTitle = nil
        activeProjectId = nil
        activeTaskId = nil
        settings.lastAgentId = agent.id
        settings.lastSessionId = nil
        Task { @MainActor in
            await loadSessions(for: agent)
        }
    }

    private func startNewSession() {
        guard let agent = selectedAgent else { return }
        disconnectCurrentSession()
        let contextTitle = activeContextTitle
        let projectId = activeProjectId
        let taskId = activeTaskId
        transcript.clear()
        selectedSessionId = nil
        activeContextTitle = contextTitle
        activeProjectId = projectId
        activeTaskId = taskId
        Task { @MainActor in
            let sessionTitle = taskId.map(taskSessionTitle(for:)) ?? contextTitle ?? "Chat with \(agent.displayName)"
            guard let summary = try? await apiClient.createAgentSession(
                agentId: agent.id,
                title: sessionTitle,
                projectId: projectId
            ) else { return }
            sessions.insert(summary, at: 0)
            selectedSessionId = summary.id
            settings.lastSessionId = summary.id
            connectToSession(agentId: agent.id, sessionId: summary.id)
        }
    }

    private func openSession(_ session: ChatSessionSummary) {
        let nextAgent = agents.first {
            $0.id.caseInsensitiveCompare(session.agentId) == .orderedSame
        } ?? selectedAgent

        if let nextAgent, selectedAgent?.id != nextAgent.id {
            selectedAgent = nextAgent
            settings.lastAgentId = nextAgent.id
        }

        selectSession(session.id, contextTitle: displayTitle(for: session), projectId: session.projectId, taskId: nil)
    }

    private func selectSession(
        _ sessionId: String,
        contextTitle: String? = nil,
        projectId: String? = nil,
        taskId: String? = nil
    ) {
        guard let agent = selectedAgent else { return }
        let retainedContextTitle = contextTitle ?? activeContextTitle
        let retainedProjectId = projectId ?? activeProjectId
        disconnectCurrentSession()
        transcript.clear()
        selectedSessionId = sessionId
        activeContextTitle = retainedContextTitle
        activeProjectId = retainedProjectId
        activeTaskId = taskId
        settings.lastSessionId = sessionId
        connectToSession(agentId: agent.id, sessionId: sessionId)
    }

    private func routeToBlankChat() {
        let agent = selectedAgent ?? agents.first
        guard let agent else {
            selectedAgent = nil
            selectedSessionId = nil
            transcript.clear()
            activeContextTitle = nil
            activeProjectId = nil
            activeTaskId = nil
            return
        }

        activateDraft(agent: agent, contextTitle: nil)
    }

    private func routeToContext(
        _ request: ChatNavigationRequest,
        projectId: String,
        title: String,
        preferredSessionTitle: String? = nil,
        preferredTaskId: String? = nil
    ) {
        let agent = agentForNavigation(request) ?? selectedAgent ?? agents.first
        guard let agent else {
            selectedAgent = nil
            selectedSessionId = nil
            transcript.clear()
            activeContextTitle = title
            activeProjectId = projectId
            activeTaskId = preferredTaskId
            return
        }

        activateProjectContext(
            agent: agent,
            projectId: projectId,
            contextTitle: title,
            preferredSessionTitle: preferredSessionTitle,
            preferredTaskId: preferredTaskId
        )
    }

    private func agentForNavigation(_ request: ChatNavigationRequest) -> APIAgentRecord? {
        guard let preferredAgentId = request.preferredAgentId else { return nil }
        return agents.first {
            $0.id.caseInsensitiveCompare(preferredAgentId) == .orderedSame
        }
    }

    private func activateDraft(agent: APIAgentRecord, contextTitle: String?) {
        disconnectCurrentSession()
        selectedAgent = agent
        selectedSessionId = nil
        transcript.clear()
        activeContextTitle = contextTitle
        activeProjectId = nil
        activeTaskId = nil
        settings.lastAgentId = agent.id
        settings.lastSessionId = nil

        Task { @MainActor in
            await loadSessions(for: agent)
        }
    }

    private func activateProjectContext(
        agent: APIAgentRecord,
        projectId: String,
        contextTitle: String,
        preferredSessionTitle: String?,
        preferredTaskId: String?
    ) {
        disconnectCurrentSession()
        selectedAgent = agent
        selectedSessionId = nil
        transcript.clear()
        activeContextTitle = contextTitle
        activeProjectId = projectId
        activeTaskId = preferredTaskId
        settings.lastAgentId = agent.id
        settings.lastSessionId = nil

        Task { @MainActor in
            await loadSessions(for: agent, projectId: preferredTaskId == nil ? projectId : nil)
            guard selectedAgent?.id == agent.id,
                  activeProjectId == projectId,
                  selectedSessionId == nil else {
                return
            }

            guard let session = preferredSession(
                in: sessions,
                title: preferredSessionTitle,
                taskId: preferredTaskId,
                projectId: projectId,
                allowsFallback: preferredTaskId == nil
            ) else {
                return
            }

            selectSession(session.id, contextTitle: contextTitle, projectId: projectId, taskId: preferredTaskId)
        }
    }

    private func disconnectCurrentSession() {
        let manager = socketManager
        streamTask?.cancel()
        streamTask = nil
        cancelPendingStreamingAssistantText()
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
                transcript.replaceAll(detail.messages)
                await cacheStore.cacheSessionDetail(agentId: agentId, detail: detail)
            } else if let cached = await cacheStore.loadSessionDetail(agentId: agentId, sessionId: sessionId) {
                guard isCurrentSession(agentId: agentId, sessionId: sessionId) else { return }
                transcript.replaceAll(cached.messages)
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
            guard transcript.isEmpty else { break }
            if let detail = try? await apiClient.fetchAgentSession(agentId: agentId, sessionId: sessionId) {
                transcript.replaceAll(detail.messages)
                await cacheStore.cacheSessionDetail(agentId: agentId, detail: detail)
            } else if let cached = await cacheStore.loadSessionDetail(agentId: agentId, sessionId: sessionId) {
                transcript.replaceAll(cached.messages)
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

    private func isCurrentSession(agentId: String, sessionId: String) -> Bool {
        selectedAgent?.id == agentId && selectedSessionId == sessionId
    }

    private func upsertMessage(_ message: ChatMessage, sessionId: String) {
        if message.role == .assistant {
            cancelPendingStreamingAssistantText(for: sessionId)
            transcript.removeAll { $0.id == streamingAssistantMessageId(for: sessionId) }
        } else if message.role == .user {
            transcript.removeAll { $0.id.hasPrefix("optimistic-user-") }
        }

        transcript.upsert(message)
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
        let id = streamingAssistantMessageId(for: sessionId)
        let message = ChatMessage(
            id: id,
            role: .assistant,
            segments: [ChatMessageSegment(kind: .text, text: text)]
        )

        transcript.upsert(message)
    }

    private func streamingAssistantMessageId(for sessionId: String) -> String {
        "streaming-assistant-\(sessionId)"
    }

    private func displayTitle(for session: ChatSessionSummary) -> String {
        session.title.isEmpty ? "Chat" : session.title
    }

    private func taskSessionTitle(for taskId: String) -> String {
        "task-\(taskId)"
    }

    private func sortSessions(_ sessions: [ChatSessionSummary]) -> [ChatSessionSummary] {
        sessions.sorted { lhs, rhs in
            let lhsPinned = settings.isSessionPinned(lhs.id)
            let rhsPinned = settings.isSessionPinned(rhs.id)
            if lhsPinned != rhsPinned {
                return lhsPinned
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func debugSessionFilePathURL(for session: ChatSessionSummary) -> URL {
        var components = URLComponents(url: apiClient.baseURL, resolvingAgainstBaseURL: false)
            ?? URLComponents()
        let agentId = selectedAgent?.id ?? session.agentId
        components.path = "/v1/debug/session-file-path/\(Self.urlPathEscape(agentId))/\(Self.urlPathEscape(session.id))"
        components.queryItems = nil
        return components.url ?? apiClient.baseURL
    }

    private static func urlPathEscape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private func preferredSession(
        in sessions: [ChatSessionSummary],
        title: String?,
        taskId: String? = nil,
        projectId: String? = nil,
        allowsFallback: Bool = true
    ) -> ChatSessionSummary? {
        let candidates = sessions
            .filter { $0.kind != "heartbeat" }
            .sorted { $0.updatedAt > $1.updatedAt }

        if let taskId = taskId?.trimmingCharacters(in: .whitespacesAndNewlines), !taskId.isEmpty {
            var normalizedTaskTitles = [taskSessionTitle(for: taskId)]
            if let projectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines), !projectId.isEmpty {
                normalizedTaskTitles.append("task-comment:\(projectId):\(taskId)")
            }
            normalizedTaskTitles = normalizedTaskTitles.map { $0.lowercased() }

            if let taskSession = candidates.first(where: { session in
                normalizedTaskTitles.contains(session.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            }) {
                return taskSession
            }
        }

        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return allowsFallback ? candidates.first : nil
        }

        let normalizedTitle = title.lowercased()
        let titleMatch = candidates.first {
            let sessionTitle = $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return sessionTitle == normalizedTitle || sessionTitle.contains(normalizedTitle)
        }

        return titleMatch ?? (allowsFallback ? candidates.first : nil)
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
                    title: activeTaskId.map(taskSessionTitle(for:)) ?? activeContextTitle ?? "Chat with \(agent.displayName)",
                    projectId: activeProjectId
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
        transcript.append(optimistic)
        _ = try? await apiClient.postSessionMessage(agentId: agentId, sessionId: sessionId, content: content)
        isSending = false
    }
}
