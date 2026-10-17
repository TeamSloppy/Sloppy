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

@Suite
struct MemoryTopicTests {
    private func context(store: any MemoryStore, agent: String = "A") -> ToolContext {
        let tmp = FileManager.default.temporaryDirectory
        return ToolContext(
            agentID: agent, sessionID: "s1", policy: AgentToolsPolicy(), workspaceRootURL: tmp,
            runtime: RuntimeSystem(), memoryStore: store,
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

    private func save(_ note: String, topic: String?, ctx: ToolContext, scope: String = "agent") async -> ToolInvocationResult {
        var arguments: [String: JSONValue] = ["note": .string(note), "scope_type": .string(scope)]
        if let topic { arguments["topic"] = .string(topic) }
        return await MemorySaveTool().invoke(arguments: arguments, context: ctx)
    }

    @Test
    func savingTheSameTopicAgainReplacesTheEarlierEntryInOneCall() async {
        let store = HybridMemoryStore(config: CoreConfig.test)
        let ctx = context(store: store)

        let first = await save("The deploy key id of billing is OLD1.", topic: "billing deploy key id", ctx: ctx)
        let second = await save("The deploy key id of billing is NEW2.", topic: "Billing   DEPLOY key-id", ctx: ctx)

        #expect(first.ok && second.ok)
        #expect(second.data?.asObject?["updated"]?.asBool == true)
        #expect(second.data?.asObject?["id"]?.asString == first.data?.asObject?["id"]?.asString)
        #expect(second.data?.asObject?["replaced_note"]?.asString == "The deploy key id of billing is OLD1.")
        let notes = await store.entries(filter: MemoryEntryFilter(scope: .agent("A"))).map(\.note)
        #expect(notes == ["The deploy key id of billing is NEW2."])
    }

    @Test
    func differentTopicsAboutSimilarlyWordedFactsCoexist() async {
        let store = HybridMemoryStore(config: CoreConfig.test)
        let ctx = context(store: store)

        _ = await save("The deploy key id of billing is K1.", topic: "billing deploy key id", ctx: ctx)
        _ = await save("The deploy key id of payments is K2.", topic: "payments deploy key id", ctx: ctx)
        _ = await save("The owner of billing is Alice.", topic: "billing owner", ctx: ctx)

        let notes = Set(await store.entries(filter: MemoryEntryFilter(scope: .agent("A"))).map(\.note))
        #expect(notes == [
            "The deploy key id of billing is K1.", "The deploy key id of payments is K2.", "The owner of billing is Alice.",
        ])
    }

    @Test
    func topicsAreScopedAndEntriesWithoutATopicAreNeverReplaced() async {
        let store = HybridMemoryStore(config: CoreConfig.test)
        let ctx = context(store: store)

        _ = await save("Agent level value one.", topic: "shared name", ctx: ctx, scope: "agent")
        _ = await save("Chat level value.", topic: "shared name", ctx: ctx, scope: "channel")
        _ = await save("A plain note.", topic: nil, ctx: ctx)
        _ = await save("Another plain note.", topic: nil, ctx: ctx)

        #expect(await store.entries(filter: MemoryEntryFilter(scope: .agent("A"))).count == 3)
        #expect(await store.entries(filter: MemoryEntryFilter(scope: .channel("agent:A:session:s1"))).count == 1)
    }

    @Test
    func replacingATopicAlsoRemovesOlderDuplicatesOfThatTopic() async {
        let store = HybridMemoryStore(config: CoreConfig.test)
        let ctx = context(store: store)
        for note in ["Port is 1.", "Port is 2."] {
            _ = await store.save(entry: MemoryWriteRequest(
                note: note, scope: .agent("A"), metadata: [MemoryTopic.metadataKey: .string("service port")]))
        }

        let result = await save("Port is 3.", topic: "service port", ctx: ctx)

        #expect(result.ok)
        #expect(await store.entries(filter: MemoryEntryFilter(scope: .agent("A"))).map(\.note) == ["Port is 3."])
    }

    @Test
    func searchResultsAndRecallLinesCarryTheTopicSoItCanBeReused() async {
        let store = HybridMemoryStore(config: CoreConfig.test)
        let ctx = context(store: store)
        _ = await save("The deploy key id of billing is K1.", topic: "billing deploy key id", ctx: ctx)

        let search = await MemorySearchTool().invoke(arguments: ["query": .string("deploy key billing")], context: ctx)
        let item = search.data?.asObject?["items"]?.asArray?.first?.asObject
        #expect(item?["topic"]?.asString == "billing deploy key id")

        let hits = await store.recall(request: MemoryRecallRequest(query: "deploy key billing", limit: 5, scope: .agent("A")))
        let block = RuntimeSystem.recalledMemoryBlock(hits: hits, limit: 5, maxCharacters: 6000)
        #expect(block.lines.last?.hasPrefix("- [billing deploy key id] The deploy key id of billing is K1.") == true)
    }

    @Test
    func topicNormalizationIsExactAfterCaseAndPunctuationFolding() {
        #expect(MemoryTopic.key("Billing  Deploy-Key ID") == "billing deploy key id")
        #expect(MemoryTopic.key("billing deploy key id") != MemoryTopic.key("deploy key id of billing"))
        #expect(MemoryTopic.display("   ") == nil)
        #expect(MemoryTopic.display(String(repeating: "x", count: 200))?.count == MemoryTopic.maxLength)
    }
}

@Suite
struct MemoryUpdateSafetyTests {
    private func context(store: any MemoryStore) -> ToolContext {
        let tmp = FileManager.default.temporaryDirectory
        return ToolContext(
            agentID: "A", sessionID: "s1", policy: AgentToolsPolicy(), workspaceRootURL: tmp,
            runtime: RuntimeSystem(), memoryStore: store,
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

    private func save(_ arguments: [String: JSONValue], _ ctx: ToolContext) async -> ToolInvocationResult {
        var args = arguments
        args["scope_type"] = .string("agent")
        return await MemorySaveTool().invoke(arguments: args, context: ctx)
    }

    @Test
    func identifierDiffSeparatesASubstitutionFromALossyRewrite() {
        let substitution = MemoryNoteDiff.compare(
            old: "The deploy key id of billing is ZG3XYV.", new: "The deploy key id of billing is K9Q2LD.")
        #expect(substitution.dropped == ["ZG3XYV"] && substitution.added == ["K9Q2LD"] && !substitution.losesDetail)

        let loss = MemoryNoteDiff.compare(
            old: "The internal billing service is called HGPAHQ, and its deploy key id is ZG3XYV.",
            new: "The internal billing service is called HGPAHQ.")
        #expect(loss.dropped == ["ZG3XYV"] && loss.added.isEmpty && loss.losesDetail)

        let reworded = MemoryNoteDiff.compare(old: "The port is 7654.", new: "Port 7654 is used by the database.")
        #expect(!reworded.losesDetail, "rewording that keeps the identifiers is fine")
    }

    @Test
    func identifierDetectionIgnoresOrdinaryWords() {
        #expect(MemoryNoteDiff.identifiers(in: "The user prefers tabs over spaces") == [])
        #expect(MemoryNoteDiff.identifiers(in: "Runs on port 5432, build v2.3.1, key KESTREL-7, host db-1.internal")
                == ["5432", "V2.3.1", "KESTREL-7", "DB-1.INTERNAL"])
    }

    @Test
    func updatingByIdCannotSilentlyDropAnIdentifier() async {
        let store = HybridMemoryStore(config: CoreConfig.test)
        let ctx = context(store: store)
        let first = await save(["note": .string("Billing is HGPAHQ and its deploy key id is ZG3XYV.")], ctx)
        let id = first.data?.asObject?["id"]?.asString ?? ""

        let lossy = await save(["note": .string("Billing is HGPAHQ."), "memory_id": .string(id)], ctx)
        let correction = await save(["note": .string("Billing is HGPAHQ and its deploy key id is K9Q2LD."), "memory_id": .string(id)], ctx)

        #expect(lossy.ok == false)
        #expect(lossy.error?.code == "memory_update_would_lose_details")
        #expect(lossy.error?.message.contains("ZG3XYV") == true)
        #expect(correction.ok)
        #expect(await store.entries(filter: MemoryEntryFilter(scope: .agent("A"))).map(\.note)
                == ["Billing is HGPAHQ and its deploy key id is K9Q2LD."])
    }

    @Test
    func replacingATopicCannotSilentlyDropAnIdentifierEither() async {
        let store = HybridMemoryStore(config: CoreConfig.test)
        let ctx = context(store: store)
        _ = await save(["note": .string("Billing is HGPAHQ and its deploy key id is ZG3XYV."), "topic": .string("billing")], ctx)

        let lossy = await save(["note": .string("The user's billing service is HGPAHQ."), "topic": .string("billing")], ctx)

        #expect(lossy.error?.code == "memory_update_would_lose_details")
        #expect(await store.entries(filter: MemoryEntryFilter(scope: .agent("A"))).map(\.note)
                == ["Billing is HGPAHQ and its deploy key id is ZG3XYV."], "the original entry is untouched")
    }
}
