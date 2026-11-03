import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging

public actor NotificationSocketManager {
    private let baseURL: URL
    private let logger: Logger
    private let decoder: JSONDecoder
    private let onConnect: (@Sendable () async -> Void)?
    private let authSessionStore: AuthSessionStore

    private var task: URLSessionWebSocketTask?
    private var continuation: AsyncStream<AppNotification>.Continuation?
    private var disposed = false
    private var reconnectDelay: Double = 1.0
    private var socketAttempt = 0

    public init(
        baseURL: URL = URL(string: "http://localhost:25101")!,
        logger: Logger = Logger(label: "sloppy.notification-socket"),
        onConnect: (@Sendable () async -> Void)? = nil,
        authSessionStore: AuthSessionStore = .shared
    ) {
        self.baseURL = baseURL
        self.logger = logger
        self.onConnect = onConnect
        self.authSessionStore = authSessionStore

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

    public func connect() async -> AsyncStream<AppNotification> {
        disposed = false
        reconnectDelay = 1.0
        socketAttempt = 0
        let stream = AsyncStream<AppNotification> { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.disconnect() }
            }
        }
        await openSocket()
        return stream
    }

    public func disconnect() {
        disposed = true
        logger.info("Disconnecting notification socket for \(baseURL.absoluteString)")
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        continuation?.finish()
        continuation = nil
    }

    func connectionRequest() async -> URLRequest? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components?.path = "/v1/notifications/ws"
        components?.query = nil
        components?.fragment = nil
        guard let wsURL = components?.url else { return nil }
        var request = URLRequest(url: wsURL)
        if let token = await authSessionStore.session(for: baseURL)?.accessToken
            .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func openSocket() async {
        guard !disposed else { return }
        guard let request = await connectionRequest() else {
            logger.error("Could not build notification socket URL from \(baseURL.absoluteString)")
            return
        }
        guard !disposed else { return }

        socketAttempt += 1
        logger.info("Opening notification socket attempt \(socketAttempt)")
        let wsTask = ClientURLSessionFactory.session(for: baseURL).webSocketTask(with: request)
        self.task = wsTask
        wsTask.resume()

        if let onConnect {
            Task {
                do {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                        wsTask.sendPing { error in
                            if let error { continuation.resume(throwing: error) }
                            else { continuation.resume() }
                        }
                    }
                    guard !disposed, task === wsTask else { return }
                    await onConnect()
                } catch { /* The receive loop owns reconnection. */ }
            }
        }

        Task { await receiveLoop(task: wsTask) }
    }

    private func receiveLoop(task: URLSessionWebSocketTask) async {
        while !disposed, self.task === task {
            do {
                let message = try await task.receive()
                reconnectDelay = 1.0
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
                guard !disposed, self.task === task else { return }
                let delay = reconnectDelay
                logger.warning("Notification socket attempt \(socketAttempt) disconnected: \(error). Reconnecting in \(delay)s")
                self.task = nil
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                reconnectDelay = min(delay * 2, 30)
                if !disposed {
                    await openSocket()
                }
                return
            }
        }
    }
}
