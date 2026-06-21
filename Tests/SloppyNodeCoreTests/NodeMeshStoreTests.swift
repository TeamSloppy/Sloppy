import Foundation
import Protocols
@testable import SloppyNodeCore
import Testing

@Suite("NodeMeshStore")
struct NodeMeshStoreTests {
    @Test("auth challenge and response envelopes round trip as typed payloads")
    func authChallengeAndResponseEnvelopesRoundTripAsTypedPayloads() throws {
        let challenge = MeshAuthChallengePayload(
            nonce: "nonce_123",
            nodeId: "node_worker",
            publicKey: "ed25519:worker_public",
            issuedAt: Date(timeIntervalSince1970: 1_716_000_000)
        )
        let challengeEnvelope = try MeshEnvelope(
            type: .authChallenge,
            from: "relay",
            to: "node_worker",
            payload: JSONValueCoder.encode(challenge)
        )

        let response = MeshAuthResponsePayload(
            nonce: challenge.nonce,
            nodeId: "node_worker",
            publicKey: "ed25519:worker_public",
            signature: "ed25519:worker_signature"
        )
        let responseEnvelope = try MeshEnvelope(
            type: .authResponse,
            from: "node_worker",
            to: "relay",
            payload: JSONValueCoder.encode(response)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decodedChallengeEnvelope = try decoder.decode(MeshEnvelope.self, from: encoder.encode(challengeEnvelope))
        let decodedChallenge = try JSONValueCoder.decode(MeshAuthChallengePayload.self, from: decodedChallengeEnvelope.payload)
        #expect(decodedChallengeEnvelope.type == .authChallenge)
        #expect(decodedChallenge.nonce == "nonce_123")
        #expect(decodedChallenge.nodeId == "node_worker")
        #expect(decodedChallenge.publicKey == "ed25519:worker_public")

        let decodedResponseEnvelope = try decoder.decode(MeshEnvelope.self, from: encoder.encode(responseEnvelope))
        let decodedResponse = try JSONValueCoder.decode(MeshAuthResponsePayload.self, from: decodedResponseEnvelope.payload)
        #expect(decodedResponseEnvelope.type == .authResponse)
        #expect(decodedResponse.nonce == "nonce_123")
        #expect(decodedResponse.nodeId == "node_worker")
        #expect(decodedResponse.publicKey == "ed25519:worker_public")
        #expect(decodedResponse.signature == "ed25519:worker_signature")
    }

    @Test("invite consume registers node once and rejects reuse")
    func inviteConsumeRegistersNodeOnceAndRejectsReuse() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let invite = try store.createInvite(
            networkId: "personal",
            name: "Home Mac",
            roles: ["worker", "autopilot"],
            capabilities: ["run_agent", "git"],
            ttlSeconds: 60
        )
        let identity = NodeIdentityGenerator.makeIdentity(
            name: "Home Mac",
            roles: invite.roles,
            capabilities: invite.capabilities
        )

        let node = try store.consumeInvite(
            token: invite.token,
            identity: identity,
            endpoint: "https://sloppy.example.com"
        )

        #expect(node.id == identity.nodeId)
        #expect(node.status == .online)
        #expect(node.endpoint == "https://sloppy.example.com")
        let state = try store.load()
        #expect(state.networkId == "personal")
        #expect(state.nodes.map(\.id) == [identity.nodeId])
        #expect(state.invites.first?.consumedByNodeId == identity.nodeId)

        do {
            _ = try store.consumeInvite(token: invite.token, identity: identity, endpoint: nil)
            Issue.record("Expected consumed invite to reject reuse")
        } catch let error as NodeMeshStoreError {
            #expect(error == .inviteConsumed)
        }
    }

    @Test("invite revoke removes pending invite and records audit entry")
    func inviteRevokeRemovesPendingInviteAndRecordsAuditEntry() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let invite = try store.createInvite(
            networkId: "personal",
            name: "Home Mac",
            roles: ["worker"],
            capabilities: ["run_agent"],
            ttlSeconds: 60
        )

        try store.revokeInvite(token: invite.token, actor: "api")

        let state = try store.load()
        #expect(state.invites.isEmpty)
        #expect(state.auditLog.last?.action == "node.invite.revoke")
        #expect(state.auditLog.last?.actor == "api")
        #expect(state.auditLog.last?.message == invite.token)
    }

    @Test("bundled invite token carries relay URL and worker public key")
    func bundledInviteTokenCarriesRelayURLAndWorkerPublicKey() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let identity = NodeIdentityGenerator.makeIdentity(
            name: "Home Mac",
            roles: ["worker"],
            capabilities: ["run_agent", "git"]
        )
        let invite = try store.createInvite(
            networkId: "personal",
            name: "Home Mac",
            roles: identity.roles,
            capabilities: identity.capabilities,
            ttlSeconds: 60,
            relayURL: "https://sloppy.example.com",
            nodeId: identity.nodeId,
            publicKey: identity.publicKey
        )

        let bundleToken = try #require(invite.bundleToken)
        let bundle = try MeshInviteBundle.parse(bundleToken)

        #expect(bundle.inviteToken == invite.token)
        #expect(bundle.relayURL == "https://sloppy.example.com")
        #expect(bundle.nodeId == identity.nodeId)
        #expect(bundle.publicKey == identity.publicKey)

        let node = try store.consumeInvite(
            token: bundleToken,
            identity: identity,
            endpoint: bundle.relayURL
        )

        #expect(node.publicKey == identity.publicKey)
        #expect(node.endpoint == "https://sloppy.example.com")
    }

    @Test("accept bundled invite registers expected node from one token")
    func acceptBundledInviteRegistersExpectedNodeFromOneToken() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let identity = NodeIdentityGenerator.makeIdentity(
            name: "Home Mac",
            roles: ["worker"],
            capabilities: ["run_agent", "git"]
        )
        let invite = try store.createInvite(
            networkId: "personal",
            name: "Home Mac",
            roles: identity.roles,
            capabilities: identity.capabilities,
            ttlSeconds: 60,
            relayURL: "https://sloppy.example.com",
            nodeId: identity.nodeId,
            publicKey: identity.publicKey
        )
        let bundleToken = try #require(invite.bundleToken)

        let node = try store.acceptInvite(token: bundleToken)

        #expect(node.id == identity.nodeId)
        #expect(node.name == "Home Mac")
        #expect(node.publicKey == identity.publicKey)
        #expect(node.roles == ["worker"])
        #expect(node.capabilities == ["run_agent", "git"])
        #expect(node.status == .offline)
        #expect(node.endpoint == "https://sloppy.example.com")
        let state = try store.load()
        #expect(state.invites.first?.consumedByNodeId == identity.nodeId)
        #expect(state.nodes.map(\.id) == [identity.nodeId])
    }

    @Test("shared project attach stores per-node local paths")
    func sharedProjectAttachStoresPerNodeLocalPaths() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let controller = NodeIdentityGenerator.makeIdentity(name: "Laptop", roles: ["client"], capabilities: ["git"])
        let worker = NodeIdentityGenerator.makeIdentity(name: "Home Mac", roles: ["worker"], capabilities: ["git"])
        try store.registerNode(controller)
        try store.registerNode(worker)
        let project = try store.createSharedProject(
            name: "My Project",
            repoUrl: "git@github.com:me/my-project.git",
            defaultBranch: "main"
        )

        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: controller.nodeId,
            localRepoPath: "/Users/me/dev/my-project",
            role: "controller",
            permissions: ["project.read", "task.assign"]
        )
        let updated = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: worker.nodeId,
            localRepoPath: "/Users/home/dev/my-project",
            role: "worker",
            permissions: ["project.read", "task.update"]
        )

        #expect(updated.repoUrl == "git@github.com:me/my-project.git")
        #expect(updated.members.count == 2)
        #expect(updated.members.first(where: { $0.nodeId == controller.nodeId })?.localRepoPath == "/Users/me/dev/my-project")
        #expect(updated.members.first(where: { $0.nodeId == worker.nodeId })?.localRepoPath == "/Users/home/dev/my-project")
        #expect(updated.eventScope == "sharedProject:\(project.id)")
    }

    @Test("shared project update and member removal are audited")
    func sharedProjectUpdateAndMemberRemovalAreAudited() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let worker = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["git"])
        try store.registerNode(worker)
        let project = try store.createSharedProject(name: "Old", repoUrl: "git@example.com:old.git")
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: worker.nodeId,
            localRepoPath: "/repo",
            role: "worker",
            permissions: MeshPermission.workerDefaults.rawValues
        )

        let updated = try store.updateSharedProject(
            projectIdOrName: project.id,
            name: "New",
            repoUrl: "git@example.com:new.git",
            defaultBranch: "trunk",
            policies: SharedProjectPolicies(requireTestsBeforeReady: false),
            actor: "node_laptop"
        )
        #expect(updated.name == "New")
        #expect(updated.repoUrl == "git@example.com:new.git")
        #expect(updated.defaultBranch == "trunk")
        #expect(updated.policies.requireTestsBeforeReady == false)

        let withoutMember = try store.removeSharedProjectMember(projectIdOrName: updated.id, nodeId: worker.nodeId, actor: "node_laptop")
        #expect(withoutMember.members.isEmpty)
        let state = try store.load()
        #expect(state.auditLog.map(\.action).contains("shared_project.update"))
        #expect(state.auditLog.last?.action == "shared_project.member.remove")
        #expect(state.auditLog.last?.target == worker.nodeId)
    }

    @Test("shared project metadata changes publish sync envelopes")
    func sharedProjectMetadataChangesPublishSyncEnvelopes() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let worker = NodeIdentityGenerator.makeIdentity(name: "Home Mac", roles: ["worker"], capabilities: ["git"])
        try store.registerNode(worker)
        let project = try store.createSharedProject(name: "My Project", repoUrl: "git@example.com:repo.git")

        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: worker.nodeId,
            localRepoPath: "/Users/home/dev/repo",
            role: "worker",
            permissions: MeshPermission.workerDefaults.rawValues
        )
        _ = try store.updateSharedProject(projectIdOrName: project.id, defaultBranch: "trunk")

        let syncEvents = try store.load().envelopes.filter { $0.type == .projectSyncEvent }
        #expect(syncEvents.count == 2)
        #expect(syncEvents.last?.to == worker.nodeId)
        #expect(syncEvents.last?.scope == "sharedProject:\(project.id)")
        #expect(syncEvents.last?.payload.asObject?["action"] == .string("shared_project.update"))
        #expect(syncEvents.last?.payload.asObject?["projectId"] == .string(project.id))
    }

    @Test("mesh permissions encode stable protocol values")
    func meshPermissionsEncodeStableProtocolValues() throws {
        #expect(MeshPermission.projectRead.rawValue == "project.read")
        #expect(MeshPermission.projectWrite.rawValue == "project.write")
        #expect(MeshPermission.taskCreate.rawValue == "task.create")
        #expect(MeshPermission.taskAssign.rawValue == "task.assign")
        #expect(MeshPermission.taskUpdate.rawValue == "task.update")
        #expect(MeshPermission.nodeRPC.rawValue == "node.rpc")
        #expect(MeshPermission.nodeShell.rawValue == "node.shell")
        #expect(MeshPermission.nodeAgentSpawn.rawValue == "node.agent.spawn")
        #expect(MeshPermission.nodeFilesRead.rawValue == "node.files.read")
        #expect(MeshPermission.nodeFilesWrite.rawValue == "node.files.write")
        #expect(MeshPermission.nodeRelay.rawValue == "node.relay")

        let member = SharedProjectMember(
            nodeId: "node_worker",
            localRepoPath: "/repo",
            role: "worker",
            permissions: MeshPermission.workerDefaults.rawValues
        )
        let data = try JSONEncoder().encode(member)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["permissions"] as? [String] == ["project.read", "task.update", "node.rpc"])
    }

    @Test("mesh store appends signed events idempotently")
    func meshStoreAppendsSignedEventsIdempotently() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let identity = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        try store.registerNode(identity)
        let event = MeshEvent(
            id: "evt_node_announce",
            type: .nodeAnnounced,
            actorNodeId: identity.nodeId,
            logicalTime: 1,
            payload: .object([
                "name": .string(identity.name),
                "roles": .array(identity.roles.map(JSONValue.string)),
                "capabilities": .array(identity.capabilities.map(JSONValue.string)),
                "status": .string(MeshNodeStatus.online.rawValue),
            ])
        )
        let signed = try MeshEventSigner.sign(event, identity: identity)

        _ = try store.appendEvent(signed, expectedActorPublicKey: identity.publicKey)
        _ = try store.appendEvent(signed, expectedActorPublicKey: identity.publicKey)

        let state = try store.load()
        #expect(state.events.map(\.event.id) == ["evt_node_announce"])
        #expect(state.auditLog.last?.action == "event.append")
    }

    @Test("mesh store rejects signed event with wrong public key")
    func meshStoreRejectsSignedEventWithWrongPublicKey() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let identity = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let other = NodeIdentityGenerator.makeIdentity(name: "Other", roles: ["client"], capabilities: ["git"])
        let signed = try MeshEventSigner.sign(
            MeshEvent(type: .taskCreated, actorNodeId: identity.nodeId, logicalTime: 1),
            identity: identity
        )

        #expect(throws: MeshEventVerificationError.invalidSignature) {
            _ = try store.appendEvent(signed, expectedActorPublicKey: other.publicKey)
        }
    }

    @Test("mesh store rejects conflicting event with duplicate id")
    func meshStoreRejectsConflictingEventWithDuplicateId() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let identity = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        try store.registerNode(identity)
        let first = try MeshEventSigner.sign(
            MeshEvent(
                id: "evt_node_announce",
                type: .nodeAnnounced,
                actorNodeId: identity.nodeId,
                logicalTime: 1,
                payload: .object([
                    "name": .string("Work"),
                    "roles": .array([.string("client")]),
                    "capabilities": .array([.string("git")]),
                ])
            ),
            identity: identity
        )
        let conflicting = try MeshEventSigner.sign(
            MeshEvent(
                id: "evt_node_announce",
                type: .nodeAnnounced,
                actorNodeId: identity.nodeId,
                logicalTime: 1,
                payload: .object([
                    "name": .string("Changed"),
                    "roles": .array([.string("client")]),
                    "capabilities": .array([.string("git")]),
                ])
            ),
            identity: identity
        )

        _ = try store.appendEvent(first, expectedActorPublicKey: identity.publicKey)

        #expect(throws: MeshEventVerificationError.eventConflict("evt_node_announce")) {
            _ = try store.appendEvent(conflicting, expectedActorPublicKey: identity.publicKey)
        }

        let state = try store.load()
        #expect(state.events.count == 1)
        #expect(state.events.first?.event.id == first.event.id)
        #expect(state.events.first?.event.payload.asObject?["name"] == .string("Work"))
        #expect(state.auditLog.last?.message == "event_conflict")
    }

    @Test("mesh store rejects replay invalid signed event before saving")
    func meshStoreRejectsReplayInvalidSignedEventBeforeSaving() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
        let projectId = "sp_event_backed"
        let prefix = try [
            signedEvent(.projectCreated, actor: work, projectId: projectId, logicalTime: 1, payload: [
                "id": .string(projectId),
                "name": .string("Event Backed"),
                "repoUrl": .string("git@example.com:event-backed.git"),
            ]),
            signedEvent(.projectMemberAdded, actor: work, target: work.nodeId, projectId: projectId, logicalTime: 2, payload: [
                "nodeId": .string(work.nodeId),
                "localRepoPath": .string("/work/event-backed"),
                "role": .string("controller"),
                "permissions": .array([
                    .string(MeshPermission.projectWrite.rawValue),
                ]),
            ]),
            signedEvent(.projectMemberAdded, actor: work, target: home.nodeId, projectId: projectId, logicalTime: 3, payload: [
                "nodeId": .string(home.nodeId),
                "localRepoPath": .string("/home/event-backed"),
                "role": .string("worker"),
                "permissions": .array(MeshPermission.workerDefaults.rawValues.map(JSONValue.string)),
            ]),
        ]
        try store.save(MeshState(nodes: baseNodes([work, home]), events: prefix))
        let invalid = try signedEvent(.aclGranted, actor: home, target: home.nodeId, projectId: projectId, logicalTime: 4, payload: [
            "permissions": .array([
                .string(MeshPermission.nodeShell.rawValue),
            ]),
        ])

        #expect(throws: (any Error).self) {
            _ = try store.appendEvent(invalid, expectedActorPublicKey: home.publicKey)
        }

        let state = try store.load()
        #expect(state.events.map(\.event.id) == prefix.map(\.event.id))
    }

    @Test("list methods merge projected and legacy projects and tasks when events exist")
    func listMethodsMergeProjectedAndLegacyProjectsAndTasksWhenEventsExist() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let staleProject = SharedProjectRecord(id: "sp_stale", name: "Stale", repoUrl: "git@example.com:stale.git")
        let staleTask = MeshTaskRecord(id: "mesh_task_stale", projectId: staleProject.id, title: "Stale", assignedNodeId: work.nodeId)
        let projectId = "sp_projected"
        let events = try [
            signedEvent(.projectCreated, actor: work, projectId: projectId, logicalTime: 1, payload: [
                "id": .string(projectId),
                "name": .string("Projected"),
                "repoUrl": .string("git@example.com:projected.git"),
                "defaultBranch": .string("main"),
            ]),
            signedEvent(.projectMemberAdded, actor: work, target: work.nodeId, projectId: projectId, logicalTime: 2, payload: [
                "nodeId": .string(work.nodeId),
                "localRepoPath": .string("/work/projected"),
                "role": .string("controller"),
                "permissions": .array([
                    .string(MeshPermission.projectWrite.rawValue),
                    .string(MeshPermission.taskCreate.rawValue),
                ]),
            ]),
            signedEvent(.taskCreated, actor: work, projectId: projectId, logicalTime: 3, payload: [
                "taskId": .string("mesh_task_projected"),
                "title": .string("Projected task"),
            ]),
        ]
        try store.save(MeshState(
            nodes: baseNodes([work]),
            sharedProjects: [staleProject],
            tasks: [staleTask],
            events: events
        ))

        #expect(try store.listSharedProjects().map(\.id) == [projectId, staleProject.id])
        #expect(Set(try store.listTasks().map(\.id)) == ["mesh_task_projected", staleTask.id])
        #expect(try store.listTasks(projectIdOrName: "Projected").map(\.id) == ["mesh_task_projected"])
        #expect(try store.listTasks(projectIdOrName: "Stale").map(\.id) == [staleTask.id])
    }

    @Test("signed dispatch keeps legacy shared project visible")
    func signedDispatchKeepsLegacySharedProjectVisible() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
        try store.registerNode(work)
        try store.registerNode(home)
        let project = try store.createSharedProject(
            id: "sp_legacy",
            name: "Legacy",
            repoUrl: "git@example.com:legacy.git"
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: work.nodeId,
            localRepoPath: "/work/legacy",
            role: "controller",
            permissions: [MeshPermission.taskCreate.rawValue, MeshPermission.taskAssign.rawValue]
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: home.nodeId,
            localRepoPath: "/home/legacy",
            role: "worker",
            permissions: MeshPermission.workerDefaults.rawValues
        )

        _ = try store.dispatchTask(
            projectIdOrName: project.id,
            title: "Run build",
            assignedNodeId: home.nodeId,
            actorIdentity: work
        )

        #expect(try store.load().events.map(\.event.type).contains(.taskCreated))
        #expect(try store.listSharedProjects().map(\.id) == [project.id])
    }

    @Test("accepted signed dispatch remains replayable after legacy member removal")
    func acceptedSignedDispatchRemainsReplayableAfterLegacyMemberRemoval() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
        try store.registerNode(work)
        try store.registerNode(home)
        let project = try store.createSharedProject(
            id: "sp_legacy_replay",
            name: "Legacy Replay",
            repoUrl: "git@example.com:legacy-replay.git"
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: work.nodeId,
            localRepoPath: "/work/legacy-replay",
            role: "controller",
            permissions: [
                MeshPermission.taskCreate.rawValue,
                MeshPermission.taskAssign.rawValue,
            ]
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: home.nodeId,
            localRepoPath: "/home/legacy-replay",
            role: "worker",
            permissions: MeshPermission.workerDefaults.rawValues
        )

        let task = try store.dispatchTask(
            projectIdOrName: project.id,
            title: "Run build",
            assignedNodeId: home.nodeId,
            actorIdentity: work
        )
        _ = try store.removeSharedProjectMember(projectIdOrName: project.id, nodeId: work.nodeId, actor: "local")

        let projected = try store.projectedState()
        let projectedTask = try #require(projected.tasks.first(where: { $0.id == task.id }))
        #expect(projectedTask.assignedNodeId == home.nodeId)
        #expect(try store.listTasks(projectIdOrName: project.id).map(\.id).contains(task.id))
    }

    @Test("signed project creation cannot shadow an existing legacy project without project write")
    func signedProjectCreationCannotShadowExistingLegacyProjectWithoutProjectWrite() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let owner = NodeIdentityGenerator.makeIdentity(name: "Owner", roles: ["client"], capabilities: ["git"])
        let rogue = NodeIdentityGenerator.makeIdentity(name: "Rogue", roles: ["worker"], capabilities: ["git"])
        let legacyProject = SharedProjectRecord(
            id: "sp_legacy",
            name: "Legacy",
            repoUrl: "git@example.com:legacy.git",
            members: [
                SharedProjectMember(
                    nodeId: owner.nodeId,
                    localRepoPath: "/work/legacy",
                    role: "controller",
                    permissions: [MeshPermission.projectWrite.rawValue]
                ),
            ]
        )
        try store.save(MeshState(
            nodes: baseNodes([owner, rogue]),
            sharedProjects: [legacyProject]
        ))

        let shadowAttempt = try signedEvent(.projectCreated, actor: rogue, projectId: legacyProject.id, logicalTime: 1, payload: [
            "id": .string(legacyProject.id),
            "name": .string("Shadow Legacy"),
            "repoUrl": .string("git@example.com:shadow.git"),
            "defaultBranch": .string("trunk"),
        ])

        #expect(throws: MeshEventVerificationError.unauthorized(MeshPermission.projectWrite.rawValue)) {
            _ = try store.appendEvent(shadowAttempt, expectedActorPublicKey: rogue.publicKey)
        }

        let state = try store.load()
        #expect(state.events.isEmpty)
        #expect(try store.listSharedProjects().map(\.id) == [legacyProject.id])
        let project = try #require(try store.listSharedProjects().first)
        #expect(project.name == legacyProject.name)
        #expect(project.repoUrl == legacyProject.repoUrl)
    }

    @Test("signed dispatch falls back to legacy project when unrelated projected project exists")
    func signedDispatchFallsBackToLegacyProjectWhenUnrelatedProjectedProjectExists() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
        try store.registerNode(work)
        try store.registerNode(home)
        let legacyProject = try store.createSharedProject(
            id: "sp_legacy",
            name: "Legacy",
            repoUrl: "git@example.com:legacy.git"
        )
        _ = try store.attachMember(
            projectIdOrName: legacyProject.id,
            nodeId: work.nodeId,
            localRepoPath: "/work/legacy",
            role: "controller",
            permissions: [MeshPermission.taskCreate.rawValue, MeshPermission.taskAssign.rawValue]
        )
        _ = try store.attachMember(
            projectIdOrName: legacyProject.id,
            nodeId: home.nodeId,
            localRepoPath: "/home/legacy",
            role: "worker",
            permissions: MeshPermission.workerDefaults.rawValues
        )

        let projectedProjectId = "sp_projected"
        let projectedEvents = try [
            signedEvent(.projectCreated, actor: work, projectId: projectedProjectId, logicalTime: 1, payload: [
                "id": .string(projectedProjectId),
                "name": .string("Projected"),
                "repoUrl": .string("git@example.com:projected.git"),
                "defaultBranch": .string("main"),
            ]),
            signedEvent(.projectMemberAdded, actor: work, target: work.nodeId, projectId: projectedProjectId, logicalTime: 2, payload: [
                "nodeId": .string(work.nodeId),
                "localRepoPath": .string("/work/projected"),
                "role": .string("controller"),
                "permissions": .array([
                    .string(MeshPermission.projectWrite.rawValue),
                ]),
            ]),
        ]
        for event in projectedEvents {
            _ = try store.appendEvent(event, expectedActorPublicKey: work.publicKey)
        }

        let task = try store.dispatchTask(
            projectIdOrName: legacyProject.id,
            title: "Run build",
            assignedNodeId: home.nodeId,
            actorIdentity: work
        )

        #expect(task.projectId == legacyProject.id)
        #expect(task.assignedNodeId == home.nodeId)
        #expect(Set(try store.listSharedProjects().map(\.id)) == [legacyProject.id, projectedProjectId])
        #expect(try store.load().events.map(\.event.type).suffix(2) == [.taskCreated, .taskAssigned])
    }

    @Test("list tasks merges legacy and projected tasks when events exist")
    func listTasksMergesLegacyAndProjectedTasksWhenEventsExist() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
        let project = SharedProjectRecord(
            id: "sp_mixed",
            name: "Mixed",
            repoUrl: "git@example.com:mixed.git",
            members: [
                SharedProjectMember(
                    nodeId: work.nodeId,
                    localRepoPath: "/work/mixed",
                    role: "controller",
                    permissions: [MeshPermission.taskCreate.rawValue, MeshPermission.taskAssign.rawValue]
                ),
                SharedProjectMember(
                    nodeId: home.nodeId,
                    localRepoPath: "/home/mixed",
                    role: "worker",
                    permissions: MeshPermission.workerDefaults.rawValues
                ),
            ]
        )
        let legacyTask = MeshTaskRecord(
            id: "mesh_task_legacy",
            projectId: project.id,
            title: "Legacy task",
            assignedNodeId: home.nodeId,
            status: .dispatched,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let events = try [
            signedEvent(.taskCreated, actor: work, projectId: project.id, logicalTime: 1, payload: [
                "taskId": .string("mesh_task_projected"),
                "title": .string("Projected task"),
                "assignedNodeId": .string(home.nodeId),
            ]),
            signedEvent(.taskAssigned, actor: work, target: home.nodeId, projectId: project.id, logicalTime: 2, payload: [
                "taskId": .string("mesh_task_projected"),
                "assignedNodeId": .string(home.nodeId),
            ]),
        ]
        try store.save(MeshState(
            nodes: baseNodes([work, home]),
            sharedProjects: [project],
            tasks: [legacyTask],
            events: events
        ))

        #expect(Set(try store.listTasks().map(\.id)) == ["mesh_task_legacy", "mesh_task_projected"])
        #expect(Set(try store.listTasks(projectIdOrName: project.name).map(\.id)) == ["mesh_task_legacy", "mesh_task_projected"])
    }

    @Test("list tasks keeps same task id in different projects")
    func listTasksKeepsSameTaskIDInDifferentProjects() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
        let legacyProject = SharedProjectRecord(
            id: "sp_legacy",
            name: "Legacy",
            repoUrl: "git@example.com:legacy.git"
        )
        let projectedProject = SharedProjectRecord(
            id: "sp_projected",
            name: "Projected",
            repoUrl: "git@example.com:projected.git",
            members: [
                SharedProjectMember(
                    nodeId: work.nodeId,
                    localRepoPath: "/work/projected",
                    role: "controller",
                    permissions: [
                        MeshPermission.projectWrite.rawValue,
                        MeshPermission.taskCreate.rawValue,
                        MeshPermission.taskAssign.rawValue,
                    ]
                ),
                SharedProjectMember(
                    nodeId: home.nodeId,
                    localRepoPath: "/home/projected",
                    role: "worker",
                    permissions: MeshPermission.workerDefaults.rawValues
                ),
            ]
        )
        let taskId = "mesh_task_shared_id"
        let legacyTask = MeshTaskRecord(
            id: taskId,
            projectId: legacyProject.id,
            title: "Legacy task",
            assignedNodeId: home.nodeId,
            status: .dispatched,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let events = try [
            signedEvent(.taskCreated, actor: work, projectId: projectedProject.id, logicalTime: 1, payload: [
                "taskId": .string(taskId),
                "title": .string("Projected task"),
            ]),
            signedEvent(.taskAssigned, actor: work, target: home.nodeId, projectId: projectedProject.id, logicalTime: 2, payload: [
                "taskId": .string(taskId),
                "assignedNodeId": .string(home.nodeId),
            ]),
        ]
        try store.save(MeshState(
            nodes: baseNodes([work, home]),
            sharedProjects: [legacyProject, projectedProject],
            tasks: [legacyTask],
            events: events
        ))

        let tasks = try store.listTasks()
        #expect(tasks.count == 2)
        #expect(Set(tasks.map(\.projectId)) == [legacyProject.id, projectedProject.id])
        #expect(try store.listTasks(projectIdOrName: legacyProject.id).map(\.title) == ["Legacy task"])
        #expect(try store.listTasks(projectIdOrName: projectedProject.id).map(\.title) == ["Projected task"])
    }

    @Test("projected nodes merge with stored nodes for listing and routing")
    func projectedNodesMergeWithStoredNodesForListingAndRouting() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let stored = NodeIdentityGenerator.makeIdentity(name: "Stored", roles: ["client"], capabilities: ["git"])
        let projected = NodeIdentityGenerator.makeIdentity(name: "Projected", roles: ["worker"], capabilities: ["git"])
        let announce = try signedEvent(.nodeAnnounced, actor: projected, projectId: nil, logicalTime: 1, payload: [
            "name": .string(projected.name),
            "roles": .array(projected.roles.map(JSONValue.string)),
            "capabilities": .array(projected.capabilities.map(JSONValue.string)),
            "status": .string(MeshNodeStatus.online.rawValue),
        ])
        try store.save(MeshState(nodes: baseNodes([stored]), events: [announce]))

        #expect(Set(try store.listNodes().map(\.id)) == [stored.nodeId, projected.nodeId])
        _ = try store.routeEnvelope(MeshEnvelope(type: .rpcRequest, from: stored.nodeId, to: projected.nodeId))
        #expect(try store.load().envelopes.last?.to == projected.nodeId)
    }

    @Test("mesh state decodes legacy JSON without event fields")
    func meshStateDecodesLegacyJSONWithoutEventFields() throws {
        let legacyJSON = """
        {
          "networkId" : "personal",
          "networkName" : "Personal Mesh",
          "nodes" : [],
          "invites" : [],
          "sharedProjects" : [],
          "tasks" : [],
          "envelopes" : [],
          "auditLog" : []
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let state = try decoder.decode(MeshState.self, from: legacyJSON)

        #expect(state.events.isEmpty)
        #expect(state.eventCursors.isEmpty)
    }

    @Test("mesh state preserves legacy default network name")
    func meshStatePreservesLegacyDefaultNetworkName() throws {
        #expect(MeshState().networkName == "personal")

        let legacyJSON = """
        {
          "networkId" : "personal",
          "nodes" : [],
          "invites" : [],
          "sharedProjects" : [],
          "tasks" : [],
          "envelopes" : [],
          "auditLog" : []
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let state = try decoder.decode(MeshState.self, from: legacyJSON)

        #expect(state.networkName == "personal")
    }

    @Test("mesh store lists events after cursor with limit")
    func meshStoreListsEventsAfterCursorWithLimit() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let identity = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        try store.registerNode(identity)
        let first = try MeshEventSigner.sign(
            MeshEvent(id: "evt_1", type: .nodeAnnounced, actorNodeId: identity.nodeId, logicalTime: 1),
            identity: identity
        )
        let second = try MeshEventSigner.sign(
            MeshEvent(id: "evt_2", type: .nodeAnnounced, actorNodeId: identity.nodeId, logicalTime: 2),
            identity: identity
        )
        let third = try MeshEventSigner.sign(
            MeshEvent(id: "evt_3", type: .nodeAnnounced, actorNodeId: identity.nodeId, logicalTime: 3),
            identity: identity
        )

        _ = try store.appendEvent(first, expectedActorPublicKey: identity.publicKey)
        _ = try store.appendEvent(second, expectedActorPublicKey: identity.publicKey)
        _ = try store.appendEvent(third, expectedActorPublicKey: identity.publicKey)

        #expect(try store.listEvents(after: "evt_1", limit: 1).map(\.event.id) == ["evt_2"])
        #expect(try store.listEvents(after: "evt_2", limit: 5).map(\.event.id) == ["evt_3"])
        #expect(try store.listEvents(after: "evt_3", limit: 5).isEmpty)
    }

    @Test("routing envelope to unknown node audits denial")
    func routingEnvelopeToUnknownNodeAuditsDenial() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())

        do {
            _ = try store.routeEnvelope(MeshEnvelope(type: .rpcRequest, from: "node_laptop", to: "node_missing"))
            Issue.record("Expected unknown target to be rejected")
        } catch let error as NodeMeshStoreError {
            #expect(error == .nodeMissing("node_missing"))
        }

        let state = try store.load()
        #expect(state.envelopes.isEmpty)
        #expect(state.auditLog.last?.action == "rpc.request")
        #expect(state.auditLog.last?.allowed == false)
        #expect(state.auditLog.last?.target == "node_missing")
    }

    @Test("task dispatch requires project member permission")
    func taskDispatchRequiresProjectMemberPermission() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let worker = NodeIdentityGenerator.makeIdentity(name: "Home Mac", roles: ["worker"], capabilities: ["git"])
        try store.registerNode(worker)
        let project = try store.createSharedProject(name: "My Project", repoUrl: "git@example.com:repo.git")
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: worker.nodeId,
            localRepoPath: "/Users/home/dev/repo",
            role: "worker",
            permissions: ["project.read"]
        )

        do {
            _ = try store.dispatchTask(projectIdOrName: project.id, title: "Implement feature", assignedNodeId: worker.nodeId)
            Issue.record("Expected missing task permission to reject dispatch")
        } catch let error as NodeMeshStoreError {
            #expect(error == .permissionDenied("task.dispatch"))
        }

        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: worker.nodeId,
            localRepoPath: "/Users/home/dev/repo",
            role: "worker",
            permissions: ["project.read", "task.update"]
        )
        let task = try store.dispatchTask(
            projectIdOrName: project.id,
            title: "Implement feature",
            assignedNodeId: worker.nodeId,
            actor: "node_laptop"
        )

        #expect(task.status == .dispatched)
        #expect(task.assignedNodeId == worker.nodeId)
        let state = try store.load()
        #expect(state.envelopes.last?.type == .taskDispatch)
        #expect(state.envelopes.last?.to == worker.nodeId)
        #expect(state.auditLog.last?.allowed == true)
        #expect(state.auditLog.last?.action == "task.dispatch")
    }

    @Test("task status update records review branch result")
    func taskStatusUpdateRecordsReviewBranchResult() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let worker = NodeIdentityGenerator.makeIdentity(name: "Home Mac", roles: ["worker"], capabilities: ["git"])
        try store.registerNode(worker)
        let project = try store.createSharedProject(name: "My Project", repoUrl: "git@example.com:repo.git")
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: worker.nodeId,
            localRepoPath: "/Users/home/dev/repo",
            role: "worker",
            permissions: ["task.update"]
        )
        let task = try store.dispatchTask(projectIdOrName: project.id, title: "Implement feature", assignedNodeId: worker.nodeId)

        let updated = try store.updateTaskStatus(
            taskId: task.id,
            status: .readyForReview,
            actor: worker.nodeId,
            branch: "agent/home-mac/task-1",
            commit: "abc123",
            summary: "Implemented feature"
        )

        #expect(updated.status == .readyForReview)
        #expect(updated.branch == "agent/home-mac/task-1")
        #expect(updated.commit == "abc123")
        #expect(updated.summary == "Implemented feature")
        let state = try store.load()
        #expect(state.envelopes.last?.type == .taskStatusUpdate)
        #expect(state.auditLog.last?.message == "ready_for_review")
    }

    @Test("task status update requires project when task id is duplicated")
    func taskStatusUpdateRequiresProjectWhenTaskIDIsDuplicated() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let sharedTaskId = "mesh_task_shared_id"
        let projectA = SharedProjectRecord(id: "sp_a", name: "A", repoUrl: "git@example.com:a.git")
        let projectB = SharedProjectRecord(id: "sp_b", name: "B", repoUrl: "git@example.com:b.git")
        try store.save(MeshState(
            sharedProjects: [projectA, projectB],
            tasks: [
                MeshTaskRecord(id: sharedTaskId, projectId: projectA.id, title: "A", assignedNodeId: "node_home"),
                MeshTaskRecord(id: sharedTaskId, projectId: projectB.id, title: "B", assignedNodeId: "node_home"),
            ]
        ))

        #expect(throws: NodeMeshStoreError.taskAmbiguous(sharedTaskId)) {
            _ = try store.updateTaskStatus(
                taskId: sharedTaskId,
                status: .readyForReview,
                actor: "node_home"
            )
        }

        let updated = try store.updateTaskStatus(
            taskId: sharedTaskId,
            projectIdOrName: projectB.id,
            status: .readyForReview,
            actor: "node_home"
        )

        let state = try store.load()
        #expect(updated.projectId == projectB.id)
        #expect(state.tasks.first(where: { $0.projectId == projectA.id })?.status == .queued)
        #expect(state.tasks.first(where: { $0.projectId == projectB.id })?.status == .readyForReview)
    }

    @Test("dispatch task with actor identity writes signed task events")
    func dispatchTaskWithActorIdentityWritesSignedTaskEvents() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
        try store.registerNode(work)
        try store.registerNode(home)
        let project = try store.createSharedProject(
            id: "sp_sloppy",
            name: "Sloppy",
            repoUrl: "git@example.com:sloppy.git"
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: work.nodeId,
            localRepoPath: "/work/sloppy",
            role: "controller",
            permissions: [
                MeshPermission.projectWrite.rawValue,
                MeshPermission.taskCreate.rawValue,
                MeshPermission.taskAssign.rawValue,
            ]
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: home.nodeId,
            localRepoPath: "/home/sloppy",
            role: "worker",
            permissions: MeshPermission.workerDefaults.rawValues
        )

        let task = try store.dispatchTask(
            projectIdOrName: project.id,
            title: "Run build",
            assignedNodeId: home.nodeId,
            actorIdentity: work
        )

        let state = try store.load()
        #expect(task.status == .dispatched)
        #expect(state.events.map(\.event.type).contains(.taskCreated))
        #expect(state.events.map(\.event.type).contains(.taskAssigned))
    }

    @Test("dispatch task with actor identity rejects non-member assignee")
    func dispatchTaskWithActorIdentityRejectsNonMemberAssignee() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
        try store.registerNode(work)
        try store.registerNode(home)
        let project = try store.createSharedProject(
            id: "sp_sloppy",
            name: "Sloppy",
            repoUrl: "git@example.com:sloppy.git"
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: work.nodeId,
            localRepoPath: "/work/sloppy",
            role: "controller",
            permissions: [
                MeshPermission.projectWrite.rawValue,
                MeshPermission.taskCreate.rawValue,
                MeshPermission.taskAssign.rawValue,
            ]
        )

        do {
            _ = try store.dispatchTask(
                projectIdOrName: project.id,
                title: "Run build",
                assignedNodeId: home.nodeId,
                actorIdentity: work
            )
            Issue.record("Expected non-member assignee to reject signed dispatch")
        } catch let error as NodeMeshStoreError {
            #expect(error == .permissionDenied("task.dispatch"))
        }

        let state = try store.load()
        #expect(state.events.isEmpty)
    }

    @Test("dispatch task with actor identity rejects non-member actor")
    func dispatchTaskWithActorIdentityRejectsNonMemberActor() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
        try store.registerNode(work)
        try store.registerNode(home)
        let project = try store.createSharedProject(
            id: "sp_sloppy",
            name: "Sloppy",
            repoUrl: "git@example.com:sloppy.git"
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: home.nodeId,
            localRepoPath: "/home/sloppy",
            role: "worker",
            permissions: MeshPermission.workerDefaults.rawValues
        )

        do {
            _ = try store.dispatchTask(
                projectIdOrName: project.id,
                title: "Run build",
                assignedNodeId: home.nodeId,
                actorIdentity: work
            )
            Issue.record("Expected non-member actor to reject signed dispatch")
        } catch let error as NodeMeshStoreError {
            #expect(error == .permissionDenied("task.dispatch"))
        }

        let state = try store.load()
        #expect(state.events.isEmpty)
    }

    @Test("batch append leaves no task events when second dispatch event is invalid")
    func batchAppendLeavesNoTaskEventsWhenSecondDispatchEventIsInvalid() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
        let rogue = NodeIdentityGenerator.makeIdentity(name: "Rogue", roles: ["worker"], capabilities: ["git"])
        try store.registerNode(work)
        try store.registerNode(home)
        try store.registerNode(rogue)
        let project = try store.createSharedProject(
            id: "sp_sloppy",
            name: "Sloppy",
            repoUrl: "git@example.com:sloppy.git"
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: work.nodeId,
            localRepoPath: "/work/sloppy",
            role: "controller",
            permissions: [
                MeshPermission.projectWrite.rawValue,
                MeshPermission.taskCreate.rawValue,
                MeshPermission.taskAssign.rawValue,
            ]
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: home.nodeId,
            localRepoPath: "/home/sloppy",
            role: "worker",
            permissions: MeshPermission.workerDefaults.rawValues
        )
        let taskId = "mesh_task_atomic"
        let created = try signedEvent(.taskCreated, actor: work, projectId: project.id, logicalTime: 1, payload: [
            "taskId": .string(taskId),
            "title": .string("Run build"),
            "assignedNodeId": .string(home.nodeId),
        ])
        let invalidAssigned = try signedEvent(.taskAssigned, actor: work, target: rogue.nodeId, projectId: project.id, logicalTime: 2, payload: [
            "taskId": .string(taskId),
            "assignedNodeId": .string(rogue.nodeId),
        ])

        #expect(throws: MeshEventVerificationError.unauthorized("task.dispatch")) {
            _ = try store.appendEvents([created, invalidAssigned], expectedActorPublicKey: work.publicKey)
        }

        let state = try store.load()
        #expect(state.events.contains(where: { $0.event.type == .taskCreated }) == false)
        #expect(state.events.contains(where: { $0.event.type == .taskAssigned }) == false)
    }

    @Test("signed dispatch prefers projected member removal over stale legacy membership")
    func signedDispatchPrefersProjectedMemberRemovalOverStaleLegacyMembership() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
        try store.registerNode(work)
        try store.registerNode(home)
        let project = try store.createSharedProject(
            id: "sp_sloppy",
            name: "Sloppy",
            repoUrl: "git@example.com:sloppy.git"
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: work.nodeId,
            localRepoPath: "/work/sloppy",
            role: "controller",
            permissions: [
                MeshPermission.projectWrite.rawValue,
                MeshPermission.taskCreate.rawValue,
                MeshPermission.taskAssign.rawValue,
            ]
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: home.nodeId,
            localRepoPath: "/home/sloppy",
            role: "worker",
            permissions: MeshPermission.workerDefaults.rawValues
        )

        let events = try [
            signedEvent(.projectCreated, actor: work, projectId: project.id, logicalTime: 1, payload: [
                "id": .string(project.id),
                "name": .string(project.name),
                "repoUrl": .string(project.repoUrl),
                "defaultBranch": .string(project.defaultBranch),
            ]),
            signedEvent(.projectMemberAdded, actor: work, target: work.nodeId, projectId: project.id, logicalTime: 2, payload: [
                "nodeId": .string(work.nodeId),
                "localRepoPath": .string("/work/sloppy"),
                "role": .string("controller"),
                "permissions": .array([
                    .string(MeshPermission.projectWrite.rawValue),
                    .string(MeshPermission.taskCreate.rawValue),
                    .string(MeshPermission.taskAssign.rawValue),
                ]),
            ]),
            signedEvent(.projectMemberAdded, actor: work, target: home.nodeId, projectId: project.id, logicalTime: 3, payload: [
                "nodeId": .string(home.nodeId),
                "localRepoPath": .string("/home/sloppy"),
                "role": .string("worker"),
                "permissions": .array(MeshPermission.workerDefaults.rawValues.map(JSONValue.string)),
            ]),
            signedEvent(.projectMemberRemoved, actor: work, target: work.nodeId, projectId: project.id, logicalTime: 4, payload: [
                "nodeId": .string(work.nodeId),
            ]),
        ]
        for event in events {
            _ = try store.appendEvent(event, expectedActorPublicKey: work.publicKey)
        }

        let projected = try store.projectedState()
        let projectedProject = try #require(projected.sharedProjects.first(where: { $0.id == project.id }))
        #expect(projectedProject.members.map(\.nodeId) == [home.nodeId])

        let eventCountBeforeDispatch = try store.load().events.count
        do {
            _ = try store.dispatchTask(
                projectIdOrName: project.id,
                title: "Run build",
                assignedNodeId: home.nodeId,
                actorIdentity: work
            )
            Issue.record("Expected signed dispatch to reject stale legacy membership")
        } catch let error as NodeMeshStoreError {
            #expect(error == .permissionDenied("task.dispatch"))
        }

        let state = try store.load()
        #expect(state.events.count == eventCountBeforeDispatch)
        #expect(state.events.map(\.event.type).contains(.taskCreated) == false)
        #expect(state.events.map(\.event.type).contains(.taskAssigned) == false)
    }

    @Test("signed member removal applies to legacy project without project creation event")
    func signedMemberRemovalAppliesToLegacyProjectWithoutProjectCreationEvent() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
        try store.registerNode(work)
        try store.registerNode(home)
        let project = try store.createSharedProject(
            id: "sp_legacy_overlay",
            name: "Legacy Overlay",
            repoUrl: "git@example.com:legacy-overlay.git"
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: work.nodeId,
            localRepoPath: "/work/legacy-overlay",
            role: "controller",
            permissions: [
                MeshPermission.projectWrite.rawValue,
                MeshPermission.taskCreate.rawValue,
                MeshPermission.taskAssign.rawValue,
            ]
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: home.nodeId,
            localRepoPath: "/home/legacy-overlay",
            role: "worker",
            permissions: MeshPermission.workerDefaults.rawValues
        )

        let removal = try signedEvent(.projectMemberRemoved, actor: work, target: home.nodeId, projectId: project.id, logicalTime: 1, payload: [
            "nodeId": .string(home.nodeId),
        ])
        _ = try store.appendEvent(removal, expectedActorPublicKey: work.publicKey)

        let projected = try store.projectedState()
        let projectedProject = try #require(projected.sharedProjects.first(where: { $0.id == project.id }))
        #expect(projectedProject.members.map(\.nodeId) == [work.nodeId])

        let listedProject = try #require(try store.listSharedProjects().first(where: { $0.id == project.id }))
        #expect(listedProject.members.map(\.nodeId) == [work.nodeId])

        do {
            _ = try store.dispatchTask(
                projectIdOrName: project.id,
                title: "Run build",
                assignedNodeId: home.nodeId,
                actorIdentity: work
            )
            Issue.record("Expected signed dispatch to reject removed legacy assignee")
        } catch let error as NodeMeshStoreError {
            #expect(error == .permissionDenied("task.dispatch"))
        }
    }

    @Test("new signed events cannot be backdated before a persisted revocation")
    func newSignedEventsCannotBeBackdatedBeforePersistedRevocation() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
        try store.registerNode(work)
        try store.registerNode(home)
        let project = try store.createSharedProject(
            id: "sp_sloppy",
            name: "Sloppy",
            repoUrl: "git@example.com:sloppy.git"
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: work.nodeId,
            localRepoPath: "/work/sloppy",
            role: "controller",
            permissions: [
                MeshPermission.projectWrite.rawValue,
                MeshPermission.taskCreate.rawValue,
                MeshPermission.taskAssign.rawValue,
            ]
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: home.nodeId,
            localRepoPath: "/home/sloppy",
            role: "worker",
            permissions: MeshPermission.workerDefaults.rawValues
        )

        let events = try [
            signedEvent(.projectCreated, actor: work, projectId: project.id, logicalTime: 1, payload: [
                "id": .string(project.id),
                "name": .string(project.name),
                "repoUrl": .string(project.repoUrl),
                "defaultBranch": .string(project.defaultBranch),
            ]),
            signedEvent(.projectMemberAdded, actor: work, target: work.nodeId, projectId: project.id, logicalTime: 2, payload: [
                "nodeId": .string(work.nodeId),
                "localRepoPath": .string("/work/sloppy"),
                "role": .string("controller"),
                "permissions": .array([
                    .string(MeshPermission.projectWrite.rawValue),
                    .string(MeshPermission.taskCreate.rawValue),
                    .string(MeshPermission.taskAssign.rawValue),
                ]),
            ]),
            signedEvent(.projectMemberAdded, actor: work, target: home.nodeId, projectId: project.id, logicalTime: 3, payload: [
                "nodeId": .string(home.nodeId),
                "localRepoPath": .string("/home/sloppy"),
                "role": .string("worker"),
                "permissions": .array(MeshPermission.workerDefaults.rawValues.map(JSONValue.string)),
            ]),
            signedEvent(.projectMemberRemoved, actor: work, target: work.nodeId, projectId: project.id, logicalTime: 4, payload: [
                "nodeId": .string(work.nodeId),
            ]),
        ]
        for event in events {
            _ = try store.appendEvent(event, expectedActorPublicKey: work.publicKey)
        }

        let backdated = try signedEvent(.taskCreated, actor: work, projectId: project.id, logicalTime: 3, payload: [
            "taskId": .string("mesh_task_backdated"),
            "title": .string("Run build"),
        ])

        #expect(throws: MeshEventVerificationError.unauthorized("event.append")) {
            _ = try store.appendEvent(backdated, expectedActorPublicKey: work.publicKey)
        }

        let state = try store.load()
        #expect(state.events.count == events.count)
        #expect(state.events.contains(where: { $0.event.id == backdated.event.id }) == false)
    }

    @Test("update task status with actor identity writes signed status event")
    func updateTaskStatusWithActorIdentityWritesSignedStatusEvent() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
        try store.registerNode(work)
        try store.registerNode(home)
        let project = try store.createSharedProject(
            id: "sp_sloppy",
            name: "Sloppy",
            repoUrl: "git@example.com:sloppy.git"
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: work.nodeId,
            localRepoPath: "/work/sloppy",
            role: "controller",
            permissions: [MeshPermission.taskCreate.rawValue, MeshPermission.taskAssign.rawValue]
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: home.nodeId,
            localRepoPath: "/home/sloppy",
            role: "worker",
            permissions: MeshPermission.workerDefaults.rawValues
        )

        let task = try store.dispatchTask(
            projectIdOrName: project.id,
            title: "Run build",
            assignedNodeId: home.nodeId,
            actorIdentity: work
        )
        let updated = try store.updateTaskStatus(
            taskId: task.id,
            status: .readyForReview,
            actorIdentity: home,
            branch: "agent/home/run-build",
            commit: "abc123",
            summary: "Build passed."
        )

        let state = try store.load()
        #expect(updated.status == .readyForReview)
        #expect(updated.branch == "agent/home/run-build")
        #expect(updated.commit == "abc123")
        #expect(updated.summary == "Build passed.")
        #expect(state.events.map(\.event.type).contains(.taskStatusUpdated))
    }

    @Test("signed task status update uses project when task id is duplicated")
    func signedTaskStatusUpdateUsesProjectWhenTaskIDIsDuplicated() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
        let projectA = "sp_a"
        let projectB = "sp_b"
        let sharedTaskId = "mesh_task_shared_id"
        let events = try [
            signedEvent(.projectCreated, actor: work, projectId: projectA, logicalTime: 1, payload: [
                "id": .string(projectA),
                "name": .string("A"),
                "repoUrl": .string("git@example.com:a.git"),
            ]),
            signedEvent(.projectMemberAdded, actor: work, target: work.nodeId, projectId: projectA, logicalTime: 2, payload: [
                "nodeId": .string(work.nodeId),
                "localRepoPath": .string("/work/a"),
                "role": .string("controller"),
                "permissions": .array([
                    .string(MeshPermission.projectWrite.rawValue),
                    .string(MeshPermission.taskCreate.rawValue),
                    .string(MeshPermission.taskAssign.rawValue),
                ]),
            ]),
            signedEvent(.projectMemberAdded, actor: work, target: home.nodeId, projectId: projectA, logicalTime: 3, payload: [
                "nodeId": .string(home.nodeId),
                "localRepoPath": .string("/home/a"),
                "role": .string("worker"),
                "permissions": .array(MeshPermission.workerDefaults.rawValues.map(JSONValue.string)),
            ]),
            signedEvent(.projectCreated, actor: work, projectId: projectB, logicalTime: 4, payload: [
                "id": .string(projectB),
                "name": .string("B"),
                "repoUrl": .string("git@example.com:b.git"),
            ]),
            signedEvent(.projectMemberAdded, actor: work, target: work.nodeId, projectId: projectB, logicalTime: 5, payload: [
                "nodeId": .string(work.nodeId),
                "localRepoPath": .string("/work/b"),
                "role": .string("controller"),
                "permissions": .array([
                    .string(MeshPermission.projectWrite.rawValue),
                    .string(MeshPermission.taskCreate.rawValue),
                    .string(MeshPermission.taskAssign.rawValue),
                ]),
            ]),
            signedEvent(.projectMemberAdded, actor: work, target: home.nodeId, projectId: projectB, logicalTime: 6, payload: [
                "nodeId": .string(home.nodeId),
                "localRepoPath": .string("/home/b"),
                "role": .string("worker"),
                "permissions": .array(MeshPermission.workerDefaults.rawValues.map(JSONValue.string)),
            ]),
            signedEvent(.taskCreated, actor: work, projectId: projectA, logicalTime: 7, payload: [
                "taskId": .string(sharedTaskId),
                "title": .string("A"),
            ]),
            signedEvent(.taskAssigned, actor: work, target: home.nodeId, projectId: projectA, logicalTime: 8, payload: [
                "taskId": .string(sharedTaskId),
                "assignedNodeId": .string(home.nodeId),
            ]),
            signedEvent(.taskCreated, actor: work, projectId: projectB, logicalTime: 9, payload: [
                "taskId": .string(sharedTaskId),
                "title": .string("B"),
            ]),
            signedEvent(.taskAssigned, actor: work, target: home.nodeId, projectId: projectB, logicalTime: 10, payload: [
                "taskId": .string(sharedTaskId),
                "assignedNodeId": .string(home.nodeId),
            ]),
        ]
        try store.save(MeshState(nodes: baseNodes([work, home]), events: events))

        #expect(throws: NodeMeshStoreError.taskAmbiguous(sharedTaskId)) {
            _ = try store.updateTaskStatus(
                taskId: sharedTaskId,
                status: .readyForReview,
                actorIdentity: home
            )
        }

        let updated = try store.updateTaskStatus(
            taskId: sharedTaskId,
            projectIdOrName: projectB,
            status: .readyForReview,
            actorIdentity: home
        )

        let projected = try store.projectedState()
        #expect(updated.projectId == projectB)
        #expect(projected.tasks.first(where: { $0.projectId == projectA })?.status == .dispatched)
        #expect(projected.tasks.first(where: { $0.projectId == projectB })?.status == .readyForReview)
    }

    @Test("update task status with actor identity rejects updates for another worker task")
    func updateTaskStatusWithActorIdentityRejectsUpdatesForAnotherWorkerTask() throws {
        let store = NodeMeshStore(stateURL: temporaryStateURL())
        let work = NodeIdentityGenerator.makeIdentity(name: "Work", roles: ["client"], capabilities: ["git"])
        let home = NodeIdentityGenerator.makeIdentity(name: "Home", roles: ["worker"], capabilities: ["git"])
        let other = NodeIdentityGenerator.makeIdentity(name: "Other", roles: ["worker"], capabilities: ["git"])
        try store.registerNode(work)
        try store.registerNode(home)
        try store.registerNode(other)
        let project = try store.createSharedProject(
            id: "sp_sloppy",
            name: "Sloppy",
            repoUrl: "git@example.com:sloppy.git"
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: work.nodeId,
            localRepoPath: "/work/sloppy",
            role: "controller",
            permissions: [MeshPermission.taskCreate.rawValue, MeshPermission.taskAssign.rawValue]
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: home.nodeId,
            localRepoPath: "/home/sloppy",
            role: "worker",
            permissions: MeshPermission.workerDefaults.rawValues
        )
        _ = try store.attachMember(
            projectIdOrName: project.id,
            nodeId: other.nodeId,
            localRepoPath: "/other/sloppy",
            role: "worker",
            permissions: MeshPermission.workerDefaults.rawValues
        )

        let task = try store.dispatchTask(
            projectIdOrName: project.id,
            title: "Run build",
            assignedNodeId: home.nodeId,
            actorIdentity: work
        )
        let eventCount = try store.load().events.count

        do {
            _ = try store.updateTaskStatus(
                taskId: task.id,
                status: .readyForReview,
                actorIdentity: other,
                summary: "Not my task."
            )
            Issue.record("Expected another worker's task update to be rejected")
        } catch let error as NodeMeshStoreError {
            #expect(error == .permissionDenied("task.status.update"))
        }

        let state = try store.load()
        #expect(state.events.count == eventCount)
        #expect(state.events.map(\.event.type).contains(.taskStatusUpdated) == false)
    }

    private func temporaryStateURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-mesh-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("mesh.json")
    }

    private func signedEvent(
        _ type: MeshEventType,
        actor: NodeIdentity,
        target: String? = nil,
        projectId: String?,
        logicalTime: UInt64,
        payload: [String: JSONValue]
    ) throws -> SignedMeshEvent {
        try MeshEventSigner.sign(
            MeshEvent(
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

    private func baseNodes(_ identities: [NodeIdentity]) -> [MeshNodeRecord] {
        identities.map {
            MeshNodeRecord(
                id: $0.nodeId,
                name: $0.name,
                publicKey: $0.publicKey,
                roles: $0.roles,
                status: .online,
                capabilities: $0.capabilities
            )
        }
    }
}
