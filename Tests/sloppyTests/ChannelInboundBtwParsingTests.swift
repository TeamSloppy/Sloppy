import ChannelPluginSupport
import Foundation
import Protocols
import Testing
@testable import sloppy

@Test
func channelInboundBtwParsing_notCommand() {
    #expect(ChannelInboundBtwParsing.btwModelTailIfCommand("hello") == nil)
    #expect(ChannelInboundBtwParsing.btwModelTailIfCommand("/abort") == nil)
}

@Test
func channelInboundBtwParsing_emptyTail() {
    #expect(ChannelInboundBtwParsing.btwModelTailIfCommand("/btw") == "")
    #expect(ChannelInboundBtwParsing.btwModelTailIfCommand("  /btw  ") == "")
}

@Test
func channelInboundBtwParsing_withTailPreservesCasing() {
    #expect(ChannelInboundBtwParsing.btwModelTailIfCommand("/btw Hello World") == "Hello World")
    #expect(ChannelInboundBtwParsing.btwModelTailIfCommand("/BTW urgent") == "urgent")
}

@Test
func channelCommandHandler_forwardsBtwToSloppy() {
    let handler = ChannelCommandHandler(platformName: "test")
    let context = MessageContext(
        channelId: "c",
        userId: "u",
        platform: "t",
        displayName: "d"
    )
    #expect(handler.handle(text: "/btw hi", context: context) == nil)
    #expect(handler.handle(text: "/btw", context: context) == nil)
}

@Test
func channelRouteDecisionEncodesOptionalQueueFields() throws {
    let withQueue = ChannelRouteDecision(
        action: .respond,
        reason: "queued",
        confidence: 1.0,
        tokenBudget: 0,
        queued: true,
        queueDepth: 2
    )
    let encoder = JSONEncoder()
    let data = try encoder.encode(withQueue)
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(json.contains("queued"))
    #expect(json.contains("queueDepth"))

    let decoded = try JSONDecoder().decode(ChannelRouteDecision.self, from: data)
    #expect(decoded.queued == true)
    #expect(decoded.queueDepth == 2)
}

@Test
func slashBotTargeting_acceptsMatchingOrBare() {
    #expect(ChannelSlashBotTargeting.telegramCommandTargetsThisBot(commandText: "/model", ourBotUsernameLowercased: "mybot"))
    #expect(ChannelSlashBotTargeting.telegramCommandTargetsThisBot(commandText: "/model@mybot", ourBotUsernameLowercased: "mybot"))
    #expect(!ChannelSlashBotTargeting.telegramCommandTargetsThisBot(commandText: "/model@other", ourBotUsernameLowercased: "mybot"))
}

@Test
func slashBotTargeting_stripsSuffix() {
    #expect(
        ChannelSlashBotTargeting.stripTelegramBotUsernameSuffix(commandText: "/model@mybot openai:gpt", ourBotUsernameLowercased: "mybot")
            == "/model openai:gpt"
    )
    #expect(
        ChannelSlashBotTargeting.stripTelegramBotUsernameSuffix(commandText: "/model@MYBOT", ourBotUsernameLowercased: "mybot")
            == "/model"
    )
}
