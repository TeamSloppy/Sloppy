import Foundation
import SwiftUI
import Observation
import SloppyClientCore
import SloppyClientUI

public enum ChatComposerDictationPhase: Sendable, Equatable {
    case idle
    case recording
    case transcribing
}

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

    func appendStreamingAssistantText(_ text: String, messageId: String) {
        if let messageIndex = allMessages.firstIndex(where: { $0.id == messageId }) {
            var message = allMessages[messageIndex]
            if let segmentIndex = message.segments.lastIndex(where: { $0.kind == .text }) {
                message.segments[segmentIndex].text = (message.segments[segmentIndex].text ?? "") + text
            } else {
                message.segments.append(ChatMessageSegment(kind: .text, text: text))
            }
            allMessages[messageIndex] = message
        } else {
            allMessages.append(
                ChatMessage(
                    id: messageId,
                    role: .assistant,
                    segments: [ChatMessageSegment(kind: .text, text: text)]
                )
            )
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
    public private(set) var projects: [APIProjectRecord] = []
    public private(set) var selectedAgent: APIAgentRecord?
    public private(set) var availableModels: [ChatModelOption] = []
    public private(set) var selectedModelId: String = ""
    public private(set) var selectedReasoningEffort: ChatReasoningEffort = .default
    public internal(set) var sessions: [ChatSessionSummary] = []
    public var selectedSessionId: String?
    public var pinnedSessionIds: Set<String> { settings.pinnedSessionIds }
    public private(set) var activeContextTitle: String?
    public private(set) var sessionActionStatus: String?
    public private(set) var sendErrorMessage: String?
    public private(set) var isLoadingSessions = false
    public private(set) var isSending = false
    public private(set) var isAwaitingAgentResponse = false
    public private(set) var isStopping = false
    public private(set) var composerFocusResetToken = 0
    private(set) var composerSuggestions: [ChatComposerSuggestion] = []
    private(set) var composerSuggestionSelection = ChatComposerSuggestionSelection()
    public let transcript = ChatTranscriptState()
    public let composerDraft = ChatComposerDraft()
    public var isAttachmentPickerShown = false
    public var isCameraPickerShown = false
    public var isPhotoPickerShown = false
    public private(set) var dictationPhase: ChatComposerDictationPhase = .idle
    public private(set) var dictationLevels: [CGFloat] = Array(repeating: 0.12, count: 48)
    public private(set) var dictationDuration: TimeInterval = 0

    public var messages: [ChatMessage] {
        transcript.messages
    }

    public var isShowingDictationComposer: Bool {
        dictationPhase != .idle
    }

    public var activeProjectIdForWorkspacePanel: String? {
        activeProjectId
    }

    public var shouldShowStopButton: Bool {
        isAwaitingAgentResponse || isStopping
    }

    public var canSubmitMessage: Bool {
        selectedAgent != nil && !isSending && !isStopping
    }

    public var activeSessionTitle: String {
        guard let selectedSessionId else {
            return activeContextTitle ?? "New chat"
        }
        return sessions.first(where: { $0.id == selectedSessionId })?.title
            ?? activeContextTitle
            ?? "Session \(selectedSessionId.prefix(8))"
    }

    public var activeProjectNameForWorkspacePanel: String? {
        guard let title = activeContextTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return nil
        }
        if title.hasPrefix("Project: ") {
            return String(title.dropFirst("Project: ".count))
        }
        if let slashRange = title.range(of: " / ") {
            return String(title[..<slashRange.lowerBound])
        }
        return title
    }

    @ObservationIgnored private let apiClient: SloppyAPIClient
    @ObservationIgnored private let cacheStore: ClientCacheStore
    @ObservationIgnored private let settings: ClientSettings
    @ObservationIgnored private let restoresLastSession: Bool
    public let connectionMonitor: ConnectionMonitor
    @ObservationIgnored private let onOpenSettings: @MainActor () -> Void

    @ObservationIgnored private var socketManager: SessionSocketManager?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var sessionStatusTask: Task<Void, Never>?
    @ObservationIgnored private var streamingFlushTask: Task<Void, Never>?
    @ObservationIgnored private var pendingStreamingSessionId: String?
    @ObservationIgnored private var pendingStreamingAssistantText: String?
    @ObservationIgnored private var pendingStreamingTextUpdateMode: StreamingTextUpdateMode?
    @ObservationIgnored private var pendingNavigationRequest: ChatNavigationRequest?
    @ObservationIgnored private var pendingSessionSummary: ChatSessionSummary?
    @ObservationIgnored private var lastAppliedNavigationRequestId: Int?
    @ObservationIgnored private var activeProjectId: String?
    @ObservationIgnored private var activeTaskId: String?
    @ObservationIgnored private var didLoadInitialData = false
    @ObservationIgnored private var isLoadingInitialData = false
    @ObservationIgnored private var sessionLoadGeneration = 0
    @ObservationIgnored private var composerDraftsByKey: [String: String] = [:]
    @ObservationIgnored private var activeComposerDraftKey: String?
    @ObservationIgnored private let dictationRecorder = DictationRecorder()
    @ObservationIgnored private var dictationMeterTask: Task<Void, Never>?
    @ObservationIgnored private var suggestionTask: Task<Void, Never>?

    public init(
        apiClient: SloppyAPIClient,
        cacheStore: ClientCacheStore = ClientCacheStore(),
        settings: ClientSettings,
        connectionMonitor: ConnectionMonitor,
        restoresLastSession: Bool = true,
        onOpenSettings: @escaping @MainActor () -> Void
    ) {
        self.apiClient = apiClient
        self.cacheStore = cacheStore
        self.settings = settings
        self.connectionMonitor = connectionMonitor
        self.restoresLastSession = restoresLastSession
        self.onOpenSettings = onOpenSettings
    }

    public func openSettings() {
        onOpenSettings()
    }

    public func dismissComposerFocus() {
        composerFocusResetToken += 1
    }

    func updateComposerSuggestions(for text: String) {
        suggestionTask?.cancel()
        guard let query = ChatComposerQuery.parse(text), let agent = selectedAgent else {
            setComposerSuggestions([])
            return
        }

        suggestionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let suggestions = await loadComposerSuggestions(query: query, agentId: agent.id)
            guard !Task.isCancelled, ChatComposerQuery.parse(composerDraft.text) == query else { return }
            setComposerSuggestions(suggestions)
        }
    }

    @discardableResult
    func moveComposerSuggestionSelection(_ direction: ChatComposerSuggestionSelectionDirection) -> Bool {
        composerSuggestionSelection.move(direction, in: composerSuggestions)
    }

    @discardableResult
    func applySelectedComposerSuggestion() -> Bool {
        guard let suggestion = composerSuggestionSelection.selectedSuggestion(in: composerSuggestions) else {
            return false
        }
        applyComposerSuggestion(suggestion)
        return true
    }

    func applyComposerSuggestion(_ suggestion: ChatComposerSuggestion) {
        guard let query = ChatComposerQuery.parse(composerDraft.text) else { return }
        composerDraft.text = query.applying(suggestion, to: composerDraft.text)
        setComposerSuggestions([])
    }

    private func setComposerSuggestions(_ suggestions: [ChatComposerSuggestion]) {
        composerSuggestions = suggestions
        composerSuggestionSelection.reconcile(with: suggestions)
    }

    private func loadComposerSuggestions(query: ChatComposerQuery, agentId: String) async -> [ChatComposerSuggestion] {
        switch query.trigger {
        case "/":
            let response = try? await apiClient.fetchChatSlashCommands(agentId: agentId)
            return filterCommands(response?.commands ?? [], query: query.term, skillsOnly: false)
        case "@":
            async let commands = try? await apiClient.fetchChatSlashCommands(agentId: agentId)
            async let files = loadProjectFiles(projectId: activeProjectId)
            let skillItems = filterCommands((await commands)?.commands ?? [], query: query.term, skillsOnly: true)
            return Array((skillItems + (await files).filter { matches(query.term, in: $0.title) }).prefix(12))
        case "#":
            guard let projectId = activeProjectId,
                  let project = try? await apiClient.fetchProject(id: projectId) else { return [] }
            return (project.tasks ?? [])
                .filter { matches(query.term, in: $0.title) || matches(query.term, in: $0.id) }
                .prefix(12)
                .map {
                    ChatComposerSuggestion(
                        id: "task:\($0.id)", kind: .task, title: $0.title,
                        subtitle: $0.status.replacingOccurrences(of: "_", with: " "), insertion: "#\($0.id)"
                    )
                }
        default:
            return []
        }
    }

    private func filterCommands(
        _ commands: [AgentChatSlashCommandItem],
        query: String,
        skillsOnly: Bool
    ) -> [ChatComposerSuggestion] {
        commands
            .filter { !skillsOnly || $0.source == "skill" }
            .filter { matches(query, in: $0.name) || matches(query, in: $0.description) }
            .prefix(12)
            .map {
                let isSkill = $0.source == "skill"
                let prefix = skillsOnly ? "@" : "/"
                return ChatComposerSuggestion(
                    id: "\($0.source):\($0.skillId ?? $0.name)",
                    kind: isSkill ? .skill : .command,
                    title: prefix + $0.name,
                    subtitle: $0.description,
                    insertion: prefix + $0.name
                )
            }
    }

    private func loadProjectFiles(projectId: String?) async -> [ChatComposerSuggestion] {
        guard let projectId else { return [] }
        var pending = [""]
        var results: [ChatComposerSuggestion] = []
        while let directory = pending.popLast(), results.count < 200, !Task.isCancelled {
            guard let entries = try? await apiClient.fetchProjectFiles(projectId: projectId, path: directory) else { continue }
            for entry in entries {
                let path = directory.isEmpty ? entry.name : "\(directory)/\(entry.name)"
                if entry.type == .directory {
                    pending.append(path)
                } else {
                    results.append(ChatComposerSuggestion(
                        id: "file:\(path)", kind: .file, title: path,
                        subtitle: "Project file", insertion: "@\(path)"
                    ))
                }
            }
        }
        return results
    }

    private func matches(_ query: String, in value: String) -> Bool {
        query.isEmpty || value.localizedCaseInsensitiveContains(query)
    }

    public func loadInitialData() {
        guard !didLoadInitialData, !isLoadingInitialData else { return }

        isLoadingInitialData = true
        Task { @MainActor in
            defer {
                didLoadInitialData = true
                isLoadingInitialData = false
            }

            async let agentsRequest = try? await apiClient.fetchAgents()
            async let modelsRequest = try? await apiClient.fetchAvailableModels()
            async let projectsRequest = try? await apiClient.fetchProjects()
            let fetched = await agentsRequest ?? []
            let fetchedModels = await modelsRequest ?? []
            projects = await projectsRequest ?? []
            if fetched.isEmpty {
                agents = await cacheStore.loadAgents()
            } else {
                agents = fetched
                await cacheStore.cacheAgents(fetched)
            }
            applyAvailableModels(fetchedModels)

            let availableAgents = agents
            let lastId = settings.lastAgentId
            let agent = availableAgents.first(where: { $0.id == lastId }) ?? availableAgents.first
            if let agent {
                selectedAgent = agent
                await loadSessions(for: agent)

                if let pendingSessionSummary {
                    openSessionFromSummary(pendingSessionSummary)
                } else if restoresLastSession,
                          let lastSessionId = settings.lastSessionId,
                          sessions.contains(where: { $0.id == lastSessionId }) {
                    selectSession(lastSessionId)
                } else {
                    selectedSessionId = nil
                    transcript.clear()
                    activeContextTitle = nil
                    activeProjectId = nil
                    activeTaskId = nil
                    if restoresLastSession {
                        settings.lastSessionId = nil
                    }
                    syncComposerDraft(toSessionId: nil, projectId: nil, taskId: nil, agentId: agent.id)
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
        switchAgent(agent)
    }

    public func pickModel(_ model: ChatModelOption) {
        selectedModelId = model.id
        selectedReasoningEffort = .default
    }

    public func pickReasoningEffort(_ effort: ChatReasoningEffort) {
        selectedReasoningEffort = effort
    }

    public func pickSession(_ session: ChatSessionSummary) {
        openSession(session)
    }

    public func pickNewSession() {
        startNewSession()
    }

    public func pickProject(_ project: APIProjectRecord) {
        guard let agent = selectedAgent ?? agents.first else { return }
        activateProjectContext(
            agent: agent,
            projectId: project.id,
            contextTitle: "Project: \(project.name)",
            preferredSessionTitle: nil,
            preferredTaskId: nil,
            opensPreferredSession: false
        )
    }

    public func useStarterPrompt(_ prompt: String) {
        composerDraft.text = prompt
        saveActiveComposerDraft()
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

    public func openSessionFromSummary(_ session: ChatSessionSummary) {
        if agents.isEmpty {
            pendingSessionSummary = session
            loadInitialData()
            return
        }

        pendingSessionSummary = nil
        openSession(session)
    }

    public func attachProjectFileReference(projectId: String, path: String, type: String) {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }

        let reference = type == "directory"
            ? "@project[\(projectId)]:dir:\(trimmedPath)"
            : "@project[\(projectId)]:file:\(trimmedPath)"
        composerDraft.text = composerDraft.text.isEmpty
            ? reference
            : "\(composerDraft.text)\n\(reference)"
        saveActiveComposerDraft()
    }

    public func attachFileURLs(_ urls: [URL]) {
        let references = urls
            .map { $0.path.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "@file:\($0)" }
        guard !references.isEmpty else { return }

        composerDraft.text = ([composerDraft.text] + references)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        saveActiveComposerDraft()
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
        saveActiveComposerDraft()
        selectedAgent = agent
        selectedSessionId = nil
        transcript.clear()
        activeContextTitle = nil
        activeProjectId = nil
        activeTaskId = nil
        settings.lastAgentId = agent.id
        settings.lastSessionId = nil
        syncComposerDraft(toSessionId: nil, projectId: nil, taskId: nil, agentId: agent.id)
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
        saveActiveComposerDraft()
        transcript.clear()
        selectedSessionId = nil
        activeContextTitle = contextTitle
        activeProjectId = projectId
        activeTaskId = taskId
        syncComposerDraft(toSessionId: nil, projectId: projectId, taskId: taskId, agentId: agent.id)
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
            await connectToSession(agentId: agent.id, sessionId: summary.id)
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
        saveActiveComposerDraft()
        disconnectCurrentSession()
        transcript.clear()
        selectedSessionId = sessionId
        activeContextTitle = retainedContextTitle
        activeProjectId = retainedProjectId
        activeTaskId = taskId
        settings.lastSessionId = sessionId
        syncComposerDraft(toSessionId: sessionId, projectId: retainedProjectId, taskId: taskId, agentId: agent.id)
        Task { @MainActor in
            await connectToSession(agentId: agent.id, sessionId: sessionId)
        }
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
        saveActiveComposerDraft()
        selectedAgent = agent
        selectedSessionId = nil
        transcript.clear()
        activeContextTitle = contextTitle
        activeProjectId = nil
        activeTaskId = nil
        settings.lastAgentId = agent.id
        settings.lastSessionId = nil
        syncComposerDraft(toSessionId: nil, projectId: nil, taskId: nil, agentId: agent.id)

        Task { @MainActor in
            await loadSessions(for: agent)
        }
    }

    private func activateProjectContext(
        agent: APIAgentRecord,
        projectId: String,
        contextTitle: String,
        preferredSessionTitle: String?,
        preferredTaskId: String?,
        opensPreferredSession: Bool = true
    ) {
        disconnectCurrentSession()
        saveActiveComposerDraft()
        selectedAgent = agent
        selectedSessionId = nil
        transcript.clear()
        activeContextTitle = contextTitle
        activeProjectId = projectId
        activeTaskId = preferredTaskId
        settings.lastAgentId = agent.id
        settings.lastSessionId = nil
        syncComposerDraft(
            toSessionId: nil,
            projectId: projectId,
            taskId: preferredTaskId,
            agentId: agent.id
        )

        Task { @MainActor in
            await loadSessions(for: agent, projectId: preferredTaskId == nil ? projectId : nil)
            guard selectedAgent?.id == agent.id,
                  activeProjectId == projectId,
                  selectedSessionId == nil else {
                return
            }

            guard opensPreferredSession else {
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
        cancelDictationIfNeeded()
        let manager = socketManager
        streamTask?.cancel()
        streamTask = nil
        cancelPendingStreamingAssistantText()
        socketManager = nil
        if let manager {
            Task { await manager.disconnect() }
        }
    }

    private func connectToSession(agentId: String, sessionId: String) async {
        guard isCurrentSession(agentId: agentId, sessionId: sessionId) else { return }
        let manager = SessionSocketManager(baseURL: apiClient.baseURL, agentId: agentId, sessionId: sessionId)
        socketManager = manager
        // Start the socket before yielding back to callers that may immediately
        // POST a prompt into a newly-created session.
        let stream = await manager.connect()

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
                scheduleStreamingAssistantText(text, sessionId: sessionId, mode: .append)
            } else if let msg = update.message {
                upsertMessage(msg, sessionId: sessionId)
            }
            if let runStatus = update.streamEvent?.runStatus {
                handleRunStatus(runStatus, sessionId: sessionId)
            }
        case .sessionClosed, .sessionError:
            isAwaitingAgentResponse = false
            isStopping = false
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
            isAwaitingAgentResponse = false
            isStopping = false
        } else if message.role == .user {
            transcript.removeAll { $0.id.hasPrefix("optimistic-user-") }
        }

        transcript.upsert(message)
    }

    private enum StreamingTextUpdateMode {
        case append
        case replace
    }

    private func scheduleStreamingAssistantText(
        _ text: String,
        sessionId: String,
        mode: StreamingTextUpdateMode
    ) {
        guard !text.isEmpty else { return }
        pendingStreamingSessionId = sessionId
        isAwaitingAgentResponse = true
        isStopping = false
        switch mode {
        case .append:
            pendingStreamingAssistantText = (pendingStreamingAssistantText ?? "") + text
            if pendingStreamingTextUpdateMode != .replace {
                pendingStreamingTextUpdateMode = .append
            }
        case .replace:
            pendingStreamingAssistantText = text
            pendingStreamingTextUpdateMode = .replace
        }

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
              let text = pendingStreamingAssistantText,
              let mode = pendingStreamingTextUpdateMode else {
            streamingFlushTask = nil
            return
        }

        pendingStreamingSessionId = nil
        pendingStreamingAssistantText = nil
        pendingStreamingTextUpdateMode = nil
        streamingFlushTask = nil
        applyStreamingAssistantText(text, sessionId: sessionId, mode: mode)
    }

    private func cancelPendingStreamingAssistantText(for sessionId: String? = nil) {
        guard sessionId == nil || pendingStreamingSessionId == sessionId else {
            return
        }

        streamingFlushTask?.cancel()
        streamingFlushTask = nil
        pendingStreamingSessionId = nil
        pendingStreamingAssistantText = nil
        pendingStreamingTextUpdateMode = nil
    }

    private func applyStreamingAssistantText(
        _ text: String,
        sessionId: String,
        mode: StreamingTextUpdateMode
    ) {
        let id = streamingAssistantMessageId(for: sessionId)
        switch mode {
        case .append:
            transcript.appendStreamingAssistantText(text, messageId: id)
        case .replace:
            transcript.upsert(
                ChatMessage(
                    id: id,
                    role: .assistant,
                    segments: [ChatMessageSegment(kind: .text, text: text)]
                )
            )
        }
    }

    private func handleRunStatus(_ status: ChatRunStatusEvent, sessionId: String) {
        if status.stage == .responding,
           let expandedText = status.expandedText,
           !expandedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scheduleStreamingAssistantText(expandedText, sessionId: sessionId, mode: .replace)
        }

        switch status.stage {
        case .thinking, .searching, .responding, .paused:
            isAwaitingAgentResponse = true
        case .done, .interrupted:
            isAwaitingAgentResponse = false
            isStopping = false
        }
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
        guard let agent = selectedAgent, !isSending, !isStopping else { return }
        sendErrorMessage = nil
        clearActiveComposerDraft()
        dismissComposerFocus()
        isAwaitingAgentResponse = true

        if selectedSessionId == nil {
            Task { @MainActor in
                do {
                    let summary = try await apiClient.createAgentSession(
                        agentId: agent.id,
                        title: activeTaskId.map(taskSessionTitle(for:)) ?? activeContextTitle ?? "Chat with \(agent.displayName)",
                        projectId: activeProjectId
                    )
                    sessions.insert(summary, at: 0)
                    selectedSessionId = summary.id
                    settings.lastSessionId = summary.id
                    syncComposerDraft(
                        toSessionId: summary.id,
                        projectId: activeProjectId,
                        taskId: activeTaskId,
                        agentId: agent.id
                    )
                    await connectToSession(agentId: agent.id, sessionId: summary.id)
                    await postMessage(content: content, agentId: agent.id, sessionId: summary.id)
                } catch {
                    isAwaitingAgentResponse = false
                    composerDraft.text = content
                    sendErrorMessage = "Could not create session: \(error.localizedDescription)"
                }
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
        defer { isSending = false }
        let optimistic = ChatMessage(
            id: "optimistic-user-\(UUID().uuidString)",
            role: .user,
            segments: [ChatMessageSegment(kind: .text, text: content)]
        )
        transcript.append(optimistic)
        do {
            _ = try await apiClient.postSessionMessage(
                agentId: agentId,
                sessionId: sessionId,
                content: content,
                selectedModel: selectedModelId,
                reasoningEffort: selectedModelSupportsReasoningEffort ? selectedReasoningEffort.payloadValue : nil
            )
        } catch {
            transcript.removeAll { $0.id == optimistic.id }
            isAwaitingAgentResponse = false
            composerDraft.text = content
            sendErrorMessage = "Message was not sent: \(error.localizedDescription)"
        }
    }

    public func stopActiveRun() {
        guard let agentId = selectedAgent?.id,
              let sessionId = selectedSessionId,
              shouldShowStopButton,
              !isStopping else {
            return
        }

        isStopping = true
        Task { @MainActor in
            do {
                try await apiClient.interruptAgentSession(
                    agentId: agentId,
                    sessionId: sessionId,
                    includeSubsessions: true,
                    reason: "Interrupted from Apple client"
                )
            } catch {
                isStopping = false
            }
        }
    }

    public func startDictation() {
        guard dictationPhase == .idle, !shouldShowStopButton, !isSending else {
            return
        }

        Task { @MainActor in
            do {
                try await dictationRecorder.start()
                dictationPhase = .recording
                dictationDuration = 0
                dictationLevels = Array(repeating: 0.12, count: 48)
                beginDictationMetering()
            } catch {
                resetDictationState()
                showSessionStatus(error.localizedDescription)
            }
        }
    }

    public func stopDictation() {
        guard dictationPhase == .recording else {
            return
        }

        dictationPhase = .transcribing
        dictationMeterTask?.cancel()
        dictationMeterTask = nil

        Task { @MainActor in
            do {
                let capture = try await dictationRecorder.stop()
                dictationDuration = capture.duration
                let transcript = try await transcribeDictationCapture(capture)
                composerDraft.text = transcript
                saveActiveComposerDraft()
                resetDictationState()
            } catch {
                await dictationRecorder.cancel()
                resetDictationState()
                showSessionStatus(error.localizedDescription)
            }
        }
    }

    private var selectedModelSupportsReasoningEffort: Bool {
        guard let selectedModel = availableModels.first(where: { $0.id == selectedModelId }) else {
            return false
        }
        return selectedModel.supportsReasoningEffort
    }

    private func applyAvailableModels(_ models: [ChatModelOption]) {
        availableModels = models
        guard !models.isEmpty else {
            selectedModelId = ""
            selectedReasoningEffort = .default
            return
        }

        if !models.contains(where: { $0.id == selectedModelId }) {
            selectedModelId = models[0].id
            selectedReasoningEffort = .default
        }
    }

    private func beginDictationMetering() {
        dictationMeterTask?.cancel()
        dictationMeterTask = Task { @MainActor in
            while !Task.isCancelled, dictationPhase == .recording {
                let snapshot = await dictationRecorder.snapshot()
                dictationDuration = snapshot.elapsed
                appendDictationLevel(snapshot.level)
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }

    private func appendDictationLevel(_ level: Double) {
        dictationLevels.removeFirst()
        dictationLevels.append(max(0.08, min(1, CGFloat(level))))
    }

    private func transcribeDictationCapture(_ capture: DictationCapture) async throws -> String {
        defer {
            try? FileManager.default.removeItem(at: capture.fileURL)
        }

        let audioData = try Data(contentsOf: capture.fileURL)
        if !audioData.isEmpty {
            do {
                let response = try await apiClient.transcribeVoice(
                    VoiceTranscriptionRequest(
                        audioBase64: audioData.base64EncodedString(),
                        mimeType: capture.mimeType,
                        language: Locale.current.identifier
                    )
                )
                let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            } catch {
                let fallback = try await AppleSpeechTranscriber.transcribe(
                    fileURL: capture.fileURL,
                    localeIdentifier: Locale.current.identifier
                )
                let text = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
                throw error
            }
        }

        let fallback = try await AppleSpeechTranscriber.transcribe(
            fileURL: capture.fileURL,
            localeIdentifier: Locale.current.identifier
        )
        let text = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return text
        }
        throw DictationRecorderError.noCapture
    }

    private func resetDictationState() {
        dictationMeterTask?.cancel()
        dictationMeterTask = nil
        dictationPhase = .idle
        dictationDuration = 0
        dictationLevels = Array(repeating: 0.12, count: 48)
    }

    private func cancelDictationIfNeeded() {
        guard dictationPhase != .idle else {
            return
        }
        resetDictationState()
        Task {
            await dictationRecorder.cancel()
        }
    }

    private func syncComposerDraft(
        toSessionId sessionId: String?,
        projectId: String?,
        taskId: String?,
        agentId: String?
    ) {
        let nextKey = composerDraftKey(
            sessionId: sessionId,
            projectId: projectId,
            taskId: taskId,
            agentId: agentId
        )
        activeComposerDraftKey = nextKey
        composerDraft.text = composerDraftsByKey[nextKey] ?? ""
    }

    private func saveActiveComposerDraft() {
        guard let activeComposerDraftKey else { return }
        if composerDraft.text.isEmpty {
            composerDraftsByKey.removeValue(forKey: activeComposerDraftKey)
        } else {
            composerDraftsByKey[activeComposerDraftKey] = composerDraft.text
        }
    }

    private func clearActiveComposerDraft() {
        guard let activeComposerDraftKey else {
            composerDraft.text = ""
            return
        }
        composerDraft.text = ""
        composerDraftsByKey.removeValue(forKey: activeComposerDraftKey)
    }

    private func composerDraftKey(
        sessionId: String?,
        projectId: String?,
        taskId: String?,
        agentId: String?
    ) -> String {
        if let sessionId, !sessionId.isEmpty {
            return "session:\(sessionId)"
        }

        let resolvedAgentId = agentId ?? selectedAgent?.id ?? "none"
        return "draft:\(resolvedAgentId):\(projectId ?? "-"):\(taskId ?? "-")"
    }
}
