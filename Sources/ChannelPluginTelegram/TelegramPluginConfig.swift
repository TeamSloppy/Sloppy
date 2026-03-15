import Foundation

struct TelegramPluginConfig: Sendable {
    let botToken: String
    let allowedUserIds: Set<Int64>
    let allowedChatIds: Set<Int64>
    /// Maps Sloppy channelId → Telegram chat_id.
    let channelChatMap: [String: Int64]

    /// Initialise from structured config values (used when loading from CoreConfig).
    init(
        botToken: String,
        channelChatMap: [String: Int64] = [:],
        allowedUserIds: [Int64] = [],
        allowedChatIds: [Int64] = []
    ) {
        self.botToken = botToken
        self.channelChatMap = channelChatMap
        self.allowedUserIds = Set(allowedUserIds)
        self.allowedChatIds = Set(allowedChatIds)
    }

    /// Reverse lookup: Telegram chat_id → channelId.
    /// Tries an exact match first; falls back to a catch-all binding (chatId == 0).
    func channelId(forChatId chatId: Int64) -> String? {
        if let exact = channelChatMap.first(where: { $0.value == chatId }) {
            return exact.key
        }
        return channelChatMap.first(where: { $0.value == 0 })?.key
    }

    func chatId(forChannelId channelId: String) -> Int64? {
        channelChatMap[channelId]
    }

    /// Returns true when the userId is permitted. Chat ID is not checked here —
    /// chat-level restriction is handled by the binding's configured chatId.
    func isAllowed(userId: Int64) -> Bool {
        allowedUserIds.isEmpty || allowedUserIds.contains(userId)
    }
}
