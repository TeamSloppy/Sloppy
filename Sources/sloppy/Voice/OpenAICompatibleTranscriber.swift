import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

import Protocols

/// Multipart `/audio/transcriptions` client shared by OpenAI-compatible vendors (OpenAI, Groq).
struct OpenAICompatibleTranscriber: VoiceTranscriptionProvider {
    let endpoint: URL
    let apiKey: String
    let model: String
    let providerName: String
    var session: URLSession = SloppyURLSessionFactory.shared

    func transcribe(request: VoiceModeTranscriptionRequest) async throws -> VoiceModeTranscriptionResponse {
        let audioData = Data(base64Encoded: request.audioBase64) ?? Data()
        guard !audioData.isEmpty else {
            throw CoreService.VoiceModeError.invalidPayload
        }

        let boundary = "sloppy-voice-\(UUID().uuidString)"
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = Self.multipartBody(
            boundary: boundary,
            fields: [
                "model": model,
                "response_format": "json",
            ].merging(Self.optionalFields(request: request)) { current, _ in current },
            fileField: "file",
            filename: Self.filename(for: request.mimeType),
            mimeType: request.mimeType,
            data: audioData
        )

        let (data, response) = try await session.data(for: urlRequest)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return VoiceModeTranscriptionResponse(
            text: decoded.text.trimmingCharacters(in: .whitespacesAndNewlines),
            provider: providerName,
            model: model
        )
    }

    static func optionalFields(request: VoiceModeTranscriptionRequest) -> [String: String] {
        var fields: [String: String] = [:]
        if let language = request.language?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty, language != "auto" {
            fields["language"] = language
        }
        if let prompt = request.prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
            fields["prompt"] = prompt
        }
        return fields
    }

    static func multipartBody(
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

    static func filename(for mimeType: String) -> String {
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
            throw CoreService.VoiceModeError.requestFailed("\(providerName)_http_\(http.statusCode): \(message)")
        }
    }

    private struct TranscriptionResponse: Decodable {
        let text: String
    }
}

extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
