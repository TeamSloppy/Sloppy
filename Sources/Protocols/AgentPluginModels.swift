import Foundation

// MARK: - Agent Plugin Package Manifest

public struct AgentPluginManifest: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var version: String
    public var description: String?
    public var minimumSloppyVersion: String?
    public var platforms: [AgentPluginPlatform]
    public var inputs: [AgentPluginInput]
    public var components: AgentPluginComponents

    public init(
        schemaVersion: Int = 1,
        id: String,
        name: String,
        version: String,
        description: String? = nil,
        minimumSloppyVersion: String? = nil,
        platforms: [AgentPluginPlatform] = [],
        inputs: [AgentPluginInput] = [],
        components: AgentPluginComponents = .init()
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.minimumSloppyVersion = minimumSloppyVersion
        self.platforms = platforms
        self.inputs = inputs
        self.components = components
    }
}

public struct AgentPluginPlatform: Codable, Sendable, Equatable {
    public var os: String
    public var architectures: [String]

    public init(os: String, architectures: [String] = []) {
        self.os = os
        self.architectures = architectures
    }
}

public struct AgentPluginInput: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case string, boolean, choice, secret }
    public var id: String
    public var title: String
    public var description: String?
    public var kind: Kind
    public var required: Bool
    public var defaultValue: String?
    public var choices: [String]

    public init(id: String, title: String, description: String? = nil, kind: Kind = .string, required: Bool = false, defaultValue: String? = nil, choices: [String] = []) {
        self.id = id
        self.title = title
        self.description = description
        self.kind = kind
        self.required = required
        self.defaultValue = defaultValue
        self.choices = choices
    }
}

public struct AgentPluginComponents: Codable, Sendable, Equatable {
    public var skills: [AgentPluginSkillComponent]
    public var mcpServers: [AgentPluginMCPComponent]
    public var sloppyPlugins: [AgentPluginSloppyComponent]
    public var software: [AgentPluginSoftwareComponent]

    public init(skills: [AgentPluginSkillComponent] = [], mcpServers: [AgentPluginMCPComponent] = [], sloppyPlugins: [AgentPluginSloppyComponent] = [], software: [AgentPluginSoftwareComponent] = []) {
        self.skills = skills
        self.mcpServers = mcpServers
        self.sloppyPlugins = sloppyPlugins
        self.software = software
    }

    private enum CodingKeys: String, CodingKey { case skills, mcpServers, sloppyPlugins, software }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skills = try container.decodeIfPresent([AgentPluginSkillComponent].self, forKey: .skills) ?? []
        mcpServers = try container.decodeIfPresent([AgentPluginMCPComponent].self, forKey: .mcpServers) ?? []
        sloppyPlugins = try container.decodeIfPresent([AgentPluginSloppyComponent].self, forKey: .sloppyPlugins) ?? []
        software = try container.decodeIfPresent([AgentPluginSoftwareComponent].self, forKey: .software) ?? []
    }
}

public struct AgentPluginSkillComponent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var path: String
    public init(id: String, path: String) { self.id = id; self.path = path }
}

public struct AgentPluginMCPComponent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var transport: String
    public var command: String?
    public var arguments: [String]
    public var cwd: String?
    public var endpoint: String?
    public var headers: [String: String]
    public var environment: [String: String]
    public var timeoutMs: Int
    public var enabled: Bool
    public var exposeTools: Bool
    public var exposeResources: Bool
    public var exposePrompts: Bool
    public var toolPrefix: String?

    public init(id: String, transport: String = "stdio", command: String? = nil, arguments: [String] = [], cwd: String? = nil, endpoint: String? = nil, headers: [String: String] = [:], environment: [String: String] = [:], timeoutMs: Int = 15_000, enabled: Bool = true, exposeTools: Bool = true, exposeResources: Bool = true, exposePrompts: Bool = true, toolPrefix: String? = nil) {
        self.id = id; self.transport = transport; self.command = command; self.arguments = arguments
        self.cwd = cwd; self.endpoint = endpoint; self.headers = headers; self.environment = environment
        self.timeoutMs = timeoutMs; self.enabled = enabled; self.exposeTools = exposeTools
        self.exposeResources = exposeResources; self.exposePrompts = exposePrompts; self.toolPrefix = toolPrefix
    }

    private enum CodingKeys: String, CodingKey { case id, transport, command, arguments, cwd, endpoint, headers, environment, timeoutMs, enabled, exposeTools, exposeResources, exposePrompts, toolPrefix }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        transport = try c.decodeIfPresent(String.self, forKey: .transport) ?? "stdio"
        command = try c.decodeIfPresent(String.self, forKey: .command)
        arguments = try c.decodeIfPresent([String].self, forKey: .arguments) ?? []
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint)
        headers = try c.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        environment = try c.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        timeoutMs = try c.decodeIfPresent(Int.self, forKey: .timeoutMs) ?? 15_000
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        exposeTools = try c.decodeIfPresent(Bool.self, forKey: .exposeTools) ?? true
        exposeResources = try c.decodeIfPresent(Bool.self, forKey: .exposeResources) ?? true
        exposePrompts = try c.decodeIfPresent(Bool.self, forKey: .exposePrompts) ?? true
        toolPrefix = try c.decodeIfPresent(String.self, forKey: .toolPrefix)
    }
}

public struct AgentPluginSloppyComponent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var path: String
    public init(id: String, path: String) { self.id = id; self.path = path }
}

public struct AgentPluginSoftwareComponent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var platforms: [AgentPluginPlatform]
    public var check: [AgentPluginCommand]
    public var install: [AgentPluginCommand]
    public var uninstall: [AgentPluginCommand]
    public var rollback: [AgentPluginCommand]

    public init(id: String, platforms: [AgentPluginPlatform] = [], check: [AgentPluginCommand] = [], install: [AgentPluginCommand] = [], uninstall: [AgentPluginCommand], rollback: [AgentPluginCommand]) {
        self.id = id; self.platforms = platforms; self.check = check; self.install = install
        self.uninstall = uninstall; self.rollback = rollback
    }
}

public struct AgentPluginCommand: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var executable: String
    public var arguments: [String]
    public var cwd: String?
    public var environment: [String: String]
    public var timeoutSeconds: Int

    public init(id: String, executable: String, arguments: [String] = [], cwd: String? = nil, environment: [String: String] = [:], timeoutSeconds: Int = 300) {
        self.id = id; self.executable = executable; self.arguments = arguments
        self.cwd = cwd; self.environment = environment; self.timeoutSeconds = timeoutSeconds
    }
}

// MARK: - Package Sources and Registry

public struct AgentPluginSource: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case upload, url, registry }
    public var kind: Kind
    public var uploadId: String?
    public var url: String?
    public var registryId: String?
    public var packageId: String?
    public var version: String?
    public var expectedSHA256: String?

    public init(kind: Kind, uploadId: String? = nil, url: String? = nil, registryId: String? = nil, packageId: String? = nil, version: String? = nil, expectedSHA256: String? = nil) {
        self.kind = kind; self.uploadId = uploadId; self.url = url; self.registryId = registryId
        self.packageId = packageId; self.version = version; self.expectedSHA256 = expectedSHA256
    }
}

public struct AgentPluginRegistry: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var baseURL: String
    public var enabled: Bool
    public var isDefault: Bool
    public init(id: String, name: String, baseURL: String, enabled: Bool = true, isDefault: Bool = false) {
        self.id = id; self.name = name; self.baseURL = baseURL; self.enabled = enabled; self.isDefault = isDefault
    }
}

public struct AgentPluginRegistryRelease: Codable, Sendable, Equatable, Identifiable {
    public var version: String
    public var downloadURL: String
    public var sha256: String
    public var size: Int64
    public var minimumSloppyVersion: String?
    public var platforms: [AgentPluginPlatform]
    public var prerelease: Bool
    public var id: String { version }

    public init(version: String, downloadURL: String, sha256: String, size: Int64, minimumSloppyVersion: String? = nil, platforms: [AgentPluginPlatform] = [], prerelease: Bool = false) {
        self.version = version; self.downloadURL = downloadURL; self.sha256 = sha256; self.size = size
        self.minimumSloppyVersion = minimumSloppyVersion; self.platforms = platforms; self.prerelease = prerelease
    }

    private enum CodingKeys: String, CodingKey { case version, downloadURL, sha256, size, minimumSloppyVersion, platforms, prerelease }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(String.self, forKey: .version)
        downloadURL = try c.decode(String.self, forKey: .downloadURL)
        sha256 = try c.decode(String.self, forKey: .sha256)
        size = try c.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        minimumSloppyVersion = try c.decodeIfPresent(String.self, forKey: .minimumSloppyVersion)
        platforms = try c.decodeIfPresent([AgentPluginPlatform].self, forKey: .platforms) ?? []
        prerelease = try c.decodeIfPresent(Bool.self, forKey: .prerelease) ?? version.contains("-")
    }
}

public struct AgentPluginCatalogItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var registryId: String
    public var name: String
    public var description: String?
    public var publisher: String?
    public var latestVersion: String
    public var releases: [AgentPluginRegistryRelease]

    public init(id: String, registryId: String, name: String, description: String? = nil, publisher: String? = nil, latestVersion: String, releases: [AgentPluginRegistryRelease] = []) {
        self.id = id; self.registryId = registryId; self.name = name; self.description = description
        self.publisher = publisher; self.latestVersion = latestVersion; self.releases = releases
    }

    private enum CodingKeys: String, CodingKey { case id, registryId, name, description, publisher, latestVersion, releases }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        registryId = try c.decodeIfPresent(String.self, forKey: .registryId) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        description = try c.decodeIfPresent(String.self, forKey: .description)
        publisher = try c.decodeIfPresent(String.self, forKey: .publisher)
        latestVersion = try c.decode(String.self, forKey: .latestVersion)
        releases = try c.decodeIfPresent([AgentPluginRegistryRelease].self, forKey: .releases) ?? []
    }
}

public struct AgentPluginCatalogResponse: Codable, Sendable, Equatable {
    public var packages: [AgentPluginCatalogItem]
    public var nextCursor: String?
    public var warnings: [String]
    public init(packages: [AgentPluginCatalogItem], nextCursor: String? = nil, warnings: [String] = []) {
        self.packages = packages; self.nextCursor = nextCursor; self.warnings = warnings
    }

    private enum CodingKeys: String, CodingKey { case packages, nextCursor, warnings }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        packages = try c.decodeIfPresent([AgentPluginCatalogItem].self, forKey: .packages) ?? []
        nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor)
        warnings = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}

// MARK: - Inspection, Planning, and Operations

public struct AgentPluginUpload: Codable, Sendable, Equatable {
    public var id: String
    public var sha256: String
    public var size: Int64
    public var expiresAt: Date

    public init(id: String, sha256: String, size: Int64, expiresAt: Date) {
        self.id = id; self.sha256 = sha256; self.size = size; self.expiresAt = expiresAt
    }
}

public struct AgentPluginInspectionRequest: Codable, Sendable, Equatable {
    public var source: AgentPluginSource
    public init(source: AgentPluginSource) { self.source = source }
}

public struct AgentPluginInspection: Codable, Sendable, Equatable, Identifiable {
    public enum Trust: String, Codable, Sendable { case verifiedChecksum = "verified_checksum", unverified }
    public var id: String
    public var source: AgentPluginSource
    public var manifest: AgentPluginManifest
    public var sha256: String
    public var size: Int64
    public var trust: Trust
    public var warnings: [String]
    public var expiresAt: Date

    public init(id: String, source: AgentPluginSource, manifest: AgentPluginManifest, sha256: String, size: Int64, trust: Trust, warnings: [String], expiresAt: Date) {
        self.id = id; self.source = source; self.manifest = manifest; self.sha256 = sha256
        self.size = size; self.trust = trust; self.warnings = warnings; self.expiresAt = expiresAt
    }
}

public struct AgentPluginPlanRequest: Codable, Sendable, Equatable {
    public var inspectionId: String
    public var agentIds: [String]
    public var inputs: [String: String]
    public init(inspectionId: String, agentIds: [String], inputs: [String: String]) {
        self.inspectionId = inspectionId; self.agentIds = agentIds; self.inputs = inputs
    }
}

public struct AgentPluginPlannedChange: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case skill, mcp, sloppyPlugin = "sloppy_plugin", software }
    public var id: String
    public var kind: Kind
    public var title: String
    public var detail: String

    public init(id: String, kind: Kind, title: String, detail: String) {
        self.id = id; self.kind = kind; self.title = title; self.detail = detail
    }
}

public struct AgentPluginInstallPlan: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var inspectionId: String
    public var packageId: String
    public var version: String
    public var sha256: String
    public var agentIds: [String]
    public var changes: [AgentPluginPlannedChange]
    public var commands: [AgentPluginCommand]
    public var warnings: [String]
    public var requiresTrustConfirmation: Bool
    public var requiresCommandApproval: Bool
    public var approvalHash: String
    public var expiresAt: Date

    public init(id: String, inspectionId: String, packageId: String, version: String, sha256: String, agentIds: [String], changes: [AgentPluginPlannedChange], commands: [AgentPluginCommand], warnings: [String], requiresTrustConfirmation: Bool, requiresCommandApproval: Bool, approvalHash: String, expiresAt: Date) {
        self.id = id; self.inspectionId = inspectionId; self.packageId = packageId; self.version = version
        self.sha256 = sha256; self.agentIds = agentIds; self.changes = changes; self.commands = commands
        self.warnings = warnings; self.requiresTrustConfirmation = requiresTrustConfirmation
        self.requiresCommandApproval = requiresCommandApproval; self.approvalHash = approvalHash; self.expiresAt = expiresAt
    }
}

public struct AgentPluginInstallRequest: Codable, Sendable, Equatable {
    public var planId: String
    public var approvalHash: String
    public var trustConfirmed: Bool
    public var commandsApproved: Bool
    public init(planId: String, approvalHash: String, trustConfirmed: Bool, commandsApproved: Bool) {
        self.planId = planId; self.approvalHash = approvalHash; self.trustConfirmed = trustConfirmed; self.commandsApproved = commandsApproved
    }
}

public struct AgentPluginUninstallPlanRequest: Codable, Sendable, Equatable {
    public var forceModifiedComponents: Bool
    public init(forceModifiedComponents: Bool = false) { self.forceModifiedComponents = forceModifiedComponents }
}

public struct InstalledAgentPlugin: Codable, Sendable, Equatable, Identifiable {
    public enum Status: String, Codable, Sendable { case installing, installed, failed, failedWithResiduals = "failed_with_residuals", uninstalling, uninstallFailed = "uninstall_failed" }
    public var id: String
    public var name: String
    public var version: String
    public var source: AgentPluginSource
    public var sha256: String
    public var status: Status
    public var agentIds: [String]
    public var manifest: AgentPluginManifest
    public var componentHashes: [String: String]
    public var configuration: [String: String]?
    public var installedAt: Date
    public var updatedAt: Date
    public var lastError: String?

    public init(id: String, name: String, version: String, source: AgentPluginSource, sha256: String, status: Status, agentIds: [String], manifest: AgentPluginManifest, componentHashes: [String: String], configuration: [String: String]? = nil, installedAt: Date, updatedAt: Date, lastError: String? = nil) {
        self.id = id; self.name = name; self.version = version; self.source = source; self.sha256 = sha256
        self.status = status; self.agentIds = agentIds; self.manifest = manifest; self.componentHashes = componentHashes; self.configuration = configuration
        self.installedAt = installedAt; self.updatedAt = updatedAt; self.lastError = lastError
    }
}

public struct AgentPluginOperation: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case install, update, reconfigure, uninstall }
    public enum Status: String, Codable, Sendable { case queued, running, completed, failed, failedWithResiduals = "failed_with_residuals" }
    public var id: String
    public var packageId: String
    public var kind: Kind
    public var status: Status
    public var progress: Double
    public var message: String
    public var startedAt: Date
    public var finishedAt: Date?

    public init(id: String, packageId: String, kind: Kind, status: Status, progress: Double, message: String, startedAt: Date, finishedAt: Date? = nil) {
        self.id = id; self.packageId = packageId; self.kind = kind; self.status = status
        self.progress = progress; self.message = message; self.startedAt = startedAt; self.finishedAt = finishedAt
    }
}

public struct AgentPluginRegistryWriteRequest: Codable, Sendable, Equatable {
    public var name: String
    public var baseURL: String
    public var enabled: Bool
    public var isDefault: Bool

    public init(name: String, baseURL: String, enabled: Bool = true, isDefault: Bool = false) {
        self.name = name; self.baseURL = baseURL; self.enabled = enabled; self.isDefault = isDefault
    }
}
