import Foundation
import PluginSDK
import Protocols

actor UnifiedLoopUsage {
    private(set) var total: TokenUsage?
    func record(_ usage: TokenUsage?) {
        guard let usage else { return }
        var value = total ?? .init(prompt: 0, completion: 0)
        value.prompt += usage.prompt; value.completion += usage.completion
        value.cachedInput += usage.cachedInput; value.cacheCreationInput += usage.cacheCreationInput; value.reasoning += usage.reasoning
        total = value
    }
}

/// The runtime bridge awaits the durable writer before mandatory usage/ledger/product observations.
struct RuntimeLoopJournal: AgentLoopStateJournal, AgentLoopInstructionJournal, AgentLoopOutcomeJournal, AgentLoopContextJournal, AgentLoopInputJournal, AgentLoopPendingToolJournal {
    let base: any AgentLoopJournal
    let runtime: RuntimeSystem
    let state: RunState
    let channelID: String
    let model: String
    let provider: any ModelProvider
    let userMessage: String
    let usage: UnifiedLoopUsage
    let observedUsage: Bool
    let observationHandler: (@Sendable (RuntimeResponseObservation) async -> Void)?
    let additionalTools: [ModelStepToolDefinition]

    func pendingToolBatch(for request: ModelStepRequest) async throws -> AgentLoopPendingTools? {
        try await (base as? any AgentLoopPendingToolJournal)?.pendingToolBatch(for: request)
    }

    func admitSteering(_ request: ModelStepRequest, state: RunState) async throws -> Bool {
        try await (base as? any AgentLoopInputJournal)?.admitSteering(request, state: state) ?? false
    }

    func appendInstruction(_ instruction: AgentRunInstruction, request: ModelStepRequest) async throws {
        guard let instructions = base as? any AgentLoopInstructionJournal else {
            throw ModelStepFailure(category: .unavailable, code: "durable_instruction_journal_required",
                message: "The session must persist recovery instructions before generation.")
        }
        try await instructions.appendInstruction(instruction, request: request)
    }

    func appendRunState(_ snapshot: RunStateSnapshot, request: ModelStepRequest) async throws {
        guard let stateJournal = base as? any AgentLoopStateJournal else {
            throw ModelStepFailure(category: .unavailable, code: "durable_state_journal_required", message: "A durable session must checkpoint turn counters before generation.")
        }
        try await stateJournal.appendRunState(snapshot, request: request)
        await runtime.recordUnifiedRecovery(snapshot, channelID: channelID)
    }
    func restoreRunState(userTurnID: String?) async throws -> RunState? {
        guard let stateJournal = base as? any AgentLoopStateJournal else { return nil }
        return try await stateJournal.restoreRunState(userTurnID: userTurnID)
    }

    func prepareRequest(_ request: ModelStepRequest) async throws -> ModelStepRequest {
        let projected = try await base.prepareRequest(request)
        return try await runtime.prepareUnifiedFrame(projected, channelID: channelID, model: model, provider: provider,
            userMessage: userMessage, additionalTools: additionalTools)
    }

    func compactContext(_ request: ModelStepRequest, inputBudget: Int) async throws -> ModelStepRequest? {
        guard let projection = base as? any AgentLoopProjectionJournal,
              let plan = try await projection.makeCompactionPlan(for: request, inputBudget: inputBudget) else { return nil }
        let summary = try await runtime.generateAgentLoopContextSummary(history: plan.history, model: model,
            channelID: channelID, state: state, journal: base)
        try await state.checkActive(generation: request.generation)
        return try await projection.commitCompaction(plan, summary: summary.text, request: request)
    }
    func appendResponse(_ response: ModelStepResponse, request: ModelStepRequest) async throws {
        if !observedUsage, let reported = response.usage {
            guard let accounting = base as? any AgentLoopUsageJournal else {
                // Keep the complete response before stopping an unsupported host. No tool
                // may execute after this capability failure.
                try await base.appendResponse(response, request: request)
                throw ModelStepFailure(category: .unavailable, code: "durable_usage_journal_required",
                    message: "Usage persistence is unavailable for this session.", stage: .finalization)
            }
            let record = UsageRequestRecord(id: try UsageRequestRecord.nativeIdentifier(channelId: channelID, runId: request.runId,
                userTurnId: request.userTurnId, stepId: request.stepId, attemptId: request.attemptId),
                channelId: channelID, provider: model.split(separator: ":").first.map(String.init) ?? provider.id,
                model: model, createdAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)),
                usage: reported, complete: false, runId: request.runId, userTurnId: request.userTurnId)
            try await accounting.appendResponse(response, request: request, usageRequest: record)
        } else {
            try await base.appendResponse(response, request: request)
        }
        await runtime.recordUnifiedResponse(response, channelID: channelID, usage: usage, observed: observedUsage)
    }
    func appendRequested(_ calls: [AgentLoopCall], request: ModelStepRequest) async throws {
        try await base.appendRequested(calls, request: request)
        for call in calls { await runtime.recordUnifiedCall(call, request: request, channelID: channelID, model: model, handler: observationHandler) }
    }
    func appendStarted(_ call: AgentLoopCall, request: ModelStepRequest) async throws {
        try await base.appendStarted(call, request: request)
    }
    func appendResult(_ result: ToolInvocationResult, call: AgentLoopCall, request: ModelStepRequest) async throws {
        try await base.appendResult(result, call: call, request: request)
        await runtime.recordUnifiedResult(result, call: call, request: request, channelID: channelID, handler: observationHandler)
    }
    func appendOutcome(_ outcome: AgentLoopToolOutcome, call: AgentLoopCall, request: ModelStepRequest) async throws {
        var unsupportedAuthority = false
        if let outcomes = base as? any AgentLoopOutcomeJournal {
            try await outcomes.appendOutcome(outcome, call: call, request: request)
        } else {
            try await base.appendResult(outcome.result, call: call, request: request)
            unsupportedAuthority = outcome.completion != nil || outcome.verificationEvidence?.isEmpty == false
        }
        await runtime.recordUnifiedResult(outcome.result, call: call, request: request, channelID: channelID, handler: observationHandler)
        if unsupportedAuthority {
            throw ModelStepFailure(category: .unavailable, code: "durable_outcome_journal_required",
                message: "The session cannot persist completion or verification authority.", stage: .finalization)
        }
    }
}
