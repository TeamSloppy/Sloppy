import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging

public actor SessionSocketManager {
    private let baseURL: URL
    private let agentId: String
    private let sessionId: String
    private let logger: Logger
    private let decoder: JSONDecoder

    private var task: URLSessionWebSocketTask?
    private var continuation: AsyncStream<ChatStreamUpdate>.Continuation?
    private var disposed = false
    private var reconnectDelay: Double = 1.0

    public init(
        baseURL: URL = URL(string: "http://localhost:25101")!,
        agentId: String,
        sessionId: String,
        logger: Logger = Logger(label: "sloppy.session-socket")
    ) {
        self.baseURL = baseURL
        self.agentId = agentId
        self.sessionId = sessionId
        self.logger = logger

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = ISO8601DateFormatter().date(from: str) { return date }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(str)"
            )
        }
        self.decoder = decoder
    }

    public func connect() -> AsyncStream<ChatStreamUpdate> {
        let stream = AsyncStream<ChatStreamUpdate> { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.disconnect() }
            }
        }
        openSocket()
        return stream
    }

    public func disconnect() {
        disposed = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        continuation?.finish()
        continuation = nil
    }

    private func openSocket() {
        guard !disposed else { return }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components?.percentEncodedPath = [
            "",
            "v1",
            "agents",
            Self.encodePathSegment(agentId),
            "sessions",
            Self.encodePathSegment(sessionId),
            "ws"
        ].joined(separator: "/")
        guard let wsURL = components?.url else { return }

        let wsTask = URLSession.shared.webSocketTask(with: wsURL)
        self.task = wsTask
        wsTask.resume()
        reconnectDelay = 1.0

        Task { await receiveLoop(task: wsTask) }
    }

    private func receiveLoop(task: URLSessionWebSocketTask) async {
        while !disposed {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let update = try? decoder.decode(ChatStreamUpdate.self, from: data) {
                        continuation?.yield(update)
                    } else {
                        logger.warning("Failed to decode session socket text payload.")
                    }
                case .data(let data):
                    if let update = try? decoder.decode(ChatStreamUpdate.self, from: data) {
                        continuation?.yield(update)
                    } else {
                        logger.warning("Failed to decode session socket binary payload.")
                    }
                @unknown default:
                    break
                }
            } catch {
                guard !disposed else { return }
                logger.warning("Session socket disconnected: \(error). Reconnecting in \(reconnectDelay)s")
                self.task = nil
                try? await Task.sleep(nanoseconds: UInt64(reconnectDelay * 1_000_000_000))
                reconnectDelay = min(reconnectDelay * 2, 30)

                // Signal caller to resync via REST
                continuation?.yield(ChatStreamUpdate(kind: .sessionReady, cursor: 0))
                if !disposed {
                    openSocket()
                }
                return
            }
        }
    }

    private static func encodePathSegment(_ segment: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }
}
