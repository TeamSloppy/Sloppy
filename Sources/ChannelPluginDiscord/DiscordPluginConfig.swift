import Foundation

struct DiscordPluginConfig: Sendable {
    let botToken: String
    let allowedGuildIds: Set<String>
    let allowedChannelIds: Set<String>
    let allowedUserIds: Set<String>
    /// Maps Sloppy channelId -> Discord channel ID.
    let channelDiscordChannelMap: [String: String]

    init(
        botToken: String,
        channelDiscordChannelMap: [String: String] = [:],
        allowedGuildIds: [String] = [],
        allowedChannelIds: [String] = [],
        allowedUserIds: [String] = []
    ) {
        self.botToken = botToken
        self.channelDiscordChannelMap = channelDiscordChannelMap
        self.allowedGuildIds = Set(allowedGuildIds)
        self.allowedChannelIds = Set(allowedChannelIds)
        self.allowedUserIds = Set(allowedUserIds)
    }

    func channelId(forDiscordChannelId discordChannelId: String) -> String? {
        channelDiscordChannelMap.first(where: { $0.value == discordChannelId })?.key
    }

    func discordChannelId(forChannelId channelId: String) -> String? {
        channelDiscordChannelMap[channelId]
    }

    func isAllowed(userId: String, guildId: String?, channelId: String) -> Bool {
        if allowedGuildIds.isEmpty && allowedChannelIds.isEmpty && allowedUserIds.isEmpty {
            return true
        }

        if !allowedUserIds.isEmpty && !allowedUserIds.contains(userId) {
            return false
        }

        if !allowedGuildIds.isEmpty {
            guard let guildId, allowedGuildIds.contains(guildId) else {
                return false
            }
        }

        if !allowedChannelIds.isEmpty && !allowedChannelIds.contains(channelId) {
            return false
        }

        return true
    }
}
