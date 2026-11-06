import Foundation

/// Responses SSE follows the official streaming-events contract; only a terminal response settles a step.
/// https://developers.openai.com/api/reference/resources/responses/streaming-events
public struct ResponsesStepCodec {
    let providerID: String
    let modelID: String
    private var framing = StepSSEDecoder()
    private var completedItems: [Int: StepJSONValue] = [:]
    private var terminal: [String: StepJSONValue]?

    public init(providerID: String, modelID: String) { self.providerID = providerID; self.modelID = modelID }

    public static func requestBody(_ request: LanguageModelStepRequest, model: String, providerID: String,
                            instructions: String, cacheKey: String, includeOutputLimit: Bool = false) throws -> Data {
        var input: [StepJSONValue] = []
        var system: [String] = []
        for message in request.messages {
            switch message.role {
            case .system: system.append(message.text)
            case .user:
                var content: [StepJSONValue] = []
                if !message.text.isEmpty { content.append(.object(["type": .string("input_text"), "text": .string(message.text)])) }
                for image in message.images {
                    let url: String
                    if let data = image.data, !image.mimeType.isEmpty { url = "data:\(image.mimeType);base64,\(data.base64EncodedString())" }
                    else if let remote = image.url, ["http", "https"].contains(remote.scheme?.lowercased() ?? "") { url = remote.absoluteString }
                    else { throw invalid("invalid_image", "Image input needs bytes/MIME type or an HTTP URL.") }
                    content.append(.object(["type": .string("input_image"), "image_url": .string(url)]))
                }
                input.append(.object(["role": .string("user"), "content": .array(content)]))
            case .assistant:
                if let continuation = message.continuation {
                    guard continuation.providerId == providerID, continuation.modelId == model,
                          continuation.format == "responses-v1", let items = continuation.content.asArray else {
                        throw invalid("incompatible_continuation", "Provider continuation must be explicitly normalized before switching its provider/model.")
                    }
                    input += items
                } else {
                    if !message.text.isEmpty { input.append(.object(["role": .string("assistant"), "content": .string(message.text)])) }
                    input += message.toolCalls.map { .object(["type": .string("function_call"), "call_id": .string($0.id),
                        "name": .string($0.name), "arguments": .string($0.rawArguments)]) }
                }
            case .tool:
                guard let output = message.toolOutput else { throw invalid("missing_tool_output", "A tool message has no correlated result.") }
                input.append(.object(["type": .string("function_call_output"), "call_id": .string(output.callId), "output": .string(output.content)]))
            }
        }
        var body: [String: StepJSONValue] = ["model": .string(model), "instructions": .string(system.isEmpty ? instructions : system.joined(separator: "\n\n")),
            "input": .array(input), "stream": .bool(true), "store": .bool(false),
            "include": .array([.string("reasoning.encrypted_content")]), "prompt_cache_key": .string(cacheKey)]
        if includeOutputLimit { body["max_output_tokens"] = .number(Double(request.maximumOutputTokens)) }
        if !request.tools.isEmpty {
            body["tools"] = .array(request.tools.map { .object(["type": .string("function"), "name": .string($0.name),
                "description": .string($0.description), "parameters": $0.parameters]) })
            body["parallel_tool_calls"] = .bool(request.parallelToolCalls)
        }
        if let effort = request.reasoningEffort { body["reasoning"] = .object(["effort": .string(effort.rawValue), "summary": .string("auto")]) }
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
        guard terminal == nil, let response = try JSONDecoder().decode(StepJSONValue.self, from: data).asObject else {
            throw Self.invalid("invalid_json_response", "The model response is not a complete JSON object.")
        }
        if response["status"]?.asString == "failed" || response["error"]?.asObject != nil {
            throw Self.providerFailure(response["error"]?.asObject ?? [:], stage: .finalization)
        }
        terminal = response
    }

    public mutating func finish() throws -> LanguageModelStepResponse {
        for payload in try framing.finish() { _ = try consumePayload(payload) }
        guard let terminal else {
            throw LanguageModelStepFailure(category: .transport, code: "stream_ended_before_final",
                message: "The stream closed without a terminal model response.", retryable: true, stage: .streaming)
        }
        let status = terminal["status"]?.asString
        let output: [StepJSONValue]
        if let final = terminal["output"]?.asArray { output = final }
        else {
            let indexes = completedItems.keys.sorted()
            guard indexes == Array(0..<indexes.count) else { throw Self.invalid("missing_output_items", "The response omitted part of its completed output.") }
            output = indexes.compactMap { completedItems[$0] }
        }
        var text: [String] = []
        var calls: [LanguageModelStepToolCall] = []
        var incomplete = status != "completed"
        for value in output {
            guard let item = value.asObject else { throw Self.invalid("invalid_output_item", "A model output item is not an object.") }
            if let state = item["status"]?.asString, state != "completed" { incomplete = true }
            switch item["type"]?.asString {
            case "message":
                for content in item["content"]?.asArray ?? [] {
                    if let value = content.asObject?["text"]?.asString { text.append(value) }
                    else if let value = content.asObject?["refusal"]?.asString { text.append(value) }
                }
            case "function_call":
                guard let id = item["call_id"]?.asString, !id.isEmpty, let name = item["name"]?.asString,
                      !name.isEmpty, let arguments = item["arguments"]?.asString else {
                    throw Self.invalid("invalid_function_call", "A completed function call is missing its ID, name or raw arguments.")
                }
                calls.append(.init(id: id, name: name, rawArguments: arguments))
            default: break // Keep every opaque item, in its original position, in continuation.
            }
        }
        let reason: LanguageModelStepResponse.StopReason
        if terminal["incomplete_details"]?.asObject?["reason"]?.asString == "max_output_tokens" { reason = .outputLimit }
        else if incomplete { reason = .incomplete }
        else { reason = calls.isEmpty ? .endTurn : .toolCalls }
        var usage: StepTokenUsage?
        if let value = terminal["usage"]?.asObject {
            usage = .init(prompt: try Self.tokens(value["input_tokens"]), completion: try Self.tokens(value["output_tokens"]),
                cachedInputTokens: try Self.tokens(value["input_tokens_details"]?.asObject?["cached_tokens"]),
                reasoningTokens: try Self.tokens(value["output_tokens_details"]?.asObject?["reasoning_tokens"]))
        }
        return .init(text: text.joined(separator: "\n"), toolCalls: calls, stopReason: reason, usage: usage,
            continuation: .init(providerId: providerID, modelId: modelID, format: "responses-v1", content: .array(output)))
    }

    private mutating func consumePayload(_ payload: String) throws -> [LanguageModelStepEvent] {
        if payload == "[DONE]" { return [] }
        guard let data = payload.data(using: .utf8), let event = try JSONDecoder().decode(StepJSONValue.self, from: data).asObject else {
            throw Self.invalid("invalid_sse_event", "An SSE event is not a JSON object.")
        }
        guard terminal == nil else { throw Self.invalid("events_after_terminal", "The provider emitted data after the terminal response.") }
        switch event["type"]?.asString {
        case "response.output_text.delta": return event["delta"]?.asString.map { [.textDelta($0)] } ?? []
        case "response.reasoning_summary_text.delta", "response.reasoning_text.delta":
            return event["delta"]?.asString.map { [.reasoningDelta($0)] } ?? []
        case "response.function_call_arguments.delta":
            if let number = event["output_index"]?.asNumber, let index = Int(exactly: number), index >= 0,
               let delta = event["delta"]?.asString { return [.toolCallDelta(index: index, name: nil, arguments: delta)] }
        case "response.output_item.done":
            if let number = event["output_index"]?.asNumber, let index = Int(exactly: number), index >= 0, let item = event["item"] {
                completedItems[index] = item
            }
        case "response.completed", "response.incomplete":
            guard let response = event["response"]?.asObject else { throw Self.invalid("missing_response", "The terminal event has no response.") }
            terminal = response
        case "response.failed", "error":
            let error = event["response"]?.asObject?["error"]?.asObject ?? event["error"]?.asObject ?? event
            throw Self.providerFailure(error, stage: .streaming)
        default: break
        }
        return []
    }

    private static func tokens(_ value: StepJSONValue?) throws -> Int {
        guard let value, value != .null else { return 0 }
        guard let number = value.asNumber, let count = Int(exactly: number), (0...1_000_000_000).contains(count) else {
            throw invalid("invalid_usage", "The provider returned an invalid token count.")
        }
        return count
    }

    private static func providerFailure(_ error: [String: StepJSONValue], stage: LanguageModelStepFailure.Stage) -> LanguageModelStepFailure {
        let code = error["code"]?.asString ?? "response_failed"
        return .init(category: code == "context_length_exceeded" ? .context : .provider,
            code: code, message: error["message"]?.asString ?? "The provider failed the response.", stage: stage)
    }

    private static func invalid(_ code: String, _ message: String) -> LanguageModelStepFailure {
        .init(category: .protocolViolation, code: code, message: message, stage: .streaming)
    }
}
