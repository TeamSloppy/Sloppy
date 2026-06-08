import Foundation
import Protocols

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum NodeMeshClientError: LocalizedError, Equatable {
    case invalidRelayURL(String)
    case unsupportedRelayScheme(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRelayURL(let value):
            "Invalid relay URL: \(value)"
        case .unsupportedRelayScheme(let scheme):
            "Unsupported relay URL scheme: \(scheme)"
        }
    }
}

public actor NodeMeshClient {
    public typealias EnvelopeObserver = @Sendable (MeshEnvelope) async -> Void

    private let config: NodeConfig
    private let daemon: NodeDaemon
    private let heartbeatInterval: TimeInterval
    private let reconnectDelay: TimeInterval
    private let onEnvelope: EnvelopeObserver?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        config: NodeConfig,
        daemon: NodeDaemon? = nil,
        heartbeatInterval: TimeInterval = 15,
        reconnectDelay: TimeInterval = 2,
        onEnvelope: EnvelopeObserver? = nil
    ) {
        self.config = config
        self.daemon = daemon ?? NodeDaemon(config: config)
        self.heartbeatInterval = max(1, heartbeatInterval)
        self.reconnectDelay = max(0.25, reconnectDelay)
        self.onEnvelope = onEnvelope
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public static func resolveRelayWebSocketURL(_ relayURL: String) throws -> URL {
        guard var components = URLComponents(string: relayURL), let scheme = components.scheme?.lowercased() else {
            throw NodeMeshClientError.invalidRelayURL(relayURL)
        }

        switch scheme {
        case "http":
            components.scheme = "ws"
            components.path = "/v1/node/mesh/ws"
        case "https":
            components.scheme = "wss"
            components.path = "/v1/node/mesh/ws"
        case "ws", "wss":
            break
        default:
            throw NodeMeshClientError.unsupportedRelayScheme(scheme)
        }

        guard let url = components.url else {
            throw NodeMeshClientError.invalidRelayURL(relayURL)
        }
        return url
    }

    public static func makeHelloEnvelope(identity: NodeIdentity) -> MeshEnvelope {
        MeshEnvelope(
            type: .nodeHello,
            from: identity.nodeId,
            payload: .object([
                "name": .string(identity.name),
                "publicKey": .string(identity.publicKey),
                "roles": .array(identity.roles.map(JSONValue.string)),
                "capabilities": .array(identity.capabilities.map(JSONValue.string)),
            ])
        )
    }

    public static func makeHeartbeatEnvelope(identity: NodeIdentity) -> MeshEnvelope {
        MeshEnvelope(type: .nodeHeartbeat, from: identity.nodeId)
    }

    public func response(to envelope: MeshEnvelope) async -> MeshEnvelope? {
        guard envelope.type == .rpcRequest else {
            if let onEnvelope {
                await onEnvelope(envelope)
            }
            return nil
        }

        let payload = envelope.payload.asObject ?? [:]
        let method = payload["method"]?.asString ?? ""
        let responsePayload: JSONValue
        switch method {
        case "node.ping":
            responsePayload = .object([
                "requestId": .string(envelope.id),
                "method": .string(method),
                "ok": .bool(true),
                "time": .string(ISO8601DateFormatter().string(from: Date())),
            ])
        case "node.status":
            let status = await daemon.invoke(NodeActionRequest(action: .status))
            responsePayload = .object([
                "requestId": .string(envelope.id),
                "method": .string(method),
                "ok": .bool(status.ok),
                "result": status.data ?? .object([:]),
            ])
        case "node.capabilities":
            responsePayload = .object([
                "requestId": .string(envelope.id),
                "method": .string(method),
                "ok": .bool(true),
                "result": .object([
                    "roles": .array(config.identity.roles.map(JSONValue.string)),
                    "capabilities": .array(config.identity.capabilities.map(JSONValue.string)),
                ]),
            ])
        case "project.status":
            responsePayload = .object([
                "requestId": .string(envelope.id),
                "method": .string(method),
                "ok": .bool(true),
                "result": .object([
                    "projects": .array([]),
                ]),
            ])
        default:
            responsePayload = .object([
                "requestId": .string(envelope.id),
                "method": .string(method),
                "ok": .bool(false),
                "error": .object([
                    "code": .string("unknown_method"),
                    "message": .string("Unknown mesh RPC method."),
                ]),
            ])
        }

        return MeshEnvelope(
            type: .rpcResponse,
            from: config.identity.nodeId,
            to: envelope.from,
            scope: envelope.scope,
            payload: responsePayload
        )
    }

    public func run(relayURL: String? = nil) async throws {
        let configuredRelayURL = relayURL ?? config.relayURL
        guard let configuredRelayURL, !configuredRelayURL.isEmpty else {
            return
        }
        let url = try Self.resolveRelayWebSocketURL(configuredRelayURL)

        while !Task.isCancelled {
            do {
                try await runConnection(url: url)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try await Task.sleep(nanoseconds: UInt64(reconnectDelay * 1_000_000_000))
            }
        }
    }

    private func runConnection(url: URL) async throws {
        #if os(Linux)
        throw NodeMeshClientError.unsupportedRelayScheme("linux-urlsession-websocket")
        #else
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }

        await daemon.connect()
        try await send(Self.makeHelloEnvelope(identity: config.identity), over: task)

        let heartbeatTask = Task {
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: UInt64(heartbeatInterval * 1_000_000_000))
                await daemon.heartbeat()
                try await send(Self.makeHeartbeatEnvelope(identity: config.identity), over: task)
            }
        }
        defer { heartbeatTask.cancel() }

        while !Task.isCancelled {
            let message = try await task.receive()
            guard let text = Self.text(from: message), let data = text.data(using: .utf8) else {
                continue
            }
            let envelope = try decoder.decode(MeshEnvelope.self, from: data)
            if let responseEnvelope = await response(to: envelope) {
                try await send(responseEnvelope, over: task)
            }
        }
        #endif
    }

    #if !os(Linux)
    private func send(_ envelope: MeshEnvelope, over task: URLSessionWebSocketTask) async throws {
        let data = try encoder.encode(envelope)
        guard let text = String(data: data, encoding: .utf8) else {
            return
        }
        try await task.send(.string(text))
    }

    private static func text(from message: URLSessionWebSocketTask.Message) -> String? {
        switch message {
        case .string(let text):
            return text
        case .data(let data):
            return String(data: data, encoding: .utf8)
        @unknown default:
            return nil
        }
    }
    #endif
}
