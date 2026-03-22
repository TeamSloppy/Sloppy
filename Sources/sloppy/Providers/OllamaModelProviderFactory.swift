import AnyLanguageModel
import Foundation
import PluginSDK

/// Ollama model provider factory.
struct OllamaModelProviderFactory: ModelProviderFactory {
    func buildProvider(from config: ModelProviderBuildConfig) -> (any ModelProvider)? {
        let ollamaModels = config.resolvedModels.filter { $0.hasPrefix("ollama:") }
        guard !ollamaModels.isEmpty else { return nil }

        let primaryConfig = config.coreConfig.models.first {
            CoreModelProviderFactory.resolvedIdentifier(for: $0)?.hasPrefix("ollama:") == true
        }

        let baseURL = CoreModelProviderFactory.parseURL(primaryConfig?.apiUrl)
            ?? OllamaLanguageModel.defaultBaseURL

        return OllamaModelProvider(
            supportedModels: ollamaModels,
            baseURL: baseURL,
            tools: config.tools,
            systemInstructions: config.systemInstructions,
            session: config.proxySession
        )
    }
}
