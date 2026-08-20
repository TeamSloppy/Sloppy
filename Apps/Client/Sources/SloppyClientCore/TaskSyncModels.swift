import Foundation

public enum APITaskSyncSourceKind: String, Codable, Sendable, Equatable, CaseIterable {
    case queue
    case query
    case savedFilter = "saved_filter"
}

public struct APIProjectTaskSyncSource: Codable, Sendable, Equatable {
    public var kind: APITaskSyncSourceKind
    public var value: String
    public var displayName: String?
    public var url: String?

    public init(kind: APITaskSyncSourceKind, value: String, displayName: String? = nil, url: String? = nil) {
        self.kind = kind
        self.value = value
        self.displayName = displayName
        self.url = url
    }
}

public struct APITaskExternalStatus: Codable, Sendable, Equatable {
    public var key: String
    public var display: String
    public var type: String?
}

public struct APITaskExternalMetadata: Codable, Sendable, Equatable {
    public var providerId: String?
    public var externalIssueId: String?
    public var externalIssueNumber: Int?
    public var externalIssueURL: String?
    public var externalIssueKey: String?
    public var externalCommentId: String?
    public var externalStatus: APITaskExternalStatus?
    public var externalAssignee: String?
    public var externalPriority: String?
    public var externalVersion: Int?
    public var origin: String?
    public var syncState: String?
    public var lastSyncedAt: Date?
}

public struct APIProjectTaskSyncSchedule: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var intervalMinutes: Int
    public var lastRunAt: Date?

    public init(enabled: Bool = true, intervalMinutes: Int = 5, lastRunAt: Date? = nil) {
        self.enabled = enabled
        self.intervalMinutes = intervalMinutes
        self.lastRunAt = lastRunAt
    }
}

public struct APIProjectTaskSyncHealth: Codable, Sendable, Equatable {
    public var status: String
    public var message: String?
    public var checkedAt: Date?

    public init(status: String = "unknown", message: String? = nil, checkedAt: Date? = nil) {
        self.status = status
        self.message = message
        self.checkedAt = checkedAt
    }
}

public struct APIProjectTaskSyncSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var providerId: String?
    public var source: APIProjectTaskSyncSource?
    public var statusMappings: [String: String]
    public var inboundStatusMappings: [String: String]
    public var syncSchedule: APIProjectTaskSyncSchedule
    public var health: APIProjectTaskSyncHealth

    private enum CodingKeys: String, CodingKey {
        case enabled, providerId, source, statusMappings, inboundStatusMappings, syncSchedule, health
    }

    public init(
        enabled: Bool = false,
        providerId: String? = nil,
        source: APIProjectTaskSyncSource? = nil,
        statusMappings: [String: String] = [:],
        inboundStatusMappings: [String: String] = [:],
        syncSchedule: APIProjectTaskSyncSchedule = .init(),
        health: APIProjectTaskSyncHealth = .init(status: "unknown", message: nil, checkedAt: nil)
    ) {
        self.enabled = enabled
        self.providerId = providerId
        self.source = source
        self.statusMappings = statusMappings
        self.inboundStatusMappings = inboundStatusMappings
        self.syncSchedule = syncSchedule
        self.health = health
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        providerId = try container.decodeIfPresent(String.self, forKey: .providerId)
        source = try container.decodeIfPresent(APIProjectTaskSyncSource.self, forKey: .source)
        statusMappings = try container.decodeIfPresent([String: String].self, forKey: .statusMappings) ?? [:]
        inboundStatusMappings = try container.decodeIfPresent([String: String].self, forKey: .inboundStatusMappings) ?? [:]
        syncSchedule = try container.decodeIfPresent(APIProjectTaskSyncSchedule.self, forKey: .syncSchedule) ?? .init()
        health = try container.decodeIfPresent(APIProjectTaskSyncHealth.self, forKey: .health)
            ?? .init(status: "unknown", message: nil, checkedAt: nil)
    }
}

public struct APITaskSyncProviderDescriptor: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var sourceKinds: [APITaskSyncSourceKind]
    public var capabilities: [String]
}

public struct APIProjectTaskSyncDiscoverRequest: Codable, Sendable {
    public var providerId: String
    public var tokenMode: String
    public var source: APIProjectTaskSyncSource

    public init(providerId: String = "startrek", tokenMode: String = "override", source: APIProjectTaskSyncSource) {
        self.providerId = providerId
        self.tokenMode = tokenMode
        self.source = source
    }
}

public struct APIProjectTaskSyncDiscoveryResponse: Codable, Sendable, Equatable {
    public var providerId: String
    public var statusOptions: [String]
    public var message: String?
}

public struct APIProjectTaskSyncLinkRequest: Codable, Sendable {
    public var providerId: String
    public var tokenMode: String
    public var source: APIProjectTaskSyncSource
    public var statusMappings: [String: String]
    public var inboundStatusMappings: [String: String]
    public var syncSchedule: APIProjectTaskSyncSchedule

    public init(
        providerId: String = "startrek",
        tokenMode: String = "override",
        source: APIProjectTaskSyncSource,
        statusMappings: [String: String] = [:],
        inboundStatusMappings: [String: String] = [:],
        syncSchedule: APIProjectTaskSyncSchedule = .init()
    ) {
        self.providerId = providerId
        self.tokenMode = tokenMode
        self.source = source
        self.statusMappings = statusMappings
        self.inboundStatusMappings = inboundStatusMappings
        self.syncSchedule = syncSchedule
    }
}

public struct APIProjectTaskSyncResponse: Codable, Sendable {
    public var project: APIProjectRecord
    public var settings: APIProjectTaskSyncSettings
}

public struct APIProjectTaskSyncNowResponse: Codable, Sendable, Equatable {
    public var imported: Int
    public var updated: Int
    public var skipped: Int
    public var message: String?
}

public struct APIProjectTaskSyncTokenStatus: Codable, Sendable, Equatable {
    public var tokenMode: String
    public var hasOverrideToken: Bool
    public var maskedToken: String?
}

public struct APITaskComment: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var taskId: String
    public var content: String
    public var authorActorId: String
    public var externalMetadata: APITaskExternalMetadata?
    public var sourceAuthor: String?
    public var createdAt: Date
}
