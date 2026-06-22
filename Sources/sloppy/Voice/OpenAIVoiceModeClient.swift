import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

import Protocols

struct OpenAIVoiceModeClient: Sendable {
    private let session: URLSession

    init(session: URLSession = SloppyURLSessionFactory.shared) {
        self.session = session
    }

    func transcribe(
        request: VoiceModeTranscriptionRequest,
        config: CoreConfig,
        apiKey: String
    ) async throws -> VoiceModeTranscriptionResponse {
        let audioData = Data(base64Encoded: request.audioBase64) ?? Data()
        guard !audioData.isEmpty else {
            throw CoreService.VoiceModeError.invalidPayload
        }

        let boundary = "sloppy-voice-\(UUID().uuidString)"
        var urlRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = multipartBody(
            boundary: boundary,
            fields: [
                "model": config.voiceMode.openAI.transcriptionModel,
                "response_format": "json",
            ].merging(optionalFields(request: request)) { current, _ in current },
            fileField: "file",
            filename: filename(for: request.mimeType),
            mimeType: request.mimeType,
            data: audioData
        )

        let (data, response) = try await session.data(for: urlRequest)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data)
        return VoiceModeTranscriptionResponse(
            text: decoded.text.trimmingCharacters(in: .whitespacesAndNewlines),
            provider: "openai",
            model: config.voiceMode.openAI.transcriptionModel
        )
    }

    func speech(
        request: VoiceModeSpeechRequest,
        config: CoreConfig,
        apiKey: String
    ) async throws -> VoiceModeSpeechResponse {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw CoreService.VoiceModeError.invalidPayload
        }
        let voice = request.voice?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? config.voiceMode.openAI.voice
        let instructions = request.instructions?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? config.voiceMode.openAI.instructions
        var payload: [String: String] = [
            "model": config.voiceMode.openAI.ttsModel,
            "voice": voice,
            "input": text,
            "response_format": "mp3",
        ]
        if !instructions.isEmpty {
            payload["instructions"] = instructions
        }

        var urlRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: urlRequest)
        try validate(response: response, data: data)
        return VoiceModeSpeechResponse(
            audioBase64: data.base64EncodedString(),
            mimeType: "audio/mpeg",
            provider: "openai",
            model: config.voiceMode.openAI.ttsModel,
            voice: voice
        )
    }

    private func optionalFields(request: VoiceModeTranscriptionRequest) -> [String: String] {
        var fields: [String: String] = [:]
        if let language = request.language?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty, language != "auto" {
            fields["language"] = language
        }
        if let prompt = request.prompt?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty {
            fields["prompt"] = prompt
        }
        return fields
    }

    private func multipartBody(
        boundary: String,
        fields: [String: String],
        fileField: String,
        filename: String,
        mimeType: String,
        data: Data
    ) -> Data {
        var body = Data()
        for (name, value) in fields {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n")
        return body
    }

    private func filename(for mimeType: String) -> String {
        if mimeType.contains("wav") {
            return "voice.wav"
        }
        if mimeType.contains("mpeg") || mimeType.contains("mp3") {
            return "voice.mp3"
        }
        if mimeType.contains("mp4") {
            return "voice.mp4"
        }
        return "voice.webm"
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CoreService.VoiceModeError.requestFailed("invalid_response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(decoding: data.prefix(240), as: UTF8.self)
            throw CoreService.VoiceModeError.requestFailed("openai_http_\(http.statusCode): \(message)")
        }
    }

    private struct OpenAITranscriptionResponse: Decodable {
        let text: String
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
