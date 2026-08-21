import AnyLanguageModel
import Foundation
import Logging
import PluginSDK
import Protocols

struct StreamIdleTimeoutError: Error, LocalizedError {
    var errorDescription: String? { "Model stream idle timeout" }
}

actor StreamActivityTracker {
    var lastActivityAt: Date = .init()
    var activeToolCalls: Int = 0
    private(set) var latestContent: String = ""
    private(set) var chunks: Int = 0
    private(set) var wasCancelledByConsumer: Bool = false
    private(set) var sawToolTimeout: Bool = false
    private(set) var toolRoundsUsed: Int = 0
    private(set) var hitToolRoundLimit: Bool = false
    var toolErrors: [ToolInvocationResult] = []
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

    func touch() {
        lastActivityAt = Date()
    }

    func recordChunk(content: String) {
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
    }

    func toolStarted(id: String = UUID().uuidString) {
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
        if let startedAt = toolStartedAt.removeValue(forKey: id) {
            totalToolDurationMs += max(0, Int((Date().timeIntervalSince(startedAt) * 1000).rounded()))
            finishedToolCalls += 1
        }
        activeToolCalls = max(0, activeToolCalls - 1)
        lastActivityAt = Date()
    }

    func toolFinished() {
        activeToolCalls = max(0, activeToolCalls - 1)
        lastActivityAt = Date()
    }

    nonisolated static func isToolTimeout(_ result: ToolInvocationResult) -> Bool {
        guard let error = result.error else {
            return false
        }
        let code = error.code.lowercased()
        let message = error.message.lowercased()
        return code.contains("timeout") || message.contains("timed out")
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
            maxToolRounds: maxToolRounds,
            finishedNaturally: finishedNaturally && !hitToolRoundLimit,
            hitTurnLimit: hitToolRoundLimit,
            toolErrors: toolErrors,
            lastAssistantText: lastAssistantText,
            turnExitReason: turnExitReason
        )
    }
}
