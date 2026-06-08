import Foundation
import Logging
import Protocols
import SloppyNodeCore

actor NodeMeshRelay {
    private struct Connection {
        var node: MeshNodeRecord
        var context: WebSocketConnectionContext
    }

    private var connections: [String: Connection] = [:]
    private var nodes: [String: MeshNodeRecord] = [:]
    private let store: NodeMeshStore?
    private let logger: Logger
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(store: NodeMeshStore? = nil, logger: Logger = Logger(label: "sloppy.node.mesh.relay")) {
        self.store = store
        self.logger = logger
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func attach(connection: WebSocketConnectionContext, remoteAddress: String?) async {
        var attachedNodeId: String?
        defer {
            if let attachedNodeId {
                markOffline(nodeId: attachedNodeId)
            }
        }

        for await text in connection.incomingMessages() {
            guard let data = text.data(using: .utf8) else {
                continue
            }
            do {
                let envelope = try decoder.decode(MeshEnvelope.self, from: data)
                switch envelope.type {
                case .nodeHello:
                    let node = nodeRecord(from: envelope, remoteAddress: remoteAddress)
                    nodes[node.id] = node
                    connections[node.id] = Connection(node: node, context: connection)
                    attachedNodeId = node.id
                    persist {
                        try store?.upsertNodeRecord(node, auditAction: "node.hello")
                    }
                case .nodeHeartbeat:
                    handleHeartbeat(envelope)
                default:
                    try await route(envelope)
                }
            } catch {
                logger.warning("Node mesh websocket message failed", metadata: ["error": .string(String(describing: error))])
            }
        }
    }

    func activeNodeIds() -> [String] {
        Array(connections.keys).sorted()
    }

    func nodeRecord(id: String) -> MeshNodeRecord? {
        nodes[id]
    }

    private func route(_ envelope: MeshEnvelope) async throws {
        guard let target = envelope.to else {
            return
        }
        guard let connection = connections[target] else {
            logger.warning(
                "Node mesh target is not connected",
                metadata: [
                    "from": .string(envelope.from),
                    "target": .string(target),
                    "type": .string(envelope.type.rawValue),
                ]
            )
            try await sendUnavailableTargetError(for: envelope, target: target)
            return
        }
        persist {
            try store?.routeEnvelope(envelope)
        }
        let data = try encoder.encode(envelope)
        guard let text = String(data: data, encoding: .utf8) else {
            return
        }
        _ = await connection.context.sendText(text)
    }

    private func handleHeartbeat(_ envelope: MeshEnvelope) {
        guard var node = nodes[envelope.from] else {
            return
        }
        node.status = .online
        node.lastSeenAt = Date()
        nodes[node.id] = node
        if var connection = connections[node.id] {
            connection.node = node
            connections[node.id] = connection
        }
        persist {
            try store?.updateNodeStatus(nodeId: node.id, status: .online, auditAction: "node.heartbeat")
        }
    }

    private func markOffline(nodeId: String) {
        connections[nodeId] = nil
        guard var node = nodes[nodeId] else {
            return
        }
        node.status = .offline
        node.lastSeenAt = Date()
        nodes[nodeId] = node
        persist {
            try store?.updateNodeStatus(nodeId: nodeId, status: .offline, auditAction: "node.offline")
        }
    }

    private func nodeRecord(from envelope: MeshEnvelope, remoteAddress: String?) -> MeshNodeRecord {
        let payload = envelope.payload.asObject ?? [:]
        return MeshNodeRecord(
            id: envelope.from,
            name: payload["name"]?.asString ?? envelope.from,
            publicKey: payload["publicKey"]?.asString ?? "",
            roles: stringArray(payload["roles"]),
            endpoint: remoteAddress,
            status: .online,
            lastSeenAt: Date(),
            capabilities: stringArray(payload["capabilities"])
        )
    }

    private func stringArray(_ value: JSONValue?) -> [String] {
        guard case .array(let values) = value else {
            return []
        }
        return values.compactMap(\.asString)
    }

    private func sendUnavailableTargetError(for envelope: MeshEnvelope, target: String) async throws {
        guard let source = connections[envelope.from] else {
            return
        }
        let errorEnvelope = MeshEnvelope(
            type: .rpcResponse,
            from: "relay",
            to: envelope.from,
            scope: envelope.scope,
            payload: .object([
                "requestId": .string(envelope.id),
                "ok": .bool(false),
                "error": .object([
                    "code": .string("node_unavailable"),
                    "target": .string(target),
                    "message": .string("Target node is not connected."),
                ]),
            ])
        )
        let data = try encoder.encode(errorEnvelope)
        guard let text = String(data: data, encoding: .utf8) else {
            return
        }
        _ = await source.context.sendText(text)
        persist {
            try store?.recordRouteFailure(envelope, target: target, message: "target node unavailable")
        }
    }

    private func persist(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            logger.warning("Node mesh persistence failed", metadata: ["error": .string(String(describing: error))])
        }
    }
}
