import Foundation

public enum WorkflowNodeType: String, Codable, Sendable, CaseIterable {
    case trigger
    case projectTask = "project_task"
    case agentStep = "agent_step"
    case humanApproval = "human_approval"
    case humanInput = "human_input"
    case toolCheck = "tool_check"
    case condition
    case parallel
    case join
    case updateTask = "update_task"
    case notify
    case end
}

public enum WorkflowLaneKind: String, Codable, Sendable, CaseIterable {
    case system
    case human
    case agent
    case team
}

public enum WorkflowRunStatus: String, Codable, Sendable, CaseIterable {
    case queued
    case running
    case waitingForHuman = "waiting_for_human"
    case waitingForAgent = "waiting_for_agent"
    case waitingForWorkflow = "waiting_for_workflow"
    case blocked
    case failed
    case completed
    case cancelled
}

public enum WorkflowStepStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case running
    case waiting
    case succeeded
    case failed
    case skipped
}

public enum WorkflowHumanDecision: String, Codable, Sendable, CaseIterable {
    case approved
    case rejected
    case changesRequested = "changes_requested"
}

public struct WorkflowLane: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var kind: WorkflowLaneKind
    public var actorId: String?
    public var teamId: String?

    public init(id: String, title: String, kind: WorkflowLaneKind, actorId: String? = nil, teamId: String? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.actorId = actorId
        self.teamId = teamId
    }
}

public struct WorkflowNode: Codable, Sendable, Equatable {
    public var id: String
    public var type: WorkflowNodeType
    public var title: String
    public var laneId: String
    public var config: [String: JSONValue]
    public var positionX: Double
    public var positionY: Double

    public init(
        id: String,
        type: WorkflowNodeType,
        title: String,
        laneId: String,
        config: [String: JSONValue] = [:],
        positionX: Double = 0,
        positionY: Double = 0
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.laneId = laneId
        self.config = config
        self.positionX = positionX
        self.positionY = positionY
    }
}

public struct WorkflowEdgeCondition: Codable, Sendable, Equatable {
    public var path: String
    public var equals: JSONValue

    public init(path: String, equals: JSONValue) {
        self.path = path
        self.equals = equals
    }
}

public struct WorkflowEdge: Codable, Sendable, Equatable {
    public var id: String
    public var sourceNodeId: String
    public var targetNodeId: String
    public var conditionKey: String?
    public var condition: WorkflowEdgeCondition?
    public var sourceSocket: String?
    public var targetSocket: String?

    public init(
        id: String,
        sourceNodeId: String,
        targetNodeId: String,
        conditionKey: String? = nil,
        condition: WorkflowEdgeCondition? = nil,
        sourceSocket: String? = nil,
        targetSocket: String? = nil
    ) {
        self.id = id
        self.sourceNodeId = sourceNodeId
        self.targetNodeId = targetNodeId
        self.conditionKey = conditionKey
        self.condition = condition
        self.sourceSocket = sourceSocket
        self.targetSocket = targetSocket
    }
}

public struct WorkflowDefinition: Codable, Sendable, Equatable {
    public var id: String
    public var projectId: String
    public var name: String
    public var version: Int
    public var lanes: [WorkflowLane]
    public var nodes: [WorkflowNode]
    public var edges: [WorkflowEdge]
    public var enabled: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        projectId: String,
        name: String,
        version: Int = 1,
        lanes: [WorkflowLane] = [],
        nodes: [WorkflowNode] = [],
        edges: [WorkflowEdge] = [],
        enabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.version = version
        self.lanes = lanes
        self.nodes = nodes
        self.edges = edges
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct WorkflowDefinitionUpsertRequest: Codable, Sendable, Equatable {
    public var name: String
    public var lanes: [WorkflowLane]
    public var nodes: [WorkflowNode]
    public var edges: [WorkflowEdge]
    public var enabled: Bool

    public init(name: String, lanes: [WorkflowLane], nodes: [WorkflowNode], edges: [WorkflowEdge], enabled: Bool = true) {
        self.name = name
        self.lanes = lanes
        self.nodes = nodes
        self.edges = edges
        self.enabled = enabled
    }
}

public struct WorkflowRunCreateRequest: Codable, Sendable, Equatable {
    public var idempotencyKey: String?
    public var environment: WorkflowEnvironmentRequest?
    public var background: Bool?
    public var taskId: String?
    public var startedBy: String
    public var input: [String: JSONValue]

    public init(taskId: String? = nil, startedBy: String, input: [String: JSONValue] = [:], background: Bool? = nil, environment: WorkflowEnvironmentRequest? = nil, idempotencyKey: String? = nil) {
        self.idempotencyKey = idempotencyKey
        self.environment = environment
        self.background = background
        self.taskId = taskId
        self.startedBy = startedBy
        self.input = input
    }
}

public struct WorkflowRun: Codable, Sendable, Equatable {
    public var id: String
    public var workflowId: String
    public var workflowVersion: Int
    public var projectId: String
    public var environment: WorkflowEnvironmentBinding?
    public var taskId: String?
    public var status: WorkflowRunStatus
    public var currentNodeIds: [String]
    public var startedBy: String
    public var startedAt: Date
    public var finishedAt: Date?

    public init(
        id: String,
        workflowId: String,
        workflowVersion: Int,
        projectId: String,
        taskId: String? = nil,
        status: WorkflowRunStatus,
        currentNodeIds: [String] = [],
        startedBy: String,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        environment: WorkflowEnvironmentBinding? = nil
    ) {
        self.environment = environment
        self.id = id
        self.workflowId = workflowId
        self.workflowVersion = workflowVersion
        self.projectId = projectId
        self.taskId = taskId
        self.status = status
        self.currentNodeIds = currentNodeIds
        self.startedBy = startedBy
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

public struct WorkflowRunStep: Codable, Sendable, Equatable {
    public var id: String
    public var runId: String
    public var nodeId: String
    public var status: WorkflowStepStatus
    public var input: [String: JSONValue]
    public var output: [String: JSONValue]
    public var error: String?
    public var startedAt: Date
    public var finishedAt: Date?

    public init(
        id: String,
        runId: String,
        nodeId: String,
        status: WorkflowStepStatus,
        input: [String: JSONValue] = [:],
        output: [String: JSONValue] = [:],
        error: String? = nil,
        startedAt: Date = Date(),
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.runId = runId
        self.nodeId = nodeId
        self.status = status
        self.input = input
        self.output = output
        self.error = error
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

public struct WorkflowPendingAction: Codable, Sendable, Equatable {
    public var id: String
    public var projectId: String
    public var workflowRunId: String
    public var nodeId: String
    public var taskId: String?
    public var assignee: String
    public var prompt: String
    public var decisions: [WorkflowHumanDecision]
    public var createdAt: Date
    public var resolvedAt: Date?

    public init(
        id: String,
        projectId: String,
        workflowRunId: String,
        nodeId: String,
        taskId: String? = nil,
        assignee: String,
        prompt: String,
        decisions: [WorkflowHumanDecision],
        createdAt: Date = Date(),
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.workflowRunId = workflowRunId
        self.nodeId = nodeId
        self.taskId = taskId
        self.assignee = assignee
        self.prompt = prompt
        self.decisions = decisions
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }
}

public struct WorkflowActionResolveRequest: Codable, Sendable, Equatable {
    public var background: Bool?
    public var decision: WorkflowHumanDecision
    public var comment: String?
    public var resolvedBy: String

    public init(decision: WorkflowHumanDecision, comment: String? = nil, resolvedBy: String, background: Bool? = nil) {
        self.background = background
        self.decision = decision
        self.comment = comment
        self.resolvedBy = resolvedBy
    }
}

public struct WorkflowRunDetail: Codable, Sendable, Equatable {
    public var run: WorkflowRun
    public var steps: [WorkflowRunStep]
    public var reconciliations: [WorkflowReconciliation]?
    public var pendingActions: [WorkflowPendingAction]

    public init(run: WorkflowRun, steps: [WorkflowRunStep] = [], pendingActions: [WorkflowPendingAction] = [], reconciliations: [WorkflowReconciliation]? = nil) {
        self.reconciliations = reconciliations
        self.run = run
        self.steps = steps
        self.pendingActions = pendingActions
    }
}

public struct WorkflowValidationIssue: Codable, Sendable, Equatable {
    public var severity: String
    public var message: String
    public var nodeId: String?

    public init(severity: String, message: String, nodeId: String? = nil) {
        self.severity = severity
        self.message = message
        self.nodeId = nodeId
    }
}

public enum AutomationTriggerKind: String, Codable, Sendable, CaseIterable {
    case manual
    case cron
    case webhook
    case githubPullRequest = "github_pull_request"
    case githubPullRequestReview = "github_pull_request_review"
}

public enum AutomationTaskMode: String, Codable, Sendable, CaseIterable {
    case none
    case createTask = "create_task"
    case attachToExistingIfMatch = "attach_to_existing_if_match"
    case createOrAttach = "create_or_attach"
}

public enum AutomationRunStatus: String, Codable, Sendable, CaseIterable {
    case queued
    case running
    case waitingForWorkflow = "waiting_for_workflow"
    case completed
    case failed
    case cancelled
    case ignored
}

public enum AutomationPermissionsScope: String, Codable, Sendable, CaseIterable {
    case `private`
    case projectVisible = "project_visible"
    case projectManaged = "project_managed"
}

public struct AutomationTrigger: Codable, Sendable, Equatable {
    public var type: AutomationTriggerKind
    public var config: [String: JSONValue]

    public init(type: AutomationTriggerKind, config: [String: JSONValue] = [:]) {
        self.type = type
        self.config = config
    }
}

public struct AutomationDefinition: Codable, Sendable, Equatable {
    public var id: String
    public var projectId: String
    public var name: String
    public var description: String?
    public var version: Int
    public var enabled: Bool
    public var workflowId: String
    public var repositoryFullName: String
    public var trigger: AutomationTrigger
    public var taskMode: AutomationTaskMode
    public var model: String?
    public var permissionsScope: AutomationPermissionsScope
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        projectId: String,
        name: String,
        description: String? = nil,
        version: Int = 1,
        enabled: Bool = true,
        workflowId: String,
        repositoryFullName: String,
        trigger: AutomationTrigger,
        taskMode: AutomationTaskMode = .none,
        model: String? = nil,
        permissionsScope: AutomationPermissionsScope = .private,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.description = description
        self.version = version
        self.enabled = enabled
        self.workflowId = workflowId
        self.repositoryFullName = repositoryFullName
        self.trigger = trigger
        self.taskMode = taskMode
        self.model = model
        self.permissionsScope = permissionsScope
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct AutomationDefinitionUpsertRequest: Codable, Sendable, Equatable {
    public var name: String
    public var description: String?
    public var enabled: Bool
    public var workflowId: String
    public var repositoryFullName: String
    public var trigger: AutomationTrigger
    public var taskMode: AutomationTaskMode
    public var model: String?
    public var permissionsScope: AutomationPermissionsScope

    public init(
        name: String,
        description: String? = nil,
        enabled: Bool = true,
        workflowId: String,
        repositoryFullName: String,
        trigger: AutomationTrigger,
        taskMode: AutomationTaskMode = .none,
        model: String? = nil,
        permissionsScope: AutomationPermissionsScope = .private
    ) {
        self.name = name
        self.description = description
        self.enabled = enabled
        self.workflowId = workflowId
        self.repositoryFullName = repositoryFullName
        self.trigger = trigger
        self.taskMode = taskMode
        self.model = model
        self.permissionsScope = permissionsScope
    }
}

public struct AutomationRun: Codable, Sendable, Equatable {
    public var id: String
    public var automationId: String
    public var projectId: String
    public var workflowId: String
    public var workflowRunId: String?
    public var repositoryFullName: String
    public var triggerType: AutomationTriggerKind
    public var triggerEventId: String?
    public var status: AutomationRunStatus
    public var taskId: String?
    public var summary: String?
    public var startedAt: Date
    public var finishedAt: Date?

    public init(
        id: String,
        automationId: String,
        projectId: String,
        workflowId: String,
        workflowRunId: String? = nil,
        repositoryFullName: String,
        triggerType: AutomationTriggerKind,
        triggerEventId: String? = nil,
        status: AutomationRunStatus,
        taskId: String? = nil,
        summary: String? = nil,
        startedAt: Date = Date(),
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.automationId = automationId
        self.projectId = projectId
        self.workflowId = workflowId
        self.workflowRunId = workflowRunId
        self.repositoryFullName = repositoryFullName
        self.triggerType = triggerType
        self.triggerEventId = triggerEventId
        self.status = status
        self.taskId = taskId
        self.summary = summary
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

public struct AutomationRunDetail: Codable, Sendable, Equatable {
    public var run: AutomationRun
    public var workflowRun: WorkflowRunDetail?

    public init(run: AutomationRun, workflowRun: WorkflowRunDetail? = nil) {
        self.run = run
        self.workflowRun = workflowRun
    }
}

public struct AutomationManualRunRequest: Codable, Sendable, Equatable {
    public var actorId: String
    public var input: [String: JSONValue]

    public init(actorId: String, input: [String: JSONValue] = [:]) {
        self.actorId = actorId
        self.input = input
    }
}

public struct AutomationTriggerPayload: Codable, Sendable, Equatable {
    public var source: AutomationTriggerKind
    public var startedBy: String
    public var triggerEventId: String?
    public var data: [String: JSONValue]
    public var workflowInput: [String: JSONValue]

    public init(
        source: AutomationTriggerKind,
        startedBy: String,
        triggerEventId: String? = nil,
        data: [String: JSONValue] = [:],
        workflowInput: [String: JSONValue] = [:]
    ) {
        self.source = source
        self.startedBy = startedBy
        self.triggerEventId = triggerEventId
        self.data = data
        self.workflowInput = workflowInput
    }
}

public struct GitHubAutomationEventRequest: Codable, Sendable, Equatable {
    public var deliveryId: String
    public var event: String
    public var action: String
    public var repositoryFullName: String
    public var payload: [String: JSONValue]

    public init(
        deliveryId: String,
        event: String,
        action: String,
        repositoryFullName: String,
        payload: [String: JSONValue] = [:]
    ) {
        self.deliveryId = deliveryId
        self.event = event
        self.action = action
        self.repositoryFullName = repositoryFullName
        self.payload = payload
    }
}
