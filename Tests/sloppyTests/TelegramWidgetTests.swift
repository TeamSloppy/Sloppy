import Foundation
import Logging
import PluginSDK
import Protocols
import Testing
@testable import ChannelPluginTelegram
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("Telegram widgets", .serialized)
struct TelegramWidgetTests {
    private func query(id: String = "q", user: Int64 = 42, chat: Int64 = 42, message: Int64 = 7,
                       action: String = "refresh", type: [String: Any]? = nil) throws -> TelegramBotAPI.WidgetQuery {
        var value: [String: Any] = ["id": id, "from": ["id": user, "first_name": "Test"],
            "chat": ["id": chat, "type": "private"], "message_id": message, "data": action]
        value["type"] = type
        return try JSONDecoder().decode(TelegramBotAPI.WidgetQuery.self, from: JSONSerialization.data(withJSONObject: value))
    }

    @Test func limitsCountUTF8AndNULAndCompressedBytes() throws {
        try TelegramWidgetValidation.validate(html: "<p>Hello</p>", caption: "Summary", chatData: String(repeating: "я", count: 512))
        #expect(throws: (any Error).self) { try TelegramWidgetValidation.validateData(String(repeating: "я", count: 513)) }
        #expect(throws: (any Error).self) { try TelegramWidgetValidation.validateData("x\0") }
        #expect(throws: (any Error).self) { try TelegramWidgetValidation.validate(html: "x\0", caption: "Summary", chatData: nil) }
        #expect(throws: (any Error).self) { try TelegramWidgetValidation.validate(html: "x", caption: " ", chatData: nil) }
        #expect(throws: (any Error).self) { try TelegramWidgetValidation.validate(html: String(repeating: "x", count: 32769), caption: "Summary", chatData: nil) }
        // Python zlib.compress(b"hello", 9) is 13 bytes (zlib framing, not raw deflate/gzip).
        #expect(try TelegramWidgetValidation.compressedSize("hello") == 13)
        var seed: UInt64 = 1
        let noise = String((0..<12000).map { _ -> Character in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Character(UnicodeScalar(33 + Int((seed >> 32) % 90))!)
        })
        #expect(noise.utf8.count < 32768)
        #expect(try TelegramWidgetValidation.compressedSize(noise) > 4096)
        #expect(throws: (any Error).self) { try TelegramWidgetValidation.validate(html: noise, caption: "Summary", chatData: nil) }
    }

    @Test func ownershipScopesChatMessageSessionAndUser() async throws {
        let store = TelegramWidgetSessionStore()
        let owner = TelegramWidgetOwner(channelID: "private", sessionID: "generation-1", userID: 42)
        let handle = await store.register(owner: owner, chatID: 42, messageID: 7, actions: ["refresh"])
        #expect(await store.entry(handle: handle, owner: owner) != nil)
        #expect(await store.entry(handle: handle, owner: .init(channelID: "private", sessionID: "generation-2", userID: 42)) == nil)
        #expect(await store.entry(handle: handle, owner: .init(channelID: "other", sessionID: "generation-1", userID: 42)) == nil)
        #expect(await store.claim(query: try query(id: "cross-chat", user: 99, chat: 99)) == nil)
        #expect(await store.claim(query: try query(id: "cross-user", user: 99)) == nil)
        #expect(await store.claim(query: try query(id: "cross-message", message: 8)) == nil)
        #expect(await store.claim(query: try query(id: "unregistered", action: "approve")) == nil)
        #expect(await store.claim(query: try query())?.handle == handle)
        #expect(await store.claim(query: try query()) == nil)
        await store.clear()
        #expect(await store.entry(handle: handle, owner: owner) == nil)
        #expect(await store.claim(query: try query(id: "after-restart")) == nil)
    }

    @Test func walletAndUnknownQueriesFailClosed() async throws {
        let store = TelegramWidgetSessionStore()
        _ = await store.register(owner: .init(channelID: "private", sessionID: "s", userID: 42), chatID: 42, messageID: 7, actions: ["refresh"])
        for kind in ["sign_data", "sent_transaction", "future_variant"] {
            #expect(await store.claim(query: try query(id: kind, type: ["type": kind])) == nil)
        }
        #expect(await store.claim(query: try query(id: "wallet", type: ["type": "data", "wallet_card": [:]])) == nil)
        #expect(await store.claim(query: try query(id: "data", type: ["type": "data"])) != nil)
    }

    @Test func transportSerializesSendAcknowledgeAndSameMessageEdit() async throws {
        WidgetURLProtocol.handler = { request in
            let body = try #require(JSONSerialization.jsonObject(with: widgetBody(request)) as? [String: Any])
            switch request.url!.lastPathComponent {
            case "sendWidget":
                #expect(body["chat_id"] as? Int == 42)
                #expect(body["html"] as? String == "<p>Hello</p>")
                #expect(body["caption"] as? String == "Summary")
                #expect(body["allow_queries"] as? Bool == true)
                #expect(body["message_thread_id"] as? Int == 3)
                return (200, Data(#"{"ok":true,"result":{"message_id":7,"chat":{"id":42,"type":"private"},"date":1,"widget":{"html":"<p>Hello</p>","chat_data":"{}"}}}"#.utf8))
            case "answerWidgetQuery":
                #expect(body["widget_query_id"] as? String == "q")
                #expect(body["data"] as? String == "received")
                #expect(request.timeoutInterval <= 5)
            case "editMessageWidgetData":
                #expect(body["chat_id"] as? Int == 42)
                #expect(body["message_id"] as? Int == 7)
                #expect(body["chat_data"] as? String == "{\"done\":true}")
                #expect(body["html"] == nil)
            default: Issue.record("Unexpected endpoint")
            }
            return (200, Data(#"{"ok":true,"result":true}"#.utf8))
        }
        defer { WidgetURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WidgetURLProtocol.self]
        let bot = TelegramBotAPI(botToken: "TEST", baseURL: URL(string: "https://widget.test/botTEST/")!, session: URLSession(configuration: config))
        let sent = try await bot.sendWidget(chatId: 42, html: "<p>Hello</p>", caption: "Summary", chatData: "{}", allowQueries: true, messageThreadId: 3)
        #expect(sent.widget?.html == "<p>Hello</p>")
        try await bot.answerWidgetQuery(id: "q", data: "received")
        try await bot.editMessageWidgetData(chatId: 42, messageId: sent.messageId, chatData: "{\"done\":true}")
    }

    @Test func ordinaryMessageStillDecodesAndUnknownMethodIsNarrow() throws {
        let update = try JSONDecoder().decode(TelegramBotAPI.Update.self, from: Data(#"{"update_id":1,"message":{"message_id":7,"chat":{"id":42,"type":"private"},"date":1,"text":"hello"}}"#.utf8))
        #expect(update.widgetQuery == nil)
        #expect(update.message?.widget == nil)
        #expect(update.message?.text == "hello")
        #expect(TelegramGatewayPlugin.isUnknownWidgetMethod(#"{"ok":false,"error_code":404,"description":"Not Found"}"#))
        #expect(!TelegramGatewayPlugin.isUnknownWidgetMethod(#"{"description":"Unauthorized"}"#))
        #expect(!TelegramGatewayPlugin.isUnknownWidgetMethod("upstream unavailable"))
    }

    @Test func gatewayRoundTripAndIngressAccessChecks() async throws {
        WidgetURLProtocol.handler = { request in
            let body = try #require(JSONSerialization.jsonObject(with: widgetBody(request)) as? [String: Any])
            switch request.url!.lastPathComponent {
            case "sendWidget":
                return (200, Data(#"{"ok":true,"result":{"message_id":7,"chat":{"id":42,"type":"private"},"date":1,"widget":{"html":"<p>Hello</p>"}}}"#.utf8))
            case "answerWidgetQuery":
                #expect(request.timeoutInterval <= 5)
            case "editMessageWidgetData":
                #expect(body["chat_id"] as? Int == 42)
                #expect(body["message_id"] as? Int == 7)
            default: Issue.record("Unexpected endpoint")
            }
            return (200, Data(#"{"ok":true,"result":true}"#.utf8))
        }
        defer { WidgetURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WidgetURLProtocol.self]
        let bot = TelegramBotAPI(botToken: "TEST", baseURL: URL(string: "https://widget.test/")!, session: URLSession(configuration: config))
        let owner = TelegramWidgetOwner(channelID: "private", sessionID: "generation", userID: 42)
        let gateway = TelegramGatewayPlugin(config: .init(botToken: "TEST", channelChatMap: ["private": 42]), bot: bot)
        let handle = try await gateway.sendWidget(owner: owner, request: .init(html: "<p>Hello</p>", caption: "Summary", actions: ["refresh"]))
        try await gateway.updateWidget(owner: owner, handle: handle, chatData: "done")
        let receiver = WidgetReceiver()
        let sessions = TelegramWidgetSessionStore()
        _ = await sessions.register(owner: owner, chatID: 42, messageID: 7, actions: ["refresh"])
        let poller = TelegramPoller(bot: bot, receiver: receiver,
            config: .init(botToken: "TEST", channelChatMap: ["private": 42]),
            logger: Logger(label: "test.widget"), widgetSessions: sessions)
        await poller.handleWidgetQuery(try query(id: "accepted"))
        #expect(await receiver.actions == 1)
        #expect(await receiver.owner == owner)
        await receiver.block()
        await poller.handleWidgetQuery(try query(id: "blocked"))
        #expect(await receiver.actions == 1)
        await poller.handleWidgetQuery(try query(id: "foreign", user: 99, chat: 99))
        #expect(await receiver.actions == 1)
    }

    @Test func groupAndUnsupportedMethodUseOnlyCaptionFallback() async throws {
        WidgetURLProtocol.handler = { request in
            switch request.url!.lastPathComponent {
            case "sendWidget": return (404, Data(#"{"ok":false,"error_code":404,"description":"Not Found"}"#.utf8))
            case "sendChatAction": return (200, Data(#"{"ok":true,"result":true}"#.utf8))
            case "sendMessage":
                let body = try #require(JSONSerialization.jsonObject(with: widgetBody(request)) as? [String: Any])
                #expect(body["text"] as? String == "Summary")
                #expect(body["html"] == nil)
                return (200, Data(#"{"ok":true,"result":{"message_id":7,"chat":{"id":42,"type":"private"},"date":1}}"#.utf8))
            default: Issue.record("Unexpected endpoint")
            }
            return (200, Data(#"{"ok":true,"result":true}"#.utf8))
        }
        defer { WidgetURLProtocol.handler = nil }
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [WidgetURLProtocol.self]
        let bot = TelegramBotAPI(botToken: "TEST", baseURL: URL(string: "https://widget.test/")!, session: URLSession(configuration: c))
        for target: Int64 in [-100, 42] {
            let gateway = TelegramGatewayPlugin(config: .init(botToken: "TEST", channelChatMap: ["private": target]), bot: bot)
            let result = try await gateway.sendWidget(owner: .init(channelID: "private", sessionID: "s", userID: 42),
                request: .init(html: "<p>Hello</p>", caption: "Summary"))
            #expect(result == "text_fallback")
        }
    }

    @Test func catchAllAndForeignPrivateRecipientAreRejectedWithoutNetwork() async {
        let owner = TelegramWidgetOwner(channelID: "private", sessionID: "s", userID: 42)
        for target: Int64 in [0, 99] {
            let gateway = TelegramGatewayPlugin(botToken: "TEST", channelChatMap: ["private": target])
            do {
                _ = try await gateway.sendWidget(owner: owner, request: .init(html: "<p>Hello</p>", caption: "Summary"))
                Issue.record("Unsafe recipient accepted")
            } catch { #expect(error is TelegramWidgetError) }
        }
    }
}

private final class WidgetURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)
    private static let lock = NSLock()
    private nonisolated(unsafe) static var stored: Handler?
    static var handler: Handler? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let handler = try #require(Self.handler)
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private func widgetBody(_ request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open(); defer { stream.close() }
    var result = Data(), buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        result.append(buffer, count: count)
    }
    return result
}

private actor WidgetReceiver: InboundMessageReceiver {
    var actions = 0
    var denied = false
    var owner: TelegramWidgetOwner?
    func block() { denied = true }
    func checkAccess(platform: String, platformUserId: String, displayName: String, chatId: String) async -> ChannelAccessResult {
        denied ? .blocked : .allowed
    }
    func receiveTelegramWidgetAction(owner: TelegramWidgetOwner, handle: String, action: String) async -> Bool {
        actions += 1
        self.owner = owner
        return true
    }
    func postMessage(channelId: String, userId: String, content: String, topicId: String?, inboundContext: ChannelInboundContext?, attachments: [ChannelAttachment]) async -> Bool { true }
}
