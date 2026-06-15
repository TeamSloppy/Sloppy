import Foundation
import AnyLanguageModel
import Protocols

extension CoreService {
    public func petImageGenerationStatus() async -> AgentPetImageGenerationStatusResponse {
        let models = availableAgentModels()
        let providers = Set(
            models.compactMap { option -> String? in
                let id = option.id.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty else { return nil }
                if let separator = id.firstIndex(of: ":") {
                    return String(id[..<separator])
                }
                return "model"
            }
        )
        let ordered = providers.sorted()
        return AgentPetImageGenerationStatusResponse(
            available: !models.isEmpty,
            providers: ordered,
            message: models.isEmpty
                ? "No model provider is configured. Preset pets will be used."
                : "Pet generation can use any configured text model."
        )
    }

    public func generatePetDraft(_ request: AgentPetGenerationRequest) async throws -> AgentPetGenerationResponse {
        if request.mode == .prompt {
            let prompt = request.prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !prompt.isEmpty else {
                throw AgentStorageError.invalidPayload
            }
        }

        let draft = try await generateModelPetDraft(request) ?? AgentPetFactory.makePetDraft(request: request)
        do {
            try agentCatalogStore.writePetDraft(draft)
        } catch {
            throw AgentStorageError.invalidPayload
        }
        return draft.response
    }

    private func generateModelPetDraft(_ request: AgentPetGenerationRequest) async throws -> AgentPetDraftRecord? {
        let requestedModel = request.model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !requestedModel.isEmpty else { return nil }
        guard let modelProvider else { return nil }

        let modelID: String
        if modelProvider.supports(modelName: requestedModel) {
            modelID = requestedModel
        } else if let fallback = modelProvider.supportedModels.first {
            modelID = fallback
        } else {
            return nil
        }

        do {
            let languageModel = try await modelProvider.createLanguageModel(for: modelID)
            let session = LanguageModelSession(model: languageModel, tools: [])
            let options = modelProvider.generationOptions(for: modelID, maxTokens: 1_200, reasoningEffort: nil)
            let prompt = petBriefPrompt(for: request)
            let content = try await session.respond(to: prompt, options: options).content
            guard let brief = decodePetBrief(from: content) else {
                return nil
            }
            return AgentPetFactory.makePetDraft(request: request, brief: brief, modelResponse: content)
        } catch {
            logger.warning("pet.model_generation_failed", metadata: ["model": "\(modelID)", "error": "\(error.localizedDescription)"])
            return nil
        }
    }

    private func petBriefPrompt(for request: AgentPetGenerationRequest) -> String {
        let userPrompt = request.prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let constraints = userPrompt.isEmpty ? "Invent a surprising but readable Sloppie pet." : userPrompt
        return """
        Generate one original Sloppie pet design as strict JSON only.
        User request: \(constraints)

        Choose ids only from these allowed catalogs:
        headId: head_vladimir, head-cube, head-shell, head-fork, head-visor, head-probe, head-oracle, head-crown
        bodyId: body-core, body-puff, body-brick, body-terminal, body-satchel, body-relay, body-reactor, body-throne
        legsId: legs-stub, legs-bouncer, legs-track, legs-sprinter, legs-spider, legs-piston, legs-hover, legs-singularity
        faceId: face-default, face-mono, face-scan, face-grin, face-frown, face-x, face-star, face-halo
        accessoryId: acc-none, acc-scarf, acc-badge, acc-cape, acc-chain, acc-stripe, acc-wings, acc-bolt

        Return exactly this JSON shape and no markdown:
        {
          "displayName": "Short pet name",
          "speciesId": "kebab-case-species",
          "headId": "head-visor",
          "bodyId": "body-puff",
          "legsId": "legs-bouncer",
          "faceId": "face-star",
          "accessoryId": "acc-scarf",
          "idleFace": "(o_o)",
          "happyFace": "(^_^)",
          "sadFace": "(._.)",
          "sleepFace": "(-_-)"
        }
        """
    }

    private func decodePetBrief(from text: String) -> AgentPetModelBrief? {
        guard let data = extractJSONObject(from: text)?.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(AgentPetModelBrief.self, from: data)
    }

    private func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end
        else {
            return nil
        }
        return String(text[start...end])
    }
}
