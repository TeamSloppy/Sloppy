import Foundation
import AnyLanguageModel
import AgentRuntime
import PluginSDK
import Protocols
import SloppyRuntime
import Testing
@testable import sloppy

private actor FailingNativeFactory: ModelProvider, ModelStepProviderFactory {
    nonisolated let id = "failing-native-fixture"
    nonisolated let supportedModels = ["openai-api:gpt-5.4-mini"]
    nonisolated let tools: [any Tool] = []
    nonisolated let available: Bool
    private(set) var creations = 0
    private(set) var legacyCalls = 0
    init(available: Bool = true) { self.available = available }
    nonisolated func supportsModelSteps(for modelName: String) -> Bool { available && supportedModels.contains(modelName) }
    func createModelStepProvider(for modelName: String, usageContext: ModelUsageContext?) async throws -> (any ModelStepProvider)? {
        creations += 1
        throw ModelStepFailure(category: .authentication, code: "fixture_auth_failure",
            message: "The fixture provider is unavailable.", stage: .preparation)
    }
    func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        legacyCalls += 1
        throw CancellationError()
    }
}

@Suite("Native failure settlement")
struct NativeFailureSettlementTests {
    @Test
    func providerFailureIsDurableBeforeDeliveryAndDoesNotRegenerateAfterRestart() async throws {
        let config = CoreConfig.test
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.waitForStartup(dispatchReadyTasks: false)
        let provider = FailingNativeFactory()
        let model = provider.supportedModels[0]
        await service.overrideModelProviderForTests(provider, defaultModel: model)
        let models = [ProviderModelOption(id: model, title: "Fixture", capabilities: ["tools"])]
        let orchestrator = await service.sessionOrchestrator
        await orchestrator.updateAvailableModels(models)
        let workspace = await service.workspaceRootURL
        let catalog = AgentCatalogFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
        let agentID = "native-failure-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Failure fixture"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role, selectedModel: model,
            documents: original.documents, automaticModelRouting: false,
            runtime: .init(sharedMemoryEnabled: false, nativeEngine: .unified, planningPolicy: .executor)), availableModels: models)
        let session = try await orchestrator.createSession(agentID: agentID, request: .init())
        let messageID = UUID().uuidString
        let request = AgentSessionPostMessageRequest(userId: "fixture", content: "Run the failure fixture.", mode: .ask, clientMessageId: messageID)
        let response = try await service.postAgentSessionMessage(agentID: agentID, sessionID: session.id, request: request)
        #expect(response.appendedEvents.compactMap(\.runStatus).last?.stage == .interrupted)
        #expect(await provider.creations == 1)
        #expect(await provider.legacyCalls == 0)
        let store = await service.sessionStore
        let saved = try store.loadJournal(agentID: agentID, sessionID: session.id)
        let last = try #require(saved.records.last { $0.event.runtimeMetadata?.runState != nil })
        let snapshot = try JSONValueCoder.decode(RunStateSnapshot.self, from: #require(last.event.runtimeMetadata?.runState))
        #expect(snapshot.phase == .stopping)
        #expect(snapshot.toolStop?.reason.rawValue == "model_failure")
        let failure = try JSONValueCoder.encode(snapshot).asObject?["toolStop"]?.asObject?["modelFailure"]?.asObject
        #expect(failure?["category"]?.asString == "authentication")
        #expect(failure?["code"]?.asString == "fixture_auth_failure")
        guard snapshot.phase == .stopping else { return }
        // Keep the real synchronized terminal checkpoint, losing only later presentation records.
        let file = URL(fileURLWithPath: try store.sessionFilePath(agentID: agentID, sessionID: session.id))
        await service.stop()
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(last.endCursor))
        try handle.synchronize()
        try handle.close()
        let restarted = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        defer { Task { await restarted.stop() } }
        await restarted.waitForStartup(dispatchReadyTasks: false)
        let unavailable = FailingNativeFactory(available: false)
        await restarted.overrideModelProviderForTests(unavailable, defaultModel: model)
        await restarted.sessionOrchestrator.updateAvailableModels(models)
        let recovered = try await restarted.postAgentSessionMessage(agentID: agentID, sessionID: session.id, request: request)
        #expect(recovered.appendedEvents.compactMap(\.runStatus).last?.stage == .interrupted)
        #expect(recovered.appendedEvents.compactMap(\.message).flatMap(\.segments).compactMap(\.text).joined().contains("The fixture provider is unavailable."))
        #expect(await unavailable.creations == 0)
        #expect(await unavailable.legacyCalls == 0)
        let final = try store.loadSession(agentID: agentID, sessionID: session.id)
        #expect(final.events.filter { $0.message?.id == messageID && $0.message?.role == .user }.count == 1)
    }
}
