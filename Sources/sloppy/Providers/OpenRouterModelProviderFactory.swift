import AnyLanguageModel
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PluginSDK

/// OpenRouter ([openrouter.ai](https://openrouter.ai)) via AnyLanguageModel `OpenResponsesLanguageModel`.
/// Supports multiple endpoints: group `models[]` rows by `(apiUrl, apiKey)` so each Open Responses host gets its own `OpenAIModelProvider`.
struct OpenRouterModelProviderFactory: ModelProviderFactory {
    func buildProvider(from config: ModelProviderBuildConfig) -> (any ModelProvider)? {
        let openRouterModels = config.resolvedModels.filter { $0.hasPrefix("openrouter:") }
        guard !openRouterModels.isEmpty else { return nil }

        let envKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var rows: [(config: CoreConfig.ModelConfig, resolvedId: String)] = []
        for model in config.coreConfig.models {
            guard let id = CoreModelProviderFactory.resolvedIdentifier(for: model),
                  id.hasPrefix("openrouter:") else { continue }
            rows.append((model, id))
        }

        if rows.isEmpty {
            guard !envKey.isEmpty else { return nil }
            return makeOpenRouterProvider(
                config: config,
                supportedModels: openRouterModels,
                baseURL: OpenRouterLanguageModelSupport.defaultBaseURL,
                apiKey: envKey
            )
        }

        func resolveKey(for row: CoreConfig.ModelConfig) -> String {
            let configured = row.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            return configured.isEmpty ? envKey : configured
        }

        struct GroupKey: Hashable {
            var normalizedURL: String
            var resolvedKey: String
        }

        func groupKey(for row: CoreConfig.ModelConfig) -> GroupKey {
            let urlRaw = row.apiUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            let urlPart = urlRaw.isEmpty ? OpenRouterLanguageModelSupport.defaultBaseURL.absoluteString : urlRaw
            return GroupKey(normalizedURL: urlPart, resolvedKey: resolveKey(for: row))
        }

        let grouped = Dictionary(grouping: rows, by: { groupKey(for: $0.config) })
        var subproviders: [OpenAIModelProvider] = []
        for (_, groupRows) in grouped.sorted(by: { $0.key.normalizedURL < $1.key.normalizedURL }) {
            guard let first = groupRows.first else { continue }
            let key = resolveKey(for: first.config)
            guard !key.isEmpty else { continue }
            let urlRaw = first.config.apiUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseURL = CoreModelProviderFactory.parseURL(urlRaw.isEmpty ? nil : urlRaw)
                ?? OpenRouterLanguageModelSupport.defaultBaseURL
            let ids = groupRows.map(\.resolvedId)
            guard !ids.isEmpty, let provider = makeOpenRouterProvider(
                config: config,
                supportedModels: ids,
                baseURL: baseURL,
                apiKey: key
            ) else { continue }
            subproviders.append(provider)
        }

        guard !subproviders.isEmpty else { return nil }
        if subproviders.count == 1 {
            return subproviders[0]
        }
        return CompositeModelProvider(
            id: "openrouter",
            providers: subproviders,
            tools: config.tools,
            systemInstructions: config.systemInstructions
        )
    }

    private func makeOpenRouterProvider(
        config: ModelProviderBuildConfig,
        supportedModels: [String],
        baseURL: URL,
        apiKey: String
    ) -> OpenAIModelProvider? {
        guard !apiKey.isEmpty else { return nil }
        let session: URLSession? = config.proxySession ?? OpenRouterLanguageModelSupport.makeURLSession()
        let settings = OpenAIModelProvider.Settings(
            apiKey: { apiKey },
            baseURL: baseURL,
            apiVariant: .chatCompletions,
            accountId: nil,
            refreshTokenIfNeeded: nil,
            session: session,
            modelIdentifierPrefix: "openrouter:",
            useOpenAICodexOAuthPath: false,
            allowResponsesAPIFallback: false,
            useOpenResponsesLanguageModel: true
        )

        return OpenAIModelProvider(
            id: "openrouter",
            supportedModels: supportedModels,
            settings: settings,
            tools: config.tools,
            systemInstructions: config.systemInstructions
        )
    }
}
