import AnyLanguageModel
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// OpenAI OAuth model implementation.
public struct OpenAIOAuthModel: LanguageModel {
    public typealias UnavailableReason = String
    public typealias CustomGenerationOptions = Never

    public static let defaultBaseURL = URL(string: "https://chatgpt.com/backend-api/codex")!

    private let httpSession: URLSession
    private let baseURL: URL
    private let bearerTokenProvider: @Sendable () -> String
    private let bearerTokenRefresh: (@Sendable () async throws -> Void)?
    private let bearerTokenForceRefresh: (@Sendable () async throws -> Void)?
    private let modelName: String
    private let accountId: String?
    private let instructions: String
    let reasoningCapture: ReasoningContentCapture?
    let tokenUsageCapture: TokenUsageCapture?
    /// Controls `parallel_tool_calls`; flips to sequential after a batch arrives with unusable arguments.
    public let parallelToolCalls: ParallelToolCallsControl
    /// Narrows `prompt_cache_key` to one conversation so its requests keep landing on the cache that holds their prefix.
    private let promptCacheScope: String?

    public var availability: Availability<String> {
        guard !bearerTokenProvider().isEmpty else {
            return .unavailable("Bearer token is required")
        }
        return .available
    }

    public init(
        baseURL: URL = OpenAIOAuthModel.defaultBaseURL,
        bearerToken: String,
        model: String,
        accountId: String? = nil,
        instructions: String = "You are a helpful assistant.",
        reasoningCapture: ReasoningContentCapture? = nil,
        tokenUsageCapture: TokenUsageCapture? = nil,
        parallelToolCalls: ParallelToolCallsControl = ParallelToolCallsControl(),
        session: URLSession = .shared
    ) {
        self.httpSession = session
        self.baseURL = baseURL
        self.bearerTokenProvider = { bearerToken }
        self.bearerTokenRefresh = nil
        self.bearerTokenForceRefresh = nil
        self.modelName = model
        self.accountId = accountId
        self.instructions = instructions
        self.reasoningCapture = reasoningCapture
        self.tokenUsageCapture = tokenUsageCapture
        self.parallelToolCalls = parallelToolCalls
        self.promptCacheScope = nil
    }

    public init(
        baseURL: URL = OpenAIOAuthModel.defaultBaseURL,
        bearerTokenProvider: @escaping @Sendable () -> String,
        bearerTokenRefresh: (@Sendable () async throws -> Void)? = nil,
        bearerTokenForceRefresh: (@Sendable () async throws -> Void)? = nil,
        model: String,
        accountId: String? = nil,
        instructions: String = "You are a helpful assistant.",
        reasoningCapture: ReasoningContentCapture? = nil,
        tokenUsageCapture: TokenUsageCapture? = nil,
        parallelToolCalls: ParallelToolCallsControl = ParallelToolCallsControl(),
        promptCacheScope: String? = nil,
        session: URLSession = .shared
    ) {
        self.httpSession = session
        self.baseURL = baseURL
        self.bearerTokenProvider = bearerTokenProvider
        self.bearerTokenRefresh = bearerTokenRefresh
        self.bearerTokenForceRefresh = bearerTokenForceRefresh
        self.modelName = model
        self.accountId = accountId
        self.instructions = instructions
        self.reasoningCapture = reasoningCapture
        self.tokenUsageCapture = tokenUsageCapture
        self.parallelToolCalls = parallelToolCalls
        self.promptCacheScope = promptCacheScope
    }
}

// MARK: - LanguageModel Implementation

extension OpenAIOAuthModel {
    public func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        let conversion = convertToolsToAPI(session.tools)
        let transcript = session.transcript
        let requestBody = try buildRequestBody(transcript: transcript, options: options, tools: conversion.definitions)
        let result = try await collectStreamingResponseWithTools(body: requestBody)
        noteMalformedCalls(result.functionCalls)

        var transcriptEntries: [Transcript.Entry] = []
        var text = result.text
        var pendingCalls = result.functionCalls

        while !pendingCalls.isEmpty, let delegate = session.toolExecutionDelegate {
            let toolCalls = pendingCalls.map { call in
                Transcript.ToolCall(
                    id: call.callId,
                    toolName: conversion.nameMap[call.name] ?? call.name,
                    arguments: parseGeneratedContent(call.arguments)
                )
            }
            await delegate.didGenerateToolCalls(toolCalls, in: session)

            var toolOutputs: [(callId: String, output: String)] = []
            var shouldStop = false
            for (call, toolCall) in zip(pendingCalls, toolCalls) {
                let decision = await delegate.toolCallDecision(for: toolCall, in: session)
                switch decision {
                case .stop:
                    shouldStop = true
                case .execute:
                    continue
                case .provideOutput(let segments):
                    let outputText = segments.compactMap { segment -> String? in
                        if case .text(let t) = segment { return t.content }
                        return nil
                    }.joined(separator: "\n")
                    let output = Transcript.ToolOutput(id: toolCall.id, toolName: toolCall.toolName, segments: segments)
                    await delegate.didExecuteToolCall(toolCall, output: output, in: session)
                    toolOutputs.append((callId: call.callId, output: outputText))
                    transcriptEntries.append(.toolCalls(Transcript.ToolCalls([toolCall])))
                    transcriptEntries.append(.toolOutput(output))
                }
                if shouldStop {
                    break
                }
            }
            if shouldStop {
                break
            }

            let followUp = try buildFollowUpRequestBody(
                transcript: transcript,
                accumulatedEntries: transcriptEntries,
                functionCalls: pendingCalls,
                toolOutputs: toolOutputs,
                options: options,
                tools: conversion.definitions
            )

            let next = try await collectStreamingResponseWithTools(body: followUp)
            noteMalformedCalls(next.functionCalls)
            text = next.text
            pendingCalls = next.functionCalls
        }

        let decoded = try decodeResponseText(text, generating: type)
        return LanguageModelSession.Response(
            content: decoded.content,
            rawContent: decoded.rawContent,
            transcriptEntries: ArraySlice(transcriptEntries)
        )
    }

    func decodeResponseText<Content: Generable>(
        _ text: String,
        generating type: Content.Type
    ) throws -> (content: Content, rawContent: GeneratedContent) {
        let rawContent = type == String.self ? GeneratedContent(text) : try GeneratedContent(json: text)
        return (try type.init(rawContent), rawContent)
    }

    public func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        let transcript = session.transcript
        let stream = AsyncThrowingStream<LanguageModelSession.ResponseStream<Content>.Snapshot, Error> { continuation in
            let task = Task {
                do {
                    let conversion = convertToolsToAPI(session.tools)
                    let requestBody = try buildRequestBody(transcript: transcript, options: options, tools: conversion.definitions)
                    let result = try await performStreamingRequestWithTools(
                        body: requestBody,
                        continuation: continuation,
                        contentType: type
                    )

                    noteMalformedCalls(result.functionCalls)
                    var pendingCalls = result.functionCalls
                    var accumulatedEntries: [Transcript.Entry] = []

                    while !pendingCalls.isEmpty, let delegate = session.toolExecutionDelegate {
                        let toolCalls = pendingCalls.map { call in
                            Transcript.ToolCall(
                                id: call.callId,
                                toolName: conversion.nameMap[call.name] ?? call.name,
                                arguments: parseGeneratedContent(call.arguments)
                            )
                        }
                        await delegate.didGenerateToolCalls(toolCalls, in: session)

                        var toolOutputs: [(callId: String, output: String)] = []
                        var shouldStop = false
                        for (call, toolCall) in zip(pendingCalls, toolCalls) {
                            let decision = await delegate.toolCallDecision(for: toolCall, in: session)
                            switch decision {
                            case .stop:
                                shouldStop = true
                            case .execute:
                                continue
                            case .provideOutput(let segments):
                                let outputText = segments.compactMap { segment -> String? in
                                    if case .text(let t) = segment { return t.content }
                                    return nil
                                }.joined(separator: "\n")
                                let output = Transcript.ToolOutput(
                                    id: toolCall.id, toolName: toolCall.toolName, segments: segments
                                )
                                await delegate.didExecuteToolCall(toolCall, output: output, in: session)
                                toolOutputs.append((callId: call.callId, output: outputText))
                                accumulatedEntries.append(.toolCalls(Transcript.ToolCalls([toolCall])))
                                accumulatedEntries.append(.toolOutput(output))
                            }
                            if shouldStop {
                                break
                            }
                        }
                        if shouldStop {
                            break
                        }

                        let followUp = try buildFollowUpRequestBody(
                            transcript: transcript,
                            accumulatedEntries: accumulatedEntries,
                            functionCalls: pendingCalls,
                            toolOutputs: toolOutputs,
                            options: options,
                            tools: conversion.definitions
                        )
                        let next = try await performStreamingRequestWithTools(
                            body: followUp,
                            continuation: continuation,
                            contentType: type
                        )
                        noteMalformedCalls(next.functionCalls)
                        pendingCalls = next.functionCalls
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
        return LanguageModelSession.ResponseStream(stream: stream)
    }
}

// MARK: - HTTP Client

private extension OpenAIOAuthModel {
    typealias FunctionCall = ResponsesFunctionCall

    struct UsageInfo {
        var inputTokens: Int
        var outputTokens: Int
        var cachedInputTokens: Int
        var reasoningTokens: Int
    }

    struct StreamResult {
        var text: String
        var functionCalls: [FunctionCall]
        var responseId: String?
        var usage: UsageInfo?
    }

    var responsesEndpoint: URL {
        baseURL.appendingPathComponent("responses")
    }

    func buildHTTPRequest(body: Data) async throws -> URLRequest {
        try await bearerTokenRefresh?()
        let bearerToken = bearerTokenProvider()
        var request = URLRequest(url: responsesEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        if let accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        for (name, value) in affinityHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = body
        return request
    }

    func collectStreamingResponseWithTools(body: Data, retryAfterInvalidToken: Bool = true) async throws -> StreamResult {
        let request = try await buildHTTPRequest(body: body)

        #if canImport(FoundationNetworking)
        let (asyncBytes, response) = try await httpSession.linuxBytes(for: request)
        #else
        let (asyncBytes, response) = try await httpSession.bytes(for: request)
        #endif

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }

        guard 200...299 ~= httpResponse.statusCode else {
            var errorText = ""
            for try await line in asyncBytes.lines {
                errorText += line
            }
            let error = classifyHTTPError(statusCode: httpResponse.statusCode, body: errorText)
            if retryAfterInvalidToken, case .invalidToken = error, let bearerTokenForceRefresh {
                try await bearerTokenForceRefresh()
                return try await collectStreamingResponseWithTools(body: body, retryAfterInvalidToken: false)
            }
            throw error.surfaced
        }

        var accumulated = ""
        var functionCallAccumulator = ResponsesFunctionCallAccumulator()
        var responseId: String?
        var usage: UsageInfo?

        for try await line in asyncBytes.lines {
            if let delta = parseSSEOutputDelta(line) {
                accumulated += delta
            } else if let reasoning = parseSSEReasoningDelta(line) {
                reasoningCapture?.append(reasoning)
            } else if functionCallAccumulator.consume(line: line) {
                continue
            } else if let completed = parseSSEResponseCompleted(line) {
                responseId = completed.responseId
                usage = UsageInfo(
                    inputTokens: completed.inputTokens,
                    outputTokens: completed.outputTokens,
                    cachedInputTokens: completed.cachedInputTokens,
                    reasoningTokens: completed.reasoningTokens
                )
            }
        }

        if let usage {
            tokenUsageCapture?.store(
                promptTokens: usage.inputTokens,
                completionTokens: usage.outputTokens,
                cachedInputTokens: usage.cachedInputTokens,
                reasoningTokens: usage.reasoningTokens
            )
        }

        return StreamResult(text: accumulated, functionCalls: functionCallAccumulator.calls, responseId: responseId, usage: usage)
    }

    func performStreamingRequestWithTools<Content>(
        body: Data,
        continuation: AsyncThrowingStream<LanguageModelSession.ResponseStream<Content>.Snapshot, Error>.Continuation,
        contentType: Content.Type,
        retryAfterInvalidToken: Bool = true
    ) async throws -> StreamResult where Content: Generable {
        let request = try await buildHTTPRequest(body: body)

        #if canImport(FoundationNetworking)
        let (asyncBytes, response) = try await httpSession.linuxBytes(for: request)
        #else
        let (asyncBytes, response) = try await httpSession.bytes(for: request)
        #endif

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }

        guard 200...299 ~= httpResponse.statusCode else {
            var errorText = ""
            for try await line in asyncBytes.lines {
                errorText += line
            }
            let error = classifyHTTPError(statusCode: httpResponse.statusCode, body: errorText)
            if retryAfterInvalidToken, case .invalidToken = error, let bearerTokenForceRefresh {
                try await bearerTokenForceRefresh()
                return try await performStreamingRequestWithTools(
                    body: body,
                    continuation: continuation,
                    contentType: contentType,
                    retryAfterInvalidToken: false
                )
            }
            throw error.surfaced
        }

        var accumulated = ""
        var functionCallAccumulator = ResponsesFunctionCallAccumulator()
        var responseId: String?
        var usage: UsageInfo?

        for try await line in asyncBytes.lines {
            if let delta = parseSSEOutputDelta(line) {
                accumulated += delta
                if Content.self == String.self {
                    let snapshot = LanguageModelSession.ResponseStream<Content>.Snapshot(
                        content: accumulated as! Content.PartiallyGenerated,
                        rawContent: GeneratedContent(accumulated)
                    )
                    continuation.yield(snapshot)
                }
            } else if let reasoning = parseSSEReasoningDelta(line) {
                reasoningCapture?.append(reasoning)
            } else if functionCallAccumulator.consume(line: line) {
                continue
            } else if let completed = parseSSEResponseCompleted(line) {
                responseId = completed.responseId
                usage = UsageInfo(
                    inputTokens: completed.inputTokens,
                    outputTokens: completed.outputTokens,
                    cachedInputTokens: completed.cachedInputTokens,
                    reasoningTokens: completed.reasoningTokens
                )
            }
        }

        if let usage {
            tokenUsageCapture?.store(
                promptTokens: usage.inputTokens,
                completionTokens: usage.outputTokens,
                cachedInputTokens: usage.cachedInputTokens,
                reasoningTokens: usage.reasoningTokens
            )
        }

        return StreamResult(text: accumulated, functionCalls: functionCallAccumulator.calls, responseId: responseId, usage: usage)
    }

    func classifyHTTPError(statusCode: Int, body: String) -> OpenAIError {
        if let data = body.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = obj["detail"] as? String {
            if statusCode == 401 {
                return .invalidToken(detail)
            }
            if statusCode == 400, detail.contains("model"), detail.contains("is not supported") {
                return .modelNotSupported(detail)
            }
            return .httpError(statusCode, detail)
        }
        if statusCode == 401 {
            return .invalidToken("OAuth token is invalid or expired")
        } else if statusCode == 403 {
            return .invalidToken("OAuth token does not have required permissions")
        }
        return .httpError(statusCode, body.isEmpty ? "Request failed" : body)
    }
}

extension OpenAIOAuthModel {
    func buildHTTPRequestForTesting(body: Data) async throws -> URLRequest {
        try await buildHTTPRequest(body: body)
    }

    func promptCacheKeyForTesting() -> String { promptCacheKey() }

    var affinityHeadersForTesting: [String: String] { affinityHeaders }

    func buildRequestBodyForTesting(
        transcript: Transcript,
        options: GenerationOptions,
        tools: [[String: Any]] = []
    ) throws -> Data {
        try buildRequestBody(transcript: transcript, options: options, tools: tools)
    }

    func buildFollowUpRequestBodyForTesting(
        transcript: Transcript,
        accumulatedEntries: [Transcript.Entry],
        functionCalls: [ResponsesFunctionCall],
        toolOutputs: [(callId: String, output: String)]
    ) throws -> Data {
        try buildFollowUpRequestBody(
            transcript: transcript,
            accumulatedEntries: accumulatedEntries,
            functionCalls: functionCalls,
            toolOutputs: toolOutputs,
            options: GenerationOptions(),
            tools: []
        )
    }

    func classifyHTTPErrorForTesting(statusCode: Int, body: String) -> OpenAIError {
        classifyHTTPError(statusCode: statusCode, body: body)
    }

    func noteMalformedCallsForTesting(_ calls: [ResponsesFunctionCall]) {
        noteMalformedCalls(calls)
    }
}

// MARK: - Transcript Conversion

extension OpenAIOAuthModel {
    func transcriptToResponsesInput(_ transcript: Transcript) -> [[String: Any]] {
        let toolOutputIDs = Set(transcript.compactMap { entry -> String? in
            if case .toolOutput(let output) = entry {
                return output.id
            }
            return nil
        })
        var emittedToolCallIDs = Set<String>()
        var items: [[String: Any]] = []
        for entry in transcript {
            switch entry {
            case .instructions:
                break
            case .prompt(let prompt):
                let content: [[String: Any]] = prompt.segments.compactMap { segment in
                    switch segment {
                    case let .text(text): return ["type": "input_text", "text": text.content]
                    case let .image(image):
                        let url: String
                        switch image.source {
                        case let .data(data, mimeType): url = "data:\(mimeType);base64,\(data.base64EncodedString())"
                        case let .url(value): url = value.absoluteString
                        }
                        return ["type": "input_image", "image_url": url, "detail": "auto"]
                    default: return nil
                    }
                }
                items.append(["type": "message", "role": "user", "content": content])
            case .response(let response):
                let text = response.segments.compactMap { segment -> String? in
                    if case .text(let t) = segment { return t.content }
                    return nil
                }.joined(separator: "\n")
                if !text.isEmpty {
                    items.append([
                        "type": "message",
                        "role": "assistant",
                        "content": [["type": "output_text", "text": text]]
                    ])
                }
            case .toolCalls(let toolCalls):
                for call in toolCalls {
                    guard toolOutputIDs.contains(call.id) else {
                        continue
                    }
                    let argumentsJSON: String
                    if let data = try? JSONEncoder().encode(call.arguments),
                       let jsonString = String(data: data, encoding: .utf8),
                       ResponsesFunctionCallAccumulator.isJSONObject(jsonString) {
                        argumentsJSON = jsonString
                    } else {
                        argumentsJSON = "{}"
                    }
                    let sanitized = ModelToolNameSanitizer.sanitizeName(call.toolName)
                    items.append([
                        "type": "function_call",
                        "call_id": call.id,
                        "name": sanitized,
                        "arguments": argumentsJSON
                    ])
                    emittedToolCallIDs.insert(call.id)
                }
            case .toolOutput(let output):
                guard emittedToolCallIDs.contains(output.id) else {
                    continue
                }
                let text = output.segments.compactMap { segment -> String? in
                    if case .text(let t) = segment { return t.content }
                    return nil
                }.joined(separator: "\n")
                items.append([
                    "type": "function_call_output",
                    "call_id": output.id,
                    "output": text
                ])
            }
        }
        return items
    }
}

// MARK: - Request Building

private extension OpenAIOAuthModel {
    func responseInstructions(from transcript: Transcript) -> String {
        let sessionInstructions = transcript.compactMap { entry -> String? in
            guard case .instructions(let entry) = entry else { return nil }
            return entry.segments.compactMap { segment -> String? in
                guard case .text(let text) = segment else { return nil }
                return text.content
            }.joined(separator: "\n")
        }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return sessionInstructions.isEmpty ? instructions : sessionInstructions.joined(separator: "\n")
    }

    func buildRequestBody(
        transcript: Transcript,
        options: GenerationOptions,
        tools: [[String: Any]]
    ) throws -> Data {
        var body: [String: Any] = [
            "model": modelName,
            "instructions": responseInstructions(from: transcript),
            "input": transcriptToResponsesInput(transcript),
            "stream": true,
            "store": false
        ]
        if !tools.isEmpty {
            body["tools"] = tools
            body["parallel_tool_calls"] = parallelToolCalls.isEnabled
        }
        if let temperature = options.temperature {
            body["temperature"] = temperature
        }
        if reasoningCapture != nil {
            body["reasoning"] = ["summary": "auto"]
        }
        applyPromptCacheHints(to: &body)
        return try JSONSerialization.data(withJSONObject: body)
    }

    func buildFollowUpRequestBody(
        transcript: Transcript,
        accumulatedEntries: [Transcript.Entry],
        functionCalls: [FunctionCall],
        toolOutputs: [(callId: String, output: String)],
        options: GenerationOptions,
        tools: [[String: Any]]
    ) throws -> Data {
        var inputItems = transcriptToResponsesInput(transcript)

        for entry in accumulatedEntries {
            switch entry {
            case .toolCalls(let toolCalls):
                for call in toolCalls {
                    let argumentsJSON: String
                    if let data = try? JSONEncoder().encode(call.arguments),
                       let jsonString = String(data: data, encoding: .utf8),
                       ResponsesFunctionCallAccumulator.isJSONObject(jsonString) {
                        argumentsJSON = jsonString
                    } else {
                        argumentsJSON = "{}"
                    }
                    let sanitized = ModelToolNameSanitizer.sanitizeName(call.toolName)
                    inputItems.append([
                        "type": "function_call",
                        "call_id": call.id,
                        "name": sanitized,
                        "arguments": argumentsJSON
                    ])
                }
            case .toolOutput(let output):
                let text = output.segments.compactMap { segment -> String? in
                    if case .text(let t) = segment { return t.content }
                    return nil
                }.joined(separator: "\n")
                inputItems.append([
                    "type": "function_call_output",
                    "call_id": output.id,
                    "output": text
                ])
            default:
                break
            }
        }

        let replayedCallIDs = Set(accumulatedEntries.flatMap { entry -> [String] in
            if case .toolCalls(let toolCalls) = entry { return toolCalls.map(\.id) }
            return []
        })
        let replayedOutputIDs = Set(accumulatedEntries.compactMap { entry -> String? in
            if case .toolOutput(let output) = entry { return output.id }
            return nil
        })
        inputItems += functionCalls.filter { !replayedCallIDs.contains($0.callId) }.map { call in
            [
                "type": "function_call",
                "call_id": call.callId,
                "name": call.name,
                "arguments": ResponsesFunctionCallAccumulator.isJSONObject(call.arguments) ? call.arguments : "{}"
            ] as [String: Any]
        }
        inputItems += toolOutputs.filter { !replayedOutputIDs.contains($0.callId) }.map { output in
            [
                "type": "function_call_output",
                "call_id": output.callId,
                "output": output.output
            ] as [String: Any]
        }

        var body: [String: Any] = [
            "model": modelName,
            "instructions": responseInstructions(from: transcript),
            "input": inputItems,
            "stream": true,
            "store": false
        ]
        if !tools.isEmpty {
            body["tools"] = tools
            body["parallel_tool_calls"] = parallelToolCalls.isEnabled
        }
        if let temperature = options.temperature {
            body["temperature"] = temperature
        }
        if reasoningCapture != nil {
            body["reasoning"] = ["summary": "auto"]
        }
        applyPromptCacheHints(to: &body)
        return try JSONSerialization.data(withJSONObject: body)
    }

    func noteMalformedCalls(_ calls: [FunctionCall]) {
        if calls.contains(where: { !ResponsesFunctionCallAccumulator.isJSONObject($0.arguments) }) {
            parallelToolCalls.disable()
        }
    }

    func applyPromptCacheHints(to body: inout [String: Any]) {
        body["prompt_cache_key"] = promptCacheKey()
    }

    func promptCacheKey() -> String {
        let safeModel = modelName.map { character -> Character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "-"
        }
        guard let promptCacheScope, !promptCacheScope.isEmpty else {
            return "sloppy-openai-oauth-\(String(safeModel).prefix(80))"
        }
        return "sloppy-oauth-\(String(safeModel).prefix(24))-\(Self.stableDigest(promptCacheScope))"
    }

    /// The Codex backend keys request affinity, and with it prompt-cache locality, on these ids. Without them
    /// repeated requests with an identical prefix are routed independently and almost never hit the cache
    /// (measured: ~0% cached input without, ~99% with).
    var affinityHeaders: [String: String] {
        guard let promptCacheScope, !promptCacheScope.isEmpty else { return [:] }
        let conversationID = Self.stableUUIDString(promptCacheScope)
        return ["session_id": conversationID, "conversation_id": conversationID]
    }

    /// Deterministic UUID-shaped identifier for a scope string (two FNV-1a passes with different seeds).
    static func stableUUIDString(_ text: String) -> String {
        func fnv(_ seed: UInt64) -> UInt64 {
            var hash = seed
            for byte in text.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001b3
            }
            return hash
        }
        let high = fnv(0xcbf29ce484222325)
        let low = fnv(0x84222325cbf29ce4)
        let hex = String(format: "%016llx%016llx", high, low)
        let chars = Array(hex)
        func part(_ range: Range<Int>) -> String { String(chars[range]) }
        return "\(part(0..<8))-\(part(8..<12))-4\(part(13..<16))-8\(part(17..<20))-\(part(20..<32))"
    }

    /// FNV-1a 64-bit, hex. Stable across launches (unlike `Hasher`), short enough for a cache key.
    static func stableDigest(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    struct ToolConversion {
        var definitions: [[String: Any]]
        var nameMap: [String: String]
    }

    func convertToolsToAPI(_ tools: [any Tool]) -> ToolConversion {
        var definitions: [[String: Any]] = []
        var nameMap: [String: String] = [:]
        for tool in tools {
            let sanitized = ModelToolNameSanitizer.sanitizeName(tool.name)
            nameMap[sanitized] = tool.name
            let params = ModelToolSchemaNormalizer.providerSafeObjectSchema(tool.parameters)
            definitions.append([
                "type": "function",
                "name": sanitized,
                "description": tool.description,
                "parameters": params
            ])
        }
        return ToolConversion(definitions: definitions, nameMap: nameMap)
    }

    func parseGeneratedContent(_ jsonString: String) -> GeneratedContent {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return GeneratedContent(jsonString)
        }
        return GeneratedContent(properties: obj.map { ($0.key, generatedContentValue($0.value)) },
                                uniquingKeysWith: { _, new in new })
    }

    func generatedContentValue(_ value: Any) -> GeneratedContent {
        switch value {
        case let str as String: return GeneratedContent(str)
        case let b as Bool: return GeneratedContent(b)
        case let num as Double: return GeneratedContent(num)
        case let num as Int: return GeneratedContent(Double(num))
        case let arr as [Any]: return GeneratedContent(arr.map { generatedContentValue($0) })
        case let dict as [String: Any]:
            return GeneratedContent(properties: dict.map { ($0.key, generatedContentValue($0.value)) },
                                    uniquingKeysWith: { _, new in new })
        default: return GeneratedContent("")
        }
    }
}

// MARK: - SSE Parsing

extension OpenAIOAuthModel {
    func parseSSEOutputDelta(_ line: String) -> String? {
        guard line.hasPrefix("data: ") else { return nil }
        let payload = String(line.dropFirst(6))
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String,
              type == "response.output_text.delta",
              let delta = obj["delta"] as? String
        else { return nil }
        return delta
    }

    func parseSSEReasoningDelta(_ line: String) -> String? {
        guard line.hasPrefix("data: ") else { return nil }
        let payload = String(line.dropFirst(6))
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String,
              type == "response.reasoning_summary_text.delta",
              let delta = obj["delta"] as? String
        else { return nil }
        return delta
    }

    func parseSSEResponseCompleted(_ line: String) -> (
        responseId: String,
        inputTokens: Int,
        outputTokens: Int,
        cachedInputTokens: Int,
        reasoningTokens: Int
    )? {
        guard line.hasPrefix("data: ") else { return nil }
        let payload = String(line.dropFirst(6))
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String,
              type == "response.completed",
              let resp = obj["response"] as? [String: Any],
              let id = resp["id"] as? String
        else { return nil }

        var inputTokens = 0
        var outputTokens = 0
        var cachedInputTokens = 0
        var reasoningTokens = 0
        if let usageObj = resp["usage"] as? [String: Any] {
            inputTokens = usageObj["input_tokens"] as? Int ?? 0
            outputTokens = usageObj["output_tokens"] as? Int ?? 0
            if let inputDetails = usageObj["input_tokens_details"] as? [String: Any] {
                cachedInputTokens = inputDetails["cached_tokens"] as? Int ?? 0
            }
            if let outputDetails = usageObj["output_tokens_details"] as? [String: Any] {
                reasoningTokens = outputDetails["reasoning_tokens"] as? Int ?? 0
            }
        }

        return (
            responseId: id,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedInputTokens: cachedInputTokens,
            reasoningTokens: reasoningTokens
        )
    }
}

// MARK: - Linux Streaming Support

#if canImport(FoundationNetworking)
extension URLSession {
    func linuxBytes(for request: URLRequest) async throws -> (StreamWrapper, URLResponse) {
        let delegate = LinuxStreamingDelegate()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: applyingConfigurationHeaders(to: request))
        task.resume()
        let response = try await delegate.waitForResponse()
        return (StreamWrapper(stream: delegate.stream), response)
    }

    struct StreamWrapper: AsyncSequence {
        typealias Element = UInt8
        let stream: AsyncThrowingStream<UInt8, Error>

        func makeAsyncIterator() -> AsyncThrowingStream<UInt8, Error>.Iterator {
            stream.makeAsyncIterator()
        }

        var lines: AsyncThrowingStream<String, Error> {
            AsyncThrowingStream { continuation in
                Task {
                    var buffer = Data()
                    do {
                        for try await byte in stream {
                            if byte == UInt8(ascii: "\n") {
                                let line = String(data: buffer, encoding: .utf8) ?? ""
                                continuation.yield(line)
                                buffer.removeAll()
                            } else if byte != UInt8(ascii: "\r") {
                                buffer.append(byte)
                            }
                        }
                        if !buffer.isEmpty {
                            let line = String(data: buffer, encoding: .utf8) ?? ""
                            continuation.yield(line)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }
}

private final class LinuxStreamingDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    nonisolated(unsafe) private var responseContinuation: CheckedContinuation<URLResponse, Error>?
    nonisolated(unsafe) private var streamContinuation: AsyncThrowingStream<UInt8, Error>.Continuation?
    let stream: AsyncThrowingStream<UInt8, Error>

    override init() {
        var cont: AsyncThrowingStream<UInt8, Error>.Continuation?
        self.stream = AsyncThrowingStream { cont = $0 }
        self.streamContinuation = cont
        super.init()
    }

    func waitForResponse() async throws -> URLResponse {
        try await withCheckedThrowingContinuation { self.responseContinuation = $0 }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        responseContinuation?.resume(returning: response)
        responseContinuation = nil
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        for byte in data {
            streamContinuation?.yield(byte)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            if let responseContinuation = responseContinuation {
                responseContinuation.resume(throwing: error)
                self.responseContinuation = nil
            }
            streamContinuation?.finish(throwing: error)
        } else {
            streamContinuation?.finish()
        }
    }
}
#endif

// MARK: - Error Types

enum OpenAIError: Error, LocalizedError {
    case invalidToken(String)
    case invalidResponse
    case httpError(Int, String)
    case decodingError(String)
    case modelNotSupported(String)

    /// The error callers outside this module can match on.
    var surfaced: Error {
        if case .modelNotSupported(let detail) = self {
            return ProviderModelNotSupportedError(detail: detail)
        }
        return self
    }

    var errorDescription: String? {
        switch self {
        case .modelNotSupported(let detail):
            return "HTTP Error 400: \(detail)"
        case .invalidToken(let message):
            return "OAuth Authentication Error: \(message)"
        case .invalidResponse:
            return "Invalid response from OpenAI API"
        case .httpError(let code, let message):
            return "HTTP Error \(code): \(message)"
        case .decodingError(let message):
            return "Response parsing error: \(message)"
        }
    }
}

/// The provider rejected the requested model for this account (HTTP 400 "model is not supported").
public struct ProviderModelNotSupportedError: Error, LocalizedError, Sendable {
    public var detail: String

    public init(detail: String) {
        self.detail = detail
    }

    public var errorDescription: String? { "HTTP Error 400: \(detail)" }
}

/// Shared switch for `parallel_tool_calls`. Once a response delivers unusable tool arguments the
/// model is asked for one call at a time for the rest of the session.
public final class ParallelToolCallsControl: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool

    public init(enabled: Bool = true) {
        self.enabled = enabled
    }

    public var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled
    }

    public func disable() {
        lock.lock()
        enabled = false
        lock.unlock()
    }
}
