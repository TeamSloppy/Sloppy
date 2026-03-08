import Foundation
import Logging
import Protocols
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol DiscordGatewaySession: Sendable {
    func receive() async throws -> DiscordGatewayPayload
    func send(_ payload: DiscordGatewayOutboundPayload) async throws
    func close() async
}

protocol DiscordPlatformClient: Sendable {
    func gatewayURL() async throws -> URL
    func connectGateway(url: URL) async throws -> any DiscordGatewaySession
    func sendMessage(channelId: String, content: String) async throws -> DiscordRESTMessage
    func editMessage(channelId: String, messageId: String, content: String) async throws -> DiscordRESTMessage
    func deleteMessage(channelId: String, messageId: String) async throws
}

struct DiscordGatewayPayload: Codable, Sendable {
    let op: Int
    let d: JSONValue?
    let s: Int?
    let t: String?
}

struct DiscordGatewayOutboundPayload: Codable, Sendable {
    let op: Int
    let d: JSONValue?
}

struct DiscordRESTMessage: Codable, Sendable, Equatable {
    let id: String
    let channelId: String

    enum CodingKeys: String, CodingKey {
        case id
        case channelId = "channel_id"
    }
}

enum DiscordTransportError: Error, Equatable {
    case invalidGatewayURL
    case invalidResponse(method: String)
    case httpError(statusCode: Int, body: String)
    case unsupportedGatewayMessage
}

actor DiscordHTTPClient: DiscordPlatformClient {
    private struct GatewayBotResponse: Decodable {
        let url: String
    }

    private let botToken: String
    private let apiBaseURL: URL
    private let logger: Logger
    private let session: URLSession

    init(
        botToken: String,
        apiBaseURL: URL = URL(string: "https://discord.com/api/v10/")!,
        logger: Logger? = nil,
        session: URLSession? = nil
    ) {
        self.botToken = botToken
        self.apiBaseURL = apiBaseURL
        self.logger = logger ?? Logger(label: "sloppy.discord.api")
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 65
            self.session = URLSession(configuration: configuration)
        }
    }

    func gatewayURL() async throws -> URL {
        let data = try await request(method: "GET", path: "gateway/bot")
        let response = try JSONDecoder().decode(GatewayBotResponse.self, from: data)
        guard var components = URLComponents(string: response.url) else {
            throw DiscordTransportError.invalidGatewayURL
        }
        components.queryItems = [
            URLQueryItem(name: "v", value: "10"),
            URLQueryItem(name: "encoding", value: "json")
        ]
        guard let url = components.url else {
            throw DiscordTransportError.invalidGatewayURL
        }
        return url
    }

    func connectGateway(url: URL) async throws -> any DiscordGatewaySession {
        let task = session.webSocketTask(with: url)
        task.resume()
        return DiscordURLSessionGatewaySession(task: task)
    }

    func sendMessage(channelId: String, content: String) async throws -> DiscordRESTMessage {
        let payload = try await request(
            method: "POST",
            path: "channels/\(channelId)/messages",
            body: ["content": .string(content)]
        )
        let response = try JSONDecoder().decode(DiscordRESTMessage.self, from: payload)
        return response
    }

    func editMessage(channelId: String, messageId: String, content: String) async throws -> DiscordRESTMessage {
        let payload = try await request(
            method: "PATCH",
            path: "channels/\(channelId)/messages/\(messageId)",
            body: ["content": .string(content)]
        )
        let response = try JSONDecoder().decode(DiscordRESTMessage.self, from: payload)
        return response
    }

    func deleteMessage(channelId: String, messageId: String) async throws {
        _ = try await request(
            method: "DELETE",
            path: "channels/\(channelId)/messages/\(messageId)"
        )
    }

    private func request(
        method: String,
        path: String,
        body: [String: JSONValue]? = nil
    ) async throws -> Data {
        let url = apiBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bot \(botToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

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

        if let response = response as? HTTPURLResponse {
            if method == "DELETE" && response.statusCode == 204 {
                return Data()
            }
            if !(200 ..< 300).contains(response.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                logger.warning("Discord API error: method=\(method) path=\(path) status=\(response.statusCode) body=\(body)")
                throw DiscordTransportError.httpError(statusCode: response.statusCode, body: body)
            }
        }

        return data
    }
}

actor DiscordURLSessionGatewaySession: DiscordGatewaySession {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func receive() async throws -> DiscordGatewayPayload {
        let message = try await task.receive()
        let data: Data
        switch message {
        case .data(let payload):
            data = payload
        case .string(let payload):
            data = Data(payload.utf8)
        @unknown default:
            throw DiscordTransportError.unsupportedGatewayMessage
        }
        return try JSONDecoder().decode(DiscordGatewayPayload.self, from: data)
    }

    func send(_ payload: DiscordGatewayOutboundPayload) async throws {
        let data = try JSONEncoder().encode(payload)
        try await task.send(.data(data))
    }

    func close() async {
        task.cancel(with: .normalClosure, reason: nil)
    }
}
