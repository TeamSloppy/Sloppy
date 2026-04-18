import AnyLanguageModel
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols

public struct AnthropicModelProvider: ModelProvider {
    public let id: String
    public let supportedModels: [String]
    public let systemInstructions: String?
    public let tools: [any Tool]
    private let tokenProvider: @Sendable () -> String
    private let baseURL: URL
    private let session: URLSession?
    private let refreshTokenIfNeeded: (@Sendable () async throws -> Void)?

    public init(
        id: String = "anthropic",
        supportedModels: [String],
        apiKey: @escaping @Sendable () -> String,
        baseURL: URL = OAuthAnthropicLanguageModel.defaultBaseURL,
        tools: [any Tool] = [],
        systemInstructions: String? = nil,
        session: URLSession? = nil,
        refreshTokenIfNeeded: (@Sendable () async throws -> Void)? = nil
    ) {
        self.id = id
        self.supportedModels = supportedModels
        self.tokenProvider = apiKey
        self.baseURL = baseURL
        self.tools = tools
        self.systemInstructions = systemInstructions
        self.session = session
        self.refreshTokenIfNeeded = refreshTokenIfNeeded
    }

    public func supports(modelName: String) -> Bool {
        if supportedModels.contains(modelName) {
            return true
        }
        return modelName.hasPrefix("anthropic:")
    }

    public func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        let resolved = modelName.hasPrefix("anthropic:") ? String(modelName.dropFirst(10)) : modelName
        try? await refreshTokenIfNeeded?()
        let httpSession: HTTPSession
        if let session {
            httpSession = session
        } else {
            httpSession = OAuthAnthropicURLSession.makeSessionRewritingAnthropicAuth()
        }
        return OAuthAnthropicLanguageModel(
            baseURL: baseURL,
            apiKey: tokenProvider(),
            model: resolved,
            session: httpSession
        )
    }
}
