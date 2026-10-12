import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

import Protocols

/// Mints single-use Gemini Live ephemeral tokens so the browser never sees the API key (ADR 0007).
struct GeminiLiveSessionProvider: Sendable {
    static let tokenEndpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/auth_tokens")!
    static let websocketURL =
        "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained"
    /// A new session must start within this window after the token is minted.
    static let newSessionWindowSeconds: TimeInterval = 60

    let apiKey: String
    let realtime: CoreConfig.VoiceMode.Realtime
    var session: URLSession = SloppyURLSessionFactory.shared
    var now: @Sendable () -> Date = { Date() }

    func createSession() async throws -> VoiceModeRealtimeSessionResponse {
        let request = try makeTokenRequest()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CoreService.VoiceModeError.requestFailed("invalid_response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(decoding: data.prefix(240), as: UTF8.self)
            throw CoreService.VoiceModeError.requestFailed("gemini_http_\(http.statusCode): \(message)")
        }
        return try makeResponse(tokenResponse: data)
    }

    func makeTokenRequest() throws -> URLRequest {
        let issued = now()
        let expires = issued.addingTimeInterval(TimeInterval(realtime.maxSessionSeconds))
        let newSessionDeadline = issued.addingTimeInterval(Self.newSessionWindowSeconds)
        let body: [String: JSONValueLike] = [
            "uses": .int(1),
            "expireTime": .string(Self.iso8601(expires)),
            "newSessionExpireTime": .string(Self.iso8601(newSessionDeadline)),
        ]

        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    func makeResponse(tokenResponse: Data) throws -> VoiceModeRealtimeSessionResponse {
        struct TokenResponse: Decodable {
            let name: String
        }
        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: tokenResponse),
              !decoded.name.isEmpty
        else {
            throw CoreService.VoiceModeError.requestFailed("gemini_invalid_token_response")
        }
        let expires = now().addingTimeInterval(TimeInterval(realtime.maxSessionSeconds))
        return VoiceModeRealtimeSessionResponse(
            provider: "gemini",
            model: realtime.model,
            token: decoded.name,
            websocketUrl: Self.websocketURL,
            expiresAt: Self.iso8601(expires),
            voice: realtime.voice,
            systemInstruction: realtime.systemInstruction
        )
    }

    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    enum JSONValueLike: Encodable {
        case int(Int)
        case string(String)

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .int(let value): try container.encode(value)
            case .string(let value): try container.encode(value)
            }
        }
    }
}
