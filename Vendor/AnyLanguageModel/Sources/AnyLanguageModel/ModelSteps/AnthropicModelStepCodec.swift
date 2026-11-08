import Foundation

/// Messages SSE is complete only after closed content blocks and message_stop.
/// https://platform.claude.com/docs/en/build-with-claude/streaming
public struct AnthropicStepCodec {
    let providerID: String
    let modelID: String
    private var framing = StepSSEDecoder()
    private var blocks: [Int: [String: StepJSONValue]] = [:]
    private var rawInputs: [Int: String] = [:]
    private var closed: Set<Int> = []
    private var started = false
    private var stopped = false
    private var stopReason: String?
    private var usage: [String: StepJSONValue] = [:]

    public init(providerID: String, modelID: String) { self.providerID = providerID; self.modelID = modelID }

    public static func requestBody(_ request: LanguageModelStepRequest, model: String, providerID: String, instructions: String) throws -> Data {
        var system = [StepJSONValue]()
        var messages = [StepJSONValue]()
        var results = [StepJSONValue]()
        func flushResults() {
            if !results.isEmpty {
                messages.append(.object(["role": .string("user"), "content": .array(results)]))
                results.removeAll(keepingCapacity: true)
            }
        }
        for message in request.messages {
            if message.role == .system {
                if !message.text.isEmpty { system.append(.object(["type": .string("text"), "text": .string(message.text)])) }
                continue
            }
            if message.role == .tool {
                guard let output = message.toolOutput else { throw invalid("missing_tool_output", "A tool message has no correlated result.") }
                var result: [String: StepJSONValue] = ["type": .string("tool_result"), "tool_use_id": .string(output.callId), "content": .string(output.content)]
                if let isError = output.isError { result["is_error"] = .bool(isError) }
                results.append(.object(result))
                continue
            }
            flushResults()
            if message.role == .assistant, let continuation = message.continuation {
                guard continuation.providerId == providerID, continuation.modelId == model,
                      continuation.format == "anthropic-message-v1", let content = continuation.content.asArray else {
                    throw invalid("incompatible_continuation", "Provider continuation must be explicitly normalized before switching its provider/model.")
                }
                if !content.isEmpty { messages.append(.object(["role": .string("assistant"), "content": .array(content)])) }
                continue
            }
            var content = [StepJSONValue]()
            if !message.text.isEmpty { content.append(.object(["type": .string("text"), "text": .string(message.text)])) }
            for image in message.images {
                let source: StepJSONValue
                if let data = image.data, !image.mimeType.isEmpty {
                    source = .object(["type": .string("base64"), "media_type": .string(image.mimeType), "data": .string(data.base64EncodedString())])
                } else if let url = image.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    source = .object(["type": .string("url"), "url": .string(url.absoluteString)])
                } else { throw invalid("invalid_image", "Image input needs bytes/MIME type or an HTTP URL.") }
                content.append(.object(["type": .string("image"), "source": source]))
            }
            for call in message.toolCalls {
                let input = try JSONDecoder().decode(StepJSONValue.self, from: Data(call.rawArguments.utf8))
                content.append(.object(["type": .string("tool_use"), "id": .string(call.id), "name": .string(call.name), "input": input]))
            }
            if !content.isEmpty { messages.append(.object(["role": .string(message.role == .assistant ? "assistant" : "user"), "content": .array(content)])) }
        }
        flushResults()
        if system.isEmpty, !instructions.isEmpty { system = [.object(["type": .string("text"), "text": .string(instructions)])] }
        var body: [String: StepJSONValue] = ["model": .string(model), "max_tokens": .number(Double(request.maximumOutputTokens)),
            "messages": .array(messages), "stream": .bool(true)]
        if !system.isEmpty { body["system"] = .array(system) }
        if !request.tools.isEmpty {
            body["tools"] = .array(request.tools.map { .object(["name": .string($0.name), "description": .string($0.description), "input_schema": $0.parameters]) })
            body["tool_choice"] = .object(["type": .string("auto"), "disable_parallel_tool_use": .bool(!request.parallelToolCalls)])
        }
        if let effort = request.reasoningEffort {
            body["thinking"] = .object(["type": .string("adaptive")])
            body["output_config"] = .object(["effort": .string(effort.rawValue)])
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(StepJSONValue.object(body))
    }

    public mutating func consume(_ data: Data) throws -> [LanguageModelStepEvent] {
        var events = [LanguageModelStepEvent]()
        for payload in try framing.consume(data) { events += try consumePayload(payload) }
        return events
    }
    public mutating func consumeJSON(_ data: Data) throws {
        guard !started, let root = try JSONDecoder().decode(StepJSONValue.self, from: data).asObject else {
            throw Self.invalid("invalid_json_response", "An Anthropic response must be one complete message.")
        }
        try Self.checkError(root)
        try Self.validateContinuationMetadata(root)
        guard root["role"] == .string("assistant"), let content = root["content"]?.asArray,
              let reason = root["stop_reason"]?.asString else { throw Self.invalid("invalid_message", "The response lacks its complete assistant message or stop reason.") }
        for (index, value) in content.enumerated() {
            guard let block = value.asObject else { throw Self.invalid("invalid_content_block", "A content block must be an object.") }
            blocks[index] = block; closed.insert(index)
        }
        usage = root["usage"]?.asObject ?? [:]
        stopReason = reason; started = true; stopped = true
    }
    public mutating func finish() throws -> LanguageModelStepResponse {
        for payload in try framing.finish() { _ = try consumePayload(payload) }
        let indexes = blocks.keys.sorted()
        guard started, stopped, let stopReason, closed == Set(indexes), indexes == Array(0..<indexes.count) else {
            throw LanguageModelStepFailure(category: .transport, code: "stream_ended_before_final",
                message: "The Anthropic stream closed without a complete message_stop.", retryable: true, stage: .streaming)
        }
        var text = [String]()
        var calls = [LanguageModelStepToolCall]()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        for index in indexes {
            guard var block = blocks[index] else { throw Self.invalid("missing_content_block", "A content block disappeared.") }
            if block["type"] == .string("text"), let value = block["text"]?.asString { text.append(value) }
            if block["type"] == .string("tool_use") {
                guard let id = block["id"]?.asString, !id.isEmpty, let name = block["name"]?.asString, !name.isEmpty else {
                    throw Self.invalid("invalid_function_call", "A tool-use block is missing its ID or name.")
                }
                let raw: String
                if let fragments = rawInputs[index] {
                    raw = fragments
                    // Never fabricate an empty input when a completed provider block has invalid JSON.
                    block["input"] = try JSONDecoder().decode(StepJSONValue.self, from: Data(raw.utf8))
                    blocks[index] = block
                } else {
                    guard let input = block["input"] else { throw Self.invalid("invalid_function_call", "A tool-use block is missing its input.") }
                    raw = String(decoding: try encoder.encode(input), as: UTF8.self)
                }
                calls.append(.init(id: id, name: name, rawArguments: raw))
            }
        }
        let reason: LanguageModelStepResponse.StopReason
        switch stopReason {
        case "end_turn", "stop_sequence", "refusal": reason = .endTurn
        case "tool_use": reason = .toolCalls
        case "max_tokens": reason = .outputLimit
        default: reason = .incomplete
        }
        let input = try Self.count(usage["input_tokens"])
        let cached = try Self.count(usage["cache_read_input_tokens"])
        let created = try Self.count(usage["cache_creation_input_tokens"])
        let tokens: StepTokenUsage? = usage.isEmpty ? nil : .init(prompt: input + cached + created,
            completion: try Self.count(usage["output_tokens"]), cachedInputTokens: cached, cacheCreationInputTokens: created)
        return .init(text: text.joined(separator: "\n"), toolCalls: calls, stopReason: reason, usage: tokens,
            continuation: .init(providerId: providerID, modelId: modelID, format: "anthropic-message-v1",
                content: .array(indexes.compactMap { blocks[$0].map(StepJSONValue.object) })))
    }

    private mutating func consumePayload(_ payload: String) throws -> [LanguageModelStepEvent] {
        guard let event = try JSONDecoder().decode(StepJSONValue.self, from: Data(payload.utf8)).asObject else { throw Self.invalid("invalid_sse_event", "An Anthropic event must be an object.") }
        guard !stopped else { throw Self.invalid("events_after_terminal", "The provider emitted data after message_stop.") }
        try Self.checkError(event)
        switch event["type"]?.asString {
        case "message_start":
            guard !started, let message = event["message"]?.asObject, message["role"] == .string("assistant"),
                  message["content"]?.asArray?.isEmpty == true else { throw Self.invalid("invalid_message_start", "The stream must start one empty assistant message.") }
            try Self.validateContinuationMetadata(message)
            started = true; usage = message["usage"]?.asObject ?? [:]
        case "content_block_start":
            let index = try Self.index(event)
            guard started, blocks[index] == nil, let block = event["content_block"]?.asObject else { throw Self.invalid("invalid_content_block", "A content block started twice or before its message.") }
            blocks[index] = block
        case "content_block_delta":
            let index = try Self.index(event)
            guard started, !closed.contains(index), var block = blocks[index], let delta = event["delta"]?.asObject else { throw Self.invalid("invalid_content_delta", "A delta has no open content block.") }
            switch delta["type"]?.asString {
            case "text_delta", "thinking_delta", "signature_delta":
                let field = delta["type"] == .string("text_delta") ? "text" : (delta["type"] == .string("thinking_delta") ? "thinking" : "signature")
                let expectedType = field == "text" ? "text" : "thinking"
                guard block["type"] == .string(expectedType), let value = delta[field]?.asString else {
                    throw Self.invalid("invalid_content_delta", "A content delta does not match its block type or has no text.")
                }
                block[field] = .string((block[field]?.asString ?? "") + value); blocks[index] = block
                if field == "text" { return [.textDelta(value)] }
                if field == "thinking" { return [.reasoningDelta(value)] }
            case "input_json_delta":
                guard block["type"] == .string("tool_use"), let value = delta["partial_json"]?.asString else { throw Self.invalid("invalid_content_delta", "A JSON delta requires a tool-use block and raw fragment.") }
                rawInputs[index, default: ""] += value
            default: throw Self.invalid("unsupported_content_delta", "An unsupported content delta cannot be discarded safely.")
            }
        case "content_block_stop":
            let index = try Self.index(event)
            guard blocks[index] != nil, !closed.contains(index) else { throw Self.invalid("invalid_content_stop", "A content block closed without a matching open block.") }
            closed.insert(index)
        case "message_delta":
            guard started else { throw Self.invalid("invalid_message_delta", "A message delta arrived before message_start.") }
            try Self.validateContinuationMetadata(event)
            if let delta = event["delta"]?.asObject { try Self.validateContinuationMetadata(delta) }
            if let reason = event["delta"]?.asObject?["stop_reason"]?.asString { stopReason = reason }
            for (key, value) in event["usage"]?.asObject ?? [:] { usage[key] = value }
        case "message_stop": stopped = true
        default: break // Ping/unknown metadata events do not grant a terminal response or execute work.
        }
        return []
    }
    private static func index(_ event: [String: StepJSONValue]) throws -> Int {
        guard let number = event["index"]?.asNumber, let index = Int(exactly: number), (0..<1024).contains(index) else {
            throw invalid("invalid_content_index", "A content block has no valid source index.")
        }
        return index
    }
    private static func checkError(_ object: [String: StepJSONValue]) throws {
        guard let error = object["error"]?.asObject else { return }
        let code = error["type"]?.asString ?? error["code"]?.asString ?? "response_failed"
        throw LanguageModelStepFailure(category: code == "authentication_error" ? .authentication : .provider,
            code: code, message: String((error["message"]?.asString ?? "The provider failed the response.").prefix(2048)),
            retryable: ["overloaded_error", "rate_limit_error"].contains(code), stage: .streaming)
    }
    private static func validateContinuationMetadata(_ object: [String: StepJSONValue]) throws {
        if let transforms = object["input_transformations"], transforms != .null, transforms != .array([]) {
            throw invalid("unsupported_continuation", "This binding-control extension requires a compatible continuation adapter.")
        }
    }
    private static func count(_ value: StepJSONValue?) throws -> Int {
        guard let value, value != .null else { return 0 }
        guard let number = value.asNumber, let count = Int(exactly: number), (0...1_000_000_000).contains(count) else { throw invalid("invalid_usage", "The provider returned an invalid token count.") }
        return count
    }
    private static func invalid(_ code: String, _ message: String) -> LanguageModelStepFailure {
        .init(category: .protocolViolation, code: code, message: message, stage: .streaming)
    }
}
