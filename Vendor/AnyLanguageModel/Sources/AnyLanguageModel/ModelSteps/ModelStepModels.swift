import Foundation


public struct LanguageModelStepToolCall: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    /// Keep original bytes as text. Invalid JSON must never become invented empty arguments.
    public var rawArguments: String
    public init(id: String, name: String, rawArguments: String) {
        self.id = id; self.name = name; self.rawArguments = rawArguments
    }
}

public struct LanguageModelStepToolOutput: Codable, Sendable, Equatable {
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

public struct LanguageModelStepImage: Codable, Sendable, Equatable {
    public var mimeType: String
    public var data: Data?
    public var url: URL?
    public init(mimeType: String, data: Data? = nil, url: URL? = nil) {
        self.mimeType = mimeType; self.data = data; self.url = url
    }
}

/// Provider-owned content stays in its original array order, including signatures/encrypted reasoning.
public struct LanguageModelStepContinuation: Codable, Sendable, Equatable {
    public var providerId: String
    public var modelId: String
    public var format: String
    public var content: StepJSONValue
    public init(providerId: String, modelId: String, format: String, content: StepJSONValue) {
        self.providerId = providerId; self.modelId = modelId; self.format = format; self.content = content
    }
}

public struct LanguageModelStepMessage: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable { case system, user, assistant, tool }
    public var id: String
    public var role: Role
    public var text: String
    public var images: [LanguageModelStepImage]
    public var toolCalls: [LanguageModelStepToolCall]
    public var toolOutput: LanguageModelStepToolOutput?
    public var continuation: LanguageModelStepContinuation?
    public init(id: String = UUID().uuidString, role: Role, text: String = "", images: [LanguageModelStepImage] = [],
                toolCalls: [LanguageModelStepToolCall] = [], toolOutput: LanguageModelStepToolOutput? = nil,
                continuation: LanguageModelStepContinuation? = nil) {
        self.id = id; self.role = role; self.text = text; self.images = images
        self.toolCalls = toolCalls; self.toolOutput = toolOutput; self.continuation = continuation
    }
}

/// A schema declaration, never an executable tool.
public struct LanguageModelStepToolDefinition: Codable, Sendable, Equatable {
    public var name: String
    public var description: String
    public var parameters: StepJSONValue
    public init(name: String, description: String = "", parameters: StepJSONValue) {
        self.name = name; self.description = description; self.parameters = parameters
    }
}

public struct LanguageModelStepRequest: Codable, Sendable, Equatable {
    public var stepId: String
    public var attemptId: String
    public var cacheScope: String
    public var messages: [LanguageModelStepMessage]
    public var tools: [LanguageModelStepToolDefinition]
    public var maximumOutputTokens: Int
    public var reasoningEffort: StepReasoningEffort?
    public var parallelToolCalls: Bool
    public init(messages: [LanguageModelStepMessage], tools: [LanguageModelStepToolDefinition] = [],
                maximumOutputTokens: Int = 1024, reasoningEffort: StepReasoningEffort? = nil,
                parallelToolCalls: Bool = true, stepId: String = UUID().uuidString,
                attemptId: String = UUID().uuidString, cacheScope: String = "") {
        self.messages = messages; self.tools = tools; self.maximumOutputTokens = maximumOutputTokens
        self.reasoningEffort = reasoningEffort; self.parallelToolCalls = parallelToolCalls
        self.stepId = stepId; self.attemptId = attemptId; self.cacheScope = cacheScope
    }
}

public struct LanguageModelStepResponse: Codable, Sendable, Equatable {
    public enum StopReason: String, Codable, Sendable {
        case endTurn = "end_turn"
        case toolCalls = "tool_calls"
        case outputLimit = "output_limit"
        case incomplete
    }
    public var text: String
    public var toolCalls: [LanguageModelStepToolCall]
    public var stopReason: StopReason
    public var usage: StepTokenUsage?
    public var continuation: LanguageModelStepContinuation?
    public init(text: String = "", toolCalls: [LanguageModelStepToolCall] = [], stopReason: StopReason,
                usage: StepTokenUsage? = nil, continuation: LanguageModelStepContinuation? = nil) {
        self.text = text; self.toolCalls = toolCalls; self.stopReason = stopReason
        self.usage = usage; self.continuation = continuation
    }
}

public enum LanguageModelStepEvent: Sendable {
    case started
    case textDelta(String)
    case reasoningDelta(String)
    case toolCallDelta(index: Int, name: String?, arguments: String)
    case final(LanguageModelStepResponse)
}

public struct LanguageModelStepFailure: Error, Codable, Sendable, Equatable, LocalizedError {
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

public enum StepReasoningEffort: String, Codable, Sendable, CaseIterable { case low, medium, high, xhigh, max }
public struct StepTokenUsage: Codable, Sendable, Equatable {
    public var prompt: Int
    public var completion: Int
    public var cachedInput: Int
    public var cacheCreationInput: Int
    public var reasoning: Int

    public init(
        prompt: Int,
        completion: Int,
        cachedInputTokens: Int = 0,
        cacheCreationInputTokens: Int = 0,
        reasoningTokens: Int = 0
    ) {
        self.prompt = prompt
        self.completion = completion
        self.cachedInput = cachedInputTokens
        self.cacheCreationInput = cacheCreationInputTokens
        self.reasoning = reasoningTokens
    }

    public var total: Int {
        prompt + completion
    }

    public var uncachedInput: Int {
        max(0, prompt - cachedInput)
    }

    enum CodingKeys: String, CodingKey {
        case prompt
        case completion
        case cachedInput
        case cacheCreationInput
        case reasoning
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prompt = try container.decode(Int.self, forKey: .prompt)
        completion = try container.decode(Int.self, forKey: .completion)
        cachedInput = try container.decodeIfPresent(Int.self, forKey: .cachedInput) ?? 0
        cacheCreationInput = try container.decodeIfPresent(Int.self, forKey: .cacheCreationInput) ?? 0
        reasoning = try container.decodeIfPresent(Int.self, forKey: .reasoning) ?? 0
    }
}

