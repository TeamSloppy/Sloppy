import Foundation

public enum ActorKind: String, Codable, Sendable {
    case agent
    case human
    case action
}

public enum ActorLinkDirection: String, Codable, Sendable {
    case oneWay = "one_way"
    case twoWay = "two_way"
}

public enum ActorRelationshipType: String, Codable, Sendable {
    case hierarchical
    case peer
}

public enum ActorCommunicationType: String, Codable, Sendable {
    case chat
    case task
    case event
    case discussion
}

public enum ActorSocketPosition: String, Codable, Sendable {
    case top
    case right
    case bottom
    case left
}

public enum ActorSystemRole: String, Codable, Sendable {
    case manager
    case developer
    case qa
    case reviewer
    case custom
}

public struct ActorNode: Codable, Sendable, Equatable {
    public var id: String
    public var displayName: String
    public var kind: ActorKind
    public var linkedAgentId: String?
    public var channelId: String?
    public var role: String?
    public var systemRole: ActorSystemRole?
    public var positionX: Double
    public var positionY: Double
    public var createdAt: Date

    public init(
        id: String,
        displayName: String,
        kind: ActorKind,
        linkedAgentId: String? = nil,
        channelId: String? = nil,
        role: String? = nil,
        systemRole: ActorSystemRole? = nil,
        positionX: Double = 0,
        positionY: Double = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.linkedAgentId = linkedAgentId
        self.channelId = channelId
        self.role = role
        self.systemRole = systemRole
        self.positionX = positionX
        self.positionY = positionY
        self.createdAt = createdAt
    }
}

public struct ActorLink: Codable, Sendable, Equatable {
    public var id: String
    public var sourceActorId: String
    public var targetActorId: String
    public var direction: ActorLinkDirection
    public var relationship: ActorRelationshipType?
    public var communicationType: ActorCommunicationType
    public var sourceSocket: ActorSocketPosition?
    public var targetSocket: ActorSocketPosition?
    public var createdAt: Date

    public init(
        id: String,
        sourceActorId: String,
        targetActorId: String,
        direction: ActorLinkDirection,
        relationship: ActorRelationshipType? = nil,
        communicationType: ActorCommunicationType,
        sourceSocket: ActorSocketPosition? = nil,
        targetSocket: ActorSocketPosition? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceActorId = sourceActorId
        self.targetActorId = targetActorId
        self.direction = direction
        self.relationship = relationship
        self.communicationType = communicationType
        self.sourceSocket = sourceSocket
        self.targetSocket = targetSocket
        self.createdAt = createdAt
    }
}

public struct ActorTeam: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var memberActorIds: [String]
    /// An explicit empty array means no role; an absent entry preserves legacy system roles.
    public var memberRoles: [String: [ActorSystemRole]]
    public var createdAt: Date

    public init(
        id: String,
        name: String,
        memberActorIds: [String],
        memberRoles: [String: [ActorSystemRole]] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.memberActorIds = memberActorIds
        self.memberRoles = memberRoles
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, memberActorIds, memberRoles, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        memberActorIds = try container.decode([String].self, forKey: .memberActorIds)
        memberRoles = try container.decodeIfPresent([String: [ActorSystemRole]].self, forKey: .memberRoles) ?? [:]
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    public func roles(for actor: ActorNode) -> [ActorSystemRole] {
        guard memberActorIds.contains(actor.id) else { return [] }
        return memberRoles[actor.id] ?? actor.systemRole.map { [$0] } ?? []
    }

    public func defaultAssignments(nodes: [ActorNode]) -> TaskStageAssignments {
        func first(_ role: ActorSystemRole) -> String? {
            memberActorIds.first { id in
                guard let node = nodes.first(where: { $0.id == id }) else { return false }
                return roles(for: node).contains(role)
            }
        }
        return TaskStageAssignments(developer: first(.developer), reviewer: first(.reviewer), qa: first(.qa))
    }
}

public struct ActorBoardSnapshot: Codable, Sendable, Equatable {
    public var nodes: [ActorNode]
    public var links: [ActorLink]
    public var teams: [ActorTeam]
    public var updatedAt: Date

    public init(
        nodes: [ActorNode],
        links: [ActorLink],
        teams: [ActorTeam],
        updatedAt: Date = Date()
    ) {
        self.nodes = nodes
        self.links = links
        self.teams = teams
        self.updatedAt = updatedAt
    }
}

public struct ActorBoardUpdateRequest: Codable, Sendable {
    public var nodes: [ActorNode]
    public var links: [ActorLink]
    public var teams: [ActorTeam]

    public init(nodes: [ActorNode], links: [ActorLink], teams: [ActorTeam]) {
        self.nodes = nodes
        self.links = links
        self.teams = teams
    }
}

public struct ActorRouteRequest: Codable, Sendable {
    public var fromActorId: String
    public var communicationType: ActorCommunicationType?

    public init(fromActorId: String, communicationType: ActorCommunicationType? = nil) {
        self.fromActorId = fromActorId
        self.communicationType = communicationType
    }
}

public struct ActorRouteResponse: Codable, Sendable, Equatable {
    public var fromActorId: String
    public var recipientActorIds: [String]
    public var resolvedAt: Date

    public init(
        fromActorId: String,
        recipientActorIds: [String],
        resolvedAt: Date = Date()
    ) {
        self.fromActorId = fromActorId
        self.recipientActorIds = recipientActorIds
        self.resolvedAt = resolvedAt
    }
}

public enum ActorDelegationTreeStatus: String, Codable, Sendable, Equatable {
    case valid
    case invalid
}

public enum ActorDelegationTreeIssueSeverity: String, Codable, Sendable, Equatable {
    case error
    case warning
}

public struct ActorDelegationTreeIssue: Codable, Sendable, Equatable {
    public var code: String
    public var message: String
    public var severity: ActorDelegationTreeIssueSeverity
    public var actorId: String?
    public var linkId: String?

    public init(
        code: String,
        message: String,
        severity: ActorDelegationTreeIssueSeverity,
        actorId: String? = nil,
        linkId: String? = nil
    ) {
        self.code = code
        self.message = message
        self.severity = severity
        self.actorId = actorId
        self.linkId = linkId
    }
}

public struct ActorDelegationTreeLevelActor: Codable, Sendable, Equatable {
    public var actorId: String
    public var displayName: String
    public var linkedAgentId: String

    public init(actorId: String, displayName: String, linkedAgentId: String) {
        self.actorId = actorId
        self.displayName = displayName
        self.linkedAgentId = linkedAgentId
    }
}

public struct ActorDelegationTreePreviewRequest: Codable, Sendable {
    public var rootActorId: String

    public init(rootActorId: String) {
        self.rootActorId = rootActorId
    }
}

public struct ActorDelegationTreePreviewResponse: Codable, Sendable, Equatable {
    public var status: ActorDelegationTreeStatus
    public var rootActorId: String
    public var levels: [[ActorDelegationTreeLevelActor]]
    public var errors: [ActorDelegationTreeIssue]
    public var warnings: [ActorDelegationTreeIssue]
    public var previewedAt: Date

    public init(
        status: ActorDelegationTreeStatus,
        rootActorId: String,
        levels: [[ActorDelegationTreeLevelActor]],
        errors: [ActorDelegationTreeIssue],
        warnings: [ActorDelegationTreeIssue],
        previewedAt: Date = Date()
    ) {
        self.status = status
        self.rootActorId = rootActorId
        self.levels = levels
        self.errors = errors
        self.warnings = warnings
        self.previewedAt = previewedAt
    }
}
