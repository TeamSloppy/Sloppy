import Foundation

public enum AgentRuntimeType: String, Codable, Sendable, Equatable {
    case native
    case acp
}

public struct AgentRuntimeConfig: Codable, Sendable, Equatable {
    public var type: AgentRuntimeType
    public var acp: AgentACPConfig?
    public var sharedMemoryEnabled: Bool

    public init(type: AgentRuntimeType = .native, acp: AgentACPConfig? = nil, sharedMemoryEnabled: Bool = true) {
        self.type = type
        self.acp = acp
        self.sharedMemoryEnabled = sharedMemoryEnabled
    }

    enum CodingKeys: String, CodingKey {
        case type, acp, sharedMemoryEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(AgentRuntimeType.self, forKey: .type) ?? .native
        acp = try container.decodeIfPresent(AgentACPConfig.self, forKey: .acp)
        sharedMemoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .sharedMemoryEnabled) ?? true
    }
}

public struct SessionStatusResponse: Codable, Sendable, Equatable {
    public var sessionId: String
    public var status: String
    public var messageCount: Int
    public var updatedAt: Date
    public var activeProcessCount: Int

    public init(
        sessionId: String,
        status: String,
        messageCount: Int,
        updatedAt: Date,
        activeProcessCount: Int
    ) {
        self.sessionId = sessionId
        self.status = status
        self.messageCount = messageCount
        self.updatedAt = updatedAt
        self.activeProcessCount = activeProcessCount
    }
}

public enum AgentSessionKind: String, Codable, Sendable, Equatable {
    case longChat = "long_chat"
    case longChatWorker = "long_chat_worker"
    case chat
    case heartbeat
}

public struct AgentSessionRenameRequest: Codable, Sendable {
    public var title: String

    public init(title: String) {
        self.title = title
    }
}

public struct AgentSessionCreateRequest: Codable, Sendable {
    public var title: String?
    public var parentSessionId: String?
    public var kind: AgentSessionKind
    /// Explicitly create an ordinary project chat instead of opening the persistent coordinator.
    public var separateChat: Bool?
    /// When set, runs a memory checkpoint on this session before creating the new one (e.g. `/new`).
    public var checkpointSessionId: String?
    /// When set, project repo/docs context is merged into the agent session bootstrap (Dashboard project chats).
    public var projectId: String?
    /// When set, the session is scoped to a project task and inherits its task/worktree context.
    public var taskId: String?
    /// When set, the session is scoped to a canvas workspace.
    public var workspaceId: String?
    /// When set, the new session starts with a copy of this session's history instead of recovering from a parent.
    public var forkFromSessionId: String?
    /// With `forkFromSessionId`, copies history strictly before the message with this ID; nil copies everything.
    public var forkBeforeMessageId: String?

    public init(
        title: String? = nil,
        parentSessionId: String? = nil,
        kind: AgentSessionKind = .chat,
        separateChat: Bool? = nil,
        checkpointSessionId: String? = nil,
        projectId: String? = nil,
        taskId: String? = nil,
        workspaceId: String? = nil,
        forkFromSessionId: String? = nil,
        forkBeforeMessageId: String? = nil
    ) {
        self.title = title
        self.parentSessionId = parentSessionId
        self.kind = kind
        self.separateChat = separateChat
        self.checkpointSessionId = checkpointSessionId
        self.projectId = projectId
        self.taskId = taskId
        self.workspaceId = workspaceId
        self.forkFromSessionId = forkFromSessionId
        self.forkBeforeMessageId = forkBeforeMessageId
    }

    enum CodingKeys: String, CodingKey {
        case title
        case parentSessionId
        case kind
        case separateChat
        case checkpointSessionId
        case projectId
        case taskId
        case workspaceId
        case forkFromSessionId
        case forkBeforeMessageId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        parentSessionId = try container.decodeIfPresent(String.self, forKey: .parentSessionId)
        kind = try container.decodeIfPresent(AgentSessionKind.self, forKey: .kind) ?? .chat
        separateChat = try container.decodeIfPresent(Bool.self, forKey: .separateChat)
        checkpointSessionId = try container.decodeIfPresent(String.self, forKey: .checkpointSessionId)
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
        taskId = try container.decodeIfPresent(String.self, forKey: .taskId)
        workspaceId = try container.decodeIfPresent(String.self, forKey: .workspaceId)
        forkFromSessionId = try container.decodeIfPresent(String.self, forKey: .forkFromSessionId)
        forkBeforeMessageId = try container.decodeIfPresent(String.self, forKey: .forkBeforeMessageId)
    }
}

public struct AgentMemoryCheckpointRequest: Codable, Sendable {
    public var reason: String?

    public init(reason: String? = nil) {
        self.reason = reason
    }
}

public struct AgentMemoryCheckpointResponse: Codable, Sendable {
    public var ok: Bool
    public var reason: String?

    public init(ok: Bool, reason: String? = nil) {
        self.ok = ok
        self.reason = reason
    }
}

public struct AgentSessionSummary: Codable, Sendable, Equatable {
    public var id: String
    public var agentId: String
    public var title: String
    public var parentSessionId: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var messageCount: Int
    public var lastMessagePreview: String?
    public var kind: AgentSessionKind
    /// User-authored turns since last memory checkpoint (persisted in session sidecar).
    public var userTurnCount: Int
    /// Optional project scope (Dashboard project chats).
    public var projectId: String?
    /// Optional task scope for task-aware chats.
    public var taskId: String?
    /// Optional workspace scope (Dashboard workspace chats).
    public var workspaceId: String?

    public init(
        id: String,
        agentId: String,
        title: String,
        parentSessionId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messageCount: Int = 0,
        lastMessagePreview: String? = nil,
        kind: AgentSessionKind = .chat,
        userTurnCount: Int = 0,
        projectId: String? = nil,
        taskId: String? = nil,
        workspaceId: String? = nil
    ) {
        self.id = id
        self.agentId = agentId
        self.title = title
        self.parentSessionId = parentSessionId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageCount = messageCount
        self.lastMessagePreview = lastMessagePreview
        self.kind = kind
        self.userTurnCount = userTurnCount
        self.projectId = projectId
        self.taskId = taskId
        self.workspaceId = workspaceId
    }

    enum CodingKeys: String, CodingKey {
        case id
        case agentId
        case title
        case parentSessionId
        case createdAt
        case updatedAt
        case messageCount
        case lastMessagePreview
        case kind
        case userTurnCount
        case projectId
        case taskId
        case workspaceId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        agentId = try container.decode(String.self, forKey: .agentId)
        title = try container.decode(String.self, forKey: .title)
        parentSessionId = try container.decodeIfPresent(String.self, forKey: .parentSessionId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        messageCount = try container.decodeIfPresent(Int.self, forKey: .messageCount) ?? 0
        lastMessagePreview = try container.decodeIfPresent(String.self, forKey: .lastMessagePreview)
        kind = try container.decodeIfPresent(AgentSessionKind.self, forKey: .kind) ?? .chat
        userTurnCount = try container.decodeIfPresent(Int.self, forKey: .userTurnCount) ?? 0
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
        taskId = try container.decodeIfPresent(String.self, forKey: .taskId)
        workspaceId = try container.decodeIfPresent(String.self, forKey: .workspaceId)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(agentId, forKey: .agentId)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(parentSessionId, forKey: .parentSessionId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(messageCount, forKey: .messageCount)
        try container.encodeIfPresent(lastMessagePreview, forKey: .lastMessagePreview)
        try container.encode(kind, forKey: .kind)
        try container.encode(userTurnCount, forKey: .userTurnCount)
        try container.encodeIfPresent(projectId, forKey: .projectId)
        try container.encodeIfPresent(taskId, forKey: .taskId)
        try container.encodeIfPresent(workspaceId, forKey: .workspaceId)
    }
}

public enum AgentSessionEventType: String, Codable, Sendable {
    case sessionCreated = "session_created"
    case message
    case runStatus = "run_status"
    case memoryCheckpoint = "memory_checkpoint"
    case buildProgress = "build_progress"
    case planArtifact = "plan_artifact"
    case subSession = "sub_session"
    case longChatTask = "long_chat_task"
    case runControl = "run_control"
    case toolCall = "tool_call"
    case toolResult = "tool_result"
    case inputRequest = "input_request"
    case inputResponse = "input_response"
    case selfImprovementReview = "self_improvement_review"
}

public enum AgentMessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

public enum AgentMessageSegmentKind: String, Codable, Sendable {
    case text
    case thinking
    case attachment
}

public struct AgentAttachment: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var mimeType: String
    public var sizeBytes: Int
    public var relativePath: String?

    public init(
        id: String,
        name: String,
        mimeType: String,
        sizeBytes: Int,
        relativePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.relativePath = relativePath
    }
}

public struct AgentMessageSegment: Codable, Sendable, Equatable {
    public var kind: AgentMessageSegmentKind
    public var text: String?
    public var attachment: AgentAttachment?

    public init(kind: AgentMessageSegmentKind, text: String? = nil, attachment: AgentAttachment? = nil) {
        self.kind = kind
        self.text = text
        self.attachment = attachment
    }
}

public struct AgentSessionMessage: Codable, Sendable, Equatable {
    public var id: String
    public var role: AgentMessageRole
    public var segments: [AgentMessageSegment]
    public var createdAt: Date
    public var userId: String?
    public var peerOrigin: AgentSessionPeerOrigin?
    public var sessionReferences: [AgentSessionReference]?
    public var uiSurface: AgentUISurfaceSnapshot?

    public init(
        id: String = UUID().uuidString,
        role: AgentMessageRole,
        segments: [AgentMessageSegment],
        createdAt: Date = Date(),
        userId: String? = nil,
        peerOrigin: AgentSessionPeerOrigin? = nil,
        sessionReferences: [AgentSessionReference]? = nil,
        uiSurface: AgentUISurfaceSnapshot? = nil
    ) {
        self.id = id
        self.role = role
        self.segments = segments
        self.createdAt = createdAt
        self.userId = userId
        self.peerOrigin = peerOrigin
        self.sessionReferences = sessionReferences
        self.uiSurface = uiSurface
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, segments, createdAt, userId, peerOrigin, sessionReferences, uiSurface
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        role = try values.decode(AgentMessageRole.self, forKey: .role)
        segments = try values.decode([AgentMessageSegment].self, forKey: .segments)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        userId = try values.decodeIfPresent(String.self, forKey: .userId)
        peerOrigin = try values.decodeIfPresent(AgentSessionPeerOrigin.self, forKey: .peerOrigin)
        sessionReferences = try values.decodeIfPresent([AgentSessionReference].self, forKey: .sessionReferences)
        // An unsupported or damaged optional interface must never hide the ordinary message.
        uiSurface = try? values.decode(AgentUISurfaceSnapshot.self, forKey: .uiSurface)
    }
}

public enum AgentRunStage: String, Codable, Sendable {
    case thinking
    case searching
    case responding
    case paused
    case done
    case interrupted
}

public struct AgentRunDiagnostics: Codable, Sendable, Equatable {
    public var durationMs: Int
    public var toolRoundsUsed: Int
    public var maxToolRounds: Int
    public var finishedNaturally: Bool
    public var hitToolRoundLimit: Bool
    public var toolErrorCount: Int
    public var retryableToolErrorCount: Int
    public var nonRetryableToolErrorCount: Int
    public var turnExitReason: String
    public var wasInterrupted: Bool
    public var didResetContext: Bool
    public var explicitSessionCompletion: Bool

    public init(
        durationMs: Int,
        toolRoundsUsed: Int,
        maxToolRounds: Int,
        finishedNaturally: Bool,
        hitToolRoundLimit: Bool,
        toolErrorCount: Int,
        retryableToolErrorCount: Int,
        nonRetryableToolErrorCount: Int,
        turnExitReason: String,
        wasInterrupted: Bool,
        didResetContext: Bool,
        explicitSessionCompletion: Bool
    ) {
        self.durationMs = max(0, durationMs)
        self.toolRoundsUsed = max(0, toolRoundsUsed)
        self.maxToolRounds = max(0, maxToolRounds)
        self.finishedNaturally = finishedNaturally
        self.hitToolRoundLimit = hitToolRoundLimit
        self.toolErrorCount = max(0, toolErrorCount)
        self.retryableToolErrorCount = max(0, retryableToolErrorCount)
        self.nonRetryableToolErrorCount = max(0, nonRetryableToolErrorCount)
        self.turnExitReason = turnExitReason
        self.wasInterrupted = wasInterrupted
        self.didResetContext = didResetContext
        self.explicitSessionCompletion = explicitSessionCompletion
    }
}

public struct AgentRunStatusEvent: Codable, Sendable, Equatable {
    public var id: String
    public var stage: AgentRunStage
    public var label: String
    public var details: String?
    public var expandedText: String?
    public var tokenUsage: TokenUsage?
    public var selectedModel: String?
    public var diagnostics: AgentRunDiagnostics?
    public var executionOutcome: ExecutionOutcome?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        stage: AgentRunStage,
        label: String,
        details: String? = nil,
        expandedText: String? = nil,
        tokenUsage: TokenUsage? = nil,
        selectedModel: String? = nil,
        diagnostics: AgentRunDiagnostics? = nil,
        executionOutcome: ExecutionOutcome? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.stage = stage
        self.label = label
        self.details = details
        self.expandedText = expandedText
        self.tokenUsage = tokenUsage
        self.selectedModel = selectedModel
        self.diagnostics = diagnostics
        self.executionOutcome = executionOutcome
        self.createdAt = createdAt
    }
}

public enum AgentMemoryCheckpointStatus: String, Codable, Sendable, Equatable {
    case started
    case succeeded
    case failed
}

public struct AgentMemoryCheckpointEvent: Codable, Sendable, Equatable {
    public var status: AgentMemoryCheckpointStatus
    public var reason: String?
    public var message: String
    public var createdAt: Date

    public init(
        status: AgentMemoryCheckpointStatus,
        reason: String? = nil,
        message: String,
        createdAt: Date = Date()
    ) {
        self.status = status
        self.reason = reason
        self.message = message
        self.createdAt = createdAt
    }
}

public enum AgentBuildProgressStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case pending
    case inProgress = "in_progress"
    case done
    case blocked
    case skipped
}

public struct AgentBuildProgressItem: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var status: AgentBuildProgressStatus
    public var definitionOfDone: String
    public var details: String?

    public init(
        id: String,
        title: String,
        status: AgentBuildProgressStatus,
        definitionOfDone: String,
        details: String? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.definitionOfDone = definitionOfDone
        self.details = details
    }
}

public struct AgentBuildProgressEvent: Codable, Sendable, Equatable {
    public var title: String
    public var items: [AgentBuildProgressItem]
    public var createdAt: Date

    public init(
        title: String,
        items: [AgentBuildProgressItem],
        createdAt: Date = Date()
    ) {
        self.title = title
        self.items = items
        self.createdAt = createdAt
    }
}

public struct AgentPlanArtifactEvent: Codable, Sendable, Equatable {
    public var artifact: PlanArtifactRecord

    public init(artifact: PlanArtifactRecord) {
        self.artifact = artifact
    }
}

public struct AgentSubSessionEvent: Codable, Sendable, Equatable {
    public var childSessionId: String
    public var title: String

    public init(childSessionId: String, title: String) {
        self.childSessionId = childSessionId
        self.title = title
    }
}

public enum AgentRunControlAction: String, Codable, Sendable {
    case pause
    case resume
    case interrupt
    case interruptTree
}

public struct AgentRunControlEvent: Codable, Sendable, Equatable {
    public var action: AgentRunControlAction
    public var requestedBy: String
    public var reason: String?

    public init(action: AgentRunControlAction, requestedBy: String, reason: String? = nil) {
        self.action = action
        self.requestedBy = requestedBy
        self.reason = reason
    }
}

public struct AgentToolCallEvent: Codable, Sendable, Equatable {
    public var tool: String
    public var arguments: [String: JSONValue]
    public var reason: String?
    public var argumentDiagnostics: ToolInvocationArgumentDiagnostics?

    public init(
        tool: String,
        arguments: [String: JSONValue],
        reason: String? = nil,
        argumentDiagnostics: ToolInvocationArgumentDiagnostics? = nil
    ) {
        self.tool = tool
        self.arguments = arguments
        self.reason = reason
        self.argumentDiagnostics = argumentDiagnostics
    }
}

public struct AgentToolResultEvent: Codable, Sendable, Equatable {
    public var tool: String
    public var ok: Bool
    public var data: JSONValue?
    public var error: ToolErrorPayload?
    public var durationMs: Int?
    public var callEventId: String?
    public var executionOutcome: ExecutionOutcome?

    public init(
        tool: String,
        ok: Bool,
        data: JSONValue? = nil,
        error: ToolErrorPayload? = nil,
        durationMs: Int? = nil,
        callEventId: String? = nil,
        executionOutcome: ExecutionOutcome? = nil
    ) {
        self.tool = tool
        self.ok = ok
        self.data = data
        self.error = error
        self.durationMs = durationMs
        self.callEventId = callEventId
        self.executionOutcome = executionOutcome
    }
}

public struct AgentSelfImprovementReviewEvent: Codable, Sendable, Equatable {
    public var title: String
    public var category: String?
    public var jobId: String?
    public var summary: String
    public var actions: [String]
    public var reason: String
    public var createdAt: Date

    public init(
        title: String = "Self-improvement review",
        category: String? = nil,
        jobId: String? = nil,
        summary: String,
        actions: [String],
        reason: String,
        createdAt: Date = Date()
    ) {
        self.title = title
        self.category = category
        self.jobId = jobId
        self.summary = summary
        self.actions = actions
        self.reason = reason
        self.createdAt = createdAt
    }
}

public struct PlanInputOption: Codable, Sendable, Equatable {
    public var id: String
    public var label: String
    public var description: String?

    public init(id: String, label: String, description: String? = nil) {
        self.id = id
        self.label = label
        self.description = description
    }
}

public struct PlanInputQuestion: Codable, Sendable, Equatable {
    public var id: String
    public var header: String?
    public var question: String
    public var options: [PlanInputOption]
    public var allowCustomAnswer: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case header
        case question
        case options
        case allowCustomAnswer
    }

    public init(
        id: String,
        header: String? = nil,
        question: String,
        options: [PlanInputOption],
        allowCustomAnswer: Bool = true
    ) {
        self.id = id
        self.header = header
        self.question = question
        self.options = options
        self.allowCustomAnswer = allowCustomAnswer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        header = try container.decodeIfPresent(String.self, forKey: .header)
        question = try container.decode(String.self, forKey: .question)
        options = try container.decode([PlanInputOption].self, forKey: .options)
        allowCustomAnswer = try container.decodeIfPresent(Bool.self, forKey: .allowCustomAnswer) ?? true
    }
}

public struct PlanInputRequest: Codable, Sendable, Equatable {
    public var autoApproveAt: Date?
    public var id: String
    public var mode: String
    public var title: String?
    public var questions: [PlanInputQuestion]
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        mode: String = "plan",
        title: String? = nil,
        questions: [PlanInputQuestion],
        autoApproveAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.mode = mode
        self.title = title
        self.questions = questions
        self.autoApproveAt = autoApproveAt
        self.createdAt = createdAt
    }
}

public enum PlanInputResponseStatus: String, Codable, Sendable, Equatable {
    case answered
    case cancelled
}

public struct PlanInputAnswer: Codable, Sendable, Equatable {
    public var questionId: String
    public var selectedOptionId: String?
    public var customAnswer: String?

    public init(questionId: String, selectedOptionId: String? = nil, customAnswer: String? = nil) {
        self.questionId = questionId
        self.selectedOptionId = selectedOptionId
        self.customAnswer = customAnswer
    }
}

public struct PlanInputResponse: Codable, Sendable, Equatable {
    /// True when the timeout delegates the decision to the agent, without inventing a user answer.
    public var autoApproved: Bool?
    public var requestId: String
    public var status: PlanInputResponseStatus
    public var answers: [PlanInputAnswer]
    public var userId: String
    public var createdAt: Date

    public init(
        requestId: String,
        status: PlanInputResponseStatus,
        answers: [PlanInputAnswer],
        userId: String,
        autoApproved: Bool? = nil,
        createdAt: Date = Date()
    ) {
        self.requestId = requestId
        self.status = status
        self.answers = answers
        self.userId = userId
        self.autoApproved = autoApproved
        self.createdAt = createdAt
    }
}

public struct AgentSessionMetadataEvent: Codable, Sendable, Equatable {
    public var title: String
    public var parentSessionId: String?
    public var kind: AgentSessionKind
    public var projectId: String?
    public var taskId: String?
    public var workspaceId: String?
    /// True when Sloppy may derive the display title from session messages.
    public var titleIsAutomatic: Bool

    public init(
        title: String,
        parentSessionId: String? = nil,
        kind: AgentSessionKind = .chat,
        projectId: String? = nil,
        taskId: String? = nil,
        workspaceId: String? = nil,
        titleIsAutomatic: Bool = false
    ) {
        self.title = title
        self.parentSessionId = parentSessionId
        self.kind = kind
        self.projectId = projectId
        self.taskId = taskId
        self.workspaceId = workspaceId
        self.titleIsAutomatic = titleIsAutomatic
    }

    enum CodingKeys: String, CodingKey {
        case title
        case parentSessionId
        case kind
        case projectId
        case taskId
        case workspaceId
        case titleIsAutomatic
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        parentSessionId = try container.decodeIfPresent(String.self, forKey: .parentSessionId)
        kind = try container.decodeIfPresent(AgentSessionKind.self, forKey: .kind) ?? .chat
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId)
        taskId = try container.decodeIfPresent(String.self, forKey: .taskId)
        workspaceId = try container.decodeIfPresent(String.self, forKey: .workspaceId)
        titleIsAutomatic = try container.decodeIfPresent(Bool.self, forKey: .titleIsAutomatic) ?? false
    }
}

public struct AgentSessionEvent: Codable, Sendable, Equatable {
    /// Imported events are historical and must never become pending executable tool calls.
    public var importOrigin: AgentSessionImportOrigin? = nil
    public var id: String
    public var version: Int
    public var agentId: String
    public var sessionId: String
    public var type: AgentSessionEventType
    public var createdAt: Date
    public var metadata: AgentSessionMetadataEvent?
    public var message: AgentSessionMessage?
    public var runStatus: AgentRunStatusEvent?
    public var memoryCheckpoint: AgentMemoryCheckpointEvent?
    public var buildProgress: AgentBuildProgressEvent?
    public var planArtifact: AgentPlanArtifactEvent?
    public var subSession: AgentSubSessionEvent?
    public var longChatTask: LongChatTaskEvent?
    public var runControl: AgentRunControlEvent?
    public var toolCall: AgentToolCallEvent?
    public var toolResult: AgentToolResultEvent?
    public var inputRequest: PlanInputRequest?
    public var inputResponse: PlanInputResponse?
    public var selfImprovementReview: AgentSelfImprovementReviewEvent?

    public init(
        id: String = UUID().uuidString,
        version: Int = 1,
        agentId: String,
        sessionId: String,
        type: AgentSessionEventType,
        createdAt: Date = Date(),
        metadata: AgentSessionMetadataEvent? = nil,
        message: AgentSessionMessage? = nil,
        runStatus: AgentRunStatusEvent? = nil,
        memoryCheckpoint: AgentMemoryCheckpointEvent? = nil,
        buildProgress: AgentBuildProgressEvent? = nil,
        planArtifact: AgentPlanArtifactEvent? = nil,
        subSession: AgentSubSessionEvent? = nil,
        longChatTask: LongChatTaskEvent? = nil,
        runControl: AgentRunControlEvent? = nil,
        toolCall: AgentToolCallEvent? = nil,
        toolResult: AgentToolResultEvent? = nil,
        inputRequest: PlanInputRequest? = nil,
        inputResponse: PlanInputResponse? = nil,
        selfImprovementReview: AgentSelfImprovementReviewEvent? = nil
    ) {
        self.id = id
        self.version = version
        self.agentId = agentId
        self.sessionId = sessionId
        self.type = type
        self.createdAt = createdAt
        self.metadata = metadata
        self.message = message
        self.runStatus = runStatus
        self.memoryCheckpoint = memoryCheckpoint
        self.buildProgress = buildProgress
        self.planArtifact = planArtifact
        self.subSession = subSession
        self.longChatTask = longChatTask
        self.runControl = runControl
        self.toolCall = toolCall
        self.toolResult = toolResult
        self.inputRequest = inputRequest
        self.inputResponse = inputResponse
        self.selfImprovementReview = selfImprovementReview
    }
}

public struct PlanInputAnswerRequest: Codable, Sendable, Equatable {
    public var status: PlanInputResponseStatus
    public var answers: [PlanInputAnswer]
    public var userId: String

    public init(status: PlanInputResponseStatus = .answered, answers: [PlanInputAnswer], userId: String) {
        self.status = status
        self.answers = answers
        self.userId = userId
    }
}

/// Cursor is an exclusive JSONL byte boundary, stable when new events are appended.
public struct AgentSessionHistoryPage: Codable, Sendable, Equatable {
    public var nextBefore: String?
    public var hasMore: Bool

    public init(nextBefore: String?, hasMore: Bool) {
        self.nextBefore = nextBefore
        self.hasMore = hasMore
    }
}

public struct AgentSessionDetail: Codable, Sendable, Equatable {
    public var summary: AgentSessionSummary
    public var events: [AgentSessionEvent]

    public var historyPage: AgentSessionHistoryPage?
    /// Current control state may precede the requested history window.
    public var stateEvents: [AgentSessionEvent]?

    public init(
        summary: AgentSessionSummary, events: [AgentSessionEvent],
        historyPage: AgentSessionHistoryPage? = nil, stateEvents: [AgentSessionEvent]? = nil
    ) {
        self.summary = summary
        self.events = events
        self.historyPage = historyPage
        self.stateEvents = stateEvents
    }
}

public struct AgentAttachmentUpload: Codable, Sendable, Equatable {
    public var name: String
    public var mimeType: String
    public var sizeBytes: Int
    public var contentBase64: String?

    public init(
        name: String,
        mimeType: String,
        sizeBytes: Int,
        contentBase64: String? = nil
    ) {
        self.name = name
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.contentBase64 = contentBase64
    }
}

public enum ReasoningEffort: String, Codable, Sendable, Equatable, CaseIterable {
    case low
    case medium
    case high
}

public enum AgentChatMode: String, Codable, Sendable, Equatable, CaseIterable {
    case ask
    case build
    case plan
    case debug
    case auto

    public static let defaultMode: AgentChatMode = .auto
}

public struct AgentSessionPostMessageRequest: Codable, Sendable {
    public var userId: String
    public var content: String
    public var attachments: [AgentAttachmentUpload]
    public var spawnSubSession: Bool
    public var reasoningEffort: ReasoningEffort?
    /// When set and allowed for the agent, overrides catalog `selectedModel` for this turn only.
    public var selectedModel: String?
    public var mode: AgentChatMode?
    /// Correlates a persisted user message with its optimistic client submission.
    public var clientMessageId: String?
    public var sessionReferences: [AgentSessionReference]?

    public init(
        userId: String,
        content: String,
        attachments: [AgentAttachmentUpload] = [],
        spawnSubSession: Bool = false,
        reasoningEffort: ReasoningEffort? = nil,
        selectedModel: String? = nil,
        mode: AgentChatMode? = nil,
        clientMessageId: String? = nil,
        sessionReferences: [AgentSessionReference]? = nil
    ) {
        self.userId = userId
        self.content = content
        self.attachments = attachments
        self.spawnSubSession = spawnSubSession
        self.reasoningEffort = reasoningEffort
        self.selectedModel = selectedModel
        self.mode = mode
        self.clientMessageId = clientMessageId
        self.sessionReferences = sessionReferences
    }
}

public struct AgentSessionControlRequest: Codable, Sendable {
    public var action: AgentRunControlAction
    public var requestedBy: String
    public var reason: String?
    public var interruptPendingInput: Bool?

    public init(action: AgentRunControlAction, requestedBy: String, reason: String? = nil, interruptPendingInput: Bool? = nil) {
        self.action = action
        self.requestedBy = requestedBy
        self.reason = reason
        self.interruptPendingInput = interruptPendingInput
    }
}

public struct AgentSessionDirectoryRequest: Codable, Sendable {
    public var path: String

    public init(path: String) {
        self.path = path
    }
}

public struct AgentSessionDirectoryResponse: Codable, Sendable, Equatable {
    public var path: String
    public var workingDirectory: String?
    public var directories: [String]

    public init(path: String, workingDirectory: String? = nil, directories: [String]) {
        self.path = path
        self.workingDirectory = workingDirectory
        self.directories = directories
    }
}

public struct AgentSessionAppendEventsRequest: Codable, Sendable {
    public var events: [AgentSessionEvent]

    public init(events: [AgentSessionEvent]) {
        self.events = events
    }
}

public struct AgentSessionMessageResponse: Codable, Sendable {
    public var summary: AgentSessionSummary
    public var appendedEvents: [AgentSessionEvent]
    public var routeDecision: ChannelRouteDecision?

    public init(summary: AgentSessionSummary, appendedEvents: [AgentSessionEvent], routeDecision: ChannelRouteDecision?) {
        self.summary = summary
        self.appendedEvents = appendedEvents
        self.routeDecision = routeDecision
    }
}
