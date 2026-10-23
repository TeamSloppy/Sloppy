import Foundation

/// Skill information from skills.sh registry
public struct SkillInfo: Codable, Sendable, Equatable {
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
        githubUrl: String
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

/// Response from skills.sh registry API
public struct SkillsRegistryResponse: Codable, Sendable {
    public var skills: [SkillInfo]
    public var total: Int

    public init(skills: [SkillInfo], total: Int) {
        self.skills = skills
        self.total = total
    }
}

public enum SkillContext: String, Codable, Sendable, Equatable {
    case fork
}

/// Installed skill metadata stored locally
public struct InstalledSkill: Codable, Sendable, Equatable {
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
    public var context: SkillContext?
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
        localPath: String,
        userInvocable: Bool = true,
        allowedTools: [String] = [],
        context: SkillContext? = nil,
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

    enum CodingKeys: String, CodingKey {
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
        localPath = try container.decode(String.self, forKey: .localPath)
        userInvocable = try container.decodeIfPresent(Bool.self, forKey: .userInvocable) ?? true
        allowedTools = try container.decodeIfPresent([String].self, forKey: .allowedTools) ?? []
        context = try container.decodeIfPresent(SkillContext.self, forKey: .context)
        agent = try container.decodeIfPresent(String.self, forKey: .agent)
        autoRoute = try container.decodeIfPresent(String.self, forKey: .autoRoute)
    }
}

/// Request to install a skill from GitHub or a local skill directory.
public struct SkillInstallRequest: Codable, Sendable {
    public var owner: String
    public var repo: String
    public var version: String?
    /// Local directory containing a skill. When set, the skill is copied into the agent skills store.
    public var localPath: String?
    public var userInvocable: Bool?
    public var allowedTools: [String]?
    public var context: SkillContext?
    public var agent: String?
    public var autoRoute: String?

    enum CodingKeys: String, CodingKey {
        case owner, repo, version, localPath, userInvocable, allowedTools, context, agent, autoRoute
    }

    public init(
        owner: String = "",
        repo: String = "",
        version: String? = nil,
        localPath: String? = nil,
        userInvocable: Bool? = nil,
        allowedTools: [String]? = nil,
        context: SkillContext? = nil,
        agent: String? = nil,
        autoRoute: String? = nil
    ) {
        self.owner = owner
        self.repo = repo
        self.version = version
        self.localPath = localPath
        self.userInvocable = userInvocable
        self.allowedTools = allowedTools
        self.context = context
        self.agent = agent
        self.autoRoute = autoRoute
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        owner = try container.decodeIfPresent(String.self, forKey: .owner) ?? ""
        repo = try container.decodeIfPresent(String.self, forKey: .repo) ?? ""
        version = try container.decodeIfPresent(String.self, forKey: .version)
        localPath = try container.decodeIfPresent(String.self, forKey: .localPath)
        userInvocable = try container.decodeIfPresent(Bool.self, forKey: .userInvocable)
        allowedTools = try container.decodeIfPresent([String].self, forKey: .allowedTools)
        context = try container.decodeIfPresent(SkillContext.self, forKey: .context)
        agent = try container.decodeIfPresent(String.self, forKey: .agent)
        autoRoute = try container.decodeIfPresent(String.self, forKey: .autoRoute)
    }
}

/// Manifest file format for skills.json in agent's skills directory
public struct AgentSkillsManifest: Codable, Sendable {
    public var version: Int
    public var installedSkills: [InstalledSkill]

    public init(version: Int = 1, installedSkills: [InstalledSkill] = []) {
        self.version = version
        self.installedSkills = installedSkills
    }
}

/// Response for listing agent skills
public struct AgentSkillsResponse: Codable, Sendable {
    public var agentId: String
    public var skills: [InstalledSkill]
    public var skillsPath: String

    public init(agentId: String, skills: [InstalledSkill], skillsPath: String) {
        self.agentId = agentId
        self.skills = skills
        self.skillsPath = skillsPath
    }
}
