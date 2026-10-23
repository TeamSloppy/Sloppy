import Foundation

public enum AgentMemoryFilter: String, Codable, Sendable, CaseIterable {
    case all
    case persistent
    case temporary
    case todo
}

public enum AgentMemoryCategory: String, Codable, Sendable, CaseIterable {
    case persistent
    case temporary
    case todo
}

public struct AgentMemoryItem: Codable, Sendable, Equatable {
    public var id: String
    public var note: String
    public var summary: String?
    public var kind: MemoryKind
    public var memoryClass: MemoryClass
    public var scope: MemoryScope
    public var source: MemorySource?
    public var importance: Double
    public var confidence: Double
    public var createdAt: Date
    public var updatedAt: Date
    public var expiresAt: Date?
    public var derivedCategory: AgentMemoryCategory

    public init(
        id: String,
        note: String,
        summary: String? = nil,
        kind: MemoryKind,
        memoryClass: MemoryClass,
        scope: MemoryScope,
        source: MemorySource? = nil,
        importance: Double,
        confidence: Double,
        createdAt: Date,
        updatedAt: Date,
        expiresAt: Date? = nil,
        derivedCategory: AgentMemoryCategory
    ) {
        self.id = id
        self.note = note
        self.summary = summary
        self.kind = kind
        self.memoryClass = memoryClass
        self.scope = scope
        self.source = source
        self.importance = importance
        self.confidence = confidence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
        self.derivedCategory = derivedCategory
    }
}

public struct MemoryListResponse: Codable, Sendable, Equatable {
    public var items: [AgentMemoryItem]
    public var total: Int
    public var limit: Int
    public var offset: Int

    public init(items: [AgentMemoryItem], total: Int, limit: Int, offset: Int) {
        self.items = items
        self.total = total
        self.limit = limit
        self.offset = offset
    }
}

public struct AgentMemoryListResponse: Codable, Sendable, Equatable {
    public var agentId: String
    public var items: [AgentMemoryItem]
    public var total: Int
    public var limit: Int
    public var offset: Int

    public init(agentId: String, items: [AgentMemoryItem], total: Int, limit: Int, offset: Int) {
        self.agentId = agentId
        self.items = items
        self.total = total
        self.limit = limit
        self.offset = offset
    }
}

public struct AgentMemoryEdgeRecord: Codable, Sendable, Equatable {
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

public struct AgentMemoryGraphResponse: Codable, Sendable, Equatable {
    public var agentId: String
    public var nodes: [AgentMemoryItem]
    public var edges: [AgentMemoryEdgeRecord]
    public var seedIds: [String]
    public var truncated: Bool

    public init(
        agentId: String,
        nodes: [AgentMemoryItem],
        edges: [AgentMemoryEdgeRecord],
        seedIds: [String],
        truncated: Bool
    ) {
        self.agentId = agentId
        self.nodes = nodes
        self.edges = edges
        self.seedIds = seedIds
        self.truncated = truncated
    }
}

public struct ProjectMemoryListResponse: Codable, Sendable, Equatable {
    public var projectId: String
    public var items: [AgentMemoryItem]
    public var total: Int
    public var limit: Int
    public var offset: Int

    public init(projectId: String, items: [AgentMemoryItem], total: Int, limit: Int, offset: Int) {
        self.projectId = projectId
        self.items = items
        self.total = total
        self.limit = limit
        self.offset = offset
    }
}

public struct ProjectMemoryGraphResponse: Codable, Sendable, Equatable {
    public var projectId: String
    public var nodes: [AgentMemoryItem]
    public var edges: [AgentMemoryEdgeRecord]
    public var seedIds: [String]
    public var truncated: Bool

    public init(
        projectId: String,
        nodes: [AgentMemoryItem],
        edges: [AgentMemoryEdgeRecord],
        seedIds: [String],
        truncated: Bool
    ) {
        self.projectId = projectId
        self.nodes = nodes
        self.edges = edges
        self.seedIds = seedIds
        self.truncated = truncated
    }
}

public struct AgentMemoryUpdateRequest: Codable, Sendable, Equatable {
    public var note: String?
    public var summary: String?
    public var kind: MemoryKind?
    public var importance: Double?
    public var confidence: Double?

    public init(
        note: String? = nil,
        summary: String? = nil,
        kind: MemoryKind? = nil,
        importance: Double? = nil,
        confidence: Double? = nil
    ) {
        self.note = note
        self.summary = summary
        self.kind = kind
        self.importance = importance
        self.confidence = confidence
    }
}
