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

    static func defaultModel(for key: String) -> String {
        key.hasPrefix("sk-kimi-") ? "kimi-for-coding" : "kimi-k2.6"
    }

    func buildProvider(from config: ModelProviderBuildConfig) -> (any ModelProvider)? {
        let models = config.resolvedModels.filter { $0.hasPrefix(Self.prefix) }
        let providers = models.compactMap { modelID -> OpenAIModelProvider? in
            let row = config.modelConfigs.first { CoreModelProviderFactory.resolvedIdentifier(for: $0) == modelID }
            guard let credentials = try? Self.credentials(
                apiKey: row?.apiKey, apiURL: row?.apiUrl, environmentLookup: config.environmentLookup
            ) else { return nil }
            let key = credentials.key.key
            return OpenAIModelProvider(
                id: Self.id,
                supportedModels: [modelID],
                settings: .init(
                    apiKey: { key },
                    baseURL: credentials.url,
                    session: config.proxySession,
                    modelIdentifierPrefix: Self.prefix,
                    allowResponsesAPIFallback: false,
                    matchesConfiguredModelsOnly: true,
                    preserveToolCallReasoning: true
                ),
                tools: config.tools,
                systemInstructions: config.systemInstructions
            )
        }
        if providers.count == 1 { return providers[0] }
        guard !providers.isEmpty else { return nil }
        return CompositeModelProvider(
            id: Self.id, providers: providers, tools: config.tools, systemInstructions: config.systemInstructions
        )
    }
}
