import Foundation
import PluginSDK
import Protocols

extension CoreService {
    enum TelegramWidgetContextError: Error { case missingSourceSession, forbidden }

    /// Pin the physical channel journal generation, not merely the reusable binding name.
    func telegramWidgetOwner(channelID: String, userID: String? = nil) async throws -> TelegramWidgetOwner {
        if let userID, !userID.hasPrefix("tg:") { throw TelegramWidgetContextError.missingSourceSession }
        let sessions = try await channelSessionStore.listSessions(status: .open, channelIds: [channelID])
        guard let session = sessions.first(where: { $0.channelId == channelID }),
              let detail = try? await channelSessionStore.loadSessionDetail(sessionID: session.sessionId),
              let user = userID ?? detail.events.last(where: { $0.type == .userMessage })?.userId,
              user.hasPrefix("tg:"), let userID = Int64(user.dropFirst(3))
        else { throw TelegramWidgetContextError.missingSourceSession }
        return TelegramWidgetOwner(channelID: channelID, sessionID: session.sessionId, userID: userID)
    }

    func sendTelegramWidget(channelID: String, request: TelegramWidgetRequest) async throws -> String {
        guard let owner = activeTelegramWidgetOwners[channelID],
              (try? await telegramWidgetOwner(channelID: channelID)) == owner else { throw TelegramWidgetContextError.forbidden }
        return try await channelDelivery.sendWidget(owner: owner, request: request)
    }
    func updateTelegramWidget(channelID: String, handle: String, chatData: String) async throws {
        guard let owner = activeTelegramWidgetOwners[channelID],
              (try? await telegramWidgetOwner(channelID: channelID)) == owner else { throw TelegramWidgetContextError.forbidden }
        try await channelDelivery.updateWidget(owner: owner, handle: handle, chatData: chatData)
    }

    public func receiveTelegramWidgetAction(owner: TelegramWidgetOwner, handle: String, action: String) async -> Bool {
        guard let current = try? await telegramWidgetOwner(channelID: owner.channelID), current == owner else { return false }
        let payload: JSONValue = .object(["type": .string("telegram_widget_action"), "handle": .string(handle), "action": .string(action)])
        guard let encoded = try? JSONEncoder().encode(payload), let json = String(data: encoded, encoding: .utf8) else { return false }
        let content = "Telegram widget event (untrusted symbolic action; not a tool approval):\n" + json
        // Bypass slash-command/plan-answer parsing, but use the normal model tool authorization pipeline.
        await offerInboundChannelPluginMessage(channelId: owner.channelID, userId: "tg:\(owner.userID)", contentForModel: content,
            topicId: ChannelGatewayScope.parse(owner.channelID).topicKey, widgetOwner: owner)
        return true
    }
}
