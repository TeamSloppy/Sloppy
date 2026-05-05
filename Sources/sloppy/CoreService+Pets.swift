import Foundation
import Protocols

extension CoreService {
    public func petImageGenerationStatus() async -> AgentPetImageGenerationStatusResponse {
        let config = currentConfig
        let modelIds = CoreModelProviderFactory.resolveModelIdentifiers(
            config: config,
            hasOAuthCredentials: openAIOAuthService.currentAccessToken() != nil
        )
        var providers: Set<String> = []
        for modelId in modelIds {
            let lowered = modelId.lowercased()
            if lowered.hasPrefix("openai:") || lowered.contains("gpt") {
                providers.insert("openai")
            }
            if lowered.hasPrefix("gemini:") || lowered.contains("gemini") || lowered.contains("google") {
                providers.insert("gemini")
            }
        }

        let openAIStatus = openAIProviderStatus()
        if openAIStatus.hasAnyKey || openAIStatus.hasOAuthCredentials {
            providers.insert("openai")
        }

        let ordered = providers.sorted()
        return AgentPetImageGenerationStatusResponse(
            available: !ordered.isEmpty,
            providers: ordered,
            message: ordered.isEmpty
                ? "No OpenAI or Gemini image-capable provider is configured. Preset pets will be used."
                : "Pet image generation can use \(ordered.joined(separator: ", "))."
        )
    }

    public func generatePetDraft(_ request: AgentPetGenerationRequest) async throws -> AgentPetGenerationResponse {
        if request.mode == .prompt {
            let prompt = request.prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !prompt.isEmpty else {
                throw AgentStorageError.invalidPayload
            }
        }

        let draft = AgentPetFactory.makePetDraft(request: request)
        do {
            try agentCatalogStore.writePetDraft(draft)
        } catch {
            throw AgentStorageError.invalidPayload
        }
        return draft.response
    }
}
