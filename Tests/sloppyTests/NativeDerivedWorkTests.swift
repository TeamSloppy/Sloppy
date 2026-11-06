import Foundation
import AnyLanguageModel
import AgentRuntime
import PluginSDK
import Protocols
import SloppyRuntime
import Testing
@testable import sloppy

private enum DerivedSourceCase: CaseIterable { case waitingInput, superseded, completed }
private enum DerivedMemoryCase: CaseIterable { case manual, write, providerFailure }
private struct DerivedMemoryDeclaration: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String
    let name = "agent.documents.set_memory_markdown"
    let description = "Memory fixture"
    var parameters: GenerationSchema { AgentDocumentsSetMemoryMarkdownTool().parameters }
    func call(arguments: GeneratedContent) async throws -> String { throw CancellationError() }
}
private struct DerivedQuestionDeclaration: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String
    let name = "planning.request_input"
    let description = "Question fixture"
    var parameters: GenerationSchema { PlanningRequestInputTool().parameters }
    func call(arguments: GeneratedContent) async throws -> String { throw CancellationError() }
}
private actor DerivedSourceScript: ModelStepProvider {
    let scenario: DerivedSourceCase
    let gate: SessionStepGate
    private(set) var calls = 0
    private(set) var requests: [ModelStepRequest] = []
    private(set) var legacyCalls = 0
    let memoryCase: DerivedMemoryCase?
    let holdMemory: Bool
    let proposalReview: Bool
    init(_ scenario: DerivedSourceCase, gate: SessionStepGate, memoryCase: DerivedMemoryCase? = nil, holdMemory: Bool = false,
         proposalReview: Bool = false) {
        self.scenario = scenario; self.gate = gate; self.memoryCase = memoryCase; self.holdMemory = holdMemory
        self.proposalReview = proposalReview
    }
    func legacy() { legacyCalls += 1 }
    func next(_ request: ModelStepRequest) async throws -> ModelStepResponse {
        calls += 1
        requests.append(request)
        if calls == 2, proposalReview {
            return .init(toolCalls: [.init(id: "proposal", name: "self_improvement_proposal_submit", rawArguments: #"{"action":"nothing"}"#)], stopReason: .toolCalls)
        }
        if calls == 2 && holdMemory { await gate.hold() }
        if calls >= 2, memoryCase == .providerFailure {
            throw ModelStepFailure(category: .authentication, code: "memory_authentication_failed", message: "Fixture credential expired.")
        }
        if calls == 2, memoryCase == .write {
            return .init(toolCalls: [.init(id: "memory-write", name: "agent_documents_set_memory_markdown",
                rawArguments: #"{"content":"Verified durable fixture preference."}"#)], stopReason: .toolCalls)
        }
        if scenario == .superseded && calls == 2 { await gate.hold() }
        if scenario == .waitingInput {
            return .init(toolCalls: [.init(id: "question", name: "planning_request_input", rawArguments:
                #"{"title":"Choose","questions":[{"id":"which","question":"Which target?","options":[{"id":"one","label":"One"},{"id":"two","label":"Two"}]}]}"#)], stopReason: .toolCalls)
        }
        return .init(text: "Recorded source result.", stopReason: .endTurn)
    }
    nonisolated func streamStep(_ request: ModelStepRequest) -> AsyncThrowingStream<ModelStepEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.started)
                do {
                    let response = try await self.next(request)
                    if !Task.isCancelled { continuation.yield(.final(response)) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
private struct DerivedSourceFactory: ModelProvider, ModelStepProviderFactory {
    let id = "derived-source-fixture"
    let supportedModels = ["openai-api:gpt-5.4-mini", "openai-api:gpt-5.4"]
    let script: DerivedSourceScript
    var tools: [any Tool] { [DerivedQuestionDeclaration(), DerivedMemoryDeclaration()] }
    func supportsModelSteps(for modelName: String) -> Bool { supportedModels.contains(modelName) }
    func createModelStepProvider(for modelName: String, usageContext: ModelUsageContext?) async throws -> (any ModelStepProvider)? { script }
    func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        await script.legacy()
        throw ModelStepFailure(category: .unavailable, code: "legacy_derived_fixture", message: "The fixture has no legacy model.")
    }
}
@Suite("Native derived work ownership")
struct NativeDerivedWorkTests {
    @Test(.timeLimit(.minutes(3)))
    func nativeProposalReviewUsesTheDurableOwnerAndRestrictedTools() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.waitForStartup(dispatchReadyTasks: false)
        defer { Task { await service.stop() } }
        let script = DerivedSourceScript(.completed, gate: SessionStepGate(), proposalReview: true)
        let model = "openai-api:gpt-5.4-mini"
        await service.overrideModelProviderForTests(DerivedSourceFactory(script: script), defaultModel: model)
        let models = [ProviderModelOption(id: model, title: "Fixture", capabilities: ["tools"])]
        let orchestrator = await service.sessionOrchestrator
        await orchestrator.updateAvailableModels(models)
        let agentID = "native-proposal-" + UUID().uuidString.lowercased()
        let projectID = "native-proposal-project-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Native proposals"))
        _ = try await service.createProject(.init(id: projectID, name: "Native proposal fixture"))
        let workspace = await service.workspaceRootURL
        let catalog = AgentCatalogFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role, selectedModel: model,
            documents: original.documents, automaticModelRouting: false, runtime: .init(sharedMemoryEnabled: false,
                nativeEngine: .unified, planningPolicy: .executor)), availableModels: models)
        let session = try await orchestrator.createSession(agentID: agentID, request: .init(projectId: projectID))
        _ = try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id,
            request: .init(userId: "fixture", content: "Completed source for proposals.", mode: .ask))
        let before = try await service.getAgentSession(agentID: agentID, sessionID: session.id)
        let failure = await service.runSelfImprovementProposalReview(agentID: agentID, sessionID: session.id, reason: "fixture")
        #expect(failure == nil)
        #expect(await script.legacyCalls == 0)
        let requests = await script.requests
        #expect(requests.count == 3)
        if requests.count >= 3 {
            #expect(requests[1].runId == requests[2].runId)
            #expect(requests[1].runId != requests[0].runId)
            #expect(requests[1].tools.contains { $0.toolId == "self_improvement.proposal_submit" })
            #expect(requests[1].tools.allSatisfy { CoreService.selfImprovementProposalToolAllowlist.contains($0.toolId) })
            #expect(requests[2].messages.compactMap(\.toolOutput).contains { $0.content.contains("nothing") })
        }
        let raw = try AgentSessionFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
            .loadSession(agentID: agentID, sessionID: session.id)
        let derived = raw.events.filter { $0.runtimeMetadata?.derivedSource?.kind.rawValue == "self_improvement_proposal" }
        #expect(derived.filter { $0.runtimeMetadata?.executionPhase == .started }.count == 1)
        #expect(derived.compactMap(\.toolResult).first?.data?.asObject?["action"]?.asString == "nothing")
        let after = try await service.getAgentSession(agentID: agentID, sessionID: session.id)
        #expect(after.events == before.events)
    }

    @Test(.timeLimit(.minutes(3)))
    func aNewDerivedRunKeepsTheConfiguredModelOverride() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.waitForStartup(dispatchReadyTasks: false)
        defer { Task { await service.stop() } }
        let script = DerivedSourceScript(.completed, gate: SessionStepGate())
        let model = "openai-api:gpt-5.4-mini"
        await service.overrideModelProviderForTests(DerivedSourceFactory(script: script), defaultModel: model)
        let models = [ProviderModelOption(id: model, title: "Fixture", capabilities: ["tools"])]
        let orchestrator = await service.sessionOrchestrator
        await orchestrator.updateAvailableModels(models)
        let agentID = "derived-loop-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Derived loop"))
        let workspace = await service.workspaceRootURL
        let catalog = AgentCatalogFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role, selectedModel: model,
            documents: original.documents, automaticModelRouting: false, runtime: .init(sharedMemoryEnabled: false,
                nativeEngine: .unified, planningPolicy: .executor)), availableModels: models)
        let session = try await orchestrator.createSession(agentID: agentID, request: .init())
        let result = try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id,
            request: .init(userId: "fixture", content: "Remember the completed result.", mode: .ask, clientMessageId: UUID().uuidString))
        try #require(result.appendedEvents.compactMap(\.runStatus).last?.stage == .done)
        let resolution = try await service.nativeDerivedWorkSource(agentID: agentID, sessionID: session.id)
        guard case .owned(let source) = resolution else { Issue.record("Missing foreground source"); return }
        let alternate = "openai-api:gpt-5.4"
        let completed = await service.runAgentMemoryCheckpoint(agentID: agentID, sessionID: session.id,
            reason: "fixture", modelOverride: alternate, source: source)
        #expect(completed)
        let requests = await script.requests
        #expect(requests.count == 2)
        #expect(requests.last?.model == alternate)
        let detail = try AgentSessionFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
            .loadSession(agentID: agentID, sessionID: session.id)
        let metadata = detail.events.last { $0.runtimeMetadata?.derivedSource != nil && $0.runtimeMetadata?.runState != nil }?.runtimeMetadata
        let checkpoint = try metadata?.runState.map { try JSONValueCoder.decode(RunStateSnapshot.self, from: $0) }
        #expect(checkpoint?.model == alternate)
        #expect(metadata?.derivedSource?.model == source.model)
    }

    @Test(.timeLimit(.minutes(3)), arguments: [false, true])
    func derivedRestartKeepsItsRunBudgetAndKnownToolResult(automatic: Bool) async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.waitForStartup(dispatchReadyTasks: false)
        defer { Task { await service.stop() } }
        let script = DerivedSourceScript(.completed, gate: SessionStepGate(), memoryCase: .write)
        let model = "openai-api:gpt-5.4-mini"
        await service.overrideModelProviderForTests(DerivedSourceFactory(script: script), defaultModel: model)
        let models = [ProviderModelOption(id: model, title: "Fixture", capabilities: ["tools"])]
        let orchestrator = await service.sessionOrchestrator
        await orchestrator.updateAvailableModels(models)
        let agentID = "derived-loop-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Derived loop"))
        let workspace = await service.workspaceRootURL
        let catalog = AgentCatalogFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role, selectedModel: model,
            documents: original.documents, automaticModelRouting: false, runtime: .init(sharedMemoryEnabled: false,
                nativeEngine: .unified, planningPolicy: .executor)), availableModels: models)
        let session = try await orchestrator.createSession(agentID: agentID, request: .init())
        let result = try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id,
            request: .init(userId: "fixture", content: "Remember the completed result.", mode: .ask, clientMessageId: UUID().uuidString))
        try #require(result.appendedEvents.compactMap(\.runStatus).last?.stage == .done)
        let resolution = try await service.nativeDerivedWorkSource(agentID: agentID, sessionID: session.id)
        guard case .owned(let source) = resolution else { Issue.record("Missing foreground source"); return }
        await service.runAgentMemoryCheckpoint(agentID: agentID, sessionID: session.id, reason: "fixture", source: source)
        let files = AgentSessionFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
        let originalJournal = try files.loadJournal(agentID: agentID, sessionID: session.id)
        let knownResult = try #require(originalJournal.records.first {
            $0.event.runtimeMetadata?.derivedSource == source &&
                $0.event.toolResult?.tool == "agent.documents.set_memory_markdown" && $0.event.toolResult?.ok == true
        })
        let oldRunID = try #require(knownResult.event.runtimeMetadata?.runId)
        let file = URL(fileURLWithPath: try files.sessionFilePath(agentID: agentID, sessionID: session.id))
        let complete = try Data(contentsOf: file)
        await service.stop()
        try complete.prefix(Int(knownResult.endCursor)).write(to: file)
        try catalog.writeAgentScopedMarkdown(agentID: agentID, userID: "fixture", field: .memory,
            markdown: "External correction after the known result.")
        let config = await service.currentConfig
        let fresh = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        defer { Task { await fresh.stop() } }
        let freshScript = DerivedSourceScript(.completed, gate: SessionStepGate())
        await fresh.overrideModelProviderForTests(DerivedSourceFactory(script: freshScript), defaultModel: model)
        await fresh.sessionOrchestrator.updateAvailableModels(models)
        await fresh.waitForStartup(dispatchReadyTasks: false)
        let completed: Bool
        if automatic {
            await fresh.nativeDerivedRecoveryTask?.value
            let tail = try AgentSessionFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
                .loadSession(agentID: agentID, sessionID: session.id).events
                .last { $0.runtimeMetadata?.runId == oldRunID && $0.runtimeMetadata?.runState != nil }
            completed = try tail?.runtimeMetadata?.runState.map {
                try JSONValueCoder.decode(RunStateSnapshot.self, from: $0).phase == .settled
            } ?? false
        } else {
            completed = await fresh.runAgentMemoryCheckpoint(agentID: agentID, sessionID: session.id,
                reason: "fixture-restart", modelOverride: "openai-api:gpt-5.4", source: source)
        }
        #expect(completed)
        let restored = try AgentSessionFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
            .loadSession(agentID: agentID, sessionID: session.id)
        let records = restored.events.compactMap(\.runtimeMetadata).filter { $0.derivedSource == source }
        #expect(Set(records.map(\.runId)) == [oldRunID])
        let checkpoint = try records.last(where: { $0.runState != nil })?.runState.map {
            try JSONValueCoder.decode(RunStateSnapshot.self, from: $0)
        }
        #expect(checkpoint?.phase == .settled)
        #expect(checkpoint?.requestAttempts == 2)
        #expect(checkpoint?.toolRoundsUsed == 1)
        #expect(checkpoint?.model == model)
        let requests = await freshScript.requests
        #expect(requests.count == 1)
        #expect(requests.first?.model == model)
        let originalScope = await script.requests.first { $0.runId == oldRunID }?.cacheScope
        #expect(requests.first?.cacheScope == originalScope)
        #expect(requests.first?.messages.compactMap(\.toolOutput).contains { $0.callId == "memory-write" } == true)
        #expect(await freshScript.legacyCalls == 0)
        #expect(try catalog.readAgentDocuments(agentID: agentID, userID: "fixture").memoryMarkdown
            .trimmingCharacters(in: .whitespacesAndNewlines) == "External correction after the known result.")
    }

    @Test(.timeLimit(.minutes(3)))
    func autodreamRecordsNativeFailureAndLeavesItEligibleForRetry() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.waitForStartup(dispatchReadyTasks: false)
        defer { Task { await service.stop() } }
        let script = DerivedSourceScript(.completed, gate: SessionStepGate(), memoryCase: .providerFailure)
        let model = "openai-api:gpt-5.4-mini"
        await service.overrideModelProviderForTests(DerivedSourceFactory(script: script), defaultModel: model)
        let models = [ProviderModelOption(id: model, title: "Fixture", capabilities: ["tools"])]
        let orchestrator = await service.sessionOrchestrator
        await orchestrator.updateAvailableModels(models)
        let agentID = "derived-loop-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Derived loop"))
        let workspace = await service.workspaceRootURL
        let catalog = AgentCatalogFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role, selectedModel: model,
            documents: original.documents, automaticModelRouting: false, runtime: .init(sharedMemoryEnabled: false,
                nativeEngine: .unified, planningPolicy: .executor)), availableModels: models)
        let session = try await orchestrator.createSession(agentID: agentID, request: .init())
        let result = try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id,
            request: .init(userId: "fixture", content: "Remember the completed result.", mode: .ask, clientMessageId: UUID().uuidString))
        try #require(result.appendedEvents.compactMap(\.runStatus).last?.stage == .done)
        let resolution = try await service.nativeDerivedWorkSource(agentID: agentID, sessionID: session.id)
        guard case .owned = resolution else { Issue.record("Missing foreground source"); return }
        _ = await service.runAutodreamPass(reason: "fixture")
        let first = await service.store.autodreamSessionReview(agentId: agentID, sessionId: session.id)
        #expect(first?.status == "failed")
        let detail = try await service.getAgentSession(agentID: agentID, sessionID: session.id)
        #expect(await service.shouldAutodreamReview(agentID: agentID, session: detail.summary))
        _ = await service.runAutodreamPass(reason: "fixture-retry")
        let second = await service.store.autodreamSessionReview(agentId: agentID, sessionId: session.id)
        #expect(second?.status == "failed")
        #expect(await script.requests.count == 3)
        #expect(await script.legacyCalls == 0)
        #expect(try await service.getAgentSession(agentID: agentID, sessionID: session.id).summary.userTurnCount == 1)
    }

    @Test(.timeLimit(.minutes(3)))
    func coreShutdownCancelsItsNativeDerivedOwner() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.waitForStartup(dispatchReadyTasks: false)
        defer { Task { await service.stop() } }
        let gate = SessionStepGate()
        defer { Task { await gate.release() } }
        let script = DerivedSourceScript(.completed, gate: gate, holdMemory: true)
        let model = "openai-api:gpt-5.4-mini"
        await service.overrideModelProviderForTests(DerivedSourceFactory(script: script), defaultModel: model)
        let models = [ProviderModelOption(id: model, title: "Fixture", capabilities: ["tools"])]
        let orchestrator = await service.sessionOrchestrator
        await orchestrator.updateAvailableModels(models)
        let agentID = "derived-loop-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Derived loop"))
        let workspace = await service.workspaceRootURL
        let catalog = AgentCatalogFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role, selectedModel: model,
            documents: original.documents, automaticModelRouting: false, runtime: .init(sharedMemoryEnabled: false,
                nativeEngine: .unified, planningPolicy: .executor)), availableModels: models)
        let session = try await orchestrator.createSession(agentID: agentID, request: .init())
        let result = try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id,
            request: .init(userId: "fixture", content: "Remember the completed result.", mode: .ask, clientMessageId: UUID().uuidString))
        try #require(result.appendedEvents.compactMap(\.runStatus).last?.stage == .done)
        let resolution = try await service.nativeDerivedWorkSource(agentID: agentID, sessionID: session.id)
        guard case .owned(let source) = resolution else { Issue.record("Missing foreground source"); return }
        let background = Task<Bool, Error> {
            await service.runAgentMemoryCheckpoint(agentID: agentID, sessionID: session.id, reason: "fixture", source: source)
        }
        defer { background.cancel() }
        let held = await gate.waitUntilHeld(during: background)
        try #require(held)
        let state = try #require(await service.nativeDerivedRunsBySession[session.id]?.values.first)
        await service.stop()
        #expect(await state.phase == .stopping)
        #expect(await service.nativeDerivedRunsBySession[session.id] == nil)
        await gate.release()
        #expect(try await background.value == false)
    }

    @Test(.timeLimit(.minutes(3)), arguments: DerivedMemoryCase.allCases)
    fileprivate func nativeMemoryPublicCompletionMatchesDurableOutcome(scenario: DerivedMemoryCase) async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.waitForStartup(dispatchReadyTasks: false)
        defer { Task { await service.stop() } }
        let script = DerivedSourceScript(.completed, gate: SessionStepGate(), memoryCase: scenario)
        let model = "openai-api:gpt-5.4-mini"
        await service.overrideModelProviderForTests(DerivedSourceFactory(script: script), defaultModel: model)
        let models = [ProviderModelOption(id: model, title: "Fixture", capabilities: ["tools"])]
        let orchestrator = await service.sessionOrchestrator
        await orchestrator.updateAvailableModels(models)
        let agentID = "derived-loop-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Derived loop"))
        let workspace = await service.workspaceRootURL
        let catalog = AgentCatalogFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role, selectedModel: model,
            documents: original.documents, automaticModelRouting: false, runtime: .init(sharedMemoryEnabled: false,
                nativeEngine: .unified, planningPolicy: .executor)), availableModels: models)
        let session = try await orchestrator.createSession(agentID: agentID, request: .init())
        let result = try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id,
            request: .init(userId: "fixture", content: "Remember the completed result.", mode: .ask, clientMessageId: UUID().uuidString))
        try #require(result.appendedEvents.compactMap(\.runStatus).last?.stage == .done)
        let resolution = try await service.nativeDerivedWorkSource(agentID: agentID, sessionID: session.id)
        guard case .owned(let source) = resolution else { Issue.record("Missing foreground source"); return }
        let before = try await service.getAgentSession(agentID: agentID, sessionID: session.id)
        if scenario == .write {
            await service.runAgentMemoryCheckpoint(agentID: agentID, sessionID: session.id, reason: "fixture", source: source)
        } else {
            let receipt = try await service.requestAgentMemoryCheckpoint(agentID: agentID, sessionID: session.id, reason: "fixture")
            #expect(receipt.ok == (scenario != .providerFailure))
        }
        #expect(await script.legacyCalls == 0)
        let fresh = AgentSessionFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
        let raw = try fresh.loadSession(agentID: agentID, sessionID: session.id)
        let derived = raw.events.filter { $0.runtimeMetadata?.derivedSource != nil }
        #expect(!derived.isEmpty)
        let saved = try derived.last(where: { $0.runtimeMetadata?.runState != nil })?.runtimeMetadata?.runState.map {
            try JSONValueCoder.decode(RunStateSnapshot.self, from: $0)
        }
        #expect(saved?.phase == (scenario == .providerFailure ? .stopping : .settled))
        if scenario == .providerFailure {
            #expect(saved?.toolStop?.failure.code == "memory_authentication_failed")
            #expect(raw.summary.userTurnCount == before.summary.userTurnCount)
            #expect(raw.events.compactMap(\.memoryCheckpoint).last?.status == .failed)
        } else if scenario == .write {
            let docs = try catalog.readAgentDocuments(agentID: agentID, userID: "fixture")
            #expect(docs.memoryMarkdown.trimmingCharacters(in: .whitespacesAndNewlines) == "Verified durable fixture preference.")
            let requested = derived.filter { $0.toolCall?.tool == "agent.documents.set_memory_markdown" }
            #expect(requested.count == 1)
            #expect(derived.contains { $0.runtimeMetadata?.executionPhase == .started })
            #expect(derived.compactMap(\.toolResult).last?.ok == true)
            #expect(SessionToolRecovery.unknownEffectCallIDs(in: raw.events).isEmpty)
            let visible = try await service.getAgentSession(agentID: agentID, sessionID: session.id, eventLimit: 1)
            #expect(visible.events.count == 1)
            #expect(visible.events.allSatisfy { $0.runtimeMetadata?.derivedSource == nil })
        }
    }

    @Test(.timeLimit(.minutes(3)))
    func nativeMemoryUsesDurableCommonLoopWithoutChangingForegroundHistory() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.waitForStartup(dispatchReadyTasks: false)
        defer { Task { await service.stop() } }
        let script = DerivedSourceScript(.completed, gate: SessionStepGate())
        let model = "openai-api:gpt-5.4-mini"
        await service.overrideModelProviderForTests(DerivedSourceFactory(script: script), defaultModel: model)
        let models = [ProviderModelOption(id: model, title: "Fixture", capabilities: ["tools"])]
        let orchestrator = await service.sessionOrchestrator
        await orchestrator.updateAvailableModels(models)
        let agentID = "derived-loop-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Derived loop"))
        let workspace = await service.workspaceRootURL
        let catalog = AgentCatalogFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role, selectedModel: model,
            documents: original.documents, automaticModelRouting: false, runtime: .init(sharedMemoryEnabled: false,
                nativeEngine: .unified, planningPolicy: .executor)), availableModels: models)
        let session = try await orchestrator.createSession(agentID: agentID, request: .init())
        let result = try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id,
            request: .init(userId: "fixture", content: "Remember the completed result.", mode: .ask, clientMessageId: UUID().uuidString))
        try #require(result.appendedEvents.compactMap(\.runStatus).last?.stage == .done)
        let resolution = try await service.nativeDerivedWorkSource(agentID: agentID, sessionID: session.id)
        guard case .owned(let source) = resolution else { Issue.record("Missing foreground source"); return }
        let before = try await service.getAgentSession(agentID: agentID, sessionID: session.id)
        await service.runAgentMemoryCheckpoint(agentID: agentID, sessionID: session.id, reason: "fixture", source: source)
        #expect(await script.legacyCalls == 0)
        let requests = await script.requests
        #expect(requests.count == 2)
        #expect(requests.last?.runId != requests.first?.runId)
        #expect(requests.last?.messages.contains { $0.text.contains("Internal MEMORY checkpoint") } == true)
        let contextCopies = requests.last?.messages.reduce(0) { total, message in
            total + message.text.components(separatedBy: "Internal MEMORY checkpoint").count - 1
        }
        #expect(contextCopies == 1)
        let fresh = AgentSessionFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
        let raw = try fresh.loadSession(agentID: agentID, sessionID: session.id)
        let derived = raw.events.compactMap(\.runtimeMetadata).filter { $0.derivedSource != nil }
        #expect(!derived.isEmpty)
        #expect(derived.allSatisfy { $0.derivedSource == source })
        let saved = try derived.last(where: { $0.runState != nil })?.runState.map { try JSONValueCoder.decode(RunStateSnapshot.self, from: $0) }
        #expect(saved?.phase == .settled)
        #expect(saved?.loopConfig?.completionContract == .background)
        #expect(saved?.requestAttempts == 1)
        #expect(await service.nativeDerivedWorkSourceIsCurrent(source))
        let after = try await service.getAgentSession(agentID: agentID, sessionID: session.id)
        #expect(after.events.map(\.id) == before.events.map(\.id))
        #expect(after.events.compactMap(\.runStatus).last == before.events.compactMap(\.runStatus).last)
    }

    @Test(.timeLimit(.minutes(3)), arguments: DerivedSourceCase.allCases)
    fileprivate func automaticMemoryRequiresACompletedCurrentSource(scenario: DerivedSourceCase) async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.waitForStartup(dispatchReadyTasks: false)
        let gate = SessionStepGate()
        defer { Task { await gate.release(); await service.stop() } }
        let script = DerivedSourceScript(scenario, gate: gate)
        let model = "openai-api:gpt-5.4-mini"
        await service.overrideModelProviderForTests(DerivedSourceFactory(script: script), defaultModel: model)
        let models = [ProviderModelOption(id: model, title: "Fixture", capabilities: ["tools"])]
        let orchestrator = await service.sessionOrchestrator
        await orchestrator.updateAvailableModels(models)
        let agentID = "derived-source-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Derived source"))
        let workspace = await service.workspaceRootURL
        let catalog = AgentCatalogFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role, selectedModel: model,
            documents: original.documents, automaticModelRouting: false, autoApproveInput: false,
            runtime: .init(sharedMemoryEnabled: false, nativeEngine: .unified, planningPolicy: .executor)), availableModels: models)
        let session = try await orchestrator.createSession(agentID: agentID, request: .init())
        let initial = try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id,
            request: .init(userId: "fixture", content: "Prepare the source.",
                mode: scenario == .waitingInput ? .debug : .ask, clientMessageId: UUID().uuidString))
        try #require(initial.appendedEvents.compactMap(\.runStatus).last?.stage == (scenario == .waitingInput ? .paused : .done))
        var second: Task<AgentSessionMessageResponse, Error>?
        if scenario == .superseded {
            let resolution = try await service.nativeDerivedWorkSource(agentID: agentID, sessionID: session.id)
            let source: NativeDerivedWorkSource
            if case .owned(let value) = resolution { source = value }
            else { Issue.record("The completed source was not captured."); return }
            _ = try await service.updateAgentToolsPolicy(agentID: agentID, request: .init(
                approval: .init(enabled: true), guardrails: .init(allowedWriteRoots: [workspace.path])))
            let file = workspace.appendingPathComponent("deferred-effect.txt")
            try "original".write(to: file, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: file) }
            let effect = Task {
                await service.invokeToolFromDerivedRuntime(source: source,
                    request: .init(tool: "files.write", arguments: ["path": .string(file.path), "content": .string("stale write")]))
            }
            defer { effect.cancel() }
            var pending: ToolApprovalRecord?
            for _ in 0..<1_000 {
                pending = await service.listPendingToolApprovals().first
                if pending != nil { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            let approval = try #require(pending)
            try #require(approval.sessionId == session.id)
            // Admission through the real owner can race an older background approval.
            let run = Task {
                try await orchestrator.postMessage(agentID: agentID, sessionID: session.id,
                    request: .init(userId: "fixture", content: "A newer source is active.", mode: .ask, clientMessageId: UUID().uuidString))
            }
            second = run
            let held = await gate.waitUntilHeld(during: run)
            try #require(held)
            let decision = await service.approveToolApproval(id: approval.id, decidedBy: "fixture")
            #expect(decision?.status == .approved)
            let denied = await effect.value
            #expect(denied.error?.code == "tool_forbidden")
            #expect(try String(contentsOf: file, encoding: .utf8) == "original")
        }
        let scheduled = await service.scheduleAgentMemoryCheckpoint(agentID: agentID, sessionID: session.id, reason: "fixture")
        #expect(scheduled == (scenario == .completed))
        if scenario != .completed { #expect(await script.legacyCalls == 0) }
        await gate.release()
        if let second { _ = try await second.value }
    }
}
