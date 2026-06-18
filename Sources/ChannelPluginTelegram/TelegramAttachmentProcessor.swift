import Foundation
import Logging
import Protocols
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol TelegramAudioTranscribing: Sendable {
    func transcribeAudio(fileURL: URL, mimeType: String?) async throws -> String?
}

struct TelegramAttachmentProcessor: Sendable {
    private let bot: TelegramBotAPI
    private let logger: Logger
    private let storageDirectory: URL
    private let transcriber: (any TelegramAudioTranscribing)?

    init(
        bot: TelegramBotAPI,
        logger: Logger,
        storageDirectory: URL? = nil,
        transcriber: (any TelegramAudioTranscribing)? = OpenAITelegramAudioTranscriber.fromEnvironment()
    ) {
        self.bot = bot
        self.logger = logger
        self.storageDirectory = storageDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("sloppy-telegram-attachments", isDirectory: true)
        self.transcriber = transcriber
    }

    func process(_ attachments: [ChannelAttachment]) async -> [ChannelAttachment] {
        guard !attachments.isEmpty else { return [] }
        var processed: [ChannelAttachment] = []
        for attachment in attachments {
            processed.append(await processOne(attachment))
        }
        return processed
    }

    private func processOne(_ attachment: ChannelAttachment) async -> ChannelAttachment {
        guard attachment.localPath == nil,
              let fileId = attachment.platformMetadata["file_id"],
              attachment.platformMetadata["platform"] == "telegram"
        else {
            return attachment
        }

        var updated = attachment
        do {
            let file = try await bot.getFile(fileId: fileId)
            guard let filePath = file.filePath, !filePath.isEmpty else {
                logger.warning("Telegram getFile returned no file_path for attachment id=\(attachment.id)")
                return updated
            }
            let data = try await bot.downloadFile(filePath: filePath)
            let localURL = try write(data: data, attachment: attachment, telegramFilePath: filePath)
            updated.localPath = localURL.path
            updated.sizeBytes = updated.sizeBytes ?? data.count
            updated.platformMetadata["file_path"] = filePath
            updated.platformMetadata["downloaded"] = "true"

            if Self.isTranscribableAudio(updated), let transcriber {
                do {
                    let rawTranscript = try await transcriber.transcribeAudio(fileURL: localURL, mimeType: updated.mimeType)
                    if let transcript = rawTranscript?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !transcript.isEmpty {
                        updated.platformMetadata["transcript"] = transcript
                    }
                } catch {
                    logger.warning("Telegram audio transcription failed for attachment id=\(attachment.id): \(error)")
                    updated.platformMetadata["transcription_error"] = String(describing: error)
                }
            }
        } catch {
            logger.warning("Telegram attachment download failed for attachment id=\(attachment.id): \(error)")
            updated.platformMetadata["download_error"] = String(describing: error)
        }
        return updated
    }

    private func write(data: Data, attachment: ChannelAttachment, telegramFilePath: String) throws -> URL {
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        let filename = Self.safeFilename(attachment.filename, fallback: telegramFilePath)
        let prefix = Self.safeFilename(attachment.id, fallback: UUID().uuidString)
        let localURL = storageDirectory.appendingPathComponent("\(prefix)-\(filename)", isDirectory: false)
        try data.write(to: localURL, options: [.atomic])
        return localURL
    }

    static func contentWithTranscripts(content: String, attachments: [ChannelAttachment]) -> String {
        let summaries = attachments.compactMap { attachment -> String? in
            let name = attachment.filename?.trimmingCharacters(in: .whitespacesAndNewlines)
            switch attachment.type {
            case .voice:
                return name?.isEmpty == false ? "Voice message attached: \(name!)" : "Voice message attached."
            case .audio:
                return name?.isEmpty == false ? "Audio attachment: \(name!)" : "Audio attachment."
            case .document:
                return name?.isEmpty == false ? "Document attached: \(name!)" : "Document attached."
            case .image:
                return name?.isEmpty == false ? "Image attached: \(name!)" : "Image attached."
            case .video:
                return name?.isEmpty == false ? "Video attached: \(name!)" : "Video attached."
            case .file, .unknown:
                return name?.isEmpty == false ? "File attached: \(name!)" : "File attached."
            }
        }
        let transcripts = attachments.compactMap { attachment -> String? in
            guard Self.isTranscribableAudio(attachment),
                  let transcript = attachment.platformMetadata["transcript"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !transcript.isEmpty
            else { return nil }
            let label = attachment.type == .voice ? "Voice message" : "Audio attachment"
            return "\(label) transcript:\n\(transcript)"
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "[Attachment]" {
            let parts = summaries + transcripts
            return parts.isEmpty ? content : parts.joined(separator: "\n\n")
        }
        guard !transcripts.isEmpty else {
            return content
        }
        return ([content] + transcripts).joined(separator: "\n\n")
    }

    static func isTranscribableAudio(_ attachment: ChannelAttachment) -> Bool {
        attachment.type == .voice || attachment.type == .audio || (attachment.mimeType?.lowercased().hasPrefix("audio/") == true)
    }

    static func safeFilename(_ candidate: String?, fallback: String) -> String {
        let raw = (candidate?.isEmpty == false ? candidate! : (fallback as NSString).lastPathComponent)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        return sanitized.isEmpty ? UUID().uuidString : String(sanitized.prefix(160))
    }
}

struct OpenAITelegramAudioTranscriber: TelegramAudioTranscribing {
    let apiKey: String
    let model: String
    let endpoint: URL
    let session: URLSession

    static func fromEnvironment() -> OpenAITelegramAudioTranscriber? {
        let env = ProcessInfo.processInfo.environment
        guard let key = env["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return nil
        }
        let model = env["SLOPPY_TELEGRAM_TRANSCRIPTION_MODEL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return OpenAITelegramAudioTranscriber(
            apiKey: key,
            model: (model?.isEmpty == false ? model! : "whisper-1"),
            endpoint: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
            session: URLSession(configuration: .default)
        )
    }

    func transcribeAudio(fileURL: URL, mimeType: String?) async throws -> String? {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try multipartBody(fileURL: fileURL, mimeType: mimeType ?? "application/octet-stream", boundary: boundary)

        let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error { continuation.resume(throwing: error); return }
                guard let data, let response else { continuation.resume(throwing: URLError(.badServerResponse)); return }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TelegramTranscriptionError.http(statusCode: http.statusCode, body: body)
        }
        let decoded = try JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data)
        return decoded.text
    }

    private func multipartBody(fileURL: URL, mimeType: String, boundary: String) throws -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(model)\r\n")
        append("--\(boundary)\r\n")
        let filename = TelegramAttachmentProcessor.safeFilename(fileURL.lastPathComponent, fallback: "audio")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(try Data(contentsOf: fileURL))
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    private struct OpenAITranscriptionResponse: Decodable {
        let text: String
    }
}

enum TelegramTranscriptionError: Error, Equatable {
    case http(statusCode: Int, body: String)
}
