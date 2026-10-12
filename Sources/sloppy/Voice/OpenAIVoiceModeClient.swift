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
        try await OpenAICompatibleTranscriber(
            endpoint: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
            apiKey: apiKey,
            model: config.voiceMode.openAI.transcriptionModel,
            providerName: "openai",
            session: session
        ).transcribe(request: request)
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

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CoreService.VoiceModeError.requestFailed("invalid_response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(decoding: data.prefix(240), as: UTF8.self)
            throw CoreService.VoiceModeError.requestFailed("openai_http_\(http.statusCode): \(message)")
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
