import AnyLanguageModel
import Foundation
import PluginSDK

struct AnthropicModelProviderFactory: ModelProviderFactory {
    func buildProvider(from config: ModelProviderBuildConfig) -> (any ModelProvider)? {
        let anthropicModels = config.resolvedModels.filter { $0.hasPrefix("anthropic:") }
        guard !anthropicModels.isEmpty else { return nil }

        let primaryConfig = config.coreConfig.models.first {
            CoreModelProviderFactory.resolvedIdentifier(for: $0)?.hasPrefix("anthropic:") == true
        }

        let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
        let configuredKey = (primaryConfig?.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedKey = configuredKey.isEmpty ? envKey : configuredKey
        guard !resolvedKey.isEmpty else { return nil }

        let baseURL = CoreModelProviderFactory.parseURL(primaryConfig?.apiUrl)
            ?? AnthropicLanguageModel.defaultBaseURL

        return AnthropicModelProvider(
            supportedModels: anthropicModels,
            apiKey: { resolvedKey },
            baseURL: baseURL,
            tools: config.tools,
            systemInstructions: config.systemInstructions
        )
    }
}
