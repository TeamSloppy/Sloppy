import Foundation
import Protocols

public enum NodeMeshProjection {
    public static func project(events: [SignedMeshEvent], base: MeshState = MeshState()) throws -> MeshState {
        var state = base
        state.sharedProjects.removeAll()
        state.tasks.removeAll()

        for signed in events.sorted(by: eventSort) {
            try apply(signed, to: &state)
        }

        return state
    }

    private static func eventSort(_ lhs: SignedMeshEvent, _ rhs: SignedMeshEvent) -> Bool {
        if lhs.event.logicalTime == rhs.event.logicalTime {
            return lhs.event.id < rhs.event.id
        }
        return lhs.event.logicalTime < rhs.event.logicalTime
    }

    private static func apply(_ signed: SignedMeshEvent, to state: inout MeshState) throws {
        let event = signed.event

        switch event.type {
        case .nodeAnnounced:
            applyNodeAnnounced(signed, to: &state)
        case .nodeStatusChanged:
            applyNodeStatusChanged(event, to: &state)
        case .nodeAliasUpdated:
            applyNodeAliasUpdated(event, to: &state)
        case .projectCreated:
            applyProjectCreated(event, to: &state)
        case .projectUpdated:
            try applyProjectUpdated(event, to: &state)
        case .projectMemberAdded:
            applyProjectMemberAdded(event, to: &state)
        case .projectMemberRemoved:
            applyProjectMemberRemoved(event, to: &state)
        case .taskCreated:
            applyTaskCreated(event, to: &state)
        case .taskAssigned:
            applyTaskAssigned(event, to: &state)
        case .taskStatusUpdated:
            applyTaskStatusUpdated(event, to: &state)
        case .aclGranted:
            applyACLGranted(event, to: &state)
        case .aclRevoked:
            applyACLRevoked(event, to: &state)
        case .messageSent:
            break
        }
    }

    private static func applyNodeAnnounced(_ signed: SignedMeshEvent, to state: inout MeshState) {
        let payload = signed.event.payload.asObject ?? [:]
        let node = MeshNodeRecord(
            id: signed.event.actorNodeId,
            name: payload["name"]?.asString ?? signed.event.actorNodeId,
            publicKey: signed.actorPublicKey,
            roles: stringArray(payload["roles"]),
            endpoint: payload["endpoint"]?.asString,
            status: MeshNodeStatus(rawValue: payload["status"]?.asString ?? "") ?? .offline,
            lastSeenAt: signed.event.wallTime,
            capabilities: stringArray(payload["capabilities"])
        )
        upsert(node, in: &state.nodes)
    }

    private static func applyNodeStatusChanged(_ event: MeshEvent, to state: inout MeshState) {
        guard let status = MeshNodeStatus(rawValue: event.payload.asObject?["status"]?.asString ?? ""),
              let index = state.nodes.firstIndex(where: { $0.id == event.actorNodeId })
        else {
            return
        }

        state.nodes[index].status = status
        state.nodes[index].lastSeenAt = event.wallTime
    }

    private static func applyNodeAliasUpdated(_ event: MeshEvent, to state: inout MeshState) {
        guard let index = state.nodes.firstIndex(where: { $0.id == event.actorNodeId }) else {
            return
        }

        if let name = event.payload.asObject?["name"]?.asString ?? event.payload.asObject?["alias"]?.asString,
           !name.isEmpty {
            state.nodes[index].name = name
        }
        state.nodes[index].lastSeenAt = event.wallTime
    }

    private static func applyProjectCreated(_ event: MeshEvent, to state: inout MeshState) {
        guard let payload = event.payload.asObject,
              let id = payload["id"]?.asString ?? event.projectId,
              let name = payload["name"]?.asString,
              let repoURL = payload["repoUrl"]?.asString
        else {
            return
        }

        let project = SharedProjectRecord(
            id: id,
            name: name,
            repoUrl: repoURL,
            defaultBranch: payload["defaultBranch"]?.asString ?? "main",
            createdAt: event.wallTime,
            updatedAt: event.wallTime
        )
        upsert(project, in: &state.sharedProjects)
    }

    private static func applyProjectUpdated(_ event: MeshEvent, to state: inout MeshState) throws {
        guard let projectId = event.projectId,
              let index = state.sharedProjects.firstIndex(where: { $0.id == projectId }),
              let payload = event.payload.asObject
        else {
            return
        }

        if let name = payload["name"]?.asString, !name.isEmpty {
            state.sharedProjects[index].name = name
        }
        if let repoURL = payload["repoUrl"]?.asString, !repoURL.isEmpty {
            state.sharedProjects[index].repoUrl = repoURL
        }
        if let defaultBranch = payload["defaultBranch"]?.asString, !defaultBranch.isEmpty {
            state.sharedProjects[index].defaultBranch = defaultBranch
        }
        if let policies = payload["policies"] {
            if let decoded = try? JSONValueCoder.decode(SharedProjectPolicies.self, from: policies) {
                state.sharedProjects[index].policies = decoded
            }
        }
        state.sharedProjects[index].updatedAt = event.wallTime
    }

    private static func applyProjectMemberAdded(_ event: MeshEvent, to state: inout MeshState) {
        guard let projectId = event.projectId,
              let index = state.sharedProjects.firstIndex(where: { $0.id == projectId }),
              let payload = event.payload.asObject,
              let nodeId = payload["nodeId"]?.asString,
              let localRepoPath = payload["localRepoPath"]?.asString
        else {
            return
        }

        let member = SharedProjectMember(
            nodeId: nodeId,
            actorId: payload["actorId"]?.asString,
            localRepoPath: localRepoPath,
            role: payload["role"]?.asString ?? "worker",
            permissions: stringArray(payload["permissions"])
        )

        if let memberIndex = state.sharedProjects[index].members.firstIndex(where: { $0.nodeId == nodeId }) {
            state.sharedProjects[index].members[memberIndex] = member
        } else {
            state.sharedProjects[index].members.append(member)
        }
        state.sharedProjects[index].updatedAt = event.wallTime
    }

    private static func applyProjectMemberRemoved(_ event: MeshEvent, to state: inout MeshState) {
        guard let projectId = event.projectId,
              let index = state.sharedProjects.firstIndex(where: { $0.id == projectId }),
              let nodeId = event.targetNodeId ?? event.payload.asObject?["nodeId"]?.asString
        else {
            return
        }

        state.sharedProjects[index].members.removeAll { $0.nodeId == nodeId }
        state.sharedProjects[index].updatedAt = event.wallTime
    }

    private static func applyTaskCreated(_ event: MeshEvent, to state: inout MeshState) {
        guard let payload = event.payload.asObject,
              let projectId = event.projectId,
              let taskId = payload["taskId"]?.asString,
              let title = payload["title"]?.asString
        else {
            return
        }

        let task = MeshTaskRecord(
            id: taskId,
            projectId: projectId,
            title: title,
            assignedNodeId: payload["assignedNodeId"]?.asString ?? "",
            status: .queued,
            createdAt: event.wallTime,
            updatedAt: event.wallTime
        )
        upsert(task, in: &state.tasks)
    }

    private static func applyTaskAssigned(_ event: MeshEvent, to state: inout MeshState) {
        guard let payload = event.payload.asObject,
              let taskId = payload["taskId"]?.asString,
              let index = state.tasks.firstIndex(where: { $0.id == taskId })
        else {
            return
        }

        state.tasks[index].assignedNodeId = payload["assignedNodeId"]?.asString ?? event.targetNodeId ?? state.tasks[index].assignedNodeId
        state.tasks[index].status = .dispatched
        state.tasks[index].updatedAt = event.wallTime
    }

    private static func applyTaskStatusUpdated(_ event: MeshEvent, to state: inout MeshState) {
        guard let payload = event.payload.asObject,
              let taskId = payload["taskId"]?.asString,
              let index = state.tasks.firstIndex(where: { $0.id == taskId }),
              let rawStatus = payload["status"]?.asString,
              let status = MeshTaskStatus(rawValue: rawStatus)
        else {
            return
        }

        state.tasks[index].status = status
        if let branch = payload["branch"]?.asString {
            state.tasks[index].branch = branch
        }
        if let commit = payload["commit"]?.asString {
            state.tasks[index].commit = commit
        }
        if let summary = payload["summary"]?.asString {
            state.tasks[index].summary = summary
        }
        state.tasks[index].updatedAt = event.wallTime
    }

    private static func applyACLGranted(_ event: MeshEvent, to state: inout MeshState) {
        guard let projectIndex = projectIndex(for: event, in: state),
              let memberIndex = memberIndex(for: event, in: state.sharedProjects[projectIndex])
        else {
            return
        }

        for permission in permissions(from: event.payload) where !state.sharedProjects[projectIndex].members[memberIndex].permissions.contains(permission) {
            state.sharedProjects[projectIndex].members[memberIndex].permissions.append(permission)
        }
        state.sharedProjects[projectIndex].updatedAt = event.wallTime
    }

    private static func applyACLRevoked(_ event: MeshEvent, to state: inout MeshState) {
        guard let projectIndex = projectIndex(for: event, in: state),
              let memberIndex = memberIndex(for: event, in: state.sharedProjects[projectIndex])
        else {
            return
        }

        let revoked = Set(permissions(from: event.payload))
        state.sharedProjects[projectIndex].members[memberIndex].permissions.removeAll { revoked.contains($0) }
        state.sharedProjects[projectIndex].updatedAt = event.wallTime
    }

    private static func projectIndex(for event: MeshEvent, in state: MeshState) -> Int? {
        guard let projectId = event.projectId else {
            return nil
        }
        return state.sharedProjects.firstIndex(where: { $0.id == projectId })
    }

    private static func memberIndex(for event: MeshEvent, in project: SharedProjectRecord) -> Int? {
        let nodeId = event.targetNodeId ?? event.payload.asObject?["nodeId"]?.asString
        return nodeId.flatMap { nodeId in
            project.members.firstIndex(where: { $0.nodeId == nodeId })
        }
    }

    private static func permissions(from payload: JSONValue) -> [String] {
        let object = payload.asObject ?? [:]
        var values = stringArray(object["permissions"])
        if let permission = object["permission"]?.asString {
            values.append(permission)
        }
        return values
    }

    private static func upsert(_ node: MeshNodeRecord, in nodes: inout [MeshNodeRecord]) {
        if let index = nodes.firstIndex(where: { $0.id == node.id }) {
            nodes[index] = node
        } else {
            nodes.append(node)
        }
    }

    private static func upsert(_ project: SharedProjectRecord, in projects: inout [SharedProjectRecord]) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.append(project)
        }
    }

    private static func upsert(_ task: MeshTaskRecord, in tasks: inout [MeshTaskRecord]) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
    }

    private static func stringArray(_ value: JSONValue?) -> [String] {
        guard case let .array(values) = value else {
            return []
        }
        return values.compactMap(\.asString)
    }
}
