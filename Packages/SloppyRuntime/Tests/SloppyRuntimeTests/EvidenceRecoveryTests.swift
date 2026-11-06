import Foundation
import AgentRuntime
import PluginSDK
import Protocols
import Testing
@testable import SloppyRuntime

@Suite("Evidence revision recovery")
struct EvidenceRecoveryTests {
    @Test(arguments: [false, true])
    func onlyKnownSafeReadsKeepTheVerificationRevision(unknown: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("evidence-read-\(UUID())")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        let state = RunState(runID: "run", userTurnID: "turn")
        let definition = ModelStepToolDefinition(name: "inspect", toolId: unknown ? "mcp.unknown.inspect" : "files.read",
            parameters: .object(["type": .string("object")]), readOnly: true)
        let request = ModelStepRequest(runId: "run", userTurnId: "turn", stepId: "step", attemptId: "attempt", model: "script:model",
            projectionRevision: "", cacheScope: "scope", messages: [], tools: [definition])
        let pipeline = ToolPipeline(journal: journal, executor: .init(execute: { _, definition, _, start in
            try await start()
            return .init(result: .init(tool: definition.toolId, ok: true, data: .string("Observed")))
        }), state: state)
        _ = try await pipeline.execute(.init(toolCalls: [.init(id: "read", name: "inspect", rawArguments: "{}")], stopReason: .toolCalls),
            request: request, config: .init(engine: .unified))
        #expect(await state.workScopeRevision == (unknown ? 1 : 0))
    }

    @Test
    func startTailInvalidatesEvidenceEvenWithoutANewerSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("evidence-tail-\(UUID())")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("agent"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AgentSessionFileStore(agentsRootURL: root)
        let session = try store.createSession(agentID: "agent", request: .init())
        let journal = SessionLoopJournal(store: store, agentID: "agent", sessionID: session.id, authorizeWriter: {})
        var settings = RunRequestSettings(retryDelays: [], reasoningEffort: nil)
        settings.evidencePolicyVersion = 2
        let config = NativeAgentLoopConfig(engine: .unified)
        let state = try RunState(snapshot: .init(schemaVersion: 2, runID: "run", userTurnID: "turn", loopConfig: config,
            model: "script:model", requestSettings: settings))
        let evidence = await state.recordEvidence(.init(kind: .test, tool: "runtime.exec", command: "swift test", arguments: [],
            cwd: root.path, exitCode: 0, observedAt: Date()))
        let request = ModelStepRequest(runId: "run", userTurnId: "turn", stepId: "step", attemptId: "attempt", model: "script:model",
            projectionRevision: "", cacheScope: "scope", messages: [], tools: [.init(name: "write", toolId: "files.write", parameters: .object(["type": .string("object")]))])
        try await journal.appendRunState(await state.snapshot(), request: request)
        let pipeline = ToolPipeline(journal: journal, executor: .init(execute: { _, _, _, start in
            try await start()
            try Data("changed".utf8).write(to: root.appendingPathComponent("changed.txt"))
            return .init(result: .init(tool: "files.write", ok: true))
        }), state: state)
        _ = try await pipeline.execute(.init(toolCalls: [.init(id: "write", name: "write", rawArguments: "{}")], stopReason: .toolCalls), request: request, config: config)
        let fresh = SessionLoopJournal(store: AgentSessionFileStore(agentsRootURL: root), agentID: "agent", sessionID: session.id, authorizeWriter: {})
        let restored = try #require(try await fresh.restoreRunState(userTurnID: "turn"))
        #expect(await restored.workScopeRevision == 1)
        #expect(!(await restored.acceptCompletion(.init(disposition: .completed, summary: "Stale check", verification: [],
            verificationEvidence: [evidence], limitations: []))))
    }
}
