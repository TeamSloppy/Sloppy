import Foundation
import AnyLanguageModel
import AgentRuntime
import PluginSDK
import Protocols
import SloppyRuntime
import Testing
@testable import sloppy

private enum CoordinatorScenario: CaseIterable { case status, correctedStatus, missingHandoff, delegate }
private struct CoordinatorDeclaration: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String
    let action: String
    var name: String { "long_chat." + action }
    var description: String { "Coordinator fixture" }
    var parameters: GenerationSchema { LongChatTool(action: action).parameters }
    func call(arguments: GeneratedContent) async throws -> String { throw CancellationError() }
}
private actor CoordinatorScript: ModelStepProvider {
    let scenario: CoordinatorScenario
    private(set) var requests: [ModelStepRequest] = []
    private(set) var legacyCalls = 0
    init(_ scenario: CoordinatorScenario) { self.scenario = scenario }
    func legacy() { legacyCalls += 1 }
    func next(_ request: ModelStepRequest) -> ModelStepResponse {
        requests.append(request)
        if request.tools.isEmpty && request.messages.contains(where: { $0.text.contains("[Coordinator factual report review]") }) {
            let raw = scenario == .correctedStatus
                ? #"{"supported":false,"correctedResponse":"Only the recorded status is confirmed."}"#
                : #"{"supported":true,"correctedResponse":null}"#
            return .init(text: raw, stopReason: .endTurn)
        }
        if requests.count == 1 && scenario != .missingHandoff {
            let name = scenario == .delegate ? "long_chat_delegate" : "long_chat_status"
            let raw = scenario == .delegate
                ? #"{"assignment":{"requestKey":"one","title":"Inspect fixture","acceptanceCriteria":"Return inspection","tasks":[{"key":"inspect","title":"Inspect","objective":"Read the assigned fixture","resourceKeys":[],"dependsOn":[],"readOnly":true}]}}"# : "{}"
            return .init(toolCalls: [.init(id: "coordinator-operation", name: name, rawArguments: raw)], stopReason: .toolCalls)
        }
        return .init(text: "Recorded coordinator result.", stopReason: .endTurn)
    }
    nonisolated func streamStep(_ request: ModelStepRequest) -> AsyncThrowingStream<ModelStepEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { continuation.yield(.started); continuation.yield(.final(await self.next(request))); continuation.finish() }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
private struct CoordinatorFactory: ModelProvider, ModelStepProviderFactory {
    let id = "coordinator-fixture"
    let supportedModels = ["openai-api:gpt-5.4-mini"]
    let script: CoordinatorScript
    var tools: [any Tool] { [CoordinatorDeclaration(action: "status"), CoordinatorDeclaration(action: "delegate")] }
    func supportsModelSteps(for modelName: String) -> Bool { supportedModels.contains(modelName) }
    func createModelStepProvider(for modelName: String, usageContext: ModelUsageContext?) async throws -> (any ModelStepProvider)? { script }
    func createLanguageModel(for modelName: String) async throws -> any LanguageModel { await script.legacy(); throw CancellationError() }
}
@Suite("Native coordinator ownership")
struct NativeCoordinatorLoopTests {
    @Test(arguments: CoordinatorScenario.allCases)
    fileprivate func coordinatorRecoveryAndReportReviewShareTheDurableOwner(scenario: CoordinatorScenario) async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.waitForStartup(dispatchReadyTasks: false)
        defer { Task { await service.stop() } }
        let script = CoordinatorScript(scenario)
        let model = "openai-api:gpt-5.4-mini"
        await service.overrideModelProviderForTests(CoordinatorFactory(script: script), defaultModel: model)
        let models = [ProviderModelOption(id: model, title: "Fixture", capabilities: ["tools"])]
        let orchestrator = await service.sessionOrchestrator
        await orchestrator.updateAvailableModels(models)
        let agentID = "coordinator-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Coordinator"))
        let workspace = await service.workspaceRootURL
        let catalog = AgentCatalogFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role, selectedModel: model,
            documents: original.documents, automaticModelRouting: false,
            runtime: .init(sharedMemoryEnabled: false, nativeEngine: .unified, planningPolicy: .executor)), availableModels: models)
        let session = try await service.openLongChat(agentID: agentID, userID: "fixture")
        let messageID = UUID().uuidString
        let request = AgentSessionPostMessageRequest(userId: "fixture", content: "Inspect the assigned fixture.",
            mode: scenario == .status || scenario == .correctedStatus ? .ask : .build, clientMessageId: messageID)
        try await service.prepareNativeCoordinatorFixture(agentID: agentID, sessionID: session.id, request: request)
        var response: AgentSessionMessageResponse?
        do { response = try await orchestrator.postMessage(agentID: agentID, sessionID: session.id, request: request, userMessageAlreadyPersisted: true) } catch { }
        #expect(response != nil)
        let requests = await script.requests
        #expect(requests.count == 3)
        #expect(Set(requests.map(\.runId)).count == 1)
        #expect(Set(requests.map(\.userTurnId)) == [messageID])
        #expect(await script.legacyCalls == 0)
        let store = await service.sessionStore
        let detail = try store.loadSession(agentID: agentID, sessionID: session.id)
        let journal = SessionLoopJournal(store: store, agentID: agentID, sessionID: session.id, authorizeWriter: {})
        let restored = try await journal.restoreRunState(userTurnID: messageID)
        #expect(restored != nil)
        if let restored {
            let snapshot = await restored.snapshot()
            #expect(snapshot.loopConfig?.completionContract == .coordinator)
            #expect(snapshot.requestAttempts == 3)
            #expect(snapshot.phase == .settled)
            let accepted = try #require(detail.events.compactMap(\.runtimeMetadata).first { $0.requestFingerprint != nil })
            let fresh = try AgentSessionFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
                .loadSession(agentID: agentID, sessionID: session.id)
            let terminal = try NativeSessionDelivery.settledResponse(in: fresh, metadata: accepted, generation: snapshot.generation)
            #expect(terminal.text == (scenario == .correctedStatus
                ? "Only the recorded status is confirmed." : "Recorded coordinator result."))
            if scenario == .missingHandoff {
                #expect(snapshot.recoveryCounts["coordinator_recovery"] == 2)
                #expect(detail.events.last(where: { $0.runStatus != nil })?.runStatus?.stage == .interrupted)
            } else {
                #expect(requests.last?.tools.isEmpty == true)
                #expect(detail.events.contains { $0.runtimeMetadata?.modelResponse != nil && $0.runtimeMetadata?.presentationOnly == true })
                #expect(!detail.events.contains { $0.message?.segments.contains(where: { $0.text?.contains("\"supported\"") == true }) == true })
                #expect(detail.events.contains { $0.toolResult?.tool == (scenario == .delegate ? "long_chat.delegate" : "long_chat.status") && $0.toolResult?.ok == true })
            }
        }
        let conversation = try await service.getLongChat(agentID: agentID, sessionID: session.id)
        #expect(conversation.assignments.count == (scenario == .delegate ? 1 : 0))
    }
}
private extension CoreService {
    func prepareNativeCoordinatorFixture(agentID: String, sessionID: String, request: AgentSessionPostMessageRequest) async throws {
        // Keep accepted assignments queued: this fixture tests the actual coordinator, not worker dispatch.
        longChatIsStopping = true
        _ = try enqueueLongChatMessage(agentID: agentID, sessionID: sessionID, request: request)
        longChatCurrentTurns[sessionID] = request.clientMessageId
        await runtime.setChannelToolScope(channelId: sessionChannelID(agentID: agentID, sessionID: sessionID),
            toolIDs: ["long_chat.status", "long_chat.delegate"])
    }
}
