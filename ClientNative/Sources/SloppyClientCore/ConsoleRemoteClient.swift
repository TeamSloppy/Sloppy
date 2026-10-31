import Crypto
import Foundation
import Logging
import Security
import SloppyConsoleProtocol
import SloppyRemoteProtocol

public struct ConsoleDeviceCredential: Codable, Sendable {
    public var deviceID: UUID
    public var privateKey: Data
    public var tls: RemoteTLSIdentity
    public static func load() -> Self? {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "team.sloppy.console.identity", kSecAttrAccount as String: "device", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?; guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return nil }
        query.removeAll(); return try? ConsoleWire.decode(Self.self, from: data)
    }
    public static func createIfNeeded() throws -> Self {
        if let existing = load() { return existing }
        let key = Curve25519.Signing.PrivateKey(), id = UUID()
        let value = Self(deviceID: id, privateKey: key.rawRepresentation, tls: try RemoteTLSIdentity(signingPrivateKey: key.rawRepresentation, deviceID: id))
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "team.sloppy.console.identity", kSecAttrAccount as String: "device", kSecValueData as String: try ConsoleWire.encode(value), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw ConsoleTrustError.invalidConfiguration }; return value
    }
}

public actor ConsoleRemoteClientRegistry {
    public static let shared = ConsoleRemoteClientRegistry()
    private struct Connected {
        var instance: InstanceBinding
        var connection: ConsoleRemoteConnection
        var organizationID: UUID?
        var certificate: Data
    }
    private struct SavedPin: Codable { var instance: InstanceBinding; var certificate: Data; var organizationID: UUID? }
    private var savedPins: [UUID: SavedPin] = {
        guard let data = UserDefaults.standard.data(forKey: "sloppy.console.host-pins") else { return [:] }
        return (try? ConsoleWire.decode([UUID: SavedPin].self, from: data)) ?? [:]
    }()
    private var directoryHostIDs: Set<UUID> = []
    private var transport: ConsoleRemoteConnection?
    private var transportID: UUID?
    private struct StreamEntry { var hostID: UUID; var kind: String; var continuation: AsyncStream<RemoteStreamFrame>.Continuation }
    private var streams: [UUID: StreamEntry] = [:]
    private var connections: [UUID: Connected] = [:]
    private var requests: [UUID: CheckedContinuation<RemoteCoreResponse, any Error>] = [:]
    private var requestTasks: [UUID: Task<Void, Never>] = [:]
    private var requestTimeouts: [UUID: Task<Void, Never>] = [:]
    private let requestTransport: (@Sendable (UUID, RemoteCoreRequest) async throws -> RemoteCoreResponse)?

    public init() { requestTransport = nil }

    init(requestTransport: @escaping @Sendable (UUID, RemoteCoreRequest) async throws -> RemoteCoreResponse) {
        self.requestTransport = requestTransport
    }
    public func contains(hostID: UUID) -> Bool { directoryHostIDs.contains(hostID) || connections[hostID] != nil || savedPins[hostID] != nil }
    public func installDirectory(_ snapshot: ConsoleAccountClient.Snapshot) async -> Set<UUID> {
        directoryHostIDs = Set(snapshot.instances.map(\.hostDeviceID))
        var unverified: Set<UUID> = []
        for instance in snapshot.instances {
            let host = snapshot.devices.first { $0.id == instance.hostDeviceID && $0.status == .active }
            let trusted = host.map { host in
                savedPins[instance.hostDeviceID].map { pin in
                    Self.trustMatches(instance: instance, savedInstance: pin.instance, certificate: pin.certificate)
                        && pin.certificate == host.certificateDER
                } ?? false
            } ?? false
            if !trusted {
                unverified.insert(instance.hostDeviceID)
                savedPins[instance.hostDeviceID] = nil
                connections[instance.hostDeviceID] = nil
            }
        }
        UserDefaults.standard.set(try? ConsoleWire.encode(savedPins), forKey: "sloppy.console.host-pins")
        await transport?.updatePins(connections.mapValues { $0.certificate })
        return unverified
    }
    public func hasTrustedPin(for instance: InstanceBinding) -> Bool {
        guard let pin = savedPins[instance.hostDeviceID] else { return false }
        return Self.trustMatches(instance: instance, savedInstance: pin.instance, certificate: pin.certificate)
    }
    static func trustMatches(instance: InstanceBinding, savedInstance: InstanceBinding, certificate: Data) -> Bool {
        instance.status == .active
            && savedInstance.id == instance.id
            && savedInstance.hostDeviceID == instance.hostDeviceID
            && savedInstance.hostCertificateFingerprint == instance.hostCertificateFingerprint
            && ConsoleTrust.fingerprint(certificate) == instance.hostCertificateFingerprint
    }
    public func connect(instance: InstanceBinding, hostCertificate: Data, expectedFingerprint: String, organizationID: UUID?) async throws {
        guard expectedFingerprint.lowercased() == ConsoleTrust.fingerprint(hostCertificate),
              expectedFingerprint.lowercased() == instance.hostCertificateFingerprint else { throw ConsoleTrustError.invalidSignature }
        let credential = try ConsoleDeviceCredential.createIfNeeded()
        // Renew a human access proof before opening a Relay socket.
        _ = try await ConsoleAccountClient.shared.proof(instanceID: instance.id, deviceID: credential.deviceID, organizationID: organizationID)
        let connection: ConsoleRemoteConnection
        if let current = transport { connection = current }
        else {
            connection = ConsoleRemoteConnection(deviceID: credential.deviceID, signingPrivateKey: credential.privateKey, identity: credential.tls, relayURL: ConsoleAccountClient.relayGatewayURL, pins: [:], authenticateDevice: {
                try await ConsoleAccountClient.shared.authenticateRelayDevice(credential)
            })
            transport = connection
            let id = UUID()
            transportID = id
            let logger = Logger(label: "sloppy.console-transport")
            await connection.setEventHandler { event in
                switch event {
                case .connecting:
                    logger.info("console.transport.connecting")
                case .socketTCPConnected(let address):
                    logger.info("console.transport.tcp-connected", metadata: ["remote": .string(address)])
                case .socketTLSCompleted(let protocolName):
                    logger.info("console.transport.tls-completed", metadata: ["protocol": .string(protocolName ?? "none")])
                case .socketUpgradeResponse(let status):
                    logger.info("console.transport.upgrade-response", metadata: ["status": .stringConvertible(status)])
                case .connected(let ttl):
                    logger.info("console.transport.connected", metadata: ["session_expires_in": .stringConvertible(Int(ttl))])
                case .peerReady(let peer):
                    logger.info("console.transport.peer-ready", metadata: ["peer": .string(peer.uuidString)])
                case .relayError(let code, let peer):
                    logger.warning("console.transport.relay-error", metadata: ["code": .string(code), "peer": .string(peer.uuidString)])
                case .disconnected(let reason):
                    logger.warning("console.transport.disconnected", metadata: ["reason": .string(reason)])
                case .packetFailed(let kind, let peer, let reason):
                    logger.warning("console.transport.packet_failed", metadata: [
                        "kind": .string(kind), "peer": .string(peer.uuidString), "reason": .string(reason),
                    ])
                default: break
                }
            }
            await connection.setDisconnectHandler { [weak self] in await self?.transportDisconnected(id: id) }
            await connection.setHandler { [weak self] from, _, packet in
                guard let self else { return nil }
                if packet.kind == "core.http.response" { await self.complete(try ConsoleWire.decode(RemoteCoreResponse.self, from: packet.payload)) }
                else { try await self.receiveStream(senderID: from, packet: packet) }
                return nil
            }
        }
        savedPins[instance.hostDeviceID] = SavedPin(instance: instance, certificate: hostCertificate, organizationID: organizationID)
        UserDefaults.standard.set(try ConsoleWire.encode(savedPins), forKey: "sloppy.console.host-pins")
        connections[instance.hostDeviceID] = Connected(instance: instance, connection: connection, organizationID: organizationID, certificate: hostCertificate)
        await connection.updatePins(connections.mapValues { $0.certificate })
        try await connection.connect()
    }
    public func request(hostID: UUID, method: String, path: String, body: Data?, timeout: TimeInterval = 30) async throws -> RemoteCoreResponse {
        try Task.checkCancellation()
        guard timeout.isFinite, timeout > 0 else { throw URLError(.timedOut) }
        let request = RemoteCoreRequest(method: method, path: path, body: body)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                requests[request.requestID] = continuation
                requestTasks[request.requestID] = Task {
                    do {
                        if let requestTransport {
                            let response = try await requestTransport(hostID, request)
                            try Task.checkCancellation()
                            complete(response)
                        } else {
                            try await sendRequest(request, hostID: hostID)
                        }
                    } catch { fail(request.requestID, error: error) }
                }
                // Include proof renewal and connection setup in the caller's budget.
                requestTimeouts[request.requestID] = Task {
                    do { try await Task.sleep(for: .seconds(timeout)) }
                    catch { return }
                    fail(request.requestID, error: URLError(.timedOut))
                }
            }
        } onCancel: {
            Task { await self.fail(request.requestID, error: CancellationError()) }
        }
    }
    private func sendRequest(_ request: RemoteCoreRequest, hostID: UUID) async throws {
        try Task.checkCancellation()
        if connections[hostID] == nil, let saved = savedPins[hostID] {
            try await connect(instance: saved.instance, hostCertificate: saved.certificate, expectedFingerprint: saved.instance.hostCertificateFingerprint, organizationID: saved.organizationID)
        }
        try Task.checkCancellation()
        guard let connected = connections[hostID], let credential = ConsoleDeviceCredential.load() else { throw ConsoleTrustError.forbidden }
        let proof = try await ConsoleAccountClient.shared.proof(instanceID: connected.instance.id, deviceID: credential.deviceID, organizationID: connected.organizationID)
        try Task.checkCancellation()
        try await connected.connection.send(ConsoleRemotePacket(kind: "core.http", payload: ConsoleWire.encode(request), proof: proof), to: hostID)
    }
    public func openStream(hostID: UUID, kind: String, path: String) async throws -> (id: UUID, frames: AsyncStream<RemoteStreamFrame>) {
        if connections[hostID] == nil, let saved = savedPins[hostID] {
            try await connect(instance: saved.instance, hostCertificate: saved.certificate, expectedFingerprint: saved.instance.hostCertificateFingerprint, organizationID: saved.organizationID)
        }
        guard connections[hostID] != nil, streams.count < 20, ["session.stream", "terminal.stream", "preview.stream"].contains(kind) else { throw ConsoleTrustError.forbidden }
        let id = UUID(), pair = AsyncStream<RemoteStreamFrame>.makeStream(bufferingPolicy: .bufferingNewest(32))
        streams[id] = StreamEntry(hostID: hostID, kind: kind, continuation: pair.continuation)
        pair.continuation.onTermination = { [weak self] _ in Task { await self?.closeStream(id: id, hostID: hostID, kind: kind) } }
        do {
            try await sendStream(frame: RemoteStreamFrame(streamID: id, action: .open, path: path), hostID: hostID, kind: kind)
        } catch {
            streams.removeValue(forKey: id)?.continuation.finish()
            throw error
        }
        return (id, pair.stream)
    }
    public func sendStream(frame: RemoteStreamFrame, hostID: UUID, kind: String) async throws {
        if connections[hostID] == nil, let saved = savedPins[hostID] {
            try await connect(instance: saved.instance, hostCertificate: saved.certificate, expectedFingerprint: saved.instance.hostCertificateFingerprint, organizationID: saved.organizationID)
        }
        guard let connected = connections[hostID], let credential = ConsoleDeviceCredential.load() else { throw ConsoleTrustError.forbidden }
        let proof = try await ConsoleAccountClient.shared.proof(instanceID: connected.instance.id, deviceID: credential.deviceID, organizationID: connected.organizationID)
        try await connected.connection.send(ConsoleRemotePacket(kind: kind, payload: ConsoleWire.encode(frame), proof: proof), to: hostID)
        if frame.action == .close { streams.removeValue(forKey: frame.streamID)?.continuation.finish() }
    }
    private func closeStream(id: UUID, hostID: UUID, kind: String) async {
        // Finishing an already removed stream must not send a second close to
        // the host, which would reject it as an unknown stream.
        guard streams.removeValue(forKey: id) != nil else { return }
        try? await sendStream(frame: RemoteStreamFrame(streamID: id, action: .close), hostID: hostID, kind: kind)
    }
    private func receiveStream(senderID: UUID, packet: ConsoleRemotePacket) throws {
        let frame = try ConsoleWire.decode(RemoteStreamFrame.self, from: packet.payload)
        // Data already in flight may arrive after local cancellation or a
        // remote close. It must not tear down the shared Relay connection.
        guard let stream = streams[frame.streamID] else { return }
        guard stream.hostID == senderID, packet.kind == stream.kind + ".response" else { throw ConsoleTrustError.forbidden }
        if frame.action == .close { streams.removeValue(forKey: frame.streamID)?.continuation.finish() }
        else if case .dropped = stream.continuation.yield(frame) { streams.removeValue(forKey: frame.streamID)?.continuation.finish() }
    }
    private func transportDisconnected(id: UUID) {
        guard transportID == id else { return }
        finishPendingRequests()
    }
    private func finishPendingRequests() {
        for id in Array(requests.keys) { fail(id, error: RemoteTLSError.closed) }
        let activeStreams = streams; streams.removeAll()
        for stream in activeStreams.values { stream.continuation.finish() }
    }
    func recoverAfterHealthFailure(hostID: UUID) async -> Bool {
        guard connections[hostID] != nil else { return false }
        await disconnectAll()
        return true
    }
    public func disconnectAll() async {
        let previous = transport
        transport = nil
        transportID = nil
        connections.removeAll()
        finishPendingRequests()
        // A close from the retired socket must not clear requests on its replacement.
        await previous?.disconnect()
    }
    private func complete(_ response: RemoteCoreResponse) {
        guard let continuation = requests.removeValue(forKey: response.requestID) else { return }
        requestTasks.removeValue(forKey: response.requestID)?.cancel()
        requestTimeouts.removeValue(forKey: response.requestID)?.cancel()
        continuation.resume(returning: response)
    }
    private func fail(_ id: UUID, error: any Error) {
        guard let continuation = requests.removeValue(forKey: id) else { return }
        requestTasks.removeValue(forKey: id)?.cancel()
        requestTimeouts.removeValue(forKey: id)?.cancel()
        continuation.resume(throwing: error)
    }
}
