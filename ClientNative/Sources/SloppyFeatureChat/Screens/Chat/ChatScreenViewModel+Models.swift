import Foundation
import Observation
import SloppyClientCore
import SloppyClientUI
import SwiftUI
import UniformTypeIdentifiers

extension ChatScreenViewModel {
    var selectedModelSupportsReasoningEffort: Bool {
        guard let selectedModel = availableModels.first(where: { $0.id == selectedModelId }) else {
            return false
        }
        return selectedModel.supportsReasoningEffort
    }

    func restoreModelSelection(agentId: String, sessionId: String?) {
        restoreApprovalMode(agentId: agentId, sessionId: sessionId)
        selectedModelId = modelPreferences.selection(
            server: apiClient.endpoint.cacheNamespace,
            agentId: agentId,
            sessionId: sessionId
        ) ?? availableModels.first?.id ?? ""
        selectedReasoningEffort = .default
    }

    func rememberCurrentModelSelection(agentId: String, sessionId: String) {
        guard !selectedModelId.isEmpty else { return }
        modelPreferences.rememberSessionSelection(
            selectedModelId,
            server: apiClient.endpoint.cacheNamespace,
            agentId: agentId,
            sessionId: sessionId
        )
    }

    func applyAvailableModels(_ models: [ChatModelOption]) {
        availableModels = models
        if selectedModelId == ChatModelSelection.automaticJEVId {
            return
        }
        guard !models.isEmpty else {
            selectedModelId = ""
            selectedReasoningEffort = .default
            return
        }

        if !models.contains(where: { $0.id == selectedModelId }) {
            selectedModelId = models[0].id
            selectedReasoningEffort = .default
        }
    }
}
