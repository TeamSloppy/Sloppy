import Foundation
import Logging
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal Telegram Bot API client using URLSession.
actor TelegramBotAPI {
    private let botToken: String
    private let baseURL: URL
    private let fileBaseURL: URL
    private let logger: Logger
    private let session: URLSession

    init(
        botToken: String,
        logger: Logger? = nil,
        baseURL: URL? = nil,
        fileBaseURL: URL? = nil,
        session: URLSession? = nil
    ) {
        self.botToken = botToken
        self.baseURL = baseURL ?? URL(string: "https://api.telegram.org/bot\(botToken)/")!
        self.fileBaseURL = fileBaseURL ?? URL(string: "https://api.telegram.org/file/bot\(botToken)/")!
        self.logger = logger ?? Logger(label: "sloppy.telegram.api")
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 65
            self.session = URLSession(configuration: config)
        }
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

    struct MessageEntity: Decodable {
        let type: String
        let offset: Int
        let length: Int
        let user: User?
    }

    struct ReplyToMessage: Decodable {
        let from: User?
        enum CodingKeys: String, CodingKey {
            case from
        }
    }

    struct ForwardOrigin: Decodable {
        let type: String
        let date: Int?
        let senderUser: User?
        let senderUserName: String?
        let chat: Chat?
        let authorSignature: String?

        enum CodingKeys: String, CodingKey {
            case type
            case date
            case senderUser = "sender_user"
            case senderUserName = "sender_user_name"
            case chat
            case authorSignature = "author_signature"
        }

        var attribution: String? {
            switch type {
            case "user":
                return senderUser?.displayName
            case "hidden_user":
                return senderUserName
            case "chat":
                return chat?.displayName ?? authorSignature
            case "channel":
                return chat?.displayName ?? authorSignature
            default:
                return senderUser?.displayName ?? senderUserName ?? chat?.displayName ?? authorSignature
            }
        }
    }


    struct PhotoSize: Decodable {
        let fileId: String
        let fileUniqueId: String?
        let width: Int
        let height: Int
        let fileSize: Int?

        enum CodingKeys: String, CodingKey {
            case fileId = "file_id"
            case fileUniqueId = "file_unique_id"
            case width, height
            case fileSize = "file_size"
        }
    }

    struct MediaFile: Decodable {
        let fileId: String
        let fileUniqueId: String?
        let fileName: String?
        let mimeType: String?
        let fileSize: Int?
        let duration: Int?

        enum CodingKeys: String, CodingKey {
            case fileId = "file_id"
            case fileUniqueId = "file_unique_id"
            case fileName = "file_name"
            case mimeType = "mime_type"
            case fileSize = "file_size"
            case duration
        }
    }

    struct Message: Decodable {
        let messageId: Int64
        let from: User?
        let chat: Chat
        let text: String?
        let caption: String?
        let photo: [PhotoSize]?
        let voice: MediaFile?
        let audio: MediaFile?
        let document: MediaFile?
        let video: MediaFile?
        let animation: MediaFile?
        let date: Int
        /// Present for messages in forum topic threads (supergroups).
        let messageThreadId: Int?
        let replyToMessage: ReplyToMessage?
        let entities: [MessageEntity]?
        let forwardOrigin: ForwardOrigin?
        let forwardFrom: User?
        let forwardFromChat: Chat?
        let forwardSenderName: String?
        let forwardSignature: String?
        let forwardDate: Int?

        enum CodingKeys: String, CodingKey {
            case messageId = "message_id"
            case from, chat, text, caption, photo, voice, audio, document, video, animation, date
            case messageThreadId = "message_thread_id"
            case replyToMessage = "reply_to_message"
            case entities
            case forwardOrigin = "forward_origin"
            case forwardFrom = "forward_from"
            case forwardFromChat = "forward_from_chat"
            case forwardSenderName = "forward_sender_name"
            case forwardSignature = "forward_signature"
            case forwardDate = "forward_date"
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

    struct SendRichMessageResponse: Decodable {
        let ok: Bool
        let result: Message?
    }

    struct SendRichMessageDraftResponse: Decodable {
        let ok: Bool
        let result: Bool?
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

    func sendRichMessage(
        chatId: Int64,
        markdown: String,
        messageThreadId: Int? = nil,
        skipEntityDetection: Bool? = nil,
        replyMarkup: [[[String: String]]]? = nil,
        showTyping: Bool = true
    ) async throws -> Message {
        logger.debug("sendRichMessage: chatId=\(chatId), length=\(markdown.count)")

        if showTyping {
            try? await sendChatAction(chatId: chatId, action: "typing", messageThreadId: messageThreadId)
        }

        var params: [String: Any] = [
            "chat_id": chatId,
            "rich_message": inputRichMessage(markdown: markdown, skipEntityDetection: skipEntityDetection)
        ]
        if let messageThreadId { params["message_thread_id"] = messageThreadId }
        if let replyMarkup {
            params["reply_markup"] = ["inline_keyboard": replyMarkup]
        }
        let data = try await post(method: "sendRichMessage", params: params)
        let response = try JSONDecoder().decode(SendRichMessageResponse.self, from: data)
        guard response.ok, let message = response.result else {
            throw TelegramAPIError.invalidResponse(method: "sendRichMessage")
        }
        return message
    }

    func sendRichMessageDraft(
        chatId: Int64,
        draftId: Int64,
        markdown: String,
        messageThreadId: Int? = nil,
        skipEntityDetection: Bool? = nil
    ) async throws {
        logger.debug("sendRichMessageDraft: chatId=\(chatId), draftId=\(draftId), length=\(markdown.count)")

        var params: [String: Any] = [
            "chat_id": chatId,
            "draft_id": draftId,
            "rich_message": inputRichMessage(markdown: markdown, skipEntityDetection: skipEntityDetection)
        ]
        if let messageThreadId { params["message_thread_id"] = messageThreadId }
        let data = try await post(method: "sendRichMessageDraft", params: params)
        let response = try JSONDecoder().decode(SendRichMessageDraftResponse.self, from: data)
        guard response.ok, response.result == true else {
            throw TelegramAPIError.invalidResponse(method: "sendRichMessageDraft")
        }
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

    private func inputRichMessage(markdown: String, skipEntityDetection: Bool?) -> [String: Any] {
        var richMessage: [String: Any] = ["markdown": markdown]
        if let skipEntityDetection {
            richMessage["skip_entity_detection"] = skipEntityDetection
        }
        return richMessage
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


    // MARK: - getFile / file download

    struct GetFileResponse: Decodable {
        let ok: Bool
        let result: TelegramFile?
    }

    struct TelegramFile: Decodable, Equatable {
        let fileId: String
        let fileUniqueId: String?
        let fileSize: Int?
        let filePath: String?

        enum CodingKeys: String, CodingKey {
            case fileId = "file_id"
            case fileUniqueId = "file_unique_id"
            case fileSize = "file_size"
            case filePath = "file_path"
        }
    }

    func getFile(fileId: String) async throws -> TelegramFile {
        let data = try await post(method: "getFile", params: ["file_id": fileId])
        let decoded = try JSONDecoder().decode(GetFileResponse.self, from: data)
        guard decoded.ok, let file = decoded.result else {
            throw TelegramAPIError.invalidResponse(method: "getFile")
        }
        return file
    }

    func downloadFile(filePath: String) async throws -> Data {
        let url = fileBaseURL.appendingPathComponent(filePath)
        return try await get(url: url, method: "downloadFile")
    }

    // MARK: - setMyCommands

    func setMyCommands(_ commands: [[String: String]]) async throws {
        let params: [String: Any] = ["commands": commands]
        _ = try await post(method: "setMyCommands", params: params)
    }

    // MARK: - getMe

    struct GetMeResponse: Decodable {
        let ok: Bool
        let result: User?
    }

    func getMe() async throws -> User {
        let data = try await post(method: "getMe", params: [:])
        let decoded = try JSONDecoder().decode(GetMeResponse.self, from: data)
        guard decoded.ok, let user = decoded.result else {
            throw TelegramAPIError.invalidResponse(method: "getMe")
        }
        return user
    }

    // MARK: - HTTP transport

    private func post(method: String, params: [String: Any]) async throws -> Data {
        let url = baseURL.appendingPathComponent(method)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: params)
        return try await perform(request: request, method: method)
    }

    private func get(url: URL, method: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await perform(request: request, method: method)
    }

    private func perform(request: URLRequest, method: String) async throws -> Data {
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
