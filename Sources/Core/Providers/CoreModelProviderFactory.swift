import AnyLanguageModel
import Foundation
import PluginSDK

struct ModelProviderBuildConfig: @unchecked Sendable {
    var coreConfig: CoreConfig
    var resolvedModels: [String]
    var tools: [any Tool]
    var oauthTokenProvider: (@Sendable () -> String?)?
    var oauthAccountId: String?
    var oauthTokenRefresh: (@Sendable () async throws -> Void)?
    var systemInstructions: String?
}

protocol ModelProviderFactory: Sendable {
    func buildProvider(from config: ModelProviderBuildConfig) -> (any ModelProvider)?
}

enum CoreModelProviderFactory {
    private static let factories: [any ModelProviderFactory] = [
        OpenAIModelProviderFactory(),
        OllamaModelProviderFactory(),
        GeminiModelProviderFactory(),
        AnthropicModelProviderFactory(),
    ]

    static func buildModelProvider(
        config: CoreConfig,
        resolvedModels: [String],
        tools: [any Tool] = [],
        oauthTokenProvider: (@Sendable () -> String?)? = nil,
        oauthAccountId: String? = nil,
        oauthTokenRefresh: (@Sendable () async throws -> Void)? = nil,
        systemInstructions: String? = nil
    ) -> (any ModelProvider)? {
        let buildConfig = ModelProviderBuildConfig(
            coreConfig: config,
            resolvedModels: resolvedModels,
            tools: tools,
            oauthTokenProvider: oauthTokenProvider,
            oauthAccountId: oauthAccountId,
            oauthTokenRefresh: oauthTokenRefresh,
            systemInstructions: systemInstructions
        )

        let providers = factories.compactMap { $0.buildProvider(from: buildConfig) }
        guard !providers.isEmpty else { return nil }
        if providers.count == 1 { return providers[0] }

        return CompositeModelProvider(
            providers: providers,
            tools: tools,
            systemInstructions: systemInstructions
        )
    }

    /// Resolves model identifiers from config, adding fallback OpenAI defaults when needed.
    /// Only models with a recognized provider prefix are included (no unprefixed models).
    static func resolveModelIdentifiers(
        config: CoreConfig,
        hasOAuthCredentials: Bool = false
    ) -> [String] {
        var identifiers = config.models.compactMap { resolvedIdentifier(for: $0) }
        let hasOpenAI = identifiers.contains { $0.hasPrefix("openai:") }
        let environmentKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !hasOpenAI, !environmentKey.isEmpty {
            identifiers.append("openai:gpt-5.1-mini")
        }
        if !hasOpenAI, environmentKey.isEmpty, hasOAuthCredentials {
            identifiers.append("openai:gpt-5-codex-mini")
        }

        return identifiers
    }

    /// Returns the prefixed model identifier (e.g. "openai:gpt-4o") or `nil` if the
    /// provider cannot be inferred, rejecting unprefixed models.
    static func resolvedIdentifier(for model: CoreConfig.ModelConfig) -> String? {
        let modelValue = model.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelValue.isEmpty else { return nil }

        if modelValue.hasPrefix("openai:") || modelValue.hasPrefix("ollama:")
            || modelValue.hasPrefix("gemini:") || modelValue.hasPrefix("anthropic:") {
            return modelValue
        }

        guard let provider = inferredProvider(model: model) else { return nil }
        return "\(provider):\(modelValue)"
    }

    private static func inferredProvider(model: CoreConfig.ModelConfig) -> String? {
        let title = model.title.lowercased()
        let apiURL = model.apiUrl.lowercased()

        if title.contains("openai") || apiURL.contains("openai") {
            return "openai"
        }

        if title.contains("ollama") || apiURL.contains("ollama") || apiURL.contains("11434") {
            return "ollama"
        }

        if title.contains("gemini") || apiURL.contains("generativelanguage.googleapis.com") {
            return "gemini"
        }

        if title.contains("anthropic") || apiURL.contains("anthropic") {
            return "anthropic"
        }

        return nil
    }

    static func parseURL(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)
    }
}
