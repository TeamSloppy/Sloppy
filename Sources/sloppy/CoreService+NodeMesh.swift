import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols
import SloppyNodeCore

extension CoreService {
    enum MeshCoreProxyError: Error, LocalizedError {
        case missingLocalNodeConfig
        case invalidResponse(String)
        case remoteError(String)

        var errorDescription: String? {
            switch self {
            case .missingLocalNodeConfig:
                return "Local node has not joined a remote mesh."
            case .invalidResponse(let message):
                return "Invalid mesh Core response: \(message)"
            case .remoteError(let message):
                return message
            }
        }
    }

    public func getMeshState() async throws -> MeshState {
        var state = try nodeMeshStore.load()
        if let config = try? nodeConfigStore.load() {
            if let relayURL = config.relayURL,
               !relayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let coordinatorState = try? await Self.fetchMeshState(from: relayURL) {
                state = coordinatorState
            }
            if let networkId = config.networkId, !networkId.isEmpty {
                state.networkId = networkId
            }
            if let networkName = config.networkName, !networkName.isEmpty {
                state.networkName = networkName
            }
            state.localNode = MeshLocalNodeRecord(
                id: config.identity.nodeId,
                name: config.identity.name,
                publicKey: config.identity.publicKey,
                roles: config.identity.roles,
                capabilities: config.identity.capabilities,
                relayURL: config.relayURL,
                networkId: config.networkId,
                networkName: config.networkName
            )
        }
        return state
    }

    private static func fetchMeshState(from relayURL: String) async throws -> MeshState {
        let base = relayURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/v1/node/mesh") else {
            throw MeshCoreProxyError.invalidResponse("invalid relay URL")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MeshCoreProxyError.invalidResponse("coordinator state unavailable")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MeshState.self, from: data)
    }

    func startNodeMeshClientIfConfigured() async {
        guard nodeMeshClientTask == nil,
              let config = try? nodeConfigStore.load(),
              let relayURL = config.relayURL,
              !relayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }
        let client = NodeMeshClient(
            config: config,
            meshStore: nodeMeshStore,
            onEnvelope: { [weak self] envelope in
                guard let self else { return [] }
                return await self.handleMeshMailboxEnvelope(envelope)
            },
            rpcHandler: { [weak self] envelope, method, params in
                guard let self else { return nil }
                return await self.handleMeshCoreHTTPRPC(envelope: envelope, method: method, params: params)
            }
        )
        nodeMeshClientTask = Task {
            do {
                try await client.run(relayURL: relayURL)
            } catch is CancellationError {
            } catch {
                logger.warning("node.mesh.client.stopped", metadata: ["error": .string(String(describing: error))])
            }
        }
    }

    func proxyMeshCoreHTTPRequest(
        nodeId: String,
        method: String,
        path: String,
        body: Data? = nil,
        headers: [String: String] = [:],
        timeout: TimeInterval = 30
    ) async throws -> CoreRouterResponse {
        let config: NodeConfig
        do {
            config = try nodeConfigStore.load()
        } catch {
            throw MeshCoreProxyError.missingLocalNodeConfig
        }
        if nodeId == config.identity.nodeId {
            return await CoreRouter(service: self).handle(method: method, path: path, body: body, headers: headers)
        }
        let client = NodeMeshClient(config: config, meshStore: nodeMeshStore)
        var params: [String: JSONValue] = [
            "method": .string(method),
            "path": .string(path),
        ]
        if !headers.isEmpty {
            params["headers"] = .object(headers.mapValues(JSONValue.string))
        }
        if let body {
            params["bodyBase64"] = .string(body.base64EncodedString())
        }
        let response = try await client.sendRPCRequest(
            to: nodeId,
            method: "core.http",
            params: .object(params),
            timeout: timeout
        )
        return try decodeMeshCoreHTTPResponse(response)
    }

    private func decodeMeshCoreHTTPResponse(_ envelope: MeshEnvelope) throws -> CoreRouterResponse {
        guard let object = envelope.payload.asObject else {
            throw MeshCoreProxyError.invalidResponse("payload object missing")
        }
        if object["ok"]?.asBool == false {
            let error = object["error"]?.asObject
            let message = error?["message"]?.asString ?? "Remote mesh Core request failed."
            throw MeshCoreProxyError.remoteError(message)
        }
        guard let result = object["result"]?.asObject,
              let status = result["status"]?.asInt,
              let bodyBase64 = result["bodyBase64"]?.asString,
              let body = Data(base64Encoded: bodyBase64)
        else {
            throw MeshCoreProxyError.invalidResponse("result status/body missing")
        }
        return CoreRouterResponse(
            status: status,
            body: body,
            contentType: result["contentType"]?.asString ?? "application/json"
        )
    }

    public func listMeshNodes() throws -> [MeshNodeRecord] {
        try nodeMeshStore.listNodes()
    }

    public func configureMeshNetwork(_ request: MeshNetworkUpdateRequest) throws -> MeshState {
        try nodeMeshStore.createNetwork(id: request.id, name: request.name)
    }

    public func createMeshInvite(_ request: MeshInviteCreateRequest) throws -> MeshInvite {
        let relayURL = request.relayURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? request.relayURL
            : currentConfig.nodeMeshPublicURL
        return try nodeMeshStore.createInvite(
            networkId: request.networkId,
            name: request.name,
            roles: request.roles,
            capabilities: request.capabilities,
            ttlSeconds: request.ttlSeconds,
            relayURL: relayURL,
            nodeId: request.nodeId,
            publicKey: request.publicKey
        )
    }

    public func deleteMeshInvite(token: String) throws {
        try nodeMeshStore.revokeInvite(token: token, actor: "api")
    }

    public func acceptMeshInvite(_ request: MeshInviteAcceptRequest) throws -> MeshNodeRecord {
        do {
            if let nodeId = request.nodeId,
               let publicKey = request.publicKey {
                let identity = NodeIdentity(
                    nodeId: nodeId,
                    name: normalizedMeshNodeName(request.name, fallback: nodeId),
                    publicKey: publicKey,
                    privateKey: "",
                    roles: request.roles ?? ["worker"],
                    capabilities: request.capabilities ?? ["run_agent", "git"]
                )
                return try nodeMeshStore.consumeInvite(token: request.token, identity: identity, endpoint: request.endpoint)
            }
            return try nodeMeshStore.acceptInvite(token: request.token, endpoint: request.endpoint)
        } catch NodeMeshStoreError.inviteMissing {
            if let bundle = try? MeshInviteBundle.parse(request.token) {
                throw NodeMeshStoreError.inviteWrongCoordinator(bundle.relayURL)
            }
            throw NodeMeshStoreError.inviteMissing
        }
    }

    private func normalizedMeshNodeName(_ name: String?, fallback: String) -> String {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return fallback
        }
        return trimmed
    }

    public func joinRemoteMesh(_ request: MeshRemoteJoinRequest) async throws -> MeshRemoteJoinResult {
        let joiner = NodeMeshRemoteJoiner(
            configStore: nodeConfigStore,
            acceptInvite: { url, acceptRequest in
                try await Self.postMeshInviteAccept(to: url, request: acceptRequest)
            }
        )
        let result = try await joiner.join(request)
        await startNodeMeshClientIfConfigured()
        return result
    }

    private static func postMeshInviteAccept(to url: URL, request: MeshInviteAcceptRequest) async throws -> MeshNodeRecord {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        urlRequest.httpBody = try encoder.encode(request)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MeshRemoteJoinError.coordinatorUnreachable(url.absoluteString)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MeshNodeRecord.self, from: data)
    }

    public func registerMeshNode(_ request: MeshNodeRegisterRequest) throws -> MeshNodeRecord {
        try nodeMeshStore.upsertNodeRecord(
            MeshNodeRecord(
                id: request.id,
                name: request.name,
                publicKey: request.publicKey,
                roles: request.roles,
                endpoint: request.endpoint,
                status: .offline,
                capabilities: request.capabilities
            ),
            auditAction: "node.register.api"
        )
    }

    public func deleteMeshNode(id: String) throws {
        try nodeMeshStore.removeNodeRecord(nodeId: id, actor: "api")
    }

    public func listMeshSharedProjects() throws -> [SharedProjectRecord] {
        try nodeMeshStore.listSharedProjects()
    }

    public func createMeshSharedProject(_ request: MeshSharedProjectCreateRequest) throws -> SharedProjectRecord {
        try nodeMeshStore.createSharedProject(
            id: request.id,
            name: request.name,
            repoUrl: request.repoUrl,
            defaultBranch: request.defaultBranch
        )
    }

    public func deleteMeshSharedProject(id: String) throws {
        try nodeMeshStore.removeSharedProject(projectIdOrName: id, actor: "api")
    }

    public func attachMeshSharedProjectMember(
        projectId: String,
        request: MeshSharedProjectMemberRequest
    ) throws -> SharedProjectRecord {
        try nodeMeshStore.attachMember(
            projectIdOrName: projectId,
            nodeId: request.nodeId,
            localRepoPath: request.localRepoPath,
            role: request.role,
            actorId: request.actorId,
            permissions: request.permissions
        )
    }

    public func updateMeshSharedProject(
        id: String,
        request: MeshSharedProjectUpdateRequest
    ) throws -> SharedProjectRecord {
        try nodeMeshStore.updateSharedProject(
            projectIdOrName: id,
            name: request.name,
            repoUrl: request.repoUrl,
            defaultBranch: request.defaultBranch,
            policies: request.policies,
            actor: "api"
        )
    }

    public func listMeshTasks(projectId: String? = nil) throws -> [MeshTaskRecord] {
        try nodeMeshStore.listTasks(projectIdOrName: projectId)
    }

    public func listMeshAuditLog() throws -> [MeshAuditLogEntry] {
        try nodeMeshStore.load().auditLog.sorted { $0.time > $1.time }
    }

    public func createMeshTask(_ request: MeshTaskCreateRequest) throws -> MeshTaskRecord {
        try nodeMeshStore.dispatchTask(
            projectIdOrName: request.projectId,
            title: request.title,
            assignedNodeId: request.assignedNodeId
        )
    }

    public func updateMeshTask(id: String, request: MeshTaskUpdateRequest) throws -> MeshTaskRecord {
        try nodeMeshStore.updateTaskStatus(
            taskId: id,
            projectIdOrName: request.projectId,
            status: request.status,
            actor: "api",
            branch: request.branch,
            commit: request.commit,
            summary: request.summary
        )
    }

    func handleMeshCoreHTTPRPC(envelope: MeshEnvelope, method: String, params: JSONValue) async -> JSONValue {
        guard method == "core.http" else {
            return meshCoreRPCErrorPayload(
                requestId: envelope.id,
                method: method,
                code: "unknown_method",
                message: "Unknown mesh Core RPC method."
            )
        }
        guard let object = params.asObject else {
            return meshCoreRPCErrorPayload(
                requestId: envelope.id,
                method: method,
                code: "invalid_params",
                message: "core.http params object is required."
            )
        }
        let httpMethod = object["method"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? "GET"
        guard let path = object["path"]?.asString,
              path.hasPrefix("/") else {
            return meshCoreRPCErrorPayload(
                requestId: envelope.id,
                method: method,
                code: "invalid_params",
                message: "core.http path must start with /."
            )
        }

        let headers = (object["headers"]?.asObject ?? [:]).reduce(into: [String: String]()) { partial, item in
            if let value = item.value.asString {
                partial[item.key] = value
            }
        }
        let body: Data?
        if let bodyBase64 = object["bodyBase64"]?.asString, !bodyBase64.isEmpty {
            body = Data(base64Encoded: bodyBase64)
        } else {
            body = nil
        }

        let router = CoreRouter(service: self)
        let response = await router.handle(
            method: httpMethod,
            path: path,
            body: body,
            headers: headers,
            remoteAddress: "mesh:\(envelope.from)"
        )
        guard response.sseStream == nil else {
            return meshCoreRPCErrorPayload(
                requestId: envelope.id,
                method: method,
                code: "stream_unsupported",
                message: "core.http does not support streaming responses."
            )
        }

        return .object([
            "requestId": .string(envelope.id),
            "method": .string(method),
            "ok": .bool(response.status < 400),
            "result": .object([
                "status": .number(Double(response.status)),
                "contentType": .string(response.contentType),
                "bodyBase64": .string(response.body.base64EncodedString()),
            ]),
        ])
    }

    func handleMeshMailboxEnvelope(_ envelope: MeshEnvelope) async -> [MeshEnvelope] {
        guard envelope.type == .eventPublish,
              envelope.payload.asObject?["kind"]?.asString == "agent.browser_context_message",
              let requestValue = envelope.payload.asObject?["request"]
        else {
            return []
        }
        let localNodeId = envelope.to ?? ""
        if (try? nodeMeshStore.load().processedEnvelopeIDs.contains(envelope.id)) == true {
            return [meshMailboxAck(for: envelope, from: localNodeId)]
        }
        do {
            let request = try JSONValueCoder.decode(BrowserContextMessageRequest.self, from: requestValue)
            _ = try await postBrowserContextMessage(request)
            try nodeMeshStore.recordProcessedEnvelope(id: envelope.id, processedBy: localNodeId)
            return [meshMailboxAck(for: envelope, from: localNodeId)]
        } catch {
            logger.warning("node.mesh.mailbox.browser_context.failed", metadata: [
                "envelope": .string(envelope.id),
                "from": .string(envelope.from),
                "error": .string(String(describing: error)),
            ])
            return []
        }
    }

    private func meshMailboxAck(for envelope: MeshEnvelope, from nodeId: String) -> MeshEnvelope {
        MeshEnvelope(
            type: .eventAck,
            from: nodeId,
            to: envelope.from,
            payload: .object(["messageId": .string(envelope.id)])
        )
    }

    private func meshCoreRPCErrorPayload(requestId: String, method: String, code: String, message: String) -> JSONValue {
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
}
