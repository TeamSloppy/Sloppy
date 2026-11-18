import Foundation
import Protocols
import Testing

@testable import sloppy

@Suite("Long chat optional execution target")
struct LongChatEmptyExecutionTargetTests {
    private func request(target: RemoteExecutionSelection, reuse: String? = nil) -> LongChatDelegationRequest {
        .init(requestKey: "local-work", title: "Local work", acceptanceCriteria: "Verified",
              tasks: [.init(key: "work", title: "Work", objective: "Inspect local sources", readOnly: true,
                            reuseSessionId: reuse, executionTarget: target)])
    }

    private var blank: RemoteExecutionSelection {
        .init(targetId: "", baseRevision: "", agentId: "", selectedModel: "")
    }

    @Test(arguments: ["", " \n\t"])
    func whollyBlankTargetDecodesAsLocal(_ empty: String) throws {
        let target = RemoteExecutionSelection(targetId: empty, baseRevision: empty, agentId: empty,
                                              selectedModel: empty, nodeId: empty)
        let value = try JSONValueCoder.encode(request(target: target))
        #expect(try LongChatDelegationDecoder.decode(value).tasks[0].executionTarget == nil)
        #expect(LongChatDelegationDecoder.normalized(request(target: target)).tasks[0].executionTarget == nil)
    }

    @Test func everyNonemptyRemoteFieldPreservesRemoteValidation() {
        var targets = [RemoteExecutionSelection]()
        var target = blank; target.targetId = "home"; targets.append(target)
        target = blank; target.nodeId = "node-home"; targets.append(target)
        target = blank; target.baseRevision = String(repeating: "a", count: 40); targets.append(target)
        target = blank; target.agentId = "builder"; targets.append(target)
        target = blank; target.selectedModel = "model"; targets.append(target)
        for target in targets {
            #expect(LongChatDelegationDecoder.normalized(request(target: target)).tasks[0].executionTarget == target)
        }
    }

    @Test func emptyTargetCreatesLocalAssignmentAndDeduplicatesThroughToolBoundary() async throws {
        let (service, chat) = try await service()
        defer { Task { await service.stop() } }
        let invocation = ToolInvocationRequest(tool: "long_chat.delegate", arguments: ["assignment": try JSONValueCoder.encode(request(target: blank))])
        let result = await service.invokeLongChatTool(agentID: chat.agentId, sessionID: chat.id, request: invocation)
        #expect(result.ok)
        let duplicate = await service.invokeLongChatTool(agentID: chat.agentId, sessionID: chat.id, request: invocation)
        #expect(duplicate.ok)
        let saved = try await service.getLongChat(agentID: chat.agentId, sessionID: chat.id)
        #expect(saved.assignments.count == 1)
        #expect(saved.assignments.first?.tasks.first?.executionTarget == nil)
    }

    @Test func emptyTargetContinuesLocalWorkerWithItsOriginalScope() async throws {
        let (service, chat) = try await service()
        defer { Task { await service.stop() } }
        let child = try await service.seedEmptyTargetTestWorker(parent: chat, target: nil)
        let result = await service.invokeLongChatTool(agentID: chat.agentId, sessionID: chat.id, request:
            .init(tool: "long_chat.delegate", arguments: ["assignment": try JSONValueCoder.encode(request(target: blank, reuse: child))]))
        #expect(result.ok)
        let saved = try await service.getLongChat(agentID: chat.agentId, sessionID: chat.id)
        #expect(saved.assignments.first?.tasks.first?.reuseSessionId == child)
        #expect(saved.assignments.first?.tasks.first?.executionTarget == nil)
    }

    @Test func emptyTargetCannotMoveRemoteWorkerToLocalExecution() async throws {
        let (service, chat) = try await service()
        defer { Task { await service.stop() } }
        let remote = RemoteExecutionSelection(targetId: "home", baseRevision: String(repeating: "a", count: 40), agentId: "builder")
        let child = try await service.seedEmptyTargetTestWorker(parent: chat, target: remote)
        let result = await service.invokeLongChatTool(agentID: chat.agentId, sessionID: chat.id, request:
            .init(tool: "long_chat.delegate", arguments: ["assignment": try JSONValueCoder.encode(request(target: blank, reuse: child))]))
        #expect(!result.ok)
        #expect(result.error?.code == "invalid_arguments")
        #expect(try await service.getLongChat(agentID: chat.agentId, sessionID: chat.id).assignments.isEmpty)
    }

    @Test func partialRemoteTargetFailsWithoutCreatingLocalWork() async throws {
        let (service, chat) = try await service()
        defer { Task { await service.stop() } }
        var target = blank
        target.targetId = "unknown"
        let result = await service.invokeLongChatTool(agentID: chat.agentId, sessionID: chat.id, request:
            .init(tool: "long_chat.delegate", arguments: ["assignment": try JSONValueCoder.encode(request(target: target))]))
        #expect(!result.ok)
        #expect(result.error?.code == "remote_target_invalid")
        #expect(try await service.getLongChat(agentID: chat.agentId, sessionID: chat.id).assignments.isEmpty)
    }

    private func service() async throws -> (CoreService, AgentSessionSummary) {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        _ = try await service.createAgent(.init(id: "blank-target-agent", displayName: "Agent", role: "Test"))
        let chat = try await service.openLongChat(agentID: "blank-target-agent", userID: "local")
        await service.pauseEmptyTargetTestDispatch(chat.id)
        return (service, chat)
    }
}

private extension CoreService {
    func pauseEmptyTargetTestDispatch(_ id: String) {
        longChatIsStopping = true
        longChatCurrentTurns[id] = "source"
    }

    func seedEmptyTargetTestWorker(parent: AgentSessionSummary, target: RemoteExecutionSelection?) throws -> String {
        let child = try sessionStore.createSession(agentID: parent.agentId, request: .init(parentSessionId: parent.id, kind: .longChatWorker))
        try rememberSubagentContext(session: child, parentSessionID: parent.id, workingDirectory: nil,
                                    extraRoots: [], tools: ["files.read"], resourceKeys: [], readOnly: true, executionTarget: target)
        return child.id
    }
}
