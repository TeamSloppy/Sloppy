import AnyLanguageModel
import Foundation
import PluginSDK

/// OpenRouter ([openrouter.ai](https://openrouter.ai)) — OpenAI Chat Completions–compatible API.
struct OpenRouterModelProviderFactory: ModelProviderFactory {
    func buildProvider(from config: ModelProviderBuildConfig) -> (any ModelProvider)? {
        let openRouterModels = config.resolvedModels.filter { $0.hasPrefix("openrouter:") }
        guard !openRouterModels.isEmpty else { return nil }

        let primaryConfig = config.coreConfig.models.first {
            CoreModelProviderFactory.resolvedIdentifier(for: $0)?.hasPrefix("openrouter:") == true
        }

        let envKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let configuredKey = (primaryConfig?.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedKey = configuredKey.isEmpty ? envKey : configuredKey
        guard !resolvedKey.isEmpty else { return nil }

        let baseURL = CoreModelProviderFactory.parseURL(primaryConfig?.apiUrl)
            ?? OpenRouterLanguageModelSupport.defaultBaseURL

        let session: URLSession? = config.proxySession ?? OpenRouterLanguageModelSupport.makeURLSession()

        let settings = OpenAIModelProvider.Settings(
            apiKey: { resolvedKey },
            baseURL: baseURL,
            apiVariant: .chatCompletions,
            accountId: nil,
            refreshTokenIfNeeded: nil,
            session: session,
            modelIdentifierPrefix: "openrouter:",
            useOpenAICodexOAuthPath: false,
            allowResponsesAPIFallback: false
        )

        return OpenAIModelProvider(
            id: "openrouter",
            supportedModels: openRouterModels,
            settings: settings,
            tools: config.tools,
            systemInstructions: config.systemInstructions
        )
    }
}
