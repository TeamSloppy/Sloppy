import Foundation

public enum ProjectTaskKind: String, Codable, Sendable, Equatable {
    case planning
    case execution
    case bugfix
}

public enum TaskOriginType: String, Codable, Sendable, Equatable {
    case dashboard
    case channel
}

public enum ProjectTaskStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case pendingApproval = "pending_approval"
    case backlog
    case ready
    case inProgress = "in_progress"
    case waitingInput = "waiting_input"
    case done
    case blocked
    case needsReview = "needs_review"
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .done, .blocked, .cancelled:
            return true
        case .pendingApproval, .backlog, .ready, .inProgress, .waitingInput, .needsReview:
            return false
        }
    }
}

public enum ProjectTaskCompletionConfidence: String, Codable, Sendable, Equatable, CaseIterable {
    case done
    case blocked
    case waitingInput = "waiting_input"
    case unsure
}

public struct ProjectTaskRouteStep: Codable, Sendable, Equatable {
    public var actorId: String?
    public var agentId: String?
    public var reason: String
    public var createdAt: Date

    public init(
        actorId: String? = nil,
        agentId: String? = nil,
        reason: String,
        createdAt: Date = Date()
    ) {
        self.actorId = actorId
        self.agentId = agentId
        self.reason = reason
        self.createdAt = createdAt
    }
}

public struct ProjectTask: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var description: String
    public var priority: String
    public var status: String {
        didSet {
            if ProjectTaskKanbanColumn(status: oldValue) != ProjectTaskKanbanColumn(status: status) {
                kanbanColumnEnteredAt = Date()
            }
        }
    }
    /// The last transition into the current board column. Nil for legacy tasks with no recorded transition.
    public var kanbanColumnEnteredAt: Date?
    public var initiativeID: String?
    public var kind: ProjectTaskKind?
    public var loopModeOverride: ProjectLoopMode?
    public var originType: TaskOriginType?
    public var originChannelId: String?
    public var actorId: String?
    public var executionNodeId: String?
    public var teamId: String?
    public var stageAssignments: TaskStageAssignments?
    public var activeStage: TaskExecutionStage?
    public var claimedActorId: String?
    public var claimedAgentId: String?
    public var parentTaskId: String?
    public var createdBy: String?
    public var dependsOnTaskIds: [String]
    public var swarmId: String?
    public var swarmTaskId: String?
    public var swarmParentTaskId: String?
    public var swarmDependencyIds: [String]?
    public var swarmDepth: Int?
    public var swarmActorPath: [String]?
    public var worktreeBranch: String?
    public var sourceControlProviderId: String?
    /// When set and present in the agent's available models, overrides the agent default model for this task's worker run.
    public var selectedModel: String?
    public var externalMetadata: TaskExternalMetadata?
    public var attachments: [AgentAttachmentUpload]
    public var tags: [String]
    public var routeHistory: [ProjectTaskRouteStep]
    public var isArchived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case priority
        case status
        case kanbanColumnEnteredAt
        case initiativeID
        case kind
        case loopModeOverride
        case originType
        case originChannelId
        case actorId
        case executionNodeId
        case teamId
        case stageAssignments
        case activeStage
        case claimedActorId
        case claimedAgentId
        case parentTaskId
        case createdBy
        case dependsOnTaskIds
        case swarmId
        case swarmTaskId
        case swarmParentTaskId
        case swarmDependencyIds
        case swarmDepth
        case swarmActorPath
        case worktreeBranch
        case sourceControlProviderId
        case selectedModel
        case externalMetadata
        case attachments
        case tags
        case routeHistory
        case isArchived
        case createdAt
        case updatedAt
    }

    public init(
        id: String,
        title: String,
        description: String,
        priority: String,
        status: String,
        initiativeID: String? = nil,
        kind: ProjectTaskKind? = nil,
        loopModeOverride: ProjectLoopMode? = nil,
        originType: TaskOriginType? = nil,
        originChannelId: String? = nil,
        actorId: String? = nil,
        executionNodeId: String? = nil,
        teamId: String? = nil,
        stageAssignments: TaskStageAssignments? = nil,
        activeStage: TaskExecutionStage? = nil,
        claimedActorId: String? = nil,
        claimedAgentId: String? = nil,
        parentTaskId: String? = nil,
        createdBy: String? = nil,
        dependsOnTaskIds: [String] = [],
        swarmId: String? = nil,
        swarmTaskId: String? = nil,
        swarmParentTaskId: String? = nil,
        swarmDependencyIds: [String]? = nil,
        swarmDepth: Int? = nil,
        swarmActorPath: [String]? = nil,
        worktreeBranch: String? = nil,
        sourceControlProviderId: String? = nil,
        selectedModel: String? = nil,
        externalMetadata: TaskExternalMetadata? = nil,
        attachments: [AgentAttachmentUpload] = [],
        tags: [String] = [],
        routeHistory: [ProjectTaskRouteStep] = [],
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        kanbanColumnEnteredAt: Date? = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.priority = priority
        self.status = status
        self.initiativeID = initiativeID
        self.kind = kind
        self.loopModeOverride = loopModeOverride
        self.originType = originType
        self.originChannelId = originChannelId
        self.actorId = actorId
        self.executionNodeId = executionNodeId
        self.teamId = teamId
        self.stageAssignments = stageAssignments
        self.activeStage = activeStage
        self.claimedActorId = claimedActorId
        self.claimedAgentId = claimedAgentId
        self.parentTaskId = parentTaskId
        self.createdBy = createdBy
        self.dependsOnTaskIds = dependsOnTaskIds
        self.swarmId = swarmId
        self.swarmTaskId = swarmTaskId
        self.swarmParentTaskId = swarmParentTaskId
        self.swarmDependencyIds = swarmDependencyIds
        self.swarmDepth = swarmDepth
        self.swarmActorPath = swarmActorPath
        self.worktreeBranch = worktreeBranch
        self.sourceControlProviderId = sourceControlProviderId
        self.selectedModel = selectedModel
        self.externalMetadata = externalMetadata
        self.attachments = attachments
        self.tags = tags
        self.routeHistory = routeHistory
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.kanbanColumnEnteredAt = kanbanColumnEnteredAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        priority = try container.decode(String.self, forKey: .priority)
        status = try container.decode(String.self, forKey: .status)
        kanbanColumnEnteredAt = try container.decodeIfPresent(Date.self, forKey: .kanbanColumnEnteredAt)
        initiativeID = try container.decodeIfPresent(String.self, forKey: .initiativeID)
        kind = try container.decodeIfPresent(ProjectTaskKind.self, forKey: .kind)
        loopModeOverride = try container.decodeIfPresent(ProjectLoopMode.self, forKey: .loopModeOverride)
        originType = try container.decodeIfPresent(TaskOriginType.self, forKey: .originType)
        originChannelId = try container.decodeIfPresent(String.self, forKey: .originChannelId)
        actorId = try container.decodeIfPresent(String.self, forKey: .actorId)
        executionNodeId = try container.decodeIfPresent(String.self, forKey: .executionNodeId)
        teamId = try container.decodeIfPresent(String.self, forKey: .teamId)
        stageAssignments = try container.decodeIfPresent(TaskStageAssignments.self, forKey: .stageAssignments)
        activeStage = try container.decodeIfPresent(TaskExecutionStage.self, forKey: .activeStage)
        claimedActorId = try container.decodeIfPresent(String.self, forKey: .claimedActorId)
        claimedAgentId = try container.decodeIfPresent(String.self, forKey: .claimedAgentId)
        parentTaskId = try container.decodeIfPresent(String.self, forKey: .parentTaskId)
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        dependsOnTaskIds = try container.decodeIfPresent([String].self, forKey: .dependsOnTaskIds) ?? []
        swarmId = try container.decodeIfPresent(String.self, forKey: .swarmId)
        swarmTaskId = try container.decodeIfPresent(String.self, forKey: .swarmTaskId)
        swarmParentTaskId = try container.decodeIfPresent(String.self, forKey: .swarmParentTaskId)
        swarmDependencyIds = try container.decodeIfPresent([String].self, forKey: .swarmDependencyIds)
        swarmDepth = try container.decodeIfPresent(Int.self, forKey: .swarmDepth)
        swarmActorPath = try container.decodeIfPresent([String].self, forKey: .swarmActorPath)
        worktreeBranch = try container.decodeIfPresent(String.self, forKey: .worktreeBranch)
        sourceControlProviderId = try container.decodeIfPresent(String.self, forKey: .sourceControlProviderId)
        selectedModel = try container.decodeIfPresent(String.self, forKey: .selectedModel)
        externalMetadata = try container.decodeIfPresent(TaskExternalMetadata.self, forKey: .externalMetadata)
        attachments = try container.decodeIfPresent([AgentAttachmentUpload].self, forKey: .attachments) ?? []
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        routeHistory = try container.decodeIfPresent([ProjectTaskRouteStep].self, forKey: .routeHistory) ?? []
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

public extension ProjectTask {
    var statusValue: ProjectTaskStatus? {
        ProjectTaskStatus(rawValue: status)
    }
}

public struct KanbanEvent: Codable, Sendable {
    public enum EventType: String, Codable, Sendable {
        case taskCreated = "task_created"
        case taskUpdated = "task_updated"
        case taskDeleted = "task_deleted"
        case projectUpdated = "project_updated"
    }

    public var type: EventType
    public var projectId: String
    public var task: ProjectTask?
    public var taskId: String?

    public init(type: EventType, projectId: String, task: ProjectTask? = nil, taskId: String? = nil) {
        self.type = type
        self.projectId = projectId
        self.task = task
        self.taskId = taskId
    }
}

public struct ProjectTaskCountSummary: Codable, Sendable, Equatable {
    public var total: Int
    public var backlog: Int
    public var ready: Int
    public var inProgress: Int
    public var waitingInput: Int
    public var blocked: Int
    public var needsReview: Int
    public var done: Int

    public init(
        total: Int = 0,
        backlog: Int = 0,
        ready: Int = 0,
        inProgress: Int = 0,
        waitingInput: Int = 0,
        blocked: Int = 0,
        needsReview: Int = 0,
        done: Int = 0
    ) {
        self.total = total
        self.backlog = backlog
        self.ready = ready
        self.inProgress = inProgress
        self.waitingInput = waitingInput
        self.blocked = blocked
        self.needsReview = needsReview
        self.done = done
    }
}

public struct ProjectTaskCreateRequest: Codable, Sendable {
    public var title: String
    public var description: String?
    public var priority: String
    public var status: String?
    public var initiativeID: String?
    public var kind: ProjectTaskKind?
    public var loopModeOverride: ProjectLoopMode?
    public var originType: TaskOriginType?
    public var originChannelId: String?
    public var actorId: String?
    public var executionNodeId: String?
    public var teamId: String?
    public var stageAssignments: TaskStageAssignments?
    public var parentTaskId: String?
    public var dependsOnTaskIds: [String]?
    public var selectedModel: String?
    public var tags: [String]?
    public var attachments: [AgentAttachmentUpload]?
    public var changedBy: String?

    public init(
        title: String,
        description: String? = nil,
        priority: String = "medium",
        status: String? = nil,
        initiativeID: String? = nil,
        kind: ProjectTaskKind? = nil,
        loopModeOverride: ProjectLoopMode? = nil,
        originType: TaskOriginType? = nil,
        originChannelId: String? = nil,
        actorId: String? = nil,
        executionNodeId: String? = nil,
        teamId: String? = nil,
        stageAssignments: TaskStageAssignments? = nil,
        parentTaskId: String? = nil,
        dependsOnTaskIds: [String]? = nil,
        selectedModel: String? = nil,
        tags: [String]? = nil,
        attachments: [AgentAttachmentUpload]? = nil,
        changedBy: String? = nil
    ) {
        self.title = title
        self.description = description
        self.priority = priority
        self.status = status
        self.initiativeID = initiativeID
        self.kind = kind
        self.loopModeOverride = loopModeOverride
        self.originType = originType
        self.originChannelId = originChannelId
        self.actorId = actorId
        self.executionNodeId = executionNodeId
        self.teamId = teamId
        self.stageAssignments = stageAssignments
        self.parentTaskId = parentTaskId
        self.dependsOnTaskIds = dependsOnTaskIds
        self.selectedModel = selectedModel
        self.tags = tags
        self.attachments = attachments
        self.changedBy = changedBy
    }
}

public struct ProjectTaskUpdateRequest: Codable, Sendable {
    public var title: String?
    public var description: String?
    public var priority: String?
    public var status: String?
    public var initiativeID: String?
    public var completionConfidence: ProjectTaskCompletionConfidence?
    public var completionNote: String?
    public var kind: ProjectTaskKind?
    public var loopModeOverride: ProjectLoopMode?
    public var actorId: String?
    public var executionNodeId: String?
    public var teamId: String?
    public var stageAssignments: TaskStageAssignments?
    public var parentTaskId: String?
    public var dependsOnTaskIds: [String]?
    public var selectedModel: String?
    public var tags: [String]?
    public var attachments: [AgentAttachmentUpload]?
    public var isArchived: Bool?
    public var changedBy: String?

    public init(
        title: String? = nil,
        description: String? = nil,
        priority: String? = nil,
        status: String? = nil,
        initiativeID: String? = nil,
        completionConfidence: ProjectTaskCompletionConfidence? = nil,
        completionNote: String? = nil,
        kind: ProjectTaskKind? = nil,
        loopModeOverride: ProjectLoopMode? = nil,
        actorId: String? = nil,
        executionNodeId: String? = nil,
        teamId: String? = nil,
        stageAssignments: TaskStageAssignments? = nil,
        parentTaskId: String? = nil,
        dependsOnTaskIds: [String]? = nil,
        selectedModel: String? = nil,
        tags: [String]? = nil,
        attachments: [AgentAttachmentUpload]? = nil,
        isArchived: Bool? = nil,
        changedBy: String? = nil
    ) {
        self.title = title
        self.description = description
        self.priority = priority
        self.status = status
        self.initiativeID = initiativeID
        self.completionConfidence = completionConfidence
        self.completionNote = completionNote
        self.kind = kind
        self.loopModeOverride = loopModeOverride
        self.actorId = actorId
        self.executionNodeId = executionNodeId
        self.teamId = teamId
        self.stageAssignments = stageAssignments
        self.parentTaskId = parentTaskId
        self.dependsOnTaskIds = dependsOnTaskIds
        self.selectedModel = selectedModel
        self.tags = tags
        self.attachments = attachments
        self.isArchived = isArchived
        self.changedBy = changedBy
    }
}

public struct TaskRejectRequest: Codable, Sendable {
    public var reason: String?

    public init(reason: String? = nil) {
        self.reason = reason
    }
}

/// Responsibilities belong to a team membership, independently of the agent profile.
public enum TaskExecutionStage: String, Codable, Sendable {
    case development
    case review
    case qa
}

public struct TaskStageAssignments: Codable, Sendable, Equatable {
    public var developer: String?
    public var reviewer: String?
    public var qa: String?

    public init(developer: String? = nil, reviewer: String? = nil, qa: String? = nil) {
        self.developer = developer
        self.reviewer = reviewer
        self.qa = qa
    }
}

public struct ReviewComment: Codable, Sendable, Identifiable {
    public var id: String
    public var taskId: String
    public var filePath: String
    public var lineNumber: Int?
    public var side: String?
    public var content: String
    public var author: String
    public var resolved: Bool
    public var createdAt: Date

    public init(
        id: String,
        taskId: String,
        filePath: String,
        lineNumber: Int? = nil,
        side: String? = nil,
        content: String,
        author: String,
        resolved: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.side = side
        self.content = content
        self.author = author
        self.resolved = resolved
        self.createdAt = createdAt
    }
}

public struct ReviewCommentCreateRequest: Codable, Sendable {
    public var filePath: String
    public var lineNumber: Int?
    public var side: String?
    public var content: String
    public var author: String

    public init(filePath: String, lineNumber: Int? = nil, side: String? = nil, content: String, author: String) {
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.side = side
        self.content = content
        self.author = author
    }
}

public struct ReviewCommentUpdateRequest: Codable, Sendable {
    public var resolved: Bool?
    public var content: String?

    public init(resolved: Bool? = nil, content: String? = nil) {
        self.resolved = resolved
        self.content = content
    }
}

public enum TaskCommentKind: String, Codable, Sendable {
    case userComment = "user_comment"
    case technical
    case result
    case actionRequired = "action_required"
}

public struct TaskComment: Codable, Sendable, Identifiable {
    public var id: String
    public var taskId: String
    public var content: String
    public var authorActorId: String
    public var mentionedActorId: String?
    public var isAgentReply: Bool
    public var externalMetadata: TaskExternalMetadata?
    public var sourceAuthor: String?
    public var createdAt: Date
    /// Optional for compatibility with comments saved before semantic kinds were introduced.
    public var kind: TaskCommentKind?

    public var effectiveKind: TaskCommentKind {
        kind ?? (authorActorId == "system" ? .technical : .userComment)
    }

    public init(
        id: String,
        taskId: String,
        content: String,
        authorActorId: String,
        mentionedActorId: String? = nil,
        isAgentReply: Bool = false,
        externalMetadata: TaskExternalMetadata? = nil,
        sourceAuthor: String? = nil,
        createdAt: Date = Date(),
        kind: TaskCommentKind? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.content = content
        self.authorActorId = authorActorId
        self.mentionedActorId = mentionedActorId
        self.isAgentReply = isAgentReply
        self.externalMetadata = externalMetadata
        self.sourceAuthor = sourceAuthor
        self.createdAt = createdAt
        self.kind = kind
    }
}

public struct TaskCommentCreateRequest: Codable, Sendable {
    public var content: String
    public var authorActorId: String
    public var mentionedActorId: String?
    public var kind: TaskCommentKind?

    public init(content: String, authorActorId: String, mentionedActorId: String? = nil, kind: TaskCommentKind? = nil) {
        self.content = content
        self.authorActorId = authorActorId
        self.mentionedActorId = mentionedActorId
        self.kind = kind
    }
}

public enum TaskActivityField: String, Codable, Sendable {
    case status
    case priority
    case assignee
    case title
    case description
    case selectedModel
}

public struct TaskActivity: Codable, Sendable, Identifiable {
    public var id: String
    public var taskId: String
    public var field: TaskActivityField
    public var oldValue: String?
    public var newValue: String?
    public var actorId: String
    public var createdAt: Date

    public init(
        id: String,
        taskId: String,
        field: TaskActivityField,
        oldValue: String? = nil,
        newValue: String? = nil,
        actorId: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.field = field
        self.oldValue = oldValue
        self.newValue = newValue
        self.actorId = actorId
        self.createdAt = createdAt
    }
}

public struct TaskLogEntry: Codable, Sendable, Identifiable {
    public var id: String
    public var taskId: String
    public var kind: String
    public var title: String
    public var message: String?
    public var field: String?
    public var oldValue: String?
    public var newValue: String?
    public var actorId: String?
    public var agentId: String?
    public var channelId: String?
    public var workerId: String?
    public var tool: String?
    public var ok: Bool?
    public var durationMs: Int?
    public var createdAt: Date

    public init(
        id: String,
        taskId: String,
        kind: String,
        title: String,
        message: String? = nil,
        field: String? = nil,
        oldValue: String? = nil,
        newValue: String? = nil,
        actorId: String? = nil,
        agentId: String? = nil,
        channelId: String? = nil,
        workerId: String? = nil,
        tool: String? = nil,
        ok: Bool? = nil,
        durationMs: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.kind = kind
        self.title = title
        self.message = message
        self.field = field
        self.oldValue = oldValue
        self.newValue = newValue
        self.actorId = actorId
        self.agentId = agentId
        self.channelId = channelId
        self.workerId = workerId
        self.tool = tool
        self.ok = ok
        self.durationMs = durationMs
        self.createdAt = createdAt
    }
}

public enum ProjectTaskRunOutcome: String, Codable, Sendable, Equatable {
    case running
    case completed
    case needsReview = "needs_review"
    case blocked
    case waitingInput = "waiting_input"
    case failed
    case reclaimed
}

public struct ProjectTaskRun: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var projectId: String
    public var taskId: String
    public var actorId: String?
    public var agentId: String?
    public var workerId: String?
    public var channelId: String?
    public var outcome: ProjectTaskRunOutcome
    public var summary: String?
    public var metadata: [String: String]
    public var failureReason: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        projectId: String,
        taskId: String,
        actorId: String? = nil,
        agentId: String? = nil,
        workerId: String? = nil,
        channelId: String? = nil,
        outcome: ProjectTaskRunOutcome = .running,
        summary: String? = nil,
        metadata: [String: String] = [:],
        failureReason: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.taskId = taskId
        self.actorId = actorId
        self.agentId = agentId
        self.workerId = workerId
        self.channelId = channelId
        self.outcome = outcome
        self.summary = summary
        self.metadata = metadata
        self.failureReason = failureReason
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum ProjectTaskWorkerHeartbeatStatus: String, Codable, Sendable, Equatable {
    case running
    case waitingInput = "waiting_input"
    case finishing
    case blocked
}

public struct ProjectTaskWorkerHeartbeat: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var projectId: String
    public var taskId: String
    public var workerId: String?
    public var agentId: String?
    public var status: ProjectTaskWorkerHeartbeatStatus
    public var message: String?
    public var metadata: [String: String]
    public var updatedAt: Date
    public var createdAt: Date

    public init(
        id: String,
        projectId: String,
        taskId: String,
        workerId: String? = nil,
        agentId: String? = nil,
        status: ProjectTaskWorkerHeartbeatStatus,
        message: String? = nil,
        metadata: [String: String] = [:],
        updatedAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.taskId = taskId
        self.workerId = workerId
        self.agentId = agentId
        self.status = status
        self.message = message
        self.metadata = metadata
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }
}

public enum ClarificationStatus: String, Codable, Sendable, Equatable {
    case pending
    case answered
    case cancelled
}

public enum ClarificationTargetType: String, Codable, Sendable, Equatable {
    case human
    case actor
    case channel
}

public struct ClarificationOption: Codable, Sendable, Equatable {
    public var id: String
    public var label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

public struct TaskClarificationRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var projectId: String
    public var taskId: String
    public var status: ClarificationStatus
    public var targetType: ClarificationTargetType
    public var targetActorId: String?
    public var targetChannelId: String?
    public var questionText: String
    public var options: [ClarificationOption]
    public var allowNote: Bool
    public var createdByAgentId: String?
    public var selectedOptionIds: [String]
    public var note: String?
    public var createdAt: Date
    public var answeredAt: Date?

    public init(
        id: String,
        projectId: String,
        taskId: String,
        status: ClarificationStatus = .pending,
        targetType: ClarificationTargetType,
        targetActorId: String? = nil,
        targetChannelId: String? = nil,
        questionText: String,
        options: [ClarificationOption] = [],
        allowNote: Bool = true,
        createdByAgentId: String? = nil,
        selectedOptionIds: [String] = [],
        note: String? = nil,
        createdAt: Date = Date(),
        answeredAt: Date? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.taskId = taskId
        self.status = status
        self.targetType = targetType
        self.targetActorId = targetActorId
        self.targetChannelId = targetChannelId
        self.questionText = questionText
        self.options = options
        self.allowNote = allowNote
        self.createdByAgentId = createdByAgentId
        self.selectedOptionIds = selectedOptionIds
        self.note = note
        self.createdAt = createdAt
        self.answeredAt = answeredAt
    }
}

public struct TaskClarificationCreateRequest: Codable, Sendable {
    public var questionText: String
    public var options: [ClarificationOption]
    public var allowNote: Bool?
    public var createdByAgentId: String?

    public init(
        questionText: String,
        options: [ClarificationOption] = [],
        allowNote: Bool? = nil,
        createdByAgentId: String? = nil
    ) {
        self.questionText = questionText
        self.options = options
        self.allowNote = allowNote
        self.createdByAgentId = createdByAgentId
    }
}

public struct TaskClarificationAnswerRequest: Codable, Sendable {
    public var selectedOptionIds: [String]
    public var note: String?

    public init(selectedOptionIds: [String] = [], note: String? = nil) {
        self.selectedOptionIds = selectedOptionIds
        self.note = note
    }
}
