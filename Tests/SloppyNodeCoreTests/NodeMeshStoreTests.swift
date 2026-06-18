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

    private func temporaryStateURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-mesh-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("mesh.json")
    }
}
