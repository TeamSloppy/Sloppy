import AnyLanguageModel
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PluginSDK

struct OpenCodeModelProviderFactory: ModelProviderFactory {
    func buildProvider(from config: ModelProviderBuildConfig) -> (any ModelProvider)? {
        let rows = config.modelConfigs.compactMap { model -> (config: CoreConfig.ModelConfig, resolvedId: String)? in
            guard let id = CoreModelProviderFactory.resolvedIdentifier(for: model),
                  id.hasPrefix("opencode:")
            else { return nil }
            return (model, id)
        }
        guard !rows.isEmpty else { return nil }

        struct GroupKey: Hashable {
            var providerID: String
            var apiURL: String
            var apiKey: String
            var usesResponses: Bool
        }

        func groupKey(for row: CoreConfig.ModelConfig) -> GroupKey? {
            guard let provider = Self.providerMetadata(from: row) else { return nil }
            let rawURL = row.apiUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawURL.isEmpty else { return nil }
            let apiKey = Self.resolveAPIKey(
                configured: row.apiKey,
                providerID: provider.id,
                apiURL: rawURL,
                settings: config.coreConfig.opencode
            )
            return GroupKey(
                providerID: provider.id,
                apiURL: rawURL,
                apiKey: apiKey,
                usesResponses: provider.usesResponses
            )
        }

        let grouped = Dictionary(grouping: rows) { row in
            groupKey(for: row.config)
        }

        var subproviders: [OpenAIModelProvider] = []
        for (maybeKey, groupRows) in grouped {
            guard let key = maybeKey,
                  let baseURL = CoreModelProviderFactory.parseURL(key.apiURL)
            else { continue }

            let allowKeyless = OpenAICompatibleCatalogEndpoint.hostAllowsKeylessOpenAIProbe(host: baseURL.host)
            guard !key.apiKey.isEmpty || allowKeyless else { continue }

            let supportedModels = groupRows.map(\.resolvedId)
            let settings = OpenAIModelProvider.Settings(
                apiKey: { key.apiKey },
                baseURL: baseURL,
                apiVariant: .chatCompletions,
                session: config.proxySession,
                modelIdentifierPrefix: "opencode:\(key.providerID)/",
                useOpenAICodexOAuthPath: false,
                allowResponsesAPIFallback: false,
                useOpenResponsesLanguageModel: key.usesResponses
            )
            subproviders.append(
                OpenAIModelProvider(
                    id: "opencode",
                    supportedModels: supportedModels,
                    settings: settings,
                    tools: config.tools,
                    systemInstructions: config.systemInstructions
                )
            )
        }

        guard !subproviders.isEmpty else { return nil }
        if subproviders.count == 1 {
            return subproviders[0]
        }
        return CompositeModelProvider(
            id: "opencode",
            providers: subproviders,
            tools: config.tools,
            systemInstructions: config.systemInstructions
        )
    }

    private static func providerMetadata(from model: CoreConfig.ModelConfig) -> (id: String, usesResponses: Bool)? {
        let catalog = model.providerCatalogId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard catalog.hasPrefix("opencode:") else { return providerID(fromModelID: model.model).map { ($0, false) } }

        let raw = String(catalog.dropFirst("opencode:".count))
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, !first.isEmpty else { return nil }
        let usesResponses = parts.dropFirst().first == "responses"
        return (String(first), usesResponses)
    }

    private static func providerID(fromModelID modelID: String) -> String? {
        let prefix = "opencode:"
        guard modelID.hasPrefix(prefix) else { return nil }
        let rest = String(modelID.dropFirst(prefix.count))
        guard let separator = rest.firstIndex(of: "/") else { return nil }
        let providerID = String(rest[..<separator])
        return providerID.isEmpty ? nil : providerID
    }

    static func resolveAPIKey(
        configured: String,
        providerID: String,
        apiURL: String,
        settings: CoreConfig.OpenCode
    ) -> String {
        let configured = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        if let resolved = resolveConfiguredSecret(configured), !resolved.isEmpty {
            return resolved
        }

        let configuredAuthPath = settings.authPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let path = configuredAuthPath.isEmpty
            ? OpenCodeConfigImporter.expandPath("~/.local/share/opencode/auth.json")
            : OpenCodeConfigImporter.expandPath(configuredAuthPath)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "" }

        for key in [providerID, apiURL] {
            if let value = secretValue(object[key]) {
                return value
            }
        }

        return ""
    }

    private static func resolveConfiguredSecret(_ value: String) -> String? {
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("{env:"), value.hasSuffix("}") {
            let name = String(value.dropFirst("{env:".count).dropLast())
            return ProcessInfo.processInfo.environment[name]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if value.hasPrefix("$") {
            let name = String(value.dropFirst())
            return ProcessInfo.processInfo.environment[name]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    private static func secretValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let object = value as? [String: Any] {
            for key in ["apiKey", "api_key", "token", "accessToken", "access_token"] {
                if let value = secretValue(object[key]) {
                    return value
                }
            }
        }
        return nil
    }
}
