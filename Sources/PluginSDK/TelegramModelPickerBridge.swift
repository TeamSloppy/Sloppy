import Foundation
import Protocols

/// Failure type for ``TelegramModelPickerBridge/telegramPickerApplyModel(bindingChannelId:modelId:)``.
public struct TelegramModelApplyError: Error, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

/// Lets the Telegram gateway query and set the per-binding model without depending on `CoreService` directly.
public protocol TelegramModelPickerBridge: Sendable {
    /// All runnable models, typically sorted by id for stable keyboard indices.
    func telegramPickerSortedModels() async -> [ProviderModelOption]

    func telegramPickerCurrentModelId(bindingChannelId: String) async -> String?

    /// Applies model selection using the same validation as `/model <id>` in the core channel handler.
    func telegramPickerApplyModel(bindingChannelId: String, modelId: String) async -> Result<String, TelegramModelApplyError>
}
