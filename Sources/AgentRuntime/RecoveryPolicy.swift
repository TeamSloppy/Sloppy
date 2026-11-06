import Foundation
import PluginSDK

public struct ToolRunStop: Codable, Sendable, Equatable {
    public enum Reason: String, Codable, Sendable {
        case forbidden = "tool_forbidden"
        case authorizationFailed = "authorization_failed"
        case approvalRejected = "tool_approval_rejected"
        case approvalTimeout = "tool_approval_timeout"
        case loopDetected = "tool_loop_detected"
        case reconciliationRequired = "tool_reconciliation_required"
        case interrupted = "tool_execution_interrupted"
        case missingCompletion = "required_completion_missing"
        case emptyFinal = "empty_final_answer"
        case toolsDuringFinalAnswer = "tools_disallowed_during_final_answer"
        case deadlineExceeded = "tool_deadline_exhausted"
        case modelFailure = "model_failure"
    }
    public var reason: Reason
    public var message: String
    public var generation: Int
    public var modelFailure: ModelStepFailure? = nil
    public init(reason: Reason, message: String, generation: Int) {
        self.reason = reason; self.message = message; self.generation = generation
    }
    public var failure: ModelStepFailure {
        if let modelFailure { return modelFailure }
        return .init(category: .unavailable, code: reason.rawValue, message: message, stage: .finalization)
    }
}

public enum RecoveryReason: String, Codable, Sendable {
    case transportLoss = "transport_loss"
    case coordinatorRecovery = "coordinator_recovery"
    case contextOverflow = "context_overflow"
    case emptyFinal = "empty_final"
    case missingCompletion = "missing_completion"
}

/// A typed decision never infers a retry from localized provider/assistant text.
public struct RecoveryPolicy: Sendable {
    public enum Decision: Sendable, Equatable {
        case retryRequest(after: Duration)
        case stop
    }
    public let retryDelays: [Duration]

    public init(retryDelays: [Duration]) { self.retryDelays = retryDelays }

    public func decision(for failure: ModelStepFailure, usedAttempts: Int) -> Decision {
        guard failure.retryable, failure.category == .transport || failure.category == .provider,
              usedAttempts >= 0, usedAttempts < retryDelays.count else { return .stop }
        var delay = retryDelays[usedAttempts]
        if let seconds = failure.retryAfterSeconds, seconds.isFinite, seconds >= 0 {
            delay = max(delay, .seconds(seconds))
        }
        return .retryRequest(after: max(.zero, delay))
    }
}
