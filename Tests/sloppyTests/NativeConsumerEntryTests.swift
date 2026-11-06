import Foundation
import ACPModel
import AnyLanguageModel
import AgentRuntime
import PluginSDK
import Protocols
import SloppyRuntime
import Testing
@testable import sloppy

private enum NativeEntry: CaseIterable { case workflow, goal, acp, heartbeat }

private actor NativeEntryScript: ModelStepProvider {
    private(set) var requests: [ModelStepRequest] = []
    private(set) var legacyCalls = 0
    let heartbeat: Bool
    init(heartbeat: Bool) { self.heartbeat = heartbeat }
    func legacy() { legacyCalls += 1 }
    func response(_ request: ModelStepRequest) -> ModelStepResponse {
        requests.append(request)
        return .init(text: heartbeat ? CoreService.heartbeatSuccessToken : "Native entry result", stopReason: .endTurn)
    }
    nonisolated func streamStep(_ request: ModelStepRequest) -> AsyncThrowingStream<ModelStepEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.started)
                continuation.yield(.final(await self.response(request)))
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

private struct NativeEntryFactory: ModelProvider, ModelStepProviderFactory {
    let id = "native-entry"
    let supportedModels = ["openai-api:gpt-5.4-mini"]
    let script: NativeEntryScript
    func supportsModelSteps(for modelName: String) -> Bool { supportedModels.contains(modelName) }
    func createModelStepProvider(for modelName: String, usageContext: ModelUsageContext?) async throws -> (any ModelStepProvider)? { script }
    func createLanguageModel(for modelName: String) async throws -> any LanguageModel { await script.legacy(); throw CancellationError() }
}

@Suite("Native consumer entry points")
struct NativeConsumerEntryTests {
    @Test(arguments: NativeEntry.allCases, [AgentNativeEngine.legacy, .unified])
    fileprivate func eachNativeEntryUsesCanonicalSingleStepOwnership(entry: NativeEntry, engine: AgentNativeEngine) async throws {
        let agentID = "native-entry-" + UUID().uuidString.lowercased()
        var config = CoreConfig.test
        config.acp.server = .init(enabled: true, agentId: agentID, cwd: nil)
        let service = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        defer { Task { await service.stop() } }
        let script = NativeEntryScript(heartbeat: entry == .heartbeat)
        let model = "openai-api:gpt-5.4-mini"
        await service.overrideModelProviderForTests(NativeEntryFactory(script: script), defaultModel: model)
        let models = [ProviderModelOption(id: model, title: "Fixture")]
        await service.sessionOrchestrator.updateAvailableModels(models)
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Native entry fixture"))
        let workspace = await service.workspaceRootURL
        let catalog = AgentCatalogFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        var documents = original.documents
        documents.heartbeatMarkdown = "Check the supplied heartbeat context."
        var heartbeat = original.heartbeat
        heartbeat.enabled = true
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role, selectedModel: model,
            documents: documents, heartbeat: heartbeat, automaticModelRouting: false,
            runtime: .init(sharedMemoryEnabled: false, nativeEngine: engine, planningPolicy: .executor)), availableModels: models)
        let sessionID: String
        switch entry {
        case .workflow:
            let projectID = "native-entry-project-" + UUID().uuidString.lowercased()
            _ = try await service.createProject(.init(id: projectID, name: "Native workflow"))
            let result = await service.executeWorkflowAgentRequest(node: .init(id: "agent", type: .agentStep,
                title: "Native", laneId: "system", config: ["agentId": .string(agentID), "prompt": .string("Inspect the task"),
                    "mode": .string("ask"), "model": .string(model)]),
                context: .init(projectId: projectID, startedBy: "fixture", input: [:]), input: [:])
            #expect(result.ok)
            sessionID = try #require(result.data?.asObject?["sessionId"]?.asString)
        case .goal:
            let session = try await service.createAgentSession(agentID: agentID, request: .init())
            _ = try await service.startAgentSessionGoal(agentID: agentID, sessionID: session.id,
                request: .init(objective: "Inspect once", maxAttempts: 1, mode: .ask))
            sessionID = session.id
        case .acp:
            let delegate = SloppyACPServerDelegate(service: service, agentID: agentID, defaultCwd: workspace.path, sendUpdate: { _, _ in })
            let session = try await delegate.handleNewSession(NewSessionRequest(cwd: workspace.path))
            _ = try await delegate.handleSetSessionConfigOption(.init(sessionId: session.sessionId,
                configId: SloppyACPServerDelegate.modeConfigID, value: SessionConfigValueId(AgentChatMode.ask.rawValue)))
            _ = try await delegate.handlePrompt(.init(sessionId: session.sessionId, prompt: [.text(TextContent(text: "Inspect this task"))]))
            sessionID = session.sessionId.value
        case .heartbeat:
            await service.runAgentHeartbeat(agentID: agentID)
            let updated = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
            #expect(updated.heartbeatStatus.lastResult == "ok")
            sessionID = try #require(updated.heartbeatStatus.lastSessionId)
        }
        let requests = await script.requests
        #expect(requests.count == 1)
        #expect(await script.legacyCalls == 0)
        let detail = try AgentSessionFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
            .loadSession(agentID: agentID, sessionID: sessionID)
        #expect(detail.events.contains { $0.runtimeMetadata?.modelResponse != nil && $0.runtimeMetadata?.runId == requests.first?.runId })
        let raw = try #require(detail.events.last { $0.runtimeMetadata?.runState != nil }?.runtimeMetadata?.runState)
        #expect(try JSONValueCoder.decode(RunStateSnapshot.self, from: raw).phase == .settled)
    }
    @Test(arguments: [false, true])
    func aCompetingCoreCannotStartGenerationOrEnqueueIntoTheOwnersWorkspace(usingShutdown: Bool) async throws {
        let config = CoreConfig.test
        let owner = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let model = "openai-api:gpt-5.4-mini", agentID = "exclusive-core"
        let models = [ProviderModelOption(id: model, title: "Fixture")]
        await owner.overrideModelProviderForTests(NativeEntryFactory(script: NativeEntryScript(heartbeat: false)), defaultModel: model)
        await owner.sessionOrchestrator.updateAvailableModels(models)
        _ = try await owner.createAgent(.init(id: agentID, displayName: agentID, role: "Owner"))
        let workspace = await owner.workspaceRootURL
        let catalog = AgentCatalogFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role, selectedModel: model,
            documents: original.documents, automaticModelRouting: false,
            runtime: .init(sharedMemoryEnabled: false, nativeEngine: .unified, planningPolicy: .executor)), availableModels: models)
        let session = try await owner.createAgentSession(agentID: agentID, request: .init())
        let store = AgentSessionFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
        let file = URL(fileURLWithPath: try store.sessionFilePath(agentID: agentID, sessionID: session.id))
        let before = try Data(contentsOf: file)
        let contender = CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let script = NativeEntryScript(heartbeat: false)
        await contender.overrideModelProviderForTests(NativeEntryFactory(script: script), defaultModel: model)
        await contender.sessionOrchestrator.updateAvailableModels(models)
        var rejected = false
        do { _ = try await contender.postAgentSessionMessage(agentID: agentID, sessionID: session.id,
            request: .init(userId: "fixture", content: "Competing request", mode: .ask)) }
        catch { rejected = true }
        #expect(rejected)
        #expect(await script.requests.isEmpty)
        #expect(try Data(contentsOf: file) == before)
        await contender.stop()
        if usingShutdown { await owner.shutdownChannelPlugins() } else { await owner.stop() }
        let stoppedWriter = await owner.sessionStore
        var staleWriteRejected = false
        do {
            _ = try stoppedWriter.appendEvents(agentID: agentID, sessionID: session.id, events: [
                .init(agentId: agentID, sessionId: session.id, type: .message,
                    message: .init(role: .assistant, segments: [.init(kind: .text, text: "Stale completion")]))
            ])
        } catch { staleWriteRejected = true }
        #expect(staleWriteRejected)
        #expect(try Data(contentsOf: file) == before)
    }

}
