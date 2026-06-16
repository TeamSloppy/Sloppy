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

    func touch() {
        lastActivityAt = Date()
    }

    func touchChunk() {
        lastActivityAt = Date()
        chunks += 1
    }

    func update(content: String) {
        latestContent = content
    }

    func markCancelledByConsumer() {
        wasCancelledByConsumer = true
    }

    func toolStarted() {
        activeToolCalls += 1
        lastActivityAt = Date()
    }

    func toolFinished(result: ToolInvocationResult) {
        if Self.isToolTimeout(result) {
            sawToolTimeout = true
        }
        if !result.ok {
            toolErrors.append(result)
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
