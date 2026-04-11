import Foundation
import Testing
@testable import ChannelPluginTelegram

@Test func telegramModelPicker_parseCallback_roundTrip() {
    let msgId: Int64 = 42
    #expect(TelegramModelPicker.callbackPage(messageId: msgId, page: 3).count <= TelegramModelPicker.maxCallbackBytes)
    #expect(TelegramModelPicker.callbackSelect(messageId: msgId, globalIndex: 15).count <= TelegramModelPicker.maxCallbackBytes)

    switch TelegramModelPicker.parseCallback(TelegramModelPicker.callbackPage(messageId: msgId, page: 2)) {
    case .page(let id, let p):
        #expect(id == msgId)
        #expect(p == 2)
    default:
        Issue.record("expected page")
    }

    switch TelegramModelPicker.parseCallback(TelegramModelPicker.callbackSelect(messageId: msgId, globalIndex: 9)) {
    case .select(let id, let i):
        #expect(id == msgId)
        #expect(i == 9)
    default:
        Issue.record("expected select")
    }

    if case .unknown = TelegramModelPicker.parseCallback("garbage") {
    } else {
        Issue.record("expected unknown")
    }
}
