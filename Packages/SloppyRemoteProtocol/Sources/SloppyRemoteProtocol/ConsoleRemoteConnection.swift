import Crypto
import Foundation
import SloppyConsoleProtocol
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Connection lifecycle, reported so owners can log relay state without this
/// package depending on a logging backend.
public enum ConsoleRemoteEvent: Sendable {
    case connecting
    case connected(sessionExpiresIn: TimeInterval)
    case disconnected(reason: String)
    case sessionRenewal
    case relayError(code: String, peerID: UUID)
    case peerReady(UUID)
}

public struct ConsoleRemotePacket: Codable, Sendable {
    public var kind: String
    public var payload: Data
    public var proof: SignedInstanceAccessProof?
    public init(kind: String, payload: Data, proof: SignedInstanceAccessProof? = nil) { self.kind = kind; self.payload = payload; self.proof = proof }
}

protocol ConsoleRemoteTransport: Sendable {
    var messages: AsyncThrowingStream<Data, any Error> { get }
    func connect(url: URL, token: String) async throws
    func send(_ data: Data) async throws
    func close() async
}

extension RelayWebSocketConnection: ConsoleRemoteTransport {}

/// Pins are supplied by the local trust store or verified pairing, never by
/// the Relay directory. Every logical connection negotiates fresh TLS keys.
public actor ConsoleRemoteConnection {
    public typealias PacketHandler = @Sendable (UUID, Data, ConsoleRemotePacket) async throws -> ConsoleRemotePacket?
    private struct Peer {
        var sessionID: UUID
        var certificate: Data
        var tls: RemoteTLSChannel
        var sent: UInt64 = 0
        var received: UInt64 = 0
        var ready = false
    }
    private let deviceID: UUID
    private let signingPrivateKey: Data
    private let identity: RemoteTLSIdentity
    private let relayURL: URL
    private var pins: [UUID: Data]
    private var peers: [UUID: Peer] = [:]
    private var connectTask: Task<Void, any Error>?
    private var connectID: UUID?
    private var socket: (any ConsoleRemoteTransport)?
    private var socketID: UUID?
    private struct PendingSend {
        let id: UUID
        let task: Task<Void, any Error>
    }
    private var pendingSends: [UUID: PendingSend] = [:]
    /// Relay error frames name only the rejected envelope, so remember which
    /// peer each recent envelope was addressed to.
    private var envelopePeers: [UUID: UUID] = [:]
    private var envelopeOrder: [UUID] = []
    private var peerFailures: [UUID: RemoteTLSError] = [:]
    private let transportFactory: @Sendable () -> any ConsoleRemoteTransport
    private let authenticateDevice: (@Sendable () async throws -> ManagedDeviceSession)?
    private var receiveTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var handler: PacketHandler?
    private var disconnectHandler: (@Sendable () async -> Void)?
    private var eventHandler: (@Sendable (ConsoleRemoteEvent) -> Void)?
    private var closeReason = "local_disconnect"
    public init(deviceID: UUID, signingPrivateKey: Data, identity: RemoteTLSIdentity, relayURL: URL, pins: [UUID: Data]) {
        self.deviceID = deviceID; self.signingPrivateKey = signingPrivateKey; self.identity = identity; self.relayURL = relayURL; self.pins = pins
        self.transportFactory = { RelayWebSocketConnection() }
        self.authenticateDevice = nil
    }
    init(deviceID: UUID, signingPrivateKey: Data, identity: RemoteTLSIdentity, relayURL: URL, pins: [UUID: Data], transportFactory: @escaping @Sendable () -> any ConsoleRemoteTransport, authenticateDevice: @escaping @Sendable () async throws -> ManagedDeviceSession) {
        self.deviceID = deviceID; self.signingPrivateKey = signingPrivateKey; self.identity = identity; self.relayURL = relayURL; self.pins = pins
        self.transportFactory = transportFactory
        self.authenticateDevice = authenticateDevice
    }
    public var isConnected: Bool { socket != nil }
    public func setEventHandler(_ handler: @escaping @Sendable (ConsoleRemoteEvent) -> Void) { eventHandler = handler }
    public func setHandler(_ handler: @escaping PacketHandler) { self.handler = handler }
    public func setDisconnectHandler(_ handler: @escaping @Sendable () async -> Void) { disconnectHandler = handler }
    public func updatePins(_ pins: [UUID: Data]) async {
        self.pins = pins
        for (id, peer) in peers where pins[id] != peer.certificate {
            peers[id] = nil
            pendingSends.removeValue(forKey: id)?.task.cancel()
            await peer.tls.close()
        }
    }
    public func connect() async throws {
        if socket != nil { return }
        if let task = connectTask { try await task.value; return }
        let id = UUID()
        let task = Task { try await connectOnce() }
        connectID = id; connectTask = task
        do {
            try await task.value
            if connectID == id { connectTask = nil; connectID = nil }
        } catch {
            if connectID == id { connectTask = nil; connectID = nil }
            throw error
        }
    }
    private func connectOnce() async throws {
        if socket != nil { return }
        struct Challenge: Decodable { var id: UUID; var nonce: Data }
        struct Request: Encodable { var challengeID: UUID; var signature: Data }
        let session: ManagedDeviceSession
        if let authenticateDevice {
            session = try await authenticateDevice()
        } else {
            let challenge: Challenge = try await request("v1/device-auth/challenge", body: JSONEncoder().encode(["deviceID": deviceID.uuidString]))
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: signingPrivateKey)
            session = try await request("v1/device-auth/session", body: JSONEncoder().encode(Request(challengeID: challenge.id, signature: key.signature(for: challenge.nonce))))
        }
        try Task.checkCancellation()
        guard session.device.id == deviceID, session.device.signingPublicKey == identity.signingPublicKey else { throw RemoteTLSError.invalidPeer }
        eventHandler?(.connecting)
        let socket = transportFactory(); try await socket.connect(url: relayURL, token: session.token)
        do { try Task.checkCancellation() }
        catch { await socket.close(); throw error }
        let connectionID = UUID()
        self.socket = socket
        socketID = connectionID
        closeReason = "local_disconnect"
        eventHandler?(.connected(sessionExpiresIn: session.expiresAt.timeIntervalSinceNow))
        receiveTask = Task { [weak self] in
            var reason = "relay_closed"
            do { for try await data in socket.messages { try await self?.receive(data) } }
            catch { reason = "error: \(error)" }
            await self?.disconnect(ifCurrent: connectionID, reason: reason)
        }
        expiryTask = Task { [weak self] in
            // Renew a minute before the Relay session expires: a router drops a
            // destination whose token has lapsed, which looks like "host offline".
            let delay = max(1, session.expiresAt.timeIntervalSinceNow - 60)
            try? await Task.sleep(for: .seconds(delay)); if !Task.isCancelled { await self?.disconnect(ifCurrent: connectionID, reason: "session_renewal") }
        }
    }
    private func disconnect(ifCurrent id: UUID, reason: String) async {
        guard socketID == id else { return }
        closeReason = reason
        await disconnect()
    }
    public func disconnect() async {
        connectTask?.cancel(); connectTask = nil; connectID = nil
        socketID = nil
        for send in pendingSends.values { send.task.cancel() }; pendingSends.removeAll()
        receiveTask?.cancel(); receiveTask = nil; expiryTask?.cancel(); expiryTask = nil
        let previous = socket; socket = nil
        let previousPeers = peers; peers.removeAll(); peerFailures.removeAll(); envelopePeers.removeAll(); envelopeOrder.removeAll()
        if previous != nil { eventHandler?(.disconnected(reason: closeReason)); closeReason = "local_disconnect"; await disconnectHandler?() }
        await previous?.close()
        for peer in previousPeers.values { await peer.tls.close() }
    }
    public func send(_ packet: ConsoleRemotePacket, to peerID: UUID) async throws {
        // Actor reentrancy otherwise lets concurrent requests initialize different
        // sessions or emit encrypted records out of order for the same peer.
        let previous = pendingSends[peerID]?.task
        let id = UUID()
        let task = Task {
            _ = try? await previous?.value
            try Task.checkCancellation()
            try await sendOnce(packet, to: peerID)
        }
        pendingSends[peerID] = PendingSend(id: id, task: task)
        do {
            try await task.value
            if pendingSends[peerID]?.id == id { pendingSends[peerID] = nil }
        } catch {
            if pendingSends[peerID]?.id == id { pendingSends[peerID] = nil }
            throw error
        }
    }
    private func sendOnce(_ packet: ConsoleRemotePacket, to peerID: UUID) async throws {
        try await connect()
        if peers[peerID] == nil {
            guard let certificate = pins[peerID], peers.count < 20 else { throw RemoteTLSError.invalidPeer }
            let tls = try await RemoteTLSChannel(identity: identity, peerCertificate: certificate, isClient: true)
            try Task.checkCancellation()
            guard pins[peerID] == certificate else { await tls.close(); throw RemoteTLSError.invalidPeer }
            peers[peerID] = Peer(sessionID: UUID(), certificate: certificate, tls: tls)
            try await emit(tls.start(), to: peerID)
        }
        let deadline = Date().addingTimeInterval(15)
        while peers[peerID]?.ready != true {
            try Task.checkCancellation()
            if let failure = peerFailures.removeValue(forKey: peerID) { throw failure }
            guard socket != nil, peers[peerID] != nil, Date() < deadline else { throw RemoteTLSError.handshakeIncomplete }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard let peer = peers[peerID] else { throw RemoteTLSError.closed }
        try await emit(peer.tls.send(ConsoleWire.encode(packet)), to: peerID)
    }
    private func receive(_ data: Data) async throws {
        // The Relay envelope uses Foundation's default date representation;
        // ConsoleWire is only for the opaque TLS frame and inner packet.
        let decoder = JSONDecoder()
        if let control = try? decoder.decode(RemoteRelayControlFrame.self, from: data), control.type == "relay_error" {
            await handleRelayError(control)
            return
        }
        guard let envelope = try? decoder.decode(RemoteSealedEnvelope.self, from: data) else { return } // relay_ready
        guard envelope.kind == RemoteTLSFrame.kind, envelope.to == deviceID,
              let certificate = pins[envelope.from] else { throw RemoteTLSError.invalidPeer }
        let frame = try ConsoleWire.decode(RemoteTLSFrame.self, from: envelope.ciphertext)
        guard frame.version == 2, frame.from == envelope.from, frame.to == deviceID else { throw RemoteTLSError.invalidFrame }
        if let previous = peers[frame.from], previous.sessionID != frame.sessionID {
            // A reconnect starts at sequence zero with fresh TLS keys. Keep the
            // verified certificate pin; do not reuse the previous TLS channel.
            guard frame.sequence == 0 else { throw RemoteTLSError.invalidFrame }
            peers[frame.from] = nil
            await previous.tls.close()
        }
        if peers[frame.from] == nil {
            guard frame.sequence == 0, peers.count < 20 else { throw RemoteTLSError.invalidFrame }
            peers[frame.from] = Peer(sessionID: frame.sessionID, certificate: certificate, tls: try await RemoteTLSChannel(identity: identity, peerCertificate: certificate, isClient: false))
        }
        guard var peer = peers[frame.from], peer.sessionID == frame.sessionID, peer.received == frame.sequence, peer.certificate == certificate else { throw RemoteTLSError.invalidFrame }
        peer.received += 1; peers[frame.from] = peer
        let result = try await peer.tls.receive(frame.records)
        try await emit(result, to: frame.from)
        if result.handshakeComplete { peers[frame.from]?.ready = true; eventHandler?(.peerReady(frame.from)) }
        for message in result.messages {
            let packet = try ConsoleWire.decode(ConsoleRemotePacket.self, from: message)
            if let reply = try await handler?(frame.from, certificate, packet) { try await send(reply, to: frame.from) }
        }
    }
    private func handleRelayError(_ control: RemoteRelayControlFrame) async {
        guard let peerID = envelopePeers[control.envelopeID] else { return }
        eventHandler?(.relayError(code: control.code, peerID: peerID))
        peerFailures[peerID] = control.code == "host_offline" ? .hostOffline : .relayRejected
        // The peer never saw this TLS flight, so its session cannot continue.
        if let peer = peers.removeValue(forKey: peerID) { await peer.tls.close() }
        pendingSends.removeValue(forKey: peerID)?.task.cancel()
    }
    private func emit(_ result: RemoteTLSResult, to peerID: UUID) async throws {
        guard let socket else { throw RemoteTLSError.closed }
        // TLS splits large responses into small records. Batch them so a chat
        // transcript does not overflow the bounded WebSocket receive buffer.
        // One MiB leaves room for both layers of base64 in the Relay envelope.
        var batches: [Data] = []
        var batch = Data()
        for record in result.records {
            if !batch.isEmpty, batch.count + record.count > 1024 * 1024 {
                batches.append(batch)
                batch = Data()
            }
            batch.append(record)
        }
        if !batch.isEmpty { batches.append(batch) }
        for record in batches {
            guard var peer = peers[peerID] else { throw RemoteTLSError.closed }
            let frame = RemoteTLSFrame(sessionID: peer.sessionID, sequence: peer.sent, from: deviceID, to: peerID, records: record)
            peer.sent += 1; peers[peerID] = peer
            let envelope = RemoteSealedEnvelope(from: deviceID, to: peerID, kind: RemoteTLSFrame.kind, ciphertext: try ConsoleWire.encode(frame))
            envelopePeers[envelope.id] = peerID; envelopeOrder.append(envelope.id)
            if envelopeOrder.count > 256 { envelopePeers[envelopeOrder.removeFirst()] = nil }
            try await socket.send(JSONEncoder().encode(envelope))
        }
    }
    private func request<T: Decodable>(_ path: String, body: Data) async throws -> T {
        guard relayURL.scheme == "https" else { throw RemoteTLSError.invalidPeer }
        var request = URLRequest(url: relayURL.appendingPathComponent(path)); request.httpMethod = "POST"; request.httpBody = body; request.timeoutInterval = 15; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw RemoteTLSError.invalidPeer }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return try decoder.decode(T.self, from: data)
    }
}
