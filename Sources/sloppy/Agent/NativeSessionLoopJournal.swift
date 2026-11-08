import Foundation
import AgentRuntime
import PluginSDK
import Protocols
import SloppyRuntime

/// Rechecks the paired profile at every write, including callbacks from an older run.
struct NativeJournalWriterGuard: Sendable {
    let directory: URL

    func authorize(minimumJournalVersion: Int = 2) throws {
        // Engine selection is pinned by the run. The paired compatibility guard also
        // permits its actual outcomes to settle after a profile flag changes.
        try AgentProfileStorageCodec.verify(metadata: directory.appendingPathComponent("agent.json"),
            config: directory.appendingPathComponent("config.json"), minimumJournalVersion: minimumJournalVersion)
    }
}

/// Core refreshes its scoped instructions before every projected model step.
/// Forwarded writes retain the shared journal's synchronization and result arbitration.
struct NativeSessionLoopJournal: AgentLoopStateJournal, AgentLoopInstructionJournal, AgentLoopOutcomeJournal, AgentLoopUsageJournal, AgentLoopProjectionJournal, AgentLoopInputJournal, AgentLoopPendingToolJournal {
    let base: SessionLoopJournal
    let owner: AgentSessionOrchestrator
    let agentID: String
    let sessionID: String
    let userID: String

    func pendingToolBatch(for request: ModelStepRequest) async throws -> AgentLoopPendingTools? {
        try await base.pendingToolBatch(for: request)
    }

    func admitSteering(_ request: ModelStepRequest, state: RunState) async throws -> Bool {
        try await owner.prepareUnifiedSteeringStorage(agentID: agentID, sessionID: sessionID)
        return try await base.admitSteering(request, state: state)
    }

    func prepareRequest(_ request: ModelStepRequest) async throws -> ModelStepRequest {
        try await owner.prepareUnifiedSessionRequest(request, journal: base,
            agentID: agentID, sessionID: sessionID, userID: userID)
    }
    func appendResponse(_ response: ModelStepResponse, request: ModelStepRequest) async throws {
        try await base.appendResponse(response, request: request)
    }
    func appendResponse(_ response: ModelStepResponse, request: ModelStepRequest, usageRequest: UsageRequestRecord) async throws {
        try await base.appendResponse(response, request: request, usageRequest: usageRequest)
    }
    func appendRequested(_ calls: [AgentLoopCall], request: ModelStepRequest) async throws {
        try await base.appendRequested(calls, request: request)
    }
    func appendStarted(_ call: AgentLoopCall, request: ModelStepRequest) async throws {
        try await base.appendStarted(call, request: request)
    }
    func appendResult(_ result: ToolInvocationResult, call: AgentLoopCall, request: ModelStepRequest) async throws {
        try await base.appendResult(result, call: call, request: request)
    }
    func appendOutcome(_ outcome: AgentLoopToolOutcome, call: AgentLoopCall, request: ModelStepRequest) async throws {
        try await base.appendOutcome(outcome, call: call, request: request)
    }
    func appendRunState(_ snapshot: RunStateSnapshot, request: ModelStepRequest) async throws {
        try await base.appendRunState(snapshot, request: request)
    }
    func restoreRunState(userTurnID: String?) async throws -> RunState? {
        try await base.restoreRunState(userTurnID: userTurnID)
    }
    func appendInstruction(_ instruction: AgentRunInstruction, request: ModelStepRequest) async throws {
        try await base.appendInstruction(instruction, request: request)
    }
    func makeCompactionPlan(for request: ModelStepRequest, inputBudget: Int) async throws -> AgentLoopCompactionPlan? {
        try await owner.prepareUnifiedCompactionStorage(agentID: agentID)
        return try await base.makeCompactionPlan(for: request, inputBudget: inputBudget)
    }
    func commitCompaction(_ plan: AgentLoopCompactionPlan, summary: String,
        request: ModelStepRequest) async throws -> ModelStepRequest {
        try await owner.prepareUnifiedCompactionStorage(agentID: agentID)
        return try await base.commitCompaction(plan, summary: summary, request: request)
    }
}
