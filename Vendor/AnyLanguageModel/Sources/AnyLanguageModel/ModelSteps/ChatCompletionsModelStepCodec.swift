import Foundation

/// The Chat Completions wire contract; completion is not inferred from text deltas.
/// https://developers.openai.com/api/reference/resources/chat/subresources/completions/streaming-events
public struct ChatCompletionsStepCodec {
    let providerID: String
    let modelID: String
    private var framing = StepSSEDecoder()
    private var message: [String: StepJSONValue] = ["role": .string("assistant"), "content": .string("")]
    private var calls: [Int: [String: StepJSONValue]] = [:]
    private var finishReason: String?
    private var usage: StepTokenUsage?
    private var done = false
    private var jsonResponse = false

    public init(providerID: String, modelID: String) { self.providerID = providerID; self.modelID = modelID }

    public static func requestBody(_ request: LanguageModelStepRequest, model: String, providerID: String, instructions: String) throws -> Data {
        var messages = [StepJSONValue]()
        if !request.messages.contains(where: { $0.role == .system }), !instructions.isEmpty {
            messages.append(.object(["role": .string("system"), "content": .string(instructions)]))
        }
        for message in request.messages {
            if message.role == .assistant, let continuation = message.continuation {
                guard continuation.providerId == providerID, continuation.modelId == model,
                      continuation.format == "chat-completions-v1", continuation.content.asObject?["role"] == .string("assistant") else {
                    throw invalid("incompatible_continuation", "Provider continuation must be explicitly normalized before switching its provider/model.")
                }
                messages.append(continuation.content)
                continue
            }
            var value: [String: StepJSONValue] = ["role": .string(message.role.rawValue), "content": .string(message.text)]
            if message.role == .user, !message.images.isEmpty {
                var content: [StepJSONValue] = [.object(["type": .string("text"), "text": .string(message.text)])]
                for image in message.images {
                    let url: String
                    if let data = image.data, !image.mimeType.isEmpty { url = "data:\(image.mimeType);base64,\(data.base64EncodedString())" }
                    else if let remote = image.url, ["http", "https"].contains(remote.scheme?.lowercased() ?? "") { url = remote.absoluteString }
                    else { throw invalid("invalid_image", "Image input needs bytes/MIME type or an HTTP URL.") }
                    content.append(.object(["type": .string("image_url"), "image_url": .object(["url": .string(url)])]))
                }
                value["content"] = .array(content)
            }
            if message.role == .assistant, !message.toolCalls.isEmpty {
                value["tool_calls"] = .array(message.toolCalls.map { .object(["id": .string($0.id), "type": .string("function"),
                    "function": .object(["name": .string($0.name), "arguments": .string($0.rawArguments)])]) })
            }
            if message.role == .tool {
                guard let output = message.toolOutput else { throw invalid("missing_tool_output", "A tool message has no correlated result.") }
                value["tool_call_id"] = .string(output.callId)
                value["content"] = .string(output.content)
            }
            messages.append(.object(value))
        }
        var body: [String: StepJSONValue] = ["model": .string(model), "messages": .array(messages), "stream": .bool(true),
            "stream_options": .object(["include_usage": .bool(true)]),
            "max_completion_tokens": .number(Double(request.maximumOutputTokens)), "store": .bool(false)]
        if !request.tools.isEmpty {
            body["tools"] = .array(request.tools.map { .object(["type": .string("function"), "function": .object([
                "name": .string($0.name), "description": .string($0.description), "parameters": $0.parameters])]) })
            body["parallel_tool_calls"] = .bool(request.parallelToolCalls)
        }
        if let effort = request.reasoningEffort { body["reasoning_effort"] = .string(effort.rawValue) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(StepJSONValue.object(body))
    }

    public mutating func consume(_ chunk: Data) throws -> [LanguageModelStepEvent] {
        var events = [LanguageModelStepEvent]()
        for payload in try framing.consume(chunk) { events += try consumePayload(payload) }
        return events
    }

    public mutating func consumeJSON(_ data: Data) throws {
        guard !jsonResponse, finishReason == nil,
              let root = try JSONDecoder().decode(StepJSONValue.self, from: data).asObject else {
            throw Self.invalid("invalid_json_response", "The response must be one complete Chat Completions object.")
        }
        try Self.checkError(root)
        let choice = try Self.choice(root)
        guard let rawMessage = choice["message"]?.asObject, rawMessage["role"] == .string("assistant"),
              let reason = choice["finish_reason"]?.asString else {
            throw Self.invalid("invalid_chat_response", "A complete response requires an assistant message and finish reason.")
        }
        message = rawMessage
        finishReason = reason
        usage = try Self.tokens(root["usage"])
        jsonResponse = true
    }

    public mutating func finish() throws -> LanguageModelStepResponse {
        for payload in try framing.finish() { _ = try consumePayload(payload) }
        guard let finishReason, jsonResponse || done else {
            throw LanguageModelStepFailure(category: .transport, code: "stream_ended_before_final",
                message: "The stream closed without a terminal Chat Completions response.", retryable: true, stage: .streaming)
        }
        if !jsonResponse, !calls.isEmpty {
            let indexes = calls.keys.sorted()
            guard indexes == Array(0..<indexes.count) else { throw Self.invalid("missing_tool_calls", "The response omitted a tool-call index.") }
            message["tool_calls"] = .array(indexes.compactMap { calls[$0].map(StepJSONValue.object) })
        }
        guard message["role"] == .string("assistant"), message["function_call"] == nil else {
            throw Self.invalid("unsupported_chat_response", "Only assistant function-tool responses are supported.")
        }
        let toolCalls = try (message["tool_calls"]?.asArray ?? []).map { value -> LanguageModelStepToolCall in
            guard let call = value.asObject, call["type"] == .string("function"),
                  let id = call["id"]?.asString, !id.isEmpty,
                  let name = call["function"]?.asObject?["name"]?.asString, !name.isEmpty,
                  let arguments = call["function"]?.asObject?["arguments"]?.asString else {
                throw Self.invalid("invalid_function_call", "A tool call is missing its ID, name or raw arguments.")
            }
            return .init(id: id, name: name, rawArguments: arguments)
        }
        let text = message["content"]?.asString ?? message["content"]?.asArray?.compactMap {
            $0.asObject?["text"]?.asString ?? $0.asObject?["refusal"]?.asString
        }.joined(separator: "\n") ?? message["refusal"]?.asString ?? ""
        let reason: LanguageModelStepResponse.StopReason
        switch finishReason {
        case "stop": reason = .endTurn
        case "tool_calls": reason = .toolCalls
        case "length": reason = .outputLimit
        default: reason = .incomplete
        }
        return .init(text: text, toolCalls: toolCalls, stopReason: reason, usage: usage,
            continuation: .init(providerId: providerID, modelId: modelID, format: "chat-completions-v1", content: .object(message)))
    }

    private mutating func consumePayload(_ payload: String) throws -> [LanguageModelStepEvent] {
        guard !done else { throw Self.invalid("events_after_terminal", "The provider emitted data after [DONE].") }
        if payload == "[DONE]" { done = true; return [] }
        guard let root = try JSONDecoder().decode(StepJSONValue.self, from: Data(payload.utf8)).asObject else {
            throw Self.invalid("invalid_sse_event", "A Chat Completions event must be an object.")
        }
        try Self.checkError(root)
        if let value = root["usage"], value != .null { usage = try Self.tokens(value) }
        if root["choices"]?.asArray?.isEmpty == true { return [] }
        let choice = try Self.choice(root)
        let delta = choice["delta"]?.asObject ?? [:]
        guard finishReason == nil else { throw Self.invalid("events_after_terminal", "An assistant delta followed the finish reason.") }
        var events = [LanguageModelStepEvent]()
        for (key, value) in delta where value != .null {
            switch key {
            case "content", "refusal", "reasoning_content", "reasoning":
                guard let text = value.asString else { throw Self.invalid("unsupported_chat_delta", "A streamed text field must contain text.") }
                message[key] = .string((message[key]?.asString ?? "") + text)
                if key == "content" || key == "refusal" { events.append(.textDelta(text)) }
                else { events.append(.reasoningDelta(text)) }
            case "tool_calls":
                guard let fragments = value.asArray else { throw Self.invalid("invalid_function_call", "Tool-call deltas must be an array.") }
                for fragment in fragments {
                    guard var object = fragment.asObject, let number = object.removeValue(forKey: "index")?.asNumber,
                          let index = Int(exactly: number), (0..<1024).contains(index) else {
                        throw Self.invalid("invalid_call_index", "A tool-call delta has no valid source index.")
                    }
                    var call = calls[index] ?? [:]
                    for (field, item) in object where item != .null {
                        if field == "function", let function = item.asObject {
                            var collected = call[field]?.asObject ?? [:]
                            for (part, value) in function {
                                if (part == "name" || part == "arguments"), let text = value.asString {
                                    collected[part] = .string((collected[part]?.asString ?? "") + text)
                                } else { try Self.mergeAtomic(part, value, into: &collected) }
                            }
                            call[field] = .object(collected)
                        } else { try Self.mergeAtomic(field, item, into: &call) }
                    }
                    calls[index] = call
                }
            default: try Self.mergeAtomic(key, value, into: &message)
            }
        }
        if let reason = choice["finish_reason"]?.asString { finishReason = reason }
        return events
    }

    private static func mergeAtomic(_ key: String, _ value: StepJSONValue, into object: inout [String: StepJSONValue]) throws {
        guard object[key] == nil || object[key] == value else {
            throw invalid("unsupported_chat_delta", "An opaque provider field changed without a supported delta contract.")
        }
        object[key] = value
    }
    private static func choice(_ root: [String: StepJSONValue]) throws -> [String: StepJSONValue] {
        guard let values = root["choices"]?.asArray, values.count == 1, let value = values[0].asObject,
              value["index"]?.asInt == 0 else { throw invalid("invalid_chat_choices", "A model step requires exactly choice zero.") }
        return value
    }
    private static func checkError(_ root: [String: StepJSONValue]) throws {
        if let error = root["error"]?.asObject {
            let code = error["code"]?.asString ?? "response_failed"
            throw LanguageModelStepFailure(category: code == "context_length_exceeded" ? .context : .provider,
                code: code, message: error["message"]?.asString ?? "The provider failed the response.", stage: .finalization)
        }
    }
    private static func tokens(_ value: StepJSONValue?) throws -> StepTokenUsage? {
        guard let value, value != .null, let usage = value.asObject else { return nil }
        func count(_ value: StepJSONValue?) throws -> Int {
            guard let value, value != .null else { return 0 }
            guard let number = value.asNumber, let count = Int(exactly: number), (0...1_000_000_000).contains(count) else {
                throw invalid("invalid_usage", "The provider returned an invalid token count.")
            }
            return count
        }
        return .init(prompt: try count(usage["prompt_tokens"]), completion: try count(usage["completion_tokens"]),
            cachedInputTokens: try count(usage["prompt_tokens_details"]?.asObject?["cached_tokens"]),
            reasoningTokens: try count(usage["completion_tokens_details"]?.asObject?["reasoning_tokens"]))
    }
    private static func invalid(_ code: String, _ message: String) -> LanguageModelStepFailure {
        .init(category: .protocolViolation, code: code, message: message, stage: .streaming)
    }
}
