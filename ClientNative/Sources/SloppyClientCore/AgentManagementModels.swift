import Foundation

public struct AgentTokenUsageResponse: Codable, Sendable, Equatable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cachedTokens: Int
    public var cacheCreationTokens: Int
    public var reasoningTokens: Int
    public var totalCostUSD: Double

    public var totalTokens: Int { inputTokens + outputTokens }

    public init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cachedTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        reasoningTokens: Int = 0,
        totalCostUSD: Double = 0
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.reasoningTokens = reasoningTokens
        self.totalCostUSD = totalCostUSD
    }
}

public struct SkillRegistryItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var owner: String
    public var repo: String
    public var name: String
    public var description: String?
    public var installs: Int
    public var githubUrl: String

    public init(
        id: String,
        owner: String,
        repo: String,
        name: String,
        description: String? = nil,
        installs: Int = 0,
        githubUrl: String = ""
    ) {
        self.id = id
        self.owner = owner
        self.repo = repo
        self.name = name
        self.description = description
        self.installs = installs
        self.githubUrl = githubUrl
    }
}

public struct SkillsRegistryResponse: Codable, Sendable, Equatable {
    public var skills: [SkillRegistryItem]
    public var total: Int

    public init(skills: [SkillRegistryItem] = [], total: Int = 0) {
        self.skills = skills
        self.total = total
    }
}

public struct InstalledAgentSkill: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var owner: String
    public var repo: String
    public var name: String
    public var description: String?
    public var installedAt: Date
    public var version: String?
    public var localPath: String
    public var userInvocable: Bool
    public var allowedTools: [String]
    public var context: String?
    public var agent: String?
    public var autoRoute: String?

    public init(
        id: String,
        owner: String,
        repo: String,
        name: String,
        description: String? = nil,
        installedAt: Date = Date(),
        version: String? = nil,
        localPath: String = "",
        userInvocable: Bool = true,
        allowedTools: [String] = [],
        context: String? = nil,
        agent: String? = nil,
        autoRoute: String? = nil
    ) {
        self.id = id
        self.owner = owner
        self.repo = repo
        self.name = name
        self.description = description
        self.installedAt = installedAt
        self.version = version
        self.localPath = localPath
        self.userInvocable = userInvocable
        self.allowedTools = allowedTools
        self.context = context
        self.agent = agent
        self.autoRoute = autoRoute
    }

    private enum CodingKeys: String, CodingKey {
        case id, owner, repo, name, description, installedAt, version, localPath
        case userInvocable, allowedTools, context, agent, autoRoute
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        owner = try container.decode(String.self, forKey: .owner)
        repo = try container.decode(String.self, forKey: .repo)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        installedAt = try container.decode(Date.self, forKey: .installedAt)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        localPath = try container.decodeIfPresent(String.self, forKey: .localPath) ?? ""
        userInvocable = try container.decodeIfPresent(Bool.self, forKey: .userInvocable) ?? true
        allowedTools = try container.decodeIfPresent([String].self, forKey: .allowedTools) ?? []
        context = try container.decodeIfPresent(String.self, forKey: .context)
        agent = try container.decodeIfPresent(String.self, forKey: .agent)
        autoRoute = try container.decodeIfPresent(String.self, forKey: .autoRoute)
    }
}

public struct AgentSkillsResponse: Codable, Sendable, Equatable {
    public var agentId: String
    public var skills: [InstalledAgentSkill]
    public var skillsPath: String

    public init(agentId: String, skills: [InstalledAgentSkill] = [], skillsPath: String = "") {
        self.agentId = agentId
        self.skills = skills
        self.skillsPath = skillsPath
    }
}

public struct AgentSkillInstallRequest: Codable, Sendable, Equatable {
    public var owner: String
    public var repo: String
    public var localPath: String?

    public init(owner: String = "", repo: String = "", localPath: String? = nil) {
        self.owner = owner
        self.repo = repo
        self.localPath = localPath
    }
}
