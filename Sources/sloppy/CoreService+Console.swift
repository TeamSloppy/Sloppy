import Foundation
import SloppyConsoleProtocol
import SloppyRemoteProtocol

extension CoreService {
    func startConsoleRelayIfBound() async {
        await ensureConsoleRelayStarted { await self.prepareConsoleRelayIfBound() }
    }
    func ensureConsoleRelayStarted(prepare: @escaping @Sendable () async -> Void) async {
        // Reserve startup before the first cross-actor await. Otherwise multiple
        // callers register sockets for the same device and evict one another.
        if let startup = consoleRelayStartupTask { await startup.value; return }
        guard consoleRelayTask == nil else { return }
        let startup = Task { await prepare() }
        consoleRelayStartupTask = startup
        await startup.value
        consoleRelayStartupTask = nil
    }
    private func prepareConsoleRelayIfBound() async {
        guard consoleRelayTask == nil, let store = consoleTrustStore,
              let binding = await store.binding(), binding.status == .active,
              let identity = try? await consoleTLSIdentity() else { return }
        let local = await store.identity()
        let environment = await store.environment()
        let console = ConsoleCloudDeviceClient(baseURL: environment.consoleURL, deviceID: local.deviceID, privateKey: local.signingPrivateKey)
        let remote = ConsoleRemoteConnection(deviceID: local.deviceID, signingPrivateKey: local.signingPrivateKey, identity: identity, relayURL: environment.relayURL, pins: [:])
        guard !Task.isCancelled else { return }
        consoleRemoteConnection = remote
        await consoleModelBridge.configure(.init(remote: remote, cloud: console, store: store, identity: identity, local: local, binding: binding))
        await remote.setEventHandler { [weak self] event in
            guard let logger = self?.logger else { return }
            switch event {
            case .connecting: logger.info("console.relay.connecting")
            case .connected(let ttl): logger.info("console.relay.connected", metadata: ["session_expires_in": .stringConvertible(Int(ttl))])
            case .disconnected(let reason): logger.warning("console.relay.disconnected", metadata: ["reason": .string(reason)])
            case .sessionRenewal: logger.info("console.relay.session_renewal")
            case .relayError(let code, let peer): logger.warning("console.relay.error", metadata: ["code": .string(code), "peer": .string(peer.uuidString)])
            case .peerReady(let peer): logger.info("console.relay.peer_ready", metadata: ["peer": .string(peer.uuidString)])
            }
        }
        await remote.setDisconnectHandler { [weak self] in await self?.consoleModelsDisconnected() }
        await remote.setHandler { [weak self] senderID, certificate, packet in
            guard let self else { return nil }
            return try await self.handleConsoleRemotePacket(senderID: senderID, certificate: certificate, packet: packet)
        }
        guard !Task.isCancelled else { await remote.disconnect(); return }
        consoleRelayTask = Task { [weak self] in
            // Trust sync and connect run every 30s while healthy, but a dropped
            // socket is retried immediately and failures back off to 30s.
            var nextAttempt = Date.distantPast
            var backoff = 2.0
            while !Task.isCancelled {
                if Date() >= nextAttempt {
                    do {
                        let snapshot = try await console.trust(instanceID: binding.id)
                        try await store.synchronize(snapshot)
                        await self?.validateConsoleModelStreams()
                        var pins: [UUID: Data] = [:]
                        for device in snapshot.devices where device.status == .active {
                            if snapshot.grants.contains(where: { $0.deviceID == device.id && $0.status == .active && $0.certificateFingerprint == ConsoleTrust.fingerprint(device.certificateDER) }) { pins[device.id] = device.certificateDER }
                        }
                        try await self?.consoleModelBridge.refreshPins(pins)
                        try await remote.connect()
                        backoff = 2
                        nextAttempt = Date().addingTimeInterval(30)
                    } catch {
                        self?.logger.warning("console.relay.connect.failed", metadata: ["error": .string(String(describing: error)), "retry_in": .stringConvertible(backoff)])
                        await remote.disconnect()
                        nextAttempt = Date().addingTimeInterval(backoff)
                        backoff = min(backoff * 2, 30)
                    }
                } else if !(await remote.isConnected) {
                    nextAttempt = Date()
                }
                try? await Task.sleep(for: .seconds(2))
            }
            await remote.disconnect()
            await self?.consoleRelayStopped()
        }
    }
    func stopConsoleRelay() async {
        // Join setup before clearing the bridge, so a suspended startup cannot
        // publish a new connection after shutdown.
        let startup = consoleRelayStartupTask
        startup?.cancel()
        await startup?.value
        await consoleModelBridge.stop()
        for id in Array(consoleModelStreams.keys) { closeConsoleModelStream(id) }
        let task = consoleRelayTask
        task?.cancel()
        for id in Array(consoleStreams.keys) { await closeConsoleStream(id) }
        await consoleRemoteConnection?.disconnect()
        await task?.value
    }
    private func consoleRelayStopped() async {
        consoleRelayTask = nil; consoleRemoteConnection = nil
        await consoleModelBridge.stop()
    }
    func handleConsoleRemotePacket(senderID: UUID, certificate: Data, packet: ConsoleRemotePacket) async throws -> ConsoleRemotePacket? {
        if packet.kind == "models.response" {
            let response = try ConsoleWire.decode(ConsoleModelResponse.self, from: packet.payload)
            _ = await consoleModelBridge.receive(from: senderID, response: response)
            return nil
        }
        if packet.kind == "models.request" {
            return await handleConsoleModelRequest(senderID: senderID, certificate: certificate, packet: packet)
        }
        guard let store = consoleTrustStore, let proof = packet.proof, proof.proof.deviceID == senderID else { throw ConsoleTrustError.forbidden }
        let context = try await store.authorize(proof, peerCertificate: certificate)
        if ["session.stream", "terminal.stream", "preview.stream"].contains(packet.kind) {
            return try await handleConsoleStream(senderID: senderID, packet: packet, context: context)
        }
        guard packet.kind == "core.http" else { throw ConsoleTrustError.forbidden }
        let request = try ConsoleWire.decode(RemoteCoreRequest.self, from: packet.payload)
        let response = await CoreRouter(service: self).handle(method: request.method, path: request.path, body: request.body, remoteAddress: "console-peer", consoleContext: context)
        let result = RemoteCoreResponse(requestID: request.requestID, status: response.status, body: response.body, contentType: response.contentType)
        return ConsoleRemotePacket(kind: "core.http.response", payload: try ConsoleWire.encode(result))
    }

    func consoleTLSIdentity() async throws -> RemoteTLSIdentity {
        guard let store = consoleTrustStore else { throw ConsoleTrustError.invalidConfiguration }
        let local = await store.identity()
        let url = workspaceRootURL.appendingPathComponent(".sloppy/console-tls.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let identity = try ConsoleWire.decode(RemoteTLSIdentity.self, from: Data(contentsOf: url))
            guard identity.signingPublicKey == local.signingPublicKey else { throw ConsoleTrustError.invalidConfiguration }
            return identity
        }
        let identity = try RemoteTLSIdentity(signingPrivateKey: local.signingPrivateKey, deviceID: local.deviceID)
        try ConsoleWire.encode(identity).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return identity
    }
}

struct ConsoleStreamRegistration: Sendable {
    var senderID: UUID
    var kind: String
    var continuation: AsyncStream<String>.Continuation
    var task: Task<Void, Never>
    var expiryTask: Task<Void, Never>
}

extension CoreService {
    func handleConsoleStream(senderID: UUID, packet: ConsoleRemotePacket, context: ConsoleAuthorizationContext) async throws -> ConsoleRemotePacket? {
        let frame = try ConsoleWire.decode(RemoteStreamFrame.self, from: packet.payload)
        try context.require(packet.kind == "terminal.stream" ? .terminal : .read)
        switch frame.action {
        case .open:
            guard consoleStreams[frame.streamID] == nil, consoleStreams.count < 20,
                  let path = frame.path, path.hasPrefix("/v1/"), !path.hasPrefix("/v1/node/mesh/"),
                  let remote = consoleRemoteConnection else { throw ConsoleTrustError.forbidden }
            let pair = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(32))
            let connection = WebSocketConnectionContext(sendText: { text in
                do {
                    let reply = RemoteStreamFrame(streamID: frame.streamID, action: .data, data: Data(text.utf8))
                    try await remote.send(ConsoleRemotePacket(kind: packet.kind + ".response", payload: ConsoleWire.encode(reply)), to: senderID)
                    return true
                } catch { return false }
            }, close: { [weak self] in await self?.closeConsoleStream(frame.streamID) }, incomingMessages: { pair.stream })
            let task = Task { [weak self] in
                guard let self else { return }
                _ = await CoreRouter(service: self).handleWebSocket(path: path, connection: connection, remoteAddress: "console-peer", consoleContext: context)
                await self.closeConsoleStream(frame.streamID)
            }
            let expiry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, context.expiresAt.timeIntervalSinceNow)))
                if !Task.isCancelled { await self?.closeConsoleStream(frame.streamID) }
            }
            consoleStreams[frame.streamID] = ConsoleStreamRegistration(senderID: senderID, kind: packet.kind, continuation: pair.continuation, task: task, expiryTask: expiry)
        case .data:
            guard let stream = consoleStreams[frame.streamID], stream.senderID == senderID, stream.kind == packet.kind, let data = frame.data, let text = String(data: data, encoding: .utf8) else { throw ConsoleTrustError.forbidden }
            if case .dropped = stream.continuation.yield(text) { await closeConsoleStream(frame.streamID) }
        case .close:
            guard consoleStreams[frame.streamID]?.senderID == senderID else { throw ConsoleTrustError.forbidden }
            await closeConsoleStream(frame.streamID)
        }
        return nil
    }
    func closeConsoleStream(_ id: UUID) async {
        guard let stream = consoleStreams.removeValue(forKey: id) else { return }
        stream.continuation.finish(); stream.task.cancel(); stream.expiryTask.cancel()
        if let remote = consoleRemoteConnection {
            let frame = RemoteStreamFrame(streamID: id, action: .close)
            if let data = try? ConsoleWire.encode(frame) { try? await remote.send(ConsoleRemotePacket(kind: stream.kind + ".response", payload: data), to: stream.senderID) }
        }
    }
}
