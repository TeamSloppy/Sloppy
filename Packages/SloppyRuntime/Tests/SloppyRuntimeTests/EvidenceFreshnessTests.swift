import Foundation
import AgentRuntime
import PluginSDK
import Protocols
import Testing
@testable import SloppyRuntime

@Suite("Versioned evidence freshness")
struct EvidenceFreshnessTests {
    @Test(arguments: [1, 2])
    func mutationInvalidatesEarlierEvidenceOnlyUnderExplicitPolicy(version: Int) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fresh-evidence-\(UUID())")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        var raw = try #require(JSONValueCoder.encode(RunRequestSettings(retryDelays: [], reasoningEffort: nil)).asObject)
        raw["evidencePolicyVersion"] = .number(Double(version))
        let settings = try JSONValueCoder.decode(RunRequestSettings.self, from: .object(raw))
        let config = NativeAgentLoopConfig(finalizerToolNames: ["session.complete"], engine: .unified)
        let state = try RunState(snapshot: .init(schemaVersion: 2, runID: "run", userTurnID: "turn", loopConfig: config,
            model: "script:model", requestSettings: settings))
        let evidence = await state.recordEvidence(.init(kind: .test, tool: "runtime.exec", command: "swift test",
            arguments: [], cwd: root.path, exitCode: 0, observedAt: Date()))
        let request = ModelStepRequest(runId: "run", userTurnId: "turn", stepId: "step", attemptId: "attempt", model: "script:model",
            projectionRevision: "", cacheScope: "scope", messages: [],
            tools: [.init(name: "write", toolId: "files.write", parameters: .object(["type": .string("object")]))])
        let pipeline = ToolPipeline(journal: journal, executor: .init(execute: { _, _, _, beforeEffect in
            try await beforeEffect()
            try Data("changed".utf8).write(to: root.appendingPathComponent("changed.txt"))
            return .init(result: .init(tool: "files.write", ok: true))
        }), state: state)
        _ = try await pipeline.execute(.init(toolCalls: [.init(id: "write-1", name: "write", rawArguments: "{}")], stopReason: .toolCalls), request: request, config: config)
        let candidate = RunCompletion(disposition: .completed, summary: "Done", verification: [], verificationEvidence: [evidence], limitations: [])
        #expect(await state.acceptCompletion(candidate) == (version == 1))
        if version == 2 {
            let fresh = await state.recordEvidence(.init(kind: .test, tool: "runtime.exec", command: "swift test",
                arguments: [], cwd: root.path, exitCode: 0, observedAt: Date()))
            let reopened = try RunState(snapshot: await state.snapshot())
            #expect(await reopened.acceptCompletion(.init(disposition: .completed, summary: "Checked current revision",
                verification: [], verificationEvidence: [fresh], limitations: [])))
        }
    }

    @Test
    func unsupportedPolicyCannotResumeAsLegacy() throws {
        var settings = try #require(JSONValueCoder.encode(RunRequestSettings(retryDelays: [], reasoningEffort: nil)).asObject)
        settings["planningPolicyVersion"] = .number(99)
        let snapshot = RunStateSnapshot(schemaVersion: 2, runID: "run", userTurnID: "turn",
            requestSettings: try JSONValueCoder.decode(RunRequestSettings.self, from: .object(settings)))
        #expect(throws: (any Error).self) { try snapshot.validate() }
    }
}
