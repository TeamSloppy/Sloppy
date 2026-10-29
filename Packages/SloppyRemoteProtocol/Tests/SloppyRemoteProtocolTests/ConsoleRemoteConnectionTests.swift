import Crypto
import Foundation
import SloppyConsoleProtocol
import Testing
@testable import SloppyRemoteProtocol

@Suite("Console peer transport", .serialized)
struct ConsoleRemoteConnectionTests {
    @Test func firstHealthRequestUsesTheRelayEnvelopeFormat() async throws {
        let fixture = try Fixture()
        await fixture.host.setHandler { _, _, packet in
            let request = try ConsoleWire.decode(RemoteCoreRequest.self, from: packet.payload)
            #expect(request.method == "GET")
            #expect(request.path == "/health")
            let response = RemoteCoreResponse(requestID: request.requestID, status: 200, body: Data("{\"ok\":true}".utf8))
            return ConsoleRemotePacket(kind: "core.http.response", payload: try ConsoleWire.encode(response))
        }
        await fixture.client.setHandler { _, _, packet in
            #expect(packet.kind == "core.http.response")
            let response = try ConsoleWire.decode(RemoteCoreResponse.self, from: packet.payload)
            #expect(response.status == 200)
            await fixture.replies.append(response.body)
            return nil
        }
        do {
            try await fixture.host.connect()
            let request = RemoteCoreRequest(method: "GET", path: "/health", body: nil)
            try await fixture.client.send(ConsoleRemotePacket(kind: "core.http", payload: ConsoleWire.encode(request)), to: fixture.hostID)
            try await fixture.replies.waitForCount(1)
            #expect(await fixture.replies.values == [Data("{\"ok\":true}".utf8)])
        } catch {
            await fixture.close()
            throw error
        }
        await fixture.close()
    }

    @Test func concurrentRequestsShareOneTLSHandshakeAndDeliverAllReplies() async throws {
        let fixture = try Fixture()
        await fixture.host.setHandler { _, _, packet in
            ConsoleRemotePacket(kind: "reply", payload: packet.payload)
        }
        await fixture.client.setHandler { _, _, packet in
            await fixture.replies.append(packet.payload)
            return nil
        }
        try await fixture.host.connect()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<16 {
                group.addTask {
                    try await fixture.client.send(ConsoleRemotePacket(kind: "request", payload: Data("request-\(index)".utf8)), to: fixture.hostID)
                }
            }
            try await group.waitForAll()
        }
        try await fixture.replies.waitForCount(16)
        let replies = await fixture.replies.values
        #expect(Set(replies).count == 16)
        let frames = await fixture.relay.frames.filter { $0.from == fixture.clientID }
        #expect(Set(frames.map(\.sessionID)).count == 1)
        #expect(frames.map(\.sequence) == Array(0..<UInt64(frames.count)))
        await fixture.close()
    }

    @Test func reconnectRenegotiatesTLSWhileHostRetainsThePreviousPeer() async throws {
        let fixture = try Fixture()
        await fixture.host.setHandler { _, _, packet in
            ConsoleRemotePacket(kind: "reply", payload: packet.payload)
        }
        await fixture.client.setHandler { _, _, packet in
            await fixture.replies.append(packet.payload)
            return nil
        }
        try await fixture.host.connect()
        try await fixture.client.send(ConsoleRemotePacket(kind: "request", payload: Data("before".utf8)), to: fixture.hostID)
        try await fixture.replies.waitForCount(1)
        await fixture.client.disconnect()
        try await fixture.client.send(ConsoleRemotePacket(kind: "request", payload: Data("after".utf8)), to: fixture.hostID)
        try await fixture.replies.waitForCount(2)
        #expect(await fixture.replies.values == [Data("before".utf8), Data("after".utf8)])
        let starts = await fixture.relay.frames.filter { $0.from == fixture.clientID && $0.sequence == 0 }
        #expect(starts.count == 2)
        #expect(Set(starts.map(\.sessionID)).count == 2)
        await fixture.close()
    }

    @Test(arguments: [false, true])
    func simultaneousRequestsNegotiateOnePeerSession(hostHasLowerID: Bool) async throws {
        let lower = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let higher = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let fixture = try Fixture(clientID: hostHasLowerID ? higher : lower, hostID: hostHasLowerID ? lower : higher)
        await fixture.host.setHandler { _, _, packet in await fixture.replies.append(packet.payload); return nil }
        await fixture.client.setHandler { _, _, packet in await fixture.replies.append(packet.payload); return nil }
        try await fixture.host.connect()
        try await fixture.client.connect()
        do {
            async let host: Void = fixture.host.send(ConsoleRemotePacket(kind: "request", payload: Data("host".utf8)), to: fixture.clientID)
            async let client: Void = fixture.client.send(ConsoleRemotePacket(kind: "request", payload: Data("client".utf8)), to: fixture.hostID)
            _ = try await (host, client)
            try await fixture.replies.waitForCount(2)
            #expect(Set(await fixture.replies.values) == [Data("host".utf8), Data("client".utf8)])
            let established = await fixture.relay.frames.filter { $0.sequence > 0 }
            #expect(Set(established.map(\.sessionID)).count == 1)
        } catch {
            await fixture.close()
            throw error
        }
        await fixture.close()
    }

    @Test func delayedRelayErrorDoesNotInvalidateTheReplacementSession() async throws {
        let fixture = try Fixture()
        await fixture.host.setHandler { _, _, packet in ConsoleRemotePacket(kind: "reply", payload: packet.payload) }
        await fixture.client.setHandler { _, _, packet in await fixture.replies.append(packet.payload); return nil }
        try await fixture.host.connect()
        try await fixture.client.send(ConsoleRemotePacket(kind: "request", payload: Data("before".utf8)), to: fixture.hostID)
        try await fixture.replies.waitForCount(1)
        let oldEnvelope = try #require(await fixture.relay.envelopes.first { $0.from == fixture.hostID })
        await fixture.client.disconnect()
        try await fixture.client.send(ConsoleRemotePacket(kind: "request", payload: Data("after".utf8)), to: fixture.hostID)
        try await fixture.replies.waitForCount(2)
        try await fixture.relay.sendRelayError(to: fixture.hostID, envelopeID: oldEnvelope.id)
        try await fixture.client.send(ConsoleRemotePacket(kind: "request", payload: Data("still connected".utf8)), to: fixture.hostID)
        try await fixture.replies.waitForCount(3)
        #expect(await fixture.replies.values.last == Data("still connected".utf8))
        #expect(await fixture.host.isConnected)
        #expect(await fixture.relay.connectionAttempts[fixture.hostID] == 1)
        await fixture.close()
    }

    @Test func reconnectDoesNotRetagAnInFlightSnapshotWithTheNewSession() async throws {
        let fixture = try Fixture()
        await fixture.host.setHandler { _, _, packet in
            ConsoleRemotePacket(kind: "reply", payload: packet.payload)
        }
        await fixture.client.setHandler { _, _, packet in
            if packet.kind == "reply" { await fixture.replies.append(packet.payload) }
            return nil
        }
        try await fixture.host.connect()
        try await fixture.client.send(ConsoleRemotePacket(kind: "request", payload: Data("before".utf8)), to: fixture.hostID)
        try await fixture.replies.waitForCount(1)
        await fixture.relay.pauseNextLargeFrame(from: fixture.hostID)
        let snapshot = Task {
            try await fixture.host.send(ConsoleRemotePacket(kind: "snapshot", payload: Data(repeating: 97, count: 1_700_000)), to: fixture.clientID)
        }
        try await fixture.relay.waitForPausedFrame()
        await fixture.client.disconnect()
        try await fixture.client.send(ConsoleRemotePacket(kind: "request", payload: Data("after".utf8)), to: fixture.hostID)
        await fixture.relay.resumePausedFrame()
        await #expect(throws: RemoteTLSError.self) { try await snapshot.value }
        try await fixture.replies.waitForCount(2)
        #expect(await fixture.replies.values == [Data("before".utf8), Data("after".utf8)])
        #expect(await fixture.host.isConnected)
        #expect(await fixture.client.isConnected)
        #expect(await fixture.relay.connectionAttempts[fixture.hostID] == 1)
        await fixture.close()
    }

    @Test(arguments: [512 * 1024, 1_700_000])
    func largeChatResponseBatchesTLSRecordsWithinTheRelayFrameLimit(byteCount: Int) async throws {
        let fixture = try Fixture()
        let transcript = Data(repeating: 97, count: byteCount)
        await fixture.host.setHandler { _, _, _ in
            ConsoleRemotePacket(kind: "reply", payload: transcript)
        }
        await fixture.client.setHandler { _, _, packet in
            await fixture.replies.append(packet.payload)
            return nil
        }
        try await fixture.host.connect()
        try await fixture.client.send(ConsoleRemotePacket(kind: "request", payload: Data()), to: fixture.hostID)
        try await fixture.replies.waitForCount(1)
        #expect(await fixture.replies.values == [transcript])
        let responseFrames = await fixture.relay.frames.filter { $0.from == fixture.hostID }
        #expect(responseFrames.count < 16)
        #expect(responseFrames.allSatisfy { $0.records.count <= 1024 * 1024 })
        await fixture.close()
    }

    @Test(arguments: [false, true])
    func failedResponsePreservesThePeerSession(handlerThrows: Bool) async throws {
        let fixture = try Fixture()
        await fixture.host.setHandler { _, _, packet in
            let request = try ConsoleWire.decode(RemoteCoreRequest.self, from: packet.payload)
            if request.path == "/large" {
                if handlerThrows { throw RemoteTLSError.invalidPeer }
                let response = RemoteCoreResponse(requestID: request.requestID, status: 200,
                    body: Data(repeating: 97, count: 2_500_000))
                return ConsoleRemotePacket(kind: "core.http.response", payload: try ConsoleWire.encode(response))
            }
            let response = RemoteCoreResponse(requestID: request.requestID, status: 200, body: Data("ok".utf8))
            return ConsoleRemotePacket(kind: "core.http.response", payload: try ConsoleWire.encode(response))
        }
        await fixture.client.setHandler { _, _, packet in
            await fixture.replies.append(packet.payload)
            return nil
        }
        try await fixture.host.connect()
        let large = RemoteCoreRequest(method: "GET", path: "/large")
        try await fixture.client.send(ConsoleRemotePacket(kind: "core.http", payload: ConsoleWire.encode(large)), to: fixture.hostID)
        try await fixture.replies.waitForCount(1)
        let first = try ConsoleWire.decode(RemoteCoreResponse.self, from: #require(await fixture.replies.values.first))
        #expect(first.requestID == large.requestID)
        #expect(first.status == (handlerThrows ? 500 : 413))
        let body = try JSONDecoder().decode([String: String].self, from: first.body)
        #expect(body["error"] == (handlerThrows ? "remote_request_failed" : "remote_response_too_large"))
        let health = RemoteCoreRequest(method: "GET", path: "/health")
        try await fixture.client.send(ConsoleRemotePacket(kind: "core.http", payload: ConsoleWire.encode(health)), to: fixture.hostID)
        try await fixture.replies.waitForCount(2)
        let second = try ConsoleWire.decode(RemoteCoreResponse.self, from: #require(await fixture.replies.values.last))
        #expect(second.requestID == health.requestID)
        #expect(second.status == 200)
        #expect(await fixture.host.isConnected)
        #expect(await fixture.client.isConnected)
        #expect(await fixture.relay.connectionAttempts[fixture.hostID] == 1)
        #expect(await fixture.relay.connectionAttempts[fixture.clientID] == 1)
        let starts = await fixture.relay.frames.filter { $0.from == fixture.clientID && $0.sequence == 0 }
        #expect(starts.count == 1)
        await fixture.close()
    }

    @Test func relayLossNotifiesTheOwnerAndTheNextRequestReconnects() async throws {
        let fixture = try Fixture()
        let disconnects = PacketMailbox()
        await fixture.client.setDisconnectHandler { await disconnects.append(Data()) }
        await fixture.host.setHandler { _, _, packet in ConsoleRemotePacket(kind: "reply", payload: packet.payload) }
        await fixture.client.setHandler { _, _, packet in
            await fixture.replies.append(packet.payload)
            return nil
        }
        try await fixture.host.connect()
        try await fixture.client.send(ConsoleRemotePacket(kind: "request", payload: Data("before".utf8)), to: fixture.hostID)
        try await fixture.replies.waitForCount(1)
        await fixture.relay.dropConnection(deviceID: fixture.clientID)
        try await disconnects.waitForCount(1)
        try await fixture.client.send(ConsoleRemotePacket(kind: "request", payload: Data("after".utf8)), to: fixture.hostID)
        try await fixture.replies.waitForCount(2)
        #expect(await fixture.replies.values == [Data("before".utf8), Data("after".utf8)])
        await fixture.close()
    }

    @Test func failedConnectionAllowsTheNextRequestToReconnect() async throws {
        let fixture = try Fixture()
        await fixture.relay.failNextConnection(deviceID: fixture.clientID)
        await fixture.host.setHandler { _, _, packet in ConsoleRemotePacket(kind: "reply", payload: packet.payload) }
        await fixture.client.setHandler { _, _, packet in
            await fixture.replies.append(packet.payload)
            return nil
        }
        do {
            try await fixture.host.connect()
            await #expect(throws: RemoteTLSError.self) {
                try await fixture.client.send(ConsoleRemotePacket(kind: "request", payload: Data("failed".utf8)), to: fixture.hostID)
            }
            #expect(await fixture.client.isConnected == false)
            try await fixture.client.send(ConsoleRemotePacket(kind: "request", payload: Data("recovered".utf8)), to: fixture.hostID)
            try await fixture.replies.waitForCount(1)
            #expect(await fixture.replies.values == [Data("recovered".utf8)])
            #expect(await fixture.relay.connectionAttempts[fixture.clientID] == 2)
        } catch {
            await fixture.close()
            throw error
        }
        await fixture.close()
    }

    @Test func revokedPinCannotSendOnAnEstablishedChannel() async throws {
        let fixture = try Fixture()
        await fixture.host.setHandler { _, _, packet in
            await fixture.replies.append(packet.payload)
            return nil
        }
        try await fixture.host.connect()
        try await fixture.client.send(ConsoleRemotePacket(kind: "request", payload: Data("allowed".utf8)), to: fixture.hostID)
        try await fixture.replies.waitForCount(1)
        await fixture.client.updatePins([:])
        await #expect(throws: RemoteTLSError.self) {
            try await fixture.client.send(ConsoleRemotePacket(kind: "request", payload: Data("revoked".utf8)), to: fixture.hostID)
        }
        #expect(await fixture.replies.values == [Data("allowed".utf8)])
        await fixture.close()
    }
}

private struct Fixture: Sendable {
    let relay = MemoryRelay()
    let replies = PacketMailbox()
    let clientID: UUID
    let hostID: UUID
    let client: ConsoleRemoteConnection
    let host: ConsoleRemoteConnection

    init(clientID: UUID = UUID(), hostID: UUID = UUID()) throws {
        self.clientID = clientID; self.hostID = hostID
        let clientKey = Curve25519.Signing.PrivateKey()
        let hostKey = Curve25519.Signing.PrivateKey()
        let clientIdentity = try RemoteTLSIdentity(signingPrivateKey: clientKey.rawRepresentation, deviceID: clientID)
        let hostIdentity = try RemoteTLSIdentity(signingPrivateKey: hostKey.rawRepresentation, deviceID: hostID)
        let relay = relay
        client = Self.connection(id: clientID, key: clientKey.rawRepresentation, identity: clientIdentity,
                                 pins: [hostID: hostIdentity.certificateDER], relay: relay)
        host = Self.connection(id: hostID, key: hostKey.rawRepresentation, identity: hostIdentity,
                               pins: [clientID: clientIdentity.certificateDER], relay: relay)
    }

    private static func connection(id: UUID, key: Data, identity: RemoteTLSIdentity, pins: [UUID: Data], relay: MemoryRelay) -> ConsoleRemoteConnection {
        ConsoleRemoteConnection(deviceID: id, signingPrivateKey: key, identity: identity,
            relayURL: URL(string: "https://relay.test")!, pins: pins,
            transportFactory: { MemoryTransport(deviceID: id, relay: relay) },
            authenticateDevice: {
                ManagedDeviceSession(device: RemoteDevice(id: id, spaceID: UUID(), principalID: UUID(), kind: .host,
                    name: "Test", signingPublicKey: identity.signingPublicKey, encryptionPublicKey: Data(),
                    encryptionKeySignature: Data(), capabilities: []), token: "test", expiresAt: Date().addingTimeInterval(300))
            })
    }

    func close() async { await client.disconnect(); await host.disconnect() }
}

private actor PacketMailbox {
    var values: [Data] = []
    func append(_ data: Data) { values.append(data) }
    func waitForCount(_ count: Int) async throws {
        let deadline = Date().addingTimeInterval(5)
        while values.count < count, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(values.count == count)
    }
}

private actor MemoryRelay {
    private var connections: [UUID: (UUID, AsyncThrowingStream<Data, any Error>.Continuation)] = [:]
    private var failingConnections: Set<UUID> = []
    var connectionAttempts: [UUID: Int] = [:]
    var frames: [RemoteTLSFrame] = []
    var envelopes: [RemoteSealedEnvelope] = []
    func sendRelayError(to deviceID: UUID, envelopeID: UUID) throws {
        guard let target = connections[deviceID] else { throw RemoteTLSError.closed }
        let data = try JSONEncoder().encode(RemoteRelayControlFrame(envelopeID: envelopeID, code: "host_offline"))
        if case .dropped = target.1.yield(data) { throw RemoteTLSError.oversizedMessage }
    }
    private var pausedSource: UUID?
    private var pausedFrame: CheckedContinuation<Void, Never>?
    func pauseNextLargeFrame(from deviceID: UUID) { pausedSource = deviceID }
    func waitForPausedFrame() async throws {
        let deadline = Date().addingTimeInterval(5)
        while pausedFrame == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(pausedFrame != nil)
    }
    func resumePausedFrame() { pausedFrame?.resume(); pausedFrame = nil }
    func failNextConnection(deviceID: UUID) { failingConnections.insert(deviceID) }
    func register(deviceID: UUID, socketID: UUID, continuation: AsyncThrowingStream<Data, any Error>.Continuation) throws {
        connectionAttempts[deviceID, default: 0] += 1
        if failingConnections.remove(deviceID) != nil { throw RemoteTLSError.closed }
        connections[deviceID] = (socketID, continuation)
    }
    func close(deviceID: UUID, socketID: UUID) {
        if connections[deviceID]?.0 == socketID { connections.removeValue(forKey: deviceID)?.1.finish() }
    }
    func dropConnection(deviceID: UUID) {
        connections.removeValue(forKey: deviceID)?.1.finish()
    }
    func route(_ data: Data) async throws {
        // Match RelayWebSocketHandler and ManagedRelayCoordinator: the outer
        // envelope uses Foundation's default date encoding in both directions.
        let envelope = try JSONDecoder().decode(RemoteSealedEnvelope.self, from: data)
        let frame = try ConsoleWire.decode(RemoteTLSFrame.self, from: envelope.ciphertext)
        frames.append(frame)
        envelopes.append(envelope)
        guard let target = connections[envelope.to] else { throw RemoteTLSError.closed }
        if case .dropped = target.1.yield(try JSONEncoder().encode(envelope)) { throw RemoteTLSError.oversizedMessage }
        if envelope.from == pausedSource, frame.records.count > 1_000_000 {
            pausedSource = nil
            await withCheckedContinuation { pausedFrame = $0 }
        }
    }
}

private actor MemoryTransport: ConsoleRemoteTransport {
    nonisolated let messages: AsyncThrowingStream<Data, any Error>
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
    private let deviceID: UUID
    private let socketID = UUID()
    private let relay: MemoryRelay
    init(deviceID: UUID, relay: MemoryRelay) {
        self.deviceID = deviceID; self.relay = relay
        let pair = AsyncThrowingStream<Data, any Error>.makeStream(bufferingPolicy: .bufferingNewest(16))
        messages = pair.stream; continuation = pair.continuation
    }
    func connect(url: URL, token: String) async throws {
        try await relay.register(deviceID: deviceID, socketID: socketID, continuation: continuation)
    }
    func send(_ data: Data) async throws { try await relay.route(data) }
    func close() async {
        continuation.finish()
        await relay.close(deviceID: deviceID, socketID: socketID)
    }
}
