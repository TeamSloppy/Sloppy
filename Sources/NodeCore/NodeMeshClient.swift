import Foundation
import Protocols

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum NodeMeshClientError: LocalizedError, Equatable {
    case invalidRelayURL(String)
    case unsupportedRelayScheme(String)
    case missingRelayURL

    public var errorDescription: String? {
        switch self {
        case .invalidRelayURL(let value):
            "Invalid relay URL: \(value)"
        case .unsupportedRelayScheme(let scheme):
            "Unsupported relay URL scheme: \(scheme)"
        case .missingRelayURL:
            "Mesh relay URL is required."
        }
    }
}

public actor NodeMeshClient {
    public typealias EnvelopeObserver = @Sendable (MeshEnvelope) async -> Void

    private let config: NodeConfig
    private let daemon: NodeDaemon
    private let meshStore: NodeMeshStore?
    private let heartbeatInterval: TimeInterval
    private let reconnectDelay: TimeInterval
    private let onEnvelope: EnvelopeObserver?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var isRelayAuthenticated: Bool

    public init(
        config: NodeConfig,
        daemon: NodeDaemon? = nil,
        meshStore: NodeMeshStore? = nil,
        heartbeatInterval: TimeInterval = 15,
        reconnectDelay: TimeInterval = 2,
        onEnvelope: EnvelopeObserver? = nil
    ) {
        self.config = config
        self.daemon = daemon ?? NodeDaemon(config: config)
        self.meshStore = meshStore
        self.heartbeatInterval = max(1, heartbeatInterval)
        self.reconnectDelay = max(0.25, reconnectDelay)
        self.onEnvelope = onEnvelope
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.isRelayAuthenticated = false
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

    public static func makeRPCRequestEnvelope(identity: NodeIdentity, to targetNodeId: String, method: String, params: JSONValue = .object([:])) -> MeshEnvelope {
        MeshEnvelope(
            type: .rpcRequest,
            from: identity.nodeId,
            to: targetNodeId,
            payload: .object([
                "method": .string(method),
                "params": params,
            ])
        )
    }

    public static func makeAuthResponseEnvelope(identity: NodeIdentity, challengeEnvelope: MeshEnvelope) throws -> MeshEnvelope? {
        guard challengeEnvelope.type == .authChallenge else {
            return nil
        }
        let challenge = try JSONValueCoder.decode(MeshAuthChallengePayload.self, from: challengeEnvelope.payload)
        guard challenge.nodeId.isEmpty || challenge.nodeId == identity.nodeId else {
            return nil
        }
        let signature = try NodeIdentityGenerator.sign(
            challenge: Data(challenge.nonce.utf8),
            privateKey: identity.privateKey
        )
        return MeshEnvelope(
            type: .authResponse,
            from: identity.nodeId,
            to: challengeEnvelope.from,
            scope: challengeEnvelope.scope,
            payload: try JSONValueCoder.encode(
                MeshAuthResponsePayload(
                    nonce: challenge.nonce,
                    nodeId: identity.nodeId,
                    publicKey: identity.publicKey,
                    signature: signature
                )
            )
        )
    }

    public func response(to envelope: MeshEnvelope) async -> MeshEnvelope? {
        await responses(to: envelope).first
    }

    public func responses(to envelope: MeshEnvelope) async -> [MeshEnvelope] {
        if envelope.type == .authChallenge {
            do {
                guard let response = try Self.makeAuthResponseEnvelope(identity: config.identity, challengeEnvelope: envelope) else {
                    return []
                }
                isRelayAuthenticated = true
                return [response]
            } catch {
                return []
            }
        }

        guard isRelayAuthenticated else {
            return []
        }

        if envelope.type == .taskDispatch {
            return handleTaskDispatch(envelope)
        }

        guard envelope.type == .rpcRequest else {
            if let onEnvelope {
                await onEnvelope(envelope)
            }
            return []
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
            responsePayload = projectStatusResponse(for: envelope, method: method)
        case "shared_project.list":
            responsePayload = sharedProjectListResponse(for: envelope, method: method)
        case "shared_project.get":
            responsePayload = sharedProjectGetResponse(for: envelope, method: method)
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

        return [MeshEnvelope(
            type: .rpcResponse,
            from: config.identity.nodeId,
            to: envelope.from,
            scope: envelope.scope,
            payload: responsePayload
        )]
    }

    private func sharedProjectListResponse(for envelope: MeshEnvelope, method: String) -> JSONValue {
        do {
            let projects = try visibleSharedProjects(for: envelope.from)
            return .object([
                "requestId": .string(envelope.id),
                "method": .string(method),
                "ok": .bool(true),
                "result": .object([
                    "projects": .array(try projects.map { try JSONValueCoder.encode($0) }),
                ]),
            ])
        } catch {
            return rpcErrorPayload(requestId: envelope.id, method: method, code: "mesh_store_unavailable", message: error.localizedDescription)
        }
    }

    private func projectStatusResponse(for envelope: MeshEnvelope, method: String) -> JSONValue {
        let params = envelope.payload.asObject?["params"]?.asObject ?? [:]
        guard let sharedProjectId = params["sharedProjectId"]?.asString, !sharedProjectId.isEmpty else {
            return rpcErrorPayload(requestId: envelope.id, method: method, code: "invalid_params", message: "sharedProjectId is required.")
        }

        do {
            guard let project = try visibleSharedProjects(for: envelope.from).first(where: { $0.id == sharedProjectId || $0.name == sharedProjectId }) else {
                return rpcErrorPayload(
                    requestId: envelope.id,
                    method: method,
                    code: "forbidden",
                    message: "Shared project is not visible to the caller."
                )
            }
            guard let localMember = project.members.first(where: { $0.nodeId == config.identity.nodeId }) else {
                return rpcErrorPayload(
                    requestId: envelope.id,
                    method: method,
                    code: "not_member",
                    message: "This node is not a shared project member."
                )
            }

            var result: [String: JSONValue] = [
                "sharedProjectId": .string(project.id),
                "name": .string(project.name),
                "repoUrl": .string(project.repoUrl),
                "defaultBranch": .string(project.defaultBranch),
                "localRepoPath": .string(localMember.localRepoPath),
            ]
            if FileManager.default.fileExists(atPath: localMember.localRepoPath) {
                result["gitBranch"] = gitOutput(arguments: ["branch", "--show-current"], at: localMember.localRepoPath)
                    .map(JSONValue.string) ?? .null
                result["dirty"] = .bool((gitOutput(arguments: ["status", "--porcelain"], at: localMember.localRepoPath) ?? "").isEmpty == false)
            }
            if let meshStore {
                let tasks = try meshStore.listTasks(projectIdOrName: project.id)
                result["tasks"] = .array(try tasks.map { try JSONValueCoder.encode($0) })
            }
            return .object([
                "requestId": .string(envelope.id),
                "method": .string(method),
                "ok": .bool(true),
                "result": .object(result),
            ])
        } catch {
            return rpcErrorPayload(requestId: envelope.id, method: method, code: "mesh_store_unavailable", message: error.localizedDescription)
        }
    }

    private func sharedProjectGetResponse(for envelope: MeshEnvelope, method: String) -> JSONValue {
        let params = envelope.payload.asObject?["params"]?.asObject ?? [:]
        let projectIdOrName = params["id"]?.asString ?? params["name"]?.asString ?? ""
        do {
            guard let project = try visibleSharedProjects(for: envelope.from).first(where: { $0.id == projectIdOrName || $0.name == projectIdOrName }) else {
                return rpcErrorPayload(
                    requestId: envelope.id,
                    method: method,
                    code: "forbidden",
                    message: "Shared project is not visible to the caller."
                )
            }
            return .object([
                "requestId": .string(envelope.id),
                "method": .string(method),
                "ok": .bool(true),
                "result": try JSONValueCoder.encode(project),
            ])
        } catch {
            return rpcErrorPayload(requestId: envelope.id, method: method, code: "mesh_store_unavailable", message: error.localizedDescription)
        }
    }

    private func visibleSharedProjects(for callerNodeId: String) throws -> [SharedProjectRecord] {
        guard let meshStore else {
            throw NodeMeshStoreError.projectMissing("mesh_store")
        }
        return try meshStore.listSharedProjects().filter { project in
            project.members.contains { member in
                member.nodeId == callerNodeId && member.permissions.contains(MeshPermission.projectRead.rawValue)
            }
        }
    }

    private func rpcErrorPayload(requestId: String, method: String, code: String, message: String) -> JSONValue {
        .object([
            "requestId": .string(requestId),
            "method": .string(method),
            "ok": .bool(false),
            "error": .object([
                "code": .string(code),
                "message": .string(message),
            ]),
        ])
    }

    private func handleTaskDispatch(_ envelope: MeshEnvelope) -> [MeshEnvelope] {
        let payload = envelope.payload.asObject ?? [:]
        let taskId = payload["taskId"]?.asString ?? envelope.id
        let projectId = payload["projectId"]?.asString ?? ""

        do {
            guard let meshStore else {
                return [makeTaskStatusUpdate(
                    taskId: taskId,
                    projectId: projectId,
                    status: .blocked,
                    to: envelope.from,
                    scope: envelope.scope,
                    summary: "Worker mesh store is not configured."
                )]
            }
            let state = try meshStore.load()
            guard let project = state.sharedProjects.first(where: { $0.id == projectId || $0.name == projectId }) else {
                return [makeTaskStatusUpdate(
                    taskId: taskId,
                    projectId: projectId,
                    status: .blocked,
                    to: envelope.from,
                    scope: envelope.scope,
                    summary: "Shared project is not configured on this node."
                )]
            }
            guard project.members.contains(where: { $0.nodeId == config.identity.nodeId }) else {
                return [makeTaskStatusUpdate(
                    taskId: taskId,
                    projectId: project.id,
                    status: .blocked,
                    to: envelope.from,
                    scope: envelope.scope,
                    summary: "This node is not a member of the shared project."
                )]
            }

            let claimed = try meshStore.updateTaskStatus(
                taskId: taskId,
                status: .claimed,
                actor: config.identity.nodeId,
                summary: "Task dispatch claimed by \(config.identity.name)."
            )
            let started = try meshStore.updateTaskStatus(
                taskId: taskId,
                status: .started,
                actor: config.identity.nodeId,
                summary: "Task execution started by \(config.identity.name)."
            )
            return [
                makeTaskStatusUpdate(
                    taskId: claimed.id,
                    projectId: claimed.projectId,
                    status: claimed.status,
                    to: envelope.from,
                    scope: envelope.scope,
                    summary: claimed.summary
                ),
                makeTaskStatusUpdate(
                    taskId: started.id,
                    projectId: started.projectId,
                    status: started.status,
                    to: envelope.from,
                    scope: envelope.scope,
                    summary: started.summary
                ),
            ]
        } catch {
            return [makeTaskStatusUpdate(
                taskId: taskId,
                projectId: projectId,
                status: .blocked,
                to: envelope.from,
                scope: envelope.scope,
                summary: error.localizedDescription
            )]
        }
    }

    private func makeTaskStatusUpdate(
        taskId: String,
        projectId: String,
        status: MeshTaskStatus,
        to: String,
        scope: String?,
        summary: String?
    ) -> MeshEnvelope {
        MeshEnvelope(
            type: .taskStatusUpdate,
            from: config.identity.nodeId,
            to: to,
            scope: scope ?? (projectId.isEmpty ? nil : "sharedProject:\(projectId)"),
            payload: .object([
                "taskId": .string(taskId),
                "projectId": .string(projectId),
                "nodeId": .string(config.identity.nodeId),
                "status": .string(status.rawValue),
                "summary": summary.map(JSONValue.string) ?? .null,
            ])
        )
    }

    private func gitOutput(arguments: [String], at path: String) -> String? {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = URL(fileURLWithPath: path, isDirectory: true)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return nil
            }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
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

    public func sendRPCRequest(
        relayURL: String? = nil,
        to targetNodeId: String,
        method: String,
        params: JSONValue = .object([:]),
        timeout: TimeInterval = 30
    ) async throws -> MeshEnvelope {
        let configuredRelayURL = relayURL ?? config.relayURL
        guard let configuredRelayURL, !configuredRelayURL.isEmpty else {
            throw NodeMeshClientError.missingRelayURL
        }
        let url = try Self.resolveRelayWebSocketURL(configuredRelayURL)
        let request = Self.makeRPCRequestEnvelope(identity: config.identity, to: targetNodeId, method: method, params: params)

        return try await withThrowingTaskGroup(of: MeshEnvelope.self) { group in
            group.addTask {
                try await self.runRPCConnection(url: url, request: request, timeout: timeout)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                throw NodeMeshRPCError.timeout(request.id)
            }

            guard let response = try await group.next() else {
                throw NodeMeshRPCError.timeout(request.id)
            }
            group.cancelAll()
            return response
        }
    }

    private func runConnection(url: URL) async throws {
        #if os(Linux)
        throw NodeMeshClientError.unsupportedRelayScheme("linux-urlsession-websocket")
        #else
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }

        var sentHello = false
        var heartbeatTask: Task<Void, Error>?
        defer { heartbeatTask?.cancel() }

        while !Task.isCancelled {
            let message = try await task.receive()
            guard let text = Self.text(from: message), let data = text.data(using: .utf8) else {
                continue
            }
            let envelope = try decoder.decode(MeshEnvelope.self, from: data)
            let responseEnvelopes = await responses(to: envelope)
            for responseEnvelope in responseEnvelopes {
                try await send(responseEnvelope, over: task)
            }
            if envelope.type == .authChallenge, !responseEnvelopes.isEmpty, !sentHello {
                await daemon.connect()
                try await send(Self.makeHelloEnvelope(identity: config.identity), over: task)
                sentHello = true
                heartbeatTask = Task {
                    while !Task.isCancelled {
                        try await Task.sleep(nanoseconds: UInt64(heartbeatInterval * 1_000_000_000))
                        await daemon.heartbeat()
                        try await send(Self.makeHeartbeatEnvelope(identity: config.identity), over: task)
                    }
                }
            }
        }
        #endif
    }

    private func runRPCConnection(url: URL, request: MeshEnvelope, timeout: TimeInterval) async throws -> MeshEnvelope {
        #if os(Linux)
        throw NodeMeshClientError.unsupportedRelayScheme("linux-urlsession-websocket")
        #else
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }

        let manager = NodeMeshRPCManager()
        var sentRequest = false
        var responseTask: Task<MeshEnvelope, Error>?
        defer { responseTask?.cancel() }

        while !Task.isCancelled {
            let message = try await task.receive()
            guard let text = Self.text(from: message), let data = text.data(using: .utf8) else {
                continue
            }
            let envelope = try decoder.decode(MeshEnvelope.self, from: data)
            let responseEnvelopes = await responses(to: envelope)
            for responseEnvelope in responseEnvelopes {
                try await send(responseEnvelope, over: task)
            }

            if envelope.type == .authChallenge, !responseEnvelopes.isEmpty, !sentRequest {
                await daemon.connect()
                try await send(Self.makeHelloEnvelope(identity: config.identity), over: task)
                sentRequest = true
                responseTask = Task {
                    try await manager.send(request, timeout: timeout) { outbound in
                        try await self.send(outbound, over: task)
                    }
                }
            }

            if await manager.receive(envelope), let responseTask {
                return try await responseTask.value
            }
        }

        throw CancellationError()
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
