import Testing
@testable import ChannelPluginTelegram

@Test func channelIdForChatId_exactMatch() {
    let config = TelegramPluginConfig(
        botToken: "token",
        channelChatMap: ["chan-a": 111, "chan-b": 222]
    )
    #expect(config.channelId(forChatId: 111) == "chan-a")
    #expect(config.channelId(forChatId: 222) == "chan-b")
}

@Test func channelIdForChatId_fallsBackToCatchAll() {
    let config = TelegramPluginConfig(
        botToken: "token",
        channelChatMap: ["catch-all": 0, "specific": 999]
    )
    // Unknown chatId → catch-all
    #expect(config.channelId(forChatId: 12345) == "catch-all")
    // Exact match still wins
    #expect(config.channelId(forChatId: 999) == "specific")
}

@Test func channelIdForChatId_noBindingReturnsNil() {
    let config = TelegramPluginConfig(
        botToken: "token",
        channelChatMap: ["specific": 100]
    )
    #expect(config.channelId(forChatId: 999) == nil)
}

@Test func isAllowed_emptyListPermitsAll() {
    let config = TelegramPluginConfig(botToken: "token", allowedUserIds: [])
    #expect(config.isAllowed(userId: 42))
    #expect(config.isAllowed(userId: 0))
}

@Test func isAllowed_checksByUserIdOnly() {
    let config = TelegramPluginConfig(botToken: "token", allowedUserIds: [10, 20])
    #expect(config.isAllowed(userId: 10))
    #expect(config.isAllowed(userId: 20))
    #expect(!config.isAllowed(userId: 99))
}
