import Foundation
import SloppyNodeCore

extension CoreService {
    public func getMeshState() throws -> MeshState {
        try nodeMeshStore.load()
    }

    public func listMeshNodes() throws -> [MeshNodeRecord] {
        try nodeMeshStore.listNodes()
    }

    public func configureMeshNetwork(_ request: MeshNetworkUpdateRequest) throws -> MeshState {
        try nodeMeshStore.createNetwork(id: request.id, name: request.name)
    }

    public func createMeshInvite(_ request: MeshInviteCreateRequest) throws -> MeshInvite {
        let relayURL = request.relayURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? request.relayURL
            : currentConfig.nodeMeshPublicURL
        return try nodeMeshStore.createInvite(
            networkId: request.networkId,
            name: request.name,
            roles: request.roles,
            capabilities: request.capabilities,
            ttlSeconds: request.ttlSeconds,
            relayURL: relayURL,
            nodeId: request.nodeId,
            publicKey: request.publicKey
        )
    }

    public func deleteMeshInvite(token: String) throws {
        try nodeMeshStore.revokeInvite(token: token, actor: "api")
    }

    public func acceptMeshInvite(_ request: MeshInviteAcceptRequest) throws -> MeshNodeRecord {
        do {
            return try nodeMeshStore.acceptInvite(token: request.token, endpoint: request.endpoint)
        } catch NodeMeshStoreError.inviteMissing {
            if let bundle = try? MeshInviteBundle.parse(request.token) {
                throw NodeMeshStoreError.inviteWrongCoordinator(bundle.relayURL)
            }
            throw NodeMeshStoreError.inviteMissing
        }
    }

    public func registerMeshNode(_ request: MeshNodeRegisterRequest) throws -> MeshNodeRecord {
        try nodeMeshStore.upsertNodeRecord(
            MeshNodeRecord(
                id: request.id,
                name: request.name,
                publicKey: request.publicKey,
                roles: request.roles,
                endpoint: request.endpoint,
                status: .offline,
                capabilities: request.capabilities
            ),
            auditAction: "node.register.api"
        )
    }

    public func listMeshSharedProjects() throws -> [SharedProjectRecord] {
        try nodeMeshStore.listSharedProjects()
    }

    public func createMeshSharedProject(_ request: MeshSharedProjectCreateRequest) throws -> SharedProjectRecord {
        try nodeMeshStore.createSharedProject(
            id: request.id,
            name: request.name,
            repoUrl: request.repoUrl,
            defaultBranch: request.defaultBranch
        )
    }

    public func deleteMeshSharedProject(id: String) throws {
        try nodeMeshStore.removeSharedProject(projectIdOrName: id, actor: "api")
    }

    public func attachMeshSharedProjectMember(
        projectId: String,
        request: MeshSharedProjectMemberRequest
    ) throws -> SharedProjectRecord {
        try nodeMeshStore.attachMember(
            projectIdOrName: projectId,
            nodeId: request.nodeId,
            localRepoPath: request.localRepoPath,
            role: request.role,
            actorId: request.actorId,
            permissions: request.permissions
        )
    }

    public func updateMeshSharedProject(
        id: String,
        request: MeshSharedProjectUpdateRequest
    ) throws -> SharedProjectRecord {
        try nodeMeshStore.updateSharedProject(
            projectIdOrName: id,
            name: request.name,
            repoUrl: request.repoUrl,
            defaultBranch: request.defaultBranch,
            policies: request.policies,
            actor: "api"
        )
    }

    public func listMeshTasks(projectId: String? = nil) throws -> [MeshTaskRecord] {
        try nodeMeshStore.listTasks(projectIdOrName: projectId)
    }

    public func listMeshAuditLog() throws -> [MeshAuditLogEntry] {
        try nodeMeshStore.load().auditLog.sorted { $0.time > $1.time }
    }

    public func createMeshTask(_ request: MeshTaskCreateRequest) throws -> MeshTaskRecord {
        try nodeMeshStore.dispatchTask(
            projectIdOrName: request.projectId,
            title: request.title,
            assignedNodeId: request.assignedNodeId
        )
    }

    public func updateMeshTask(id: String, request: MeshTaskUpdateRequest) throws -> MeshTaskRecord {
        try nodeMeshStore.updateTaskStatus(
            taskId: id,
            projectIdOrName: request.projectId,
            status: request.status,
            actor: "api",
            branch: request.branch,
            commit: request.commit,
            summary: request.summary
        )
    }
}
