import Foundation
import AnyLanguageModel
import PluginSDK
import Protocols

/// State belongs to the user turn, including its recovery continuations.
/// Transport attempts may reset presentation samples, never the work budget or recorded failures.
public actor RunState {
    public enum Phase: String, Sendable, Codable {
        case preparing, requesting, executing, waitingApproval, recovering, finalizing, stopping, settled
    }

    public nonisolated let runID: String
    public nonisolated let userTurnID: String
    public private(set) var phase: Phase = .preparing
    public private(set) var requestAttempts = 0
    public private(set) var generation = 0
    private var cancellationHandlers: [String: @Sendable () -> Void] = [:]
    public private(set) var completion: RunCompletion?
    public private(set) var verificationEvidence: [VerificationEvidence] = []
    public private(set) var workScopeRevision = 0

    public func advanceWorkRevision() throws -> Int {
        guard workScopeRevision < Int.max else { throw RunStateSnapshot.ValidationError.invalidSnapshot }
        workScopeRevision += 1
        return workScopeRevision
    }

    public func restoreWorkRevision(_ revision: Int) throws {
        guard revision >= 0 else { throw RunStateSnapshot.ValidationError.invalidSnapshot }
        workScopeRevision = max(workScopeRevision, revision)
    }

    /// Evidence identifiers are assigned atomically, including concurrent observations.
    public func recordEvidence(_ evidence: VerificationEvidence) -> VerificationEvidence {
        var recorded = evidence
        recorded.id = "verification-\(verificationEvidence.count + 1)"
        if recorded.workScopeRevision == nil { recorded.workScopeRevision = workScopeRevision }
        verificationEvidence.append(recorded)
        return recorded
    }

    /// Product policy validates first. The first accepted record owns the terminal disposition.
    public func acceptCompletion(_ record: RunCompletion, generation expected: Int? = nil) -> Bool {
        guard !Task.isCancelled, completion == nil, !hitToolRoundLimit, phase != .stopping, phase != .settled,
              expected == nil || expected == generation else { return false }
        if requestSettings?.evidencePolicyVersion == 2, record.disposition == .completed,
           !record.verificationEvidence.isEmpty {
            guard record.verificationEvidence.allSatisfy({ evidence in
                evidence.workScopeRevision == workScopeRevision && verificationEvidence.contains(evidence)
            }) else { return false }
        }
        completion = record
        phase = .finalizing
        return true
    }

    public init(runID: String = UUID().uuidString, userTurnID: String = UUID().uuidString) {
        self.runID = runID
        self.userTurnID = userTurnID
    }

    public func cancel() {
        if phase != .stopping || (toolStop?.reason == .modelFailure && toolStop?.generation == generation) {
            generation += 1
            phase = .stopping
        }
        let handlers = Array(cancellationHandlers.values)
        cancellationHandlers.removeAll()
        for cancel in handlers { cancel() }
    }

    func registerCancellation(id: String, allowSettledCompletion: Bool = false, cancel: @escaping @Sendable () -> Void) {
        if phase == .stopping || (phase == .settled && !(allowSettledCompletion && completion != nil)) { cancel() }
        else { cancellationHandlers[id] = cancel }
    }

    func unregisterCancellation(id: String) { cancellationHandlers.removeValue(forKey: id) }

    func checkActive(generation expected: Int) throws {
        try Task.checkCancellation()
        guard generation == expected else { throw CancellationError() }
        if let toolStop, toolStop.generation == generation { throw toolStop.failure }
        if hitToolRoundLimit {
            throw ModelStepFailure(category: .unavailable, code: "tool_budget_exhausted",
                message: pinnedLoopConfig?.budgetExhaustedMessage ?? "The turn exhausted its tool budget.", stage: .finalization)
        }
        guard phase != .stopping, phase != .settled else { throw CancellationError() }
    }

    func beginRequest() throws {
        try checkActive(generation: generation)
        requestAttempts += 1
        phase = .requesting
        latestContent = ""
        chunks = 0
        toolTranscriptEntries = []
        firstChunkAt = nil
        previousChunkAt = nil
        totalDeltaIntervalMs = 0
        maxDeltaIntervalMs = 0
        measuredDeltaIntervals = 0
        totalToolDurationMs = 0
        finishedToolCalls = 0
        toolCallCount = 0
        toolBatchCount = 0
        maxParallelToolCalls = activeToolCalls
        failedToolCalls = 0
        lastActivityAt = Date()
    }
    var lastActivityAt: Date = .init()
    var activeToolCalls: Int = 0
    private(set) var latestContent: String = ""
    private(set) var chunks: Int = 0
    private(set) var wasCancelledByConsumer: Bool = false
    private(set) var sawToolTimeout: Bool = false
    private(set) var toolRoundsUsed: Int = 0
    private(set) var hitToolRoundLimit: Bool = false
    private(set) var toolLoopStopMessage: String?
    var toolErrors: [ToolInvocationResult] = []
    private(set) var toolTranscriptEntries: [Transcript.Entry] = []
    private var firstChunkAt: Date?
    private var previousChunkAt: Date?
    private var totalDeltaIntervalMs = 0
    private var maxDeltaIntervalMs = 0
    private var measuredDeltaIntervals = 0
    private var toolStartedAt: [String: Date] = [:]
    private var totalToolDurationMs = 0
    private var finishedToolCalls = 0
    private var toolCallCount = 0
    private var toolBatchCount = 0
    private var maxParallelToolCalls = 0
    private var failedToolCalls = 0

    func recordExecuted(_ call: Transcript.ToolCall, _ output: Transcript.ToolOutput) {
        toolTranscriptEntries.append(.toolCalls(Transcript.ToolCalls([call])))
        toolTranscriptEntries.append(.toolOutput(output))
    }

    func touch() {
        lastActivityAt = Date()
    }

    func recordChunk(content: String) {
        guard toolLoopStopMessage == nil else { return }
        let now = Date()
        if firstChunkAt == nil {
            firstChunkAt = now
        }
        if let previousChunkAt {
            let interval = max(0, Int((now.timeIntervalSince(previousChunkAt) * 1000).rounded()))
            totalDeltaIntervalMs += interval
            maxDeltaIntervalMs = max(maxDeltaIntervalMs, interval)
            measuredDeltaIntervals += 1
        }
        previousChunkAt = now
        lastActivityAt = now
        chunks += 1
        latestContent = content
    }

    func markCancelledByConsumer() {
        wasCancelledByConsumer = true
        cancel()
    }

    func toolStarted(id: String = UUID().uuidString) {
        if phase != .stopping { phase = .executing }
        activeToolCalls += 1
        maxParallelToolCalls = max(maxParallelToolCalls, activeToolCalls)
        toolStartedAt[id] = Date()
        lastActivityAt = Date()
    }

    func toolFinished(id: String, result: ToolInvocationResult) {
        if Self.isToolTimeout(result) {
            sawToolTimeout = true
        }
        if !result.ok {
            toolErrors.append(result)
            failedToolCalls += 1
        }
        recordLoopBlock(result)
        if let startedAt = toolStartedAt.removeValue(forKey: id) {
            totalToolDurationMs += max(0, Int((Date().timeIntervalSince(startedAt) * 1000).rounded()))
            finishedToolCalls += 1
        }
        activeToolCalls = max(0, activeToolCalls - 1)
        if activeToolCalls == 0, phase != .stopping {
            phase = completion == nil ? .requesting : .finalizing
        }
        lastActivityAt = Date()
    }

    func toolFinished() {
        activeToolCalls = max(0, activeToolCalls - 1)
        lastActivityAt = Date()
    }

    func recordLoopBlock(_ result: ToolInvocationResult) {
        guard !result.ok, result.error?.code == "tool_loop_detected", toolLoopStopMessage == nil else { return }
        if !toolErrors.contains(where: { $0.error?.code == "tool_loop_detected" }) { toolErrors.append(result) }
        let message = "Stopped repeated tool calls to \(result.tool). \(result.error?.message ?? "The operation needs corrected arguments.")"
        toolLoopStopMessage = message
        latestContent = message
    }

    nonisolated static func isToolTimeout(_ result: ToolInvocationResult) -> Bool {
        // Error prose may quote logs or be localized; only protocol fields affect recovery.
        switch result.error?.code {
        case "tool_timeout", "tool_approval_timeout", "provider_timeout":
            return true
        case "tool_execution_interrupted":
            return result.data?.asObject?["timedOut"]?.asBool == true
        default:
            return false
        }
    }

    var hasActiveTools: Bool {
        activeToolCalls > 0
    }

    func isIdle(thresholdSeconds: Int) -> Bool {
        Date().timeIntervalSince(lastActivityAt) >= Double(thresholdSeconds)
    }

    func shouldTriggerIdleTimeout(thresholdSeconds: Int) -> Bool {
        activeToolCalls == 0 && Date().timeIntervalSince(lastActivityAt) >= Double(thresholdSeconds)
    }

    func recordToolBatch(toolNames: [String], config: NativeAgentLoopConfig) {
        guard !toolNames.isEmpty else { return }
        toolCallCount += toolNames.count
        toolBatchCount += 1
        // Calls after accepted completion still receive correlated results, but cannot consume work budget.
        guard completion == nil else {
            lastActivityAt = Date()
            return
        }
        let hasNonFinalizerTool = toolNames.contains { !config.finalizerToolNames.contains($0) }
        guard hasNonFinalizerTool else {
            lastActivityAt = Date()
            return
        }
        toolRoundsUsed += 1
        if config.enforceToolRoundLimit, toolRoundsUsed > config.maxToolRounds + config.overBudgetRecoveryBatches {
            hitToolRoundLimit = true
        }
        lastActivityAt = Date()
    }

    func performanceSample(
        channelId: String,
        model: String,
        streamStartedAt: Date,
        finishedAt: Date = Date()
    ) -> RuntimePerformanceSample {
        let generationDurationMs = max(0, Int((finishedAt.timeIntervalSince(streamStartedAt) * 1000).rounded()))
        let ttft = firstChunkAt.map { max(0, Int(($0.timeIntervalSince(streamStartedAt) * 1000).rounded())) }
        let averageDelta = measuredDeltaIntervals > 0
            ? Int((Double(totalDeltaIntervalMs) / Double(measuredDeltaIntervals)).rounded())
            : nil
        let durationSeconds = max(0.001, Double(generationDurationMs) / 1000)
        return RuntimePerformanceSample(
            channelId: channelId,
            model: model,
            timeToFirstTokenMs: ttft,
            generationDurationMs: generationDurationMs,
            outputCharacters: latestContent.count,
            streamChunks: chunks,
            averageDeltaIntervalMs: averageDelta,
            maxDeltaIntervalMs: measuredDeltaIntervals > 0 ? maxDeltaIntervalMs : nil,
            charactersPerSecond: Double(latestContent.count) / durationSeconds,
            toolCallCount: toolCallCount,
            toolBatchCount: toolBatchCount,
            maxParallelToolCalls: maxParallelToolCalls,
            averageToolDurationMs: finishedToolCalls > 0
                ? Int((Double(totalToolDurationMs) / Double(finishedToolCalls)).rounded())
                : nil,
            failedToolCalls: failedToolCalls
        )
    }

    func budgetExhaustedResult(for toolName: String, config: NativeAgentLoopConfig) -> ToolInvocationResult? {
        guard config.enforceToolRoundLimit,
              !hitToolRoundLimit,
              toolRoundsUsed > config.maxToolRounds,
              !config.finalizerToolNames.contains(toolName)
        else {
            return nil
        }

        let result = ToolInvocationResult(
            tool: toolName,
            ok: false,
            error: ToolErrorPayload(
                code: "tool_budget_exhausted",
                message: config.budgetExhaustedMessage,
                retryable: false
            )
        )
        toolErrors.append(result)
        lastActivityAt = Date()
        return result
    }

    func nativeLoopOutcome(
        maxToolRounds: Int,
        finishedNaturally: Bool,
        lastAssistantText: String,
        turnExitReason: NativeAgentLoopTurnExitReason = .completed
    ) -> NativeAgentLoopOutcome {
        NativeAgentLoopOutcome(
            toolRoundsUsed: toolRoundsUsed,
            maxToolRounds: pinnedLoopConfig?.maxToolRounds ?? maxToolRounds,
            finishedNaturally: finishedNaturally && phase != .stopping && toolStop == nil && !hitToolRoundLimit && toolLoopStopMessage == nil,
            hitTurnLimit: hitToolRoundLimit,
            toolErrors: toolErrors,
            lastAssistantText: toolLoopStopMessage ?? lastAssistantText,
            turnExitReason: toolLoopStopMessage == nil ? turnExitReason : .toolLoopDetected,
            terminalToolStop: toolStop
        )
    }

    private var recoveryCounts: [RecoveryReason: Int] = [:]

    public func recoveryCount(for reason: RecoveryReason) -> Int { recoveryCounts[reason, default: 0] }

    /// The turn owns these counters, so a continuation cannot grant itself another retry budget.
    func reserveRecovery(for reason: RecoveryReason, limit: Int) -> Int? {
        guard phase != .stopping, phase != .settled, completion == nil,
              !hitToolRoundLimit, toolLoopStopMessage == nil,
              recoveryCounts[reason, default: 0] < limit else { return nil }
        recoveryCounts[reason, default: 0] += 1
        phase = .recovering
        return recoveryCounts[reason]
    }

    func clearContextRecovery() { recoveryCounts[.contextOverflow] = nil }

    func recordSettledTool(id: String, result: ToolInvocationResult) {
        if toolStartedAt[id] != nil {
            toolFinished(id: id, result: result)
        } else {
            if !result.ok { toolErrors.append(result); failedToolCalls += 1 }
            recordLoopBlock(result)
            lastActivityAt = Date()
        }
        if !result.ok, toolStop == nil, let error = result.error, let reason = ToolRunStop.Reason(rawValue: error.code) {
            toolStop = .init(reason: reason, message: error.message, generation: generation)
            phase = .stopping
        }
    }

    /// Only the authoritative journal replays these observations, before another request starts.
    /// Work counters were already committed before execution and must not be charged again.
    public func restoreSettledObservation(_ result: ToolInvocationResult, callID: String, generation expected: Int) throws {
        guard generation == expected, phase == .preparing || phase == .stopping else {
            throw ModelStepFailure(category: .protocolViolation, code: "invalid_outcome_replay",
                message: "Settled observations can only restore their original run generation before resuming.", stage: .preparation)
        }
        recordSettledTool(id: callID, result: result)
    }

    private var pinnedLoopConfig: NativeAgentLoopConfig?
    private var turnStartedAt = Date()
    private var timingOrigin = ContinuousClock.now
    private var elapsedBeforeResume: Double = 0
    public private(set) var toolStop: ToolRunStop?
    private var pinnedModel: String?
    private(set) var requestPurpose: ModelStepPurpose = .work
    public private(set) var requestSettings: RunRequestSettings?

    func setRequestPurpose(_ purpose: ModelStepPurpose) { requestPurpose = purpose }

    func stop(reason: ToolRunStop.Reason, message: String) {
        if toolStop == nil { toolStop = .init(reason: reason, message: message, generation: generation) }
        phase = .stopping
    }

    func stopForModelFailure(_ failure: ModelStepFailure) {
        guard completion == nil else { return }
        if toolStop == nil {
            var stop = ToolRunStop(reason: .modelFailure, message: failure.message, generation: generation)
            stop.modelFailure = failure
            toolStop = stop
        }
        phase = .stopping
    }

    public init(snapshot: RunStateSnapshot) throws {
        try snapshot.validate()
        runID = snapshot.runID
        userTurnID = snapshot.userTurnID
        generation = snapshot.generation
        phase = snapshot.phase == .stopping || snapshot.phase == .settled ? snapshot.phase :
            (snapshot.completion == nil ? .preparing : .finalizing)
        requestAttempts = snapshot.requestAttempts
        toolRoundsUsed = snapshot.toolRoundsUsed
        hitToolRoundLimit = snapshot.hitToolRoundLimit
        toolErrors = snapshot.toolErrors
        recoveryCounts = Dictionary(uniqueKeysWithValues: snapshot.recoveryCounts.compactMap { key, count in
            RecoveryReason(rawValue: key).map { ($0, count) }
        })
        completion = snapshot.completion
        verificationEvidence = snapshot.verificationEvidence
        workScopeRevision = snapshot.workScopeRevision ?? 0
        pinnedLoopConfig = snapshot.loopConfig
        turnStartedAt = snapshot.startedAt
        elapsedBeforeResume = snapshot.elapsedSeconds + max(0, Date().timeIntervalSince(snapshot.savedAt))
        toolLoopStopMessage = snapshot.toolErrors.first(where: { $0.error?.code == "tool_loop_detected" })?.error?.message
        toolStop = snapshot.toolStop
        pinnedModel = snapshot.model
        requestPurpose = snapshot.requestPurpose ?? .work
        requestSettings = snapshot.requestSettings
    }

    func bindLoopConfig(_ config: NativeAgentLoopConfig) -> NativeAgentLoopConfig {
        if let pinnedLoopConfig { return pinnedLoopConfig }
        var pinned = config
        pinned.engine = .unified
        pinnedLoopConfig = pinned
        return pinned
    }

    /// A successful product route can change completion policy, never replenish turn budgets.
    public func selectMode(_ mode: AgentChatMode, generation expected: Int) throws {
        try checkActive(generation: expected)
        guard var config = pinnedLoopConfig else { throw RunStateSnapshot.ValidationError.invalidSnapshot }
        config.activeMode = mode
        config.requiresExplicitCompletion = config.completionContract == .worker ||
            (config.completionContract != .coordinator && (mode == .build || mode == .debug))
        if mode == .plan || mode == .debug { config.finalizerToolNames.insert("planning.request_input") }
        pinnedLoopConfig = config
    }

    /// An answer advances authority without resetting the original turn's work or evidence.
    public func resumeAfterInput(requestID: String) throws {
        guard !Task.isCancelled, phase == .settled || phase == .finalizing,
              completion?.disposition == .waitingInput, completion?.inputRequestId == requestID,
              toolStop == nil, !hitToolRoundLimit else { throw RunStateSnapshot.ValidationError.invalidSnapshot }
        generation += 1
        completion = nil
        phase = .preparing
        requestPurpose = .work
    }

    /// Keep the original owner and all consumed budgets after credentials become available.
    public func resumeAfterProviderFailure() throws {
        guard !Task.isCancelled, snapshot().canResumeProviderFailure else {
            throw RunStateSnapshot.ValidationError.invalidSnapshot
        }
        generation += 1
        toolStop = nil
        phase = .preparing
        requestPurpose = .work
    }

    func bindRequestSettings(_ settings: RunRequestSettings) throws -> RunRequestSettings {
        if let requestSettings { return requestSettings }
        _ = try settings.transportRetryDelays()
        requestSettings = settings
        return settings
    }

    func bindModel(_ model: String) throws {
        if let pinnedModel {
            guard pinnedModel == model else {
                throw ModelStepFailure(category: .unavailable, code: "run_model_changed",
                    message: "The active turn is pinned to \(pinnedModel). Model changes require an explicit compatible routing transition or a new turn.", stage: .preparation)
            }
        } else {
            guard requestAttempts == 0 else {
                throw ModelStepFailure(category: .unavailable, code: "run_model_missing",
                    message: "This active checkpoint does not identify its model. Inspect it before resuming with a compatible engine.", stage: .preparation)
            }
            pinnedModel = model
        }
    }

    public func snapshot() -> RunStateSnapshot {
        let duration = timingOrigin.duration(to: .now).components
        let elapsed = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        var snapshot = RunStateSnapshot(schemaVersion: requestSettings == nil ? 1 : 2,
            runID: runID, userTurnID: userTurnID, generation: generation, phase: phase,
            requestAttempts: requestAttempts, toolRoundsUsed: toolRoundsUsed, hitToolRoundLimit: hitToolRoundLimit,
            toolErrors: toolErrors, recoveryCounts: Dictionary(uniqueKeysWithValues: recoveryCounts.map { ($0.key.rawValue, $0.value) }),
            completion: completion, verificationEvidence: verificationEvidence, loopConfig: pinnedLoopConfig,
            startedAt: turnStartedAt, savedAt: Date(), elapsedSeconds: elapsedBeforeResume + max(0, elapsed), toolStop: toolStop,
            model: pinnedModel, requestPurpose: requestPurpose, requestSettings: requestSettings)
        snapshot.workScopeRevision = workScopeRevision == 0 ? nil : workScopeRevision
        return snapshot
    }

    /// The journal has already restored a validated completion; settlement needs no provider.
    public func settleRestoredCompletion(generation expected: Int) throws -> RunStateSnapshot {
        try Task.checkCancellation()
        guard generation == expected, phase != .stopping else { throw CancellationError() }
        guard phase == .finalizing, completion != nil, activeToolCalls == 0 else {
            throw RunStateSnapshot.ValidationError.invalidSnapshot
        }
        if let toolStop, toolStop.generation == generation { throw toolStop.failure }
        phase = .settled
        return snapshot()
    }

    func checkTerminalDelivery(generation expected: Int) throws {
        try Task.checkCancellation()
        guard generation == expected else { throw CancellationError() }
        if let toolStop, toolStop.generation == generation { throw toolStop.failure }
        guard phase == .settled else { throw CancellationError() }
    }

    func markSettled() {
        if phase != .stopping, activeToolCalls == 0 { phase = .settled }
    }

    /// Selection and its durable write cannot interleave with cancellation or completion.
    public func atInputBoundary(generation expected: Int,
        operation: @Sendable (RunStateSnapshot) throws -> Bool) throws -> Bool {
        try checkActive(generation: expected)
        guard completion == nil, activeToolCalls == 0, requestSettings?.derivedSource == nil,
              requestSettings?.coordinatorNotification != true else { return false }
        return try operation(snapshot())
    }
}
