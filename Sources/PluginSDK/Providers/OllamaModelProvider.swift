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
    private let contextCache: OllamaCloudContextLimits

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
        self.contextCache = OllamaCloudContextLimits()
    }

    private init(copying provider: Self, session: URLSession) {
        id = provider.id
        supportedModels = provider.supportedModels
        systemInstructions = provider.systemInstructions
        tools = provider.tools
        baseURL = provider.baseURL
        self.session = session
        contextCache = provider.contextCache
    }

    public func supports(modelName: String) -> Bool {
        if supportedModels.contains(modelName) {
            return true
        }
        return modelName.hasPrefix("ollama:")
    }

    public func supportsUsageObservation(for modelName: String) -> Bool { supports(modelName: modelName) }
    public func createLanguageModel(for modelName: String, usageContext: ModelUsageContext) async throws -> any LanguageModel {
        await discoverContextLimits(for: modelName)
        let observed = UsageObservedURLSession.make(wrapping: session, context: usageContext)
        let scoped = OllamaModelProvider(copying: self, session: observed)
        return scoped.makeLanguageModel(for: modelName)
    }

    public func contextLimits(for modelName: String) -> ModelContextLimits? {
        contextCache.value(for: modelName)
    }

    public func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        await discoverContextLimits(for: modelName)
        return makeLanguageModel(for: modelName)
    }

    private func discoverContextLimits(for modelName: String) async {
        let resolved = modelName.hasPrefix("ollama:") ? String(modelName.dropFirst(7)) : modelName
        await contextCache.discover(modelName: modelName, resolved: resolved, baseURL: baseURL, session: session ?? .shared)
    }

    private func makeLanguageModel(for modelName: String) -> any LanguageModel {
        let resolved = modelName.hasPrefix("ollama:") ? String(modelName.dropFirst(7)) : modelName
        if let session {
            return OllamaLanguageModel(baseURL: baseURL, model: resolved, session: session)
        }
        return OllamaLanguageModel(baseURL: baseURL, model: resolved)
    }
}
