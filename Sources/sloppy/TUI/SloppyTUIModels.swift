import Foundation
import Protocols

enum SloppyTUIPickerKind: Equatable {
    case model
    case agent
    case session
    case subSession
    case workspaceAccess
    case toolApproval
    case provider
    case providerCatalog
    case remoteInstance
    case remoteProject
    case projectFile
    case projectTask
    case planInput
    case theme
}

enum SloppyTUISessionListMode: Equatable {
    case hidden
    case side
    case full
}

enum SloppyTUISessionListSection: String, CaseIterable, Equatable {
    case waitingInput = "Waiting inputs"
    case working = "Working"
    case completed = "Completed"
}

struct SloppyTUISessionListEntry: Equatable {
    var tracked: SloppyTUIState.TrackedSession
    var summary: AgentSessionSummary
    var section: SloppyTUISessionListSection
    var detail: String

    var sessionId: String { tracked.sessionId }
    var agentId: String { tracked.agentId }
}

enum SloppyTUISessionList {
    static func section(for events: [AgentSessionEvent], isPosting: Bool)
        -> SloppyTUISessionListSection
    {
        if SloppyTUIPlanInputState.latestUnansweredRequest(in: events) != nil {
            return .waitingInput
        }
        if isPosting || latestRunStage(in: events).map(isWorkingStage) == true {
            return .working
        }
        return .completed
    }

    static func sortedEntries(_ entries: [SloppyTUISessionListEntry]) -> [SloppyTUISessionListEntry]
    {
        entries.sorted { lhs, rhs in
            if lhs.section != rhs.section {
                return sectionRank(lhs.section) < sectionRank(rhs.section)
            }
            if lhs.tracked.pinned != rhs.tracked.pinned {
                return lhs.tracked.pinned
            }
            let lhsDate = lhs.summary.updatedAt
            let rhsDate = rhs.summary.updatedAt
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.sessionId < rhs.sessionId
        }
    }

    static func clampedSelection(_ selectedIndex: Int, entryCount: Int) -> Int {
        guard entryCount > 0 else { return 0 }
        return max(0, min(selectedIndex, entryCount - 1))
    }

    private static func sectionRank(_ section: SloppyTUISessionListSection) -> Int {
        switch section {
        case .waitingInput: return 0
        case .working: return 1
        case .completed: return 2
        }
    }

    private static func latestRunStage(in events: [AgentSessionEvent]) -> AgentRunStage? {
        events.reversed().first { $0.type == .runStatus && $0.runStatus != nil }?.runStatus?.stage
    }

    private static func isWorkingStage(_ stage: AgentRunStage) -> Bool {
        switch stage {
        case .thinking, .searching, .responding:
            return true
        case .paused, .done, .interrupted:
            return false
        }
    }
}

enum SloppyTUIPlanInputState {
    static func latestUnansweredRequest(in events: [AgentSessionEvent]) -> PlanInputRequest? {
        let answered = Set(
            events.compactMap { event -> String? in
                event.type == .inputResponse ? event.inputResponse?.requestId : nil
            })
        return events.compactMap { event -> PlanInputRequest? in
            event.type == .inputRequest ? event.inputRequest : nil
        }.last { request in
            !answered.contains(request.id)
        }
    }

    static func picker(
        for request: PlanInputRequest,
        previousRequestID: String?,
        previousSelectedIndex: Int
    ) -> SloppyTUIPicker? {
        let selectedIndex = previousRequestID == request.id ? previousSelectedIndex : 0
        return SloppyTUIPlanInputPicker.picker(for: request, selectedIndex: selectedIndex)
    }
}

enum SloppyTUIToolApprovalState {
    static func pendingApproval(
        in approvals: [ToolApprovalRecord],
        agentID: String,
        sessionID: String
    ) -> ToolApprovalRecord? {
        approvals
            .filter { approval in
                approval.status == .pending
                    && approval.agentId == agentID
                    && (approval.sessionId == sessionID || approval.displaySessionId == sessionID)
            }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id < rhs.id
            }
            .first
    }

    static func picker(
        for approval: ToolApprovalRecord,
        previousApprovalID: String?,
        previousSelectedIndex: Int
    ) -> SloppyTUIPicker {
        let selectedIndex = previousApprovalID == approval.id ? previousSelectedIndex : 0
        return SloppyTUIPicker(
            kind: .toolApproval,
            title: "Tool approval required",
            items: [
                SloppyTUIPickerItem(
                    value: "approve_once",
                    label: "Allow once",
                    description: approvalSummary(approval),
                    isCurrent: false
                ),
                SloppyTUIPickerItem(
                    value: "approve_session",
                    label: "Allow for session",
                    description: sessionApprovalDescription(for: approval),
                    isCurrent: false
                ),
                SloppyTUIPickerItem(
                    value: "reject",
                    label: "Deny",
                    description: "Reject this tool call",
                    isCurrent: false
                ),
            ],
            selectedIndex: max(0, min(selectedIndex, 2))
        )
    }

    static func approvalSummary(_ approval: ToolApprovalRecord) -> String {
        let reason = approval.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let reason, !reason.isEmpty {
            return "\(approval.tool) - \(reason)"
        }
        return approval.tool
    }

    private static func sessionApprovalDescription(for approval: ToolApprovalRecord) -> String {
        if approval.approvalKind == .missingAccess, !approval.grants.isEmpty {
            return "Remember this access grant for the current session"
        }
        return "Skip the next approval for this tool in the current session"
    }
}

struct SloppyTUIPickerItem {
    var value: String
    var label: String
    var description: String?
    var isCurrent: Bool
    var group: String? = nil
    var searchHaystack: String

    init(
        value: String,
        label: String,
        description: String?,
        isCurrent: Bool,
        group: String? = nil,
        searchHaystack: String? = nil
    ) {
        self.value = value
        self.label = label
        self.description = description
        self.isCurrent = isCurrent
        self.group = group
        self.searchHaystack =
            searchHaystack
            ?? [
                value,
                label,
                description ?? "",
                group ?? "",
            ].joined(separator: " ").lowercased()
    }
}

struct SloppyTUIPicker {
    var kind: SloppyTUIPickerKind
    var title: String
    var items: [SloppyTUIPickerItem]
    var selectedIndex: Int
    var allItems: [SloppyTUIPickerItem]? = nil
    var searchQuery: String = ""
    var supportsSearch: Bool = false

    var totalItemCount: Int {
        allItems?.count ?? items.count
    }

    mutating func appendSearchCharacter(_ character: Character) {
        setSearchQuery(searchQuery + String(character))
    }

    mutating func removeLastSearchCharacter() {
        guard !searchQuery.isEmpty else { return }
        var updated = searchQuery
        updated.removeLast()
        setSearchQuery(updated)
    }

    mutating func clearSearchQuery() {
        setSearchQuery("")
    }

    mutating func setSearchQuery(_ query: String) {
        guard supportsSearch, let allItems else { return }
        let previousValue = items.indices.contains(selectedIndex) ? items[selectedIndex].value : nil
        searchQuery = query
        items = Self.filteredItems(allItems, query: query)
        if let previousValue,
            let nextIndex = items.firstIndex(where: { $0.value == previousValue })
        {
            selectedIndex = nextIndex
        } else {
            selectedIndex = 0
        }
    }

    static func filteredItems(_ items: [SloppyTUIPickerItem], query: String)
        -> [SloppyTUIPickerItem]
    {
        let tokens =
            query
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).lowercased() }
        guard !tokens.isEmpty else { return items }
        return items.filter { item in
            return tokens.allSatisfy { token in
                item.searchHaystack.contains(token)
            }
        }
    }
}

enum SloppyTUIReasoningEffortSelector {
    static let options = ReasoningEffort.allCases

    static func index(for effort: ReasoningEffort?) -> Int {
        guard let effort,
            let index = options.firstIndex(of: effort)
        else {
            return options.firstIndex(of: .medium) ?? 0
        }
        return index
    }

    static func effort(at index: Int) -> ReasoningEffort {
        options[max(0, min(index, options.count - 1))]
    }

    static func movedIndex(from index: Int, delta: Int) -> Int {
        max(0, min(index + delta, options.count - 1))
    }
}

enum SloppyTUIScrollbackModeSelector {
    static let options = SloppyTUIScrollbackMode.allCases

    static func index(for mode: SloppyTUIScrollbackMode) -> Int {
        options.firstIndex(of: mode) ?? 0
    }

    static func mode(at index: Int) -> SloppyTUIScrollbackMode {
        options[max(0, min(index, options.count - 1))]
    }

    static func movedIndex(from index: Int, delta: Int) -> Int {
        max(0, min(index + delta, options.count - 1))
    }
}

enum SloppyTUIWorkspaceAccess {
    static func requiredDirectoryForAbsolutePath(
        _ rawPath: String,
        projectRootPath: String,
        sessionDirectories: [String],
        fileManager: FileManager = .default
    ) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else {
            return nil
        }

        let candidate = URL(fileURLWithPath: trimmed, isDirectory: false)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let roots = normalizedRoots([projectRootPath] + sessionDirectories)
        guard !roots.contains(where: { contains(candidate.path, inside: $0) }) else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) else {
            return nil
        }
        if isDirectory.boolValue {
            return candidate.path
        }
        return candidate.deletingLastPathComponent().path
    }

    static func normalizedRoots(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.compactMap { path in
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }
            let normalized = URL(
                fileURLWithPath: (trimmed as NSString).expandingTildeInPath, isDirectory: true
            )
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
            guard seen.insert(normalized).inserted else {
                return nil
            }
            return normalized
        }
    }

    static func contains(_ path: String, inside rootPath: String) -> Bool {
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return path == rootPath || path.hasPrefix(prefix)
    }
}

struct SloppyTUIWorkspaceDiffPreview: Equatable {
    var branch: String
    var linesAdded: Int
    var linesDeleted: Int
    var diff: String
    var truncated: Bool

    var timelineBlock: SloppyTUITimelineBlock {
        .workspaceDiff(
            branch: branch,
            linesAdded: linesAdded,
            linesDeleted: linesDeleted,
            diff: diff,
            truncated: truncated
        )
    }
}

struct SloppyTUISourceControlFooterStatus: Equatable {
    var providerId: String?
    var isRepository: Bool
    var branch: String?
    var linesAdded: Int
    var linesDeleted: Int
    var message: String?

    init(
        providerId: String?,
        isRepository: Bool,
        branch: String? = nil,
        linesAdded: Int = 0,
        linesDeleted: Int = 0,
        message: String? = nil
    ) {
        self.providerId = providerId
        self.isRepository = isRepository
        self.branch = branch
        self.linesAdded = linesAdded
        self.linesDeleted = linesDeleted
        self.message = message
    }

    init(_ response: ProjectWorkingTreeSourceControlResponse) {
        self.init(
            providerId: response.providerId,
            isRepository: response.isRepository,
            branch: response.branch,
            linesAdded: response.linesAdded,
            linesDeleted: response.linesDeleted,
            message: response.message
        )
    }
}

enum SloppyTUIChatTimelineComposition {
    static func blocks(
        sessionBlocks: [SloppyTUITimelineBlock],
        liveAssistantBlocks: [SloppyTUITimelineBlock],
        queuedMessageBlocks: [SloppyTUITimelineBlock],
        workspaceDiffPreview: SloppyTUIWorkspaceDiffPreview?,
        localCards: [SloppyTUILocalCard]
    ) -> [SloppyTUITimelineBlock] {
        sessionBlocks
            + (workspaceDiffPreview.map { [$0.timelineBlock] } ?? [])
            + liveAssistantBlocks
            + queuedMessageBlocks
            + localCards.map(\.block)
    }
}

struct SloppyTUILocalCard {
    var id: Int
    var block: SloppyTUITimelineBlock
}

enum SloppyTUIWelcomeVisibility {
    static func shouldRender(
        welcomeDismissed: Bool,
        hasPersistedSession: Bool,
        hasSessionCards: Bool,
        hasLiveAssistantDraft: Bool,
        hasQueuedMessages: Bool,
        hasLocalCards: Bool,
        hasTransientNotice _: Bool
    ) -> Bool {
        !welcomeDismissed
            && !hasPersistedSession
            && !hasSessionCards
            && !hasLiveAssistantDraft
            && !hasQueuedMessages
            && !hasLocalCards
    }
}

enum SloppyTUIDraftSessionReset {
    static func pendingCheckpointSessionID(
        currentSessionID: String,
        hasPersistedSession: Bool
    ) -> String? {
        hasPersistedSession ? currentSessionID : nil
    }
}

struct SloppyTUISubSessionCard: Equatable {
    var childSessionId: String
    var title: String
    var status: SloppyTUISubSessionStatus = .starting
}

struct SloppyTUITokenUsageSummary: Equatable {
    var promptTokens: Int
    var completionTokens: Int
    var totalTokens: Int
    var contextWindowTokens: Int
    var costUSD: Double?

    var usagePercent: Int? {
        guard contextWindowTokens > 0 else {
            return nil
        }
        return min(100, Int(((Double(totalTokens) / Double(contextWindowTokens)) * 100).rounded()))
    }

    var freeTokens: Int? {
        guard contextWindowTokens > 0 else {
            return nil
        }
        return max(0, contextWindowTokens - totalTokens)
    }
}

struct SloppyTUIMCPStatusSummary: Equatable {
    static let empty = SloppyTUIMCPStatusSummary(available: 0, total: 0)

    var available: Int
    var total: Int

    init(available: Int, total: Int) {
        let normalizedTotal = max(0, total)
        self.total = normalizedTotal
        self.available = min(max(0, available), normalizedTotal)
    }

    init(statuses: [MCPServerStatus]) {
        self.init(
            available: statuses.filter(\.connected).count,
            total: statuses.count
        )
    }
}

struct SloppyTUIContextUsageSummary: Equatable {
    var modelTitle: String
    var modelID: String
    var contextWindowLabel: String
    var promptTokens: Int
    var completionTokens: Int
    var totalTokens: Int
    var contextWindowTokens: Int
    var pendingContextAttached: Bool
    var pendingUploadCount: Int

    var usagePercent: Int? {
        guard contextWindowTokens > 0 else {
            return nil
        }
        return min(100, Int(((Double(totalTokens) / Double(contextWindowTokens)) * 100).rounded()))
    }

    var promptPercent: Double? {
        percent(promptTokens)
    }

    var completionPercent: Double? {
        percent(completionTokens)
    }

    var freeTokens: Int? {
        guard contextWindowTokens > 0 else {
            return nil
        }
        return max(0, contextWindowTokens - totalTokens)
    }

    var freePercent: Double? {
        guard let freeTokens else {
            return nil
        }
        return percent(freeTokens)
    }

    private func percent(_ tokens: Int) -> Double? {
        guard contextWindowTokens > 0 else {
            return nil
        }
        return min(100, (Double(max(0, tokens)) / Double(contextWindowTokens)) * 100)
    }
}

struct SloppyTUIExitSummary: Equatable {
    var sessionID: String
    var canResume: Bool
    var toolCallCount: Int
    var successfulToolCallCount: Int
    var failedToolCallCount: Int
    var wallTime: TimeInterval
    var agentActiveTime: TimeInterval
    var apiTime: TimeInterval
    var toolTime: TimeInterval

    var successRate: Double {
        guard toolCallCount > 0 else {
            return 0
        }
        return (Double(successfulToolCallCount) / Double(toolCallCount)) * 100
    }

    var apiTimePercent: Double {
        percent(apiTime, of: agentActiveTime)
    }

    var toolTimePercent: Double {
        percent(toolTime, of: agentActiveTime)
    }

    private func percent(_ value: TimeInterval, of total: TimeInterval) -> Double {
        guard total > 0 else {
            return 0
        }
        return min(100, max(0, (value / total) * 100))
    }
}

enum SloppyTUISubSessionStatus: Equatable {
    case starting
    case running(String?)
    case waiting(String?)
    case done
    case interrupted(String?)
}

enum SloppyTUITimelineBlock {
    case message(role: AgentMessageRole, text: String)
    case local(String)
    case queuedMessage(SloppyTUIQueuedMessage)
    case error(String)
    case thinking(String)
    case attachment(name: String, mimeType: String, sizeBytes: Int)
    case subSession(childSessionId: String, title: String, status: SloppyTUISubSessionStatus)
    case buildProgress(AgentBuildProgressEvent)
    case planArtifact(PlanArtifactRecord)
    case inputRequest(PlanInputRequest)
    case workspaceDiff(
        branch: String, linesAdded: Int, linesDeleted: Int, diff: String, truncated: Bool)
    case toolCall(tool: String, reason: String?, summary: String?, details: String?)
    case toolResult(
        tool: String, rawTool: String, ok: Bool, error: String?, durationMs: Int?, details: String?)

    var plainText: String {
        switch self {
        case .message(_, let text), .local(let text), .error(let text):
            return text
        case .queuedMessage(let message):
            return "Queued message\n\(message.displayText)"
        case .thinking(let text):
            return text
        case .attachment(let name, let mimeType, _):
            return "\(name) \(mimeType)"
        case .subSession(let childSessionId, let title, let status):
            return "\(title) \(childSessionId) \(status.plainText)"
        case .buildProgress(let progress):
            let items = progress.items.map {
                "\($0.title) \($0.status.rawValue) \($0.definitionOfDone)"
            }
            return ([progress.title] + items).joined(separator: " ")
        case .planArtifact(let artifact):
            return "Plan web page \(artifact.planName) \(artifact.webUrl)"
        case .inputRequest(let request):
            return SloppyTUIPlanInputPicker.requestText(request)
        case .workspaceDiff(let branch, let linesAdded, let linesDeleted, let diff, let truncated):
            return
                "Patched \(branch) +\(linesAdded) -\(linesDeleted) \(truncated ? "truncated" : "") \(diff)"
        case .toolCall(let tool, let reason, let summary, let details):
            return ([tool] + [summary, reason, details].compactMap { $0 }).joined(separator: " ")
        case .toolResult(let tool, _, _, let error, _, let details):
            return ([tool] + [error, details].compactMap { $0 }).joined(separator: " ")
        }
    }
}

enum SloppyTUIToolTranscriptCompactor {
    static func visibleExecutingBlocks(in blocks: [SloppyTUITimelineBlock])
        -> [SloppyTUITimelineBlock]
    {
        var pendingCalls: [(tool: String, block: SloppyTUITimelineBlock)] = []

        for block in blocks {
            switch block {
            case .toolCall(let tool, _, _, _):
                pendingCalls.append((tool: tool, block: block))
            case .toolResult(_, let rawTool, _, _, _, _):
                guard let index = pendingCalls.firstIndex(where: { $0.tool == rawTool }) else {
                    continue
                }
                pendingCalls.remove(at: index)
            default:
                continue
            }
        }

        return pendingCalls.map(\.block)
    }
}

extension SloppyTUISubSessionStatus {
    var plainText: String {
        switch self {
        case .starting:
            return "starting"
        case .running(let label):
            if let label, !label.isEmpty {
                return "working: \(label)"
            }
            return "working"
        case .waiting(let label):
            if let label, !label.isEmpty {
                return "waiting: \(label)"
            }
            return "waiting"
        case .done:
            return "done"
        case .interrupted(let label):
            if let label, !label.isEmpty {
                return "stopped: \(label)"
            }
            return "stopped"
        }
    }
}

enum SloppyTUIPlanInputPicker {
    static func picker(for request: PlanInputRequest, selectedIndex: Int = 0) -> SloppyTUIPicker? {
        let items = selectionItems(for: request)
        guard !items.isEmpty else {
            return nil
        }
        let title: String
        if request.questions.count == 1, let question = request.questions.first {
            title = question.header ?? question.question
        } else {
            title = request.title ?? "Input needed"
        }
        return SloppyTUIPicker(
            kind: .planInput,
            title: title,
            items: items,
            selectedIndex: max(0, min(selectedIndex, items.count - 1))
        )
    }

    static func selectionItems(for request: PlanInputRequest) -> [SloppyTUIPickerItem] {
        let questions = request.questions.filter { !$0.options.isEmpty }
        guard questions.count == request.questions.count else {
            return []
        }
        if questions.count == 1, let question = questions.first {
            return question.options.map { option in
                SloppyTUIPickerItem(
                    value: encodedValue([(question.id, option.id)]),
                    label: option.label,
                    description: option.description,
                    isCurrent: false
                )
            }
        }

        let combinations = optionCombinations(for: questions)
        return combinations.map { answers in
            let labels = answers.compactMap { questionID, optionID -> String? in
                questions
                    .first(where: { $0.id == questionID })?
                    .options
                    .first(where: { $0.id == optionID })?
                    .label
            }
            let description = answers.compactMap { questionID, optionID -> String? in
                guard let question = questions.first(where: { $0.id == questionID }),
                    let option = question.options.first(where: { $0.id == optionID })
                else {
                    return nil
                }
                let label = question.header ?? question.question
                return "\(label): \(option.label)"
            }.joined(separator: " | ")
            return SloppyTUIPickerItem(
                value: encodedValue(answers),
                label: labels.joined(separator: " / "),
                description: description,
                isCurrent: false
            )
        }
    }

    static func answerRequest(
        for item: SloppyTUIPickerItem,
        request: PlanInputRequest,
        userID: String = "tui"
    ) -> PlanInputAnswerRequest? {
        let decoded = decodedValue(item.value)
        guard decoded.count == request.questions.count else {
            return nil
        }
        var selectedByQuestion: [String: String] = [:]
        for (questionID, optionID) in decoded {
            selectedByQuestion[questionID] = optionID
        }
        let answers: [PlanInputAnswer] = request.questions.compactMap { question in
            guard let optionID = selectedByQuestion[question.id],
                question.options.contains(where: { $0.id == optionID })
            else {
                return nil
            }
            return PlanInputAnswer(questionId: question.id, selectedOptionId: optionID)
        }
        guard answers.count == request.questions.count else {
            return nil
        }
        return PlanInputAnswerRequest(answers: answers, userId: userID)
    }

    static func requestText(_ request: PlanInputRequest) -> String {
        let title = request.title ?? "Input needed"
        let questionText = request.questions.map { question -> String in
            let header = question.header.map { "\($0)\n" } ?? ""
            let options = question.options.map { option -> String in
                let suffix = option.description.map { " - \($0)" } ?? ""
                return "- \(option.label)\(suffix)"
            }.joined(separator: "\n")
            return "\(header)\(question.question)\n\(options)"
        }.joined(separator: "\n\n")
        return "## \(title)\n\(questionText)"
    }

    private static func optionCombinations(for questions: [PlanInputQuestion]) -> [[(
        String, String
    )]] {
        questions.reduce([[]]) { combinations, question in
            combinations.flatMap { prefix in
                question.options.map { option in
                    prefix + [(question.id, option.id)]
                }
            }
        }
    }

    private static func encodedValue(_ answers: [(String, String)]) -> String {
        answers.map { "\($0.0)=\($0.1)" }.joined(separator: "|")
    }

    private static func decodedValue(_ value: String) -> [(String, String)] {
        value.split(separator: "|").compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
                return nil
            }
            return (String(parts[0]), String(parts[1]))
        }
    }
}

extension AgentChatMode {
    var next: AgentChatMode {
        switch self {
        case .auto: return .build
        case .build: return .plan
        case .plan: return .debug
        case .debug: return .ask
        case .ask: return .auto
        }
    }

    var title: String {
        switch self {
        case .ask: return "Ask"
        case .build: return "Build"
        case .plan: return "Plan"
        case .debug: return "Debug"
        case .auto: return "Auto"
        }
    }
}
