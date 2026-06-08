import Foundation
import Protocols

public enum MeshMessageType: String, Codable, Sendable, Equatable {
    case nodeHello = "node.hello"
    case nodeHeartbeat = "node.heartbeat"
    case nodeRegistryUpdate = "node.registry.update"
    case eventPublish = "event.publish"
    case eventSubscribe = "event.subscribe"
    case rpcRequest = "rpc.request"
    case rpcResponse = "rpc.response"
    case streamOpen = "stream.open"
    case streamChunk = "stream.chunk"
    case streamClose = "stream.close"
    case taskDispatch = "task.dispatch"
    case taskStatusUpdate = "task.status.update"
    case projectSyncEvent = "project.sync"
}

public struct MeshEnvelope: Codable, Sendable, Equatable {
    public var id: String
    public var type: MeshMessageType
    public var from: String
    public var to: String?
    public var scope: String?
    public var timestamp: Date
    public var payload: JSONValue
    public var signature: String?

    public init(
        id: String = UUID().uuidString,
        type: MeshMessageType,
        from: String,
        to: String? = nil,
        scope: String? = nil,
        timestamp: Date = Date(),
        payload: JSONValue = .object([:]),
        signature: String? = nil
    ) {
        self.id = id
        self.type = type
        self.from = from
        self.to = to
        self.scope = scope
        self.timestamp = timestamp
        self.payload = payload
        self.signature = signature
    }
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
}

public struct MeshTaskRecord: Codable, Sendable, Equatable {
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

public enum MeshNodeStatus: String, Codable, Sendable, Equatable {
    case online
    case offline
    case degraded
}

public struct MeshNodeRecord: Codable, Sendable, Equatable {
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
        capabilities: [String]
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
}

public struct MeshInvite: Codable, Sendable, Equatable {
    public var token: String
    public var networkId: String
    public var name: String?
    public var roles: [String]
    public var capabilities: [String]
    public var createdAt: Date
    public var expiresAt: Date
    public var consumedAt: Date?
    public var consumedByNodeId: String?

    public init(
        token: String,
        networkId: String,
        name: String? = nil,
        roles: [String],
        capabilities: [String],
        createdAt: Date = Date(),
        expiresAt: Date,
        consumedAt: Date? = nil,
        consumedByNodeId: String? = nil
    ) {
        self.token = token
        self.networkId = networkId
        self.name = name
        self.roles = roles
        self.capabilities = capabilities
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.consumedAt = consumedAt
        self.consumedByNodeId = consumedByNodeId
    }

    public var isConsumed: Bool { consumedAt != nil }
}

public struct SharedProjectPolicies: Codable, Sendable, Equatable {
    public var branchPerTask: Bool
    public var directPushToMain: Bool
    public var requireCleanWorktree: Bool
    public var requireTestsBeforeReady: Bool

    public init(
        branchPerTask: Bool = true,
        directPushToMain: Bool = false,
        requireCleanWorktree: Bool = true,
        requireTestsBeforeReady: Bool = true
    ) {
        self.branchPerTask = branchPerTask
        self.directPushToMain = directPushToMain
        self.requireCleanWorktree = requireCleanWorktree
        self.requireTestsBeforeReady = requireTestsBeforeReady
    }
}

public struct SharedProjectMember: Codable, Sendable, Equatable {
    public var nodeId: String
    public var actorId: String?
    public var localRepoPath: String
    public var role: String
    public var permissions: [String]

    public init(
        nodeId: String,
        actorId: String? = nil,
        localRepoPath: String,
        role: String,
        permissions: [String]
    ) {
        self.nodeId = nodeId
        self.actorId = actorId
        self.localRepoPath = localRepoPath
        self.role = role
        self.permissions = permissions
    }
}

public struct SharedProjectRecord: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var repoUrl: String
    public var defaultBranch: String
    public var members: [SharedProjectMember]
    public var eventScope: String
    public var policies: SharedProjectPolicies
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        name: String,
        repoUrl: String,
        defaultBranch: String = "main",
        members: [SharedProjectMember] = [],
        eventScope: String? = nil,
        policies: SharedProjectPolicies = SharedProjectPolicies(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.repoUrl = repoUrl
        self.defaultBranch = defaultBranch
        self.members = members
        self.eventScope = eventScope ?? "sharedProject:\(id)"
        self.policies = policies
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct MeshAuditLogEntry: Codable, Sendable, Equatable {
    public var id: String
    public var time: Date
    public var actor: String
    public var target: String?
    public var action: String
    public var project: String?
    public var task: String?
    public var allowed: Bool
    public var message: String?

    public init(
        id: String = UUID().uuidString,
        time: Date = Date(),
        actor: String,
        target: String? = nil,
        action: String,
        project: String? = nil,
        task: String? = nil,
        allowed: Bool,
        message: String? = nil
    ) {
        self.id = id
        self.time = time
        self.actor = actor
        self.target = target
        self.action = action
        self.project = project
        self.task = task
        self.allowed = allowed
        self.message = message
    }
}

public struct MeshState: Codable, Sendable, Equatable {
    public var networkId: String
    public var networkName: String
    public var nodes: [MeshNodeRecord]
    public var invites: [MeshInvite]
    public var sharedProjects: [SharedProjectRecord]
    public var tasks: [MeshTaskRecord]
    public var envelopes: [MeshEnvelope]
    public var auditLog: [MeshAuditLogEntry]

    public init(
        networkId: String = "personal",
        networkName: String = "personal",
        nodes: [MeshNodeRecord] = [],
        invites: [MeshInvite] = [],
        sharedProjects: [SharedProjectRecord] = [],
        tasks: [MeshTaskRecord] = [],
        envelopes: [MeshEnvelope] = [],
        auditLog: [MeshAuditLogEntry] = []
    ) {
        self.networkId = networkId
        self.networkName = networkName
        self.nodes = nodes
        self.invites = invites
        self.sharedProjects = sharedProjects
        self.tasks = tasks
        self.envelopes = envelopes
        self.auditLog = auditLog
    }
}

public enum NodeMeshStoreError: LocalizedError, Equatable {
    case inviteMissing
    case inviteExpired
    case inviteConsumed
    case projectMissing(String)
    case nodeMissing(String)
    case permissionDenied(String)
    case taskMissing(String)

    public var errorDescription: String? {
        switch self {
        case .inviteMissing:
            return "Invite token was not found."
        case .inviteExpired:
            return "Invite token has expired."
        case .inviteConsumed:
            return "Invite token has already been consumed."
        case let .projectMissing(projectId):
            return "Shared project '\(projectId)' was not found."
        case let .nodeMissing(nodeId):
            return "Node '\(nodeId)' was not found."
        case let .permissionDenied(permission):
            return "Permission denied: \(permission)."
        case let .taskMissing(taskId):
            return "Mesh task '\(taskId)' was not found."
        }
    }
}

public struct NodeMeshStore: Sendable {
    public var stateURL: URL

    public init(stateURL: URL = NodeMeshStore.defaultStateURL()) {
        self.stateURL = stateURL
    }

    public static func defaultStateURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".sloppy/mesh.json")
    }

    public func load() throws -> MeshState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return MeshState()
        }
        let data = try Data(contentsOf: stateURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MeshState.self, from: data)
    }

    public func save(_ state: MeshState) throws {
        let directoryURL = stateURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: [.atomic])
        #if !os(Windows)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
        #endif
    }

    @discardableResult
    public func createInvite(
        networkId: String,
        name: String?,
        roles: [String],
        capabilities: [String],
        ttlSeconds: TimeInterval = 86400
    ) throws -> MeshInvite {
        var state = try load()
        state.networkId = networkId
        state.networkName = state.networkName.isEmpty ? networkId : state.networkName
        let invite = MeshInvite(
            token: "slp_invite_" + NodeIdentityGenerator.randomToken(byteCount: 18),
            networkId: networkId,
            name: name,
            roles: roles,
            capabilities: capabilities,
            expiresAt: Date().addingTimeInterval(max(1, ttlSeconds))
        )
        state.invites.append(invite)
        state.auditLog.append(MeshAuditLogEntry(actor: "local", action: "node.invite.create", allowed: true, message: invite.token))
        try save(state)
        return invite
    }

    @discardableResult
    public func consumeInvite(token: String, identity: NodeIdentity, endpoint: String?) throws -> MeshNodeRecord {
        var state = try load()
        guard let index = state.invites.firstIndex(where: { $0.token == token }) else {
            throw NodeMeshStoreError.inviteMissing
        }
        let invite = state.invites[index]
        guard invite.consumedAt == nil else { throw NodeMeshStoreError.inviteConsumed }
        guard invite.expiresAt > Date() else { throw NodeMeshStoreError.inviteExpired }

        state.invites[index].consumedAt = Date()
        state.invites[index].consumedByNodeId = identity.nodeId
        state.networkId = invite.networkId
        let record = MeshNodeRecord(
            id: identity.nodeId,
            name: identity.name,
            publicKey: identity.publicKey,
            roles: identity.roles,
            endpoint: endpoint,
            status: .online,
            lastSeenAt: Date(),
            capabilities: identity.capabilities
        )
        upsert(record, in: &state.nodes)
        state.auditLog.append(MeshAuditLogEntry(actor: identity.nodeId, action: "node.join", allowed: true, message: invite.token))
        try save(state)
        return record
    }

    @discardableResult
    public func registerNode(_ identity: NodeIdentity, endpoint: String? = nil, status: MeshNodeStatus = .online) throws -> MeshNodeRecord {
        var state = try load()
        let record = MeshNodeRecord(
            id: identity.nodeId,
            name: identity.name,
            publicKey: identity.publicKey,
            roles: identity.roles,
            endpoint: endpoint,
            status: status,
            lastSeenAt: Date(),
            capabilities: identity.capabilities
        )
        upsert(record, in: &state.nodes)
        state.auditLog.append(MeshAuditLogEntry(actor: identity.nodeId, action: "node.register", allowed: true))
        try save(state)
        return record
    }

    @discardableResult
    public func upsertNodeRecord(_ record: MeshNodeRecord, auditAction: String = "node.register") throws -> MeshNodeRecord {
        var state = try load()
        upsert(record, in: &state.nodes)
        state.auditLog.append(MeshAuditLogEntry(actor: record.id, action: auditAction, allowed: true))
        try save(state)
        return record
    }

    @discardableResult
    public func updateNodeStatus(nodeId: String, status: MeshNodeStatus, auditAction: String) throws -> MeshNodeRecord {
        var state = try load()
        guard let index = state.nodes.firstIndex(where: { $0.id == nodeId }) else {
            throw NodeMeshStoreError.nodeMissing(nodeId)
        }
        state.nodes[index].status = status
        state.nodes[index].lastSeenAt = Date()
        let record = state.nodes[index]
        state.auditLog.append(MeshAuditLogEntry(actor: nodeId, action: auditAction, allowed: true))
        try save(state)
        return record
    }

    @discardableResult
    public func createSharedProject(name: String, repoUrl: String, defaultBranch: String = "main") throws -> SharedProjectRecord {
        var state = try load()
        let project = SharedProjectRecord(
            id: makeSharedProjectId(name),
            name: name,
            repoUrl: repoUrl,
            defaultBranch: defaultBranch.isEmpty ? "main" : defaultBranch
        )
        if let existingIndex = state.sharedProjects.firstIndex(where: { $0.id == project.id || $0.name == name }) {
            state.sharedProjects[existingIndex] = project
        } else {
            state.sharedProjects.append(project)
        }
        state.auditLog.append(MeshAuditLogEntry(actor: "local", action: "shared_project.create", project: project.id, allowed: true))
        try save(state)
        return project
    }

    @discardableResult
    public func attachMember(
        projectIdOrName: String,
        nodeId: String,
        localRepoPath: String,
        role: String,
        actorId: String? = nil,
        permissions: [String]
    ) throws -> SharedProjectRecord {
        var state = try load()
        guard let projectIndex = state.sharedProjects.firstIndex(where: { $0.id == projectIdOrName || $0.name == projectIdOrName }) else {
            throw NodeMeshStoreError.projectMissing(projectIdOrName)
        }
        let member = SharedProjectMember(
            nodeId: nodeId,
            actorId: actorId,
            localRepoPath: localRepoPath,
            role: role,
            permissions: permissions
        )
        if let memberIndex = state.sharedProjects[projectIndex].members.firstIndex(where: { $0.nodeId == nodeId }) {
            state.sharedProjects[projectIndex].members[memberIndex] = member
        } else {
            state.sharedProjects[projectIndex].members.append(member)
        }
        state.sharedProjects[projectIndex].updatedAt = Date()
        let project = state.sharedProjects[projectIndex]
        state.auditLog.append(MeshAuditLogEntry(actor: "local", target: nodeId, action: "shared_project.attach", project: project.id, allowed: true))
        try save(state)
        return project
    }

    @discardableResult
    public func createNetwork(id: String, name: String? = nil) throws -> MeshState {
        var state = try load()
        state.networkId = id
        state.networkName = name?.isEmpty == false ? name! : id
        state.auditLog.append(MeshAuditLogEntry(actor: "local", action: "network.create", allowed: true, message: state.networkName))
        try save(state)
        return state
    }

    public func listSharedProjects() throws -> [SharedProjectRecord] {
        try load().sharedProjects.sorted { $0.name < $1.name }
    }

    public func listTasks(projectIdOrName: String? = nil) throws -> [MeshTaskRecord] {
        let state = try load()
        guard let projectIdOrName, !projectIdOrName.isEmpty else {
            return state.tasks.sorted { $0.updatedAt > $1.updatedAt }
        }
        let projectId = state.sharedProjects.first(where: { $0.id == projectIdOrName || $0.name == projectIdOrName })?.id ?? projectIdOrName
        return state.tasks.filter { $0.projectId == projectId }.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    public func routeEnvelope(_ envelope: MeshEnvelope) throws -> MeshEnvelope {
        var state = try load()
        if let target = envelope.to, !state.nodes.contains(where: { $0.id == target }) {
            state.auditLog.append(MeshAuditLogEntry(actor: envelope.from, target: target, action: envelope.type.rawValue, allowed: false, message: "unknown target node"))
            try save(state)
            throw NodeMeshStoreError.nodeMissing(target)
        }
        state.envelopes.append(envelope)
        state.auditLog.append(MeshAuditLogEntry(actor: envelope.from, target: envelope.to, action: envelope.type.rawValue, project: projectFromScope(envelope.scope), allowed: true))
        try save(state)
        return envelope
    }

    public func recordRouteFailure(_ envelope: MeshEnvelope, target: String, message: String) throws {
        var state = try load()
        state.auditLog.append(MeshAuditLogEntry(
            actor: envelope.from,
            target: target,
            action: envelope.type.rawValue,
            project: projectFromScope(envelope.scope),
            allowed: false,
            message: message
        ))
        try save(state)
    }

    @discardableResult
    public func rpcRequest(from: String, to: String, method: String, params: JSONValue = .object([:])) throws -> MeshEnvelope {
        try routeEnvelope(MeshEnvelope(
            type: .rpcRequest,
            from: from,
            to: to,
            payload: .object([
                "method": .string(method),
                "params": params,
            ])
        ))
    }

    @discardableResult
    public func dispatchTask(projectIdOrName: String, title: String, assignedNodeId: String, actor: String = "local") throws -> MeshTaskRecord {
        var state = try load()
        guard let project = state.sharedProjects.first(where: { $0.id == projectIdOrName || $0.name == projectIdOrName }) else {
            throw NodeMeshStoreError.projectMissing(projectIdOrName)
        }
        guard state.nodes.contains(where: { $0.id == assignedNodeId }) else {
            throw NodeMeshStoreError.nodeMissing(assignedNodeId)
        }
        guard let member = project.members.first(where: { $0.nodeId == assignedNodeId }), member.permissions.contains("task.update") || member.permissions.contains("task.assign") else {
            state.auditLog.append(MeshAuditLogEntry(actor: actor, target: assignedNodeId, action: "task.dispatch", project: project.id, allowed: false, message: "missing task.update/task.assign permission"))
            try save(state)
            throw NodeMeshStoreError.permissionDenied("task.dispatch")
        }
        let task = MeshTaskRecord(projectId: project.id, title: title, assignedNodeId: assignedNodeId, status: .dispatched)
        state.tasks.append(task)
        state.envelopes.append(MeshEnvelope(
            type: .taskDispatch,
            from: actor,
            to: assignedNodeId,
            scope: project.eventScope,
            payload: .object([
                "taskId": .string(task.id),
                "projectId": .string(project.id),
                "title": .string(title),
            ])
        ))
        state.auditLog.append(MeshAuditLogEntry(actor: actor, target: assignedNodeId, action: "task.dispatch", project: project.id, task: task.id, allowed: true))
        try save(state)
        return task
    }

    @discardableResult
    public func updateTaskStatus(
        taskId: String,
        status: MeshTaskStatus,
        actor: String,
        branch: String? = nil,
        commit: String? = nil,
        summary: String? = nil
    ) throws -> MeshTaskRecord {
        var state = try load()
        guard let index = state.tasks.firstIndex(where: { $0.id == taskId }) else {
            throw NodeMeshStoreError.taskMissing(taskId)
        }
        state.tasks[index].status = status
        if let branch { state.tasks[index].branch = branch }
        if let commit { state.tasks[index].commit = commit }
        if let summary { state.tasks[index].summary = summary }
        state.tasks[index].updatedAt = Date()
        let task = state.tasks[index]
        let project = state.sharedProjects.first(where: { $0.id == task.projectId })
        state.envelopes.append(MeshEnvelope(
            type: .taskStatusUpdate,
            from: actor,
            scope: project?.eventScope ?? "sharedProject:\(task.projectId)",
            payload: .object([
                "taskId": .string(task.id),
                "status": .string(status.rawValue),
                "branch": branch.map(JSONValue.string) ?? .null,
                "commit": commit.map(JSONValue.string) ?? .null,
                "summary": summary.map(JSONValue.string) ?? .null,
            ])
        ))
        state.auditLog.append(MeshAuditLogEntry(actor: actor, action: "task.status.update", project: task.projectId, task: task.id, allowed: true, message: status.rawValue))
        try save(state)
        return task
    }

    private func projectFromScope(_ scope: String?) -> String? {
        guard let scope, scope.hasPrefix("sharedProject:") else { return nil }
        return String(scope.dropFirst("sharedProject:".count))
    }

    private func upsert(_ node: MeshNodeRecord, in nodes: inout [MeshNodeRecord]) {
        if let index = nodes.firstIndex(where: { $0.id == node.id }) {
            nodes[index] = node
        } else {
            nodes.append(node)
        }
    }

    private func makeSharedProjectId(_ name: String) -> String {
        let slug = name
            .lowercased()
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
            .split(separator: "-")
            .joined(separator: "-")
        return "sp_\(slug.isEmpty ? NodeIdentityGenerator.randomToken(byteCount: 4) : slug)"
    }
}
