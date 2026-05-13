import Foundation

public enum TaskSyncTokenMode: String, Codable, Sendable, Equatable {
    case inherit
    case override
}

public struct ProjectTaskSyncWebhookState: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var webhookURL: String?
    public var secretMasked: Bool
    public var manualSetupRequired: Bool
    public var lastDeliveryId: String?
    public var lastReceivedAt: Date?

    public init(
        enabled: Bool = false,
        webhookURL: String? = nil,
        secretMasked: Bool = false,
        manualSetupRequired: Bool = false,
        lastDeliveryId: String? = nil,
        lastReceivedAt: Date? = nil
    ) {
        self.enabled = enabled
        self.webhookURL = webhookURL
        self.secretMasked = secretMasked
        self.manualSetupRequired = manualSetupRequired
        self.lastDeliveryId = lastDeliveryId
        self.lastReceivedAt = lastReceivedAt
    }
}

public struct ProjectTaskSyncHealth: Codable, Sendable, Equatable {
    public var status: String
    public var message: String?
    public var checkedAt: Date?

    public init(status: String = "unknown", message: String? = nil, checkedAt: Date? = nil) {
        self.status = status
        self.message = message
        self.checkedAt = checkedAt
    }
}

public struct ProjectTaskSyncLinkedProject: Codable, Sendable, Equatable {
    public var title: String
    public var projectURL: String
    public var projectNodeId: String?
    public var tag: String
    public var statusOptions: [String]

    public init(
        title: String,
        projectURL: String,
        projectNodeId: String? = nil,
        tag: String,
        statusOptions: [String] = []
    ) {
        self.title = title
        self.projectURL = projectURL
        self.projectNodeId = projectNodeId
        self.tag = tag
        self.statusOptions = statusOptions
    }
}

public struct ProjectTaskSyncSchedule: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var intervalMinutes: Int
    public var lastRunAt: Date?

    public init(enabled: Bool = false, intervalMinutes: Int = 15, lastRunAt: Date? = nil) {
        self.enabled = enabled
        self.intervalMinutes = max(1, intervalMinutes)
        self.lastRunAt = lastRunAt
    }
}

public struct ProjectTaskSyncSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var providerId: String?
    public var repositoryURL: String?
    public var repositorySlug: String?
    public var projectURL: String?
    public var projectNodeId: String?
    public var defaultRepo: String?
    public var tokenMode: TaskSyncTokenMode
    public var statusMappings: [String: String]
    public var inboundStatusMappings: [String: String]
    public var linkedProjects: [ProjectTaskSyncLinkedProject]
    public var syncSchedule: ProjectTaskSyncSchedule
    public var webhook: ProjectTaskSyncWebhookState
    public var health: ProjectTaskSyncHealth

    private enum CodingKeys: String, CodingKey {
        case enabled
        case providerId
        case repositoryURL
        case repositorySlug
        case projectURL
        case projectNodeId
        case defaultRepo
        case tokenMode
        case statusMappings
        case inboundStatusMappings
        case linkedProjects
        case syncSchedule
        case webhook
        case health
    }

    public init(
        enabled: Bool = false,
        providerId: String? = nil,
        repositoryURL: String? = nil,
        repositorySlug: String? = nil,
        projectURL: String? = nil,
        projectNodeId: String? = nil,
        defaultRepo: String? = nil,
        tokenMode: TaskSyncTokenMode = .inherit,
        statusMappings: [String: String] = [:],
        inboundStatusMappings: [String: String] = [:],
        linkedProjects: [ProjectTaskSyncLinkedProject] = [],
        syncSchedule: ProjectTaskSyncSchedule = .init(),
        webhook: ProjectTaskSyncWebhookState = .init(),
        health: ProjectTaskSyncHealth = .init()
    ) {
        self.enabled = enabled
        self.providerId = providerId
        self.repositoryURL = repositoryURL
        self.repositorySlug = repositorySlug
        self.projectURL = projectURL
        self.projectNodeId = projectNodeId
        self.defaultRepo = defaultRepo
        self.tokenMode = tokenMode
        self.statusMappings = statusMappings
        self.inboundStatusMappings = inboundStatusMappings
        self.linkedProjects = linkedProjects
        self.syncSchedule = syncSchedule
        self.webhook = webhook
        self.health = health
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        providerId = try container.decodeIfPresent(String.self, forKey: .providerId)
        repositoryURL = try container.decodeIfPresent(String.self, forKey: .repositoryURL)
        repositorySlug = try container.decodeIfPresent(String.self, forKey: .repositorySlug)
        projectURL = try container.decodeIfPresent(String.self, forKey: .projectURL)
        projectNodeId = try container.decodeIfPresent(String.self, forKey: .projectNodeId)
        defaultRepo = try container.decodeIfPresent(String.self, forKey: .defaultRepo)
        tokenMode = try container.decodeIfPresent(TaskSyncTokenMode.self, forKey: .tokenMode) ?? .inherit
        statusMappings = try container.decodeIfPresent([String: String].self, forKey: .statusMappings) ?? [:]
        inboundStatusMappings = try container.decodeIfPresent([String: String].self, forKey: .inboundStatusMappings) ?? [:]
        linkedProjects = try container.decodeIfPresent([ProjectTaskSyncLinkedProject].self, forKey: .linkedProjects) ?? []
        syncSchedule = try container.decodeIfPresent(ProjectTaskSyncSchedule.self, forKey: .syncSchedule) ?? .init()
        webhook = try container.decodeIfPresent(ProjectTaskSyncWebhookState.self, forKey: .webhook) ?? .init()
        health = try container.decodeIfPresent(ProjectTaskSyncHealth.self, forKey: .health) ?? .init()
    }
}

public struct TaskExternalProjectMembership: Codable, Sendable, Equatable {
    public var projectNodeId: String?
    public var projectURL: String?
    public var projectTitle: String
    public var tag: String
    public var status: String?
    public var itemId: String?

    public init(
        projectNodeId: String? = nil,
        projectURL: String? = nil,
        projectTitle: String,
        tag: String,
        status: String? = nil,
        itemId: String? = nil
    ) {
        self.projectNodeId = projectNodeId
        self.projectURL = projectURL
        self.projectTitle = projectTitle
        self.tag = tag
        self.status = status
        self.itemId = itemId
    }
}

public struct TaskExternalMetadata: Codable, Sendable, Equatable {
    public var providerId: String?
    public var externalProjectId: String?
    public var externalItemId: String?
    public var externalIssueId: String?
    public var externalIssueNumber: Int?
    public var externalIssueURL: String?
    public var externalCommentId: String?
    public var origin: String?
    public var syncState: String?
    public var lastSyncedAt: Date?
    public var projectMemberships: [TaskExternalProjectMembership]

    private enum CodingKeys: String, CodingKey {
        case providerId
        case externalProjectId
        case externalItemId
        case externalIssueId
        case externalIssueNumber
        case externalIssueURL
        case externalCommentId
        case origin
        case syncState
        case lastSyncedAt
        case projectMemberships
    }

    public init(
        providerId: String? = nil,
        externalProjectId: String? = nil,
        externalItemId: String? = nil,
        externalIssueId: String? = nil,
        externalIssueNumber: Int? = nil,
        externalIssueURL: String? = nil,
        externalCommentId: String? = nil,
        origin: String? = nil,
        syncState: String? = nil,
        lastSyncedAt: Date? = nil,
        projectMemberships: [TaskExternalProjectMembership] = []
    ) {
        self.providerId = providerId
        self.externalProjectId = externalProjectId
        self.externalItemId = externalItemId
        self.externalIssueId = externalIssueId
        self.externalIssueNumber = externalIssueNumber
        self.externalIssueURL = externalIssueURL
        self.externalCommentId = externalCommentId
        self.origin = origin
        self.syncState = syncState
        self.lastSyncedAt = lastSyncedAt
        self.projectMemberships = projectMemberships
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerId = try container.decodeIfPresent(String.self, forKey: .providerId)
        externalProjectId = try container.decodeIfPresent(String.self, forKey: .externalProjectId)
        externalItemId = try container.decodeIfPresent(String.self, forKey: .externalItemId)
        externalIssueId = try container.decodeIfPresent(String.self, forKey: .externalIssueId)
        externalIssueNumber = try container.decodeIfPresent(Int.self, forKey: .externalIssueNumber)
        externalIssueURL = try container.decodeIfPresent(String.self, forKey: .externalIssueURL)
        externalCommentId = try container.decodeIfPresent(String.self, forKey: .externalCommentId)
        origin = try container.decodeIfPresent(String.self, forKey: .origin)
        syncState = try container.decodeIfPresent(String.self, forKey: .syncState)
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        projectMemberships = try container.decodeIfPresent([TaskExternalProjectMembership].self, forKey: .projectMemberships) ?? []
    }
}

public struct ProjectTaskSyncSettingsUpdateRequest: Codable, Sendable {
    public var enabled: Bool?
    public var providerId: String?
    public var repositoryURL: String?
    public var repositorySlug: String?
    public var projectURL: String?
    public var projectNodeId: String?
    public var defaultRepo: String?
    public var tokenMode: TaskSyncTokenMode?
    public var statusMappings: [String: String]?
    public var inboundStatusMappings: [String: String]?
    public var linkedProjects: [ProjectTaskSyncLinkedProject]?
    public var syncSchedule: ProjectTaskSyncSchedule?

    public init(
        enabled: Bool? = nil,
        providerId: String? = nil,
        repositoryURL: String? = nil,
        repositorySlug: String? = nil,
        projectURL: String? = nil,
        projectNodeId: String? = nil,
        defaultRepo: String? = nil,
        tokenMode: TaskSyncTokenMode? = nil,
        statusMappings: [String: String]? = nil,
        inboundStatusMappings: [String: String]? = nil,
        linkedProjects: [ProjectTaskSyncLinkedProject]? = nil,
        syncSchedule: ProjectTaskSyncSchedule? = nil
    ) {
        self.enabled = enabled
        self.providerId = providerId
        self.repositoryURL = repositoryURL
        self.repositorySlug = repositorySlug
        self.projectURL = projectURL
        self.projectNodeId = projectNodeId
        self.defaultRepo = defaultRepo
        self.tokenMode = tokenMode
        self.statusMappings = statusMappings
        self.inboundStatusMappings = inboundStatusMappings
        self.linkedProjects = linkedProjects
        self.syncSchedule = syncSchedule
    }
}

public struct ProjectTaskSyncDiscoverRequest: Codable, Sendable {
    public var providerId: String
    public var repositoryURL: String?
    public var tokenMode: TaskSyncTokenMode?

    public init(
        providerId: String = "github",
        repositoryURL: String? = nil,
        tokenMode: TaskSyncTokenMode? = nil
    ) {
        self.providerId = providerId
        self.repositoryURL = repositoryURL
        self.tokenMode = tokenMode
    }
}

public struct ProjectTaskSyncLinkRequest: Codable, Sendable {
    public var providerId: String
    public var repositoryURL: String?
    public var projectURL: String?
    public var defaultRepo: String?
    public var tokenMode: TaskSyncTokenMode?
    public var statusMappings: [String: String]?
    public var inboundStatusMappings: [String: String]?
    public var syncSchedule: ProjectTaskSyncSchedule?

    public init(
        providerId: String = "github",
        repositoryURL: String? = nil,
        projectURL: String? = nil,
        defaultRepo: String? = nil,
        tokenMode: TaskSyncTokenMode? = nil,
        statusMappings: [String: String]? = nil,
        inboundStatusMappings: [String: String]? = nil,
        syncSchedule: ProjectTaskSyncSchedule? = nil
    ) {
        self.providerId = providerId
        self.repositoryURL = repositoryURL
        self.projectURL = projectURL
        self.defaultRepo = defaultRepo
        self.tokenMode = tokenMode
        self.statusMappings = statusMappings
        self.inboundStatusMappings = inboundStatusMappings
        self.syncSchedule = syncSchedule
    }
}

public struct ProjectTaskSyncDiscoveryResponse: Codable, Sendable, Equatable {
    public var providerId: String
    public var repositoryURL: String?
    public var repositorySlug: String?
    public var projects: [ProjectTaskSyncLinkedProject]
    public var statusOptions: [String]
    public var manualRepositoryRequired: Bool
    public var message: String?

    public init(
        providerId: String = "github",
        repositoryURL: String? = nil,
        repositorySlug: String? = nil,
        projects: [ProjectTaskSyncLinkedProject] = [],
        statusOptions: [String] = [],
        manualRepositoryRequired: Bool = false,
        message: String? = nil
    ) {
        self.providerId = providerId
        self.repositoryURL = repositoryURL
        self.repositorySlug = repositorySlug
        self.projects = projects
        self.statusOptions = statusOptions
        self.manualRepositoryRequired = manualRepositoryRequired
        self.message = message
    }
}

public struct ProjectTaskSyncTokenRequest: Codable, Sendable {
    public var token: String

    public init(token: String) {
        self.token = token
    }
}

public struct ProjectTaskSyncTokenStatusResponse: Codable, Sendable, Equatable {
    public var tokenMode: TaskSyncTokenMode
    public var hasOverrideToken: Bool
    public var maskedToken: String?

    public init(tokenMode: TaskSyncTokenMode, hasOverrideToken: Bool, maskedToken: String? = nil) {
        self.tokenMode = tokenMode
        self.hasOverrideToken = hasOverrideToken
        self.maskedToken = maskedToken
    }
}

public struct ProjectTaskSyncResponse: Codable, Sendable, Equatable {
    public var project: ProjectRecord
    public var settings: ProjectTaskSyncSettings

    public init(project: ProjectRecord, settings: ProjectTaskSyncSettings) {
        self.project = project
        self.settings = settings
    }
}

public struct ProjectTaskSyncNowResponse: Codable, Sendable, Equatable {
    public var imported: Int
    public var updated: Int
    public var skipped: Int
    public var message: String?

    public init(imported: Int = 0, updated: Int = 0, skipped: Int = 0, message: String? = nil) {
        self.imported = imported
        self.updated = updated
        self.skipped = skipped
        self.message = message
    }
}

public struct TaskSyncWebhookResponse: Codable, Sendable, Equatable {
    public var ok: Bool
    public var duplicate: Bool
    public var message: String?

    public init(ok: Bool, duplicate: Bool = false, message: String? = nil) {
        self.ok = ok
        self.duplicate = duplicate
        self.message = message
    }
}
