import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

import Protocols

struct ElevenLabsSpeechProvider: VoiceSpeechProvider {
    let apiKey: String
    let model: String
    let defaultVoiceId: String
    var session: URLSession = SloppyURLSessionFactory.shared

    func speech(request: VoiceModeSpeechRequest) async throws -> VoiceModeSpeechResponse {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw CoreService.VoiceModeError.invalidPayload
        }
        let requested = request.voice?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let voiceId = requested.isEmpty ? defaultVoiceId : requested
        guard let encodedVoice = voiceId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(encodedVoice)?output_format=mp3_44100_128")
        else {
            throw CoreService.VoiceModeError.invalidPayload
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(["text": text, "model_id": model])

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw CoreService.VoiceModeError.requestFailed("invalid_response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(decoding: data.prefix(240), as: UTF8.self)
            throw CoreService.VoiceModeError.requestFailed("elevenlabs_http_\(http.statusCode): \(message)")
        }
        return VoiceModeSpeechResponse(
            audioBase64: data.base64EncodedString(),
            mimeType: "audio/mpeg",
            provider: "elevenlabs",
            model: model,
            voice: voiceId
        )
    }
}
