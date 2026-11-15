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
        if hasLoadedModelCatalog { validateModelSelection() }
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
        hasLoadedModelCatalog = true
        validateModelSelection()
    }

    private func validateModelSelection() {
        guard selectedModelId != ChatModelSelection.automaticJEVId,
              !availableModels.contains(where: { $0.id == selectedModelId }) else { return }
        selectedModelId = availableModels.first?.id ?? ""
        selectedReasoningEffort = .default
    }
}
