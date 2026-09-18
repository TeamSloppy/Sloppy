import Foundation

public struct ClientAgentPluginManifest: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var version: String
    public var description: String?
    public var inputs: [ClientAgentPluginInput]
    public var components: ClientAgentPluginComponents
}

public struct ClientAgentPluginInput: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var description: String?
    public var kind: String
    public var required: Bool
    public var defaultValue: String?
    public var choices: [String]
}

public struct ClientAgentPluginComponents: Codable, Sendable, Equatable {
    public var skills: [ClientAgentPluginComponent]
    public var mcpServers: [ClientAgentPluginComponent]
    public var sloppyPlugins: [ClientAgentPluginComponent]
    public var software: [ClientAgentPluginComponent]

    private enum CodingKeys: String, CodingKey { case skills, mcpServers, sloppyPlugins, software }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        skills = try c.decodeIfPresent([ClientAgentPluginComponent].self, forKey: .skills) ?? []
        mcpServers = try c.decodeIfPresent([ClientAgentPluginComponent].self, forKey: .mcpServers) ?? []
        sloppyPlugins = try c.decodeIfPresent([ClientAgentPluginComponent].self, forKey: .sloppyPlugins) ?? []
        software = try c.decodeIfPresent([ClientAgentPluginComponent].self, forKey: .software) ?? []
    }
}

public struct ClientAgentPluginComponent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
}

public struct ClientAgentPluginSource: Codable, Sendable, Equatable {
    public var kind: String
    public var uploadId: String?
    public var url: String?
    public var registryId: String?
    public var packageId: String?
    public var version: String?
    public var expectedSHA256: String?

    public init(kind: String, uploadId: String? = nil, url: String? = nil, registryId: String? = nil, packageId: String? = nil, version: String? = nil, expectedSHA256: String? = nil) {
        self.kind = kind; self.uploadId = uploadId; self.url = url; self.registryId = registryId
        self.packageId = packageId; self.version = version; self.expectedSHA256 = expectedSHA256
    }
}

public struct ClientAgentPluginUpload: Codable, Sendable, Equatable {
    public var id: String
    public var sha256: String
    public var size: Int64
    public var expiresAt: Date
}

public struct ClientAgentPluginInspection: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var source: ClientAgentPluginSource
    public var manifest: ClientAgentPluginManifest
    public var sha256: String
    public var size: Int64
    public var trust: String
    public var warnings: [String]
    public var expiresAt: Date
}

public struct ClientAgentPluginInspectionRequest: Codable, Sendable {
    public var source: ClientAgentPluginSource
    public init(source: ClientAgentPluginSource) { self.source = source }
}

public struct ClientAgentPluginPlanRequest: Codable, Sendable {
    public var inspectionId: String
    public var agentIds: [String]
    public var inputs: [String: String]
}

public struct ClientAgentPluginPlan: Codable, Sendable, Equatable, Identifiable {
    public struct Change: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var kind: String
        public var title: String
        public var detail: String
    }
    public struct Command: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var executable: String
        public var arguments: [String]
    }
    public var id: String
    public var inspectionId: String
    public var packageId: String
    public var version: String
    public var sha256: String
    public var agentIds: [String]
    public var changes: [Change]
    public var commands: [Command]
    public var warnings: [String]
    public var requiresTrustConfirmation: Bool
    public var requiresCommandApproval: Bool
    public var approvalHash: String
    public var expiresAt: Date
}

public struct ClientAgentPluginInstallRequest: Codable, Sendable {
    public var planId: String
    public var approvalHash: String
    public var trustConfirmed: Bool
    public var commandsApproved: Bool
}

public struct ClientInstalledAgentPlugin: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var version: String
    public var source: ClientAgentPluginSource
    public var sha256: String
    public var status: String
    public var agentIds: [String]
    public var manifest: ClientAgentPluginManifest
    public var installedAt: Date
    public var updatedAt: Date
    public var lastError: String?
}

public struct ClientAgentPluginOperation: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var packageId: String
    public var kind: String
    public var status: String
    public var progress: Double
    public var message: String
    public var startedAt: Date
    public var finishedAt: Date?
}

public struct ClientAgentPluginRegistry: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var baseURL: String
    public var enabled: Bool
    public var isDefault: Bool
}

public struct ClientAgentPluginRegistryWriteRequest: Codable, Sendable {
    public var name: String
    public var baseURL: String
    public var enabled: Bool
    public var isDefault: Bool

    public init(name: String, baseURL: String, enabled: Bool = true, isDefault: Bool = false) {
        self.name = name; self.baseURL = baseURL; self.enabled = enabled; self.isDefault = isDefault
    }
}

public struct ClientAgentPluginCatalogItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var registryId: String
    public var name: String
    public var description: String?
    public var publisher: String?
    public var latestVersion: String
}

public struct ClientAgentPluginCatalogResponse: Codable, Sendable, Equatable {
    public var packages: [ClientAgentPluginCatalogItem]
    public var nextCursor: String?
    public var warnings: [String]
}
