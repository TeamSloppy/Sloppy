import Foundation
import Testing
import PluginSDK

@Test func channelGatewayScope_roundTrip() {
    let base = "telegram-main"
    let scoped = ChannelGatewayScope.scopedChannelId(baseChannelId: base, topicKey: "551")
    #expect(scoped != base)
    let parsed = ChannelGatewayScope.parse(scoped)
    #expect(parsed.baseChannelId == base)
    #expect(parsed.topicKey == "551")
    #expect(ChannelGatewayScope.scopedChannelId(baseChannelId: base, topicKey: nil) == base)
}

@Test func channelGatewayScope_sessionMatchesBinding() {
    let binding = "support"
    let scoped = ChannelGatewayScope.scopedChannelId(baseChannelId: binding, topicKey: "42")
    #expect(ChannelGatewayScope.sessionMatchesBinding(sessionChannelId: binding, bindingChannelId: binding))
    #expect(ChannelGatewayScope.sessionMatchesBinding(sessionChannelId: scoped, bindingChannelId: binding))
    #expect(!ChannelGatewayScope.sessionMatchesBinding(sessionChannelId: "other", bindingChannelId: binding))
}
