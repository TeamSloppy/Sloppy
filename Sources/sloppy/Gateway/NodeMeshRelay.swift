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
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func attach(connection: WebSocketConnectionContext, remoteAddress: String?) async {
        var attachedNodeId: String?
        let authChallenge = makeAuthChallenge()
        var authenticatedNode: MeshNodeRecord?
        defer {
            if let attachedNodeId {
                markOffline(nodeId: attachedNodeId)
            }
        }

        do {
            try await Task.sleep(nanoseconds: 1_000_000)
            try await send(authChallenge, over: connection)
        } catch {
            logger.warning("Node mesh auth challenge failed", metadata: ["error": .string(String(describing: error))])
            await connection.close()
            return
        }

        for await text in connection.incomingMessages() {
            guard let data = text.data(using: .utf8) else {
                continue
            }
            do {
                let envelope = try decoder.decode(MeshEnvelope.self, from: data)
                switch envelope.type {
                case .authResponse:
                    switch verifyAuthResponse(envelope, challenge: authChallenge) {
                    case let .success(node):
                        authenticatedNode = node
                    case let .failure(message):
                        try await sendAuthFailure(to: envelope.from, message: message, over: connection)
                        await connection.close()
                        return
                    }
                case .nodeHello:
                    guard let authenticatedNode, authenticatedNode.id == envelope.from else {
                        try await sendAuthFailure(to: envelope.from, message: "Node is not authenticated.", over: connection)
                        await connection.close()
                        return
                    }
                    let node = nodeRecord(from: envelope, remoteAddress: remoteAddress)
                    nodes[node.id] = node
                    connections[node.id] = Connection(node: node, context: connection)
                    attachedNodeId = node.id
                    persist {
                        try store?.upsertNodeRecord(node, auditAction: "node.hello")
                    }
                    try await sendPendingTaskDispatches(to: node.id)
                case .nodeHeartbeat:
                    guard authenticatedNode?.id == envelope.from else {
                        continue
                    }
                    handleHeartbeat(envelope)
                default:
                    guard authenticatedNode != nil else {
                        continue
                    }
                    try await route(envelope)
                }
            } catch {
                logger.warning("Node mesh websocket message failed", metadata: ["error": .string(String(describing: error))])
            }
        }
    }

    private enum AuthVerificationResult {
        case success(MeshNodeRecord)
        case failure(String)
    }

    private func makeAuthChallenge() -> MeshEnvelope {
        MeshEnvelope(
            type: .authChallenge,
            from: "relay",
            payload: .object([
                "nonce": .string(NodeIdentityGenerator.randomToken(byteCount: 24)),
                "nodeId": .string(""),
                "publicKey": .string(""),
                "issuedAt": .string(ISO8601DateFormatter().string(from: Date())),
            ])
        )
    }

    private func verifyAuthResponse(_ envelope: MeshEnvelope, challenge: MeshEnvelope) -> AuthVerificationResult {
        guard let store else {
            return .failure("Node mesh store is not configured.")
        }
        do {
            let challengePayload = try JSONValueCoder.decode(MeshAuthChallengePayload.self, from: challenge.payload)
            let response = try JSONValueCoder.decode(MeshAuthResponsePayload.self, from: envelope.payload)
            guard response.nonce == challengePayload.nonce else {
                return .failure("Auth nonce does not match.")
            }
            guard response.nodeId == envelope.from else {
                return .failure("Auth node id does not match envelope sender.")
            }
            guard let registered = try store.load().nodes.first(where: { $0.id == response.nodeId }) else {
                return .failure("Node is not registered.")
            }
            guard response.publicKey == registered.publicKey else {
                return .failure("Auth public key does not match registered node.")
            }
            guard NodeIdentityGenerator.verify(
                signature: response.signature,
                challenge: Data(response.nonce.utf8),
                publicKey: registered.publicKey
            ) else {
                return .failure("Auth signature is invalid.")
            }
            return .success(registered)
        } catch {
            return .failure("Auth response is invalid.")
        }
    }

    func activeNodeIds() -> [String] {
        Array(connections.keys).sorted()
    }

    func nodeRecord(id: String) -> MeshNodeRecord? {
        nodes[id]
    }

    private func route(_ envelope: MeshEnvelope) async throws {
        if envelope.type == .taskStatusUpdate {
            persistTaskStatusUpdate(envelope)
        }
        guard let target = envelope.to else {
            return
        }
        if envelope.type == .rpcRequest, let denial = rpcAuthorizationDenial(for: envelope, target: target) {
            try await sendForbiddenRPCResponse(for: envelope, message: denial)
            persist {
                try store?.recordRouteFailure(envelope, target: target, message: denial)
            }
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
        try await send(envelope, over: connection.context)
    }

    private func sendPendingTaskDispatches(to nodeId: String) async throws {
        guard let store, let connection = connections[nodeId] else {
            return
        }
        let state = try store.load()
        for envelope in state.envelopes where envelope.type == .taskDispatch && envelope.to == nodeId {
            try await send(envelope, over: connection.context)
            let taskId = envelope.payload.asObject?["taskId"]?.asString ?? envelope.id
            persist {
                try store.recordTaskDispatchDelivery(taskId: taskId, target: nodeId, delivered: true)
            }
        }
    }

    private func persistTaskStatusUpdate(_ envelope: MeshEnvelope) {
        guard let store else { return }
        let payload = envelope.payload.asObject ?? [:]
        guard let taskId = payload["taskId"]?.asString,
              let rawStatus = payload["status"]?.asString,
              let status = MeshTaskStatus(rawValue: rawStatus)
        else { return }
        persist {
            _ = try store.updateTaskStatus(
                taskId: taskId,
                status: status,
                actor: envelope.from,
                branch: payload["branch"]?.asString,
                commit: payload["commit"]?.asString,
                summary: payload["summary"]?.asString
            )
        }
    }

    private func rpcAuthorizationDenial(for envelope: MeshEnvelope, target: String) -> String? {
        guard let store,
              envelope.scope?.hasPrefix("sharedProject:") == true,
              let projectId = envelope.scope.map({ String($0.dropFirst("sharedProject:".count)) })
        else {
            return nil
        }

        do {
            guard let project = try store.load().sharedProjects.first(where: { $0.id == projectId }) else {
                return "shared project scope is unknown"
            }
            guard let sourceMember = project.members.first(where: { $0.nodeId == envelope.from }) else {
                return "source node is not a project member"
            }
            guard project.members.contains(where: { $0.nodeId == target }) else {
                return "target node is not a project member"
            }
            guard sourceMember.permissions.contains(MeshPermission.nodeRPC.rawValue) else {
                return "missing node.rpc permission"
            }
            return nil
        } catch {
            return "mesh authorization state is unavailable"
        }
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
        guard case let .array(values) = value else {
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
        try await send(errorEnvelope, over: source.context)
        persist {
            try store?.recordRouteFailure(envelope, target: target, message: "target node unavailable")
        }
    }

    private func sendForbiddenRPCResponse(for envelope: MeshEnvelope, message: String) async throws {
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
                    "code": .string("forbidden"),
                    "message": .string(message),
                ]),
            ])
        )
        try await send(errorEnvelope, over: source.context)
    }

    private func sendAuthFailure(to nodeId: String, message: String, over connection: WebSocketConnectionContext) async throws {
        let errorEnvelope = MeshEnvelope(
            type: .rpcResponse,
            from: "relay",
            to: nodeId.isEmpty ? nil : nodeId,
            payload: .object([
                "ok": .bool(false),
                "error": .object([
                    "code": .string("auth_failed"),
                    "message": .string(message),
                ]),
            ])
        )
        try await send(errorEnvelope, over: connection)
    }

    private func send(_ envelope: MeshEnvelope, over connection: WebSocketConnectionContext) async throws {
        let data = try encoder.encode(envelope)
        guard let text = String(data: data, encoding: .utf8) else {
            return
        }
        _ = await connection.sendText(text)
    }

    private func persist(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            logger.warning("Node mesh persistence failed", metadata: ["error": .string(String(describing: error))])
        }
    }
}
