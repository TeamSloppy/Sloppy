import Foundation
import PluginSDK
import Protocols

public struct AgentLoopCall: Sendable, Codable, Equatable {
    public var eventID: String
    public var sourceOrder: Int
    public var call: ModelStepToolCall
    public var runtimeMetadata: AgentRunMetadata?
    public init(eventID: String = UUID().uuidString, sourceOrder: Int, call: ModelStepToolCall, runtimeMetadata: AgentRunMetadata? = nil) {
        self.eventID = eventID
        self.sourceOrder = sourceOrder
        self.call = call
        self.runtimeMetadata = runtimeMetadata
    }
}

/// Durable operations are awaited. An implementation must throw before acknowledging a failed write.
public protocol AgentLoopJournal: Sendable {
    func prepareRequest(_ request: ModelStepRequest) async throws -> ModelStepRequest
    func appendResponse(_ response: ModelStepResponse, request: ModelStepRequest) async throws
    func appendRequested(_ calls: [AgentLoopCall], request: ModelStepRequest) async throws
    func appendStarted(_ call: AgentLoopCall, request: ModelStepRequest) async throws
    func appendResult(_ result: ToolInvocationResult, call: AgentLoopCall, request: ModelStepRequest) async throws
}

/// Provider-reported fallback usage shares the response's durable commit.
public protocol AgentLoopUsageJournal: AgentLoopJournal {
    func appendResponse(_ response: ModelStepResponse, request: ModelStepRequest, usageRequest: UsageRequestRecord) async throws
}

/// A durable writer can retain product-policy authority separately from scalar observations.
public protocol AgentLoopOutcomeJournal: AgentLoopJournal {
    func appendOutcome(_ outcome: AgentLoopToolOutcome, call: AgentLoopCall, request: ModelStepRequest) async throws
}

public protocol AgentLoopStateJournal: AgentLoopJournal {
    func appendRunState(_ snapshot: RunStateSnapshot, request: ModelStepRequest) async throws
    func restoreRunState(userTurnID: String?) async throws -> RunState?
}

public protocol AgentLoopInstructionJournal: AgentLoopJournal {
    func appendInstruction(_ instruction: AgentRunInstruction, request: ModelStepRequest) async throws
}

public protocol AgentLoopInputJournal: AgentLoopJournal {
    func admitSteering(_ request: ModelStepRequest, state: RunState) async throws -> Bool
}

public struct AgentLoopPendingTools: Sendable {
    public var request: ModelStepRequest
    public var response: ModelStepResponse
    public var calls: [AgentLoopCall]
    public init(request: ModelStepRequest, response: ModelStepResponse, calls: [AgentLoopCall]) {
        self.request = request; self.response = response; self.calls = calls
    }
}

public protocol AgentLoopPendingToolJournal: AgentLoopJournal {
    func pendingToolBatch(for request: ModelStepRequest) async throws -> AgentLoopPendingTools?
}

public enum AgentLoopCompletionDecision: Sendable {
    case finish(ModelStepResponse)
    case recover(reason: RecoveryReason, limit: Int, instruction: AgentRunInstruction)
}

/// Session owners provide durable storage and their existing access/approval execution boundary.
public struct AgentLoopServices: Sendable {
    public var journal: any AgentLoopJournal
    public var executor: AgentLoopToolExecutor
    public var completionPolicy: (@Sendable (ModelStepResponse, ModelStepRequest) async throws -> AgentLoopCompletionDecision)?
    /// Trusted, consumer-scoped declarations. The pinned tool scope still narrows them.
    public var additionalTools: [ModelStepToolDefinition]
    public init(journal: any AgentLoopJournal, executor: AgentLoopToolExecutor,
        completionPolicy: (@Sendable (ModelStepResponse, ModelStepRequest) async throws -> AgentLoopCompletionDecision)? = nil,
        additionalTools: [ModelStepToolDefinition] = []) {
        self.journal = journal
        self.executor = executor
        self.completionPolicy = completionPolicy
        self.additionalTools = additionalTools
    }
}

/// Execution returns observations and an optional product-policy candidate, never terminal ownership.
public struct AgentLoopToolOutcome: Sendable {
    public var result: ToolInvocationResult
    /// A product-policy candidate. It cannot own the turn until its result is durable.
    public var completion: RunCompletion?
    /// Product-owned verification, independent of untrusted fields in result.data.
    public var verificationEvidence: [VerificationEvidence]?
    public var selectedMode: AgentChatMode? = nil
    public init(result: ToolInvocationResult, completion: RunCompletion? = nil,
                verificationEvidence: [VerificationEvidence]? = nil) {
        self.result = result
        self.completion = completion
        self.verificationEvidence = verificationEvidence
    }
}

/// Core invokes beforeEffect after its current policy, pre-hooks and approval checks.
/// No executable tool closure is ever passed to a provider.
public struct AgentLoopToolExecutor: Sendable {
    public typealias BeforeEffect = @Sendable () async throws -> Void
    public var execute: @Sendable (AgentLoopCall, ModelStepToolDefinition, [String: JSONValue], @escaping BeforeEffect) async throws -> AgentLoopToolOutcome
    public var invoke: @Sendable (AgentLoopCall, ModelStepToolDefinition, [String: JSONValue], @escaping BeforeEffect) async throws -> ToolInvocationResult {
        let operation = execute
        return { call, definition, arguments, beforeEffect in
            try await operation(call, definition, arguments, beforeEffect).result
        }
    }
    public init(invoke: @escaping @Sendable (AgentLoopCall, ModelStepToolDefinition, [String: JSONValue], @escaping BeforeEffect) async throws -> ToolInvocationResult) {
        self.execute = { call, definition, arguments, beforeEffect in
            .init(result: try await invoke(call, definition, arguments, beforeEffect))
        }
    }
    public init(execute: @escaping @Sendable (AgentLoopCall, ModelStepToolDefinition, [String: JSONValue], @escaping BeforeEffect) async throws -> AgentLoopToolOutcome) {
        self.execute = execute
    }
}
