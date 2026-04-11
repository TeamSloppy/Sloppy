import Foundation
import PluginSDK
import Protocols

extension CoreService: TelegramModelPickerBridge {
    public func telegramPickerSortedModels() async -> [ProviderModelOption] {
        availableAgentModels().sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    public func telegramPickerCurrentModelId(bindingChannelId: String) async -> String? {
        await channelModelStore.get(channelId: bindingChannelId)
    }

    public func telegramPickerApplyModel(bindingChannelId: String, modelId: String) async -> Result<String, TelegramModelApplyError> {
        let trimmed = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(TelegramModelApplyError("Empty model id."))
        }
        let available = availableAgentModels()
        let hasOAuth = openAIOAuthService.currentAccessToken() != nil
        let canonical: String?
        if let resolved = CoreService.resolveCanonicalAgentModelID(trimmed, availableModels: available) {
            canonical = resolved
        } else if CoreService.isRuntimeRoutableModelID(trimmed, config: currentConfig, hasOAuthCredentials: hasOAuth) {
            canonical = trimmed
        } else {
            canonical = nil
        }
        guard let canonical else {
            return .failure(TelegramModelApplyError("Unknown model: \(trimmed)"))
        }
        await channelModelStore.set(channelId: bindingChannelId, model: canonical)
        return .success(canonical)
    }
}
