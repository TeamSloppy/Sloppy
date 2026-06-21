import Foundation

public enum MeshNodeStatus: String, Codable, Sendable, Equatable {
    case online
    case offline
    case degraded
}

public enum MeshTaskStatus: String, Codable, Sendable, Equatable {
    case queued
    case dispatched
    case claimed
    case started
    case progress
    case blocked
    case readyForReview = "ready_for_review"
    case failed

    public var displayName: String {
        switch self {
        case .queued:
            "queued"
        case .dispatched:
            "dispatched"
        case .claimed:
            "claimed"
        case .started:
            "started"
        case .progress:
            "in progress"
        case .blocked:
            "blocked"
        case .readyForReview:
            "ready for review"
        case .failed:
            "failed"
        }
    }
}

public struct MeshNodeRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var publicKey: String
    public var roles: [String]
    public var endpoint: String?
    public var status: MeshNodeStatus
    public var lastSeenAt: Date
    public var capabilities: [String]

    public init(
        id: String,
        name: String,
        publicKey: String,
        roles: [String],
        endpoint: String? = nil,
        status: MeshNodeStatus = .offline,
        lastSeenAt: Date = Date(),
        capabilities: [String] = []
    ) {
        self.id = id
        self.name = name
        self.publicKey = publicKey
        self.roles = roles
        self.endpoint = endpoint
        self.status = status
        self.lastSeenAt = lastSeenAt
        self.capabilities = capabilities
    }

    public var displayName: String {
        name.isEmpty ? id : name
    }
}

public struct MeshTaskRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var projectId: String
    public var title: String
    public var assignedNodeId: String
    public var status: MeshTaskStatus
    public var branch: String?
    public var commit: String?
    public var summary: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = "mesh_task_" + UUID().uuidString,
        projectId: String,
        title: String,
        assignedNodeId: String,
        status: MeshTaskStatus = .queued,
        branch: String? = nil,
        commit: String? = nil,
        summary: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.assignedNodeId = assignedNodeId
        self.status = status
        self.branch = branch
        self.commit = commit
        self.summary = summary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct MeshTaskCreateRequest: Codable, Sendable, Equatable {
    public var projectId: String
    public var title: String
    public var assignedNodeId: String

    public init(projectId: String, title: String, assignedNodeId: String) {
        self.projectId = projectId
        self.title = title
        self.assignedNodeId = assignedNodeId
    }
}

public struct MeshInviteAcceptRequest: Codable, Sendable, Equatable {
    public var token: String
    public var endpoint: String?
    public var allowRemote: Bool

    public init(token: String, endpoint: String? = nil, allowRemote: Bool = true) {
        self.token = token
        self.endpoint = endpoint
        self.allowRemote = allowRemote
    }

    enum CodingKeys: String, CodingKey {
        case token
        case endpoint
        case allowRemote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.token = try container.decode(String.self, forKey: .token)
        self.endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint)
        self.allowRemote = try container.decodeIfPresent(Bool.self, forKey: .allowRemote) ?? true
    }
}
