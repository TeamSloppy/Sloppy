import Foundation
import AnyLanguageModel
import AgentRuntime
import PluginSDK
import Protocols
import SloppyRuntime
import Testing
@testable import sloppy

private actor NativeProactiveScript: ModelStepProvider {
    private(set) var requests: [ModelStepRequest] = []
    private(set) var legacyCalls = 0
    private var rejectsRequests = false
    func setCredentialFailure(_ value: Bool) { rejectsRequests = value }
    func legacy() { legacyCalls += 1 }
    func response(_ request: ModelStepRequest) throws -> ModelStepResponse {
        requests.append(request)
        if rejectsRequests { throw ModelStepFailure(category: .authentication, code: "fixture_expired_credentials", message: "Fixture credentials expired") }
        if request.messages.compactMap(\.toolOutput).contains(where: { $0.callId == "report" }) {
            return .init(text: "Report recorded", stopReason: .endTurn)
        }
        return .init(toolCalls: [.init(id: "report", name: "heartbeat_report", rawArguments: #"{"sourceId":"source-fixture","outcome":"quiet"}"#)], stopReason: .toolCalls)
    }
    nonisolated func streamStep(_ request: ModelStepRequest) -> AsyncThrowingStream<ModelStepEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.started)
                do { continuation.yield(.final(try await self.response(request))); continuation.finish() }
                catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

private struct NativeProactiveFactory: ModelProvider, ModelStepProviderFactory {
    let id = "native-proactive"
    let supportedModels = ["openai-api:gpt-5.4-mini"]
    let script: NativeProactiveScript
    func supportsModelSteps(for modelName: String) -> Bool { supportedModels.contains(modelName) }
    func createModelStepProvider(for modelName: String, usageContext: ModelUsageContext?) async throws -> (any ModelStepProvider)? { script }
    func createLanguageModel(for modelName: String) async throws -> any LanguageModel { await script.legacy(); throw CancellationError() }
}

@Suite("Native proactive work")
struct NativeProactiveWorkTests {
    @Test(.timeLimit(.minutes(10)), arguments: [false, true])
    func proactiveReportsUseTheCommonOwnerAndResumeKnownResults(startupCredentialFailure: Bool) async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        defer { Task { await service.stop() } }
        let model = "openai-api:gpt-5.4-mini"
        let script = NativeProactiveScript()
        await service.overrideModelProviderForTests(NativeProactiveFactory(script: script), defaultModel: model)
        await service.setToolApprovalPresenter { _ in .approve(.once) }
        let models = [ProviderModelOption(id: model, title: "Fixture", capabilities: ["tools"])]
        await service.sessionOrchestrator.updateAvailableModels(models)
        let agentID = "proactive-native-" + UUID().uuidString.lowercased()
        _ = try await service.createAgent(.init(id: agentID, displayName: agentID, role: "Proactive fixture"))
        let workspace = await service.workspaceRootURL
        let catalog = AgentCatalogFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
        let original = try catalog.getAgentConfig(agentID: agentID, availableModels: models)
        _ = try catalog.updateAgentConfig(agentID: agentID, request: .init(role: original.role, selectedModel: model,
            documents: original.documents, heartbeat: .init(enabled: true, mode: .proactive, proactive: .init(analysisModel: model)), automaticModelRouting: false,
            runtime: .init(sharedMemoryEnabled: false, nativeEngine: .unified, planningPolicy: .executor)), availableModels: models)
        let snapshots: [ProactiveSnapshot] = [.init(source: .init(id: "source-fixture", kind: .task, title: "Review"),
            scope: "fixture", revision: "v1", summary: "Read-only context", updatedAt: nil)]
        var batch: ProactiveAnalysisBatch?
        var failure: Error?
        do { batch = try await service.analyzeProactiveSnapshots(agentID: agentID, snapshots: snapshots, model: model) }
        catch { failure = error }
        #expect(failure == nil)
        #expect(await script.legacyCalls == 0)
        let completed = try #require(batch)
        #expect(completed.reports.count == 1)
        #expect(completed.reports.first?.outcome == .quiet)
        let files = AgentSessionFileStore(agentsRootURL: workspace.appendingPathComponent("agents"))
        let journal = try files.loadJournal(agentID: agentID, sessionID: completed.sessionID)
        let result = try #require(journal.records.first { $0.event.toolResult?.tool == "heartbeat.report" && $0.event.toolResult?.ok == true })
        let runID = try #require(result.event.runtimeMetadata?.runId)
        let url = URL(fileURLWithPath: try files.sessionFilePath(agentID: agentID, sessionID: completed.sessionID))
        let completeBytes = try Data(contentsOf: url)
        await service.stop()
        try completeBytes.prefix(Int(result.endCursor)).write(to: url)
        let fresh = CoreService(config: await service.currentConfig, persistenceBuilder: InMemoryCorePersistenceBuilder())
        defer { Task { await fresh.stop() } }
        let resumed = NativeProactiveScript()
        await resumed.setCredentialFailure(startupCredentialFailure)
        await fresh.overrideModelProviderForTests(NativeProactiveFactory(script: resumed), defaultModel: model)
        await fresh.sessionOrchestrator.updateAvailableModels(models)
        await fresh.setToolApprovalPresenter { _ in .approve(.once) }
        await fresh.waitForStartup(dispatchReadyTasks: false)
        if startupCredentialFailure {
            await fresh.nativeDerivedRecoveryTask?.value
            await resumed.setCredentialFailure(false)
        }
        let restored = try await fresh.analyzeProactiveSnapshots(agentID: agentID, snapshots: snapshots, model: model)
        #expect(restored.sessionID == completed.sessionID)
        #expect(restored.reports == completed.reports)
        let requests = await resumed.requests
        #expect(requests.count == (startupCredentialFailure ? 2 : 1))
        #expect(requests.allSatisfy { $0.runId == runID })
        #expect(requests.last?.tools.map(\.toolId) == ["heartbeat.report"])
        #expect(requests.last?.messages.compactMap(\.toolOutput).contains { $0.callId == "report" } == true)
        let final = try files.loadSession(agentID: agentID, sessionID: completed.sessionID)
        #expect(final.events.filter { $0.runtimeMetadata?.executionPhase == .started }.count == 1)
        #expect(await resumed.legacyCalls == 0)
        let saved = try #require(final.events.last { $0.runtimeMetadata?.runState != nil }?.runtimeMetadata?.runState)
        let stopped = try RunState(snapshot: JSONValueCoder.decode(RunStateSnapshot.self, from: saved))
        await stopped.cancel()
        let stoppedSnapshot = await stopped.snapshot()
        let frame = ModelStepRequest(runId: runID, userTurnId: stoppedSnapshot.userTurnID,
            stepId: "stopped", attemptId: "stopped", model: model, projectionRevision: "", cacheScope: runID,
            messages: [], tools: [], generation: stoppedSnapshot.generation)
        let stoppedJournal = SessionLoopJournal(store: files, agentID: agentID, sessionID: completed.sessionID, authorizeWriter: {})
        try await stoppedJournal.appendRunState(stoppedSnapshot, request: frame)
        await #expect(throws: ProactiveHeartbeatError.self) {
            try await fresh.analyzeProactiveSnapshots(agentID: agentID, snapshots: snapshots, model: model)
        }
        #expect(await resumed.requests.count == requests.count)
    }
}
