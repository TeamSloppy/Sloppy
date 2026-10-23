import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import UniformTypeIdentifiers

@Observable
@MainActor
public final class ChatScreenViewModel {
    static let maximumAttachmentCount = 10
    static let maximumAttachmentSize = 25 * 1_024 * 1_024

    public internal(set) var agents: [APIAgentRecord] = []
    public internal(set) var projects: [APIProjectRecord] = []
    public internal(set) var selectedAgent: APIAgentRecord?
    public internal(set) var availableModels: [ChatModelOption] = []
    public internal(set) var selectedModelId: String = ""
    public internal(set) var selectedReasoningEffort: ChatReasoningEffort = .default
    public internal(set) var contextTokenUsage: ChatTokenUsage?
    public internal(set) var semanticDecisionUsage: ChatSemanticDecisionUsage?
    public internal(set) var sessions: [ChatSessionSummary] = []
    public internal(set) var sessionCatalog: [ChatSessionSummary] = []
    public var sessionToRename: ChatSessionSummary?
    public var selectedSessionId: String?
    public var pinnedSessionIds: Set<String> { settings.pinnedSessionIds }
    public internal(set) var activeContextTitle: String?
    public internal(set) var sessionActionStatus: String?
    public internal(set) var sendErrorMessage: String?
    public internal(set) var isLoadingSessions = false
    public internal(set) var isLoadingTranscript = false
    public internal(set) var isLoadingEarlierMessages = false
    public internal(set) var transcriptLoadError: String?
    var historyPage: ChatSessionHistoryPage?
    @ObservationIgnored var latestHydratedEventIDs: Set<String>?
    @ObservationIgnored var isEarlierPageLoadError = false
    public var hasEarlierTranscriptMessages: Bool {
        transcript.hasEarlierMessages || historyPage?.hasMore == true
    }
    public internal(set) var isSending = false
    public internal(set) var isAwaitingAgentResponse = false
    public internal(set) var isStopping = false
    public internal(set) var pendingToolApproval: PendingToolApprovalRecord?
    public internal(set) var isResolvingToolApproval = false
    public internal(set) var toolApprovalErrorMessage: String?
    public internal(set) var selectedApprovalMode: ChatApprovalMode = .askForApproval
    public internal(set) var isSavingApprovalMode = false
    public internal(set) var isLoadingApprovalMode = false
    public internal(set) var approvalModeErrorMessage: String?
    var approvalModesBySession: [String: ChatApprovalMode] = [:]
    var approvalModeRevision = UUID()
    @ObservationIgnored var approvalModeSaveTask: Task<ChatApprovalPolicy, Error>?
    public internal(set) var activeInputRequest: ChatPlanInputRequest?
    public internal(set) var isSubmittingInputResponse = false
    public internal(set) var inputRequestErrorMessage: String?
    public internal(set) var activeRunStatus: ChatRunStatusEvent?
    internal(set) var computerUseActivity: ChatComputerUseActivity?
    internal(set) var isComputerUsePreviewHidden = false
    public internal(set) var workingTreeSourceControl: ProjectWorkingTreeSourceControlResponse?
    public internal(set) var didLoadInitialData = false
    public internal(set) var transcriptScrollToEndRequest = 0
    internal(set) var providerSettingsRecoveryMessageIDs: Set<String> = []
    public internal(set) var composerFocusResetToken = 0
    public internal(set) var composerFocusRequestToken = 0
    public private(set) var isMobileComposerExpanded = false
    public internal(set) var isMobileComposerFullscreen = false
    public private(set) var composerPanelHeight: CGFloat?
    internal(set) var composerSuggestions: [ChatComposerSuggestion] = []
    internal(set) var composerSuggestionSelection = ChatComposerSuggestionSelection()
    public let transcript = ChatTranscriptState()
    public let launch: ChatLaunchViewModel
    public let parallelAgents: ChatParallelAgentsViewModel
    var attachmentPreviewContext: ChatAttachmentPreviewContext {
        let client = apiClient
        let agentID = selectedAgent?.id
        let sessionID = selectedSessionId
        return ChatAttachmentPreviewContext(
            scope: [client.endpoint.cacheNamespace, agentID ?? "", sessionID ?? ""],
            load: { attachment in
                if let data = attachment.previewData { return data }
                guard let agentID, let sessionID else { throw URLError(.resourceUnavailable) }
                return try await client.fetchSessionAttachment(agentID: agentID, sessionID: sessionID, attachmentID: attachment.id)
            }
        )
    }

    public var sessionEndpoint: SloppyInstanceEndpoint { apiClient.endpoint }
    @ObservationIgnored public var onOpenWorkerSession: (@MainActor (ChatSessionSummary, ChatScreenViewModel) -> Void)?
    public let composerDraft = ChatComposerDraft()
    public internal(set) var composerAttachments: [ChatComposerAttachment] = []
    public internal(set) var composerQuotes: [ChatComposerQuote] = []
    var editingComposerQuoteID: UUID?
#if os(macOS)
    @ObservationIgnored let quoteAnnotationPresenter = ChatQuoteAnnotationPresenter()
#endif
    internal(set) var queuedMessages: [ChatQueuedMessage] = []
    public var isAttachmentPickerShown = false
    public var isCameraPickerShown = false
    public var isPhotoPickerShown = false
    public internal(set) var dictationPhase: ChatComposerDictationPhase = .idle
    public internal(set) var dictationLevels: [CGFloat] = Array(repeating: 0.12, count: 48)
    public internal(set) var dictationDuration: TimeInterval = 0
    /// Reads finished assistant replies aloud through Core's speech provider. Persisted per device.
    public internal(set) var isReadAloudEnabled = UserDefaults.standard.bool(forKey: "sloppy.chat.readAloud")
    public var isSpeakingReply: Bool { voiceReplyPlayer.isSpeaking }

    public var messages: [ChatMessage] {
        transcript.messages
    }

    public var modelPickerOptions: [ChatModelOption] {
        [ChatModelSelection.automaticJEVOption] + availableModels
    }

    public var isAutomaticModelSelection: Bool {
        selectedModelId == ChatModelSelection.automaticJEVId
    }

    public var isShowingDictationComposer: Bool {
        dictationPhase != .idle
    }

    func updateMobileComposerExpansion(_ isExpanded: Bool) {
        isMobileComposerExpanded = isExpanded
        if !isExpanded { isMobileComposerFullscreen = false }
    }

    func updateComposerPanelHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        guard composerPanelHeight.map({ abs($0 - height) > 0.5 }) ?? true else { return }
        composerPanelHeight = height
    }

    public var activeProjectIdForWorkspacePanel: String? {
        activeProjectId
    }

    public var activeWorkspaceIdForCanvas: String? {
        guard let selectedSessionId else {
            return nil
        }
        return sessions.first(where: { $0.id == selectedSessionId })?.workspaceId
    }

    public var isLongChat: Bool {
        sessions.first(where: { $0.id == selectedSessionId })?.kind == "long_chat"
    }

    public var activeLongChatTaskCount: Int {
        transcript.messages.compactMap(\.longChatTask).filter { !$0.task.status.isTerminal }.count
    }

    var createsSeparateProjectChat = false

    public func openLongChat() {
        guard let agent = selectedAgent else { return }
        let projectId = activeProjectId
        Task { @MainActor in
            do {
                let session = try await apiClient.openLongChat(agentId: agent.id, projectId: projectId)
                guard selectedAgent?.id == agent.id, activeProjectId == projectId else { return }
                upsertSessionSummary(session)
                openSession(session)
            } catch { sendErrorMessage = error.localizedDescription }
        }
    }

    public func openLongChatWorker(_ sessionID: String) {
        guard let agent = selectedAgent else { return }
        let parentID = selectedSessionId
        Task { @MainActor in
            do {
                let detail = try await apiClient.fetchAgentSession(agentId: agent.id, sessionId: sessionID, eventLimit: 1)
                guard selectedAgent?.id == agent.id, selectedSessionId == parentID else { return }
                var summary = detail.summary
                summary.parentSessionId = summary.parentSessionId ?? parentID
                upsertSessionSummary(summary)
                if let onOpenWorkerSession {
                    onOpenWorkerSession(summary, self)
                } else {
                    openSession(summary)
                }
            } catch { sendErrorMessage = error.localizedDescription }
        }
    }

    public var activeParentSessionID: String? {
        let parentID = (sessions + sessionCatalog).first { $0.id == selectedSessionId }?.parentSessionId
        guard let parentID, !parentID.isEmpty, parentID != selectedSessionId else { return nil }
        return parentID
    }

    public func returnToParentChat() {
        guard let parentID = activeParentSessionID, let agent = selectedAgent else { return }
        if let parent = (sessions + sessionCatalog).first(where: { $0.id == parentID }) {
            openSession(parent)
            return
        }
        let childID = selectedSessionId
        Task { @MainActor in
            do {
                let detail = try await apiClient.fetchAgentSession(agentId: agent.id, sessionId: parentID, eventLimit: 1)
                guard selectedAgent?.id == agent.id, selectedSessionId == childID else { return }
                upsertSessionSummary(detail.summary)
                openSession(detail.summary)
            } catch { sendErrorMessage = error.localizedDescription }
        }
    }

    public func updateLongChatTask(_ taskID: String, action: String) {
        guard let agent = selectedAgent, let sessionID = selectedSessionId else { return }
        Task { @MainActor in
            do {
                _ = try await apiClient.updateLongChatTask(agentId: agent.id, sessionId: sessionID, taskId: taskID, action: action)
                await hydrateSession(agentId: agent.id, sessionId: sessionID)
            } catch { sendErrorMessage = error.localizedDescription }
        }
    }

    public func stopLongChatTasks() {
        guard let agent = selectedAgent, let sessionID = selectedSessionId else { return }
        Task { @MainActor in
            do { try await apiClient.cancelLongChatTasks(agentId: agent.id, sessionId: sessionID) }
            catch { sendErrorMessage = error.localizedDescription }
        }
    }

    public var shouldShowStopButton: Bool {
        isAwaitingAgentResponse || isStopping
    }

    public var contextUsage: ChatContextUsage? {
        let contextModelId = isAutomaticModelSelection
            ? activeRunStatus?.selectedModel ?? availableModels.first?.id
            : selectedModelId
        guard let model = availableModels.first(where: { $0.id == contextModelId }),
              let limitTokens = model.contextWindowTokens else {
            return nil
        }
        return ChatContextUsage(
            usedTokens: contextTokenUsage?.total ?? 0,
            limitTokens: limitTokens,
            semanticDecisionUsage: semanticDecisionUsage
        )
    }

    public var canSubmitMessage: Bool {
        selectedAgent != nil
            && activeInputRequest == nil
    }

    public var willQueueMessage: Bool {
        isSending || isAwaitingAgentResponse || isStopping || pendingToolApproval != nil
            || !queuedMessages.isEmpty
    }

    public var activeRunStatusLabel: String {
        ChatRunStatusPresentation.label(
            status: activeRunStatus,
            isStopping: isStopping,
            isSending: isSending,
            isAutomaticModelSelection: isAutomaticModelSelection,
            availableModels: availableModels
        )
    }

    public var activeRunStatusDetails: String? {
        activeRunStatus?.details?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func hideComputerUsePreview() {
        isComputerUsePreviewHidden = true
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
        guard let projectId = activeProjectId else { return nil }
        if let project = projects.first(where: { $0.id == projectId }) {
            return project.name
        }
        guard selectedSessionId == nil else { return nil }
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
        return nil
    }

    @ObservationIgnored let apiClient: SloppyAPIClient
    @ObservationIgnored let cacheStore: ClientCacheStore
    @ObservationIgnored let settings: ClientSettings
    @ObservationIgnored let restoresLastSession: Bool
    @ObservationIgnored let loadsGlobalSessionCatalog: Bool
    @ObservationIgnored let onSessionSummaryChange: @MainActor (ChatSessionSummary) -> Void
    @ObservationIgnored let onPlanArtifact: @MainActor (ChatPlanArtifactPresentation) -> Void
    @ObservationIgnored let responseNotificationScheduler: any AgentResponseNotificationScheduling
    public let connectionMonitor: ConnectionMonitor
    @ObservationIgnored let onOpenSettings: @MainActor (ClientSettingsDestination) -> Void

    @ObservationIgnored var socketManager: SessionSocketManager?
    @ObservationIgnored var streamTask: Task<Void, Never>?
    @ObservationIgnored var hydrationTask: Task<Void, Never>?
    @ObservationIgnored var earlierMessagesTask: Task<Void, Never>?
    @ObservationIgnored var hydrationRequested = false
    @ObservationIgnored var streamStateRevision: UInt = 0
    @ObservationIgnored var streamCursorTracker = ChatStreamCursorTracker()
    @ObservationIgnored var usageRefreshTask: Task<Void, Never>?
    @ObservationIgnored var approvalRefreshTask: Task<Void, Never>?
    @ObservationIgnored var suspendedDeliveries: [String: SuspendedChatDelivery] = [:]
    @ObservationIgnored var backgroundHydrationIDs: [String: UUID] = [:]
    @ObservationIgnored var backgroundHydrations: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var hydrationGeneration: UInt = 0
    @ObservationIgnored var backgroundStreams: [String: (SessionSocketManager?, Task<Void, Never>)] = [:]
    @ObservationIgnored let sessionStreamProvider: (@MainActor (String, String) async -> AsyncStream<ChatStreamUpdate>)?
    @ObservationIgnored var sessionStatusTask: Task<Void, Never>?
    @ObservationIgnored var streamingFlushTask: Task<Void, Never>?
    @ObservationIgnored var pendingStreamingSessionId: String?
    @ObservationIgnored var pendingStreamingAssistantMessageId: String?
    @ObservationIgnored var pendingStreamingAssistantText: String?
    @ObservationIgnored var pendingStreamingTextUpdateMode: StreamingTextUpdateMode?
    @ObservationIgnored var streamingTurnTracker = ChatStreamingTurnTracker()
    @ObservationIgnored var pendingNavigationRequest: ChatNavigationRequest?
    @ObservationIgnored var pendingSessionSummary: ChatSessionSummary?
    @ObservationIgnored var lastAppliedNavigationRequestId: Int?
    @ObservationIgnored var activeProjectId: String?
    @ObservationIgnored var activeTaskId: String?
    @ObservationIgnored var isLoadingInitialData = false
    @ObservationIgnored var initialDataTask: Task<Void, Never>?
    @ObservationIgnored var sessionLoadGeneration = 0
    @ObservationIgnored var pendingProjectDraft: StoredComposerDraft?
    @ObservationIgnored var composerDraftsByKey: [String: StoredComposerDraft] = [:]
    @ObservationIgnored var activeComposerDraftKey: String?
    @ObservationIgnored var pendingComposerTextMutation: PendingComposerTextMutation?
    @ObservationIgnored var pendingComposerQuotes: [ChatComposerQuote] = []
    @ObservationIgnored let dictationRecorder = DictationRecorder()
    @ObservationIgnored let voiceReplyPlayer = VoiceReplyPlayer()
    @ObservationIgnored var voiceConfig: VoiceConfig?
    @ObservationIgnored var voiceConfigTask: Task<VoiceConfig?, Never>?
    @ObservationIgnored var spokenReplyIDs: Set<String> = []
    @ObservationIgnored var dictationMeterTask: Task<Void, Never>?
    @ObservationIgnored var suggestionTask: Task<Void, Never>?
    @ObservationIgnored var workingTreeSourceControlTask: Task<Void, Never>?
    @ObservationIgnored var isForkingSession = false
    @ObservationIgnored var composerSuggestionCursorOffset: Int?
    @ObservationIgnored var composerSuggestionRequestID: UInt = 0
    @ObservationIgnored var presentedPlanArtifactEventIDs: Set<String> = []
    @ObservationIgnored var messageQueue = ChatMessageQueue()
    @ObservationIgnored var isDrainingQueuedMessages = false
    @ObservationIgnored var approvalExpirationTask: Task<Void, Never>?
    @ObservationIgnored var resolvedToolApprovalIDs: Set<String> = []
    @ObservationIgnored let modelPreferences: ChatModelPreferenceStore

    public init(
        apiClient: SloppyAPIClient,
        cacheStore: ClientCacheStore = ClientCacheStore(),
        settings: ClientSettings,
        connectionMonitor: ConnectionMonitor,
        modelPreferences: ChatModelPreferenceStore = ChatModelPreferenceStore(),
        restoresLastSession: Bool = true,
        loadsGlobalSessionCatalog: Bool = false,
        onSessionSummaryChange: @escaping @MainActor (ChatSessionSummary) -> Void = { _ in },
        onPlanArtifact: @escaping @MainActor (ChatPlanArtifactPresentation) -> Void = { _ in },
        responseNotificationScheduler: any AgentResponseNotificationScheduling = LocalAgentResponseNotificationScheduler.shared,
        sessionStreamProvider: (@MainActor (String, String) async -> AsyncStream<ChatStreamUpdate>)? = nil,
        onOpenSettings: @escaping @MainActor (ClientSettingsDestination) -> Void
    ) {
        self.apiClient = apiClient
        self.sessionStreamProvider = sessionStreamProvider
        self.launch = ChatLaunchViewModel(apiClient: apiClient)
        self.parallelAgents = ChatParallelAgentsViewModel(apiClient: apiClient)
        self.cacheStore = cacheStore
        self.settings = settings
        self.connectionMonitor = connectionMonitor
        self.modelPreferences = modelPreferences
        self.restoresLastSession = restoresLastSession
        self.loadsGlobalSessionCatalog = loadsGlobalSessionCatalog
        self.onSessionSummaryChange = onSessionSummaryChange
        self.onPlanArtifact = onPlanArtifact
        self.responseNotificationScheduler = responseNotificationScheduler
        self.onOpenSettings = onOpenSettings
        self.parallelAgents.onSessionSummaryChange = { [weak self] summary in self?.mergeSessionSummary(summary) }
    }

}
