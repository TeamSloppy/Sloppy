import Foundation
import SloppyNodeCore
import Testing
@testable import Protocols
@testable import sloppy

@Suite
struct MemorySaveRecoveryTests {
    private func fixture() async throws -> (CoreService, String) {
        var config = CoreConfig.test
        config.experimentalFlags.disableToolBudgetAndLoopGuard = false
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder(),
            nodeConfigStore: NodeConfigStore(configURL: URL(fileURLWithPath: config.sqlitePath + ".node.json")), sharedSkillsRootURLs: [])
        _ = try await service.createAgent(.init(id: "memory-recovery", displayName: "Memory recovery", role: "Test"))
        let session = try await service.createAgentSession(agentID: "memory-recovery", request: .init(title: "Recovery"))
        return (service, session.id)
    }

    private func save(_ service: CoreService, _ session: String, id: JSONValue?, note: String = "Imported preference", scope: String = "memory-recovery") async -> ToolInvocationResult {
        var arguments: [String: JSONValue] = ["note": .string(note), "scope_type": .string("agent"), "scope_id": .string(scope), "kind": .string("preference")]
        arguments["memory_id"] = id
        return await service.invokeToolFromRuntime(agentID: "memory-recovery", sessionID: session, request: .init(tool: "memory.save", arguments: arguments))
    }

    @Test
    func omittedNullAndBlankIDsCreateButUnknownIDsNeverCreate() async throws {
        let (service, session) = try await fixture()
        var ids = Set<String>()
        let inputIDs: [JSONValue?] = [nil, .null, .string(""), .string(" \n\t ")]
        for id in inputIDs {
            let result = await save(service, session, id: id)
            #expect(result.ok)
            ids.insert(try #require(result.data?.asObject?["id"]?.asString))
        }
        #expect(ids.count == 4)
        let unknown = await save(service, session, id: .string("missing"))
        #expect(unknown.error?.code == "memory_not_found")
        #expect(unknown.error?.argumentRecovery?.invalidFields == ["memory_id"])
        let records = await service.memoryStore.entries(filter: .default)
        #expect(records.count == 4)
        let existingID = try #require(ids.first)
        let updated = await save(service, session, id: .string(" \(existingID)\n"), note: "Corrected preference")
        #expect(updated.ok)
        #expect(updated.data?.asObject?["id"]?.asString == existingID)
        #expect(updated.data?.asObject?["updated"]?.asBool == true)
        let wrongScope = await save(service, session, id: .string(existingID), note: "Must not overwrite", scope: "another-agent")
        #expect(wrongScope.error?.code == "memory_not_found")
        let unchanged = await service.memoryStore.entries(filter: .default)
        #expect(unchanged.count == 4)
        #expect(unchanged.first { $0.id == existingID }?.note == "Corrected preference")
    }

    @Test
    func changingNoteDoesNotHideBadIDButCorrectingIDAllowsProgress() async throws {
        let (service, session) = try await fixture()
        let first = await save(service, session, id: .string("missing"), note: "First fact")
        #expect(first.error?.code == "memory_not_found")
        let repeated = await save(service, session, id: .string("missing"), note: "Completely different fact")
        #expect(repeated.error?.code == "tool_loop_detected")
        let corrected = await save(service, session, id: nil, note: "A new fact")
        #expect(corrected.ok)
        let otherScope = await save(service, session, id: .string("missing"), scope: "another-agent")
        #expect(otherScope.error?.code == "memory_not_found")
    }

    @Test
    func oneUnsuccessfulCorrectionStopsFurtherAttemptsUntilNewTurn() async throws {
        let (service, session) = try await fixture()
        #expect(await save(service, session, id: .string("first-wrong-id")).error?.code == "memory_not_found")
        #expect(await save(service, session, id: .string("second-wrong-id")).error?.code == "tool_loop_detected")
        #expect(await save(service, session, id: .string("third-wrong-id")).error?.code == "tool_loop_detected")
        await service.toolLoopGuard.beginTurn(sessionID: session)
        #expect(await save(service, session, id: nil).ok)
    }

    @Test
    func invalidIDTypeDoesNotSilentlyCreate() async throws {
        let (service, session) = try await fixture()
        let result = await save(service, session, id: .number(123))
        #expect(result.error?.code == "invalid_arguments")
        #expect(result.error?.argumentRecovery?.invalidFields == ["memory_id"])
        #expect(await service.memoryStore.entries(filter: .default).isEmpty)
    }
}
