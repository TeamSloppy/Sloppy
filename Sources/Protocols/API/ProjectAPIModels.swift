import Foundation

public struct ProjectChannel: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var channelId: String
    public var createdAt: Date

    public init(id: String, title: String, channelId: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.channelId = channelId
        self.createdAt = createdAt
    }
}

public enum ProjectLoopMode: String, Codable, Sendable, Equatable {
    case human
    case agent
}

public enum ProjectAutopilotMode: String, Codable, Sendable, Equatable {
    case assistive
    case sequential
    case parallel
}

public struct ProjectAutopilotSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var mode: ProjectAutopilotMode
    public var defaultAgentId: String?
    public var reviewerAgentId: String?
    public var includedTags: [String]
    public var ignoredTags: [String]
    public var trustedAuthors: [String]
    public var pickupRules: ProjectTaskPickupRules
    public var maxParallelTasks: Int
    public var canUseWeb: Bool
    public var canEditFiles: Bool
    public var canRunCommands: Bool
    public var canStartLocalhost: Bool
    public var canCommit: Bool
    public var canPush: Bool

    public init(
        enabled: Bool = false,
        mode: ProjectAutopilotMode = .assistive,
        defaultAgentId: String? = nil,
        reviewerAgentId: String? = nil,
        includedTags: [String] = [],
        ignoredTags: [String] = [],
        trustedAuthors: [String] = [],
        maxParallelTasks: Int = 1,
        canUseWeb: Bool = false,
        canEditFiles: Bool = false,
        canRunCommands: Bool = false,
        canStartLocalhost: Bool = false,
        canCommit: Bool = false,
        canPush: Bool = false,
        pickupRules: ProjectTaskPickupRules = .init()
    ) {
        self.enabled = enabled
        self.mode = mode
        self.defaultAgentId = defaultAgentId
        self.reviewerAgentId = reviewerAgentId
        self.includedTags = Self.normalizedTags(includedTags)
        self.ignoredTags = Self.normalizedTags(ignoredTags)
        self.trustedAuthors = trustedAuthors
        self.pickupRules = pickupRules
        self.maxParallelTasks = max(1, maxParallelTasks)
        self.canUseWeb = canUseWeb
        self.canEditFiles = canEditFiles
        self.canRunCommands = canRunCommands
        self.canStartLocalhost = canStartLocalhost
        self.canCommit = canCommit
        self.canPush = canPush
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case mode
        case defaultAgentId
        case reviewerAgentId
        case includedTags
        case ignoredTags
        case trustedAuthors
        case pickupRules
        case maxParallelTasks
        case canUseWeb
        case canEditFiles
        case canRunCommands
        case canStartLocalhost
        case canCommit
        case canPush
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        mode = try container.decodeIfPresent(ProjectAutopilotMode.self, forKey: .mode) ?? .assistive
        defaultAgentId = try container.decodeIfPresent(String.self, forKey: .defaultAgentId)
        reviewerAgentId = try container.decodeIfPresent(String.self, forKey: .reviewerAgentId)
        let tags = try container.decodeIfPresent([String].self, forKey: .includedTags) ?? []
        includedTags = Self.normalizedTags(tags)
        ignoredTags = Self.normalizedTags(try container.decodeIfPresent([String].self, forKey: .ignoredTags) ?? [])
        trustedAuthors = try container.decodeIfPresent([String].self, forKey: .trustedAuthors) ?? []
        pickupRules = try container.decodeIfPresent(ProjectTaskPickupRules.self, forKey: .pickupRules) ?? .init()
        maxParallelTasks = max(1, try container.decodeIfPresent(Int.self, forKey: .maxParallelTasks) ?? 1)
        canUseWeb = try container.decodeIfPresent(Bool.self, forKey: .canUseWeb) ?? false
        canEditFiles = try container.decodeIfPresent(Bool.self, forKey: .canEditFiles) ?? false
        canRunCommands = try container.decodeIfPresent(Bool.self, forKey: .canRunCommands) ?? false
        canStartLocalhost = try container.decodeIfPresent(Bool.self, forKey: .canStartLocalhost) ?? false
        canCommit = try container.decodeIfPresent(Bool.self, forKey: .canCommit) ?? false
        canPush = try container.decodeIfPresent(Bool.self, forKey: .canPush) ?? false
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(normalized)
        }
        return result
    }
}

public struct ProjectHeartbeatSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var intervalMinutes: Int

    public init(enabled: Bool = false, intervalMinutes: Int = 5) {
        self.enabled = enabled
        self.intervalMinutes = intervalMinutes
    }
}

public enum ProjectKind: String, Codable, Sendable, Equatable, CaseIterable {
    case project
    case workspace
}

public struct ProjectRecord: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var description: String
    public var icon: String?
    public var kind: ProjectKind
    public var directoryPaths: [String]
    public var channels: [ProjectChannel]
    public var tasks: [ProjectTask]
    public var actors: [String]
    public var teams: [String]
    public var models: [String]
    public var agentFiles: [String]
    public var heartbeat: ProjectHeartbeatSettings
    public var repoPath: String?
    public var worktreeRootPath: String?
    public var sourceControlProviderId: String?
    public var reviewSettings: ProjectReviewSettings
    public var automaticTaskPickupEnabled: Bool
    public var autopilotSettings: ProjectAutopilotSettings
    public var taskLoopMode: ProjectLoopMode
    public var taskSyncSettings: ProjectTaskSyncSettings
    public var isFavorite: Bool
    public var isArchived: Bool
    public var parentProjectId: String?
    public var worktreeBranch: String?
    public var isWorktree: Bool
    public var createdAt: Date
    public var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, name, description, icon, kind, directoryPaths, channels, tasks, actors, teams, models
        case agentFiles, heartbeat, repoPath, worktreeRootPath, sourceControlProviderId, reviewSettings, automaticTaskPickupEnabled, autopilotSettings, taskLoopMode, taskSyncSettings, isFavorite, isArchived, createdAt, updatedAt
        case parentProjectId, worktreeBranch, isWorktree
    }

    public init(
        id: String,
        name: String,
        description: String,
        icon: String? = nil,
        kind: ProjectKind = .project,
        directoryPaths: [String] = [],
        channels: [ProjectChannel],
        tasks: [ProjectTask],
        actors: [String] = [],
        teams: [String] = [],
        models: [String] = [],
        agentFiles: [String] = [],
        heartbeat: ProjectHeartbeatSettings = ProjectHeartbeatSettings(),
        repoPath: String? = nil,
        worktreeRootPath: String? = nil,
        sourceControlProviderId: String? = nil,
        reviewSettings: ProjectReviewSettings = ProjectReviewSettings(),
        automaticTaskPickupEnabled: Bool = true,
        autopilotSettings: ProjectAutopilotSettings = ProjectAutopilotSettings(),
        taskLoopMode: ProjectLoopMode = .human,
        taskSyncSettings: ProjectTaskSyncSettings = ProjectTaskSyncSettings(),
        isFavorite: Bool = false,
        isArchived: Bool = false,
        parentProjectId: String? = nil,
        worktreeBranch: String? = nil,
        isWorktree: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.kind = kind
        self.directoryPaths = directoryPaths
        self.channels = channels
        self.tasks = tasks
        self.actors = actors
        self.teams = teams
        self.models = models
        self.agentFiles = agentFiles
        self.heartbeat = heartbeat
        self.repoPath = repoPath
        self.worktreeRootPath = worktreeRootPath
        self.sourceControlProviderId = sourceControlProviderId
        self.reviewSettings = reviewSettings
        self.automaticTaskPickupEnabled = automaticTaskPickupEnabled
        self.autopilotSettings = autopilotSettings
        self.taskLoopMode = taskLoopMode
        self.taskSyncSettings = taskSyncSettings
        self.isFavorite = isFavorite
        self.isArchived = isArchived
        self.parentProjectId = parentProjectId
        self.worktreeBranch = worktreeBranch
        self.isWorktree = isWorktree
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        kind = try container.decodeIfPresent(ProjectKind.self, forKey: .kind) ?? .project
        directoryPaths = try container.decodeIfPresent([String].self, forKey: .directoryPaths) ?? []
        channels = try container.decodeIfPresent([ProjectChannel].self, forKey: .channels) ?? []
        tasks = try container.decodeIfPresent([ProjectTask].self, forKey: .tasks) ?? []
        actors = try container.decodeIfPresent([String].self, forKey: .actors) ?? []
        teams = try container.decodeIfPresent([String].self, forKey: .teams) ?? []
        models = try container.decodeIfPresent([String].self, forKey: .models) ?? []
        agentFiles = try container.decodeIfPresent([String].self, forKey: .agentFiles) ?? []
        heartbeat = try container.decodeIfPresent(ProjectHeartbeatSettings.self, forKey: .heartbeat) ?? ProjectHeartbeatSettings()
        repoPath = try container.decodeIfPresent(String.self, forKey: .repoPath)
        worktreeRootPath = try container.decodeIfPresent(String.self, forKey: .worktreeRootPath)
        sourceControlProviderId = try container.decodeIfPresent(String.self, forKey: .sourceControlProviderId)
        reviewSettings = try container.decodeIfPresent(ProjectReviewSettings.self, forKey: .reviewSettings) ?? ProjectReviewSettings()
        automaticTaskPickupEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticTaskPickupEnabled) ?? true
        autopilotSettings = try container.decodeIfPresent(ProjectAutopilotSettings.self, forKey: .autopilotSettings) ?? ProjectAutopilotSettings()
        taskLoopMode = try container.decodeIfPresent(ProjectLoopMode.self, forKey: .taskLoopMode) ?? .human
        taskSyncSettings = try container.decodeIfPresent(ProjectTaskSyncSettings.self, forKey: .taskSyncSettings) ?? ProjectTaskSyncSettings()
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        parentProjectId = try container.decodeIfPresent(String.self, forKey: .parentProjectId)
        worktreeBranch = try container.decodeIfPresent(String.self, forKey: .worktreeBranch)
        isWorktree = try container.decodeIfPresent(Bool.self, forKey: .isWorktree) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

public struct ProjectEmergencyStopResponse: Codable, Sendable {
    public var project: ProjectRecord
    public var stoppedWorkerCount: Int
    public var interruptedSessionCount: Int
    public var warnings: [String]

    public init(project: ProjectRecord, stoppedWorkerCount: Int, interruptedSessionCount: Int, warnings: [String]) {
        self.project = project
        self.stoppedWorkerCount = stoppedWorkerCount
        self.interruptedSessionCount = interruptedSessionCount
        self.warnings = warnings
    }
}

public struct ProjectListRecord: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var description: String
    public var icon: String?
    public var kind: ProjectKind
    public var directoryPaths: [String]
    public var channels: [ProjectChannel]
    public var actors: [String]
    public var teams: [String]
    public var repoPath: String?
    public var worktreeRootPath: String?
    public var sourceControlProviderId: String?
    public var taskCounts: ProjectTaskCountSummary
    public var isFavorite: Bool
    public var isArchived: Bool
    public var parentProjectId: String?
    public var worktreeBranch: String?
    public var isWorktree: Bool
    public var createdAt: Date
    public var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, name, description, icon, kind, directoryPaths, channels, actors, teams, repoPath, worktreeRootPath, sourceControlProviderId, taskCounts, isFavorite, isArchived
        case parentProjectId, worktreeBranch, isWorktree, createdAt, updatedAt
    }

    public init(
        id: String,
        name: String,
        description: String,
        icon: String? = nil,
        kind: ProjectKind = .project,
        directoryPaths: [String] = [],
        channels: [ProjectChannel] = [],
        actors: [String] = [],
        teams: [String] = [],
        repoPath: String? = nil,
        worktreeRootPath: String? = nil,
        sourceControlProviderId: String? = nil,
        taskCounts: ProjectTaskCountSummary = ProjectTaskCountSummary(),
        isFavorite: Bool = false,
        isArchived: Bool = false,
        parentProjectId: String? = nil,
        worktreeBranch: String? = nil,
        isWorktree: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.kind = kind
        self.directoryPaths = directoryPaths
        self.channels = channels
        self.actors = actors
        self.teams = teams
        self.repoPath = repoPath
        self.worktreeRootPath = worktreeRootPath
        self.sourceControlProviderId = sourceControlProviderId
        self.taskCounts = taskCounts
        self.isFavorite = isFavorite
        self.isArchived = isArchived
        self.parentProjectId = parentProjectId
        self.worktreeBranch = worktreeBranch
        self.isWorktree = isWorktree
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        kind = try container.decodeIfPresent(ProjectKind.self, forKey: .kind) ?? .project
        directoryPaths = try container.decodeIfPresent([String].self, forKey: .directoryPaths) ?? []
        channels = try container.decodeIfPresent([ProjectChannel].self, forKey: .channels) ?? []
        actors = try container.decodeIfPresent([String].self, forKey: .actors) ?? []
        teams = try container.decodeIfPresent([String].self, forKey: .teams) ?? []
        repoPath = try container.decodeIfPresent(String.self, forKey: .repoPath)
        worktreeRootPath = try container.decodeIfPresent(String.self, forKey: .worktreeRootPath)
        sourceControlProviderId = try container.decodeIfPresent(String.self, forKey: .sourceControlProviderId)
        taskCounts = try container.decodeIfPresent(ProjectTaskCountSummary.self, forKey: .taskCounts) ?? ProjectTaskCountSummary()
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        parentProjectId = try container.decodeIfPresent(String.self, forKey: .parentProjectId)
        worktreeBranch = try container.decodeIfPresent(String.self, forKey: .worktreeBranch)
        isWorktree = try container.decodeIfPresent(Bool.self, forKey: .isWorktree) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

/// Payload returned when creating a project via HTTP; includes Git clone outcome when `repoUrl` was used.
public struct ProjectCreateResult: Codable, Sendable, Equatable {
    public var project: ProjectRecord
    /// When the project was created with a `repoUrl`, whether `git clone` finished successfully. `nil` when no remote clone was attempted.
    public var repoCloneSucceeded: Bool?

    public init(project: ProjectRecord, repoCloneSucceeded: Bool? = nil) {
        self.project = project
        self.repoCloneSucceeded = repoCloneSucceeded
    }
}

public struct ProjectCreateRequest: Codable, Sendable {
    public var id: String?
    public var name: String
    public var description: String?
    public var idea: String?
    public var channels: [ProjectChannelCreateRequest]
    public var actors: [String]?
    public var teams: [String]?
    public var repoUrl: String?
    public var repoPath: String?
    public var kind: ProjectKind
    public var directoryPaths: [String]
    public var sourceControlProviderId: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case idea
        case channels
        case actors
        case teams
        case repoUrl
        case repoPath
        case kind
        case directoryPaths
        case sourceControlProviderId
    }

    public init(
        id: String? = nil,
        name: String,
        description: String? = nil,
        idea: String? = nil,
        channels: [ProjectChannelCreateRequest] = [],
        actors: [String]? = nil,
        teams: [String]? = nil,
        repoUrl: String? = nil,
        repoPath: String? = nil,
        kind: ProjectKind = .project,
        directoryPaths: [String] = [],
        sourceControlProviderId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.idea = idea
        self.channels = channels
        self.actors = actors
        self.teams = teams
        self.repoUrl = repoUrl
        self.repoPath = repoPath
        self.kind = kind
        self.directoryPaths = directoryPaths
        self.sourceControlProviderId = sourceControlProviderId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        idea = try container.decodeIfPresent(String.self, forKey: .idea)
        channels = try container.decodeIfPresent([ProjectChannelCreateRequest].self, forKey: .channels) ?? []
        actors = try container.decodeIfPresent([String].self, forKey: .actors)
        teams = try container.decodeIfPresent([String].self, forKey: .teams)
        repoUrl = try container.decodeIfPresent(String.self, forKey: .repoUrl)
        repoPath = try container.decodeIfPresent(String.self, forKey: .repoPath)
        kind = try container.decodeIfPresent(ProjectKind.self, forKey: .kind) ?? .project
        directoryPaths = try container.decodeIfPresent([String].self, forKey: .directoryPaths) ?? []
        sourceControlProviderId = try container.decodeIfPresent(String.self, forKey: .sourceControlProviderId)
    }
}

public struct ProjectUpdateRequest: Codable, Sendable {
    public var name: String?
    public var description: String?
    public var icon: String?
    public var actors: [String]?
    public var teams: [String]?
    public var models: [String]?
    public var agentFiles: [String]?
    public var heartbeat: ProjectHeartbeatSettings?
    public var repoPath: String?
    public var kind: ProjectKind?
    public var directoryPaths: [String]?
    public var sourceControlProviderId: String?
    public var reviewSettings: ProjectReviewSettings?
    public var automaticTaskPickupEnabled: Bool?
    public var autopilotSettings: ProjectAutopilotSettings?
    public var taskLoopMode: ProjectLoopMode?
    public var isFavorite: Bool?
    public var isArchived: Bool?

    public init(
        name: String? = nil,
        description: String? = nil,
        icon: String? = nil,
        actors: [String]? = nil,
        teams: [String]? = nil,
        models: [String]? = nil,
        agentFiles: [String]? = nil,
        heartbeat: ProjectHeartbeatSettings? = nil,
        repoPath: String? = nil,
        kind: ProjectKind? = nil,
        directoryPaths: [String]? = nil,
        sourceControlProviderId: String? = nil,
        reviewSettings: ProjectReviewSettings? = nil,
        automaticTaskPickupEnabled: Bool? = nil,
        autopilotSettings: ProjectAutopilotSettings? = nil,
        taskLoopMode: ProjectLoopMode? = nil,
        isFavorite: Bool? = nil,
        isArchived: Bool? = nil
    ) {
        self.name = name
        self.description = description
        self.icon = icon
        self.actors = actors
        self.teams = teams
        self.models = models
        self.agentFiles = agentFiles
        self.heartbeat = heartbeat
        self.repoPath = repoPath
        self.kind = kind
        self.directoryPaths = directoryPaths
        self.sourceControlProviderId = sourceControlProviderId
        self.reviewSettings = reviewSettings
        self.automaticTaskPickupEnabled = automaticTaskPickupEnabled
        self.autopilotSettings = autopilotSettings
        self.taskLoopMode = taskLoopMode
        self.isFavorite = isFavorite
        self.isArchived = isArchived
    }
}

public struct ProjectContextRefreshResponse: Codable, Sendable {
    public var projectId: String
    public var repoPath: String?
    public var appliedChannelIds: [String]
    public var loadedDocPaths: [String]
    public var loadedSkillPaths: [String]
    public var totalChars: Int
    public var truncated: Bool

    public init(
        projectId: String,
        repoPath: String?,
        appliedChannelIds: [String],
        loadedDocPaths: [String],
        loadedSkillPaths: [String],
        totalChars: Int,
        truncated: Bool
    ) {
        self.projectId = projectId
        self.repoPath = repoPath
        self.appliedChannelIds = appliedChannelIds
        self.loadedDocPaths = loadedDocPaths
        self.loadedSkillPaths = loadedSkillPaths
        self.totalChars = totalChars
        self.truncated = truncated
    }
}

public struct ProjectChannelCreateRequest: Codable, Sendable {
    public var title: String
    public var channelId: String

    public init(title: String, channelId: String) {
        self.title = title
        self.channelId = channelId
    }
}

public struct ProjectChannelLinkRequest: Codable, Sendable {
    public var channelId: String
    public var title: String?
    public var ensureSession: Bool?

    public init(channelId: String, title: String? = nil, ensureSession: Bool? = nil) {
        self.channelId = channelId
        self.title = title
        self.ensureSession = ensureSession
    }
}

public struct ProjectChannelLinkSession: Codable, Sendable, Equatable {
    public var channelId: String
    public var sessionId: String
    public var status: String

    public init(channelId: String, sessionId: String, status: String) {
        self.channelId = channelId
        self.sessionId = sessionId
        self.status = status
    }
}

public struct ProjectChannelLinkResponse: Codable, Sendable, Equatable {
    public var project: ProjectRecord
    public var channel: ProjectChannel
    public var session: ProjectChannelLinkSession?
    public var status: String

    public init(
        project: ProjectRecord,
        channel: ProjectChannel,
        session: ProjectChannelLinkSession? = nil,
        status: String
    ) {
        self.project = project
        self.channel = channel
        self.session = session
        self.status = status
    }
}

public enum ReviewApprovalMode: String, Codable, Sendable {
    case auto
    case human
    case agent
}

public enum ProjectAutonomousMode: String, Codable, Sendable {
    case off
    case sequential
    case parallel
}

public struct ProjectReviewSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var approvalMode: ReviewApprovalMode
    public var autonomousMode: ProjectAutonomousMode
    public var maxAutonomousRouteSteps: Int

    public init(
        enabled: Bool = true,
        approvalMode: ReviewApprovalMode = .human,
        autonomousMode: ProjectAutonomousMode = .off,
        maxAutonomousRouteSteps: Int = 6
    ) {
        self.enabled = enabled
        self.approvalMode = approvalMode
        self.autonomousMode = autonomousMode
        self.maxAutonomousRouteSteps = max(1, maxAutonomousRouteSteps)
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case approvalMode
        case autonomousMode
        case maxAutonomousRouteSteps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        approvalMode = try container.decodeIfPresent(ReviewApprovalMode.self, forKey: .approvalMode) ?? .human
        autonomousMode = try container.decodeIfPresent(ProjectAutonomousMode.self, forKey: .autonomousMode) ?? .off
        maxAutonomousRouteSteps = max(1, try container.decodeIfPresent(Int.self, forKey: .maxAutonomousRouteSteps) ?? 6)
    }
}
