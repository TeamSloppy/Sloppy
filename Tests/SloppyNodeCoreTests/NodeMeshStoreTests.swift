import Foundation
import Protocols
import Testing
@testable import SloppyNodeCore

@Suite("NodeMeshStore")
struct NodeMeshStoreTests {
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
