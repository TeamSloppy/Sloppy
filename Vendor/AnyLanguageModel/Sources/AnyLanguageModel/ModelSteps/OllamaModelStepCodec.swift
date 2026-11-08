import Foundation

/// Ollama chat JSON/NDJSON. Only done:true settles a model generation.
/// https://docs.ollama.com/api/chat
public struct OllamaStepCodec {
    let providerID: String
    let modelID: String
    let stepID: String
    private var bytes = Data()
    private var message: [String: StepJSONValue] = ["role": .string("assistant"), "content": .string("")]
    private var calls: [Int: StepJSONValue] = [:]
    private var terminal: [String: StepJSONValue]?

    public init(providerID: String, modelID: String, stepID: String) {
        self.providerID = providerID; self.modelID = modelID; self.stepID = stepID
    }

    public static func requestBody(_ request: LanguageModelStepRequest, model: String, providerID: String,
                            instructions: String, thinkingValues: [StepJSONValue]?) throws -> Data {
        var messages = [StepJSONValue]()
        if !request.messages.contains(where: { $0.role == .system }), !instructions.isEmpty {
            messages.append(.object(["role": .string("system"), "content": .string(instructions)]))
        }
        for message in request.messages {
            if message.role == .assistant, let continuation = message.continuation {
                guard continuation.providerId == providerID, continuation.modelId == model,
                      continuation.format == "ollama-chat-v1", continuation.content.asObject?["role"] == .string("assistant") else {
                    throw invalid("incompatible_continuation", "Provider continuation must be explicitly normalized before switching its provider/model.")
                }
                messages.append(continuation.content)
                continue
            }
            var value: [String: StepJSONValue] = ["role": .string(message.role.rawValue), "content": .string(message.text)]
            if !message.images.isEmpty {
                guard message.role == .user else { throw invalid("invalid_image", "Only user image input is supported.") }
                value["images"] = .array(try message.images.map { image in
                    guard let data = image.data else { throw invalid("invalid_image", "Ollama image input requires loaded image bytes.") }
                    return .string(data.base64EncodedString())
                })
            }
            if message.role == .assistant, !message.toolCalls.isEmpty {
                value["tool_calls"] = .array(try message.toolCalls.map { call in
                    let arguments = try JSONDecoder().decode(StepJSONValue.self, from: Data(call.rawArguments.utf8))
                    return .object(["type": .string("function"), "function": .object(["name": .string(call.name), "arguments": arguments])])
                })
            }
            if message.role == .tool {
                guard let output = message.toolOutput else { throw invalid("missing_tool_output", "A tool message has no correlated result.") }
                value["tool_name"] = .string(output.name)
                value["content"] = .string(output.content)
            }
            messages.append(.object(value))
        }
        var body: [String: StepJSONValue] = ["model": .string(model), "messages": .array(messages), "stream": .bool(true),
            "options": .object(["num_predict": .number(Double(request.maximumOutputTokens))])]
        if !request.tools.isEmpty {
            body["tools"] = .array(request.tools.map { .object(["type": .string("function"), "function": .object([
                "name": .string($0.name), "description": .string($0.description), "parameters": $0.parameters])]) })
        }
        if let effort = request.reasoningEffort {
            guard let values = thinkingValues else {
                throw LanguageModelStepFailure(category: .unavailable, code: "reasoning_controls_unavailable",
                    message: "Ollama has not declared this model's thinking controls.", stage: .preparation)
            }
            let level = StepJSONValue.string(effort.rawValue)
            if values.contains(level) { body["think"] = level }
            else if values.contains(.bool(true)) { body["think"] = .bool(true) }
            else {
                throw LanguageModelStepFailure(category: .unavailable, code: "unsupported_reasoning_effort",
                    message: "The selected effort is not declared by this Ollama model.", stage: .preparation)
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(StepJSONValue.object(body))
    }

    public mutating func consume(_ chunk: Data) throws -> [LanguageModelStepEvent] {
        bytes.append(chunk)
        var events = [LanguageModelStepEvent]()
        while let newline = bytes.firstIndex(of: 0x0A) {
            let line = Data(bytes[..<newline]); bytes.removeSubrange(...newline)
            if !line.isEmpty { events += try consumeRecord(line) }
        }
        guard bytes.count <= 8 * 1024 * 1024 else { throw Self.invalid("json_frame_too_large", "An NDJSON record exceeded 8 MiB.") }
        return events
    }
    public mutating func consumeJSON(_ data: Data) throws { _ = try consumeRecord(data) }

    public mutating func finish() throws -> LanguageModelStepResponse {
        if !bytes.isEmpty { _ = try consumeRecord(bytes); bytes.removeAll() }
        guard let terminal else {
            throw LanguageModelStepFailure(category: .transport, code: "stream_ended_before_final",
                message: "The Ollama stream closed without done:true.", retryable: true, stage: .streaming)
        }
        let indexes = calls.keys.sorted()
        guard indexes == Array(0..<indexes.count) else { throw Self.invalid("missing_tool_calls", "The response omitted a tool-call index.") }
        if !calls.isEmpty { message["tool_calls"] = .array(indexes.compactMap { calls[$0] }) }
        let argumentEncoder = JSONEncoder()
        argumentEncoder.outputFormatting = [.sortedKeys]
        let toolCalls = try indexes.map { index -> LanguageModelStepToolCall in
            guard let raw = calls[index]?.asObject, let function = raw["function"]?.asObject,
                  let name = function["name"]?.asString, !name.isEmpty, let arguments = function["arguments"] else {
                throw Self.invalid("invalid_function_call", "An Ollama tool call is missing its name or arguments.")
            }
            let id = raw["id"]?.asString ?? "ollama-\(stepID)-\(index)"
            guard !id.isEmpty else { throw Self.invalid("invalid_function_call", "An Ollama tool call has an empty ID.") }
            return .init(id: id, name: name, rawArguments: String(decoding: try argumentEncoder.encode(arguments), as: UTF8.self))
        }
        let reason: LanguageModelStepResponse.StopReason
        switch terminal["done_reason"]?.asString {
        case "length": reason = .outputLimit
        case "stop", nil: reason = toolCalls.isEmpty ? .endTurn : .toolCalls
        default: reason = .incomplete
        }
        let usage: StepTokenUsage?
        if terminal["prompt_eval_count"] != nil || terminal["eval_count"] != nil {
            usage = .init(prompt: try Self.count(terminal["prompt_eval_count"]), completion: try Self.count(terminal["eval_count"]),
                cachedInputTokens: try Self.count(terminal["prompt_eval_cached_count"]))
        } else { usage = nil }
        return .init(text: message["content"]?.asString ?? "", toolCalls: toolCalls, stopReason: reason, usage: usage,
            continuation: .init(providerId: providerID, modelId: modelID, format: "ollama-chat-v1", content: .object(message)))
    }

    private mutating func consumeRecord(_ data: Data) throws -> [LanguageModelStepEvent] {
        guard data.count <= 8 * 1024 * 1024 else { throw Self.invalid("json_frame_too_large", "An NDJSON record exceeded 8 MiB.") }
        guard terminal == nil else { throw Self.invalid("events_after_terminal", "Ollama emitted data after done:true.") }
        guard let root = try JSONDecoder().decode(StepJSONValue.self, from: data).asObject else {
            throw Self.invalid("invalid_json_response", "An Ollama response must be an object.")
        }
        if let error = root["error"]?.asString {
            throw LanguageModelStepFailure(category: .provider, code: "ollama_error", message: String(error.prefix(2048)), stage: .streaming)
        }
        guard let delta = root["message"]?.asObject, delta["role"] == .string("assistant"), root["done"]?.asBool != nil else {
            throw Self.invalid("invalid_chat_response", "An Ollama chat chunk requires an assistant message and done flag.")
        }
        var events = [LanguageModelStepEvent]()
        for (key, value) in delta where value != .null {
            switch key {
            case "content", "thinking":
                guard let text = value.asString else { throw Self.invalid("invalid_chat_delta", "A text delta must contain text.") }
                message[key] = .string((message[key]?.asString ?? "") + text)
                events.append(key == "content" ? .textDelta(text) : .reasoningDelta(text))
            case "tool_calls":
                guard let values = value.asArray else { throw Self.invalid("invalid_function_call", "Tool calls must be an array.") }
                for value in values {
                    guard let object = value.asObject, object["type"] == nil || object["type"] == .string("function"),
                          let function = object["function"]?.asObject else { throw Self.invalid("invalid_function_call", "A tool call needs a function.") }
                    let index: Int
                    if let raw = function["index"] {
                        guard let number = raw.asNumber, let parsed = Int(exactly: number), (0..<1024).contains(parsed) else {
                            throw Self.invalid("invalid_call_index", "An Ollama tool-call index is invalid.")
                        }
                        index = parsed
                    } else { index = calls.count }
                    guard calls[index] == nil else { throw Self.invalid("duplicate_call_index", "An Ollama tool-call index occurred twice.") }
                    calls[index] = value
                }
            default:
                guard message[key] == nil || message[key] == value else { throw Self.invalid("unsupported_chat_delta", "An opaque Ollama field changed without a delta contract.") }
                message[key] = value
            }
        }
        if root["done"]?.asBool == true { terminal = root }
        return events
    }
    private static func count(_ value: StepJSONValue?) throws -> Int {
        guard let value, value != .null else { return 0 }
        guard let number = value.asNumber, let count = Int(exactly: number), (0...1_000_000_000).contains(count) else {
            throw invalid("invalid_usage", "Ollama returned an invalid token count.")
        }
        return count
    }
    private static func invalid(_ code: String, _ message: String) -> LanguageModelStepFailure {
        .init(category: .protocolViolation, code: code, message: message, stage: .streaming)
    }
}
