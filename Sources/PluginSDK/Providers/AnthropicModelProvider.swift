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
    private let apiKey: @Sendable () -> String
    private let baseURL: URL
    private let session: URLSession?

    public init(
        id: String = "anthropic",
        supportedModels: [String],
        apiKey: @escaping @Sendable () -> String,
        baseURL: URL = AnthropicLanguageModel.defaultBaseURL,
        tools: [any Tool] = [],
        systemInstructions: String? = nil,
        session: URLSession? = nil
    ) {
        self.id = id
        self.supportedModels = supportedModels
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.tools = tools
        self.systemInstructions = systemInstructions
        self.session = session
    }

    public func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        let resolved = modelName.hasPrefix("anthropic:") ? String(modelName.dropFirst(10)) : modelName
        if let session {
            return AnthropicLanguageModel(
                baseURL: baseURL,
                apiKey: apiKey(),
                model: resolved,
                session: session
            )
        }
        return AnthropicLanguageModel(
            baseURL: baseURL,
            apiKey: apiKey(),
            model: resolved
        )
    }
}
