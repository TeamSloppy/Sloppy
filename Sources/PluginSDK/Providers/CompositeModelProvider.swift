import AnyLanguageModel
import Foundation
import Protocols

/// Combines multiple `ModelProvider` instances into a single provider.
/// Routes `createLanguageModel(for:)` and `generationOptions(for:)` to the
/// matching sub-provider based on `supportedModels`.
public struct CompositeModelProvider: ModelProvider {
    public enum ProviderError: Error {
        case unsupportedModel(String)
    }

    private let providers: [any ModelProvider]

    public let id: String
    public let systemInstructions: String?
    public let tools: [any Tool]

    public var supportedModels: [String] {
        providers.flatMap(\.supportedModels)
    }

    public init(
        id: String = "composite",
        providers: [any ModelProvider],
        tools: [any Tool] = [],
        systemInstructions: String? = nil
    ) {
        self.id = id
        self.providers = providers
        self.tools = tools
        self.systemInstructions = systemInstructions
    }

    public func createLanguageModel(for modelName: String) async throws -> any LanguageModel {
        guard let provider = providers.first(where: { $0.supportedModels.contains(modelName) }) else {
            throw ProviderError.unsupportedModel(modelName)
        }
        return try await provider.createLanguageModel(for: modelName)
    }

    public func generationOptions(for modelName: String, maxTokens: Int, reasoningEffort: ReasoningEffort?) -> GenerationOptions {
        guard let provider = providers.first(where: { $0.supportedModels.contains(modelName) }) else {
            return GenerationOptions(maximumResponseTokens: maxTokens)
        }
        return provider.generationOptions(for: modelName, maxTokens: maxTokens, reasoningEffort: reasoningEffort)
    }

    public func reasoningCapture(for modelName: String) -> ReasoningContentCapture? {
        providers.first(where: { $0.supportedModels.contains(modelName) })?.reasoningCapture(for: modelName)
    }
}
