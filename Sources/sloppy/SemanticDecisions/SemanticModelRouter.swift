import Foundation
import Logging
import Protocols

struct SemanticModelRoute: Sendable, Equatable {
    var profile: String
    var model: String
    var confidence: Double
    var probabilities: [String: Double]
    var mode: CoreConfig.SemanticDecisions.Mode

    var shouldApply: Bool {
        mode == .active
    }
}

actor SemanticModelRouter {
    typealias ProviderFactory = @Sendable (CoreConfig.SemanticDecisions) -> (any SemanticDecisionProvider)?

    private var config: CoreConfig.SemanticDecisions
    private let usageMeter: SemanticDecisionUsageMeter
    private let providerFactory: ProviderFactory
    private let logger: Logger

    init(
        config: CoreConfig.SemanticDecisions,
        usageMeter: SemanticDecisionUsageMeter,
        providerFactory: @escaping ProviderFactory = SemanticModelRouter.defaultProvider,
        logger: Logger = .sloppy(label: "sloppy.semantic-model-router")
    ) {
        self.config = config
        self.usageMeter = usageMeter
        self.providerFactory = providerFactory
        self.logger = logger
    }

    func updateConfig(_ config: CoreConfig.SemanticDecisions) {
        self.config = config
    }

    func route(
        channelID: String,
        userRequest: String,
        chatMode: AgentChatMode?,
        attachmentTypes: [String],
        availableModelIDs: Set<String>
    ) async -> SemanticModelRoute? {
        guard config.executorModelRouting != .disabled,
              let provider = providerFactory(config)
        else {
            return nil
        }

        let profiles = config.modelProfiles.filter { _, profile in
            availableModelIDs.contains(profile.model)
        }
        guard profiles.count >= 2 else {
            return nil
        }

        let state = ModelRoutingState(
            request: userRequest,
            chatMode: chatMode?.rawValue,
            attachmentTypes: attachmentTypes,
            availableProfiles: profiles.keys.sorted()
        )
        guard let stateData = try? JSONEncoder().encode(state),
              let stateString = String(data: stateData, encoding: .utf8)
        else {
            return nil
        }

        do {
            let response = try await provider.choose(
                SemanticChoiceRequest(
                    state: stateString,
                    questionID: "executor_profile",
                    instructions: "Choose the least expensive execution profile that can reliably complete the user's request. Prefer stronger profiles when the task requires deep reasoning, architecture, debugging, broad code changes, or high-stakes correctness.",
                    choices: profiles.mapValues { $0.description }
                )
            )
            await usageMeter.record(channelID: channelID, usage: response.usage)
            guard response.confidence >= config.minimumConfidence,
                  let selected = profiles[response.choice]
            else {
                logger.info("Jev model route fell back to the configured model", metadata: [
                    "channel_id": .string(channelID),
                    "confidence": .stringConvertible(response.confidence),
                ])
                return nil
            }
            return SemanticModelRoute(
                profile: response.choice,
                model: selected.model,
                confidence: response.confidence,
                probabilities: response.probabilities,
                mode: config.executorModelRouting
            )
        } catch {
            logger.warning("Jev model routing failed; using the configured model", metadata: [
                "channel_id": .string(channelID),
                "error": .string(error.localizedDescription),
            ])
            return nil
        }
    }

    nonisolated static func defaultProvider(
        config: CoreConfig.SemanticDecisions
    ) -> (any SemanticDecisionProvider)? {
        guard let provider = config.provider else { return nil }
        let configuredEnvironmentName = config.apiKeyEnvironmentVariable.trimmingCharacters(in: .whitespacesAndNewlines)
        let environmentName: String
        if configuredEnvironmentName.isEmpty {
            environmentName = provider == .vercel ? "AI_GATEWAY_API_KEY" : "TYPESAFE_API_KEY"
        } else {
            environmentName = configuredEnvironmentName
        }
        guard !environmentName.isEmpty,
              let apiKey = ProcessInfo.processInfo.environment[environmentName]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty
        else {
            return nil
        }
        let defaultURL: String
        switch provider {
        case .typeSafe:
            defaultURL = "https://api.typesafe.ai/v1/systemone"
        case .vercel:
            defaultURL = "https://ai-gateway.vercel.sh/typesafe/v1/systemone"
        }
        let rawURL = config.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let endpoint = URL(string: rawURL.isEmpty ? defaultURL : rawURL) else {
            return nil
        }
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return JevSemanticDecisionProvider(
            endpoint: endpoint,
            apiKey: apiKey,
            model: model.isEmpty ? (provider == .vercel ? "typesafe-ai/jev" : "jev-latest") : model,
            timeoutMs: config.timeoutMs,
            inputCostPerMillionTokensUSD: config.inputCostPerMillionTokensUSD
        )
    }

    private struct ModelRoutingState: Encodable {
        var request: String
        var chatMode: String?
        var attachmentTypes: [String]
        var availableProfiles: [String]
    }
}
