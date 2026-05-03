import AnyLanguageModel
import Foundation
import PluginSDK

struct GeminiModelProviderFactory: ModelProviderFactory {
    func buildProvider(from config: ModelProviderBuildConfig) -> (any ModelProvider)? {
        let geminiModels = config.resolvedModels.filter { $0.hasPrefix("gemini:") }
        guard !geminiModels.isEmpty else { return nil }

        let primaryConfig = config.coreConfig.models.first {
            CoreModelProviderFactory.resolvedIdentifier(for: $0)?.hasPrefix("gemini:") == true
        }

        let baseURL = CoreModelProviderFactory.parseURL(primaryConfig?.apiUrl)
            ?? GeminiLanguageModel.defaultBaseURL

        if let oauthCredentials = config.geminiOAuthCredentialsProvider?() {
            return GeminiModelProvider(
                supportedModels: geminiModels,
                apiKey: { oauthCredentials.accessToken },
                baseURL: baseURL,
                tools: config.tools,
                systemInstructions: config.systemInstructions,
                session: ProxySessionFactory.makeSession(
                    proxy: config.coreConfig.proxy,
                    protocolClasses: [GeminiOAuthURLProtocol.self]
                )
            )
        }

        let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
        let configuredKey = (primaryConfig?.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedKey = configuredKey.isEmpty ? envKey : configuredKey
        guard !resolvedKey.isEmpty else { return nil }

        return GeminiModelProvider(
            supportedModels: geminiModels,
            apiKey: { resolvedKey },
            baseURL: baseURL,
            tools: config.tools,
            systemInstructions: config.systemInstructions,
            session: config.proxySession
        )
    }
}
