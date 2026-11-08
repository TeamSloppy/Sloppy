import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum StepHTTPFormat: String, Sendable {
    case responses
    case chatCompletions = "chat-completions"
    case ollama
    case anthropic
    case gemini
}

/// One HTTP generation. The caller alone owns tool execution and request recovery.
/// https://developers.openai.com/api/docs/guides/streaming-responses
public struct HTTPModelStepProvider: LanguageModelStepProvider {
    let providerID: String
    let model: String
    let baseURL: URL
    let token: @Sendable () -> String
    let refresh: (@Sendable () async throws -> Void)?
    let session: URLSession
    let instructions: String
    var format: StepHTTPFormat = .responses
    var thinkingValues: [StepJSONValue]? = nil
    var nativeCodeAssist: StepCodeAssistSettings? = nil

    private let includeOutputLimit: Bool
    private let cacheKey: (@Sendable (LanguageModelStepRequest) -> String)?
    private let requestTransform: (@Sendable (URLRequest, LanguageModelStepRequest) async throws -> URLRequest)?
    private let refreshAuthentication: (@Sendable () async throws -> Void)?

    public init(providerID: String, model: String, baseURL: URL,
                token: @escaping @Sendable () -> String, refresh: (@Sendable () async throws -> Void)? = nil,
                session: URLSession = .shared, instructions: String = "", format: StepHTTPFormat = .responses,
                thinkingValues: [StepJSONValue]? = nil, nativeCodeAssist: StepCodeAssistSettings? = nil,
                includeOutputLimit: Bool = true, cacheKey: (@Sendable (LanguageModelStepRequest) -> String)? = nil,
                requestTransform: (@Sendable (URLRequest, LanguageModelStepRequest) async throws -> URLRequest)? = nil,
                refreshAuthentication: (@Sendable () async throws -> Void)? = nil) {
        self.providerID = providerID; self.model = model; self.baseURL = baseURL; self.token = token
        self.refresh = refresh; self.session = session; self.instructions = instructions; self.format = format
        self.thinkingValues = thinkingValues; self.nativeCodeAssist = nativeCodeAssist
        self.includeOutputLimit = includeOutputLimit; self.cacheKey = cacheKey
        self.requestTransform = requestTransform; self.refreshAuthentication = refreshAuthentication
    }

    public func streamStep(_ step: LanguageModelStepRequest) -> AsyncThrowingStream<LanguageModelStepEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(256)) { continuation in
            let operation = Task {
                do {
                    try Task.checkCancellation()
                    try await refreshCredentials()
                    let resolvedProject = nativeCodeAssist?.projectID()?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let project = resolvedProject.flatMap { $0.isEmpty ? nil : $0 }
                    let providerID: String
                    if nativeCodeAssist != nil {
                        let binding = project.map { "\($0.utf8.count):" + $0 } ?? "none"
                        providerID = self.providerID + "/project:" + binding
                    } else { providerID = self.providerID }
                    let body: Data
                    switch format {
                    case .responses:
                        body = try ResponsesStepCodec.requestBody(step, model: model, providerID: providerID,
                            instructions: instructions, cacheKey: cacheKey?(step) ?? ("model-step-" + StepHTTPTransport.cacheKeyDigest(providerID + "/" + step.cacheScope)),
                            includeOutputLimit: includeOutputLimit)
                    case .chatCompletions:
                        body = try ChatCompletionsStepCodec.requestBody(step, model: model,
                            providerID: providerID, instructions: instructions)
                    case .ollama:
                        body = try OllamaStepCodec.requestBody(step, model: model, providerID: providerID,
                            instructions: instructions, thinkingValues: thinkingValues)
                    case .anthropic:
                        body = try AnthropicStepCodec.requestBody(step, model: model,
                            providerID: providerID, instructions: instructions)
                    case .gemini:
                        let payload = try GeminiStepCodec.requestBody(step, model: model,
                            providerID: providerID, instructions: instructions)
                        if let settings = nativeCodeAssist {
                            var envelope: [String: StepJSONValue] = ["model": .string(model),
                                "request": try JSONDecoder().decode(StepJSONValue.self, from: payload),
                                "requestType": .string("agent"), "userAgent": .string(settings.userAgent),
                                "requestId": .string(step.attemptId)]
                            if let project { envelope["project"] = .string(project) }
                            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                            body = try encoder.encode(StepJSONValue.object(envelope))
                        } else { body = payload }
                    }
                    let path: String
                    switch format {
                    case .responses: path = "responses"
                    case .chatCompletions: path = "chat/completions"
                    case .ollama: path = "api/chat"
                    case .anthropic: path = "v1/messages"
                    case .gemini:
                        path = nativeCodeAssist == nil ? "v1beta/models/" + model + ":streamGenerateContent" : "v1internal:streamGenerateContent"
                    }
                    var request = URLRequest(url: baseURL.appendingPathComponent(path))
                    if format == .gemini { request.url?.append(queryItems: [.init(name: "alt", value: "sse")]) }
                    request.httpMethod = "POST"
                    request.httpBody = body
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(format == .ollama ? "application/x-ndjson" : "text/event-stream", forHTTPHeaderField: "Accept")
                    try await ModelStepEventDelivery.yield(.started, into: continuation)
                    var mayRefresh = true
                    while true {
                        var outgoing = request
                        let key = token()
                        if format == .anthropic {
                            outgoing.setValue(key, forHTTPHeaderField: "x-api-key")
                            outgoing.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                        } else if format == .gemini {
                            if let settings = nativeCodeAssist {
                                for (field, value) in settings.headers { outgoing.setValue(value, forHTTPHeaderField: field) }
                                outgoing.setValue(settings.userAgent, forHTTPHeaderField: "User-Agent")
                                outgoing.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
                            } else { outgoing.setValue(key, forHTTPHeaderField: "x-goog-api-key") }
                        } else if !key.isEmpty { outgoing.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
                        if let requestTransform { outgoing = try await requestTransform(outgoing, step) }
                        var status = 0
                        var headers: [String: String] = [:]
                        var isJSON = false
                        var json = Data()
                        var errorBody = Data()
                        var codec = ResponsesStepCodec(providerID: providerID, modelID: model)
                        var chatCodec = ChatCompletionsStepCodec(providerID: providerID, modelID: model)
                        var ollamaCodec = OllamaStepCodec(providerID: providerID, modelID: model, stepID: step.stepId)
                        var anthropicCodec = AnthropicStepCodec(providerID: providerID, modelID: model)
                        var geminiCodec = GeminiStepCodec(providerID: providerID, modelID: model, stepID: step.stepId)
                        for try await event in StepHTTPTransport(session: session).stream(outgoing) {
                            try Task.checkCancellation()
                            switch event {
                            case .response(let code, let received):
                                status = code; headers = received
                                isJSON = received["content-type"]?.lowercased().contains("application/json") == true
                            case .data(let data):
                                if 200...299 ~= status {
                                    if isJSON { json.append(data) }
                                    else {
                                        let events: [LanguageModelStepEvent]
                                        switch format {
                                        case .responses: events = try codec.consume(data)
                                        case .chatCompletions: events = try chatCodec.consume(data)
                                        case .ollama: events = try ollamaCodec.consume(data)
                                        case .anthropic: events = try anthropicCodec.consume(data)
                                        case .gemini: events = try geminiCodec.consume(data)
                                        }
                                        for event in events { try await ModelStepEventDelivery.yield(event, into: continuation) }
                                    }
                                } else if errorBody.count < 65_536 {
                                    errorBody.append(data.prefix(65_536 - errorBody.count))
                                }
                            }
                        }
                        try Task.checkCancellation()
                        if status == 401, mayRefresh, let refreshAuthentication {
                            mayRefresh = false
                            try await refreshAuthentication()
                            continue
                        }
                        guard 200...299 ~= status else {
                            throw StepHTTPTransport.failure(status: status, headers: headers, body: errorBody)
                        }
                        let response: LanguageModelStepResponse
                        switch format {
                        case .responses:
                            if isJSON { try codec.consumeJSON(json) }
                            response = try codec.finish()
                        case .chatCompletions:
                            if isJSON { try chatCodec.consumeJSON(json) }
                            response = try chatCodec.finish()
                        case .ollama:
                            if isJSON { try ollamaCodec.consumeJSON(json) }
                            response = try ollamaCodec.finish()
                        case .anthropic:
                            if isJSON { try anthropicCodec.consumeJSON(json) }
                            response = try anthropicCodec.finish()
                        case .gemini:
                            if isJSON { try geminiCodec.consumeJSON(json) }
                            response = try geminiCodec.finish()
                        }
                        try await ModelStepEventDelivery.yield(.final(response), into: continuation)
                        continuation.finish()
                        break
                    }
                } catch {
                    continuation.finish(throwing: StepHTTPTransport.normalizedFailure(error))
                }
            }
            continuation.onTermination = { @Sendable _ in operation.cancel() }
        }
    }

    private func refreshCredentials() async throws {
        do { try await (refresh ?? nativeCodeAssist?.refreshCredentials)?() }
        catch {
            if let failure = error as? LanguageModelStepFailure { throw failure }
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if let urlError = error as? URLError, urlError.code != .userAuthenticationRequired {
                var failure = StepHTTPTransport.normalizedFailure(error)
                failure.stage = .preparation
                throw failure
            }
            throw LanguageModelStepFailure(category: .authentication, code: "credential_refresh_failed",
                message: String(error.localizedDescription.prefix(2048)), stage: .preparation)
        }
    }

}
