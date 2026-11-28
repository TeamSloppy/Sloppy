import AnyLanguageModel
import Foundation
import PluginSDK

/// OpenAI model provider factory.
struct OpenAIModelProviderFactory: ModelProviderFactory {
    var environmentLookup: (@Sendable (String) -> String?)? = nil

    func buildProvider(from config: ModelProviderBuildConfig) -> (any ModelProvider)? {
        var providers: [any ModelProvider] = []

        if let apiProvider = buildAPIProvider(from: config) {
            providers.append(apiProvider)
        }
        if let oauthProvider = buildOAuthProvider(from: config) {
            providers.append(oauthProvider)
        }

        guard !providers.isEmpty else { return nil }
        if providers.count == 1 { return providers[0] }

        return CompositeModelProvider(
            id: "openai",
            providers: providers,
            tools: config.tools,
            systemInstructions: config.systemInstructions
        )
    }

    private func buildAPIProvider(from config: ModelProviderBuildConfig) -> OpenAIModelProvider? {
        let models = config.resolvedModels.filter { $0.hasPrefix("openai-api:") }
        guard !models.isEmpty else { return nil }

        guard let connection = Self.apiConnection(
            modelConfigs: config.modelConfigs, environmentLookup: environmentLookup ?? config.environmentLookup
        ) else { return nil }

        let settings = OpenAIModelProvider.Settings(
            apiKey: { connection.apiKey },
            baseURL: connection.baseURL,
            session: config.proxySession,
            modelIdentifierPrefix: "openai-api:",
            useOpenAICodexOAuthPath: false
        )

        return OpenAIModelProvider(
            id: "openai-api",
            supportedModels: models,
            settings: settings,
            tools: config.tools,
            systemInstructions: config.systemInstructions
        )
    }

    /// OpenAI API chat models share the first configured provider connection.
    static func apiConnection(
        modelConfigs: [CoreConfig.ModelConfig],
        environmentLookup: (String) -> String?
    ) -> (apiKey: String, baseURL: URL)? {
        let primary = modelConfigs.first {
            CoreModelProviderFactory.resolvedIdentifier(for: $0)?.hasPrefix("openai-api:") == true
        }
        // Resolve explicit references before choosing a provider; do not substitute other accounts.
        guard let resolution = try? ProviderAPIKeyResolver.resolve(configured: primary?.apiKey, environmentLookup: environmentLookup) else {
            return nil
        }
        let configuredURL = CoreModelProviderFactory.parseURL(primary?.apiUrl)
        let allowsKeyless = configuredURL.map { OpenAICompatibleCatalogEndpoint.hostAllowsKeylessOpenAIProbe(host: $0.host) } ?? false
        guard !resolution.key.isEmpty || allowsKeyless else { return nil }
        return (resolution.key, configuredURL ?? OpenAILanguageModel.defaultBaseURL)
    }

    private func buildOAuthProvider(from config: ModelProviderBuildConfig) -> OpenAIModelProvider? {
        let models = config.resolvedModels.filter { $0.hasPrefix("openai-oauth:") }
        guard !models.isEmpty else { return nil }

        let primaryConfig = config.modelConfigs.first {
            CoreModelProviderFactory.resolvedIdentifier(for: $0)?.hasPrefix("openai-oauth:") == true
        }
        let configuredKey = (primaryConfig?.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let keyProvider: (@Sendable () -> String)
        if let oauthProvider = config.oauthTokenProvider, oauthProvider() != nil {
            keyProvider = { config.oauthTokenProvider?() ?? "" }
        } else if !configuredKey.isEmpty {
            keyProvider = { configuredKey }
        } else {
            return nil
        }

        let baseURL = CoreModelProviderFactory.parseURL(primaryConfig?.apiUrl)
            ?? OpenAIOAuthModel.defaultBaseURL

        let settings = OpenAIModelProvider.Settings(
            apiKey: keyProvider,
            baseURL: baseURL,
            accountId: config.oauthAccountId,
            refreshTokenIfNeeded: config.oauthTokenRefresh,
            refreshTokenAfterInvalidToken: config.oauthTokenForceRefresh,
            session: config.proxySession,
            modelIdentifierPrefix: "openai-oauth:",
            useOpenAICodexOAuthPath: true
        )

        return OpenAIModelProvider(
            id: "openai-oauth",
            supportedModels: models,
            settings: settings,
            tools: config.tools,
            systemInstructions: config.systemInstructions
        )
    }

    private func isOpenAIOAuthEntry(_ model: CoreConfig.ModelConfig) -> Bool {
        let catalog = model.providerCatalogId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if catalog == "openai-oauth" {
            return true
        }
        let title = model.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return title.contains("oauth") || title.contains("deeplink")
    }
}
