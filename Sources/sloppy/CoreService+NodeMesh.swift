import Foundation
import SloppyNodeCore

extension CoreService {
    public func listMeshNodes() throws -> [MeshNodeRecord] {
        try nodeMeshStore.load().nodes.sorted { $0.name < $1.name }
    }

    public func listMeshSharedProjects() throws -> [SharedProjectRecord] {
        try nodeMeshStore.listSharedProjects()
    }

    public func createMeshSharedProject(_ request: MeshSharedProjectCreateRequest) throws -> SharedProjectRecord {
        try nodeMeshStore.createSharedProject(
            name: request.name,
            repoUrl: request.repoUrl,
            defaultBranch: request.defaultBranch
        )
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
            status: request.status,
            actor: "api",
            branch: request.branch,
            commit: request.commit,
            summary: request.summary
        )
    }
}
