import Foundation
import PluginSDK
import Protocols

private actor ToolStartPermit {
    private(set) var started = false
    private(set) var granted = false
    private var claimed = false
    private(set) var writeFailure: (any Error)?

    func start(call: AgentLoopCall, request: ModelStepRequest, journal: any AgentLoopJournal, state: RunState, generation: Int, mutating: Bool) async throws {
        guard !claimed else { throw ModelStepFailure(category: .protocolViolation, code: "duplicate_effect_start", message: "The executor attempted to start one invocation twice.") }
        claimed = true
        try await state.checkActive(generation: generation)
        var startedCall = call
        if mutating {
            let revision = try await state.advanceWorkRevision()
            startedCall.runtimeMetadata?.workScopeRevision = revision
            // Custom callers may not supply metadata. Start provenance is still durable.
            if startedCall.runtimeMetadata == nil {
                startedCall.runtimeMetadata = .init(runId: request.runId, userTurnId: request.userTurnId)
                startedCall.runtimeMetadata?.workScopeRevision = revision
            }
        }
        do { try await journal.appendStarted(startedCall, request: request) }
        catch { writeFailure = error; throw error }
        started = true
        await state.toolStarted(id: call.eventID)
        try await state.checkActive(generation: generation)
        granted = true
    }
}

/// One durable, policy-aware boundary for every effectful native model step.
public struct ToolPipeline: Sendable {
    public let journal: any AgentLoopJournal
    public let executor: AgentLoopToolExecutor
    public let state: RunState

    public init(journal: any AgentLoopJournal, executor: AgentLoopToolExecutor, state: RunState) {
        self.journal = journal
        self.executor = executor
        self.state = state
    }

    public func execute(_ response: ModelStepResponse, request: ModelStepRequest, config: NativeAgentLoopConfig) async throws -> [ToolInvocationResult] {
        let calls = response.toolCalls.enumerated().map { index, raw in
            let eventID = UUID().uuidString
            let metadata = AgentRunMetadata(runId: request.runId, userTurnId: request.userTurnId,
                stepId: request.stepId, attemptId: request.attemptId, generation: request.generation,
                sourceOrder: index, providerCallId: raw.id, callEventId: eventID, executionPhase: .requested)
            return AgentLoopCall(eventID: eventID, sourceOrder: index, call: raw, runtimeMetadata: metadata)
        }
        try await journal.appendRequested(calls, request: request)
        return try await resume(response, request: request, config: config, calls: calls)
    }

    /// The journal supplies only original requested calls with neither a start nor a result.
    public func resume(_ response: ModelStepResponse, request: ModelStepRequest, config: NativeAgentLoopConfig,
        calls: [AgentLoopCall]) async throws -> [ToolInvocationResult] {
        let generation = await state.generation
        let segments = ToolConcurrencyPolicy.segments(count: calls.count) { index in
            guard request.parallelToolCalls,
                  let definition = request.tools.first(where: { $0.name == calls[index].call.name }) else { return false }
            return definition.readOnly && definition.concurrencySafe && ToolConcurrencyPolicy.readOnlyToolIDs.contains(definition.toolId)
        }
        var results: [(Int, ToolInvocationResult)] = []
        for segment in segments {
            if segment.count == 1, let index = segment.first {
                results.append((index, try await executeAndPersist(calls[index], response: response, request: request, config: config, generation: generation)))
            } else {
                try await withThrowingTaskGroup(of: (Int, ToolInvocationResult).self) { group in
                    for index in segment {
                        group.addTask {
                            (index, try await executeAndPersist(calls[index], response: response, request: request, config: config, generation: generation))
                        }
                    }
                    for try await result in group { results.append(result) }
                }
            }
        }
        return results.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private func executeAndPersist(_ call: AgentLoopCall, response: ModelStepResponse, request: ModelStepRequest, config: NativeAgentLoopConfig, generation: Int) async throws -> ToolInvocationResult {
        let outcome = try await execute(call, response: response, request: request, config: config, generation: generation)
        // An effect can finish after cancellation or owner generation replacement. Keep its
        // actual result, but never commit product authority from that stale invocation.
        let active: Bool
        do { try await state.checkActive(generation: generation); active = true }
        catch { active = false }
        if !active {
            try await journal.appendResult(outcome.result, call: call, request: request)
            await state.recordSettledTool(id: call.eventID, result: outcome.result)
            return outcome.result
        }
        // Validate authority before persisting it. Acceptance still waits for the durable result.
        if outcome.completion != nil {
            let declaredID = request.tools.first(where: { $0.name == call.call.name })?.toolId
            guard outcome.result.ok, let declaredID, config.finalizerToolNames.contains(declaredID) else {
                throw ModelStepFailure(category: .protocolViolation, code: "invalid_completion_source",
                    message: "Only a successful declared finalizer may provide a completion candidate.")
            }
        }
        // This is deliberately awaited even if cancellation arrived while the effect completed.
        var unsupportedAuthority = false
        if let outcomes = journal as? any AgentLoopOutcomeJournal {
            do { try await outcomes.appendOutcome(outcome, call: call, request: request) }
            catch let failure as ModelStepFailure where failure.code == "durable_outcome_journal_required" {
                // Runtime's journal adapter has already preserved the actual scalar result.
                unsupportedAuthority = true
            }
        } else {
            try await journal.appendResult(outcome.result, call: call, request: request)
            unsupportedAuthority = outcome.completion != nil || outcome.verificationEvidence?.isEmpty == false
        }
        await state.recordSettledTool(id: call.eventID, result: outcome.result)
        if unsupportedAuthority {
            // Preserve the actual result, then revoke continuation. A scalar write cannot
            // silently stand in for a durable product decision, even within this process.
            await state.cancel()
            throw ModelStepFailure(category: .unavailable, code: "durable_outcome_journal_required",
                message: "The journal cannot persist completion or verification authority.", stage: .finalization)
        }
        if let selectedMode = outcome.selectedMode {
            guard outcome.result.ok else {
                throw ModelStepFailure(category: .protocolViolation, code: "invalid_route_source", message: "A failed route cannot change turn policy.")
            }
            try await state.selectMode(selectedMode, generation: generation)
        }
        if let completion = outcome.completion {
            _ = await state.acceptCompletion(completion, generation: generation)
        }
        return outcome.result
    }

    private func execute(_ call: AgentLoopCall, response: ModelStepResponse, request: ModelStepRequest, config: NativeAgentLoopConfig, generation: Int) async throws -> AgentLoopToolOutcome {
        let nativeToolID = request.tools.first(where: { $0.name == call.call.name })?.toolId ?? call.call.name
        func rejected(_ code: String, _ message: String, data: JSONValue? = nil) -> AgentLoopToolOutcome {
            .init(result: .init(tool: nativeToolID, ok: false, data: data, error: .init(code: code, message: message, retryable: false)))
        }
        guard response.stopReason == .toolCalls else {
            return rejected("incomplete_model_response", "The response did not finish its tool batch. No call from this response was executed.")
        }
        if request.purpose == .finalAnswer {
            return rejected("tools_disallowed_during_final_answer", "The final-answer request cannot execute tools.")
        }
        do { try await state.checkActive(generation: generation) }
        catch let failure as ModelStepFailure { return rejected("not_executed_after_stop", failure.message) }
        catch { return rejected("not_executed_cancelled", "The run stopped before this invocation started.") }
        guard await state.completion == nil else {
            return rejected("not_executed_after_completion", "Completion has already been accepted for this turn.")
        }
        let matching = request.tools.filter { $0.name == call.call.name }
        guard matching.count == 1, let definition = matching.first else {
            return rejected("undeclared_tool", "The call must name exactly one tool declared in this request.")
        }
        if config.enforceToolRoundLimit, await state.toolRoundsUsed > config.maxToolRounds,
           !config.finalizerToolNames.contains(definition.toolId) {
            return rejected("tool_budget_exhausted", config.budgetExhaustedMessage)
        }
        let arguments: [String: JSONValue]
        do { arguments = try ToolArgumentValidator.arguments(call.call.rawArguments, schema: definition.parameters) }
        catch {
            return .init(result: .init(tool: nativeToolID, ok: false, error: .init(
                code: "invalid_tool_arguments", message: String(describing: error), retryable: false,
                hint: "Correct the arguments to match the declared schema before retrying.",
                argumentRecovery: .init(invalidFields: ["arguments"]))))
        }
        if request.requiresReconciliation,
           !(definition.readOnly && ToolConcurrencyPolicy.readOnlyToolIDs.contains(definition.toolId)) {
            return rejected("tool_reconciliation_required",
                "An earlier invocation has an unknown effect outcome. Inspect it and record owner reconciliation before making further changes.",
                data: .object(["requiresReconciliation": .bool(true),
                    "previousCallEventIDs": .array(request.reconciliationCallEventIDs.map(JSONValue.string))]))
        }

        let permit = ToolStartPermit()
        let outcome: AgentLoopToolOutcome
        do {
            outcome = try await executor.execute(call, definition, arguments, {
                try await permit.start(call: call, request: request, journal: journal, state: state, generation: generation,
                    mutating: !(definition.readOnly && ToolConcurrencyPolicy.readOnlyToolIDs.contains(definition.toolId)) &&
                        !config.finalizerToolNames.contains(definition.toolId) && definition.toolId != "planning.select_route")
            })
        } catch {
            if let writeFailure = await permit.writeFailure { throw writeFailure }
            let started = await permit.started
            let granted = await permit.granted
            let code: String
            if granted { code = "tool_execution_interrupted" }
            else if error is CancellationError { code = "not_executed_cancelled" }
            else if error is ModelStepFailure { code = "not_executed_after_stop" }
            else { code = started ? "tool_execution_interrupted" : "tool_execution_failed" }
            outcome = rejected(code, error.localizedDescription)
        }
        if let writeFailure = await permit.writeFailure { throw writeFailure }
        if !(await permit.started), outcome.result.ok {
            throw ModelStepFailure(category: .protocolViolation, code: "effect_start_missing",
                message: "An executor returned success without committing the invocation start.")
        }
        return outcome
    }
}
