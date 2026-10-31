import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging
import SloppyRemoteProtocol

public actor SessionSocketManager {
    private let baseURL: URL
    private let endpoint: SloppyInstanceEndpoint
    private let agentId: String
    private let sessionId: String
    private let logger: Logger
    private let decoder: JSONDecoder
    private let managedStreamProvider: @Sendable (UUID, String) async throws -> AsyncStream<RemoteStreamFrame>
    private let retrySleep: @Sendable (Duration) async throws -> Void

    private var task: URLSessionWebSocketTask?
    private var managedTask: Task<Void, Never>?
    private var continuation: AsyncStream<ChatStreamUpdate>.Continuation?
    private var disposed = false
    private var reconnectDelay: Double = 1.0
    private var socketAttempt = 0

    public init(
        baseURL: URL = URL(string: "http://localhost:25101")!,
        agentId: String,
        sessionId: String,
        logger: Logger = Logger(label: "sloppy.session-socket"),
        managedStreamProvider: (@Sendable (UUID, String) async throws -> AsyncStream<RemoteStreamFrame>)? = nil,
        retrySleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.init(
            endpoint: .direct(baseURL: baseURL),
            agentId: agentId,
            sessionId: sessionId,
            logger: logger,
            managedStreamProvider: managedStreamProvider,
            retrySleep: retrySleep
        )
    }

    public init(
        endpoint: SloppyInstanceEndpoint,
        agentId: String,
        sessionId: String,
        logger: Logger = Logger(label: "sloppy.session-socket"),
        managedStreamProvider: (@Sendable (UUID, String) async throws -> AsyncStream<RemoteStreamFrame>)? = nil,
        retrySleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.endpoint = endpoint
        self.baseURL = endpoint.coordinatorBaseURL
        self.agentId = agentId
        self.sessionId = sessionId
        self.logger = logger
        self.managedStreamProvider = managedStreamProvider ?? { hostID, path in
            let (_, frames) = try await ManagedRemoteConnection.shared.openStream(to: hostID, kind: "session.stream", path: path)
            return frames
        }
        self.retrySleep = retrySleep

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

    public func connect() async -> AsyncStream<ChatStreamUpdate> {
        disposed = false
        reconnectDelay = 1.0
        socketAttempt = 0
        let stream = AsyncStream<ChatStreamUpdate> { continuation in
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
        logger.info("Disconnecting session socket for agent=\(agentId) session=\(sessionId) baseURL=\(baseURL.absoluteString)")
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        managedTask?.cancel()
        managedTask = nil
        continuation?.finish()
        continuation = nil
    }

    private func openSocket() async {
        guard !disposed else { return }

        if case .managed(_, let targetDeviceID) = endpoint {
            let path = "/v1/agents/\(Self.encodePathSegment(agentId))/sessions/\(Self.encodePathSegment(sessionId))/ws"
            // Return the consumer's stream immediately, even while Relay is
            // unavailable. One cancellable task owns all connection attempts.
            managedTask = Task { await runManagedConnection(hostID: targetDeviceID, path: path) }
            return
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        var pathComponents = ["", "v1"]
        if case .relay(_, let targetNodeID) = endpoint {
            pathComponents += ["node", "mesh", "nodes", Self.encodePathSegment(targetNodeID)]
        }
        pathComponents += [
            "agents", Self.encodePathSegment(agentId),
            "sessions", Self.encodePathSegment(sessionId), "ws",
        ]
        components?.percentEncodedPath = pathComponents.joined(separator: "/")
        guard let wsURL = components?.url else {
            logger.error("Could not build session socket URL from \(baseURL.absoluteString) for agent=\(agentId) session=\(sessionId)")
            return
        }

        socketAttempt += 1
        logger.info("Opening session socket attempt \(socketAttempt): \(wsURL.absoluteString)")
        var request = URLRequest(url: wsURL)
        if let token = await AuthSessionStore.shared.session(for: baseURL)?.accessToken,
           !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let wsTask = ClientURLSessionFactory.session(for: baseURL).webSocketTask(with: request)
        self.task = wsTask
        wsTask.resume()

        Task { await receiveLoop(task: wsTask) }
    }

    private func managedReceiveLoop(_ frames: AsyncStream<RemoteStreamFrame>) async {
        for await frame in frames {
            guard !disposed, !Task.isCancelled else { return }
            if frame.action == .data, let data = frame.data {
                if let update = try? decoder.decode(ChatStreamUpdate.self, from: data) {
                    reconnectDelay = 1.0
                    continuation?.yield(update)
                } else {
                    logger.warning("Failed to decode managed session stream payload.")
                }
            }
        }
    }

    private func runManagedConnection(hostID: UUID, path: String) async {
        while !disposed, !Task.isCancelled {
            do {
                let frames = try await managedStreamProvider(hostID, path)
                guard !disposed, !Task.isCancelled else { return }
                await managedReceiveLoop(frames)
            } catch {
                guard !disposed, !Task.isCancelled else { return }
                logger.warning("Managed session stream failed: \(error)")
            }
            guard !disposed, !Task.isCancelled else { return }
            continuation?.yield(ChatStreamUpdate(kind: .sessionReady, cursor: 0))
            let delay = reconnectDelay
            reconnectDelay = min(delay * 2, 30)
            do { try await retrySleep(.seconds(delay)) }
            catch { return }
        }
    }

    private func receiveLoop(task: URLSessionWebSocketTask) async {
        while !disposed {
            do {
                let message = try await task.receive()
                reconnectDelay = 1.0
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
                let delay = reconnectDelay
                logger.warning("Session socket attempt \(socketAttempt) disconnected: \(error). Reconnecting in \(delay)s")
                self.task = nil
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                reconnectDelay = min(delay * 2, 30)

                // Signal caller to resync via REST
                continuation?.yield(ChatStreamUpdate(kind: .sessionReady, cursor: 0))
                if !disposed {
                    await openSocket()
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
