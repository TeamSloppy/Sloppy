import Foundation
#if canImport(AppKit)
import AppKit
#endif
import ChannelPluginSupport
import Logging
import Protocols
import TauTUI

enum SloppyTUIAttachmentLimits {
    static let maxBytes = 25 * 1024 * 1024
}

enum SloppyTUISendStage: String {
    case preparing = "Preparing message"
    case creatingSession = "Creating session"
    case snapshottingUndo = "Snapshotting workspace"
    case updatingOnboarding = "Updating onboarding"
    case sending = "Sending request"
    case refreshing = "Refreshing session"
}

struct SloppyTUISendProgress {
    var stage: SloppyTUISendStage
    var attachmentCount: Int
    var inlineReferenceCount: Int
    var contentCharacters: Int?

    init(
        stage: SloppyTUISendStage,
        attachmentCount: Int = 0,
        inlineReferenceCount: Int = 0,
        contentCharacters: Int? = nil
    ) {
        self.stage = stage
        self.attachmentCount = attachmentCount
        self.inlineReferenceCount = inlineReferenceCount
        self.contentCharacters = contentCharacters
    }

    var statusLine: String {
        var details: [String] = []
        if attachmentCount > 0 {
            details.append("\(attachmentCount) attachment" + (attachmentCount == 1 ? "" : "s"))
        }
        if inlineReferenceCount > 0 {
            details.append("\(inlineReferenceCount) @path" + (inlineReferenceCount == 1 ? "" : "s"))
        }
        if let contentCharacters, contentCharacters > 0 {
            details.append("\(contentCharacters) chars")
        }

        guard !details.isEmpty else {
            return stage.rawValue + "..."
        }
        return stage.rawValue + " (" + details.joined(separator: ", ") + ")..."
    }
}

enum SloppyTUIStreamTyping {
    static let intervalNanoseconds: UInt64 = 32_000_000
    static let intervalSeconds = 0.032
    static let charactersPerSecond = 90.0
    static let maxCatchupSeconds = 0.85
}

enum SloppyTUILiveDraftPolicy {
    static func shouldInterpolate(current: String, target: String) -> Bool {
        guard !target.isEmpty,
              target.hasPrefix(current),
              target.count > current.count else {
            return false
        }

        if current.contains("\n") || target.contains("\n") || target.count > 240 {
            return false
        }

        return !hasMarkdownControlPrefix(target)
    }

    static func hasMarkdownControlPrefix(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        if trimmed.hasPrefix("#") || trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("> ") {
            return true
        }

        var sawDigit = false
        for scalar in trimmed.unicodeScalars {
            if CharacterSet.decimalDigits.contains(scalar) {
                sawDigit = true
                continue
            }
            return sawDigit && scalar == "."
        }

        return false
    }
}

enum SloppyTUILocalCardBehavior {
    static let autoDismissSeconds: TimeInterval = 10
    static let autoDismissLineLimit = 3
    static let autoDismissCharacterLimit = 320
}

enum SloppyTUITimelinePerformance {
    static let animatedSessionBlockLimit = 80
}

struct SloppyTUISessionTimelineCache {
    var revision: Int
    var width: Int
    var transcriptExpanded: Bool
    var animationFrameKey: Int
    var lines: [String]
    var containsToolTranscriptBlock: Bool
}

extension Array where Element == String {
    func trimmingEmptyEdges() -> [String] {
        var startIndex = self.startIndex
        var endIndex = self.endIndex

        while startIndex < endIndex, self[startIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            startIndex = index(after: startIndex)
        }
        while endIndex > startIndex {
            let previousIndex = index(before: endIndex)
            guard self[previousIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                break
            }
            endIndex = previousIndex
        }

        return Array(self[startIndex..<endIndex])
    }
}

enum SloppyTUIAttachmentError: LocalizedError {
    case notAFile
    case tooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .notAFile:
            return "not a file"
        case .tooLarge(let bytes):
            return "file is too large (\(bytes) bytes)"
        }
    }
}

struct SloppyTUIWorkspaceAccessRequest {
    var directoryPath: String
    var originalPath: String
    var value: String
    var context: String?
    var uploads: [AgentAttachmentUpload]
    var spawnSubSession: Bool
    var clearsPendingInputsOnSuccess: Bool
}

@MainActor
final class SloppyTUIScreen: @preconcurrency Component, @unchecked Sendable {
    let editor = Editor()
    var onExit: (@MainActor @Sendable () -> Void)?

    static let baseSlashCommands = [
        SloppyTUISlashCommand("help", "Show TUI commands"),
        SloppyTUISlashCommand("status", "Show session status"),
        SloppyTUISlashCommand("workspace", "Show workspace roots and directory access"),
        SloppyTUISlashCommand("projects", "Switch project workspace"),
        SloppyTUISlashCommand("pet", "Toggle Sloppie pet and show terminal face status"),
        SloppyTUISlashCommand("agents", "Switch agent"),
        SloppyTUISlashCommand("sessions", "Switch session"),
        SloppyTUISlashCommand("subagents", "Open a child subagent session"),
        SloppyTUISlashCommand("parent", "Return to the parent session"),
        SloppyTUISlashCommand("new", "Create a new session"),
        SloppyTUISlashCommand("bg", "Create a background worktree session", argument: "task"),
        SloppyTUISlashCommand("goal", "Set, inspect, pause, resume, or clear an autonomous goal", argument: "objective|status|pause|resume|clear|bg"),
        SloppyTUISlashCommand("pin", "Pin or unpin the current session"),
        SloppyTUISlashCommand("clear", "Clear local cards"),
        SloppyTUISlashCommand("stop", "Interrupt the current run"),
        SloppyTUISlashCommand("restore", "Nudge a live session or restore it after a failed run"),
        SloppyTUISlashCommand("up", "Alias for restore"),
        SloppyTUISlashCommand("undo", "Undo file changes from the last completed turn"),
        SloppyTUISlashCommand("redo", "Redo the last undone turn"),
        SloppyTUISlashCommand("btw", "Ask a quick side question without interrupting the main conversation", argument: "message"),
        SloppyTUISlashCommand("compact", "Free up context by summarizing the conversation so far"),
        SloppyTUISlashCommand("add_dir", "Add a working directory to this session", argument: "path"),
        SloppyTUISlashCommand("fork", "Create a branch of the current conversation", argument: "task"),
        SloppyTUISlashCommand("themes", "Switch TUI color theme"),
        SloppyTUISlashCommand("bar", "Change color bar", argument: "red|blue|green|yellow|purple|orange|pink|cyan|default"),
        SloppyTUISlashCommand("copy", "Copy last agent response to clipboard"),
        SloppyTUISlashCommand("diff", "Show changes recorded in the current TUI session"),
        SloppyTUISlashCommand("feedback", "Open GitHub issues for feedback"),
        SloppyTUISlashCommand("plan-web", "Open the latest Plan mode web page"),
        SloppyTUISlashCommand("effort", "Set reasoning effort level", argument: "low|medium|high"),
        SloppyTUISlashCommand("skills", "Show enabled skills"),
        SloppyTUISlashCommand("editor", "Open code editor, optionally choose cursor/xcode/code"),
        SloppyTUISlashCommand("model", "Switch agent model"),
        SloppyTUISlashCommand("keybindings", "Show TUI quick reference"),
        SloppyTUISlashCommand("shortcuts", "Show TUI quick reference"),
        SloppyTUISlashCommand("scrollback", "Configure timeline scrollback rendering"),
        SloppyTUISlashCommand("context", "Attach changes or source-control diff", argument: "changes|diff"),
        SloppyTUISlashCommand("tasks", "Show project tasks"),
        SloppyTUISlashCommand("mcps", "Show MCP server statuses"),
        SloppyTUISlashCommand("provider", "Configure provider"),
        SloppyTUISlashCommand("remote", "Switch to a linked Sloppy instance"),
        SloppyTUISlashCommand("local", "Switch back to the local Sloppy instance"),
        SloppyTUISlashCommand("quit", "Exit TUI"),
    ]
    static let handledSlashCommandNames: Set<String> = [
        "help",
        "status",
        "workspace",
        "projects",
        "project",
        "pet",
        "agents",
        "agent",
        "subagents",
        "children",
        "parent",
        "back",
        "sessions",
        "session",
        "new",
        "bg",
        "goal",
        "pin",
        "clear",
        "stop",
        "restore",
        "up",
        "undo",
        "redo",
        "btw",
        "compact",
        "add_dir",
        "add-dir",
        "fork",
        "themes",
        "theme",
        "bar",
        "copy",
        "diff",
        "feedback",
        "plan-web",
        "plans",
        "open-plan",
        "effort",
        "skills",
        "editor",
        "model",
        "keybindings",
        "shortcuts",
        "scrollback",
        "context",
        "tasks",
        "mcps",
        "mcp",
        "provider",
        "providers",
        "remote",
        "local",
        "openai-device",
        "anthropic-oauth",
        "anthropic-callback",
        "quit",
        "exit",
    ]

    static let firstStartBootstrapCard = """
    ## First start bootstrap
    Configure a provider with `/provider <id> <key> [model]`, `/openai-device`, or `/anthropic-oauth`.
    Type the launch prompt when ready; Sloppy will create the onboarding session turn and mark onboarding complete.
    """

    let runtime: SloppyTUIRuntime
    var service: any SloppyTUIBackend
    let logger = Logger(label: "sloppy.tui.screen")
    let desktopNotificationService = DesktopNotificationService.live()
    var project: ProjectRecord
    var agent: AgentSummary
    var session: AgentSessionSummary
    var hasPersistedSession: Bool
    let stateStore: SloppyTUIStateStore
    var state: SloppyTUIState
    let welcomeTipCursor: Int
    let initialAction: SloppyTUIInitialAction
    weak var tui: TUI?
    weak var terminal: Terminal?

    let header = Text(paddingX: 1, paddingY: 0)
    let timeline = MarkdownComponent(padding: .init(horizontal: 1, vertical: 0))
    let status = Text(paddingX: 1, paddingY: 0)

    var sessionCards: [SloppyTUITimelineBlock] = []
    var localCards: [SloppyTUILocalCard] = []
    var subSessionCards: [SloppyTUISubSessionCard] = []
    var pendingContext: String?
    var pendingUploads: [AgentAttachmentUpload] = []
    var pendingDraftCheckpointSessionID: String?
    var chatMode: AgentChatMode = .auto
    var shellModeEnabled = false
    var selectedModel = "default"
    var selectedModelContextWindowTokens = 0
    var reasoningEffort: ReasoningEffort?
    var effortSliderSelectionIndex: Int?
    var scrollbackModeSelectionIndex: Int?
    var addDirectoryInput: String?
    var pendingWorkspaceAccessRequest: SloppyTUIWorkspaceAccessRequest?
    var deniedWorkspaceAccessDirectories: Set<String> = []
    var skillSlashCommands: [SloppyTUISlashCommand] = []
    var skillSlashCommandNames: Set<String> = []
    var commandPaletteSelection = 0
    var streamTask: Task<Void, Never>?
    var sessionStreamReadyKey: String?
    var sessionStreamReadyWaiters: [CheckedContinuation<Void, Never>] = []
    var changeTask: Task<Void, Never>?
    var autoDiffTask: Task<Void, Never>?
    var devicePollTask: Task<Void, Never>?
    var thinkingAnimationTask: Task<Void, Never>?
    var autoModeAnimationTask: Task<Void, Never>?
    var projectFileIndexTask: Task<Void, Never>?
    var projectFileReindexTask: Task<Void, Never>?
    var lastChangeBatch: ProjectWorkingTreeChangeBatch?
    var lastRenderedSessionEventIDs: Set<String> = []
    var activePicker: SloppyTUIPicker?
    var pendingPlanInputRequest: PlanInputRequest?
    var pendingToolApproval: ToolApprovalRecord?
    var tokenUsageSummary: SloppyTUITokenUsageSummary?
    var tokenUsageCostUSD: Double?
    var projectFileIndex: ProjectFileIndex?
    var projectFileIndexLookup: ProjectFileIndexLookup?
    var projectFileRootURL: URL?
    var projectFileIndexLoading = false
    var projectFileSearchSelection = 0
    var suppressedProjectFileSearch: SloppyTUIProjectPathSearchSuppression?
    var projectFileIndexGeneration = 0
    var projectFileSearchCache: (generation: Int, token: String, items: [SloppyTUIPickerItem])?
    var restoredDirectorySessionKeys: Set<String> = []
    var projectTaskSearchSelection = 0
    var projectTaskAutocompleteLoading = false
    var projectTaskAutocompleteTask: Task<Void, Never>?
    var suppressedProjectTaskSearch: SloppyTUITaskReferenceSearchSuppression?
    var projectTaskGeneration = 0
    var projectTaskSearchCache: (generation: Int, token: String, items: [SloppyTUIPickerItem])?
    var editorTextRevision = 0
    var currentProjectFileTokenCache: (
        revision: Int,
        line: Int,
        column: Int,
        token: SloppyTUIProjectPathTokens.Token?
    )?
    var currentProjectTaskTokenCache: (
        revision: Int,
        line: Int,
        column: Int,
        token: SloppyTUITaskReferenceTokens.Token?
    )?
    var liveAssistantDraft: String?
    var liveAssistantTarget: String?
    var liveAssistantInterpolationTask: Task<Void, Never>?
    var liveRunStage: AgentRunStage?
    var liveRunStatusLine: String?
    var shellRunStatusLine: String?
    let tuiStartedAt = Date()
    var taskStartedAt: Date?
    var lastTaskElapsed: TimeInterval?
    var cumulativeAgentActiveTime: TimeInterval = 0
    var transientNoticeLine: String?
    var transientNoticeTask: Task<Void, Never>?
    var workspaceDiffPreview: SloppyTUIWorkspaceDiffPreview?
    var lastAgentToolActivityAt: Date?
    var transcriptExpanded = false
    var sessionUndoManagers = SloppyTUISessionUndoManagers()
    var thinkingFrame = 0
    var thinkingWord = "thinking"
    var petMood: AgentPetAnimationState = .idle
    var welcomeDismissed = false
    var isPosting = false
    var queuedMessages = SloppyTUIMessageQueue()
    var isDrainingQueuedMessages = false
    var queuedMessageInterruptRequested = false
    var isRunningShellCommand = false
    var isInterruptingRun = false
    var sendTimingStart: Date?
    var sendTimingLast: Date?
    var sendTimingFirstStreamEventMarked = false
    var sendTimingFirstModelChunkMarked = false
    var sendTimingFirstToolCallMarked = false
    var isExiting = false
    var controlCExitDetector = SloppyTUIControlCExitDetector()
    var exitAfterModelSelection = false
    var nextLocalCardID = 0
    var localCardDismissTasks: [Int: Task<Void, Never>] = [:]
    var timelineScrollOffset = 0
    var lastTimelineViewportHeight = 1
    var sessionTimelineRevision = 0
    var sessionTimelineCache: SloppyTUISessionTimelineCache?
    var sessionReloadGeneration = 0
    var mcpStatusSummary = SloppyTUIMCPStatusSummary.empty
    var projectSourceControlFooterStatus: SloppyTUISourceControlFooterStatus?
    var projectSourceControlFooterTask: Task<Void, Never>?
    var pendingRemoteNodes: [String: CoreConfig.Node] = [:]
    var pendingRemoteProjectBackend: RemoteSloppyTUIBackend?
    var sessionListMode: SloppyTUISessionListMode = .hidden
    var sessionListEntries: [SloppyTUISessionListEntry] = []
    var sessionListSelectedIndex = 0
    var sessionListRefreshTask: Task<Void, Never>?
    var postingSessionIDs: Set<String> = []
    var hitRegions: [SloppyTUIHitRegion] = []
    var scrollRegions: [SloppyTUIScrollRegion] = []
    var selectionState = SloppyTUISelectionState()
    var mouseHoverCell: SloppyTUIScreenCell?
    var mouseHoverRegion: SloppyTUIHitRegion?
    var mouseHoverAction: SloppyTUIHitAction?
    var mousePressCell: SloppyTUIScreenCell?
    var mousePressAction: SloppyTUIHitAction?
    var lastRenderedSelectionLines: [String] = []

    init(
        runtime: SloppyTUIRuntime,
        project: ProjectRecord,
        agent: AgentSummary,
        session: AgentSessionSummary,
        hasPersistedSession: Bool,
        stateStore: SloppyTUIStateStore,
        state: SloppyTUIState,
        welcomeTipCursor: Int = 0,
        initialAction: SloppyTUIInitialAction = .none,
        tui: TUI,
        terminal: Terminal
    ) {
        self.runtime = runtime
        self.service = runtime.service
        self.project = project
        self.agent = agent
        self.session = session
        self.hasPersistedSession = hasPersistedSession
        self.stateStore = stateStore
        self.state = state
        self.welcomeTipCursor = welcomeTipCursor
        self.initialAction = initialAction
        self.tui = tui
        self.terminal = terminal
        self.mcpStatusSummary = SloppyTUIMCPStatusSummary(
            available: 0,
            total: runtime.config.mcp.servers.count
        )

        editor.apply(theme: SloppyTUITheme.palette)
        if SloppyTUIAutocompleteFeatureFlags.editorAutocompleteEnabled {
            editor.setAutocompleteProvider(SloppyTUIAutocompleteProvider(basePath: runtime.cwd))
        }
        editor.onSubmit = { [weak self] value in
            guard let self else { return }
            Task { @MainActor in await self.submit(value) }
        }
        editor.onChange = { [weak self] value in
            self?.persistDraft(value)
            self?.editorTextRevision += 1
            self?.currentProjectFileTokenCache = nil
            self?.currentProjectTaskTokenCache = nil
            if !Self.isReasoningEffortSelectorText(value) {
                self?.effortSliderSelectionIndex = nil
            }
            self?.projectFileSearchSelection = 0
            self?.projectFileSearchCache = nil
            self?.projectTaskSearchSelection = 0
            self?.projectTaskSearchCache = nil
            if let suppressed = self?.suppressedProjectFileSearch,
               !suppressed.matches(self?.currentProjectFileToken()) {
                self?.suppressedProjectFileSearch = nil
            }
            if let suppressed = self?.suppressedProjectTaskSearch,
               !suppressed.matches(self?.currentProjectTaskToken()) {
                self?.suppressedProjectTaskSearch = nil
            }
        }
        let draftKey = SloppyTUIStateStore.draftKey(
            projectId: project.id,
            agentId: agent.id,
            sessionId: session.id
        )
        editor.setText(state.drafts[draftKey] ?? "")
        if hasPersistedSession {
            trackSession(session, opened: true)
        }
        refreshStaticChrome()
        renderTimeline()
    }

    func start() {
        let startupService = service
        Task {
            await startupService.waitForStartup()
        }
        if hasPersistedSession {
            Task { @MainActor in
                await restorePersistedDirectoriesForCurrentSession()
                await prepareCurrentSessionContext()
                await reloadSession()
            }
        }
        Task { @MainActor in await reloadSkillSlashCommands() }
        Task { @MainActor in
            await refreshSelectedModel()
            if case .modelPicker(let exitAfterSelection) = initialAction {
                await showModelPicker(exitAfterSelection: exitAfterSelection)
            }
        }
        if hasPersistedSession {
            streamSession()
        }
        streamChanges()
        scheduleProjectSourceControlFooterRefresh()
        startAutoModeAnimationIfNeeded()
        loadProjectFileIndex()
        reloadProjectForTaskAutocompleteIfNeeded()
        Task { @MainActor in await refreshMCPStatusSummary() }
        if !runtime.config.onboarding.completed {
            appendLocalCard(Self.firstStartBootstrapCard)
        }
    }

    func stopBackgroundTasks() {
        streamTask?.cancel()
        resumeSessionStreamReadyWaiters()
        changeTask?.cancel()
        autoDiffTask?.cancel()
        autoDiffTask = nil
        devicePollTask?.cancel()
        thinkingAnimationTask?.cancel()
        autoModeAnimationTask?.cancel()
        autoModeAnimationTask = nil
        projectFileIndexTask?.cancel()
        projectSourceControlFooterTask?.cancel()
        projectSourceControlFooterTask = nil
        projectTaskAutocompleteTask?.cancel()
        projectFileReindexTask?.cancel()
        sessionListRefreshTask?.cancel()
        sessionListRefreshTask = nil
        transientNoticeTask?.cancel()
        transientNoticeTask = nil
        cancelLocalCardDismissTasks()
    }

    func render(width: Int) -> [String] {
        hitRegions.removeAll(keepingCapacity: true)
        scrollRegions.removeAll(keepingCapacity: true)
        terminal?.setMouseReportingEnabled(true)
        let height = max(terminal?.rows ?? 24, 12)
        let lines = renderBaseScreen(width: width, height: height)
        let normalized = SloppyTUITheme.normalize(lines: lines, width: width, height: max(height, lines.count))
        registerTextHitRegions(lines: normalized, width: width)
        lastRenderedSelectionLines = normalized
        let hoverRegion = mouseHoverCell.flatMap(hitRegion(at:))
        mouseHoverRegion = hoverRegion
        mouseHoverAction = hoverRegion?.action
        let hoverLines = selectionState.activeRange == nil
            ? SloppyTUISelectionRenderer.applyHitRegionOverlay(lines: normalized, region: hoverRegion)
            : normalized
        return SloppyTUISelectionRenderer.applySelectionOverlay(lines: hoverLines, range: selectionState.activeRange)
    }

    func handle(input: TerminalInput) {
        controlCExitDetector.reset()
        if handleMouseInput(input) {
            return
        }
        if handleQueuedMessageCancel(input) {
            return
        }
        if handleActivePicker(input: input) {
            return
        }
        if handleAddDirectoryInput(input: input) {
            return
        }
        if handleReasoningEffortSelector(input: input) {
            return
        }
        if handleScrollbackModeSelector(input: input) {
            return
        }
        if handleCommandPalette(input: input) {
            return
        }
        if shouldPrioritizeComposerSubmit(over: input) {
            editor.handle(input: input)
            return
        }
        if handleSessionListInput(input) {
            return
        }
        if handleSessionListOpenShortcut(input) {
            return
        }
        if handleProjectTaskSearchInput(input) {
            return
        }
        if handleProjectFileSearchInput(input) {
            return
        }
        if handleShellModeToggle(input) {
            return
        }
        if handleGlobalShortcut(input) {
            return
        }
        if handleAttachmentInput(input) {
            return
        }
        if handleRunInterrupt(input) {
            return
        }
        if handleModeCycle(input) {
            return
        }
        if handleTranscriptInput(input) {
            return
        }
        if handleTimelineScroll(input) {
            return
        }
        editor.handle(input: input)
    }

}

#if canImport(AppKit)
extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
#endif
