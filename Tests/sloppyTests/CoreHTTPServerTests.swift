import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging
import Testing
@testable import sloppy
@testable import Protocols
@testable import SloppyNodeCore

private struct SSEMalformedResponseError: Error {}
private struct WebSocketMalformedResponseError: Error {}
private struct DashboardTerminalClientFrame: Encodable {
    let type: String
    let token: String?
    let projectId: String?
    let cwd: String?
    let cols: Int?
    let rows: Int?
    let data: String?
}
private struct DashboardTerminalServerFrame: Decodable {
    let type: String
    let sessionId: String?
    let cwd: String?
    let shell: String?
    let pid: Int32?
    let data: String?
    let exitCode: Int32?
    let code: String?
    let message: String?
}
private struct AsyncTestTimeoutError: Error {
    let operation: String
}

private final class SSEDataCollector: NSObject, @unchecked Sendable, URLSessionDataDelegate {
    private let lock = NSLock()
    private var receivedData = Data()
    private var httpResponse: HTTPURLResponse?
    private var continuation: CheckedContinuation<(HTTPURLResponse, Data), Error>?
    private var task: URLSessionDataTask?

    func start(request: URLRequest) async throws -> (HTTPURLResponse, Data) {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            lock.lock()
            self.task = session.dataTask(with: request)
            lock.unlock()
            self.task?.resume()
            session.finishTasksAndInvalidate()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        receivedData.append(data)
        let response = httpResponse
        let count = receivedData.count
        let dataCopy = receivedData
        lock.unlock()
        if let response = response, count > 0 {
            let text = String(data: dataCopy, encoding: .utf8) ?? ""
            if text.contains("data: ") {
                lock.lock()
                let cont = continuation
                continuation = nil
                lock.unlock()
                if let cont = cont {
                    dataTask.cancel()
                    cont.resume(returning: (response, dataCopy))
                }
            }
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        httpResponse = response as? HTTPURLResponse
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let cont = continuation
        continuation = nil
        let response = httpResponse
        let data = receivedData
        lock.unlock()
        guard let cont = cont else { return }
        if let error = error {
            cont.resume(throwing: error)
        } else if let response = response {
            cont.resume(returning: (response, data))
        } else {
            cont.resume(throwing: SSEMalformedResponseError())
        }
    }
}

private func readFirstSSEEvent(url: URL) async throws -> (HTTPURLResponse, String, Data) {
    var mutableRequest = URLRequest(url: url)
    mutableRequest.timeoutInterval = 10
    let request = mutableRequest

    let collector = SSEDataCollector()
    let (response, data) = try await withAsyncTestTimeout(
        operation: "SSE session-ready event"
    ) {
        try await collector.start(request: request)
    }

    let text = String(data: data, encoding: .utf8) ?? ""
    let lines = text.components(separatedBy: CharacterSet.newlines)

    var eventName = "message"
    for line in lines {
        if line.hasPrefix(":") || line.isEmpty {
            continue
        }
        if line.hasPrefix("event: ") {
            eventName = String(line.dropFirst("event: ".count)).trimmingCharacters(in: .whitespaces)
            continue
        }
        if line.hasPrefix("data: ") {
            let payload = String(line.dropFirst("data: ".count))
            return (response, eventName, Data(payload.utf8))
        }
    }

    throw SSEMalformedResponseError()
}

@Test
func sseStreamEndpointOverHTTPServerReturnsSessionReadyEvent() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config)
    let router = CoreRouter(service: service)
    let server = CoreHTTPServer(
        host: "127.0.0.1",
        port: 0,
        router: router,
        logger: Logger(label: "sloppy.core.httpserver.tests")
    )
    try server.start()
    defer { try? server.shutdown() }

    guard let boundPort = server.boundPort else {
        throw SSEMalformedResponseError()
    }

    _ = try await service.createAgent(
        AgentCreateRequest(
            id: "agent-http-stream",
            displayName: "Agent HTTP Stream",
            role: "SSE regression"
        )
    )
    let session = try await service.createAgentSession(
        agentID: "agent-http-stream",
        request: AgentSessionCreateRequest(title: "HTTP SSE Session")
    )

    let url = try #require(
        URL(string: "http://127.0.0.1:\(boundPort)/v1/agents/agent-http-stream/sessions/\(session.id)/stream")
    )

    let (httpResponse, eventName, payload) = try await readFirstSSEEvent(url: url)

    #expect(httpResponse.statusCode == 200)
    #expect((httpResponse.value(forHTTPHeaderField: "content-type") ?? "").contains("text/event-stream"))
    #expect(eventName == AgentSessionStreamUpdateKind.sessionReady.rawValue)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let update = try decoder.decode(AgentSessionStreamUpdate.self, from: payload)
    #expect(update.kind == .sessionReady)
    #expect(update.summary?.id == session.id)
}

// Linux Foundation uses libcurl for URLSession; WebSocket tasks are not supported there
// (NSURLErrorDomain -1002 "WebSockets not supported by libcurl").
#if !os(Linux)
@Test
func nodeMeshWebSocketRelaysTargetedEnvelopeBetweenConnectedNodes() async throws {
    let config = CoreConfig.test
    let laptopIdentity = NodeIdentityGenerator.makeIdentity(name: "Laptop", roles: ["client"], capabilities: ["git"])
    let workerIdentity = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["run_agent"])
    let store = NodeMeshStore(stateURL: config.resolvedNodeMeshStateURL())
    try store.registerNode(laptopIdentity, status: .offline)
    try store.registerNode(workerIdentity, status: .offline)
    let service = CoreService(config: config)
    let router = CoreRouter(service: service)
    let server = CoreHTTPServer(
        host: "127.0.0.1",
        port: 0,
        router: router,
        logger: Logger(label: "sloppy.node.mesh.httpserver.tests")
    )
    try server.start()
    defer { try? server.shutdown() }

    let port = try #require(server.boundPort)
    let wsURL = try #require(URL(string: "ws://127.0.0.1:\(port)/v1/node/mesh/ws"))
    let laptopSocket = URLSession.shared.webSocketTask(with: wsURL)
    let workerSocket = URLSession.shared.webSocketTask(with: wsURL)
    laptopSocket.resume()
    workerSocket.resume()
    defer {
        laptopSocket.cancel(with: .normalClosure, reason: nil)
        workerSocket.cancel(with: .normalClosure, reason: nil)
    }

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    try await authenticateMeshSocket(identity: laptopIdentity, encoder: encoder, decoder: decoder, over: laptopSocket)
    try await authenticateMeshSocket(identity: workerIdentity, encoder: encoder, decoder: decoder, over: workerSocket)

    try await sendMeshEnvelope(
        MeshEnvelope(
            type: .rpcRequest,
            from: laptopIdentity.nodeId,
            to: workerIdentity.nodeId,
            payload: .object([
                "method": .string("node.ping"),
                "params": .object([:]),
            ])
        ),
        encoder: encoder,
        over: laptopSocket
    )

    let message = try await receiveMeshWebSocketMessage(over: workerSocket, operation: "mesh routed rpc request")
    let payload = try #require(messagePayload(message))
    let envelope = try decoder.decode(MeshEnvelope.self, from: Data(payload.utf8))
    #expect(envelope.type == .rpcRequest)
    #expect(envelope.from == laptopIdentity.nodeId)
    #expect(envelope.to == workerIdentity.nodeId)
    #expect(envelope.payload.asObject?["method"] == .string("node.ping"))
}

@Test
func nodeMeshWebSocketRoutePersistsStateToConfiguredStore() async throws {
    var config = CoreConfig.test
    config.nodeMeshStatePath = "mesh/relay-state.json"
    let identity = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["run_agent"])
    let store = NodeMeshStore(stateURL: config.resolvedNodeMeshStateURL())
    try store.registerNode(identity, status: .offline)
    let service = CoreService(config: config)
    let router = CoreRouter(service: service)
    let server = CoreHTTPServer(
        host: "127.0.0.1",
        port: 0,
        router: router,
        logger: Logger(label: "sloppy.node.mesh.httpserver.persistence.tests")
    )
    try server.start()
    defer { try? server.shutdown() }

    let port = try #require(server.boundPort)
    let wsURL = try #require(URL(string: "ws://127.0.0.1:\(port)/v1/node/mesh/ws"))
    let socket = URLSession.shared.webSocketTask(with: wsURL)
    socket.resume()
    defer {
        socket.cancel(with: .normalClosure, reason: nil)
    }

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    try await authenticateMeshSocket(identity: identity, encoder: encoder, decoder: decoder, over: socket)

    try await waitUntil("configured mesh state persisted online") {
        (try? store.load().nodes.first(where: { $0.id == identity.nodeId })?.status) == .online
    }

    socket.cancel(with: .normalClosure, reason: nil)
    try await waitUntil("configured mesh state persisted offline") {
        (try? store.load().nodes.first(where: { $0.id == identity.nodeId })?.status) == .offline
    }
}

@Test
func nodeMeshRelayTracksHeartbeatAndMarksOfflineOnDisconnect() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-relay-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("mesh.json")
    let store = NodeMeshStore(stateURL: stateURL)
    let identity = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["run_agent"])
    try store.registerNode(identity, status: .offline)
    let relay = NodeMeshRelay(store: store, logger: Logger(label: "sloppy.node.mesh.relay.tests"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var continuation: AsyncStream<String>.Continuation!
    let sentMessages = WebSocketSentMessageRecorder()
    let stream = AsyncStream<String> { next in
        continuation = next
    }
    let connection = WebSocketConnectionContext(
        sendText: { text in
            await sentMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { stream }
    )

    let relayTask = Task {
        await relay.attach(connection: connection, remoteAddress: "127.0.0.1")
    }

    try await authenticateRelayConnection(
        identity: identity,
        continuation: continuation,
        sentMessages: sentMessages,
        encoder: encoder,
        decoder: decoder
    )
    try await waitUntil("node_worker registered online") {
        await relay.nodeRecord(id: identity.nodeId)?.status == .online
    }
    let firstSeenAt = try #require(await relay.nodeRecord(id: identity.nodeId)?.lastSeenAt)

    try await Task.sleep(nanoseconds: 5_000_000)
    continuation.yield(try encodedMeshEnvelope(
        MeshEnvelope(type: .nodeHeartbeat, from: identity.nodeId),
        encoder: encoder
    ))
    try await waitUntil("node_worker heartbeat advanced") {
        guard let node = await relay.nodeRecord(id: identity.nodeId) else {
            return false
        }
        return node.status == .online && node.lastSeenAt > firstSeenAt
    }

    continuation.finish()
    await relayTask.value
    let offline = try #require(await relay.nodeRecord(id: identity.nodeId))
    #expect(offline.status == .offline)
    #expect(await relay.activeNodeIds().isEmpty)
}

@Test
func nodeMeshRelayPersistsHelloHeartbeatRouteAndOffline() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-relay-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("mesh.json")
    let store = NodeMeshStore(stateURL: stateURL)
    let identity = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["run_agent"])
    try store.registerNode(identity, status: .offline)
    let relay = NodeMeshRelay(
        store: store,
        logger: Logger(label: "sloppy.node.mesh.relay.persistence.tests")
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var continuation: AsyncStream<String>.Continuation!
    let sentMessages = WebSocketSentMessageRecorder()
    let stream = AsyncStream<String> { next in
        continuation = next
    }
    let connection = WebSocketConnectionContext(
        sendText: { text in
            await sentMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { stream }
    )

    let relayTask = Task {
        await relay.attach(connection: connection, remoteAddress: "127.0.0.1")
    }

    try await authenticateRelayConnection(
        identity: identity,
        continuation: continuation,
        sentMessages: sentMessages,
        encoder: encoder,
        decoder: decoder
    )
    try await waitUntil("node_worker persisted online") {
        (try? store.load().nodes.first(where: { $0.id == identity.nodeId })?.status) == .online
    }
    try await Task.sleep(nanoseconds: 1_100_000_000)
    continuation.yield(try encodedMeshEnvelope(
        MeshEnvelope(type: .nodeHeartbeat, from: identity.nodeId),
        encoder: encoder
    ))
    try await waitUntil("node_worker heartbeat persisted") {
        guard let state = try? store.load(),
              let node = state.nodes.first(where: { $0.id == identity.nodeId }) else {
            return false
        }
        return node.status == .online && state.auditLog.contains { $0.action == "node.heartbeat" && $0.actor == identity.nodeId }
    }

    continuation.yield(try encodedMeshEnvelope(
        MeshEnvelope(type: .rpcRequest, from: identity.nodeId, to: identity.nodeId),
        encoder: encoder
    ))
    try await waitUntil("routed envelope audited") {
        (try? store.load().auditLog.last?.action) == "rpc.request"
    }

    continuation.finish()
    await relayTask.value
    let offline = try #require(try store.load().nodes.first(where: { $0.id == identity.nodeId }))
    #expect(offline.status == .offline)
}

@Test
func nodeMeshRelayAuthenticatesProjectedNodeAnnouncement() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-relay-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("mesh.json")
    let store = NodeMeshStore(stateURL: stateURL)
    let identity = NodeIdentityGenerator.makeIdentity(name: "Projected Worker", roles: ["worker"], capabilities: ["run_agent"])
    let announcement = try signedRelayEvent(.nodeAnnounced, actor: identity, projectId: nil, logicalTime: 1, payload: [
        "name": .string(identity.name),
        "roles": .array(identity.roles.map(JSONValue.string)),
        "capabilities": .array(identity.capabilities.map(JSONValue.string)),
        "status": .string(MeshNodeStatus.offline.rawValue),
    ])
    try store.save(MeshState(events: [announcement]))
    let relay = NodeMeshRelay(store: store, logger: Logger(label: "sloppy.node.mesh.relay.projected-auth.tests"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var continuation: AsyncStream<String>.Continuation!
    let sentMessages = WebSocketSentMessageRecorder()
    let stream = AsyncStream<String> { next in
        continuation = next
    }
    let connection = WebSocketConnectionContext(
        sendText: { text in
            await sentMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { stream }
    )

    let relayTask = Task {
        await relay.attach(connection: connection, remoteAddress: "127.0.0.1")
    }
    try await authenticateRelayConnection(
        identity: identity,
        continuation: continuation,
        sentMessages: sentMessages,
        encoder: encoder,
        decoder: decoder
    )

    try await waitUntil("projected node authenticated") {
        await relay.nodeRecord(id: identity.nodeId)?.status == .online
    }
    #expect(await relay.nodeRecord(id: identity.nodeId)?.publicKey == identity.publicKey)

    continuation.finish()
    await relayTask.value
}

@Test
func nodeMeshRelayPreservesAuthenticatedPublicKeyOnHello() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-relay-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("mesh.json")
    let store = NodeMeshStore(stateURL: stateURL)
    let identity = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["run_agent"])
    let impostor = NodeIdentityGenerator.makeIdentity(name: "Impostor", roles: ["worker"], capabilities: ["run_agent"])
    try store.registerNode(identity, status: .offline)
    let relay = NodeMeshRelay(store: store, logger: Logger(label: "sloppy.node.mesh.relay.hello-key.tests"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var continuation: AsyncStream<String>.Continuation!
    let sentMessages = WebSocketSentMessageRecorder()
    let stream = AsyncStream<String> { next in
        continuation = next
    }
    let connection = WebSocketConnectionContext(
        sendText: { text in
            await sentMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { stream }
    )

    let relayTask = Task {
        await relay.attach(connection: connection, remoteAddress: "127.0.0.1")
    }
    let challenge = try await receiveRelayAuthChallenge(sentMessages: sentMessages, decoder: decoder)
    let response = try #require(try NodeMeshClient.makeAuthResponseEnvelope(identity: identity, challengeEnvelope: challenge))
    continuation.yield(try encodedMeshEnvelope(response, encoder: encoder))
    continuation.yield(try encodedMeshEnvelope(
        MeshEnvelope(
            type: .nodeHello,
            from: identity.nodeId,
            payload: .object([
                "name": .string(identity.name),
                "publicKey": .string(impostor.publicKey),
                "roles": .array(identity.roles.map(JSONValue.string)),
                "capabilities": .array(identity.capabilities.map(JSONValue.string)),
            ])
        ),
        encoder: encoder
    ))

    try await waitUntil("hello persisted authenticated key") {
        await relay.nodeRecord(id: identity.nodeId)?.publicKey == identity.publicKey &&
            (try? store.load().nodes.first(where: { $0.id == identity.nodeId })?.publicKey) == identity.publicKey
    }
    #expect(await relay.nodeRecord(id: identity.nodeId)?.publicKey == identity.publicKey)

    continuation.finish()
    await relayTask.value
}

@Test
func nodeMeshRelayReturnsStructuredErrorForMissingTarget() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-relay-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("mesh.json")
    let store = NodeMeshStore(stateURL: stateURL)
    let identity = NodeIdentityGenerator.makeIdentity(name: "Laptop", roles: ["client"], capabilities: ["git"])
    try store.registerNode(identity, status: .offline)
    let relay = NodeMeshRelay(store: store, logger: Logger(label: "sloppy.node.mesh.relay.error.tests"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var continuation: AsyncStream<String>.Continuation!
    let sentMessages = WebSocketSentMessageRecorder()
    let stream = AsyncStream<String> { next in
        continuation = next
    }
    let connection = WebSocketConnectionContext(
        sendText: { text in
            await sentMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { stream }
    )

    let relayTask = Task {
        await relay.attach(connection: connection, remoteAddress: "127.0.0.1")
    }

    try await authenticateRelayConnection(
        identity: identity,
        continuation: continuation,
        sentMessages: sentMessages,
        encoder: encoder,
        decoder: decoder
    )
    try await waitUntil("node_laptop registered online") {
        await relay.nodeRecord(id: identity.nodeId)?.status == .online
    }
    continuation.yield(try encodedMeshEnvelope(
        MeshEnvelope(
            id: "rpc_missing",
            type: .rpcRequest,
            from: identity.nodeId,
            to: "node_missing",
            payload: .object(["method": .string("node.ping")])
        ),
        encoder: encoder
    ))

    try await waitUntil("missing target error sent") {
        await sentMessages.count >= 2
    }
    let message = try #require(await sentMessages.last)
    let envelope = try decoder.decode(MeshEnvelope.self, from: Data(message.utf8))
    #expect(envelope.type == .rpcResponse)
    #expect(envelope.from == "relay")
    #expect(envelope.to == identity.nodeId)
    #expect(envelope.payload.asObject?["requestId"] == .string("rpc_missing"))
    #expect(envelope.payload.asObject?["ok"] == .bool(false))
    #expect(envelope.payload.asObject?["error"]?.asObject?["code"] == .string("node_unavailable"))
    #expect(envelope.payload.asObject?["error"]?.asObject?["target"] == .string("node_missing"))

    continuation.finish()
    await relayTask.value
}

@Test
func nodeMeshRelayDeliversLiveTaskDispatchAndAuditsDelivery() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-relay-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("mesh.json")
    let store = NodeMeshStore(stateURL: stateURL)
    let laptopIdentity = NodeIdentityGenerator.makeIdentity(name: "Laptop", roles: ["client"], capabilities: ["git"])
    let workerIdentity = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["run_agent"])
    try store.registerNode(laptopIdentity, status: .offline)
    try store.registerNode(workerIdentity, status: .offline)
    let project = try store.createSharedProject(name: "Mesh Project", repoUrl: "git@example.com:mesh.git")
    _ = try store.attachMember(
        projectIdOrName: project.id,
        nodeId: laptopIdentity.nodeId,
        localRepoPath: "/Users/laptop/mesh",
        role: "controller",
        permissions: [MeshPermission.taskCreate.rawValue, MeshPermission.taskAssign.rawValue]
    )
    _ = try store.attachMember(
        projectIdOrName: project.id,
        nodeId: workerIdentity.nodeId,
        localRepoPath: "/Users/worker/mesh",
        role: "worker",
        permissions: MeshPermission.workerDefaults.rawValues
    )
    let task = try store.dispatchTask(
        projectIdOrName: project.id,
        title: "Implement feature",
        assignedNodeId: workerIdentity.nodeId,
        actor: laptopIdentity.nodeId
    )
    let relay = NodeMeshRelay(store: store, logger: Logger(label: "sloppy.node.mesh.relay.dispatch.tests"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    var laptopContinuation: AsyncStream<String>.Continuation!
    let laptopMessages = WebSocketSentMessageRecorder()
    let laptopStream = AsyncStream<String> { next in
        laptopContinuation = next
    }
    let laptopConnection = WebSocketConnectionContext(
        sendText: { text in
            await laptopMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { laptopStream }
    )
    var workerContinuation: AsyncStream<String>.Continuation!
    let workerMessages = WebSocketSentMessageRecorder()
    let workerStream = AsyncStream<String> { next in
        workerContinuation = next
    }
    let workerConnection = WebSocketConnectionContext(
        sendText: { text in
            await workerMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { workerStream }
    )

    let laptopTask = Task {
        await relay.attach(connection: laptopConnection, remoteAddress: "127.0.0.1")
    }
    let workerTask = Task {
        await relay.attach(connection: workerConnection, remoteAddress: "127.0.0.1")
    }

    try await authenticateRelayConnection(
        identity: laptopIdentity,
        continuation: laptopContinuation,
        sentMessages: laptopMessages,
        encoder: encoder,
        decoder: decoder
    )
    try await authenticateRelayConnection(
        identity: workerIdentity,
        continuation: workerContinuation,
        sentMessages: workerMessages,
        encoder: encoder,
        decoder: decoder
    )
    try await waitUntil("mesh nodes authenticated for dispatch test") {
        await relay.activeNodeIds().sorted() == [laptopIdentity.nodeId, workerIdentity.nodeId].sorted()
    }
    let messagesBeforeLiveDispatch = await workerMessages.count

    laptopContinuation.yield(try encodedMeshEnvelope(
        MeshEnvelope(
            id: "dispatch_live",
            type: .taskDispatch,
            from: laptopIdentity.nodeId,
            to: workerIdentity.nodeId,
            scope: project.eventScope,
            payload: .object([
                "taskId": .string(task.id),
                "projectId": .string(project.id),
                "title": .string(task.title),
            ])
        ),
        encoder: encoder
    ))

    try await waitUntil("worker received live task dispatch") {
        await workerMessages.count > messagesBeforeLiveDispatch
    }
    let message = try #require(await workerMessages.last)
    let envelope = try decoder.decode(MeshEnvelope.self, from: Data(message.utf8))
    #expect(envelope.type == .taskDispatch)
    #expect(envelope.to == workerIdentity.nodeId)
    #expect(envelope.payload.asObject?["taskId"] == .string(task.id))
    try await waitUntil("task dispatch delivery audited") {
        (try? store.load().auditLog.contains {
            $0.action == "task.dispatch.delivery" &&
                $0.task == task.id &&
                $0.target == workerIdentity.nodeId &&
                $0.allowed
        }) == true
    }

    laptopContinuation.finish()
    workerContinuation.finish()
    await laptopTask.value
    await workerTask.value
}

@Test
func nodeMeshRelayReplaysLocalTaskDispatchFromAPIStore() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-relay-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("mesh.json")
    let store = NodeMeshStore(stateURL: stateURL)
    let workerIdentity = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["run_agent"])
    try store.registerNode(workerIdentity, status: .offline)
    let project = try store.createSharedProject(name: "Mesh Project", repoUrl: "git@example.com:mesh.git")
    _ = try store.attachMember(
        projectIdOrName: project.id,
        nodeId: workerIdentity.nodeId,
        localRepoPath: "/Users/worker/mesh",
        role: "worker",
        permissions: MeshPermission.workerDefaults.rawValues
    )
    let task = try store.dispatchTask(
        projectIdOrName: project.id,
        title: "Implement feature",
        assignedNodeId: workerIdentity.nodeId
    )
    #expect(try store.load().envelopes.contains { envelope in
        envelope.type == .taskDispatch &&
            envelope.from == "local" &&
            envelope.to == workerIdentity.nodeId
    })

    let relay = NodeMeshRelay(store: store, logger: Logger(label: "sloppy.node.mesh.relay.local-dispatch.tests"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var continuation: AsyncStream<String>.Continuation!
    let sentMessages = WebSocketSentMessageRecorder()
    let stream = AsyncStream<String> { next in
        continuation = next
    }
    let connection = WebSocketConnectionContext(
        sendText: { text in
            await sentMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { stream }
    )

    let relayTask = Task {
        await relay.attach(connection: connection, remoteAddress: "127.0.0.1")
    }
    try await authenticateRelayConnection(
        identity: workerIdentity,
        continuation: continuation,
        sentMessages: sentMessages,
        encoder: encoder,
        decoder: decoder
    )

    try await waitUntil("worker received local pending task dispatch") {
        let messages = await sentMessages.all
        return messages.contains { message in
            guard let envelope = try? decoder.decode(MeshEnvelope.self, from: Data(message.utf8)) else {
                return false
            }
            return envelope.type == .taskDispatch &&
                envelope.from == "local" &&
                envelope.payload.asObject?["taskId"] == .string(task.id)
        }
    }

    continuation.finish()
    await relayTask.value
}

@Test
func nodeMeshRelayReplaysLocalProjectSyncFromAPIStore() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-relay-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("mesh.json")
    let store = NodeMeshStore(stateURL: stateURL)
    let workerIdentity = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["run_agent"])
    try store.registerNode(workerIdentity, status: .offline)
    let project = try store.createSharedProject(name: "Mesh Project", repoUrl: "git@example.com:mesh.git")
    _ = try store.attachMember(
        projectIdOrName: project.id,
        nodeId: workerIdentity.nodeId,
        localRepoPath: "/Users/worker/mesh",
        role: "worker",
        permissions: MeshPermission.workerDefaults.rawValues
    )
    #expect(try store.load().envelopes.contains { envelope in
        envelope.type == .projectSyncEvent &&
            envelope.from == "local" &&
            envelope.to == workerIdentity.nodeId
    })

    let relay = NodeMeshRelay(store: store, logger: Logger(label: "sloppy.node.mesh.relay.local-project-sync.tests"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var continuation: AsyncStream<String>.Continuation!
    let sentMessages = WebSocketSentMessageRecorder()
    let stream = AsyncStream<String> { next in
        continuation = next
    }
    let connection = WebSocketConnectionContext(
        sendText: { text in
            await sentMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { stream }
    )

    let relayTask = Task {
        await relay.attach(connection: connection, remoteAddress: "127.0.0.1")
    }
    try await authenticateRelayConnection(
        identity: workerIdentity,
        continuation: continuation,
        sentMessages: sentMessages,
        encoder: encoder,
        decoder: decoder
    )

    try await waitUntil("worker received local pending project sync") {
        let messages = await sentMessages.all
        return messages.contains { message in
            guard let envelope = try? decoder.decode(MeshEnvelope.self, from: Data(message.utf8)) else {
                return false
            }
            return envelope.type == .projectSyncEvent &&
                envelope.from == "local" &&
                envelope.to == workerIdentity.nodeId &&
                envelope.payload.asObject?["projectId"] == .string(project.id)
        }
    }

    continuation.finish()
    await relayTask.value
}

@Test
func nodeMeshRelayRejectsUnauthorizedTaskDispatch() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-relay-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("mesh.json")
    let store = NodeMeshStore(stateURL: stateURL)
    let laptopIdentity = NodeIdentityGenerator.makeIdentity(name: "Laptop", roles: ["client"], capabilities: ["git"])
    let workerIdentity = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["run_agent"])
    let rogueIdentity = NodeIdentityGenerator.makeIdentity(name: "Rogue", roles: ["worker"], capabilities: ["run_agent"])
    try store.registerNode(laptopIdentity, status: .offline)
    try store.registerNode(workerIdentity, status: .offline)
    try store.registerNode(rogueIdentity, status: .offline)
    let project = try store.createSharedProject(name: "Mesh Project", repoUrl: "git@example.com:mesh.git")
    _ = try store.attachMember(
        projectIdOrName: project.id,
        nodeId: workerIdentity.nodeId,
        localRepoPath: "/Users/worker/mesh",
        role: "worker",
        permissions: MeshPermission.workerDefaults.rawValues
    )
    let task = try store.dispatchTask(
        projectIdOrName: project.id,
        title: "Implement feature",
        assignedNodeId: workerIdentity.nodeId,
        actor: laptopIdentity.nodeId
    )
    let relay = NodeMeshRelay(store: store, logger: Logger(label: "sloppy.node.mesh.relay.dispatch.auth.tests"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    var rogueContinuation: AsyncStream<String>.Continuation!
    let rogueMessages = WebSocketSentMessageRecorder()
    let rogueStream = AsyncStream<String> { next in
        rogueContinuation = next
    }
    let rogueConnection = WebSocketConnectionContext(
        sendText: { text in
            await rogueMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { rogueStream }
    )
    var workerContinuation: AsyncStream<String>.Continuation!
    let workerMessages = WebSocketSentMessageRecorder()
    let workerStream = AsyncStream<String> { next in
        workerContinuation = next
    }
    let workerConnection = WebSocketConnectionContext(
        sendText: { text in
            await workerMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { workerStream }
    )

    let rogueTask = Task {
        await relay.attach(connection: rogueConnection, remoteAddress: "127.0.0.1")
    }
    let workerTask = Task {
        await relay.attach(connection: workerConnection, remoteAddress: "127.0.0.1")
    }
    try await authenticateRelayConnection(
        identity: rogueIdentity,
        continuation: rogueContinuation,
        sentMessages: rogueMessages,
        encoder: encoder,
        decoder: decoder
    )
    try await authenticateRelayConnection(
        identity: workerIdentity,
        continuation: workerContinuation,
        sentMessages: workerMessages,
        encoder: encoder,
        decoder: decoder
    )

    rogueContinuation.yield(try encodedMeshEnvelope(
        MeshEnvelope(
            id: "dispatch_unauthorized",
            type: .taskDispatch,
            from: rogueIdentity.nodeId,
            to: workerIdentity.nodeId,
            scope: project.eventScope,
            payload: .object([
                "taskId": .string(task.id),
                "projectId": .string(project.id),
                "title": .string(task.title),
            ])
        ),
        encoder: encoder
    ))

    try await waitUntil("forbidden dispatch response sent") {
        let messages = await rogueMessages.all
        return messages.contains { message in
            guard let envelope = try? decoder.decode(MeshEnvelope.self, from: Data(message.utf8)) else {
                return false
            }
            return envelope.type == .rpcResponse &&
                envelope.payload.asObject?["requestId"] == .string("dispatch_unauthorized")
        }
    }
    #expect(await workerMessages.all.contains { message in
        guard let envelope = try? decoder.decode(MeshEnvelope.self, from: Data(message.utf8)) else {
            return false
        }
        return envelope.type == .taskDispatch
    } == false)

    rogueContinuation.finish()
    workerContinuation.finish()
    await rogueTask.value
    await workerTask.value
}

@Test
func nodeMeshRelayAuditsOfflineTaskDispatchDeliveryFailure() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-relay-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("mesh.json")
    let store = NodeMeshStore(stateURL: stateURL)
    let laptopIdentity = NodeIdentityGenerator.makeIdentity(name: "Laptop", roles: ["client"], capabilities: ["git"])
    let workerIdentity = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["run_agent"])
    try store.registerNode(laptopIdentity, status: .offline)
    try store.registerNode(workerIdentity, status: .offline)
    let project = try store.createSharedProject(name: "Mesh Project", repoUrl: "git@example.com:mesh.git")
    _ = try store.attachMember(
        projectIdOrName: project.id,
        nodeId: laptopIdentity.nodeId,
        localRepoPath: "/Users/laptop/mesh",
        role: "controller",
        permissions: [MeshPermission.taskCreate.rawValue, MeshPermission.taskAssign.rawValue]
    )
    _ = try store.attachMember(
        projectIdOrName: project.id,
        nodeId: workerIdentity.nodeId,
        localRepoPath: "/Users/worker/mesh",
        role: "worker",
        permissions: MeshPermission.workerDefaults.rawValues
    )
    let task = try store.dispatchTask(
        projectIdOrName: project.id,
        title: "Implement feature",
        assignedNodeId: workerIdentity.nodeId,
        actor: laptopIdentity.nodeId
    )
    let relay = NodeMeshRelay(store: store, logger: Logger(label: "sloppy.node.mesh.relay.dispatch.offline.tests"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var continuation: AsyncStream<String>.Continuation!
    let sentMessages = WebSocketSentMessageRecorder()
    let stream = AsyncStream<String> { next in
        continuation = next
    }
    let connection = WebSocketConnectionContext(
        sendText: { text in
            await sentMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { stream }
    )

    let relayTask = Task {
        await relay.attach(connection: connection, remoteAddress: "127.0.0.1")
    }

    try await authenticateRelayConnection(
        identity: laptopIdentity,
        continuation: continuation,
        sentMessages: sentMessages,
        encoder: encoder,
        decoder: decoder
    )
    continuation.yield(try encodedMeshEnvelope(
        MeshEnvelope(
            id: "dispatch_offline",
            type: .taskDispatch,
            from: laptopIdentity.nodeId,
            to: workerIdentity.nodeId,
            scope: project.eventScope,
            payload: .object([
                "taskId": .string(task.id),
                "projectId": .string(project.id),
                "title": .string(task.title),
            ])
        ),
        encoder: encoder
    ))

    try await waitUntil("offline dispatch error sent") {
        let messages = await sentMessages.all
        return messages.contains { message in
            guard let envelope = try? decoder.decode(MeshEnvelope.self, from: Data(message.utf8)) else {
                return false
            }
            return envelope.type == .rpcResponse &&
                envelope.payload.asObject?["requestId"] == .string("dispatch_offline")
        }
    }
    let message = try #require(await sentMessages.all.first { message in
        guard let envelope = try? decoder.decode(MeshEnvelope.self, from: Data(message.utf8)) else {
            return false
        }
        return envelope.type == .rpcResponse &&
            envelope.payload.asObject?["requestId"] == .string("dispatch_offline")
    })
    let envelope = try decoder.decode(MeshEnvelope.self, from: Data(message.utf8))
    #expect(envelope.type == .rpcResponse)
    #expect(envelope.payload.asObject?["error"]?.asObject?["code"] == .string("node_unavailable"))
    try await waitUntil("offline task dispatch delivery audited") {
        (try? store.load().auditLog.contains {
            $0.action == "task.dispatch.delivery" &&
                $0.task == task.id &&
                $0.target == workerIdentity.nodeId &&
                !$0.allowed
        }) == true
    }

    continuation.finish()
    await relayTask.value
}

@Test
func nodeMeshRelayRejectsUnauthorizedTaskStatusUpdate() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-relay-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("mesh.json")
    let store = NodeMeshStore(stateURL: stateURL)
    let laptopIdentity = NodeIdentityGenerator.makeIdentity(name: "Laptop", roles: ["client"], capabilities: ["git"])
    let workerIdentity = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["run_agent"])
    let rogueIdentity = NodeIdentityGenerator.makeIdentity(name: "Rogue", roles: ["worker"], capabilities: ["run_agent"])
    try store.registerNode(laptopIdentity, status: .offline)
    try store.registerNode(workerIdentity, status: .offline)
    try store.registerNode(rogueIdentity, status: .offline)
    let project = try store.createSharedProject(name: "Mesh Project", repoUrl: "git@example.com:mesh.git")
    _ = try store.attachMember(
        projectIdOrName: project.id,
        nodeId: workerIdentity.nodeId,
        localRepoPath: "/Users/worker/mesh",
        role: "worker",
        permissions: MeshPermission.workerDefaults.rawValues
    )
    _ = try store.attachMember(
        projectIdOrName: project.id,
        nodeId: rogueIdentity.nodeId,
        localRepoPath: "/Users/rogue/mesh",
        role: "worker",
        permissions: MeshPermission.workerDefaults.rawValues
    )
    let task = try store.dispatchTask(
        projectIdOrName: project.id,
        title: "Implement feature",
        assignedNodeId: workerIdentity.nodeId,
        actor: laptopIdentity.nodeId
    )
    let relay = NodeMeshRelay(store: store, logger: Logger(label: "sloppy.node.mesh.relay.status.auth.tests"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var continuation: AsyncStream<String>.Continuation!
    let sentMessages = WebSocketSentMessageRecorder()
    let stream = AsyncStream<String> { next in
        continuation = next
    }
    let connection = WebSocketConnectionContext(
        sendText: { text in
            await sentMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { stream }
    )

    let relayTask = Task {
        await relay.attach(connection: connection, remoteAddress: "127.0.0.1")
    }
    try await authenticateRelayConnection(
        identity: rogueIdentity,
        continuation: continuation,
        sentMessages: sentMessages,
        encoder: encoder,
        decoder: decoder
    )
    continuation.yield(try encodedMeshEnvelope(
        MeshEnvelope(
            id: "status_unauthorized",
            type: .taskStatusUpdate,
            from: rogueIdentity.nodeId,
            scope: project.eventScope,
            payload: .object([
                "taskId": .string(task.id),
                "projectId": .string(project.id),
                "status": .string(MeshTaskStatus.readyForReview.rawValue),
            ])
        ),
        encoder: encoder
    ))

    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(try store.load().tasks.first(where: { $0.id == task.id })?.status == .dispatched)

    continuation.finish()
    await relayTask.value
}

@Test
func nodeMeshRelayRejectsUnknownTaskStatusUpdateValue() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-relay-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("mesh.json")
    let store = NodeMeshStore(stateURL: stateURL)
    let workerIdentity = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["run_agent"])
    try store.registerNode(workerIdentity, status: .offline)
    let project = try store.createSharedProject(name: "Mesh Project", repoUrl: "git@example.com:mesh.git")
    _ = try store.attachMember(
        projectIdOrName: project.id,
        nodeId: workerIdentity.nodeId,
        localRepoPath: "/Users/worker/mesh",
        role: "worker",
        permissions: MeshPermission.workerDefaults.rawValues
    )
    let task = try store.dispatchTask(
        projectIdOrName: project.id,
        title: "Implement feature",
        assignedNodeId: workerIdentity.nodeId
    )
    let relay = NodeMeshRelay(store: store, logger: Logger(label: "sloppy.node.mesh.relay.status.invalid.tests"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var continuation: AsyncStream<String>.Continuation!
    let sentMessages = WebSocketSentMessageRecorder()
    let stream = AsyncStream<String> { next in
        continuation = next
    }
    let connection = WebSocketConnectionContext(
        sendText: { text in
            await sentMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { stream }
    )

    let relayTask = Task {
        await relay.attach(connection: connection, remoteAddress: "127.0.0.1")
    }
    try await authenticateRelayConnection(
        identity: workerIdentity,
        continuation: continuation,
        sentMessages: sentMessages,
        encoder: encoder,
        decoder: decoder
    )
    continuation.yield(try encodedMeshEnvelope(
        MeshEnvelope(
            id: "status_invalid",
            type: .taskStatusUpdate,
            from: workerIdentity.nodeId,
            scope: project.eventScope,
            payload: .object([
                "taskId": .string(task.id),
                "projectId": .string(project.id),
                "status": .string("done-ish"),
            ])
        ),
        encoder: encoder
    ))

    try await waitUntil("invalid status update response sent") {
        let messages = await sentMessages.all
        return messages.contains { message in
            guard let envelope = try? decoder.decode(MeshEnvelope.self, from: Data(message.utf8)) else {
                return false
            }
            return envelope.type == .rpcResponse &&
                envelope.payload.asObject?["requestId"] == .string("status_invalid") &&
                envelope.payload.asObject?["error"]?.asObject?["code"] == .string("forbidden")
        }
    }
    #expect(try store.load().tasks.first(where: { $0.id == task.id })?.status == .dispatched)

    continuation.finish()
    await relayTask.value
}

@Test
func nodeMeshRelayDoesNotDeliverUnauthorizedTaskStatusUpdate() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-relay-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("mesh.json")
    let store = NodeMeshStore(stateURL: stateURL)
    let laptopIdentity = NodeIdentityGenerator.makeIdentity(name: "Laptop", roles: ["client"], capabilities: ["git"])
    let workerIdentity = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["run_agent"])
    let rogueIdentity = NodeIdentityGenerator.makeIdentity(name: "Rogue", roles: ["worker"], capabilities: ["run_agent"])
    try store.registerNode(laptopIdentity, status: .offline)
    try store.registerNode(workerIdentity, status: .offline)
    try store.registerNode(rogueIdentity, status: .offline)
    let project = try store.createSharedProject(name: "Mesh Project", repoUrl: "git@example.com:mesh.git")
    _ = try store.attachMember(
        projectIdOrName: project.id,
        nodeId: workerIdentity.nodeId,
        localRepoPath: "/Users/worker/mesh",
        role: "worker",
        permissions: MeshPermission.workerDefaults.rawValues
    )
    _ = try store.attachMember(
        projectIdOrName: project.id,
        nodeId: rogueIdentity.nodeId,
        localRepoPath: "/Users/rogue/mesh",
        role: "worker",
        permissions: MeshPermission.workerDefaults.rawValues
    )
    let task = try store.dispatchTask(
        projectIdOrName: project.id,
        title: "Implement feature",
        assignedNodeId: workerIdentity.nodeId,
        actor: laptopIdentity.nodeId
    )
    let relay = NodeMeshRelay(store: store, logger: Logger(label: "sloppy.node.mesh.relay.status.delivery.tests"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    var rogueContinuation: AsyncStream<String>.Continuation!
    let rogueMessages = WebSocketSentMessageRecorder()
    let rogueStream = AsyncStream<String> { next in
        rogueContinuation = next
    }
    let rogueConnection = WebSocketConnectionContext(
        sendText: { text in
            await rogueMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { rogueStream }
    )
    var workerContinuation: AsyncStream<String>.Continuation!
    let workerMessages = WebSocketSentMessageRecorder()
    let workerStream = AsyncStream<String> { next in
        workerContinuation = next
    }
    let workerConnection = WebSocketConnectionContext(
        sendText: { text in
            await workerMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { workerStream }
    )

    let rogueTask = Task {
        await relay.attach(connection: rogueConnection, remoteAddress: "127.0.0.1")
    }
    let workerTask = Task {
        await relay.attach(connection: workerConnection, remoteAddress: "127.0.0.1")
    }
    try await authenticateRelayConnection(
        identity: rogueIdentity,
        continuation: rogueContinuation,
        sentMessages: rogueMessages,
        encoder: encoder,
        decoder: decoder
    )
    try await authenticateRelayConnection(
        identity: workerIdentity,
        continuation: workerContinuation,
        sentMessages: workerMessages,
        encoder: encoder,
        decoder: decoder
    )

    rogueContinuation.yield(try encodedMeshEnvelope(
        MeshEnvelope(
            id: "status_delivery_unauthorized",
            type: .taskStatusUpdate,
            from: rogueIdentity.nodeId,
            to: workerIdentity.nodeId,
            scope: project.eventScope,
            payload: .object([
                "taskId": .string(task.id),
                "projectId": .string(project.id),
                "status": .string(MeshTaskStatus.readyForReview.rawValue),
            ])
        ),
        encoder: encoder
    ))

    try await waitUntil("forbidden status response sent") {
        let messages = await rogueMessages.all
        return messages.contains { message in
            guard let envelope = try? decoder.decode(MeshEnvelope.self, from: Data(message.utf8)) else {
                return false
            }
            return envelope.type == .rpcResponse &&
                envelope.payload.asObject?["requestId"] == .string("status_delivery_unauthorized")
        }
    }
    #expect(await workerMessages.all.contains { message in
        guard let envelope = try? decoder.decode(MeshEnvelope.self, from: Data(message.utf8)) else {
            return false
        }
        return envelope.type == .taskStatusUpdate
    } == false)
    #expect(try store.load().tasks.first(where: { $0.id == task.id })?.status == .dispatched)

    rogueContinuation.finish()
    workerContinuation.finish()
    await rogueTask.value
    await workerTask.value
}

@Test
func nodeMeshRelayRejectsSpoofedEnvelopeFromAuthenticatedConnection() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-relay-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("mesh.json")
    let store = NodeMeshStore(stateURL: stateURL)
    let laptopIdentity = NodeIdentityGenerator.makeIdentity(name: "Laptop", roles: ["client"], capabilities: ["git"])
    let workerIdentity = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["run_agent"])
    let rogueIdentity = NodeIdentityGenerator.makeIdentity(name: "Rogue", roles: ["worker"], capabilities: ["run_agent"])
    try store.registerNode(laptopIdentity, status: .offline)
    try store.registerNode(workerIdentity, status: .offline)
    try store.registerNode(rogueIdentity, status: .offline)
    let project = try store.createSharedProject(name: "Mesh Project", repoUrl: "git@example.com:mesh.git")
    _ = try store.attachMember(
        projectIdOrName: project.id,
        nodeId: workerIdentity.nodeId,
        localRepoPath: "/Users/worker/mesh",
        role: "worker",
        permissions: MeshPermission.workerDefaults.rawValues
    )
    let task = try store.dispatchTask(
        projectIdOrName: project.id,
        title: "Implement feature",
        assignedNodeId: workerIdentity.nodeId,
        actor: laptopIdentity.nodeId
    )
    let relay = NodeMeshRelay(store: store, logger: Logger(label: "sloppy.node.mesh.relay.spoof.tests"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var continuation: AsyncStream<String>.Continuation!
    let sentMessages = WebSocketSentMessageRecorder()
    let stream = AsyncStream<String> { next in
        continuation = next
    }
    let connection = WebSocketConnectionContext(
        sendText: { text in
            await sentMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { stream }
    )

    let relayTask = Task {
        await relay.attach(connection: connection, remoteAddress: "127.0.0.1")
    }
    try await authenticateRelayConnection(
        identity: rogueIdentity,
        continuation: continuation,
        sentMessages: sentMessages,
        encoder: encoder,
        decoder: decoder
    )
    continuation.yield(try encodedMeshEnvelope(
        MeshEnvelope(
            id: "status_spoofed",
            type: .taskStatusUpdate,
            from: workerIdentity.nodeId,
            scope: project.eventScope,
            payload: .object([
                "taskId": .string(task.id),
                "projectId": .string(project.id),
                "status": .string(MeshTaskStatus.readyForReview.rawValue),
            ])
        ),
        encoder: encoder
    ))

    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(try store.load().tasks.first(where: { $0.id == task.id })?.status == .dispatched)

    continuation.finish()
    await relayTask.value
}

@Test
func nodeMeshRelayRejectsRPCWithoutPermission() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-relay-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("mesh.json")
    let store = NodeMeshStore(stateURL: stateURL)
    let laptopIdentity = NodeIdentityGenerator.makeIdentity(name: "Laptop", roles: ["client"], capabilities: ["git"])
    let workerIdentity = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["run_agent"])
    try store.registerNode(laptopIdentity, status: .offline)
    try store.registerNode(workerIdentity, status: .offline)
    let project = try store.createSharedProject(name: "Mesh Project", repoUrl: "git@example.com:mesh.git")
    _ = try store.attachMember(
        projectIdOrName: project.id,
        nodeId: laptopIdentity.nodeId,
        localRepoPath: "/Users/laptop/mesh",
        role: "controller",
        permissions: [MeshPermission.projectRead.rawValue]
    )
    _ = try store.attachMember(
        projectIdOrName: project.id,
        nodeId: workerIdentity.nodeId,
        localRepoPath: "/Users/worker/mesh",
        role: "worker",
        permissions: MeshPermission.workerDefaults.rawValues
    )

    let relay = NodeMeshRelay(store: store, logger: Logger(label: "sloppy.node.mesh.relay.acl.tests"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    var laptopContinuation: AsyncStream<String>.Continuation!
    let laptopMessages = WebSocketSentMessageRecorder()
    let laptopStream = AsyncStream<String> { next in
        laptopContinuation = next
    }
    let laptopConnection = WebSocketConnectionContext(
        sendText: { text in
            await laptopMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { laptopStream }
    )
    var workerContinuation: AsyncStream<String>.Continuation!
    let workerMessages = WebSocketSentMessageRecorder()
    let workerStream = AsyncStream<String> { next in
        workerContinuation = next
    }
    let workerConnection = WebSocketConnectionContext(
        sendText: { text in
            await workerMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { workerStream }
    )

    let laptopTask = Task {
        await relay.attach(connection: laptopConnection, remoteAddress: "127.0.0.1")
    }
    let workerTask = Task {
        await relay.attach(connection: workerConnection, remoteAddress: "127.0.0.1")
    }

    try await authenticateRelayConnection(
        identity: laptopIdentity,
        continuation: laptopContinuation,
        sentMessages: laptopMessages,
        encoder: encoder,
        decoder: decoder
    )
    try await authenticateRelayConnection(
        identity: workerIdentity,
        continuation: workerContinuation,
        sentMessages: workerMessages,
        encoder: encoder,
        decoder: decoder
    )
    try await waitUntil("mesh nodes authenticated for acl test") {
        await relay.activeNodeIds().sorted() == [laptopIdentity.nodeId, workerIdentity.nodeId].sorted()
    }

    laptopContinuation.yield(try encodedMeshEnvelope(
        MeshEnvelope(
            id: "rpc_forbidden",
            type: .rpcRequest,
            from: laptopIdentity.nodeId,
            to: workerIdentity.nodeId,
            scope: project.eventScope,
            payload: .object(["method": .string("node.status")])
        ),
        encoder: encoder
    ))

    try await waitUntil("forbidden rpc response sent") {
        let messages = await laptopMessages.all
        return messages.contains { message in
            guard let envelope = try? decoder.decode(MeshEnvelope.self, from: Data(message.utf8)) else {
                return false
            }
            return envelope.type == .rpcResponse &&
                envelope.payload.asObject?["requestId"] == .string("rpc_forbidden")
        }
    }
    let message = try #require(await laptopMessages.all.first { message in
        guard let envelope = try? decoder.decode(MeshEnvelope.self, from: Data(message.utf8)) else {
            return false
        }
        return envelope.type == .rpcResponse &&
            envelope.payload.asObject?["requestId"] == .string("rpc_forbidden")
    })
    let envelope = try decoder.decode(MeshEnvelope.self, from: Data(message.utf8))
    #expect(envelope.type == .rpcResponse)
    #expect(envelope.from == "relay")
    #expect(envelope.to == laptopIdentity.nodeId)
    #expect(envelope.payload.asObject?["requestId"] == .string("rpc_forbidden"))
    #expect(envelope.payload.asObject?["ok"] == .bool(false))
    #expect(envelope.payload.asObject?["error"]?.asObject?["code"] == .string("forbidden"))
    #expect(await workerMessages.all.contains { message in
        guard let envelope = try? decoder.decode(MeshEnvelope.self, from: Data(message.utf8)) else {
            return false
        }
        return envelope.type == .rpcRequest
    } == false)
    let audit = try #require(try store.load().auditLog.last)
    #expect(audit.action == "rpc.request")
    #expect(audit.allowed == false)
    #expect(audit.message == "missing node.rpc permission")

    laptopContinuation.finish()
    workerContinuation.finish()
    await laptopTask.value
    await workerTask.value
}

@Test
func nodeMeshRelayUsesProjectedMembershipForRPC() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-relay-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("mesh.json")
    let store = NodeMeshStore(stateURL: stateURL)
    let laptopIdentity = NodeIdentityGenerator.makeIdentity(name: "Laptop", roles: ["client"], capabilities: ["git"])
    let workerIdentity = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["run_agent"])
    let projectId = "sp_projected_acl"
    let staleProject = SharedProjectRecord(
        id: projectId,
        name: "Projected ACL",
        repoUrl: "git@example.com:projected-acl.git",
        members: [
            SharedProjectMember(
                nodeId: laptopIdentity.nodeId,
                localRepoPath: "/Users/laptop/mesh",
                role: "controller",
                permissions: [MeshPermission.projectWrite.rawValue, MeshPermission.nodeRPC.rawValue]
            ),
            SharedProjectMember(
                nodeId: workerIdentity.nodeId,
                localRepoPath: "/Users/worker/mesh",
                role: "worker",
                permissions: MeshPermission.workerDefaults.rawValues
            ),
        ]
    )
    let events = try [
        signedRelayEvent(.projectCreated, actor: laptopIdentity, projectId: projectId, logicalTime: 1, payload: [
            "id": .string(projectId),
            "name": .string(staleProject.name),
            "repoUrl": .string(staleProject.repoUrl),
        ]),
        signedRelayEvent(.projectMemberAdded, actor: laptopIdentity, target: laptopIdentity.nodeId, projectId: projectId, logicalTime: 2, payload: [
            "nodeId": .string(laptopIdentity.nodeId),
            "localRepoPath": .string("/Users/laptop/mesh"),
            "role": .string("controller"),
            "permissions": .array([
                .string(MeshPermission.projectWrite.rawValue),
                .string(MeshPermission.nodeRPC.rawValue),
            ]),
        ]),
        signedRelayEvent(.projectMemberAdded, actor: laptopIdentity, target: workerIdentity.nodeId, projectId: projectId, logicalTime: 3, payload: [
            "nodeId": .string(workerIdentity.nodeId),
            "localRepoPath": .string("/Users/worker/mesh"),
            "role": .string("worker"),
            "permissions": .array(MeshPermission.workerDefaults.rawValues.map(JSONValue.string)),
        ]),
        signedRelayEvent(.projectMemberRemoved, actor: laptopIdentity, target: laptopIdentity.nodeId, projectId: projectId, logicalTime: 4, payload: [
            "nodeId": .string(laptopIdentity.nodeId),
        ]),
    ]
    try store.save(MeshState(
        nodes: [
            MeshNodeRecord(
                id: laptopIdentity.nodeId,
                name: laptopIdentity.name,
                publicKey: laptopIdentity.publicKey,
                roles: laptopIdentity.roles,
                capabilities: laptopIdentity.capabilities
            ),
            MeshNodeRecord(
                id: workerIdentity.nodeId,
                name: workerIdentity.name,
                publicKey: workerIdentity.publicKey,
                roles: workerIdentity.roles,
                capabilities: workerIdentity.capabilities
            ),
        ],
        sharedProjects: [staleProject],
        events: events
    ))

    let relay = NodeMeshRelay(store: store, logger: Logger(label: "sloppy.node.mesh.relay.projected-acl.tests"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    var laptopContinuation: AsyncStream<String>.Continuation!
    let laptopMessages = WebSocketSentMessageRecorder()
    let laptopStream = AsyncStream<String> { next in
        laptopContinuation = next
    }
    let laptopConnection = WebSocketConnectionContext(
        sendText: { text in
            await laptopMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { laptopStream }
    )
    var workerContinuation: AsyncStream<String>.Continuation!
    let workerMessages = WebSocketSentMessageRecorder()
    let workerStream = AsyncStream<String> { next in
        workerContinuation = next
    }
    let workerConnection = WebSocketConnectionContext(
        sendText: { text in
            await workerMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { workerStream }
    )

    let laptopTask = Task {
        await relay.attach(connection: laptopConnection, remoteAddress: "127.0.0.1")
    }
    let workerTask = Task {
        await relay.attach(connection: workerConnection, remoteAddress: "127.0.0.1")
    }

    try await authenticateRelayConnection(
        identity: laptopIdentity,
        continuation: laptopContinuation,
        sentMessages: laptopMessages,
        encoder: encoder,
        decoder: decoder
    )
    try await authenticateRelayConnection(
        identity: workerIdentity,
        continuation: workerContinuation,
        sentMessages: workerMessages,
        encoder: encoder,
        decoder: decoder
    )
    try await waitUntil("mesh nodes authenticated for projected acl test") {
        await relay.activeNodeIds().sorted() == [laptopIdentity.nodeId, workerIdentity.nodeId].sorted()
    }

    laptopContinuation.yield(try encodedMeshEnvelope(
        MeshEnvelope(
            id: "rpc_projected_revoked",
            type: .rpcRequest,
            from: laptopIdentity.nodeId,
            to: workerIdentity.nodeId,
            scope: staleProject.eventScope,
            payload: .object(["method": .string("node.status")])
        ),
        encoder: encoder
    ))

    try await waitUntil("projected revoked rpc response sent") {
        let messages = await laptopMessages.all
        return messages.contains { message in
            guard let envelope = try? decoder.decode(MeshEnvelope.self, from: Data(message.utf8)) else {
                return false
            }
            return envelope.type == .rpcResponse &&
                envelope.payload.asObject?["requestId"] == .string("rpc_projected_revoked")
        }
    }
    #expect(await workerMessages.all.contains { message in
        guard let envelope = try? decoder.decode(MeshEnvelope.self, from: Data(message.utf8)) else {
            return false
        }
        return envelope.type == .rpcRequest
    } == false)

    laptopContinuation.finish()
    workerContinuation.finish()
    await laptopTask.value
    await workerTask.value
}

@Test
func nodeMeshRelayRejectsUnauthorizedLiveProjectSync() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-relay-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("mesh.json")
    let store = NodeMeshStore(stateURL: stateURL)
    let laptopIdentity = NodeIdentityGenerator.makeIdentity(name: "Laptop", roles: ["client"], capabilities: ["git"])
    let workerIdentity = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["run_agent"])
    let rogueIdentity = NodeIdentityGenerator.makeIdentity(name: "Rogue", roles: ["worker"], capabilities: ["run_agent"])
    try store.registerNode(laptopIdentity, status: .offline)
    try store.registerNode(workerIdentity, status: .offline)
    try store.registerNode(rogueIdentity, status: .offline)
    let project = try store.createSharedProject(name: "Mesh Project", repoUrl: "git@example.com:mesh.git")
    _ = try store.attachMember(
        projectIdOrName: project.id,
        nodeId: laptopIdentity.nodeId,
        localRepoPath: "/Users/laptop/mesh",
        role: "controller",
        permissions: [MeshPermission.projectWrite.rawValue]
    )
    _ = try store.attachMember(
        projectIdOrName: project.id,
        nodeId: workerIdentity.nodeId,
        localRepoPath: "/Users/worker/mesh",
        role: "worker",
        permissions: MeshPermission.workerDefaults.rawValues
    )
    let relay = NodeMeshRelay(store: store, logger: Logger(label: "sloppy.node.mesh.relay.project-sync.auth.tests"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    var rogueContinuation: AsyncStream<String>.Continuation!
    let rogueMessages = WebSocketSentMessageRecorder()
    let rogueStream = AsyncStream<String> { next in
        rogueContinuation = next
    }
    let rogueConnection = WebSocketConnectionContext(
        sendText: { text in
            await rogueMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { rogueStream }
    )
    var workerContinuation: AsyncStream<String>.Continuation!
    let workerMessages = WebSocketSentMessageRecorder()
    let workerStream = AsyncStream<String> { next in
        workerContinuation = next
    }
    let workerConnection = WebSocketConnectionContext(
        sendText: { text in
            await workerMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { workerStream }
    )

    let rogueTask = Task {
        await relay.attach(connection: rogueConnection, remoteAddress: "127.0.0.1")
    }
    let workerTask = Task {
        await relay.attach(connection: workerConnection, remoteAddress: "127.0.0.1")
    }
    try await authenticateRelayConnection(
        identity: rogueIdentity,
        continuation: rogueContinuation,
        sentMessages: rogueMessages,
        encoder: encoder,
        decoder: decoder
    )
    try await authenticateRelayConnection(
        identity: workerIdentity,
        continuation: workerContinuation,
        sentMessages: workerMessages,
        encoder: encoder,
        decoder: decoder
    )

    rogueContinuation.yield(try encodedMeshEnvelope(
        MeshEnvelope(
            id: "project_sync_targeted_unauthorized",
            type: .projectSyncEvent,
            from: rogueIdentity.nodeId,
            to: workerIdentity.nodeId,
            scope: project.eventScope,
            payload: .object(["projectId": .string(project.id)])
        ),
        encoder: encoder
    ))
    rogueContinuation.yield(try encodedMeshEnvelope(
        MeshEnvelope(
            id: "project_sync_broadcast_unauthorized",
            type: .projectSyncEvent,
            from: rogueIdentity.nodeId,
            scope: project.eventScope,
            payload: .object(["projectId": .string(project.id)])
        ),
        encoder: encoder
    ))

    try await waitUntil("forbidden project sync response sent") {
        let messages = await rogueMessages.all
        return messages.contains { message in
            guard let envelope = try? decoder.decode(MeshEnvelope.self, from: Data(message.utf8)) else {
                return false
            }
            return envelope.type == .rpcResponse &&
                envelope.payload.asObject?["requestId"] == .string("project_sync_targeted_unauthorized")
        }
    }
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(await workerMessages.all.contains { message in
        guard let envelope = try? decoder.decode(MeshEnvelope.self, from: Data(message.utf8)) else {
            return false
        }
        return envelope.type == .projectSyncEvent &&
            envelope.from == rogueIdentity.nodeId
    } == false)

    rogueContinuation.finish()
    workerContinuation.finish()
    await rogueTask.value
    await workerTask.value
}

@Test
func nodeMeshRelaySkipsPendingProjectSyncForProjectedRemovedMember() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-relay-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("mesh.json")
    let store = NodeMeshStore(stateURL: stateURL)
    let laptopIdentity = NodeIdentityGenerator.makeIdentity(name: "Laptop", roles: ["client"], capabilities: ["git"])
    let workerIdentity = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["run_agent"])
    let projectId = "sp_projected_sync"
    let staleProject = SharedProjectRecord(
        id: projectId,
        name: "Projected Sync",
        repoUrl: "git@example.com:projected-sync.git",
        members: [
            SharedProjectMember(
                nodeId: laptopIdentity.nodeId,
                localRepoPath: "/Users/laptop/mesh",
                role: "controller",
                permissions: [MeshPermission.projectWrite.rawValue]
            ),
            SharedProjectMember(
                nodeId: workerIdentity.nodeId,
                localRepoPath: "/Users/worker/mesh",
                role: "worker",
                permissions: MeshPermission.workerDefaults.rawValues
            ),
        ]
    )
    let pendingSync = MeshEnvelope(
        id: "pending_project_sync",
        type: .projectSyncEvent,
        from: laptopIdentity.nodeId,
        to: workerIdentity.nodeId,
        scope: staleProject.eventScope,
        payload: .object(["projectId": .string(projectId)])
    )
    let events = try [
        signedRelayEvent(.projectCreated, actor: laptopIdentity, projectId: projectId, logicalTime: 1, payload: [
            "id": .string(projectId),
            "name": .string(staleProject.name),
            "repoUrl": .string(staleProject.repoUrl),
        ]),
        signedRelayEvent(.projectMemberAdded, actor: laptopIdentity, target: laptopIdentity.nodeId, projectId: projectId, logicalTime: 2, payload: [
            "nodeId": .string(laptopIdentity.nodeId),
            "localRepoPath": .string("/Users/laptop/mesh"),
            "role": .string("controller"),
            "permissions": .array([.string(MeshPermission.projectWrite.rawValue)]),
        ]),
        signedRelayEvent(.projectMemberAdded, actor: laptopIdentity, target: workerIdentity.nodeId, projectId: projectId, logicalTime: 3, payload: [
            "nodeId": .string(workerIdentity.nodeId),
            "localRepoPath": .string("/Users/worker/mesh"),
            "role": .string("worker"),
            "permissions": .array(MeshPermission.workerDefaults.rawValues.map(JSONValue.string)),
        ]),
        signedRelayEvent(.projectMemberRemoved, actor: laptopIdentity, target: workerIdentity.nodeId, projectId: projectId, logicalTime: 4, payload: [
            "nodeId": .string(workerIdentity.nodeId),
        ]),
    ]
    try store.save(MeshState(
        nodes: [
            MeshNodeRecord(
                id: laptopIdentity.nodeId,
                name: laptopIdentity.name,
                publicKey: laptopIdentity.publicKey,
                roles: laptopIdentity.roles,
                capabilities: laptopIdentity.capabilities
            ),
            MeshNodeRecord(
                id: workerIdentity.nodeId,
                name: workerIdentity.name,
                publicKey: workerIdentity.publicKey,
                roles: workerIdentity.roles,
                capabilities: workerIdentity.capabilities
            ),
        ],
        sharedProjects: [staleProject],
        envelopes: [pendingSync],
        events: events
    ))

    let relay = NodeMeshRelay(store: store, logger: Logger(label: "sloppy.node.mesh.relay.pending-sync.tests"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var continuation: AsyncStream<String>.Continuation!
    let sentMessages = WebSocketSentMessageRecorder()
    let stream = AsyncStream<String> { next in
        continuation = next
    }
    let connection = WebSocketConnectionContext(
        sendText: { text in
            await sentMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { stream }
    )

    let relayTask = Task {
        await relay.attach(connection: connection, remoteAddress: "127.0.0.1")
    }
    try await authenticateRelayConnection(
        identity: workerIdentity,
        continuation: continuation,
        sentMessages: sentMessages,
        encoder: encoder,
        decoder: decoder
    )

    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(await sentMessages.all.contains { message in
        guard let envelope = try? decoder.decode(MeshEnvelope.self, from: Data(message.utf8)) else {
            return false
        }
        return envelope.type == .projectSyncEvent
    } == false)

    continuation.finish()
    await relayTask.value
}

@Test
func nodeMeshRelaySkipsPendingProjectSyncForLegacyRemovedMember() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-relay-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("mesh.json")
    let store = NodeMeshStore(stateURL: stateURL)
    let laptopIdentity = NodeIdentityGenerator.makeIdentity(name: "Laptop", roles: ["client"], capabilities: ["git"])
    let workerIdentity = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["run_agent"])
    let projectId = "sp_legacy_sync"
    let legacyProject = SharedProjectRecord(
        id: projectId,
        name: "Legacy Sync",
        repoUrl: "git@example.com:legacy-sync.git",
        members: [
            SharedProjectMember(
                nodeId: laptopIdentity.nodeId,
                localRepoPath: "/Users/laptop/mesh",
                role: "controller",
                permissions: [MeshPermission.projectWrite.rawValue]
            ),
            SharedProjectMember(
                nodeId: workerIdentity.nodeId,
                localRepoPath: "/Users/worker/mesh",
                role: "worker",
                permissions: MeshPermission.workerDefaults.rawValues
            ),
        ]
    )
    let pendingSync = MeshEnvelope(
        id: "pending_legacy_project_sync",
        type: .projectSyncEvent,
        from: laptopIdentity.nodeId,
        to: workerIdentity.nodeId,
        scope: legacyProject.eventScope,
        payload: .object(["projectId": .string(projectId)])
    )
    let removal = try signedRelayEvent(.projectMemberRemoved, actor: laptopIdentity, target: workerIdentity.nodeId, projectId: projectId, logicalTime: 1, payload: [
        "nodeId": .string(workerIdentity.nodeId),
    ])
    try store.save(MeshState(
        nodes: [
            MeshNodeRecord(
                id: laptopIdentity.nodeId,
                name: laptopIdentity.name,
                publicKey: laptopIdentity.publicKey,
                roles: laptopIdentity.roles,
                capabilities: laptopIdentity.capabilities
            ),
            MeshNodeRecord(
                id: workerIdentity.nodeId,
                name: workerIdentity.name,
                publicKey: workerIdentity.publicKey,
                roles: workerIdentity.roles,
                capabilities: workerIdentity.capabilities
            ),
        ],
        sharedProjects: [legacyProject],
        envelopes: [pendingSync],
        events: [removal]
    ))

    let relay = NodeMeshRelay(store: store, logger: Logger(label: "sloppy.node.mesh.relay.pending-legacy-sync.tests"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var continuation: AsyncStream<String>.Continuation!
    let sentMessages = WebSocketSentMessageRecorder()
    let stream = AsyncStream<String> { next in
        continuation = next
    }
    let connection = WebSocketConnectionContext(
        sendText: { text in
            await sentMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { stream }
    )

    let relayTask = Task {
        await relay.attach(connection: connection, remoteAddress: "127.0.0.1")
    }
    try await authenticateRelayConnection(
        identity: workerIdentity,
        continuation: continuation,
        sentMessages: sentMessages,
        encoder: encoder,
        decoder: decoder
    )

    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(await sentMessages.all.contains { message in
        guard let envelope = try? decoder.decode(MeshEnvelope.self, from: Data(message.utf8)) else {
            return false
        }
        return envelope.type == .projectSyncEvent
    } == false)

    continuation.finish()
    await relayTask.value
}

@Test
func nodeMeshRelaySkipsPendingTaskDispatchForProjectedRemovedAssignee() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-relay-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("mesh.json")
    let store = NodeMeshStore(stateURL: stateURL)
    let laptopIdentity = NodeIdentityGenerator.makeIdentity(name: "Laptop", roles: ["client"], capabilities: ["git"])
    let workerIdentity = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["run_agent"])
    let projectId = "sp_projected_dispatch"
    let taskId = "mesh_task_projected_dispatch"
    let staleProject = SharedProjectRecord(
        id: projectId,
        name: "Projected Dispatch",
        repoUrl: "git@example.com:projected-dispatch.git",
        members: [
            SharedProjectMember(
                nodeId: laptopIdentity.nodeId,
                localRepoPath: "/Users/laptop/mesh",
                role: "controller",
                permissions: [MeshPermission.projectWrite.rawValue, MeshPermission.taskCreate.rawValue, MeshPermission.taskAssign.rawValue]
            ),
            SharedProjectMember(
                nodeId: workerIdentity.nodeId,
                localRepoPath: "/Users/worker/mesh",
                role: "worker",
                permissions: MeshPermission.workerDefaults.rawValues
            ),
        ]
    )
    let pendingDispatch = MeshEnvelope(
        id: "pending_task_dispatch",
        type: .taskDispatch,
        from: laptopIdentity.nodeId,
        to: workerIdentity.nodeId,
        scope: staleProject.eventScope,
        payload: .object([
            "taskId": .string(taskId),
            "projectId": .string(projectId),
            "title": .string("Run build"),
        ])
    )
    let events = try [
        signedRelayEvent(.projectCreated, actor: laptopIdentity, projectId: projectId, logicalTime: 1, payload: [
            "id": .string(projectId),
            "name": .string(staleProject.name),
            "repoUrl": .string(staleProject.repoUrl),
        ]),
        signedRelayEvent(.projectMemberAdded, actor: laptopIdentity, target: laptopIdentity.nodeId, projectId: projectId, logicalTime: 2, payload: [
            "nodeId": .string(laptopIdentity.nodeId),
            "localRepoPath": .string("/Users/laptop/mesh"),
            "role": .string("controller"),
            "permissions": .array([
                .string(MeshPermission.projectWrite.rawValue),
                .string(MeshPermission.taskCreate.rawValue),
                .string(MeshPermission.taskAssign.rawValue),
            ]),
        ]),
        signedRelayEvent(.projectMemberAdded, actor: laptopIdentity, target: workerIdentity.nodeId, projectId: projectId, logicalTime: 3, payload: [
            "nodeId": .string(workerIdentity.nodeId),
            "localRepoPath": .string("/Users/worker/mesh"),
            "role": .string("worker"),
            "permissions": .array(MeshPermission.workerDefaults.rawValues.map(JSONValue.string)),
        ]),
        signedRelayEvent(.taskCreated, actor: laptopIdentity, projectId: projectId, logicalTime: 4, payload: [
            "taskId": .string(taskId),
            "title": .string("Run build"),
        ]),
        signedRelayEvent(.taskAssigned, actor: laptopIdentity, target: workerIdentity.nodeId, projectId: projectId, logicalTime: 5, payload: [
            "taskId": .string(taskId),
            "assignedNodeId": .string(workerIdentity.nodeId),
        ]),
        signedRelayEvent(.projectMemberRemoved, actor: laptopIdentity, target: workerIdentity.nodeId, projectId: projectId, logicalTime: 6, payload: [
            "nodeId": .string(workerIdentity.nodeId),
        ]),
    ]
    try store.save(MeshState(
        nodes: [
            MeshNodeRecord(
                id: laptopIdentity.nodeId,
                name: laptopIdentity.name,
                publicKey: laptopIdentity.publicKey,
                roles: laptopIdentity.roles,
                capabilities: laptopIdentity.capabilities
            ),
            MeshNodeRecord(
                id: workerIdentity.nodeId,
                name: workerIdentity.name,
                publicKey: workerIdentity.publicKey,
                roles: workerIdentity.roles,
                capabilities: workerIdentity.capabilities
            ),
        ],
        sharedProjects: [staleProject],
        envelopes: [pendingDispatch],
        events: events
    ))

    let relay = NodeMeshRelay(store: store, logger: Logger(label: "sloppy.node.mesh.relay.pending-dispatch.tests"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var continuation: AsyncStream<String>.Continuation!
    let sentMessages = WebSocketSentMessageRecorder()
    let stream = AsyncStream<String> { next in
        continuation = next
    }
    let connection = WebSocketConnectionContext(
        sendText: { text in
            await sentMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { stream }
    )

    let relayTask = Task {
        await relay.attach(connection: connection, remoteAddress: "127.0.0.1")
    }
    try await authenticateRelayConnection(
        identity: workerIdentity,
        continuation: continuation,
        sentMessages: sentMessages,
        encoder: encoder,
        decoder: decoder
    )

    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(await sentMessages.all.contains { message in
        guard let envelope = try? decoder.decode(MeshEnvelope.self, from: Data(message.utf8)) else {
            return false
        }
        return envelope.type == .taskDispatch
    } == false)

    continuation.finish()
    await relayTask.value
}

@Test
func nodeMeshRelayRejectsUnknownNodeAuth() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-relay-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("mesh.json")
    let store = NodeMeshStore(stateURL: stateURL)
    let identity = NodeIdentityGenerator.makeIdentity(name: "Unknown", roles: ["worker"], capabilities: ["run_agent"])
    let relay = NodeMeshRelay(store: store, logger: Logger(label: "sloppy.node.mesh.relay.auth.tests"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var continuation: AsyncStream<String>.Continuation!
    let sentMessages = WebSocketSentMessageRecorder()
    let stream = AsyncStream<String> { next in
        continuation = next
    }
    let connection = WebSocketConnectionContext(
        sendText: { text in
            await sentMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { stream }
    )

    let relayTask = Task {
        await relay.attach(connection: connection, remoteAddress: "127.0.0.1")
    }
    let challenge = try await receiveRelayAuthChallenge(sentMessages: sentMessages, decoder: decoder)
    let response = try #require(try NodeMeshClient.makeAuthResponseEnvelope(identity: identity, challengeEnvelope: challenge))
    continuation.yield(try encodedMeshEnvelope(response, encoder: encoder))

    try await waitUntil("unknown node auth error sent") {
        await sentMessages.count >= 2
    }
    let errorMessage = try #require(await sentMessages.last)
    let errorEnvelope = try decoder.decode(MeshEnvelope.self, from: Data(errorMessage.utf8))
    #expect(errorEnvelope.type == .rpcResponse)
    #expect(errorEnvelope.payload.asObject?["ok"] == .bool(false))
    #expect(errorEnvelope.payload.asObject?["error"]?.asObject?["code"] == .string("auth_failed"))
    #expect(await relay.activeNodeIds().isEmpty)

    continuation.finish()
    await relayTask.value
}

@Test
func nodeMeshRelayRejectsWrongSignatureAuth() async throws {
    let stateURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sloppy-relay-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("mesh.json")
    let store = NodeMeshStore(stateURL: stateURL)
    let registered = NodeIdentityGenerator.makeIdentity(name: "Worker", roles: ["worker"], capabilities: ["run_agent"])
    let impostor = NodeIdentityGenerator.makeIdentity(name: "Impostor", roles: ["worker"], capabilities: ["run_agent"])
    try store.registerNode(registered, status: .offline)
    let relay = NodeMeshRelay(store: store, logger: Logger(label: "sloppy.node.mesh.relay.auth.tests"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var continuation: AsyncStream<String>.Continuation!
    let sentMessages = WebSocketSentMessageRecorder()
    let stream = AsyncStream<String> { next in
        continuation = next
    }
    let connection = WebSocketConnectionContext(
        sendText: { text in
            await sentMessages.append(text)
            return true
        },
        close: {},
        incomingMessages: { stream }
    )

    let relayTask = Task {
        await relay.attach(connection: connection, remoteAddress: "127.0.0.1")
    }
    let challenge = try await receiveRelayAuthChallenge(sentMessages: sentMessages, decoder: decoder)
    let nonce = try JSONValueCoder.decode(MeshAuthChallengePayload.self, from: challenge.payload).nonce
    let wrongSignature = try NodeIdentityGenerator.sign(challenge: Data(nonce.utf8), privateKey: impostor.privateKey)
    let response = MeshEnvelope(
        type: .authResponse,
        from: registered.nodeId,
        to: "relay",
        payload: try JSONValueCoder.encode(
            MeshAuthResponsePayload(
                nonce: nonce,
                nodeId: registered.nodeId,
                publicKey: registered.publicKey,
                signature: wrongSignature
            )
        )
    )
    continuation.yield(try encodedMeshEnvelope(response, encoder: encoder))

    try await waitUntil("wrong signature auth error sent") {
        await sentMessages.count >= 2
    }
    let errorMessage = try #require(await sentMessages.last)
    let errorEnvelope = try decoder.decode(MeshEnvelope.self, from: Data(errorMessage.utf8))
    #expect(errorEnvelope.payload.asObject?["ok"] == .bool(false))
    #expect(errorEnvelope.payload.asObject?["error"]?.asObject?["code"] == .string("auth_failed"))
    #expect(await relay.activeNodeIds().isEmpty)

    continuation.finish()
    await relayTask.value
}

@Test
func webSocketSessionStreamPublishesToolEventsOverHTTPServer() async throws {
    let config = CoreConfig.test
    let service = CoreService(config: config)
    let router = CoreRouter(service: service)
    let server = CoreHTTPServer(
        host: "127.0.0.1",
        port: 0,
        router: router,
        logger: Logger(label: "sloppy.core.httpserver.tests")
    )
    try server.start()
    defer { try? server.shutdown() }

    guard let boundPort = server.boundPort else {
        throw WebSocketMalformedResponseError()
    }

    _ = try await service.createAgent(
        AgentCreateRequest(
            id: "agent-http-ws",
            displayName: "Agent HTTP WS",
            role: "WS regression"
        )
    )
    let session = try await service.createAgentSession(
        agentID: "agent-http-ws",
        request: AgentSessionCreateRequest(title: "HTTP WS Session")
    )

    let wsURL = try #require(
        URL(string: "ws://127.0.0.1:\(boundPort)/v1/agents/agent-http-ws/sessions/\(session.id)/ws")
    )
    let webSocket = URLSession.shared.webSocketTask(with: wsURL)
    webSocket.resume()
    defer { webSocket.cancel(with: .normalClosure, reason: nil) }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let readyMessage = try await withAsyncTestTimeout(
        operation: "WebSocket session-ready event"
    ) {
        try await webSocket.receive()
    }
    guard case .string(let readyPayload) = readyMessage else {
        throw WebSocketMalformedResponseError()
    }
    let readyUpdate = try decoder.decode(AgentSessionStreamUpdate.self, from: Data(readyPayload.utf8))
    #expect(readyUpdate.kind == .sessionReady)
    #expect(readyUpdate.summary?.id == session.id)

    async let invocation: ToolInvocationResult = service.invokeToolFromRuntime(
        agentID: "agent-http-ws",
        sessionID: session.id,
        request: ToolInvocationRequest(tool: "sessions.list", arguments: [:], reason: "ws regression")
    )

    let firstEventMessage = try await withAsyncTestTimeout(
        operation: "WebSocket tool-call event"
    ) {
        try await webSocket.receive()
    }
    let secondEventMessage = try await withAsyncTestTimeout(
        operation: "WebSocket tool-result event"
    ) {
        try await webSocket.receive()
    }
    _ = await invocation

    let firstPayload = try #require(messagePayload(firstEventMessage))
    let secondPayload = try #require(messagePayload(secondEventMessage))
    let firstUpdate = try decoder.decode(AgentSessionStreamUpdate.self, from: Data(firstPayload.utf8))
    let secondUpdate = try decoder.decode(AgentSessionStreamUpdate.self, from: Data(secondPayload.utf8))

    #expect(firstUpdate.kind == .sessionEvent)
    #expect(firstUpdate.event?.type == .toolCall)
    #expect(firstUpdate.event?.toolCall?.tool == "sessions.list")
    #expect(secondUpdate.kind == .sessionEvent)
    #expect(secondUpdate.event?.type == .toolResult)
    #expect(secondUpdate.event?.toolResult?.tool == "sessions.list")
    #expect(secondUpdate.cursor > firstUpdate.cursor)
}

@Test
func dashboardTerminalWebSocketAcceptsInputAndAllowsReconnect() async throws {
    var config = CoreConfig.test
    config.ui.dashboardAuth.enabled = true
    config.ui.dashboardAuth.token = "dashboard-secret"
    config.ui.dashboardTerminal.enabled = true
    config.ui.dashboardTerminal.localOnly = true

    let service = CoreService(config: config)
    let router = CoreRouter(service: service)
    let server = CoreHTTPServer(
        host: "127.0.0.1",
        port: 0,
        router: router,
        logger: Logger(label: "sloppy.dashboard.terminal.httpserver.tests")
    )
    try server.start()
    defer { try? server.shutdown() }

    let port = try #require(server.boundPort)
    let wsURL = try #require(URL(string: "ws://127.0.0.1:\(port)/v1/dashboard/terminal/ws"))

    let unauthenticatedSocket = URLSession.shared.webSocketTask(with: wsURL)
    unauthenticatedSocket.resume()
    defer { unauthenticatedSocket.cancel(with: .normalClosure, reason: nil) }

    try await sendDashboardTerminalMessage(
        DashboardTerminalClientFrame(type: "start", token: nil, projectId: nil, cwd: nil, cols: 80, rows: 24, data: nil),
        over: unauthenticatedSocket
    )
    let unauthorized = try await receiveDashboardTerminalMessage(over: unauthenticatedSocket)
    #expect(unauthorized.type == "error")
    #expect(unauthorized.code == "unauthorized")

    let badAuthSocket = URLSession.shared.webSocketTask(with: wsURL)
    badAuthSocket.resume()
    defer { badAuthSocket.cancel(with: .normalClosure, reason: nil) }

    try await sendDashboardTerminalMessage(
        DashboardTerminalClientFrame(type: "auth", token: "wrong-token", projectId: nil, cwd: nil, cols: nil, rows: nil, data: nil),
        over: badAuthSocket
    )
    let badAuth = try await receiveDashboardTerminalMessage(over: badAuthSocket)
    #expect(badAuth.type == "error")
    #expect(badAuth.code == "unauthorized")

    let firstSocket = URLSession.shared.webSocketTask(with: wsURL)
    firstSocket.resume()
    defer { firstSocket.cancel(with: .normalClosure, reason: nil) }

    try await sendDashboardTerminalMessage(
        DashboardTerminalClientFrame(type: "auth", token: "dashboard-secret", projectId: nil, cwd: nil, cols: nil, rows: nil, data: nil),
        over: firstSocket
    )
    let authenticated = try await receiveDashboardTerminalMessage(over: firstSocket)
    #expect(authenticated.type == "authenticated")

    try await sendDashboardTerminalMessage(
        DashboardTerminalClientFrame(type: "start", token: nil, projectId: nil, cwd: nil, cols: 80, rows: 24, data: nil),
        over: firstSocket
    )
    let ready = try await receiveDashboardTerminalMessage(over: firstSocket)
    #expect(ready.type == "ready")
    #expect((ready.sessionId ?? "").isEmpty == false)

    let marker = "__sloppy_terminal_input_ok_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))__"
    try await sendDashboardTerminalMessage(
        DashboardTerminalClientFrame(type: "input", token: nil, projectId: nil, cwd: nil, cols: nil, rows: nil, data: "printf '\(marker)\\n'\r"),
        over: firstSocket
    )

    let combinedOutput = try await collectDashboardTerminalOutput(untilContains: marker, over: firstSocket)
    #expect(combinedOutput.contains(marker))

    try await sendDashboardTerminalMessage(
        DashboardTerminalClientFrame(type: "close", token: nil, projectId: nil, cwd: nil, cols: nil, rows: nil, data: nil),
        over: firstSocket
    )
    let closed = try await receiveDashboardTerminalMessage(over: firstSocket)
    #expect(closed.type == "closed")

    try await sendDashboardTerminalMessage(
        DashboardTerminalClientFrame(type: "start", token: nil, projectId: nil, cwd: nil, cols: 100, rows: 30, data: nil),
        over: firstSocket
    )
    let restarted = try await receiveDashboardTerminalMessage(over: firstSocket)
    #expect(restarted.type == "ready")
    #expect((restarted.sessionId ?? "").isEmpty == false)
    #expect(restarted.sessionId != ready.sessionId)

    firstSocket.cancel(with: .normalClosure, reason: nil)

    let secondSocket = URLSession.shared.webSocketTask(with: wsURL)
    secondSocket.resume()
    defer { secondSocket.cancel(with: .normalClosure, reason: nil) }

    try await sendDashboardTerminalMessage(
        DashboardTerminalClientFrame(type: "auth", token: "dashboard-secret", projectId: nil, cwd: nil, cols: nil, rows: nil, data: nil),
        over: secondSocket
    )
    let reauthenticated = try await receiveDashboardTerminalMessage(over: secondSocket)
    #expect(reauthenticated.type == "authenticated")

    try await sendDashboardTerminalMessage(
        DashboardTerminalClientFrame(type: "start", token: nil, projectId: nil, cwd: nil, cols: 90, rows: 28, data: nil),
        over: secondSocket
    )
    let reconnected = try await receiveDashboardTerminalMessage(over: secondSocket)
    #expect(reconnected.type == "ready")
    #expect((reconnected.sessionId ?? "").isEmpty == false)
}

private func messagePayload(_ message: URLSessionWebSocketTask.Message) -> String? {
    switch message {
    case .string(let payload):
        return payload
    case .data(let payload):
        return String(data: payload, encoding: .utf8)
    @unknown default:
        return nil
    }
}

private func sendDashboardTerminalMessage(
    _ message: DashboardTerminalClientFrame,
    over socket: URLSessionWebSocketTask
) async throws {
    let payload = try JSONEncoder().encode(message)
    let text = try #require(String(data: payload, encoding: .utf8))
    try await socket.send(.string(text))
}

private func sendMeshEnvelope(
    _ envelope: MeshEnvelope,
    encoder: JSONEncoder,
    over socket: URLSessionWebSocketTask
) async throws {
    try await socket.send(.string(try encodedMeshEnvelope(envelope, encoder: encoder)))
}

private func authenticateMeshSocket(
    identity: NodeIdentity,
    encoder: JSONEncoder,
    decoder: JSONDecoder,
    over socket: URLSessionWebSocketTask
) async throws {
    let challengeMessage = try await receiveMeshWebSocketMessage(over: socket, operation: "mesh auth challenge")
    let challengePayload = try #require(messagePayload(challengeMessage))
    let challengeEnvelope = try decoder.decode(MeshEnvelope.self, from: Data(challengePayload.utf8))
    #expect(challengeEnvelope.type == .authChallenge)
    let responseEnvelope = try #require(try NodeMeshClient.makeAuthResponseEnvelope(identity: identity, challengeEnvelope: challengeEnvelope))
    try await sendMeshEnvelope(responseEnvelope, encoder: encoder, over: socket)
    try await sendMeshEnvelope(NodeMeshClient.makeHelloEnvelope(identity: identity), encoder: encoder, over: socket)
}

private func encodedMeshEnvelope(_ envelope: MeshEnvelope, encoder: JSONEncoder) throws -> String {
    let payload = try encoder.encode(envelope)
    return try #require(String(data: payload, encoding: .utf8))
}

private func receiveMeshWebSocketMessage(
    over socket: URLSessionWebSocketTask,
    operation: String,
    timeoutSeconds: TimeInterval = 5
) async throws -> URLSessionWebSocketTask.Message {
    final class ReceiveBox: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false
        private var continuation: CheckedContinuation<URLSessionWebSocketTask.Message, Error>?

        func setContinuation(_ continuation: CheckedContinuation<URLSessionWebSocketTask.Message, Error>) {
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }

        func finish(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            finished = true
            let continuation = continuation
            self.continuation = nil
            lock.unlock()

            switch result {
            case .success(let message):
                continuation?.resume(returning: message)
            case .failure(let error):
                continuation?.resume(throwing: error)
            }
        }
    }

    let box = ReceiveBox()
    return try await withCheckedThrowingContinuation { continuation in
        box.setContinuation(continuation)
        socket.receive { result in
            switch result {
            case .success(let message):
                box.finish(.success(message))
            case .failure(let error):
                box.finish(.failure(error))
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
            socket.cancel(with: .goingAway, reason: nil)
            box.finish(.failure(AsyncTestTimeoutError(operation: operation)))
        }
    }
}

private func receiveDashboardTerminalMessage(
    over socket: URLSessionWebSocketTask
) async throws -> DashboardTerminalServerFrame {
    try await withThrowingTaskGroup(of: DashboardTerminalServerFrame.self) { group in
        group.addTask {
            let message = try await socket.receive()
            let payload = try #require(messagePayload(message))
            return try JSONDecoder().decode(DashboardTerminalServerFrame.self, from: Data(payload.utf8))
        }
        group.addTask {
            try await Task.sleep(nanoseconds: 10_000_000_000)
            socket.cancel(with: .goingAway, reason: nil)
            throw AsyncTestTimeoutError(operation: "dashboard terminal websocket message")
        }

        let result = try await group.next()
        group.cancelAll()
        return try #require(result)
    }
}

private func collectDashboardTerminalOutput(
    untilContains needle: String,
    over socket: URLSessionWebSocketTask
) async throws -> String {
    var combined = ""

    while !combined.contains(needle) {
        let message = try await receiveDashboardTerminalMessage(over: socket)
        if message.type == "output" {
            combined += message.data ?? ""
            continue
        }
        if message.type == "error" {
            Issue.record("Terminal error while waiting for output: \(message.message ?? "(unknown)")")
            break
        }
    }

    return combined
}
#endif

private actor WebSocketSentMessageRecorder {
    private var messages: [String] = []

    var count: Int {
        messages.count
    }

    var isEmpty: Bool {
        messages.isEmpty
    }

    var first: String? {
        messages.first
    }

    var last: String? {
        messages.last
    }

    var all: [String] {
        messages
    }

    func append(_ message: String) {
        messages.append(message)
    }
}

private func receiveRelayAuthChallenge(
    sentMessages: WebSocketSentMessageRecorder,
    decoder: JSONDecoder
) async throws -> MeshEnvelope {
    try await waitUntil("relay auth challenge sent") {
        await sentMessages.isEmpty == false
    }
    let message = try #require(await sentMessages.first)
    let envelope = try decoder.decode(MeshEnvelope.self, from: Data(message.utf8))
    #expect(envelope.type == .authChallenge)
    return envelope
}

private func authenticateRelayConnection(
    identity: NodeIdentity,
    continuation: AsyncStream<String>.Continuation,
    sentMessages: WebSocketSentMessageRecorder,
    encoder: JSONEncoder,
    decoder: JSONDecoder
) async throws {
    let challenge = try await receiveRelayAuthChallenge(sentMessages: sentMessages, decoder: decoder)
    let response = try #require(try NodeMeshClient.makeAuthResponseEnvelope(identity: identity, challengeEnvelope: challenge))
    continuation.yield(try encodedMeshEnvelope(response, encoder: encoder))
    continuation.yield(try encodedMeshEnvelope(NodeMeshClient.makeHelloEnvelope(identity: identity), encoder: encoder))
}

private func signedRelayEvent(
    _ type: MeshEventType,
    actor: NodeIdentity,
    target: String? = nil,
    projectId: String?,
    logicalTime: UInt64,
    payload: [String: JSONValue]
) throws -> SignedMeshEvent {
    try MeshEventSigner.sign(
        MeshEvent(
            type: type,
            actorNodeId: actor.nodeId,
            targetNodeId: target,
            projectId: projectId,
            logicalTime: logicalTime,
            payload: .object(payload)
        ),
        identity: actor
    )
}

private func waitUntil(
    _ operation: String,
    timeoutSeconds: TimeInterval = 2,
    condition: @escaping @Sendable () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while !(await condition()) {
        if Date() > deadline {
            throw AsyncTestTimeoutError(operation: operation)
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

private func withAsyncTestTimeout<T: Sendable>(
    seconds: Double = 10,
    operation: String,
    _ work: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await work()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw AsyncTestTimeoutError(operation: operation)
        }

        let result = try await group.next()
        group.cancelAll()
        return try #require(result)
    }
}
