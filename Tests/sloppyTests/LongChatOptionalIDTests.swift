import Foundation
import Protocols
import Testing
@testable import sloppy

@Suite("Long chat optional identifiers")
struct LongChatOptionalIDTests {
    @Test(arguments: ["", " \n\t"])
    func blankReuseAndProjectIDsMeanFreshWorker(_ blank: String) throws {
        let request = LongChatDelegationRequest(requestKey: "request", title: "Work", acceptanceCriteria: "Verified",
            tasks: [.init(key: "task", title: "Task", objective: "Do work", projectId: blank, readOnly: true, reuseSessionId: blank)])
        let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(request))
        let decoded = try LongChatDelegationDecoder.decode(value)
        #expect(decoded.tasks[0].reuseSessionId == nil)
        #expect(decoded.tasks[0].projectId == nil)
    }

    @Test func blankReuseCreatesAFreshAssignmentThroughTheRealToolBoundary() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        defer { Task { await service.stop() } }
        _ = try await service.createAgent(.init(id: "fresh-agent", displayName: "Agent", role: "Test"))
        let chat = try await service.openLongChat(agentID: "fresh-agent", userID: "local")
        await service.setOptionalIDTestTurn(chat.id)
        let assignment = LongChatDelegationRequest(requestKey: "fresh", title: "Inspect", acceptanceCriteria: "Findings",
            tasks: [.init(key: "inspect", title: "Inspect", objective: "Inspect", projectId: "", readOnly: true, reuseSessionId: "")])
        let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(assignment))
        let result = await service.invokeLongChatTool(agentID: chat.agentId, sessionID: chat.id,
            request: .init(tool: "long_chat.delegate", arguments: ["assignment": value]))
        #expect(result.ok)
        let saved = try await service.getLongChat(agentID: chat.agentId, sessionID: chat.id)
        #expect(saved.assignments.count == 1)
        #expect(saved.assignments.first?.tasks.first?.reuseSessionId == nil)
    }

    @Test func blankStatusIDReadsConversationAndMissingReuseReportsCorrectableField() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        defer { Task { await service.stop() } }
        _ = try await service.createAgent(.init(id: "optional-agent", displayName: "Agent", role: "Test"))
        let chat = try await service.openLongChat(agentID: "optional-agent", userID: "local")
        let result = await service.invokeLongChatTool(agentID: chat.agentId, sessionID: chat.id,
            request: .init(tool: "long_chat.status", arguments: ["taskId": .string("")]))
        #expect(result.ok)
        let invalid = LongChatTaskRequest(key: "work", title: "Work", objective: "Inspect", readOnly: true, reuseSessionId: "missing")
        await service.setOptionalIDTestTurn(chat.id)
        let assignment = LongChatDelegationRequest(requestKey: "request", title: "Work", acceptanceCriteria: "Verified", tasks: [invalid])
        let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(assignment))
        let failure = await service.invokeLongChatTool(agentID: chat.agentId, sessionID: chat.id,
            request: .init(tool: "long_chat.delegate", arguments: ["assignment": value]))
        #expect(!failure.ok)
        #expect(failure.error?.code == "invalid_arguments")
        #expect(failure.error?.hint?.contains("reuseSessionId") == true)
        #expect(try await service.getLongChat(agentID: chat.agentId, sessionID: chat.id).assignments.isEmpty)
    }
}

private extension CoreService {
    func setOptionalIDTestTurn(_ id: String) { longChatIsStopping = true; longChatCurrentTurns[id] = "source" }
}
