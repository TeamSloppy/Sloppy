import Foundation
import AnyLanguageModel
import AgentRuntime
import PluginSDK
import Protocols
import Testing
@testable import SloppyRuntime

private actor AuxiliaryRetryScript: ModelStepProvider {
    private(set) var requests: [ModelStepRequest] = []
    func response(_ request: ModelStepRequest) throws -> ModelStepResponse {
        requests.append(request)
        if requests.count == 1 {
            throw ModelStepFailure(category: .transport, code: "fixture_connection_lost", message: "Transient fixture failure", retryable: true)
        }
        return .init(text: "Bounded auxiliary result", stopReason: .endTurn)
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

private struct AuxiliaryRetryFactory: ModelProvider, ModelStepProviderFactory {
    let id = "auxiliary-fixture"
    let supportedModels = ["script:model"]
    let script: AuxiliaryRetryScript
    func supportsModelSteps(for modelName: String) -> Bool { supportedModels.contains(modelName) }
    func createModelStepProvider(for modelName: String, usageContext: ModelUsageContext?) async throws -> (any ModelStepProvider)? { script }
    func createLanguageModel(for modelName: String) async throws -> any LanguageModel { throw CancellationError() }
}

@Suite("Auxiliary request recovery")
struct AuxiliaryRecoveryTests {
    @Test(arguments: [ModelStepPurpose.planning, .compaction, .reportReview])
    func transientFailureSpendsParentBudgetAndPersistsTheSuccessfulAttempt(purpose: ModelStepPurpose) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("auxiliary-retry-\(UUID())")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        let settings = RunRequestSettings(retryDelays: [.zero], reasoningEffort: nil)
        let state = try RunState(snapshot: .init(schemaVersion: 2, runID: "parent", userTurnID: "turn",
            loopConfig: .init(engine: .unified), model: "script:model", requestSettings: settings))
        let script = AuxiliaryRetryScript()
        let runtime = RuntimeSystem(modelProvider: AuxiliaryRetryFactory(script: script), defaultModel: "script:model", modelReconnectDelays: [.zero])
        var failure: Error?
        do {
            switch purpose {
            case .planning: _ = try await runtime.generateAgentLoopPlan(prompt: "Plan", model: "script:model", channelID: "channel", state: state, journal: journal)
            case .compaction: _ = try await runtime.generateAgentLoopContextSummary(history: "Historical data", model: "script:model", channelID: "channel", state: state, journal: journal)
            default: _ = try await runtime.generateAgentLoopReportReview(prompt: "Review", model: "script:model", channelID: "channel", state: state, journal: journal, stepID: "review")
            }
        } catch { failure = error }
        #expect(failure == nil)
        let requests = await script.requests
        #expect(requests.count == 2)
        #expect(Set(requests.map(\.runId)) == [state.runID])
        #expect(Set(requests.map(\.stepId)).count == 1)
        #expect(Set(requests.map(\.attemptId)).count == 2)
        #expect(requests.allSatisfy { $0.tools.isEmpty && $0.purpose == purpose })
        let terminal = await state.snapshot()
        #expect(terminal.requestAttempts == 2)
        #expect(terminal.completion == nil)
        #expect(terminal.phase != .settled)
        let response = try store.loadSession(agentID: "agent", sessionID: session.id).events.last { $0.runtimeMetadata?.modelResponse != nil }
        #expect(response?.runtimeMetadata?.attemptId == requests.last?.attemptId)
    }
}
