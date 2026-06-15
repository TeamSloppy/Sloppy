import Foundation
import Testing
@testable import ChannelPluginTelegram
@testable import Protocols
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("Telegram attachment processor", .serialized)
struct TelegramAttachmentProcessorTests {
@Test
func telegramBotAPIGetFileAndDownloadUseTelegramFileEndpoints() async throws {
    TelegramMockURLProtocol.reset()
    TelegramMockURLProtocol.handler = { request in
        let url = request.url!.absoluteString
        if url.hasSuffix("/botTEST/getFile") {
            let body = String(data: requestBodyData(request), encoding: .utf8) ?? ""
            #expect(body.contains("voice-file-id"))
            return (200, #"{"ok":true,"result":{"file_id":"voice-file-id","file_unique_id":"unique-1","file_size":3,"file_path":"voice/file_1.oga"}}"#.data(using: .utf8)!)
        }
        if url.hasSuffix("/file/botTEST/voice/file_1.oga") {
            return (200, Data([0x4f, 0x67, 0x67]))
        }
        return (404, Data("not found".utf8))
    }

    let bot = TelegramBotAPI(
        botToken: "TEST",
        baseURL: URL(string: "https://telegram.test/botTEST/")!,
        fileBaseURL: URL(string: "https://telegram.test/file/botTEST/")!,
        session: TelegramMockURLProtocol.session()
    )

    let file = try await bot.getFile(fileId: "voice-file-id")
    #expect(file.filePath == "voice/file_1.oga")

    let data = try await bot.downloadFile(filePath: "voice/file_1.oga")
    #expect(data == Data([0x4f, 0x67, 0x67]))
}

@Test
func telegramBotAPISendRichMessageUsesRichMessageEndpoint() async throws {
    TelegramMockURLProtocol.reset()
    TelegramMockURLProtocol.handler = { request in
        let url = request.url!.absoluteString
        #expect(url.hasSuffix("/botTEST/sendRichMessage"))
        let params = try #require(JSONSerialization.jsonObject(with: requestBodyData(request)) as? [String: Any])
        #expect(params["chat_id"] as? Int == 42)
        #expect((params["rich_message"] as? [String: Any])?["markdown"] as? String == "# Report\n\n| Status | Value |")
        #expect((params["rich_message"] as? [String: Any])?["skip_entity_detection"] as? Bool == true)
        return (200, #"{"ok":true,"result":{"message_id":7,"chat":{"id":42,"type":"private"},"date":1,"text":"Report"}}"#.data(using: .utf8)!)
    }

    let bot = TelegramBotAPI(
        botToken: "TEST",
        baseURL: URL(string: "https://telegram.test/botTEST/")!,
        fileBaseURL: URL(string: "https://telegram.test/file/botTEST/")!,
        session: TelegramMockURLProtocol.session()
    )

    let message = try await bot.sendRichMessage(
        chatId: 42,
        markdown: "# Report\n\n| Status | Value |",
        skipEntityDetection: true,
        showTyping: false
    )

    #expect(message.messageId == 7)
}

@Test
func telegramBotAPISendRichMessageDraftUsesDraftEndpoint() async throws {
    TelegramMockURLProtocol.reset()
    TelegramMockURLProtocol.handler = { request in
        let url = request.url!.absoluteString
        #expect(url.hasSuffix("/botTEST/sendRichMessageDraft"))
        let params = try #require(JSONSerialization.jsonObject(with: requestBodyData(request)) as? [String: Any])
        #expect(params["chat_id"] as? Int == 42)
        #expect(params["draft_id"] as? Int == 99)
        #expect((params["rich_message"] as? [String: Any])?["markdown"] as? String == "Streaming **partial**")
        return (200, #"{"ok":true,"result":true}"#.data(using: .utf8)!)
    }

    let bot = TelegramBotAPI(
        botToken: "TEST",
        baseURL: URL(string: "https://telegram.test/botTEST/")!,
        fileBaseURL: URL(string: "https://telegram.test/file/botTEST/")!,
        session: TelegramMockURLProtocol.session()
    )

    try await bot.sendRichMessageDraft(
        chatId: 42,
        draftId: 99,
        markdown: "Streaming **partial**"
    )
}

@Test
func telegramBotAPISendRichMessageDraftCanSendThinkingBlockHTML() async throws {
    TelegramMockURLProtocol.reset()
    TelegramMockURLProtocol.handler = { request in
        let url = request.url!.absoluteString
        #expect(url.hasSuffix("/botTEST/sendRichMessageDraft"))
        let params = try #require(JSONSerialization.jsonObject(with: requestBodyData(request)) as? [String: Any])
        #expect(params["chat_id"] as? Int == 42)
        #expect(params["draft_id"] as? Int == 99)
        let richMessage = try #require(params["rich_message"] as? [String: Any])
        #expect(richMessage["html"] as? String == "<tg-thinking>Thinking...</tg-thinking>")
        #expect(richMessage["markdown"] == nil)
        return (200, #"{"ok":true,"result":true}"#.data(using: .utf8)!)
    }

    let bot = TelegramBotAPI(
        botToken: "TEST",
        baseURL: URL(string: "https://telegram.test/botTEST/")!,
        fileBaseURL: URL(string: "https://telegram.test/file/botTEST/")!,
        session: TelegramMockURLProtocol.session()
    )

    try await bot.sendRichMessageDraft(
        chatId: 42,
        draftId: 99,
        html: "<tg-thinking>Thinking...</tg-thinking>"
    )
}

@Test
func telegramAttachmentProcessorDownloadsVoiceAndAddsTranscript() async throws {
    TelegramMockURLProtocol.reset()
    TelegramMockURLProtocol.handler = { request in
        let url = request.url!.absoluteString
        if url.hasSuffix("/botTEST/getFile") {
            return (200, #"{"ok":true,"result":{"file_id":"voice-file-id","file_size":3,"file_path":"voice/file_1.oga"}}"#.data(using: .utf8)!)
        }
        if url.hasSuffix("/file/botTEST/voice/file_1.oga") {
            return (200, Data([0x4f, 0x67, 0x67]))
        }
        return (404, Data("not found".utf8))
    }

    let bot = TelegramBotAPI(
        botToken: "TEST",
        baseURL: URL(string: "https://telegram.test/botTEST/")!,
        fileBaseURL: URL(string: "https://telegram.test/file/botTEST/")!,
        session: TelegramMockURLProtocol.session()
    )
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("telegram-attachment-processor-tests-")
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let processor = TelegramAttachmentProcessor(
        bot: bot,
        logger: .init(label: "test.telegram.attachments"),
        storageDirectory: directory,
        transcriber: StubTelegramAudioTranscriber(transcript: "привет из войса")
    )
    let attachment = ChannelAttachment(
        id: "unique-1",
        type: .voice,
        mimeType: "audio/ogg",
        filename: "voice.oga",
        platformMetadata: ["platform": "telegram", "file_id": "voice-file-id"]
    )

    let processed = await processor.process([attachment])

    #expect(processed.count == 1)
    let voice = try #require(processed.first)
    #expect(voice.localPath != nil)
    #expect(voice.platformMetadata["file_path"] == "voice/file_1.oga")
    #expect(voice.platformMetadata["downloaded"] == "true")
    #expect(voice.platformMetadata["transcript"] == "привет из войса")
    #expect(try Data(contentsOf: URL(fileURLWithPath: #require(voice.localPath))) == Data([0x4f, 0x67, 0x67]))

    let content = TelegramAttachmentProcessor.contentWithTranscripts(content: "[Attachment]", attachments: processed)
    #expect(content == "Voice message transcript:\nпривет из войса")
}
}

private struct StubTelegramAudioTranscriber: TelegramAudioTranscribing {
    let transcript: String?

    func transcribeAudio(fileURL: URL, mimeType: String?) async throws -> String? {
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(mimeType == "audio/ogg")
        return transcript
    }
}

private final class TelegramMockURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)

    private static let lock = NSLock()
    private nonisolated(unsafe) static var _handler: Handler?

    static var handler: Handler? {
        get {
            lock.lock(); defer { lock.unlock() }
            return _handler
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _handler = newValue
        }
    }

    static func reset() {
        handler = nil
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TelegramMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw URLError(.badServerResponse)
            }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func requestBodyData(_ request: URLRequest) -> Data {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return Data()
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: buffer.count)
        if read <= 0 {
            break
        }
        data.append(buffer, count: read)
    }
    return data
}
