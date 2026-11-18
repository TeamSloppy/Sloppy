import Foundation
import Protocols
import SloppyNodeCore
import Testing
@testable import sloppy

@Suite("Remote execution bounded contract")
struct RemoteExecutionContractTests {
    private var selection: RemoteExecutionSelection {
        .init(targetId: "home", baseRevision: String(repeating: "a", count: 40), agentId: "builder")
    }
    private var target: RemoteExecutionTarget {
        .init(id: "home", alias: "$home_machine", nodeId: "node-home", projectId: "project",
              sharedProjectId: "shared", allowedPeerIds: ["coordinator"], allowedAgentIds: ["builder"],
              toolIDs: ["files.read", "agent_delegate.finish"], requiredCapabilities: ["swift"], maxConcurrentTasks: 1)
    }
    private var node: MeshNodeRecord {
        .init(id: "node-home", name: "Home", publicKey: "test", roles: ["worker"], status: .online,
              capabilities: ["sloppy.core.remote", "swift"])
    }
    private func resolve(_ value: RemoteExecutionSelection, project: String = "project", peer: String = "coordinator",
                         nodes: [MeshNodeRecord]? = nil) throws -> RemoteExecutionSelection {
        try RemoteExecutionRegistry.resolve(value, projectID: project, peerID: peer, targets: [target], nodes: nodes ?? [node])
    }

    @Test func legacyPayloadRemainsLocal() throws {
        let data = Data(#"{"key":"a","title":"A","objective":"Inspect","resourceKeys":[],"dependsOn":[]}"#.utf8)
        let request = try JSONDecoder().decode(LongChatTaskRequest.self, from: data)
        #expect(request.executionTarget == nil)
        #expect(request.reuseSessionId == nil)
    }

    @Test func exactAliasResolvesToPinnedIdentityWithoutChoosingModel() throws {
        var value = selection
        value.targetId = "$home_machine"
        let resolved = try resolve(value)
        #expect(resolved.targetId == "home")
        #expect(resolved.nodeId == "node-home")
        #expect(resolved.agentId == "builder")
        #expect(resolved.selectedModel == nil)
        var remapped = node
        remapped.id = "another-node"
        #expect(throws: RemoteExecutionError.offline) { try resolve(resolved, nodes: [remapped]) }
        var forged = resolved
        forged.nodeId = "another-node"
        #expect(throws: RemoteExecutionError.forbidden) { try resolve(forged) }
    }

    @Test func unknownAliasNeverExpandsEnvironmentOrFallsBack() throws {
        var value = selection
        value.targetId = "${HOME}"
        #expect(throws: RemoteExecutionError.invalidTarget) { try resolve(value) }
        value.targetId = "home_machine"
        #expect(throws: RemoteExecutionError.invalidTarget) { try resolve(value) }
    }

    @Test func offlineMissingAndCapabilityMismatchFailClosed() throws {
        var offline = node
        offline.status = .offline
        #expect(throws: RemoteExecutionError.offline) { try resolve(selection, nodes: [offline]) }
        #expect(throws: RemoteExecutionError.offline) { try resolve(selection, nodes: []) }
        var incompatible = node
        incompatible.capabilities = ["sloppy.core.remote"]
        #expect(throws: RemoteExecutionError.forbidden) { try resolve(selection, nodes: [incompatible]) }
    }

    @Test func unauthorizedProjectPeerAgentAndMovingBaseFailClosed() throws {
        #expect(throws: RemoteExecutionError.forbidden) { try resolve(selection, project: "other") }
        #expect(throws: RemoteExecutionError.forbidden) { try resolve(selection, peer: "other") }
        var value = selection
        value.agentId = "admin"
        #expect(throws: RemoteExecutionError.forbidden) { try resolve(value) }
        value = selection
        value.baseRevision = "HEAD"
        #expect(throws: RemoteExecutionError.invalidBase) { try resolve(value) }
    }

    @Test func ambiguousRegistryIsRejected() throws {
        var duplicate = target
        duplicate.id = "$home_machine"
        duplicate.alias = "other"
        #expect(throws: RemoteExecutionError.invalidTarget) { try RemoteExecutionRegistry.validate([target, duplicate]) }
    }

    @Test func assignmentAndReuseContextPersistTargetAcrossReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LongChatFileStore(root: root)
        let resolved = try resolve(selection)
        try store.transaction {
            $0.conversations = [.init(agentId: "coordinator", userId: "user", sessionId: "parent", assignments: [])]
            $0.workerContexts = ["worker": .init(agentId: "builder", parentSessionId: "parent", projectId: "project",
                workingDirectory: nil, extraRoots: [], toolIDs: ["files.read"], resourceKeys: ["project:project"],
                readOnly: true, executionTarget: resolved)]
        }
        let assignment = try store.delegate(sessionId: "parent", sourceMessageId: "source", request:
            .init(requestKey: "key", title: "Work", acceptanceCriteria: "Result", tasks: [
                .init(key: "task", title: "Work", objective: "Inspect", projectId: "project", readOnly: true, executionTarget: resolved)]))
        let reopened = try LongChatFileStore(root: root)
        #expect(try reopened.conversation(sessionId: "parent").assignments[0].tasks[0].executionTarget == resolved)
        #expect(reopened.state.workerContexts?["worker"]?.executionTarget == resolved)
        #expect(assignment.tasks[0].attempts[0].remoteExecution == nil)
    }

    @Test func reuseCannotChangeTargetOrWidenPermissionsButModelIsIndependent() throws {
        let original = try resolve(selection)
        func check(_ requested: RemoteExecutionSelection?, readOnly: Bool = true, keys: [String] = ["project:p"]) throws {
            try RemoteExecutionRegistry.validateReuse(original: original, requested: requested,
                originalProject: "p", requestedProject: "p", originalKeys: ["project:p"], requestedKeys: keys,
                originalReadOnly: true, requestedReadOnly: readOnly)
        }
        var changed = original
        changed.targetId = "other"
        #expect(throws: CoreService.SubagentReuseError.self) { try check(changed) }
        #expect(throws: CoreService.SubagentReuseError.self) { try check(nil) }
        #expect(throws: CoreService.SubagentReuseError.self) { try check(original, readOnly: false) }
        #expect(throws: CoreService.SubagentReuseError.self) { try check(original, keys: ["project:other"]) }
        changed = original
        changed.selectedModel = "independent-model"
        try check(changed)
    }

    @Test func unsupportedExecutorHasExplicitError() throws {
        #expect(throws: RemoteExecutionError.unsupportedExecution) { try RemoteExecutionRegistry.requireSupportedExecutor() }
    }

    @Test func realToolBoundaryRejectsConfiguredUnsupportedTargetAndMeshStart() async throws {
        let config = CoreConfig.test
        let nodeStore = NodeConfigStore(configURL: config.resolvedWorkspaceRootURL().appendingPathComponent("node.json"))
        _ = try nodeStore.initialize(name: "Coordinator", roles: ["coordinator"], capabilities: [])
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder(), nodeConfigStore: nodeStore)
        _ = try await service.createAgent(.init(id: "remote-configured", displayName: "Contract", role: "Test"))
        let chat = try await service.openLongChat(agentID: "remote-configured", userID: "user")
        _ = try await service.createProject(.init(id: "remote-fixture", name: "Remote fixture"))
        let configured = try await service.configureContractTarget(chatID: chat.id)
        let assignment = LongChatDelegationRequest(requestKey: "remote", title: "Work", acceptanceCriteria: "Result", tasks: [
            .init(key: "task", title: "Work", objective: "Inspect", projectId: "remote-fixture", readOnly: true, executionTarget: configured)])
        let result = await service.invokeLongChatTool(agentID: chat.agentId, sessionID: chat.id, request:
            .init(tool: "long_chat.delegate", arguments: ["assignment": try JSONValueCoder.encode(assignment)]))
        #expect(!result.ok)
        #expect(result.error?.code == "remote_execution_unsupported")
        #expect(try await service.getLongChat(agentID: chat.agentId, sessionID: chat.id).assignments.isEmpty)
        #expect(try await service.hasNoContractWorkers())
        let rpc = await service.handleMeshCoreHTTPRPC(envelope:
            .init(id: "start", type: .rpcRequest, from: "unknown", to: "local"), method: "subagent.start", params: .object([:]))
        #expect(rpc.asObject?["ok"] == .bool(false))
        #expect(rpc.asObject?["error"]?.asObject?["code"] == .string("remote_execution_unsupported"))
        await service.stop()
    }

    @Test func persistedExperimentalRemoteRequestCannotFallThroughLocalDispatcher() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        _ = try await service.createAgent(.init(id: "remote-restored", displayName: "Restored", role: "Test"))
        let chat = try await service.openLongChat(agentID: "remote-restored", userID: "user")
        try await service.seedContractRemoteRequest(chatID: chat.id, selection: selection)
        await service.dispatchLongChatWorkers()
        let task = try #require(try await service.getLongChat(agentID: chat.agentId, sessionID: chat.id).assignments.first?.tasks.first)
        #expect(task.executionTarget == selection)
        #expect(task.attempts.last?.sessionId == nil)
        #expect(task.attempts.last?.automaticRetryAllowed == false)
        #expect(task.attempts.last?.executionStopped == false)
        #expect(task.attempts.last?.summary?.contains("No local fallback") == true)
        #expect(try await service.hasNoContractWorkers())
        await service.stop()
    }

    @Test func realDelegationBoundaryRejectsUnknownRemoteWithoutAssignmentOrLocalSession() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        _ = try await service.createAgent(.init(id: "remote-contract", displayName: "Contract", role: "Test"))
        let chat = try await service.openLongChat(agentID: "remote-contract", userID: "user")
        await service.pauseContractDispatch()
        do {
            _ = try await service.delegateLongChat(agentID: chat.agentId, sessionID: chat.id, sourceID: "source", request:
                .init(requestKey: "remote", title: "Work", acceptanceCriteria: "Result", tasks: [
                    .init(key: "task", title: "Work", objective: "Inspect", readOnly: true, executionTarget: selection)]))
            Issue.record("Remote request must not succeed")
        } catch { #expect(error as? RemoteExecutionError == .invalidTarget) }
        #expect(try await service.getLongChat(agentID: chat.agentId, sessionID: chat.id).assignments.isEmpty)
        #expect(try await service.hasNoContractWorkers())
        await service.stop()
    }
}

private extension CoreService {
    func seedContractRemoteRequest(chatID: String, selection: RemoteExecutionSelection) throws {
        _ = try longChats().delegate(sessionId: chatID, sourceMessageId: "old-start", request:
            .init(requestKey: "old", title: "Old request", acceptanceCriteria: "Inspect", tasks: [
                .init(key: "task", title: "Old request", objective: "Inspect", readOnly: true, executionTarget: selection)]))
    }
    func pauseContractDispatch() { longChatIsStopping = true }
    func hasNoContractWorkers() throws -> Bool { try longChats().state.workerContexts?.isEmpty != false }
    func configureContractTarget(chatID: String) throws -> RemoteExecutionSelection {
        longChatIsStopping = true
        longChatCurrentTurns[chatID] = "source"
        let node = NodeIdentityGenerator.makeIdentity(name: "Remote", roles: ["worker"], capabilities: ["sloppy.core.remote"])
        _ = try nodeMeshStore.registerNode(node)
        let target = RemoteExecutionTarget(id: "configured", alias: "$test_machine", nodeId: node.nodeId,
            projectId: "remote-fixture", sharedProjectId: "shared", allowedPeerIds: [try nodeConfigStore.load().identity.nodeId],
            allowedAgentIds: ["builder"], toolIDs: ["agent_delegate.finish"], requiredCapabilities: [], maxConcurrentTasks: 1)
        // This fixture uses an explicit project; no existing production workspace or credentials.
        try JSONEncoder().encode([target]).write(to: workspaceRootURL.appendingPathComponent("remote-execution-targets.json"))
        return .init(targetId: target.id, baseRevision: String(repeating: "a", count: 40), agentId: "builder")
    }
}
