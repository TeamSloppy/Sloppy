import Foundation
import Logging
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal Telegram Bot API client using URLSession.
actor TelegramBotAPI {
    private let botToken: String
    private let baseURL: URL
    private let logger: Logger
    private let session: URLSession

    init(botToken: String, logger: Logger? = nil) {
        self.botToken = botToken
        self.baseURL = URL(string: "https://api.telegram.org/bot\(botToken)/")!
        self.logger = logger ?? Logger(label: "sloppy.telegram.api")
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 65
        self.session = URLSession(configuration: config)
    }

    // MARK: - getUpdates (long-polling)

    struct GetUpdatesResponse: Decodable {
        let ok: Bool
        let result: [Update]?
    }

    struct Update: Decodable {
        let updateId: Int64
        let message: Message?
        let callbackQuery: CallbackQuery?

        enum CodingKeys: String, CodingKey {
            case updateId = "update_id"
            case message
            case callbackQuery = "callback_query"
        }
    }

    struct CallbackQuery: Decodable {
        let id: String
        let from: User
        let message: Message?
        let data: String?

        enum CodingKeys: String, CodingKey {
            case id
            case from
            case message
            case data
        }
    }

    struct Message: Decodable {
        let messageId: Int64
        let from: User?
        let chat: Chat
        let text: String?
        let date: Int
        /// Present for messages in forum topic threads (supergroups).
        let messageThreadId: Int?

        enum CodingKeys: String, CodingKey {
            case messageId = "message_id"
            case from, chat, text, date
            case messageThreadId = "message_thread_id"
        }
    }

    struct User: Decodable {
        let id: Int64
        let firstName: String
        let lastName: String?
        let username: String?

        enum CodingKeys: String, CodingKey {
            case id
            case firstName = "first_name"
            case lastName = "last_name"
            case username
        }

        var displayName: String {
            if let username { return "@\(username)" }
            if let lastName { return "\(firstName) \(lastName)" }
            return firstName
        }
    }

    struct Chat: Decodable {
        let id: Int64
        let type: String
        let title: String?
    }

    func getUpdates(offset: Int64?, timeout: Int = 60) async throws -> [Update] {
        var params: [String: Any] = ["timeout": timeout]
        if let offset { params["offset"] = offset }
        let data = try await post(method: "getUpdates", params: params)
        let decoded = try JSONDecoder().decode(GetUpdatesResponse.self, from: data)
        let updates = decoded.result ?? []
        if !updates.isEmpty {
            logger.debug("getUpdates: received \(updates.count) update(s), offset=\(offset.map(String.init) ?? "nil")")
        }
        return updates
    }

    // MARK: - sendChatAction

    func sendChatAction(chatId: Int64, action: String, messageThreadId: Int? = nil) async throws {
        var params: [String: Any] = [
            "chat_id": chatId,
            "action": action
        ]
        if let messageThreadId { params["message_thread_id"] = messageThreadId }
        _ = try await post(method: "sendChatAction", params: params)
    }

    // MARK: - sendMessage

    struct SendMessageResponse: Decodable {
        let ok: Bool
        let result: Message?
    }

    struct EditMessageTextResponse: Decodable {
        let ok: Bool
        let result: Message?
    }

    struct DeleteMessageResponse: Decodable {
        let ok: Bool
        let result: Bool?
    }

    /// - Parameters:
    ///   - showTyping: When false, skips `sendChatAction` (e.g. inline keyboard refreshes).
    ///   - replyMarkup: Optional inline keyboard (`inline_keyboard` rows).
    func sendMessage(
        chatId: Int64,
        text: String,
        messageThreadId: Int? = nil,
        parseMode: String? = nil,
        replyMarkup: [[[String: String]]]? = nil,
        showTyping: Bool = true
    ) async throws -> Message {
        logger.debug("sendMessage: chatId=\(chatId), length=\(text.count)")

        if showTyping {
            try? await sendChatAction(chatId: chatId, action: "typing", messageThreadId: messageThreadId)
        }

        var params: [String: Any] = [
            "chat_id": chatId,
            "text": text
        ]
        if let messageThreadId { params["message_thread_id"] = messageThreadId }
        if let parseMode { params["parse_mode"] = parseMode }
        if let replyMarkup {
            params["reply_markup"] = ["inline_keyboard": replyMarkup]
        }
        let data = try await post(method: "sendMessage", params: params)
        let response = try JSONDecoder().decode(SendMessageResponse.self, from: data)
        guard response.ok, let message = response.result else {
            throw TelegramAPIError.invalidResponse(method: "sendMessage")
        }
        return message
    }

    func editMessageText(
        chatId: Int64,
        messageId: Int64,
        text: String,
        messageThreadId: Int? = nil,
        parseMode: String? = nil,
        replyMarkup: [[[String: String]]]? = nil
    ) async throws -> Message {
        logger.debug("editMessageText: chatId=\(chatId), messageId=\(messageId), length=\(text.count)")

        var params: [String: Any] = [
            "chat_id": chatId,
            "message_id": messageId,
            "text": text
        ]
        if let messageThreadId { params["message_thread_id"] = messageThreadId }
        if let parseMode { params["parse_mode"] = parseMode }
        if let replyMarkup {
            params["reply_markup"] = ["inline_keyboard": replyMarkup]
        }
        let data = try await post(method: "editMessageText", params: params)
        let response = try JSONDecoder().decode(EditMessageTextResponse.self, from: data)
        guard response.ok, let message = response.result else {
            throw TelegramAPIError.invalidResponse(method: "editMessageText")
        }
        return message
    }

    func deleteMessage(chatId: Int64, messageId: Int64, messageThreadId: Int? = nil) async throws {
        logger.debug("deleteMessage: chatId=\(chatId), messageId=\(messageId)")

        var params: [String: Any] = [
            "chat_id": chatId,
            "message_id": messageId
        ]
        if let messageThreadId { params["message_thread_id"] = messageThreadId }
        let data = try await post(method: "deleteMessage", params: params)
        let response = try JSONDecoder().decode(DeleteMessageResponse.self, from: data)
        guard response.ok else {
            throw TelegramAPIError.invalidResponse(method: "deleteMessage")
        }
    }

    // MARK: - answerCallbackQuery

    func answerCallbackQuery(
        callbackQueryId: String,
        text: String? = nil,
        showAlert: Bool = false
    ) async throws {
        var params: [String: Any] = [
            "callback_query_id": callbackQueryId
        ]
        if let text { params["text"] = text }
        if showAlert { params["show_alert"] = true }
        _ = try await post(method: "answerCallbackQuery", params: params)
    }

    // MARK: - setMyCommands

    func setMyCommands(_ commands: [[String: String]]) async throws {
        let params: [String: Any] = ["commands": commands]
        _ = try await post(method: "setMyCommands", params: params)
    }

    // MARK: - HTTP transport

    private func post(method: String, params: [String: Any]) async throws -> Data {
        let url = baseURL.appendingPathComponent(method)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: params)

        // Use callback-based dataTask to avoid URLSession async cancellation issues
        // with FoundationNetworking on Linux (NSURLErrorDomain -999).
        let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            logger.warning("Telegram API error: method=\(method) status=\(http.statusCode) body=\(body)")
            throw TelegramAPIError.httpError(statusCode: http.statusCode, body: body)
        }
        return data
    }
}

enum TelegramAPIError: Error {
    case httpError(statusCode: Int, body: String)
    case invalidResponse(method: String)
}
