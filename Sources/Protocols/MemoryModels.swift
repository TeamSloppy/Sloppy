import Foundation

public enum MemoryClass: String, Codable, Sendable, CaseIterable {
    case episodic
    case semantic
    case procedural
    case bulletin
}

public enum MemoryKind: String, Codable, Sendable, CaseIterable {
    case identity
    case goal
    case decision
    case todo
    case preference
    case fact
    case event
    case observation
}

public enum MemoryScopeType: String, Codable, Sendable, CaseIterable {
    case global
    case project
    case channel
    case agent
}

public struct MemoryScope: Codable, Sendable, Equatable {
    public var type: MemoryScopeType
    public var id: String
    public var channelId: String?
    public var projectId: String?
    public var agentId: String?

    public init(
        type: MemoryScopeType,
        id: String,
        channelId: String? = nil,
        projectId: String? = nil,
        agentId: String? = nil
    ) {
        self.type = type
        self.id = id
        self.channelId = channelId
        self.projectId = projectId
        self.agentId = agentId
    }

    public static func channel(_ channelId: String) -> MemoryScope {
        MemoryScope(type: .channel, id: channelId, channelId: channelId)
    }

    public static func project(_ projectId: String) -> MemoryScope {
        MemoryScope(type: .project, id: projectId, projectId: projectId)
    }

    public static func agent(_ agentId: String) -> MemoryScope {
        MemoryScope(type: .agent, id: agentId, agentId: agentId)
    }

    public static let `default` = MemoryScope(type: .global, id: "global")
}

public struct MemorySource: Codable, Sendable, Equatable {
    public var type: String
    public var id: String?

    public init(type: String, id: String? = nil) {
        self.type = type
        self.id = id
    }
}

public struct MemoryWriteRequest: Codable, Sendable, Equatable {
    public var note: String
    public var summary: String?
    public var kind: MemoryKind?
    public var memoryClass: MemoryClass?
    public var scope: MemoryScope?
    public var source: MemorySource?
    public var importance: Double?
    public var confidence: Double?
    public var metadata: [String: JSONValue]
    public var expiresAt: Date?
    /// Optional backdating for restored/imported entries. Nil = use current time.
    public var updatedAt: Date?

    public init(
        note: String,
        summary: String? = nil,
        kind: MemoryKind? = nil,
        memoryClass: MemoryClass? = nil,
        scope: MemoryScope? = nil,
        source: MemorySource? = nil,
        importance: Double? = nil,
        confidence: Double? = nil,
        metadata: [String: JSONValue] = [:],
        expiresAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.note = note
        self.summary = summary
        self.kind = kind
        self.memoryClass = memoryClass
        self.scope = scope
        self.source = source
        self.importance = importance
        self.confidence = confidence
        self.metadata = metadata
        self.expiresAt = expiresAt
        self.updatedAt = updatedAt
    }
}

public struct MemoryRecallRequest: Codable, Sendable, Equatable {
    public var query: String
    public var limit: Int
    public var scope: MemoryScope?
    public var kinds: [MemoryKind]
    public var classes: [MemoryClass]

    public init(
        query: String,
        limit: Int = 8,
        scope: MemoryScope? = nil,
        kinds: [MemoryKind] = [],
        classes: [MemoryClass] = []
    ) {
        self.query = query
        self.limit = limit
        self.scope = scope
        self.kinds = kinds
        self.classes = classes
    }
}

public struct MemoryHit: Codable, Sendable, Equatable {
    public var ref: MemoryRef
    public var note: String
    public var summary: String?
    /// What the fact is about, when the writer named one (see ``MemoryTopic``).
    public var topic: String?

    public init(ref: MemoryRef, note: String, summary: String? = nil, topic: String? = nil) {
        self.ref = ref
        self.note = note
        self.summary = summary
        self.topic = topic
    }
}

/// A short stable name for what a fact is about (for example "billing service deploy key id"). Saving a fact again
/// with the same topic in the same scope replaces the earlier entry, which makes a correction one typed step instead of
/// a search-then-update protocol. Matching is exact after normalization; nothing is inferred from the note text.
public enum MemoryTopic {
    public static let metadataKey = "topic"
    public static let maxLength = 80

    /// The display form: trimmed, single-spaced, bounded. Nil when nothing usable is left.
    public static func display(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maxLength))
    }

    /// The comparison key: case-folded alphanumeric words in their original order.
    public static func key(_ raw: String) -> String {
        raw.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }
}

public struct MemoryEdgeRecord: Codable, Sendable, Equatable {
    public var fromMemoryId: String
    public var toMemoryId: String
    public var relation: MemoryEdgeRelation
    public var weight: Double
    public var provenance: String?
    public var createdAt: Date

    public init(
        fromMemoryId: String,
        toMemoryId: String,
        relation: MemoryEdgeRelation,
        weight: Double = 1.0,
        provenance: String? = nil,
        createdAt: Date = Date()
    ) {
        self.fromMemoryId = fromMemoryId
        self.toMemoryId = toMemoryId
        self.relation = relation
        self.weight = weight
        self.provenance = provenance
        self.createdAt = createdAt
    }
}

public enum MemoryEdgeRelation: String, Codable, Sendable, CaseIterable {
    case supports
    case contradicts
    case dependsOn = "depends_on"
    case about
    case derivedFrom = "derived_from"
    case supersedes
}

public struct MemoryEdgeWriteRequest: Codable, Sendable, Equatable {
    public var fromMemoryId: String
    public var toMemoryId: String
    public var relation: MemoryEdgeRelation
    public var weight: Double
    public var provenance: String?

    public init(
        fromMemoryId: String,
        toMemoryId: String,
        relation: MemoryEdgeRelation,
        weight: Double = 1.0,
        provenance: String? = nil
    ) {
        self.fromMemoryId = fromMemoryId
        self.toMemoryId = toMemoryId
        self.relation = relation
        self.weight = weight
        self.provenance = provenance
    }
}

public struct MemoryEntryFilter: Codable, Sendable, Equatable {
    public var scope: MemoryScope?
    public var kinds: [MemoryKind]
    public var classes: [MemoryClass]
    public var includeDeleted: Bool
    public var includeExpired: Bool
    public var limit: Int?

    public init(
        scope: MemoryScope? = nil,
        kinds: [MemoryKind] = [],
        classes: [MemoryClass] = [],
        includeDeleted: Bool = false,
        includeExpired: Bool = false,
        limit: Int? = nil
    ) {
        self.scope = scope
        self.kinds = kinds
        self.classes = classes
        self.includeDeleted = includeDeleted
        self.includeExpired = includeExpired
        self.limit = limit
    }

    public static let `default` = MemoryEntryFilter()
}
