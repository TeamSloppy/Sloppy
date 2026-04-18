import AnyLanguageModel
import Foundation
import PluginSDK

struct AnthropicModelProviderFactory: ModelProviderFactory {
    func buildProvider(from config: ModelProviderBuildConfig) -> (any ModelProvider)? {
        let anthropicModels = config.resolvedModels.filter { $0.hasPrefix("anthropic:") }
        guard !anthropicModels.isEmpty else { return nil }

        let oauthConfig = config.coreConfig.models.first {
            guard CoreModelProviderFactory.resolvedIdentifier(for: $0)?.hasPrefix("anthropic:") == true else {
                return false
            }
            return isAnthropicOAuthEntry($0)
        }

        let plainConfig = config.coreConfig.models.first {
            CoreModelProviderFactory.resolvedIdentifier(for: $0)?.hasPrefix("anthropic:") == true
        }

        if let oauthConfig {
            let configuredKey = oauthConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let envAnthropicToken = ProcessInfo.processInfo.environment["ANTHROPIC_TOKEN"]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let envClaudeCodeToken = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let legacyAPIKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let baseURL = CoreModelProviderFactory.parseURL(oauthConfig.apiUrl)
                ?? OAuthAnthropicLanguageModel.defaultBaseURL

            let keyProvider: @Sendable () -> String = {
                let resolvedOAuth = config.anthropicOAuthTokenProvider?()?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !resolvedOAuth.isEmpty { return resolvedOAuth }
                if !configuredKey.isEmpty { return configuredKey }
                if !envAnthropicToken.isEmpty { return envAnthropicToken }
                if !envClaudeCodeToken.isEmpty { return envClaudeCodeToken }
                if !legacyAPIKey.isEmpty, isOAuthStyleToken(legacyAPIKey) {
                    return legacyAPIKey
                }
                return ""
            }

            guard !keyProvider().isEmpty else { return nil }

            return AnthropicModelProvider(
                supportedModels: anthropicModels,
                apiKey: keyProvider,
                baseURL: baseURL,
                tools: config.tools,
                systemInstructions: config.systemInstructions,
                session: config.proxySession,
                refreshTokenIfNeeded: config.anthropicOAuthTokenRefresh
            )
        }

        let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
        let configuredKey = (plainConfig?.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedKey = configuredKey.isEmpty ? envKey : configuredKey
        guard !resolvedKey.isEmpty else { return nil }

        let baseURL = CoreModelProviderFactory.parseURL(plainConfig?.apiUrl)
            ?? OAuthAnthropicLanguageModel.defaultBaseURL

        return AnthropicModelProvider(
            supportedModels: anthropicModels,
            apiKey: { resolvedKey },
            baseURL: baseURL,
            tools: config.tools,
            systemInstructions: config.systemInstructions,
            session: config.proxySession
        )
    }

    private func isAnthropicOAuthEntry(_ model: CoreConfig.ModelConfig) -> Bool {
        let catalog = model.providerCatalogId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if catalog == "anthropic-oauth" {
            return true
        }
        return model.title.lowercased().contains("anthropic-oauth")
    }

    private func isOAuthStyleToken(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix("sk-ant-api")
    }
}
