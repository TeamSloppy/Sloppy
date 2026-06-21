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
                    .string(MeshPermission.projectWrite.rawValue),
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

        let state = try NodeMeshProjection.project(events: events, base: baseState(nodes: [work, home]))

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

        let state = try NodeMeshProjection.project(events: events, base: baseState(nodes: [work]))

        #expect(state.sharedProjects.first?.name == "Updated Name")
    }

    @Test("task created payload cannot assign without task assigned event")
    func taskCreatedPayloadCannotAssignWithoutTaskAssignedEvent() throws {
        let owner = NodeIdentityGenerator.makeIdentity(name: "Owner", roles: ["client"], capabilities: ["git"])
        let worker = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["git"])
        let projectId = "sp_task_created_assignment"
        var events = try authorizedProjectEvents(projectId: projectId, owner: owner, worker: worker)
        events.append(try signed(.taskCreated, actor: owner, projectId: projectId, logicalTime: 4, payload: [
            "taskId": .string("mesh_task_assignment_smuggle"),
            "title": .string("Run build"),
            "assignedNodeId": .string(worker.nodeId),
        ]))

        let state = try NodeMeshProjection.project(events: events, base: baseState(nodes: [owner, worker]))

        let task = try #require(state.tasks.first(where: { $0.id == "mesh_task_assignment_smuggle" }))
        #expect(task.assignedNodeId == "")
        #expect(task.status == .queued)
    }

    @Test("task assignment rejects mismatched target and payload assignee")
    func taskAssignmentRejectsMismatchedTargetAndPayloadAssignee() throws {
        let owner = NodeIdentityGenerator.makeIdentity(name: "Owner", roles: ["client"], capabilities: ["git"])
        let worker = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["git"])
        let rogue = NodeIdentityGenerator.makeIdentity(name: "Rogue", roles: ["worker"], capabilities: ["git"])
        let projectId = "sp_task_assignee_mismatch"
        let events = try authorizedProjectEvents(projectId: projectId, owner: owner, worker: worker) + [
            signed(.taskCreated, actor: owner, projectId: projectId, logicalTime: 4, payload: [
                "taskId": .string("mesh_task_mismatch"),
                "title": .string("Run build"),
            ]),
            signed(.taskAssigned, actor: owner, target: worker.nodeId, projectId: projectId, logicalTime: 5, payload: [
                "taskId": .string("mesh_task_mismatch"),
                "assignedNodeId": .string(rogue.nodeId),
            ]),
        ]

        #expect(throws: MeshEventVerificationError.unauthorized("task.dispatch")) {
            _ = try NodeMeshProjection.project(events: events, base: baseState(nodes: [owner, worker, rogue]))
        }
    }

    @Test("project creation name cannot shadow existing legacy project id without write permission")
    func projectCreationNameCannotShadowExistingLegacyProjectIDWithoutWritePermission() throws {
        let owner = NodeIdentityGenerator.makeIdentity(name: "Owner", roles: ["client"], capabilities: ["git"])
        let rogue = NodeIdentityGenerator.makeIdentity(name: "Rogue", roles: ["worker"], capabilities: ["git"])
        let legacyProject = SharedProjectRecord(
            id: "sp_legacy_collision",
            name: "Legacy Collision",
            repoUrl: "git@example.com:legacy-collision.git",
            members: [
                SharedProjectMember(
                    nodeId: owner.nodeId,
                    localRepoPath: "/work/legacy-collision",
                    role: "controller",
                    permissions: [MeshPermission.projectWrite.rawValue]
                ),
            ]
        )
        let event = try signed(.projectCreated, actor: rogue, projectId: "sp_rogue_collision", logicalTime: 1, payload: [
            "id": .string("sp_rogue_collision"),
            "name": .string(legacyProject.id),
            "repoUrl": .string("git@example.com:rogue-collision.git"),
        ])

        #expect(throws: MeshEventVerificationError.unauthorized(MeshPermission.projectWrite.rawValue)) {
            _ = try NodeMeshProjection.project(
                events: [event],
                base: MeshState(nodes: baseState(nodes: [owner, rogue]).nodes, sharedProjects: [legacyProject])
            )
        }
    }

    @Test("projection rejects tampered signed events before mutating state")
    func projectionRejectsTamperedSignedEventsBeforeMutatingState() throws {
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let projectId = "sp_tampered"
        var signed = try signed(.projectCreated, actor: work, projectId: projectId, logicalTime: 1, payload: [
            "id": .string(projectId),
            "name": .string("Tampered"),
            "repoUrl": .string("git@example.com:tampered.git"),
        ])
        signed.event.payload = .object([
            "id": .string(projectId),
            "name": .string("Tampered"),
            "repoUrl": .string("git@example.com:modified.git"),
        ])

        #expect(throws: MeshEventVerificationError.invalidSignature) {
            _ = try NodeMeshProjection.project(events: [signed], base: baseState(nodes: [work]))
        }
    }

    @Test("projection rejects events signed by an unbound key for an existing actor")
    func projectionRejectsImpersonationAgainstBoundActorKey() throws {
        let victim = NodeIdentityGenerator.makeIdentity(name: "Victim", roles: ["worker"], capabilities: ["git"])
        let attacker = NodeIdentityGenerator.makeIdentity(name: "Attacker", roles: ["worker"], capabilities: ["git"])
        let base = MeshState(nodes: [
            MeshNodeRecord(
                id: victim.nodeId,
                name: victim.name,
                publicKey: victim.publicKey,
                roles: victim.roles,
                status: .online,
                capabilities: victim.capabilities
            ),
        ])
        let forged = try forgedSignedEvent(
            type: .nodeStatusChanged,
            actorNodeId: victim.nodeId,
            signer: attacker,
            logicalTime: 1,
            payload: [
                "status": .string(MeshNodeStatus.offline.rawValue),
            ]
        )

        #expect(throws: MeshEventVerificationError.invalidSignature) {
            _ = try NodeMeshProjection.project(events: [forged], base: base)
        }
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
        let memberEvent = try signed(.projectMemberAdded, actor: work, target: work.nodeId, projectId: projectId, logicalTime: 2, payload: [
            "nodeId": .string(work.nodeId),
            "localRepoPath": .string("/work/projection"),
            "role": .string("controller"),
            "permissions": .array([
                .string(MeshPermission.projectWrite.rawValue),
                .string(MeshPermission.taskCreate.rawValue),
            ]),
        ])
        let taskEvent = try signed(.taskCreated, actor: work, projectId: projectId, logicalTime: 3, payload: [
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
            nodes: baseState(nodes: [work]).nodes,
            invites: [invite],
            sharedProjects: [staleProject],
            tasks: [staleTask],
            envelopes: [envelope],
            auditLog: [audit],
            events: [projectEvent, memberEvent, taskEvent],
            eventCursors: [work.nodeId: taskEvent.event.id]
        )

        try store.save(state)
        let projected = try store.projectedState()

        #expect(projected.networkId == "mesh")
        #expect(projected.networkName == "Mesh")
        #expect(projected.invites.map(\.token) == [invite.token])
        #expect(projected.envelopes.map(\.id) == [envelope.id])
        #expect(projected.auditLog.map(\.id) == [audit.id])
        #expect(projected.events.map(\.event.id) == [projectEvent.event.id, memberEvent.event.id, taskEvent.event.id])
        #expect(projected.eventCursors == [work.nodeId: taskEvent.event.id])
        #expect(projected.sharedProjects.map(\.id) == [projectId])
        #expect(projected.tasks.map(\.id) == ["mesh_task_projection"])
    }

    @Test("projection replays acl grants and revocations")
    func projectionReplaysAclGrantsAndRevocations() throws {
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
        let projectId = "sp_acl"
        let events = try [
            signed(.projectCreated, actor: work, projectId: projectId, logicalTime: 1, payload: [
                "id": .string(projectId),
                "name": .string("ACL"),
                "repoUrl": .string("git@example.com:acl.git"),
            ]),
            signed(.projectMemberAdded, actor: work, target: work.nodeId, projectId: projectId, logicalTime: 2, payload: [
                "nodeId": .string(work.nodeId),
                "localRepoPath": .string("/work/acl"),
                "role": .string("controller"),
                "permissions": .array([
                    .string(MeshPermission.projectWrite.rawValue),
                ]),
            ]),
            signed(.projectMemberAdded, actor: work, target: home.nodeId, projectId: projectId, logicalTime: 3, payload: [
                "nodeId": .string(home.nodeId),
                "localRepoPath": .string("/home/acl"),
                "role": .string("worker"),
                "permissions": .array([
                    .string(MeshPermission.projectRead.rawValue),
                ]),
            ]),
            signed(.aclGranted, actor: work, target: home.nodeId, projectId: projectId, logicalTime: 4, payload: [
                "permissions": .array([
                    .string(MeshPermission.taskCreate.rawValue),
                    .string(MeshPermission.nodeShell.rawValue),
                ]),
            ]),
            signed(.aclRevoked, actor: work, target: home.nodeId, projectId: projectId, logicalTime: 5, payload: [
                "permissions": .array([
                    .string(MeshPermission.projectRead.rawValue),
                    .string(MeshPermission.nodeShell.rawValue),
                ]),
            ]),
        ]

        let state = try NodeMeshProjection.project(events: events, base: baseState(nodes: [work, home]))

        let project = try #require(state.sharedProjects.first(where: { $0.id == projectId }))
        let member = try #require(project.members.first(where: { $0.nodeId == home.nodeId }))
        #expect(member.permissions == [MeshPermission.taskCreate.rawValue])
    }

    @Test("projection rejects unauthorized acl grants before mutation")
    func projectionRejectsUnauthorizedACLGrantsBeforeMutation() throws {
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
        let projectId = "sp_acl_denied"
        let events = try authorizedProjectEvents(projectId: projectId, owner: work, worker: home) + [
            signed(.aclGranted, actor: home, target: home.nodeId, projectId: projectId, logicalTime: 4, payload: [
                "permissions": .array([
                    .string(MeshPermission.nodeShell.rawValue),
                ]),
            ]),
        ]

        #expect(throws: (any Error).self) {
            _ = try NodeMeshProjection.project(events: events, base: baseState(nodes: [work, home]))
        }

        let prefix = try NodeMeshProjection.project(events: Array(events.dropLast()), base: baseState(nodes: [work, home]))
        let member = try #require(prefix.sharedProjects.first?.members.first(where: { $0.nodeId == home.nodeId }))
        #expect(member.permissions.contains(MeshPermission.nodeShell.rawValue) == false)
    }

    @Test("projection rejects unauthorized member additions before mutation")
    func projectionRejectsUnauthorizedMemberAdditionsBeforeMutation() throws {
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
        let rogue = NodeIdentityGenerator.makeIdentity(name: "Rogue", roles: ["worker"], capabilities: ["git"])
        let projectId = "sp_member_denied"
        let events = try authorizedProjectEvents(projectId: projectId, owner: work, worker: home) + [
            signed(.projectMemberAdded, actor: home, target: rogue.nodeId, projectId: projectId, logicalTime: 4, payload: [
                "nodeId": .string(rogue.nodeId),
                "localRepoPath": .string("/rogue/sloppy"),
                "role": .string("worker"),
                "permissions": .array(MeshPermission.workerDefaults.rawValues.map(JSONValue.string)),
            ]),
        ]

        #expect(throws: (any Error).self) {
            _ = try NodeMeshProjection.project(events: events, base: baseState(nodes: [work, home, rogue]))
        }

        let prefix = try NodeMeshProjection.project(events: Array(events.dropLast()), base: baseState(nodes: [work, home, rogue]))
        #expect(prefix.sharedProjects.first?.members.contains(where: { $0.nodeId == rogue.nodeId }) == false)
    }

    @Test("empty project bootstrap rejects rogue self add")
    func emptyProjectBootstrapRejectsRogueSelfAdd() throws {
        let owner = NodeIdentityGenerator.makeIdentity(name: "Owner", roles: ["client"], capabilities: ["git"])
        let rogue = NodeIdentityGenerator.makeIdentity(name: "Rogue", roles: ["worker"], capabilities: ["git"])
        let projectId = "sp_owner_empty"
        let events = try [
            signed(.projectCreated, actor: owner, projectId: projectId, logicalTime: 1, payload: [
                "id": .string(projectId),
                "name": .string("Owner Empty"),
                "repoUrl": .string("git@example.com:owner-empty.git"),
            ]),
            signed(.projectMemberAdded, actor: rogue, target: rogue.nodeId, projectId: projectId, logicalTime: 2, payload: [
                "nodeId": .string(rogue.nodeId),
                "localRepoPath": .string("/rogue/owner-empty"),
                "role": .string("worker"),
                "permissions": .array(MeshPermission.workerDefaults.rawValues.map(JSONValue.string)),
            ]),
        ]

        #expect(throws: MeshEventVerificationError.unauthorized(MeshPermission.projectWrite.rawValue)) {
            _ = try NodeMeshProjection.project(events: events, base: baseState(nodes: [owner, rogue]))
        }
    }

    @Test("empty project bootstrap rejects rogue update")
    func emptyProjectBootstrapRejectsRogueUpdate() throws {
        let owner = NodeIdentityGenerator.makeIdentity(name: "Owner", roles: ["client"], capabilities: ["git"])
        let rogue = NodeIdentityGenerator.makeIdentity(name: "Rogue", roles: ["worker"], capabilities: ["git"])
        let projectId = "sp_owner_update"
        let events = try [
            signed(.projectCreated, actor: owner, projectId: projectId, logicalTime: 1, payload: [
                "id": .string(projectId),
                "name": .string("Owner Update"),
                "repoUrl": .string("git@example.com:owner-update.git"),
            ]),
            signed(.projectUpdated, actor: rogue, projectId: projectId, logicalTime: 2, payload: [
                "name": .string("Rogue Update"),
            ]),
        ]

        #expect(throws: MeshEventVerificationError.unauthorized(MeshPermission.projectWrite.rawValue)) {
            _ = try NodeMeshProjection.project(events: events, base: baseState(nodes: [owner, rogue]))
        }
    }

    @Test("empty project bootstrap allows creator initial member")
    func emptyProjectBootstrapAllowsCreatorInitialMember() throws {
        let owner = NodeIdentityGenerator.makeIdentity(name: "Owner", roles: ["client"], capabilities: ["git"])
        let projectId = "sp_owner_initial"
        let events = try [
            signed(.projectCreated, actor: owner, projectId: projectId, logicalTime: 1, payload: [
                "id": .string(projectId),
                "name": .string("Owner Initial"),
                "repoUrl": .string("git@example.com:owner-initial.git"),
            ]),
            signed(.projectMemberAdded, actor: owner, target: owner.nodeId, projectId: projectId, logicalTime: 2, payload: [
                "nodeId": .string(owner.nodeId),
                "localRepoPath": .string("/owner/owner-initial"),
                "role": .string("controller"),
                "permissions": .array([
                    .string(MeshPermission.projectWrite.rawValue),
                    .string(MeshPermission.taskCreate.rawValue),
                    .string(MeshPermission.taskAssign.rawValue),
                ]),
            ]),
        ]

        let state = try NodeMeshProjection.project(events: events, base: baseState(nodes: [owner]))

        let member = try #require(state.sharedProjects.first?.members.first)
        #expect(member.nodeId == owner.nodeId)
        #expect(member.permissions.contains(MeshPermission.projectWrite.rawValue))
    }

    @Test("projection rejects unauthorized task status updates before mutation")
    func projectionRejectsUnauthorizedTaskStatusUpdatesBeforeMutation() throws {
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
        let other = NodeIdentityGenerator.makeIdentity(name: "Other", roles: ["worker"], capabilities: ["git"])
        let projectId = "sp_task_denied"
        let events = try authorizedProjectEvents(projectId: projectId, owner: work, worker: home) + [
            signed(.projectMemberAdded, actor: work, target: other.nodeId, projectId: projectId, logicalTime: 4, payload: [
                "nodeId": .string(other.nodeId),
                "localRepoPath": .string("/other/sloppy"),
                "role": .string("worker"),
                "permissions": .array(MeshPermission.workerDefaults.rawValues.map(JSONValue.string)),
            ]),
            signed(.taskCreated, actor: work, projectId: projectId, logicalTime: 5, payload: [
                "taskId": .string("mesh_task_denied"),
                "title": .string("Run build"),
            ]),
            signed(.taskAssigned, actor: work, target: home.nodeId, projectId: projectId, logicalTime: 6, payload: [
                "taskId": .string("mesh_task_denied"),
                "assignedNodeId": .string(home.nodeId),
            ]),
            signed(.taskStatusUpdated, actor: other, projectId: projectId, logicalTime: 7, payload: [
                "taskId": .string("mesh_task_denied"),
                "status": .string(MeshTaskStatus.readyForReview.rawValue),
                "summary": .string("Not my task."),
            ]),
        ]

        #expect(throws: (any Error).self) {
            _ = try NodeMeshProjection.project(events: events, base: baseState(nodes: [work, home, other]))
        }

        let prefix = try NodeMeshProjection.project(events: Array(events.dropLast()), base: baseState(nodes: [work, home, other]))
        let task = try #require(prefix.tasks.first(where: { $0.id == "mesh_task_denied" }))
        #expect(task.status == .dispatched)
        #expect(task.summary == nil)
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

    @Test("projection bootstraps unknown node from announcement before accepting later events")
    func projectionBootstrapsUnknownNodeAnnouncementBeforeLaterEvents() throws {
        let newcomer = NodeIdentityGenerator.makeIdentity(name: "Newcomer", roles: ["worker"], capabilities: ["git"])
        let projectId = "sp_bootstrap"
        let events = try [
            signed(.nodeAnnounced, actor: newcomer, projectId: nil, logicalTime: 1, payload: [
                "name": .string("Newcomer"),
                "roles": .array([.string("worker")]),
                "capabilities": .array([.string("git")]),
                "status": .string(MeshNodeStatus.online.rawValue),
            ]),
            signed(.projectCreated, actor: newcomer, projectId: projectId, logicalTime: 2, payload: [
                "id": .string(projectId),
                "name": .string("Bootstrap"),
                "repoUrl": .string("git@example.com:bootstrap.git"),
            ]),
        ]

        let state = try NodeMeshProjection.project(events: events, base: MeshState())

        #expect(state.nodes.map(\.id) == [newcomer.nodeId])
        #expect(state.nodes.first?.publicKey == newcomer.publicKey)
        #expect(state.sharedProjects.map(\.id) == [projectId])
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

        let state = try NodeMeshProjection.project(events: events, base: baseState(nodes: [work]))

        let project = try #require(state.sharedProjects.first)
        #expect(project.name == "Updated Policy")
        #expect(project.policies == SharedProjectPolicies())
    }

    @Test("projection rejects conflicting duplicate event ids")
    func projectionRejectsConflictingDuplicateEventIDs() throws {
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let projectId = "sp_duplicate"
        let first = try signed(.projectCreated, actor: work, projectId: projectId, logicalTime: 1, eventId: "mesh_evt_duplicate", payload: [
            "id": .string(projectId),
            "name": .string("Duplicate"),
            "repoUrl": .string("git@example.com:duplicate.git"),
        ])
        let conflicting = try signed(.projectCreated, actor: work, projectId: projectId, logicalTime: 1, eventId: "mesh_evt_duplicate", payload: [
            "id": .string(projectId),
            "name": .string("Conflicting Duplicate"),
            "repoUrl": .string("git@example.com:duplicate.git"),
        ])

        #expect(throws: MeshEventVerificationError.eventConflict("mesh_evt_duplicate")) {
            _ = try NodeMeshProjection.project(events: [first, conflicting], base: baseState(nodes: [work]))
        }
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

    private func authorizedProjectEvents(
        projectId: String,
        owner: NodeIdentity,
        worker: NodeIdentity
    ) throws -> [SignedMeshEvent] {
        try [
            signed(.projectCreated, actor: owner, projectId: projectId, logicalTime: 1, payload: [
                "id": .string(projectId),
                "name": .string("Authorized"),
                "repoUrl": .string("git@example.com:authorized.git"),
                "defaultBranch": .string("main"),
            ]),
            signed(.projectMemberAdded, actor: owner, target: owner.nodeId, projectId: projectId, logicalTime: 2, payload: [
                "nodeId": .string(owner.nodeId),
                "localRepoPath": .string("/work/sloppy"),
                "role": .string("controller"),
                "permissions": .array([
                    .string(MeshPermission.projectWrite.rawValue),
                    .string(MeshPermission.taskCreate.rawValue),
                    .string(MeshPermission.taskAssign.rawValue),
                ]),
            ]),
            signed(.projectMemberAdded, actor: owner, target: worker.nodeId, projectId: projectId, logicalTime: 3, payload: [
                "nodeId": .string(worker.nodeId),
                "localRepoPath": .string("/home/sloppy"),
                "role": .string("worker"),
                "permissions": .array(MeshPermission.workerDefaults.rawValues.map(JSONValue.string)),
            ]),
        ]
    }

    private func forgedSignedEvent(
        type: MeshEventType,
        actorNodeId: String,
        signer: NodeIdentity,
        target: String? = nil,
        projectId: String? = nil,
        logicalTime: UInt64,
        payload: [String: JSONValue]
    ) throws -> SignedMeshEvent {
        let event = MeshEvent(
            id: "mesh_evt_" + UUID().uuidString,
            type: type,
            actorNodeId: actorNodeId,
            targetNodeId: target,
            projectId: projectId,
            logicalTime: logicalTime,
            payload: .object(payload)
        )
        return SignedMeshEvent(
            event: event,
            actorPublicKey: signer.publicKey,
            signature: try NodeIdentityGenerator.sign(
                challenge: try MeshEventSigner.signingData(for: event),
                privateKey: signer.privateKey
            )
        )
    }

    private func temporaryStateURL() -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("node-mesh-projection-tests", isDirectory: true)
        return directory.appendingPathComponent(UUID().uuidString + ".json")
    }

    private func baseState(nodes: [NodeIdentity]) -> MeshState {
        MeshState(nodes: nodes.map {
            MeshNodeRecord(
                id: $0.nodeId,
                name: $0.name,
                publicKey: $0.publicKey,
                roles: $0.roles,
                status: .online,
                capabilities: $0.capabilities
            )
        })
    }
}
