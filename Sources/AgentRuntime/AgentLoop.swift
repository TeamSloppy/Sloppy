import Foundation
import PluginSDK
import Protocols

/// The request boundary shared by native loop consumers. A final delta is never an executable response.
public struct AgentLoop: Sendable {
    public let provider: any ModelStepProvider
    public let state: RunState
    public let retryDelays: [Duration]
    public let contextLimits: ModelContextLimits?
    public let retrySleeper: @Sendable (Duration) async throws -> Void

    public init(provider: any ModelStepProvider, state: RunState,
                retryDelays: [Duration] = [.seconds(5), .seconds(7), .seconds(9), .seconds(10), .seconds(12)],
                retrySleeper: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.init(provider: provider, state: state, retryDelays: retryDelays,
            contextLimits: nil, retrySleeper: retrySleeper)
    }

    public init(provider: any ModelStepProvider, state: RunState,
                retryDelays: [Duration] = [.seconds(5), .seconds(7), .seconds(9), .seconds(10), .seconds(12)],
                contextLimits: ModelContextLimits?,
                retrySleeper: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.provider = provider
        self.state = state
        self.retryDelays = retryDelays
        self.contextLimits = contextLimits
        self.retrySleeper = retrySleeper
    }

    public func run(
        _ request: ModelStepRequest,
        journal: any AgentLoopJournal,
        executor: AgentLoopToolExecutor,
        config: NativeAgentLoopConfig = .init(engine: .unified),
        completionPolicy: (@Sendable (ModelStepResponse, ModelStepRequest) async throws -> AgentLoopCompletionDecision)? = nil,
        onText: (@Sendable (String) async -> Bool)? = nil,
        onReasoning: (@Sendable (String) async -> Void)? = nil
    ) async throws -> ModelStepResponse {
        do {
            // An already-cancelled caller cannot grant a fresh unstructured task any authority.
            try Task.checkCancellation()
            return try await awaitOwned(allowSettledCompletion: true) {
                try await executeRun(request, journal: journal, executor: executor, config: config, completionPolicy: completionPolicy, onText: onText, onReasoning: onReasoning)
            }
        } catch {
            let phase = await state.phase
            let cancelled = Task.isCancelled || (error as? ModelStepFailure)?.category == .cancelled ||
                (error is CancellationError && phase != .settled)
            if cancelled || phase == .stopping {
                if cancelled, phase != .stopping { await state.cancel() }
                // Settlement is awaited even in the cancelled caller. A failed checkpoint is a storage
                // failure, never a successful durable cancellation acknowledgement.
                var frame = request
                frame.runId = state.runID
                frame.userTurnId = state.userTurnID
                frame.generation = await state.generation
                try await persistState(journal: journal, request: frame)
            }
            throw error
        }
    }

    private func executeRun(
        _ request: ModelStepRequest, journal: any AgentLoopJournal,
        executor: AgentLoopToolExecutor, config: NativeAgentLoopConfig,
        completionPolicy: (@Sendable (ModelStepResponse, ModelStepRequest) async throws -> AgentLoopCompletionDecision)?,
        onText: (@Sendable (String) async -> Bool)?, onReasoning: (@Sendable (String) async -> Void)?
    ) async throws -> ModelStepResponse {
        if await state.phase == .stopping { try await state.checkActive(generation: state.generation) }
        if let completion = await state.completion {
            await state.markSettled()
            var frame = request
            frame.runId = state.runID
            frame.userTurnId = state.userTurnID
            frame.generation = await state.generation
            try await persistState(journal: journal, request: frame)
            try await state.checkTerminalDelivery(generation: frame.generation)
            return .init(text: completion.summary, stopReason: .endTurn)
        }
        var next = request
        try await state.bindModel(request.model)
        let settings = try await state.bindRequestSettings(.init(retryDelays: retryDelays, reasoningEffort: request.reasoningEffort))
        next.reasoningEffort = settings.reasoningEffort
        let generation = await state.generation
        next.runId = state.runID
        next.userTurnId = state.userTurnID
        next.generation = generation
        next.stepId = UUID().uuidString
        next.attemptId = UUID().uuidString
        var config = await state.bindLoopConfig(config)
        next.purpose = await state.requestPurpose
        next.maximumOutputTokens = min(next.maximumOutputTokens, config.maxOutputTokens)
        let pipeline = ToolPipeline(journal: journal, executor: executor, state: state)
        var checkedPendingTools = false
        while true {
            try await state.checkActive(generation: generation)
            var prepared = try await journal.prepareRequest(next)
            if let scope = settings.toolScope {
                prepared.tools = prepared.tools.filter { scope.contains($0.toolId) }
            }
            prepared.reasoningEffort = next.reasoningEffort
            // A loadout refresh may narrow authority, but cannot reopen a final-answer step.
            prepared.purpose = next.purpose
            if next.purpose == .finalAnswer {
                prepared.tools = []
            }
            let pending: AgentLoopPendingTools?
            if !checkedPendingTools, let recovery = journal as? any AgentLoopPendingToolJournal {
                pending = try await recovery.pendingToolBatch(for: prepared)
            } else { pending = nil }
            checkedPendingTools = true
            let settledRequest: ModelStepRequest
            let response: ModelStepResponse
            if let pending {
                settledRequest = pending.request; response = pending.response
                _ = try await pipeline.resume(response, request: settledRequest, config: config, calls: pending.calls)
                config = await state.snapshot().loopConfig ?? config
            } else {
                if next.purpose != .finalAnswer, config.enforceToolRoundLimit, await state.toolRoundsUsed >= config.maxToolRounds {
                    prepared.tools = prepared.tools.filter { config.finalizerToolNames.contains($0.toolId) }
                }
                (settledRequest, response) = try await requestWithRecovery(prepared, journal: journal, generation: generation, onText: onText, onReasoning: onReasoning)
                // The complete assistant response is durable before validation or tool preflight.
                try await journal.appendResponse(response, request: settledRequest)
                if !response.toolCalls.isEmpty {
                    await state.recordToolBatch(toolNames: response.toolCalls.map { call in
                        prepared.tools.first(where: { $0.name == call.name })?.toolId ?? call.name
                    }, config: config)
                    try await persistState(journal: journal, request: settledRequest)
                    _ = try await pipeline.execute(response, request: settledRequest, config: config)
                    config = await state.snapshot().loopConfig ?? config
                }
            }
            if response.stopReason == .endTurn || response.stopReason == .toolCalls {
                await state.clearContextRecovery()
            }
            try await persistState(journal: journal, request: settledRequest)
            try await state.checkActive(generation: generation)
            if let completion = await state.completion {
                // A validated, durably committed finalizer already contains a user-facing answer.
                await state.markSettled()
                try await persistState(journal: journal, request: settledRequest)
                try await state.checkTerminalDelivery(generation: generation)
                return .init(text: completion.summary, stopReason: .endTurn)
            }
            let steering = try await (journal as? any AgentLoopInputJournal)?.admitSteering(settledRequest, state: state) ?? false
            guard response.stopReason == .endTurn || response.stopReason == .toolCalls else {
                throw ModelStepFailure(category: .provider, code: "incomplete_model_response",
                    message: "The model did not return a complete response.", stage: .finalization)
            }
            if !response.toolCalls.isEmpty, response.stopReason != .toolCalls {
                throw violation("inconsistent_step_final", "An end-turn response cannot contain a tool batch.")
            }
            if response.toolCalls.isEmpty && !steering {
                guard response.stopReason == .endTurn else { throw violation("missing_tool_calls", "A tool response contained no calls.") }
                var finalResponse = response
                let decision: AgentLoopCompletionPolicy.Decision
                if let custom = try await completionPolicy?(response, settledRequest) {
                    switch custom {
                    case .finish(let reviewed): finalResponse = reviewed; decision = .finish
                    case .recover(let reason, let limit, let instruction):
                        decision = .recover(reason, limit, .completionRecovery, instruction)
                    }
                } else {
                    decision = AgentLoopCompletionPolicy.afterEnd(response, purpose: settledRequest.purpose,
                        config: config, hadTools: await state.toolRoundsUsed > 0)
                }
                switch decision {
                case .finish:
                    await state.markSettled()
                    try await persistState(journal: journal, request: settledRequest)
                    try await state.checkTerminalDelivery(generation: generation)
                    return finalResponse
                case .recover(let reason, let limit, let purpose, let instruction):
                    guard let instructions = journal as? any AgentLoopInstructionJournal else {
                        throw ModelStepFailure(category: .unavailable, code: "durable_instruction_journal_required",
                            message: "Recovery requires a durable, scoped runtime instruction.", stage: .preparation)
                    }
                    guard await state.reserveRecovery(for: reason, limit: limit) != nil else {
                        let stop: ToolRunStop.Reason = reason == .emptyFinal ? .emptyFinal : .missingCompletion
                        await state.stop(reason: stop, message: reason == .missingCompletion
                            ? "The model exhausted this turn's required-completion recovery attempts."
                            : "The model did not produce a final answer within this turn's recovery limit.")
                        try await persistState(journal: journal, request: settledRequest)
                        try await state.checkActive(generation: generation)
                        throw CancellationError()
                    }
                    next.purpose = purpose
                    await state.setRequestPurpose(purpose)
                    try await persistState(journal: journal, request: settledRequest)
                    try await instructions.appendInstruction(instruction, request: settledRequest)
                }
            } else {
                next.purpose = .work
                await state.setRequestPurpose(.work)
            }
            if await state.hitToolRoundLimit {
                throw ModelStepFailure(category: .unavailable, code: "tool_budget_exhausted", message: config.budgetExhaustedMessage)
            }
            next.stepId = UUID().uuidString
            next.attemptId = UUID().uuidString
        }
    }

    private func requestWithRecovery(_ request: ModelStepRequest, journal: any AgentLoopJournal, generation: Int,
        onText: (@Sendable (String) async -> Bool)?, onReasoning: (@Sendable (String) async -> Void)?
    ) async throws -> (ModelStepRequest, ModelStepResponse) {
        let stateJournal = journal as? any AgentLoopStateJournal
        // Transport retries retain the frozen projection. Only typed context recovery may replace it.
        var attempt = try await prepareBoundRequest(request, journal: stateJournal)
        let settings = await state.requestSettings
        let retryDelays = try settings?.transportRetryDelays() ?? self.retryDelays
        let policy = RecoveryPolicy(retryDelays: retryDelays)
        while true {
            try await state.checkActive(generation: generation)
            do { return (attempt, try await consumeBoundStep(attempt, journal: stateJournal, onText: onText, onReasoning: onReasoning)) }
            catch let failure as ModelStepFailure {
                if failure.category == .context, let contextLimits,
                   let compacted = try await recoverContext(attempt, journal: stateJournal, limits: contextLimits) {
                    attempt = compacted
                    attempt.attemptId = UUID().uuidString
                    continue
                }
                let used = await state.recoveryCount(for: .transportLoss)
                guard case .retryRequest(let delay) = policy.decision(for: failure, usedAttempts: used),
                      await state.reserveRecovery(for: .transportLoss, limit: retryDelays.count) != nil else { throw failure }
                try await persistState(journal: journal, request: attempt)
                try await retrySleeper(delay)
                try await state.checkActive(generation: generation)
                attempt.attemptId = UUID().uuidString
            }
        }
    }

    public func collectStep(
        _ request: ModelStepRequest,
        journal: (any AgentLoopStateJournal)? = nil,
        onText: (@Sendable (String) async -> Bool)? = nil,
        onReasoning: (@Sendable (String) async -> Void)? = nil
    ) async throws -> ModelStepResponse {
        do {
            return try await collectBoundStep(request, journal: journal, onText: onText, onReasoning: onReasoning)
        } catch is CancellationError {
            // Cancellation can win in the run-generation guard before the adapter's
            // normalized network failure arrives. Keep the public step boundary typed.
            throw ModelStepFailure(category: .cancelled, code: "request_cancelled",
                message: "The model request was cancelled.", stage: .streaming)
        }
    }

    /// Auxiliary generations share the parent's recovery budget without settling its
    /// completion or executing tools. Return the actual frame for durable attribution.
    public func collectStepWithRecovery(_ request: ModelStepRequest, journal: any AgentLoopStateJournal) async throws
        -> (request: ModelStepRequest, response: ModelStepResponse) {
        do {
            let generation = await state.generation
            try await state.checkActive(generation: generation)
            let (settled, response) = try await requestWithRecovery(request, journal: journal, generation: generation,
                onText: nil, onReasoning: nil)
            return (settled, response)
        } catch is CancellationError {
            throw ModelStepFailure(category: .cancelled, code: "request_cancelled", message: "The auxiliary request was cancelled.")
        }
    }

    private func collectBoundStep(_ request: ModelStepRequest, journal: (any AgentLoopStateJournal)?,
        onText: (@Sendable (String) async -> Bool)?, onReasoning: (@Sendable (String) async -> Void)?
    ) async throws -> ModelStepResponse {
        let prepared = try await prepareBoundRequest(request, journal: journal)
        return try await consumeBoundStep(prepared, journal: journal, onText: onText, onReasoning: onReasoning)
    }

    private func prepareBoundRequest(_ request: ModelStepRequest, journal: (any AgentLoopStateJournal)?) async throws -> ModelStepRequest {
        let settings = try await state.bindRequestSettings(.init(retryDelays: retryDelays, reasoningEffort: request.reasoningEffort))
        var prepared = request
        if request.purpose != .planning && request.purpose != .reportReview && request.purpose != .compaction {
            prepared.reasoningEffort = settings.reasoningEffort
        }
        if let contextLimits {
            do { try ModelStepContextBudget.validate(prepared, limits: contextLimits) }
            catch {
                guard let compacted = try await recoverContext(prepared, journal: journal, limits: contextLimits) else { throw error }
                prepared = compacted
            }
        }
        // Compaction may take a long time. Freeze any steering that arrived during preparation
        // before beginning this request; transport retries retain that exact projection.
        return try await freezePreparedInputs(prepared, journal: journal)
    }

    private func freezePreparedInputs(_ request: ModelStepRequest, journal: (any AgentLoopStateJournal)?) async throws -> ModelStepRequest {
        guard let journal, let inputs = journal as? any AgentLoopInputJournal,
              try await inputs.admitSteering(request, state: state) else { return request }
        var prepared = try await journal.prepareRequest(request)
        let snapshot = await state.snapshot()
        if let scope = snapshot.requestSettings?.toolScope {
            prepared.tools = prepared.tools.filter { scope.contains($0.toolId) }
        }
        prepared.purpose = request.purpose
        prepared.reasoningEffort = request.reasoningEffort
        prepared.maximumOutputTokens = min(prepared.maximumOutputTokens, request.maximumOutputTokens)
        if request.purpose == .finalAnswer { prepared.tools = [] }
        else if let config = snapshot.loopConfig, config.enforceToolRoundLimit, snapshot.toolRoundsUsed >= config.maxToolRounds {
            prepared.tools = prepared.tools.filter { config.finalizerToolNames.contains($0.toolId) }
        }
        if let contextLimits { try ModelStepContextBudget.validate(prepared, limits: contextLimits) }
        return prepared
    }

    private func recoverContext(_ request: ModelStepRequest, journal: (any AgentLoopStateJournal)?,
        limits: ModelContextLimits) async throws -> ModelStepRequest? {
        guard request.purpose != .compaction,
              let context = journal as? any AgentLoopContextJournal,
              await state.reserveRecovery(for: .contextOverflow, limit: 1) != nil else { return nil }
        // Persist the allowance before any auxiliary generation or projection mutation.
        if let journal { try await journal.appendRunState(await state.snapshot(), request: request) }
        guard let compacted = try await context.compactContext(request,
            inputBudget: limits.inputBudget(reserving: request.maximumOutputTokens)) else { return nil }
        try await state.checkActive(generation: request.generation)
        try ModelStepContextBudget.validate(compacted, limits: limits)
        return try await freezePreparedInputs(compacted, journal: journal)
    }

    private func consumeBoundStep(_ frozen: ModelStepRequest, journal: (any AgentLoopStateJournal)?,
        onText: (@Sendable (String) async -> Bool)?, onReasoning: (@Sendable (String) async -> Void)?
    ) async throws -> ModelStepResponse {
        try await state.beginRequest()
        if let journal { try await journal.appendRunState(await state.snapshot(), request: frozen) }
        let generation = await state.generation
        return try await awaitOwned {
            try await consumeStep(frozen, generation: generation, onText: onText, onReasoning: onReasoning)
        }
    }

    private func persistState(journal: any AgentLoopJournal, request: ModelStepRequest) async throws {
        if let journal = journal as? any AgentLoopStateJournal {
            try await journal.appendRunState(await state.snapshot(), request: request)
        }
    }

    private func awaitOwned(allowSettledCompletion: Bool = false,
        _ body: @escaping @Sendable () async throws -> ModelStepResponse) async throws -> ModelStepResponse {
        let id = UUID().uuidString
        let start = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingOldest(1))
        let operation = Task {
            for await _ in start.stream { break }
            try Task.checkCancellation()
            return try await body()
        }
        await state.registerCancellation(id: id, allowSettledCompletion: allowSettledCompletion, cancel: { operation.cancel() })
        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                start.continuation.yield(())
                start.continuation.finish()
                let response = try await operation.value
                await state.unregisterCancellation(id: id)
                return response
            } catch {
                operation.cancel()
                start.continuation.finish()
                await state.unregisterCancellation(id: id)
                throw error
            }
        } onCancel: {
            operation.cancel()
            start.continuation.finish()
        }
    }

    private func consumeStep(
        _ request: ModelStepRequest, generation: Int,
        onText: (@Sendable (String) async -> Bool)?, onReasoning: (@Sendable (String) async -> Void)?
    ) async throws -> ModelStepResponse {
        try await state.checkActive(generation: generation)
        var started = false
        var final: ModelStepResponse?
        var text = ""
        for try await event in provider.streamStep(request) {
            try await state.checkActive(generation: generation)
            guard final == nil else { throw violation("events_after_final", "Provider emitted events after its final response.") }
            switch event {
            case .started:
                guard !started else { throw violation("duplicate_step_start", "Provider started the same request twice.") }
                started = true
            case .textDelta(let delta):
                guard started else { throw violation("step_not_started", "Provider emitted a delta before request start.") }
                text += delta
                await state.recordChunk(content: text)
                if let onText, !(await onText(text)) {
                    await state.markCancelledByConsumer()
                    throw ModelStepFailure(category: .cancelled, code: "consumer_cancelled", message: "Response consumer cancelled the run.")
                }
            case .reasoningDelta(let delta):
                guard started else { throw violation("step_not_started", "Provider emitted reasoning before request start.") }
                await onReasoning?(delta)
            case .toolCallDelta:
                guard started else { throw violation("step_not_started", "Provider emitted a tool delta before request start.") }
            case .final(let response):
                guard started else { throw violation("step_not_started", "Provider finalized a request that never started.") }
                final = response
            }
        }
        try await state.checkActive(generation: generation)
        guard let final else { throw violation("missing_step_final", "Provider closed without a complete final response.") }
        let callIDs = final.toolCalls.map(\.id)
        guard callIDs.allSatisfy({ !$0.isEmpty }), Set(callIDs).count == callIDs.count else {
            throw violation("invalid_tool_call_ids", "Provider tool call IDs must be nonempty and unique within a response.")
        }
        if final.text != text {
            await state.recordChunk(content: final.text)
            if let onText, !(await onText(final.text)) {
                await state.markCancelledByConsumer()
                throw ModelStepFailure(category: .cancelled, code: "consumer_cancelled", message: "Response consumer cancelled the run.")
            }
        }
        return final
    }

    private func violation(_ code: String, _ message: String) -> ModelStepFailure {
        .init(category: .protocolViolation, code: code, message: message, stage: .streaming)
    }
}
