import Foundation
import PluginSDK

struct KimiModelProviderFactory: ModelProviderFactory {
    static let id = "kimi"
    static let prefix = "kimi:"
    static let keyName = "KIMI_API_KEY"

    static func credentials(
        apiKey: String?,
        apiURL: String?,
        environmentLookup: (String) -> String?
    ) throws -> (key: ProviderAPIKeyResolver.Resolution, url: URL)? {
        let key = try ProviderAPIKeyResolver.resolve(
            configured: apiKey, fallbackEnvironmentVariable: keyName, environmentLookup: environmentLookup
        )
        guard !key.key.isEmpty else { return nil }
        let defaultURL = key.key.hasPrefix("sk-kimi-")
            ? "https://api.kimi.ai/coding/v1" : "https://api.moonshot.ai/v1"
        let configuredURL = apiURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: configuredURL.isEmpty ? defaultURL : configuredURL),
              url.scheme?.lowercased() == "https", url.host != nil else {
            throw URLError(.badURL)
        }
        return (key, url)
    }

    /// Kimi Code OAuth always targets the membership endpoint unless a valid HTTPS URL is configured.
    static func oauthBaseURL(apiURL: String?) -> URL? {
        let configured = apiURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: configured.isEmpty ? KimiOAuthService.codingBaseURL : configured),
              url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }

    static func defaultModel(for key: String) -> String {
        key.hasPrefix("sk-kimi-") ? "kimi-for-coding" : "kimi-k2.6"
    }

    private static func defaultContextLimits(for modelID: String, baseURL: URL) -> ModelContextLimits? {
        guard let host = baseURL.host?.lowercased(),
              ["api.kimi.com", "api.kimi.ai"].contains(host),
              baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "coding/v1"
        else { return nil }

        switch modelID {
        case "kimi:k3.1-pro", "kimi:kimi-k3.1-pro":
            // Kimi Code Plus / Moderato supports 256K. Higher tiers can configure 1M.
            return ModelContextLimits(contextWindowTokens: 262_144)
        default:
            return nil
        }
    }

    func buildProvider(from config: ModelProviderBuildConfig) -> (any ModelProvider)? {
        let models = config.resolvedModels.filter { $0.hasPrefix(Self.prefix) }
        let workspaceRoot = config.coreConfig.resolvedWorkspaceRootURL()
        let oauth = KimiOAuthService(workspaceRootURL: workspaceRoot)
        let providers = models.compactMap { modelID -> (any ModelProvider)? in
            let row = config.modelConfigs.first { CoreModelProviderFactory.resolvedIdentifier(for: $0) == modelID }
            let credentials = try? Self.credentials(
                apiKey: row?.apiKey, apiURL: row?.apiUrl, environmentLookup: config.environmentLookup
            )
            let keyProvider: @Sendable () -> String
            let baseURL: URL
            var refresh: (@Sendable () async throws -> Void)?
            var refreshAfterInvalid: (@Sendable () async throws -> Void)?
            if let credentials {
                let key = credentials.key.key
                keyProvider = { key }
                baseURL = credentials.url
            } else if oauth.currentAccessToken() != nil,
                      let url = Self.oauthBaseURL(apiURL: row?.apiUrl) {
                keyProvider = { oauth.currentAccessToken() ?? "" }
                baseURL = url
                refresh = { try await oauth.ensureValidToken() }
                refreshAfterInvalid = { try await oauth.ensureValidToken(forceRefresh: true) }
            } else {
                return nil
            }
            let provider = OpenAIModelProvider(
                id: Self.id,
                supportedModels: [modelID],
                settings: .init(
                    apiKey: keyProvider,
                    baseURL: baseURL,
                    refreshTokenIfNeeded: refresh,
                    refreshTokenAfterInvalidToken: refreshAfterInvalid,
                    session: config.proxySession,
                    modelIdentifierPrefix: Self.prefix,
                    allowResponsesAPIFallback: false,
                    matchesConfiguredModelsOnly: true,
                    preserveToolCallReasoning: true
                ),
                tools: config.tools,
                systemInstructions: config.systemInstructions
            )
            guard let limits = Self.defaultContextLimits(for: modelID, baseURL: baseURL) else {
                return provider
            }
            return ContextLimitedModelProvider(wrapping: provider, limits: [modelID: limits])
        }
        if providers.count == 1 { return providers[0] }
        guard !providers.isEmpty else { return nil }
        return CompositeModelProvider(
            id: Self.id, providers: providers, tools: config.tools, systemInstructions: config.systemInstructions
        )
    }
}
