import AnyLanguageModel
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging
import Protocols

/// Model provider for OpenAI-compatible APIs.
/// Supports both API-key auth and OAuth bearer tokens.
/// Automatically retries with the Responses API variant when the Chat Completions API rejects a model.
public struct OpenAIModelProvider: ModelProvider {
    public struct Settings: Sendable {
        public var apiKey: @Sendable () -> String
        public var baseURL: URL
        public var apiVariant: OpenAILanguageModel.APIVariant
        public var accountId: String?
        public var refreshTokenIfNeeded: (@Sendable () async throws -> Void)?
        public var session: URLSession?

        public init(
            apiKey: @escaping @Sendable () -> String,
            baseURL: URL = OpenAILanguageModel.defaultBaseURL,
            apiVariant: OpenAILanguageModel.APIVariant = .chatCompletions,
            accountId: String? = nil,
            refreshTokenIfNeeded: (@Sendable () async throws -> Void)? = nil,
            session: URLSession? = nil
        ) {
            self.apiKey = apiKey
            self.baseURL = baseURL
            self.apiVariant = apiVariant
            self.accountId = accountId
            self.refreshTokenIfNeeded = refreshTokenIfNeeded
            self.session = session
        }
    }

    public let id: String
    public let supportedModels: [String]
    public let systemInstructions: String?
    public let tools: [any Tool]
    private let _reasoningCapture: ReasoningContentCapture
    private let settings: Settings
    private static let logger = Logger(label: "sloppy.provider.openai")

    public init(
        id: String = "openai",
        supportedModels: [String],
        settings: Settings,
        tools: [any Tool] = [],
        systemInstructions: String? = nil
    ) {
        self.id = id
        self.supportedModels = supportedModels
        self.settings = settings
        self.tools = tools
        self.systemInstructions = systemInstructions
        self._reasoningCapture = ReasoningContentCapture()
    }

    public func reasoningCapture(for modelName: String) -> ReasoningContentCapture? {
        _reasoningCapture
    }

    public func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        let resolved = normalizeModelName(modelName)
        let token = settings.apiKey()
        if isOAuthToken(token) {
            try? await settings.refreshTokenIfNeeded?()
            return OpenAIOAuthModel(
                bearerToken: token,
                model: resolved,
                accountId: settings.accountId,
                instructions: systemInstructions ?? "You are an execution-focused assistant.",
                reasoningCapture: _reasoningCapture
            )
        }
        return OpenAIRetryingLanguageModel(
            apiKey: settings.apiKey,
            baseURL: settings.baseURL,
            apiVariant: settings.apiVariant,
            model: resolved,
            session: settings.session
        )
    }

    public func generationOptions(for modelName: String, maxTokens: Int, reasoningEffort: ReasoningEffort?) -> GenerationOptions {
        var options = GenerationOptions(maximumResponseTokens: maxTokens)
        guard let mapped = mapReasoningEffort(reasoningEffort) else { return options }
        options[custom: OpenAILanguageModel.self] = .init(
            reasoningEffort: mapped,
            reasoning: .init(effort: mapped)
        )
        return options
    }

    private func normalizeModelName(_ model: String) -> String {
        model.hasPrefix("openai:") ? String(model.dropFirst(7)) : model
    }

    private func isOAuthToken(_ token: String) -> Bool {
        !token.hasPrefix("sk-") && !token.isEmpty
    }

    private func mapReasoningEffort(
        _ effort: ReasoningEffort?
    ) -> OpenAILanguageModel.CustomGenerationOptions.ReasoningEffort? {
        switch effort {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        case nil: return nil
        }
    }
}

/// Wraps `OpenAILanguageModel` and automatically retries with the Responses API variant
/// when a Chat Completions request fails because the model is not a chat model.
struct OpenAIRetryingLanguageModel: LanguageModel {
    typealias UnavailableReason = Never

    let apiKey: @Sendable () -> String
    let baseURL: URL
    let apiVariant: OpenAILanguageModel.APIVariant
    let model: String
    let session: URLSession?

    init(
        apiKey: @escaping @Sendable () -> String,
        baseURL: URL,
        apiVariant: OpenAILanguageModel.APIVariant,
        model: String,
        session: URLSession? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.apiVariant = apiVariant
        self.model = model
        self.session = session
    }

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        let primary = makeModel(variant: apiVariant)
        do {
            return try await primary.respond(
                within: session, to: prompt, generating: type,
                includeSchemaInPrompt: includeSchemaInPrompt, options: options
            )
        } catch {
            guard shouldRetryWithResponses(error: error, currentVariant: apiVariant) else { throw error }
            let fallback = makeModel(variant: .responses)
            return try await fallback.respond(
                within: session, to: prompt, generating: type,
                includeSchemaInPrompt: includeSchemaInPrompt, options: options
            )
        }
    }

    func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        let apiKey = self.apiKey()
        let baseURL = self.baseURL
        let apiVariant = self.apiVariant
        let model = self.model
        let urlSession = self.session

        let stream = AsyncThrowingStream<LanguageModelSession.ResponseStream<Content>.Snapshot, any Error> { continuation in
            Task {
                let primary = urlSession.map {
                    OpenAILanguageModel(baseURL: baseURL, apiKey: apiKey, model: model, apiVariant: apiVariant, session: $0)
                } ?? OpenAILanguageModel(baseURL: baseURL, apiKey: apiKey, model: model, apiVariant: apiVariant)
                let primaryStream = primary.streamResponse(
                    within: session, to: prompt, generating: type,
                    includeSchemaInPrompt: includeSchemaInPrompt, options: options
                )

                var retryNeeded = false
                do {
                    for try await snapshot in primaryStream {
                        continuation.yield(snapshot)
                    }
                } catch {
                    if shouldRetryWithResponses(error: error, currentVariant: apiVariant) {
                        retryNeeded = true
                    } else {
                        continuation.finish(throwing: error)
                        return
                    }
                }

                guard retryNeeded else {
                    continuation.finish()
                    return
                }

                let fallback = urlSession.map {
                    OpenAILanguageModel(baseURL: baseURL, apiKey: apiKey, model: model, apiVariant: .responses, session: $0)
                } ?? OpenAILanguageModel(baseURL: baseURL, apiKey: apiKey, model: model, apiVariant: .responses)
                let fallbackStream = fallback.streamResponse(
                    within: session, to: prompt, generating: type,
                    includeSchemaInPrompt: includeSchemaInPrompt, options: options
                )
                do {
                    for try await snapshot in fallbackStream {
                        continuation.yield(snapshot)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        return LanguageModelSession.ResponseStream(stream: stream)
    }

    private func makeModel(variant: OpenAILanguageModel.APIVariant) -> OpenAILanguageModel {
        if let session {
            return OpenAILanguageModel(baseURL: baseURL, apiKey: apiKey(), model: model, apiVariant: variant, session: session)
        }
        return OpenAILanguageModel(baseURL: baseURL, apiKey: apiKey(), model: model, apiVariant: variant)
    }

    private func shouldRetryWithResponses(error: any Error, currentVariant: OpenAILanguageModel.APIVariant) -> Bool {
        guard currentVariant == .chatCompletions else { return false }
        let text = String(describing: error).lowercased()
        return text.contains("not a chat model") ||
            (text.contains("v1/chat/completions") && text.contains("did you mean to use v1/completions"))
    }
}
