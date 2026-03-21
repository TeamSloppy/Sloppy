import AnyLanguageModel
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols

/// Model provider for Ollama backends.
public struct OllamaModelProvider: ModelProvider {
    public let id: String
    public let supportedModels: [String]
    public let systemInstructions: String?
    public let tools: [any Tool]
    private let baseURL: URL
    private let session: URLSession?

    public init(
        id: String = "ollama",
        supportedModels: [String],
        baseURL: URL = OllamaLanguageModel.defaultBaseURL,
        tools: [any Tool] = [],
        systemInstructions: String? = nil,
        session: URLSession? = nil
    ) {
        self.id = id
        self.supportedModels = supportedModels
        self.baseURL = baseURL
        self.tools = tools
        self.systemInstructions = systemInstructions
        self.session = session
    }

    public func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        let resolved = modelName.hasPrefix("ollama:") ? String(modelName.dropFirst(7)) : modelName
        if let session {
            return OllamaLanguageModel(baseURL: baseURL, model: resolved, session: session)
        }
        return OllamaLanguageModel(baseURL: baseURL, model: resolved)
    }
}
