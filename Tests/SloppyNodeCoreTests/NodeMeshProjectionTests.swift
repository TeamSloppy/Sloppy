import Foundation
import Protocols
@testable import SloppyNodeCore
import Testing

@Suite("NodeMeshProjection")
struct NodeMeshProjectionTests {
    @Test("projection builds task lifecycle from signed events")
    func projectionBuildsTaskLifecycleFromSignedEvents() throws {
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
        let projectId = "sp_sloppy"
        let events = try [
            signed(.projectCreated, actor: work, projectId: projectId, logicalTime: 1, payload: [
                "id": .string(projectId),
                "name": .string("Sloppy"),
                "repoUrl": .string("git@example.com:sloppy.git"),
                "defaultBranch": .string("main"),
            ]),
            signed(.projectMemberAdded, actor: work, target: work.nodeId, projectId: projectId, logicalTime: 2, payload: [
                "nodeId": .string(work.nodeId),
                "localRepoPath": .string("/work/sloppy"),
                "role": .string("controller"),
                "permissions": .array([
                    .string(MeshPermission.projectRead.rawValue),
                    .string(MeshPermission.taskCreate.rawValue),
                    .string(MeshPermission.taskAssign.rawValue),
                ]),
            ]),
            signed(.projectMemberAdded, actor: work, target: home.nodeId, projectId: projectId, logicalTime: 3, payload: [
                "nodeId": .string(home.nodeId),
                "localRepoPath": .string("/home/sloppy"),
                "role": .string("worker"),
                "permissions": .array(MeshPermission.workerDefaults.rawValues.map(JSONValue.string)),
            ]),
            signed(.taskCreated, actor: work, projectId: projectId, logicalTime: 4, payload: [
                "taskId": .string("mesh_task_1"),
                "title": .string("Run build"),
            ]),
            signed(.taskAssigned, actor: work, target: home.nodeId, projectId: projectId, logicalTime: 5, payload: [
                "taskId": .string("mesh_task_1"),
                "assignedNodeId": .string(home.nodeId),
            ]),
            signed(.taskStatusUpdated, actor: home, projectId: projectId, logicalTime: 6, payload: [
                "taskId": .string("mesh_task_1"),
                "status": .string(MeshTaskStatus.readyForReview.rawValue),
                "branch": .string("agent/home/mesh-task-1-run-build"),
                "summary": .string("Build passed."),
            ]),
        ]

        let state = try NodeMeshProjection.project(events: events, base: MeshState())

        let task = try #require(state.tasks.first)
        #expect(task.id == "mesh_task_1")
        #expect(task.assignedNodeId == home.nodeId)
        #expect(task.status == .readyForReview)
        #expect(task.branch == "agent/home/mesh-task-1-run-build")
        #expect(task.summary == "Build passed.")
        #expect(state.sharedProjects.first?.members.count == 2)
    }

    @Test("projection sorts same logical time by event id")
    func projectionSortsSameLogicalTimeByEventID() throws {
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let projectId = "sp_same_time"
        let events = try [
            signed(.projectUpdated, actor: work, projectId: projectId, logicalTime: 7, eventId: "mesh_evt_02", payload: [
                "name": .string("Updated Name"),
            ]),
            signed(.projectCreated, actor: work, projectId: projectId, logicalTime: 7, eventId: "mesh_evt_01", payload: [
                "id": .string(projectId),
                "name": .string("Initial Name"),
                "repoUrl": .string("git@example.com:same-time.git"),
                "defaultBranch": .string("main"),
            ]),
        ]

        let state = try NodeMeshProjection.project(events: events, base: MeshState())

        #expect(state.sharedProjects.first?.name == "Updated Name")
    }

    @Test("projected state preserves stored metadata while rebuilding derived state")
    func projectedStatePreservesStoredMetadataWhileRebuildingDerivedState() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let projectId = "sp_projection"
        let projectEvent = try signed(.projectCreated, actor: work, projectId: projectId, logicalTime: 1, payload: [
            "id": .string(projectId),
            "name": .string("Projection"),
            "repoUrl": .string("git@example.com:projection.git"),
        ])
        let taskEvent = try signed(.taskCreated, actor: work, projectId: projectId, logicalTime: 2, payload: [
            "taskId": .string("mesh_task_projection"),
            "title": .string("Replay events"),
        ])
        let envelope = MeshEnvelope(type: .eventPublish, from: work.nodeId, scope: "sharedProject:\(projectId)")
        let audit = MeshAuditLogEntry(actor: work.nodeId, action: "event.append", project: projectId, allowed: true)
        let invite = MeshInvite(
            token: "slp_invite_projection",
            networkId: "mesh",
            roles: ["worker"],
            capabilities: ["git"],
            expiresAt: Date(timeIntervalSince1970: 3_000)
        )
        let staleProject = SharedProjectRecord(id: "stale", name: "Stale", repoUrl: "git@example.com:stale.git")
        let staleTask = MeshTaskRecord(projectId: "stale", title: "Old", assignedNodeId: "")
        let state = MeshState(
            networkId: "mesh",
            networkName: "Mesh",
            invites: [invite],
            sharedProjects: [staleProject],
            tasks: [staleTask],
            envelopes: [envelope],
            auditLog: [audit],
            events: [projectEvent, taskEvent],
            eventCursors: [work.nodeId: taskEvent.event.id]
        )

        try store.save(state)
        let projected = try store.projectedState()

        #expect(projected.networkId == "mesh")
        #expect(projected.networkName == "Mesh")
        #expect(projected.invites.map(\.token) == [invite.token])
        #expect(projected.envelopes.map(\.id) == [envelope.id])
        #expect(projected.auditLog.map(\.id) == [audit.id])
        #expect(projected.events.map(\.event.id) == [projectEvent.event.id, taskEvent.event.id])
        #expect(projected.eventCursors == [work.nodeId: taskEvent.event.id])
        #expect(projected.sharedProjects.map(\.id) == [projectId])
        #expect(projected.tasks.map(\.id) == ["mesh_task_projection"])
    }

    @Test("node announcement uses signed identity over forged payload")
    func nodeAnnouncementUsesSignedIdentityOverForgedPayload() throws {
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let event = try signed(.nodeAnnounced, actor: work, projectId: nil, logicalTime: 1, payload: [
            "id": .string("node_forged"),
            "publicKey": .string("ed25519:forged"),
            "name": .string("Work"),
            "roles": .array([.string("client")]),
            "capabilities": .array([.string("git")]),
        ])

        let state = try NodeMeshProjection.project(events: [event], base: MeshState())

        let node = try #require(state.nodes.first)
        #expect(node.id == work.nodeId)
        #expect(node.publicKey == work.publicKey)
    }

    @Test("projection rebuilds nodes from signed events")
    func projectionRebuildsNodesFromSignedEvents() throws {
        let announced = NodeIdentityGenerator.makeIdentity(name: "Announced", roles: ["worker"], capabilities: ["git"])
        let staleNode = MeshNodeRecord(
            id: "node_stale",
            name: "Stale",
            publicKey: "ed25519:stale",
            roles: ["worker"],
            status: .online,
            capabilities: ["git"]
        )
        let base = MeshState(nodes: [staleNode])
        let events = try [
            signed(.nodeAnnounced, actor: announced, projectId: nil, logicalTime: 1, payload: [
                "name": .string("Announced"),
                "roles": .array([.string("worker")]),
                "capabilities": .array([.string("git")]),
                "status": .string(MeshNodeStatus.online.rawValue),
            ]),
        ]

        let state = try NodeMeshProjection.project(events: events, base: base)

        #expect(state.nodes.map(\.id) == [announced.nodeId])
        #expect(state.nodes.first?.publicKey == announced.publicKey)
        #expect(state.nodes.contains(where: { $0.id == staleNode.id }) == false)
    }

    @Test("invalid project policies do not abort projection")
    func invalidProjectPoliciesDoNotAbortProjection() throws {
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let projectId = "sp_policy"
        let events = try [
            signed(.projectCreated, actor: work, projectId: projectId, logicalTime: 1, payload: [
                "id": .string(projectId),
                "name": .string("Policy"),
                "repoUrl": .string("git@example.com:policy.git"),
            ]),
            signed(.projectUpdated, actor: work, projectId: projectId, logicalTime: 2, payload: [
                "name": .string("Updated Policy"),
                "policies": .string("invalid"),
            ]),
        ]

        let state = try NodeMeshProjection.project(events: events, base: MeshState())

        let project = try #require(state.sharedProjects.first)
        #expect(project.name == "Updated Policy")
        #expect(project.policies == SharedProjectPolicies())
    }

    private func signed(
        _ type: MeshEventType,
        actor: NodeIdentity,
        target: String? = nil,
        projectId: String?,
        logicalTime: UInt64,
        eventId: String? = nil,
        payload: [String: JSONValue]
    ) throws -> SignedMeshEvent {
        try MeshEventSigner.sign(
            MeshEvent(
                id: eventId ?? "mesh_evt_" + UUID().uuidString,
                type: type,
                actorNodeId: actor.nodeId,
                targetNodeId: target,
                projectId: projectId,
                logicalTime: logicalTime,
                payload: .object(payload)
            ),
            identity: actor
        )
    }

    private func temporaryStateURL() -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("node-mesh-projection-tests", isDirectory: true)
        return directory.appendingPathComponent(UUID().uuidString + ".json")
    }
}
