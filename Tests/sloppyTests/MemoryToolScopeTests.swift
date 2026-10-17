import Foundation
import Protocols
import Testing
@testable import AgentRuntime
@testable import sloppy
@testable import SloppyRuntime

@Suite
struct MemoryToolScopeTests {
    private func context(
        agent: String, store: any MemoryStore, project: String? = nil, shared: Bool = true, session: String = "s1"
    ) -> ToolContext {
        let tmp = FileManager.default.temporaryDirectory
        return ToolContext(
            agentID: agent, sessionID: session, sharedMemoryEnabled: shared, policy: AgentToolsPolicy(),
            workspaceRootURL: tmp, currentProjectID: project, runtime: RuntimeSystem(), memoryStore: store,
            sessionStore: AgentSessionFileStore(agentsRootURL: tmp), agentCatalogStore: AgentCatalogFileStore(agentsRootURL: tmp),
            agentSkillsStore: nil, processRegistry: SessionProcessRegistry(),
            channelSessionStore: ChannelSessionFileStore(workspaceRootURL: tmp),
            store: InMemoryCorePersistenceBuilder().makeStore(config: CoreConfig.test),
            searchProviderService: SearchProviderService(config: CoreConfig.default.searchTools),
            mcpRegistry: MCPClientRegistry(config: CoreConfig.default.mcp), logger: .sloppy(label: "test"),
            projectService: nil, configService: nil, skillsService: nil, lspManager: nil, applyAgentMarkdown: nil,
            delegateSubagent: nil
        )
    }

    private func texts(_ result: ToolInvocationResult) -> [String] {
        (result.data?.asObject?["items"]?.asArray ?? []).compactMap { $0.asObject?["note"]?.asString }
    }

    @Test
    func unscopedSearchNeverReadsAnotherAgentsOrAnUnrelatedProjectsMemory() async {
        let store = HybridMemoryStore(config: CoreConfig.test)
        _ = await store.save(entry: MemoryWriteRequest(note: "umbrella fact of agent A", scope: .agent("A")))
        _ = await store.save(entry: MemoryWriteRequest(note: "umbrella fact of agent B", scope: .agent("B")))
        _ = await store.save(entry: MemoryWriteRequest(note: "umbrella fact of project P1", scope: .project("P1")))
        _ = await store.save(entry: MemoryWriteRequest(note: "umbrella fact of project P2", scope: .project("P2")))
        _ = await store.save(entry: MemoryWriteRequest(note: "umbrella fact of this chat", scope: .channel("agent:A:session:s1")))
        _ = await store.save(entry: MemoryWriteRequest(note: "umbrella fact of another chat", scope: .channel("agent:A:session:other")))
        _ = await store.save(entry: MemoryWriteRequest(note: "umbrella fact shared by all", scope: MemoryScope(type: .global, id: "shared")))

        let found = texts(await MemorySearchTool().invoke(
            arguments: ["query": .string("umbrella fact")], context: context(agent: "A", store: store, project: "P1")))

        #expect(Set(found) == [
            "umbrella fact of agent A", "umbrella fact of project P1",
            "umbrella fact of this chat", "umbrella fact shared by all",
        ])
    }

    @Test
    func unscopedSearchOmitsSharedMemoryWhenTheAgentHasItDisabled() async {
        let store = HybridMemoryStore(config: CoreConfig.test)
        _ = await store.save(entry: MemoryWriteRequest(note: "umbrella fact shared by all", scope: MemoryScope(type: .global, id: "shared")))
        _ = await store.save(entry: MemoryWriteRequest(note: "umbrella fact of agent A", scope: .agent("A")))

        let found = texts(await MemorySearchTool().invoke(
            arguments: ["query": .string("umbrella fact")], context: context(agent: "A", store: store, shared: false)))

        #expect(found == ["umbrella fact of agent A"])
    }

    @Test
    func saveFillsInTheScopeIdFromTheSessionSoModelsDoNotHaveToGuessIt() async {
        let store = HybridMemoryStore(config: CoreConfig.test)
        let ctx = context(agent: "A", store: store, project: "P1")

        let agentSave = await MemorySaveTool().invoke(arguments: ["note": .string("agent level"), "scope_type": .string("agent")], context: ctx)
        let projectSave = await MemorySaveTool().invoke(arguments: ["note": .string("project level"), "scope": .object(["type": .string("project")])], context: ctx)
        let channelSave = await MemorySaveTool().invoke(arguments: ["note": .string("chat level"), "scope_type": .string("channel")], context: ctx)

        #expect(agentSave.ok && projectSave.ok && channelSave.ok)
        #expect(await store.entries(filter: MemoryEntryFilter(scope: .agent("A"))).map(\.note) == ["agent level"])
        #expect(await store.entries(filter: MemoryEntryFilter(scope: .project("P1"))).map(\.note) == ["project level"])
        #expect(await store.entries(filter: MemoryEntryFilter(scope: .channel("agent:A:session:s1"))).map(\.note) == ["chat level"])
    }

    @Test
    func saveWithoutAnyScopeStillFailsButSaysExactlyWhatToPass() async {
        let ctx = context(agent: "A", store: HybridMemoryStore(config: CoreConfig.test), project: "P1")

        let result = await MemorySaveTool().invoke(arguments: ["note": .string("no scope")], context: ctx)

        #expect(result.ok == false)
        #expect(result.error?.code == "invalid_arguments")
        let hint = result.error?.hint ?? ""
        #expect(hint.contains("scope_type=agent") && hint.contains("A"))
        #expect(hint.contains("P1"))
        #expect(hint.contains("agent:A:session:s1"))
    }

    @Test
    func disabledSharedMemoryErrorListsTheScopesThatDoWork() async {
        let ctx = context(agent: "A", store: HybridMemoryStore(config: CoreConfig.test), shared: false)

        let result = await MemorySaveTool().invoke(
            arguments: ["note": .string("x"), "scope_type": .string("global"), "scope_id": .string("shared")], context: ctx)

        #expect(result.error?.code == "shared_memory_disabled")
        let hint = result.error?.hint ?? ""
        #expect(hint.contains("scope_type=agent"))
        #expect(!hint.contains("scope_type=global"), "must not suggest the scope that was just rejected")
    }

    @Test
    func projectScopeWithoutAProjectIsRejectedInsteadOfGuessing() async {
        let ctx = context(agent: "A", store: HybridMemoryStore(config: CoreConfig.test), project: nil)

        let result = await MemorySaveTool().invoke(arguments: ["note": .string("x"), "scope_type": .string("project")], context: ctx)

        #expect(result.ok == false)
    }

    @Test
    func searchResultsNameTheRecordIdMemoryIdSoItIsNotMistakenForContent() async {
        let store = HybridMemoryStore(config: CoreConfig.test)
        let ref = await store.save(entry: MemoryWriteRequest(note: "the deploy key id is K-1", scope: .agent("A")))

        let result = await MemorySearchTool().invoke(
            arguments: ["query": .string("deploy key")], context: context(agent: "A", store: store))

        let item = result.data?.asObject?["items"]?.asArray?.first?.asObject
        #expect(item?["memory_id"]?.asString == ref.id)
        #expect(item?["id"] == nil, "a bare `id` field gets read as the answer to 'what is the id?'")
        #expect(item?["note"]?.asString == "the deploy key id is K-1")
    }
}
