import AnyLanguageModel
import Foundation
import Protocols

/// Model provider for Ollama backends.
public struct OllamaModelProvider: ModelProvider {
    public let id: String
    public let supportedModels: [String]
    public let systemInstructions: String?
    public let tools: [any Tool]
    private let baseURL: URL

    public init(
        id: String = "ollama",
        supportedModels: [String],
        baseURL: URL = OllamaLanguageModel.defaultBaseURL,
        tools: [any Tool] = [],
        systemInstructions: String? = nil
    ) {
        self.id = id
        self.supportedModels = supportedModels
        self.baseURL = baseURL
        self.tools = tools
        self.systemInstructions = systemInstructions
    }

    public func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        let resolved = modelName.hasPrefix("ollama:") ? String(modelName.dropFirst(7)) : modelName
        return OllamaLanguageModel(baseURL: baseURL, model: resolved)
    }
}
