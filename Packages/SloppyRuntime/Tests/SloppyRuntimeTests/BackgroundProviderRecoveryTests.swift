import AgentRuntime
import PluginSDK
import Protocols
import Testing

@Suite("Background provider failure recovery")
struct BackgroundProviderRecoveryTests {
    @Test(arguments: [RunState.Phase.stopping, .settled])
    func explicitCancellationRevokesCredentialRecovery(phase: RunState.Phase) async throws {
        var stop = ToolRunStop(reason: .modelFailure, message: "Expired credentials", generation: 0)
        stop.modelFailure = .init(category: .authentication, code: "expired", message: "Expired credentials")
        let snapshot = RunStateSnapshot(runID: "run", userTurnID: "turn", phase: phase,
            requestAttempts: 2, toolRoundsUsed: 1, loopConfig: .init(engine: .unified), toolStop: stop)
        let resumed = try RunState(snapshot: snapshot)
        try await resumed.resumeAfterProviderFailure()
        let restored = await resumed.snapshot()
        #expect(restored.runID == "run" && restored.requestAttempts == 2 && restored.toolRoundsUsed == 1)
        #expect(restored.generation == 1 && restored.toolStop == nil)
        let cancelled = try RunState(snapshot: snapshot)
        await cancelled.cancel()
        #expect(await cancelled.snapshot().canResumeProviderFailure == false)
        await #expect(throws: RunStateSnapshot.ValidationError.self) { try await cancelled.resumeAfterProviderFailure() }
    }
}
