import Foundation

public enum ProjectAutomationTriggerKind: String, Codable, Sendable, CaseIterable {
    case manual
    case cron
    case webhook
    case githubPullRequest = "github_pull_request"
    case githubPullRequestReview = "github_pull_request_review"

    public var title: String {
        switch self {
        case .manual: "Manual"
        case .cron: "Schedule"
        case .webhook: "Webhook"
        case .githubPullRequest: "GitHub pull request"
        case .githubPullRequestReview: "GitHub review"
        }
    }
}

public enum ProjectAutomationTaskMode: String, Codable, Sendable, CaseIterable {
    case none
    case createTask = "create_task"
    case attachToExistingIfMatch = "attach_to_existing_if_match"
    case createOrAttach = "create_or_attach"

    public var title: String {
        switch self {
        case .none: "Do not create tasks"
        case .createTask: "Create a task"
        case .attachToExistingIfMatch: "Attach to a matching task"
        case .createOrAttach: "Create or attach"
        }
    }
}

public enum ProjectAutomationPermissionsScope: String, Codable, Sendable, CaseIterable {
    case `private`
    case projectVisible = "project_visible"
    case projectManaged = "project_managed"

    public var title: String {
        switch self {
        case .private: "Private"
        case .projectVisible: "Project visible"
        case .projectManaged: "Project managed"
        }
    }
}

public enum ProjectAutomationRunStatus: String, Codable, Sendable {
    case queued
    case running
    case waitingForWorkflow = "waiting_for_workflow"
    case completed
    case failed
    case cancelled
    case ignored

    public var title: String {
        switch self {
        case .queued: "Queued"
        case .running: "Running"
        case .waitingForWorkflow: "Waiting"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .ignored: "Ignored"
        }
    }
}

public enum ProjectAutomationJSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([ProjectAutomationJSONValue])
    case object([String: ProjectAutomationJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([ProjectAutomationJSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: ProjectAutomationJSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public struct ProjectAutomationTrigger: Codable, Sendable, Equatable {
    public var type: ProjectAutomationTriggerKind
    public var config: [String: ProjectAutomationJSONValue]

    public init(
        type: ProjectAutomationTriggerKind,
        config: [String: ProjectAutomationJSONValue] = [:]
    ) {
        self.type = type
        self.config = config
    }
}

public struct ProjectAutomationDefinition: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var projectId: String
    public var name: String
    public var description: String?
    public var version: Int
    public var enabled: Bool
    public var workflowId: String
    public var repositoryFullName: String
    public var trigger: ProjectAutomationTrigger
    public var taskMode: ProjectAutomationTaskMode
    public var model: String?
    public var permissionsScope: ProjectAutomationPermissionsScope
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
        trigger: ProjectAutomationTrigger,
        taskMode: ProjectAutomationTaskMode = .none,
        model: String? = nil,
        permissionsScope: ProjectAutomationPermissionsScope = .private,
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

public struct ProjectAutomationDefinitionUpsertRequest: Codable, Sendable, Equatable {
    public var name: String
    public var description: String?
    public var enabled: Bool
    public var workflowId: String
    public var repositoryFullName: String
    public var trigger: ProjectAutomationTrigger
    public var taskMode: ProjectAutomationTaskMode
    public var model: String?
    public var permissionsScope: ProjectAutomationPermissionsScope

    public init(
        name: String,
        description: String? = nil,
        enabled: Bool = true,
        workflowId: String,
        repositoryFullName: String,
        trigger: ProjectAutomationTrigger,
        taskMode: ProjectAutomationTaskMode = .none,
        model: String? = nil,
        permissionsScope: ProjectAutomationPermissionsScope = .private
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

public struct ProjectAutomationWorkflowSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var projectId: String
    public var name: String
    public var enabled: Bool

    public init(id: String, projectId: String, name: String, enabled: Bool) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.enabled = enabled
    }
}

public struct ProjectAutomationRun: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var automationId: String
    public var projectId: String
    public var workflowId: String
    public var workflowRunId: String?
    public var repositoryFullName: String
    public var triggerType: ProjectAutomationTriggerKind
    public var triggerEventId: String?
    public var status: ProjectAutomationRunStatus
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
        triggerType: ProjectAutomationTriggerKind,
        triggerEventId: String? = nil,
        status: ProjectAutomationRunStatus,
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

public struct ProjectAutomationRunDetail: Codable, Sendable, Equatable {
    public var run: ProjectAutomationRun
}

public struct ProjectAutomationManualRunRequest: Codable, Sendable, Equatable {
    public var actorId: String
    public var input: [String: ProjectAutomationJSONValue]

    public init(
        actorId: String = "human:admin",
        input: [String: ProjectAutomationJSONValue] = [:]
    ) {
        self.actorId = actorId
        self.input = input
    }
}
