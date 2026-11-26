import AgentRuntime
import Foundation
import Protocols

enum ExecutionOutcomeClassifier {
    static func toolResult(_ result: ToolInvocationResult) -> ExecutionOutcome {
        if result.error?.code == MCPToolOutcomeUnknown.code {
            return .init(state: .interrupted, category: .unknown, code: result.error?.code, requiresReconciliation: true)
        }
        return .init(state: result.ok ? .completed : .failed, category: result.ok ? nil : .tool,
                     code: result.error?.code, retryable: result.error?.retryable ?? false)
    }

    static func classify(reason: NativeAgentLoopTurnExitReason, interrupted: Bool = false, waitingInput: Bool = false, blocked: Bool = false, incomplete: Bool = false) -> ExecutionOutcome {
        if interrupted || reason == .consumerCancelled || reason == .modelCancelled { return .init(state: .cancelled) }
        if waitingInput { return .init(state: .waitingInput) }
        switch reason {
        case .modelProviderError, .streamRetryFailed, .streamInterruptedAfterTools:
            return .init(state: .failed, category: .provider, code: reason.rawValue, retryable: true)
        case .steered:
            return .init(state: .interrupted, code: reason.rawValue)
        case .missingRuntimeOutcome:
            return .init(state: .failed, category: .unknown, code: reason.rawValue, retryable: true)
        case .contextWindowRecoveryFailed, .workerContextTooLarge:
            return .init(state: .failed, category: .context, code: reason.rawValue)
        case .workerLaunchFailed:
            return .init(state: .failed, category: .unavailable, code: reason.rawValue)
        case .toolLoopDetected, .emptyAfterToolTimeout:
            return .init(state: .failed, category: .tool, code: reason.rawValue)
        case .fallbackNoModel:
            return .init(state: .failed, category: .unavailable, code: reason.rawValue)
        case .toolRoundLimit, .emptyResponse:
            return .init(state: .failed, category: .incomplete, code: reason.rawValue)
        case .modelCancelled, .consumerCancelled:
            return .init(state: .cancelled)
        case .completed, .streamIdleTimeoutFallback, .contextWindowRecovered, .emptyResponseRepaired:
            break
        }
        if blocked { return .init(state: .failed, category: .tool, code: "blocked") }
        if incomplete { return .init(state: .failed, category: .incomplete, code: "completion_missing") }
        return .completed
    }
}

extension AgentSessionMessageResponse {
    var yieldedToSteering: Bool {
        appendedEvents.last?.runStatus?.diagnostics?.turnExitReason == NativeAgentLoopTurnExitReason.steered.rawValue
    }
}
