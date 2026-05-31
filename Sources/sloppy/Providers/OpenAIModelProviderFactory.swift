import AnyLanguageModel
import Foundation
import PluginSDK

/// OpenAI model provider factory.
struct OpenAIModelProviderFactory: ModelProviderFactory {
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

        let primaryConfig = config.modelConfigs.first {
            CoreModelProviderFactory.resolvedIdentifier(for: $0)?.hasPrefix("openai-api:") == true
        }
        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        let configuredKey = (primaryConfig?.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedStaticKey = configuredKey.isEmpty ? apiKey : configuredKey

        let parsedPrimaryURL = CoreModelProviderFactory.parseURL(primaryConfig?.apiUrl)
        let allowKeylessLAN = parsedPrimaryURL.map { OpenAICompatibleCatalogEndpoint.hostAllowsKeylessOpenAIProbe(host: $0.host) } ?? false

        let keyProvider: (@Sendable () -> String)
        if !resolvedStaticKey.isEmpty {
            keyProvider = { resolvedStaticKey }
        } else if allowKeylessLAN {
            keyProvider = { "" }
        } else {
            return nil
        }

        let baseURL = CoreModelProviderFactory.parseURL(primaryConfig?.apiUrl)
            ?? OpenAILanguageModel.defaultBaseURL

        let settings = OpenAIModelProvider.Settings(
            apiKey: keyProvider,
            baseURL: baseURL,
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
