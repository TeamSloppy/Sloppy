import Foundation
import Protocols

public enum ModelStepPurpose: String, Codable, Sendable {
    case work
    case planning
    case compaction
    case reportReview = "report_review"
    case completionRecovery = "completion_recovery"
    case finalAnswer = "final_answer"
}

public struct ModelStepToolCall: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    /// Keep original bytes as text. Invalid JSON must never become invented empty arguments.
    public var rawArguments: String
    public init(id: String, name: String, rawArguments: String) {
        self.id = id; self.name = name; self.rawArguments = rawArguments
    }
}

public struct ModelStepToolOutput: Codable, Sendable, Equatable {
    public var callId: String
    public var name: String
    public var content: String
    /// A recorded tool outcome, independent of any text printed by the tool.
    public var isError: Bool?
    public init(callId: String, name: String, content: String, isError: Bool? = nil) {
        self.callId = callId; self.name = name; self.content = content
        self.isError = isError
    }
}

public struct ModelStepImage: Codable, Sendable, Equatable {
    public var mimeType: String
    public var data: Data?
    public var url: URL?
    public init(mimeType: String, data: Data? = nil, url: URL? = nil) {
        self.mimeType = mimeType; self.data = data; self.url = url
    }
}

/// Provider-owned content stays in its original array order, including signatures/encrypted reasoning.
public struct ModelStepContinuation: Codable, Sendable, Equatable {
    public var providerId: String
    public var modelId: String
    public var format: String
    public var content: JSONValue
    public init(providerId: String, modelId: String, format: String, content: JSONValue) {
        self.providerId = providerId; self.modelId = modelId; self.format = format; self.content = content
    }
}

public struct ModelStepMessage: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable { case system, user, assistant, tool }
    public var id: String
    public var role: Role
    public var text: String
    public var images: [ModelStepImage]
    public var toolCalls: [ModelStepToolCall]
    public var toolOutput: ModelStepToolOutput?
    public var continuation: ModelStepContinuation?
    public init(id: String = UUID().uuidString, role: Role, text: String = "", images: [ModelStepImage] = [],
                toolCalls: [ModelStepToolCall] = [], toolOutput: ModelStepToolOutput? = nil,
                continuation: ModelStepContinuation? = nil) {
        self.id = id; self.role = role; self.text = text; self.images = images
        self.toolCalls = toolCalls; self.toolOutput = toolOutput; self.continuation = continuation
    }
}

public struct ModelStepToolDefinition: Codable, Sendable, Equatable {
    public enum ReplayPolicy: String, Codable, Sendable {
        case neverAutomatically = "never_automatically"
        case safe
    }
    public enum CachePolicy: String, Codable, Sendable { case none }
    public var name: String
    public var toolId: String
    public var description: String
    public var parameters: JSONValue
    public var readOnly: Bool
    public var concurrencySafe: Bool
    public var replayPolicy: ReplayPolicy
    public var cachePolicy: CachePolicy
    public init(name: String, toolId: String? = nil, description: String = "", parameters: JSONValue,
                readOnly: Bool = false, concurrencySafe: Bool = false,
                replayPolicy: ReplayPolicy = .neverAutomatically, cachePolicy: CachePolicy = .none) {
        self.name = name; self.toolId = toolId ?? name; self.description = description; self.parameters = parameters
        self.readOnly = readOnly; self.concurrencySafe = concurrencySafe
        self.replayPolicy = replayPolicy; self.cachePolicy = cachePolicy
    }
}

public struct ModelStepRequest: Codable, Sendable, Equatable {
    public var runId: String
    public var userTurnId: String
    public var stepId: String
    public var attemptId: String
    public var model: String
    public var projectionRevision: String
    public var cacheScope: String
    public var messages: [ModelStepMessage]
    public var tools: [ModelStepToolDefinition]
    public var maximumOutputTokens: Int
    public var reasoningEffort: ReasoningEffort?
    public var parallelToolCalls: Bool
    public var generation: Int
    public var requiresReconciliation: Bool
    public var reconciliationCallEventIDs: [String]
    public var purpose: ModelStepPurpose
    public init(runId: String, userTurnId: String, stepId: String, attemptId: String, model: String,
                projectionRevision: String, cacheScope: String, messages: [ModelStepMessage],
                tools: [ModelStepToolDefinition] = [], maximumOutputTokens: Int = 1024,
                reasoningEffort: ReasoningEffort? = nil, parallelToolCalls: Bool = true, generation: Int = 0,
                requiresReconciliation: Bool = false, reconciliationCallEventIDs: [String] = [], purpose: ModelStepPurpose = .work) {
        self.runId = runId; self.userTurnId = userTurnId; self.stepId = stepId; self.attemptId = attemptId
        self.model = model; self.projectionRevision = projectionRevision; self.cacheScope = cacheScope
        self.messages = messages; self.tools = tools; self.maximumOutputTokens = maximumOutputTokens
        self.reasoningEffort = reasoningEffort; self.parallelToolCalls = parallelToolCalls
        self.generation = generation
        self.requiresReconciliation = requiresReconciliation
        self.reconciliationCallEventIDs = reconciliationCallEventIDs
        self.purpose = purpose
    }
}

public struct ModelStepResponse: Codable, Sendable, Equatable {
    public enum StopReason: String, Codable, Sendable {
        case endTurn = "end_turn"
        case toolCalls = "tool_calls"
        case outputLimit = "output_limit"
        case incomplete
    }
    public var text: String
    public var toolCalls: [ModelStepToolCall]
    public var stopReason: StopReason
    public var usage: TokenUsage?
    public var continuation: ModelStepContinuation?
    public init(text: String = "", toolCalls: [ModelStepToolCall] = [], stopReason: StopReason,
                usage: TokenUsage? = nil, continuation: ModelStepContinuation? = nil) {
        self.text = text; self.toolCalls = toolCalls; self.stopReason = stopReason
        self.usage = usage; self.continuation = continuation
    }
}

public enum ModelStepEvent: Sendable {
    case started
    case textDelta(String)
    case reasoningDelta(String)
    case toolCallDelta(index: Int, name: String?, arguments: String)
    case final(ModelStepResponse)
}

public struct ModelStepFailure: Error, Codable, Sendable, Equatable, LocalizedError {
    public enum Category: String, Codable, Sendable {
        case transport, provider, authentication, context
        case protocolViolation = "protocol_violation"
        case cancelled, unavailable
    }
    public enum Stage: String, Codable, Sendable { case preparation, request, streaming, finalization }
    public var category: Category
    public var code: String
    public var message: String
    public var retryable: Bool
    public var stage: Stage
    public var retryAfterSeconds: Double?
    public var parameter: String? = nil
    public var errorDescription: String? { message }
    public init(category: Category, code: String, message: String, retryable: Bool = false,
                stage: Stage = .request, retryAfterSeconds: Double? = nil, parameter: String? = nil) {
        self.category = category; self.code = code; self.message = message; self.retryable = retryable
        self.stage = stage; self.retryAfterSeconds = retryAfterSeconds
        self.parameter = parameter
    }
}
