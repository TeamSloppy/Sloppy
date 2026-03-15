import AnyLanguageModel
import Foundation
import PluginSDK

/// OpenAI model provider factory.
struct OpenAIModelProviderFactory: ModelProviderFactory {
    func buildProvider(from config: ModelProviderBuildConfig) -> (any ModelProvider)? {
        let openAIModels = config.resolvedModels.filter { $0.hasPrefix("openai:") }
        guard !openAIModels.isEmpty else { return nil }

        let primaryConfig = config.coreConfig.models.first {
            CoreModelProviderFactory.resolvedIdentifier(for: $0)?.hasPrefix("openai:") == true
        }

        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        let configuredKey = (primaryConfig?.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedStaticKey = configuredKey.isEmpty ? apiKey : configuredKey

        let keyProvider: (@Sendable () -> String)?
        let isOAuth: Bool
        if !resolvedStaticKey.isEmpty {
            keyProvider = { resolvedStaticKey }
            isOAuth = false
        } else if let oauthProvider = config.oauthTokenProvider, oauthProvider() != nil {
            keyProvider = { config.oauthTokenProvider?() ?? "" }
            isOAuth = true
        } else {
            return nil
        }

        guard let keyProvider else { return nil }

        let resolvedAccountId = isOAuth ? config.oauthAccountId : nil
        let resolvedRefresh = isOAuth ? config.oauthTokenRefresh : nil

        let baseURL = CoreModelProviderFactory.parseURL(primaryConfig?.apiUrl)
            ?? OpenAILanguageModel.defaultBaseURL

        let settings = OpenAIModelProvider.Settings(
            apiKey: keyProvider,
            baseURL: baseURL,
            accountId: resolvedAccountId,
            refreshTokenIfNeeded: resolvedRefresh
        )

        return OpenAIModelProvider(
            supportedModels: openAIModels,
            settings: settings,
            tools: config.tools,
            systemInstructions: config.systemInstructions
        )
    }
}
