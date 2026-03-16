import AnyLanguageModel
import Foundation
import Protocols

public struct GeminiModelProvider: ModelProvider {
    public let id: String
    public let supportedModels: [String]
    public let systemInstructions: String?
    public let tools: [any Tool]
    private let apiKey: @Sendable () -> String
    private let baseURL: URL

    public init(
        id: String = "gemini",
        supportedModels: [String],
        apiKey: @escaping @Sendable () -> String,
        baseURL: URL = GeminiLanguageModel.defaultBaseURL,
        tools: [any Tool] = [],
        systemInstructions: String? = nil
    ) {
        self.id = id
        self.supportedModels = supportedModels
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.tools = tools
        self.systemInstructions = systemInstructions
    }

    public func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        let resolved = modelName.hasPrefix("gemini:") ? String(modelName.dropFirst(7)) : modelName
        return GeminiLanguageModel(
            baseURL: baseURL,
            apiKey: apiKey(),
            model: resolved
        )
    }
}
