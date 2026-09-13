import Foundation
import AnyLanguageModel
import PluginSDK

struct SloppyModelProviderFactory: ModelProviderFactory {
    func buildProvider(from config: ModelProviderBuildConfig) -> (any ModelProvider)? {
        let entries = config.modelConfigs.filter {
            CoreModelProviderFactory.resolvedIdentifier(for: $0)?.hasPrefix("sloppy:") == true
        }
        let models = config.resolvedModels.filter { $0.hasPrefix("sloppy:") }
        guard !models.isEmpty else { return nil }
        let singleServer = entries.first.flatMap { first in
            entries.allSatisfy { $0.apiUrl == first.apiUrl && $0.apiKey == first.apiKey } ? first : nil
        }
        return AnyModelProviderBox(
            id: "sloppy", supportedModels: models, systemInstructions: config.systemInstructions, tools: config.tools,
            createLanguageModel: { name in
                guard let entry = entries.first(where: { CoreModelProviderFactory.resolvedIdentifier(for: $0) == name }) ?? singleServer else {
                    throw SloppyRemoteError.unknownModel
                }
                _ = try SloppyRemoteEndpoint.url(base: entry.apiUrl, path: "providers/inference")
                return SloppyRemoteModel(
                    baseURL: entry.apiUrl,
                    accessToken: entry.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    model: String(name.dropFirst("sloppy:".count)),
                    session: config.proxySession ?? SloppyURLSessionFactory.shared
                )
            },
            generationOptions: { _, maxTokens, effort in
                var options = GenerationOptions(maximumResponseTokens: maxTokens)
                options[custom: SloppyRemoteModel.self] = .init(reasoningEffort: effort)
                return options
            },
            supports: { models.contains($0) || (singleServer != nil && $0.hasPrefix("sloppy:")) }
        )
    }
}
