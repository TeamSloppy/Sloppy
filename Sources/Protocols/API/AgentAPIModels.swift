import Foundation

public struct AgentCreateRequest: Codable, Sendable {
    public var id: String
    public var displayName: String
    public var role: String
    public var isSystem: Bool
    public var runtime: AgentRuntimeConfig?
    public var petDraftId: String?

    public init(
        id: String,
        displayName: String,
        role: String,
        isSystem: Bool = false,
        runtime: AgentRuntimeConfig? = nil,
        petDraftId: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.isSystem = isSystem
        self.runtime = runtime
        self.petDraftId = petDraftId
    }
}

public struct AgentACPConfig: Codable, Sendable, Equatable {
    public var targetId: String
    public var cwd: String?

    public init(targetId: String, cwd: String? = nil) {
        self.targetId = targetId
        self.cwd = cwd
    }
}

public struct AgentSummary: Codable, Sendable, Equatable {
    public var id: String
    public var displayName: String
    public var role: String
    public var createdAt: Date
    public var isSystem: Bool
    public var runtime: AgentRuntimeConfig
    public var pet: AgentPetSummary?

    enum CodingKeys: String, CodingKey {
        case id, displayName, role, createdAt, isSystem, runtime, pet
    }

    public init(
        id: String,
        displayName: String,
        role: String,
        createdAt: Date = Date(),
        isSystem: Bool = false,
        runtime: AgentRuntimeConfig = AgentRuntimeConfig(),
        pet: AgentPetSummary? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.createdAt = createdAt
        self.isSystem = isSystem
        self.runtime = runtime
        self.pet = pet
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        role = try container.decode(String.self, forKey: .role)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isSystem = try container.decodeIfPresent(Bool.self, forKey: .isSystem) ?? false
        runtime = try container.decodeIfPresent(AgentRuntimeConfig.self, forKey: .runtime) ?? .init()
        pet = try container.decodeIfPresent(AgentPetSummary.self, forKey: .pet)
    }
}

public struct AgentTaskRecord: Codable, Sendable, Equatable {
    public var projectId: String
    public var projectName: String
    public var task: ProjectTask

    public init(projectId: String, projectName: String, task: ProjectTask) {
        self.projectId = projectId
        self.projectName = projectName
        self.task = task
    }
}

public struct AgentDocumentBundle: Codable, Sendable, Equatable {
    public var userMarkdown: String
    public var agentsMarkdown: String
    public var soulMarkdown: String
    public var identityMarkdown: String
    public var heartbeatMarkdown: String
    public var friendReminderMarkdown: String
    public var memoryMarkdown: String

    public init(
        userMarkdown: String,
        agentsMarkdown: String,
        soulMarkdown: String,
        identityMarkdown: String,
        heartbeatMarkdown: String = "",
        friendReminderMarkdown: String = "",
        memoryMarkdown: String = ""
    ) {
        self.userMarkdown = userMarkdown
        self.agentsMarkdown = agentsMarkdown
        self.soulMarkdown = soulMarkdown
        self.identityMarkdown = identityMarkdown
        self.heartbeatMarkdown = heartbeatMarkdown
        self.friendReminderMarkdown = friendReminderMarkdown
        self.memoryMarkdown = memoryMarkdown
    }

    enum CodingKeys: String, CodingKey {
        case userMarkdown
        case agentsMarkdown
        case soulMarkdown
        case identityMarkdown
        case heartbeatMarkdown
        case friendReminderMarkdown
        case memoryMarkdown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userMarkdown = try container.decode(String.self, forKey: .userMarkdown)
        agentsMarkdown = try container.decode(String.self, forKey: .agentsMarkdown)
        soulMarkdown = try container.decode(String.self, forKey: .soulMarkdown)
        identityMarkdown = try container.decode(String.self, forKey: .identityMarkdown)
        heartbeatMarkdown = try container.decodeIfPresent(String.self, forKey: .heartbeatMarkdown) ?? ""
        friendReminderMarkdown = try container.decodeIfPresent(String.self, forKey: .friendReminderMarkdown) ?? ""
        memoryMarkdown = try container.decodeIfPresent(String.self, forKey: .memoryMarkdown) ?? ""
    }
}

public struct AgentHeartbeatSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var intervalMinutes: Int
    public var mode: AgentHeartbeatMode
    public var proactive: AgentProactiveSettings

    public init(enabled: Bool = false, intervalMinutes: Int? = nil, mode: AgentHeartbeatMode = .checklist,
                proactive: AgentProactiveSettings = .init()) {
        self.enabled = enabled
        self.intervalMinutes = intervalMinutes ?? (mode == .proactive ? 30 : 5)
        self.mode = mode
        self.proactive = proactive
    }

    private enum CodingKeys: String, CodingKey { case enabled, intervalMinutes, mode, proactive }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            intervalMinutes: try container.decodeIfPresent(Int.self, forKey: .intervalMinutes),
            mode: try container.decodeIfPresent(AgentHeartbeatMode.self, forKey: .mode) ?? .checklist,
            proactive: try container.decodeIfPresent(AgentProactiveSettings.self, forKey: .proactive) ?? .init()
        )
    }
}

public struct AgentHeartbeatStatus: Codable, Sendable, Equatable {
    public var lastRunAt: Date?
    public var lastSuccessAt: Date?
    public var lastFailureAt: Date?
    public var lastResult: String?
    public var lastErrorMessage: String?
    public var lastSessionId: String?

    public init(
        lastRunAt: Date? = nil,
        lastSuccessAt: Date? = nil,
        lastFailureAt: Date? = nil,
        lastResult: String? = nil,
        lastErrorMessage: String? = nil,
        lastSessionId: String? = nil
    ) {
        self.lastRunAt = lastRunAt
        self.lastSuccessAt = lastSuccessAt
        self.lastFailureAt = lastFailureAt
        self.lastResult = lastResult
        self.lastErrorMessage = lastErrorMessage
        self.lastSessionId = lastSessionId
    }
}

/// When an agent should react to inbound gateway traffic (Telegram / Discord groups).
public enum ChannelInboundActivation: String, Codable, Sendable, Equatable {
    /// Forward every non-empty message to the agent (default).
    case allMessages = "all"
    /// Only when the bot is @mentioned or the user replies to the bot's message. Slash commands still always apply.
    case mentionOrReply = "mention_or_reply"
}

public struct AgentChannelSessionSettings: Codable, Sendable, Equatable {
    public var autoCloseEnabled: Bool
    public var autoCloseAfterMinutes: Int
    public var inboundActivation: ChannelInboundActivation
    public var allowedChannelIds: [String]
    public var excludedChannelIds: [String]

    public init(
        autoCloseEnabled: Bool = false,
        autoCloseAfterMinutes: Int = 30,
        inboundActivation: ChannelInboundActivation = .allMessages,
        allowedChannelIds: [String] = [],
        excludedChannelIds: [String] = []
    ) {
        self.autoCloseEnabled = autoCloseEnabled
        self.autoCloseAfterMinutes = autoCloseAfterMinutes
        self.inboundActivation = inboundActivation
        self.allowedChannelIds = Self.normalizedChannelIds(allowedChannelIds)
        self.excludedChannelIds = Self.normalizedChannelIds(excludedChannelIds)
    }

    enum CodingKeys: String, CodingKey {
        case autoCloseEnabled
        case autoCloseAfterMinutes
        case inboundActivation
        case allowedChannelIds
        case excludedChannelIds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoCloseEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoCloseEnabled) ?? false
        autoCloseAfterMinutes = try c.decodeIfPresent(Int.self, forKey: .autoCloseAfterMinutes) ?? 30
        inboundActivation = try c.decodeIfPresent(ChannelInboundActivation.self, forKey: .inboundActivation) ?? .allMessages
        allowedChannelIds = Self.normalizedChannelIds(try c.decodeIfPresent([String].self, forKey: .allowedChannelIds) ?? [])
        excludedChannelIds = Self.normalizedChannelIds(try c.decodeIfPresent([String].self, forKey: .excludedChannelIds) ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(autoCloseEnabled, forKey: .autoCloseEnabled)
        try c.encode(autoCloseAfterMinutes, forKey: .autoCloseAfterMinutes)
        try c.encode(inboundActivation, forKey: .inboundActivation)
        try c.encode(allowedChannelIds, forKey: .allowedChannelIds)
        try c.encode(excludedChannelIds, forKey: .excludedChannelIds)
    }

    private static func normalizedChannelIds(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
                continue
            }
            result.append(trimmed)
        }
        return result
    }
}

public struct AgentSkillSettings: Codable, Sendable, Equatable {
    /// Skill ids disabled for this agent. Disabled skills remain installed but are omitted from prompt context, auto routing, and skill shortcuts.
    public var disabledSkills: [String]

    public init(disabledSkills: [String] = []) {
        self.disabledSkills = Self.normalizedSkillIds(disabledSkills)
    }

    private enum CodingKeys: String, CodingKey {
        case disabledSkills
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        disabledSkills = Self.normalizedSkillIds(try container.decodeIfPresent([String].self, forKey: .disabledSkills) ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(disabledSkills, forKey: .disabledSkills)
    }

    private static func normalizedSkillIds(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
                continue
            }
            result.append(trimmed)
        }
        return result
    }
}

public struct AgentConfigDetail: Codable, Sendable, Equatable {
    public var agentId: String
    public var role: String
    public var selectedModel: String?
    public var plannerModel: String?
    public var reasoningEffort: ReasoningEffort?
    /// Whether JEV may choose the executor model for automatic turns.
    public var automaticModelRouting: Bool
    public var autoApproveInput: Bool
    public var availableModels: [ProviderModelOption]
    public var documents: AgentDocumentBundle
    public var heartbeat: AgentHeartbeatSettings
    public var channelSessions: AgentChannelSessionSettings
    public var heartbeatStatus: AgentHeartbeatStatus
    public var runtime: AgentRuntimeConfig
    public var skills: AgentSkillSettings

    public init(
        agentId: String,
        role: String,
        selectedModel: String?,
        plannerModel: String? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        automaticModelRouting: Bool = true,
        autoApproveInput: Bool = true,
        availableModels: [ProviderModelOption],
        documents: AgentDocumentBundle,
        heartbeat: AgentHeartbeatSettings = AgentHeartbeatSettings(),
        channelSessions: AgentChannelSessionSettings = AgentChannelSessionSettings(),
        heartbeatStatus: AgentHeartbeatStatus = AgentHeartbeatStatus(),
        runtime: AgentRuntimeConfig = AgentRuntimeConfig(),
        skills: AgentSkillSettings = AgentSkillSettings()
    ) {
        self.agentId = agentId
        self.role = role
        self.selectedModel = selectedModel
        self.plannerModel = plannerModel
        self.reasoningEffort = reasoningEffort
        self.automaticModelRouting = automaticModelRouting
        self.autoApproveInput = autoApproveInput
        self.availableModels = availableModels
        self.documents = documents
        self.heartbeat = heartbeat
        self.channelSessions = channelSessions
        self.heartbeatStatus = heartbeatStatus
        self.runtime = runtime
        self.skills = skills
    }

    enum CodingKeys: String, CodingKey {
        case agentId, role, selectedModel, plannerModel, reasoningEffort, automaticModelRouting, autoApproveInput, availableModels, documents, heartbeat, channelSessions, heartbeatStatus, runtime, skills
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        agentId = try container.decode(String.self, forKey: .agentId)
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? ""
        selectedModel = try container.decodeIfPresent(String.self, forKey: .selectedModel)
        plannerModel = try container.decodeIfPresent(String.self, forKey: .plannerModel)
        reasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort)
        automaticModelRouting = try container.decodeIfPresent(Bool.self, forKey: .automaticModelRouting) ?? true
        autoApproveInput = try container.decodeIfPresent(Bool.self, forKey: .autoApproveInput) ?? true
        availableModels = try container.decode([ProviderModelOption].self, forKey: .availableModels)
        documents = try container.decode(AgentDocumentBundle.self, forKey: .documents)
        heartbeat = try container.decodeIfPresent(AgentHeartbeatSettings.self, forKey: .heartbeat) ?? AgentHeartbeatSettings()
        channelSessions = try container.decodeIfPresent(AgentChannelSessionSettings.self, forKey: .channelSessions) ?? AgentChannelSessionSettings()
        heartbeatStatus = try container.decodeIfPresent(AgentHeartbeatStatus.self, forKey: .heartbeatStatus) ?? AgentHeartbeatStatus()
        runtime = try container.decodeIfPresent(AgentRuntimeConfig.self, forKey: .runtime) ?? .init()
        skills = try container.decodeIfPresent(AgentSkillSettings.self, forKey: .skills) ?? AgentSkillSettings()
    }
}

public struct AgentConfigUpdateRequest: Codable, Sendable {
    public var role: String?
    public var selectedModel: String?
    public var plannerModel: String?
    public var reasoningEffort: ReasoningEffort?
    public var automaticModelRouting: Bool?
    public var autoApproveInput: Bool?
    public var documents: AgentDocumentBundle
    public var heartbeat: AgentHeartbeatSettings
    public var channelSessions: AgentChannelSessionSettings
    public var runtime: AgentRuntimeConfig
    public var skills: AgentSkillSettings

    public init(
        role: String?,
        selectedModel: String?,
        plannerModel: String? = nil,
        documents: AgentDocumentBundle,
        heartbeat: AgentHeartbeatSettings = AgentHeartbeatSettings(),
        channelSessions: AgentChannelSessionSettings = AgentChannelSessionSettings(),
        reasoningEffort: ReasoningEffort? = nil,
        automaticModelRouting: Bool? = nil,
        autoApproveInput: Bool? = nil,
        runtime: AgentRuntimeConfig = AgentRuntimeConfig(),
        skills: AgentSkillSettings = AgentSkillSettings()
    ) {
        self.role = role
        self.selectedModel = selectedModel
        self.plannerModel = plannerModel
        self.reasoningEffort = reasoningEffort
        self.automaticModelRouting = automaticModelRouting
        self.autoApproveInput = autoApproveInput
        self.documents = documents
        self.heartbeat = heartbeat
        self.channelSessions = channelSessions
        self.runtime = runtime
        self.skills = skills
    }

    enum CodingKeys: String, CodingKey {
        case role, selectedModel, plannerModel, reasoningEffort, automaticModelRouting, autoApproveInput, documents, heartbeat, channelSessions, runtime, skills
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        selectedModel = try container.decodeIfPresent(String.self, forKey: .selectedModel)
        plannerModel = try container.decodeIfPresent(String.self, forKey: .plannerModel)
        reasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort)
        automaticModelRouting = try container.decodeIfPresent(Bool.self, forKey: .automaticModelRouting)
        autoApproveInput = try container.decodeIfPresent(Bool.self, forKey: .autoApproveInput)
        documents = try container.decode(AgentDocumentBundle.self, forKey: .documents)
        heartbeat = try container.decodeIfPresent(AgentHeartbeatSettings.self, forKey: .heartbeat) ?? AgentHeartbeatSettings()
        channelSessions = try container.decodeIfPresent(AgentChannelSessionSettings.self, forKey: .channelSessions) ?? AgentChannelSessionSettings()
        runtime = try container.decodeIfPresent(AgentRuntimeConfig.self, forKey: .runtime) ?? .init()
        skills = try container.decodeIfPresent(AgentSkillSettings.self, forKey: .skills) ?? AgentSkillSettings()
    }
}

public struct ACPTargetProbeRequest: Codable, Sendable {
    public var target: ACPProbeTarget

    public init(target: ACPProbeTarget) {
        self.target = target
    }
}

public struct ACPProbeTarget: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var transport: String
    public var command: String?
    public var arguments: [String]
    public var host: String?
    public var user: String?
    public var port: Int?
    public var identityFile: String?
    public var strictHostKeyChecking: Bool
    public var remoteCommand: String?
    public var url: String?
    public var headers: [String: String]
    public var cwd: String?
    public var environment: [String: String]
    public var timeoutMs: Int
    public var enabled: Bool
    public var permissionMode: String

    public init(
        id: String,
        title: String,
        transport: String = "stdio",
        command: String? = nil,
        arguments: [String] = [],
        host: String? = nil,
        user: String? = nil,
        port: Int? = nil,
        identityFile: String? = nil,
        strictHostKeyChecking: Bool = true,
        remoteCommand: String? = nil,
        url: String? = nil,
        headers: [String: String] = [:],
        cwd: String? = nil,
        environment: [String: String] = [:],
        timeoutMs: Int = 30_000,
        enabled: Bool = true,
        permissionMode: String = "allow_once"
    ) {
        self.id = id
        self.title = title
        self.transport = transport
        self.command = command
        self.arguments = arguments
        self.host = host
        self.user = user
        self.port = port
        self.identityFile = identityFile
        self.strictHostKeyChecking = strictHostKeyChecking
        self.remoteCommand = remoteCommand
        self.url = url
        self.headers = headers
        self.cwd = cwd
        self.environment = environment
        self.timeoutMs = timeoutMs
        self.enabled = enabled
        self.permissionMode = permissionMode
    }
}

public struct ACPTargetProbeResponse: Codable, Sendable, Equatable {
    public var ok: Bool
    public var targetId: String
    public var targetTitle: String
    public var agentName: String?
    public var agentVersion: String?
    public var supportsSessionList: Bool
    public var supportsLoadSession: Bool
    public var supportsPromptImage: Bool
    public var supportsMCPHTTP: Bool
    public var supportsMCPSSE: Bool
    public var message: String

    public init(
        ok: Bool,
        targetId: String,
        targetTitle: String,
        agentName: String? = nil,
        agentVersion: String? = nil,
        supportsSessionList: Bool = false,
        supportsLoadSession: Bool = false,
        supportsPromptImage: Bool = false,
        supportsMCPHTTP: Bool = false,
        supportsMCPSSE: Bool = false,
        message: String
    ) {
        self.ok = ok
        self.targetId = targetId
        self.targetTitle = targetTitle
        self.agentName = agentName
        self.agentVersion = agentVersion
        self.supportsSessionList = supportsSessionList
        self.supportsLoadSession = supportsLoadSession
        self.supportsPromptImage = supportsPromptImage
        self.supportsMCPHTTP = supportsMCPHTTP
        self.supportsMCPSSE = supportsMCPSSE
        self.message = message
    }
}

public struct AgentTokenUsageResponse: Codable, Sendable, Equatable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cachedTokens: Int
    public var cacheCreationTokens: Int
    public var reasoningTokens: Int
    public var totalCostUSD: Double

    public init(
        inputTokens: Int,
        outputTokens: Int,
        cachedTokens: Int,
        cacheCreationTokens: Int = 0,
        reasoningTokens: Int = 0,
        totalCostUSD: Double
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.reasoningTokens = reasoningTokens
        self.totalCostUSD = totalCostUSD
    }
}

/// Slash menu entries for agent chat (channel builtins + per-agent skills).
public struct AgentChatSlashCommandItem: Codable, Sendable, Equatable {
    /// `"channel"` (shared plugin commands) or `"skill"`.
    public var source: String
    public var name: String
    public var description: String
    public var argument: String?
    /// Set when `source == "skill"` (original `owner/repo` id).
    public var skillId: String?
    public var displayName: String?
    public var owner: String?
    public var repo: String?
    public var disambiguated: Bool?

    public init(
        source: String,
        name: String,
        description: String,
        argument: String? = nil,
        skillId: String? = nil,
        displayName: String? = nil,
        owner: String? = nil,
        repo: String? = nil,
        disambiguated: Bool? = nil
    ) {
        self.source = source
        self.name = name
        self.description = description
        self.argument = argument
        self.skillId = skillId
        self.displayName = displayName
        self.owner = owner
        self.repo = repo
        self.disambiguated = disambiguated
    }
}

public struct AgentChatSlashCommandsResponse: Codable, Sendable, Equatable {
    public var commands: [AgentChatSlashCommandItem]

    public init(commands: [AgentChatSlashCommandItem]) {
        self.commands = commands
    }
}
