import Foundation

/// Preserve each original Part, including empty signed parts. Never merge thought signatures.
/// https://ai.google.dev/gemini-api/docs/generate-content/function-calling
public struct GeminiStepCodec {
    let providerID: String
    let modelID: String
    let stepID: String
    private var framing = StepSSEDecoder()
    private var parts = [StepJSONValue]()
    private var finishReason: String?
    private var usage: [String: StepJSONValue]?

    public init(providerID: String, modelID: String, stepID: String) {
        self.providerID = providerID; self.modelID = modelID; self.stepID = stepID
    }

    public static func requestBody(_ request: LanguageModelStepRequest, model: String, providerID: String, instructions: String) throws -> Data {
        var system = [StepJSONValue]()
        var contents = [StepJSONValue]()
        var results = [StepJSONValue]()
        var receivedCallIDs = Set<String>()
        func flushResults() {
            if !results.isEmpty {
                contents.append(.object(["role": .string("user"), "parts": .array(results)]))
                results.removeAll(keepingCapacity: true)
            }
        }
        for message in request.messages {
            if message.role == .system {
                if !message.text.isEmpty { system.append(.object(["text": .string(message.text)])) }
                continue
            }
            if message.role == .tool {
                guard let output = message.toolOutput else { throw invalid("missing_tool_output", "A tool message has no correlated result.") }
                let value = (try? JSONDecoder().decode(StepJSONValue.self, from: Data(output.content.utf8))) ?? .string(output.content)
                var result: [String: StepJSONValue] = ["name": .string(output.name),
                    "response": .object([output.isError == true ? "error" : "result": value])]
                if receivedCallIDs.contains(output.callId) { result["id"] = .string(output.callId) }
                results.append(.object(["functionResponse": .object(result)]))
                continue
            }
            flushResults()
            if message.role == .assistant, let continuation = message.continuation {
                guard continuation.providerId == providerID, continuation.modelId == model,
                      continuation.format == "gemini-content-v1", let content = continuation.content.asObject,
                      content["role"] == .string("model"), let previousParts = content["parts"]?.asArray else {
                    throw invalid("incompatible_continuation", "Provider continuation must be explicitly normalized before switching its provider/model.")
                }
                for part in previousParts {
                    if let id = part.asObject?["functionCall"]?.asObject?["id"]?.asString { receivedCallIDs.insert(id) }
                }
                if !previousParts.isEmpty { contents.append(continuation.content) }
                continue
            }
            var input = [StepJSONValue]()
            if !message.text.isEmpty { input.append(.object(["text": .string(message.text)])) }
            for image in message.images {
                guard let bytes = image.data, !image.mimeType.isEmpty else {
                    throw invalid("invalid_image", "Gemini inline image input requires loaded bytes and a MIME type.")
                }
                input.append(.object(["inlineData": .object(["mimeType": .string(image.mimeType), "data": .string(bytes.base64EncodedString())])]))
            }
            for call in message.toolCalls {
                let arguments = try JSONDecoder().decode(StepJSONValue.self, from: Data(call.rawArguments.utf8))
                guard arguments.asObject != nil else { throw invalid("invalid_function_call", "Function arguments must be an object.") }
                receivedCallIDs.insert(call.id)
                input.append(.object(["functionCall": .object(["id": .string(call.id), "name": .string(call.name), "args": arguments])]))
            }
            if !input.isEmpty { contents.append(.object(["role": .string(message.role == .assistant ? "model" : "user"), "parts": .array(input)])) }
        }
        flushResults()
        if system.isEmpty, !instructions.isEmpty { system = [.object(["text": .string(instructions)])] }
        var thinking: [String: StepJSONValue] = ["includeThoughts": .bool(true)]
        if let effort = request.reasoningEffort {
            guard [.low, .medium, .high].contains(effort) else {
                throw LanguageModelStepFailure(category: .unavailable, code: "unsupported_reasoning_effort",
                    message: "Gemini thinking levels support low, medium or high; select a compatible model and effort.", stage: .preparation)
            }
            thinking["thinkingLevel"] = .string(effort.rawValue.uppercased())
        }
        var body: [String: StepJSONValue] = ["contents": .array(contents), "generationConfig": .object([
            "maxOutputTokens": .number(Double(request.maximumOutputTokens)), "thinkingConfig": .object(thinking)])]
        if !system.isEmpty { body["systemInstruction"] = .object(["parts": .array(system)]) }
        if !request.tools.isEmpty {
            body["tools"] = .array([.object(["functionDeclarations": .array(request.tools.map { .object([
                "name": .string($0.name), "description": .string($0.description), "parametersJsonSchema": $0.parameters]) })])])
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(StepJSONValue.object(body))
    }

    public mutating func consume(_ data: Data) throws -> [LanguageModelStepEvent] {
        var events = [LanguageModelStepEvent]()
        for payload in try framing.consume(data) { events += try consumeRecord(Data(payload.utf8)) }
        return events
    }
    public mutating func consumeJSON(_ data: Data) throws { _ = try consumeRecord(data) }

    public mutating func finish() throws -> LanguageModelStepResponse {
        for payload in try framing.finish() { _ = try consumeRecord(Data(payload.utf8)) }
        guard let finishReason else {
            throw LanguageModelStepFailure(category: .transport, code: "stream_ended_before_final",
                message: "Gemini closed without a candidate finishReason.", retryable: true, stage: .streaming)
        }
        var text = ""
        var calls = [LanguageModelStepToolCall]()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        for part in parts {
            guard let object = part.asObject else { throw Self.invalid("invalid_content_part", "A Gemini part must be an object.") }
            if object["thought"]?.asBool != true { text += object["text"]?.asString ?? "" }
            if let call = object["functionCall"]?.asObject {
                guard let name = call["name"]?.asString, !name.isEmpty,
                      let arguments = call["args"], arguments.asObject != nil, call["partialArgs"] == nil,
                      call["willContinue"]?.asBool != true else {
                    throw Self.invalid("invalid_function_call", "Gemini returned an incomplete or unsupported function call.")
                }
                let id = call["id"]?.asString ?? "gemini-\(stepID)-\(calls.count)"
                guard !id.isEmpty else { throw Self.invalid("invalid_function_call", "Gemini returned an empty call ID.") }
                calls.append(.init(id: id, name: name, rawArguments: String(decoding: try encoder.encode(arguments), as: UTF8.self)))
            }
        }
        guard Set(calls.map(\.id)).count == calls.count else { throw Self.invalid("duplicate_call_id", "Gemini returned duplicate call IDs.") }
        let reason: LanguageModelStepResponse.StopReason
        switch finishReason {
        case "STOP": reason = calls.isEmpty ? .endTurn : .toolCalls
        case "MAX_TOKENS": reason = .outputLimit
        default: reason = .incomplete
        }
        let tokenUsage: StepTokenUsage?
        if let usage {
            let thinking = try Self.tokens(usage["thoughtsTokenCount"])
            tokenUsage = .init(prompt: try Self.tokens(usage["promptTokenCount"]),
                completion: try Self.tokens(usage["candidatesTokenCount"]) + thinking,
                cachedInputTokens: try Self.tokens(usage["cachedContentTokenCount"]), reasoningTokens: thinking)
        } else { tokenUsage = nil }
        return .init(text: text, toolCalls: calls, stopReason: reason, usage: tokenUsage,
            continuation: .init(providerId: providerID, modelId: modelID, format: "gemini-content-v1",
                content: .object(["role": .string("model"), "parts": .array(parts)])))
    }

    private mutating func consumeRecord(_ data: Data) throws -> [LanguageModelStepEvent] {
        guard let envelope = try JSONDecoder().decode(StepJSONValue.self, from: data).asObject else {
            throw Self.invalid("invalid_json_response", "A Gemini response must be an object.")
        }
        let root = envelope["response"]?.asObject ?? envelope
        if let error = root["error"]?.asObject ?? envelope["error"]?.asObject {
            throw LanguageModelStepFailure(category: .provider, code: error["status"]?.asString ?? "gemini_error",
                message: error["message"]?.asString ?? "Gemini generation failed.", stage: .streaming)
        }
        if let feedback = root["promptFeedback"]?.asObject, let reason = feedback["blockReason"]?.asString, !reason.isEmpty {
            throw LanguageModelStepFailure(category: .provider, code: "gemini_prompt_blocked",
                message: "Gemini blocked the request: " + reason, stage: .streaming)
        }
        if let value = root["usageMetadata"]?.asObject {
            usage = (usage ?? [:]).merging(value, uniquingKeysWith: { _, latest in latest })
        }
        let candidates = root["candidates"]?.asArray ?? []
        guard candidates.count <= 1 else { throw Self.invalid("multiple_candidates", "A step requests exactly one Gemini candidate.") }
        guard let candidate = candidates.first?.asObject else { return [] }
        guard candidate["index"] == nil || candidate["index"] == .number(0) else {
            throw Self.invalid("invalid_candidate_index", "Gemini returned an unexpected candidate index.")
        }
        guard finishReason == nil else { throw Self.invalid("events_after_terminal", "Gemini emitted candidate content after its finishReason.") }
        var events = [LanguageModelStepEvent]()
        if let content = candidate["content"]?.asObject {
            guard content["role"] == nil || content["role"] == .string("model"), let values = content["parts"]?.asArray else {
                throw Self.invalid("invalid_content", "Gemini candidate content requires model parts.")
            }
            for value in values {
                guard let part = value.asObject else { throw Self.invalid("invalid_content_part", "A Gemini part must be an object.") }
                if let text = part["text"]?.asString {
                    events.append(part["thought"]?.asBool == true ? .reasoningDelta(text) : .textDelta(text))
                }
                parts.append(value)
            }
        }
        if let reason = candidate["finishReason"]?.asString, !reason.isEmpty, reason != "FINISH_REASON_UNSPECIFIED" {
            finishReason = reason
        }
        return events
    }

    private static func tokens(_ value: StepJSONValue?) throws -> Int {
        guard let value, value != .null else { return 0 }
        guard let number = value.asNumber, let count = Int(exactly: number), (0...1_000_000_000).contains(count) else {
            throw invalid("invalid_usage", "Gemini returned an invalid token count.")
        }
        return count
    }
    private static func invalid(_ code: String, _ message: String) -> LanguageModelStepFailure {
        .init(category: .protocolViolation, code: code, message: message, stage: .streaming)
    }
}
