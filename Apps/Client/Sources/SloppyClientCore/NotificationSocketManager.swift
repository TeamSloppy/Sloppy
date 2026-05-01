import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging

public actor NotificationSocketManager {
    private let baseURL: URL
    private let logger: Logger
    private let decoder: JSONDecoder

    private var task: URLSessionWebSocketTask?
    private var continuation: AsyncStream<AppNotification>.Continuation?
    private var disposed = false
    private var reconnectDelay: Double = 1.0

    public init(
        baseURL: URL = URL(string: "http://localhost:25101")!,
        logger: Logger = Logger(label: "sloppy.notification-socket")
    ) {
        self.baseURL = baseURL
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

    public func connect() -> AsyncStream<AppNotification> {
        let stream = AsyncStream<AppNotification> { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.disconnect() }
            }
        }
        Task { await openSocket() }
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
        components?.path = "/v1/notifications/ws"
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
                       let notification = try? decoder.decode(AppNotification.self, from: data) {
                        continuation?.yield(notification)
                    }
                case .data(let data):
                    if let notification = try? decoder.decode(AppNotification.self, from: data) {
                        continuation?.yield(notification)
                    }
                @unknown default:
                    break
                }
            } catch {
                guard !disposed else { return }
                logger.warning("Notification socket disconnected: \(error). Reconnecting in \(reconnectDelay)s")
                self.task = nil
                try? await Task.sleep(nanoseconds: UInt64(reconnectDelay * 1_000_000_000))
                reconnectDelay = min(reconnectDelay * 2, 30)
                if !disposed {
                    openSocket()
                }
                return
            }
        }
    }
}
