import Foundation

/// Explicit, optional gateway capability. Callers must supply trusted channel context, never model-selected chat IDs.
public struct TelegramWidgetRequest: Sendable {
    public let html: String
    public let caption: String
    public let chatData: String?
    public let actions: [String]
    public init(html: String, caption: String, chatData: String? = nil, actions: [String] = []) {
        self.html = html; self.caption = caption; self.chatData = chatData; self.actions = actions
    }
}

public struct TelegramWidgetOwner: Sendable, Equatable {
    public let channelID: String
    public let sessionID: String
    public let userID: Int64
    public init(channelID: String, sessionID: String, userID: Int64) {
        self.channelID = channelID; self.sessionID = sessionID; self.userID = userID
    }
}

public protocol TelegramWidgetGateway: GatewayPlugin {
    func sendWidget(owner: TelegramWidgetOwner, request: TelegramWidgetRequest) async throws -> String
    func updateWidget(owner: TelegramWidgetOwner, handle: String, chatData: String) async throws
}
