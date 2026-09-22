import Foundation
import ManagedRelayCore
import SloppyRemoteProtocol
import Testing

@Suite("Managed relay PostgreSQL integration", .serialized)
struct ManagedRelayPostgresIntegrationTests {
    @Test("invite consumption, tenant isolation, approval and revoke persist")
    func persistsEnrollmentAndPairing() async throws {
        guard let rawURL = ProcessInfo.processInfo.environment["SLOPPY_RELAY_TEST_DATABASE_URL"],
              let url = URL(string: rawURL) else { return }
        guard url.lastPathComponent.hasPrefix("sloppy_relay_integration") else {
            Issue.record("Integration tests require a dedicated sloppy_relay_integration database")
            return
        }

        let store = try ManagedRelayPostgresStore(
            databaseURL: url,
            pepper: Data(repeating: 37, count: 32)
        )
        let databaseTask = Task { await store.client.run() }
        defer { databaseTask.cancel() }
        try await store.migrate()

        let adminID = try await store.bootstrapAdminDevice(
            publicKey: RemoteDeviceKeys().signingPublicKey,
            name: "Test Admin"
        )
        let firstInvite = try await store.createServiceInvite(
            adminDeviceID: adminID,
            expiresAt: Date().addingTimeInterval(60)
        )
        let secondInvite = try await store.createServiceInvite(
            adminDeviceID: adminID,
            expiresAt: Date().addingTimeInterval(60)
        )
        let firstKeys = RemoteDeviceKeys()
        let secondKeys = RemoteDeviceKeys()
        let first = try await store.consumeServiceInvite(
            firstInvite,
            hostName: "Same Node",
            signingPublicKey: firstKeys.signingPublicKey,
            encryptionPublicKey: firstKeys.encryptionPublicKey,
            encryptionKeySignature: firstKeys.signEncryptionKey()
        )
        let second = try await store.consumeServiceInvite(
            secondInvite,
            hostName: "Same Node",
            signingPublicKey: secondKeys.signingPublicKey,
            encryptionPublicKey: secondKeys.encryptionPublicKey,
            encryptionKeySignature: secondKeys.signEncryptionKey()
        )
        #expect(first.space.id != second.space.id)
        #expect(try await store.devices(spaceID: first.space.id).map(\.id) == [first.device.id])
        #expect(try await store.devices(spaceID: second.space.id).map(\.id) == [second.device.id])
        await #expect(throws: Error.self) {
            _ = try await store.consumeServiceInvite(
                firstInvite,
                hostName: "Replay",
                signingPublicKey: firstKeys.signingPublicKey,
                encryptionPublicKey: firstKeys.encryptionPublicKey,
                encryptionKeySignature: firstKeys.signEncryptionKey()
            )
        }
        let coordinator = ManagedRelayCoordinator(
            store: store,
            publicURL: URL(string: "https://relay-test.sloppy.team")!
        )
        let challenge = try await coordinator.challenge(deviceID: first.device.id)
        let hostSession = try await coordinator.authenticate(
            challengeID: challenge.id,
            signature: firstKeys.sign(challenge.nonce)
        )
        let code = try await coordinator.createPairing(token: hostSession.token, kind: .mobile)
        let mobileKeys = RemoteDeviceKeys()
        let mobileID = UUID()
        try await coordinator.claimPairing(
            id: code.pairingID,
            nonce: code.claimNonce,
            deviceID: mobileID,
            kind: .mobile,
            name: "Phone",
            signingPublicKey: mobileKeys.signingPublicKey,
            encryptionPublicKey: mobileKeys.encryptionPublicKey,
            encryptionKeySignature: mobileKeys.signEncryptionKey(),
            claimSignature: mobileKeys.sign(
                Data("sloppy-remote-pair-v1:\(code.pairingID):\(code.claimNonce)".utf8)
            )
        )
        #expect(try await coordinator.pendingPairings(token: hostSession.token).count == 1)
        #expect(try await coordinator.decidePairing(
            id: code.pairingID,
            token: hostSession.token,
            approve: true
        )?.id == mobileID)
        let mobileChallenge = try await coordinator.challenge(deviceID: mobileID)
        let mobileSession = try await coordinator.authenticate(
            challengeID: mobileChallenge.id,
            signature: mobileKeys.sign(mobileChallenge.nonce)
        )
        #expect(try await coordinator.listDevices(token: mobileSession.token).count == 2)

        let hostPairing = try await coordinator.createPairing(token: hostSession.token, kind: .host)
        let extraHostKeys = RemoteDeviceKeys()
        let extraHostID = UUID()
        try await coordinator.claimPairing(
            id: hostPairing.pairingID,
            nonce: hostPairing.claimNonce,
            deviceID: extraHostID,
            kind: .host,
            name: "Second Mac",
            signingPublicKey: extraHostKeys.signingPublicKey,
            encryptionPublicKey: extraHostKeys.encryptionPublicKey,
            encryptionKeySignature: extraHostKeys.signEncryptionKey(),
            claimSignature: extraHostKeys.sign(
                Data("sloppy-remote-pair-v1:\(hostPairing.pairingID):\(hostPairing.claimNonce)".utf8)
            )
        )
        #expect(try await coordinator.decidePairing(
            id: hostPairing.pairingID,
            token: hostSession.token,
            approve: true
        )?.id == extraHostID)
        #expect(try await coordinator.listDevices(token: mobileSession.token).count == 3)

        let rotated = try await coordinator.rotateRecoveryCodes(token: hostSession.token)
        #expect(rotated.count == 10)
        let obsolete = try #require(first.recoveryCodes.first)
        let replacementKeys = RemoteDeviceKeys()
        await #expect(throws: Error.self) {
            _ = try await store.recover(
                spaceID: first.space.id,
                code: obsolete,
                name: "Obsolete code",
                signingPublicKey: replacementKeys.signingPublicKey,
                encryptionPublicKey: replacementKeys.encryptionPublicKey,
                encryptionKeySignature: replacementKeys.signEncryptionKey()
            )
        }
        let replacementCode = try #require(rotated.first)
        let replacement = try await store.recover(
            spaceID: first.space.id,
            code: replacementCode,
            name: "Recovered Mac",
            signingPublicKey: replacementKeys.signingPublicKey,
            encryptionPublicKey: replacementKeys.encryptionPublicKey,
            encryptionKeySignature: replacementKeys.signEncryptionKey()
        )
        #expect(replacement.principalID == first.device.principalID)
        await #expect(throws: Error.self) {
            _ = try await store.recover(
                spaceID: first.space.id,
                code: replacementCode,
                name: "Replay recovery",
                signingPublicKey: replacementKeys.signingPublicKey,
                encryptionPublicKey: replacementKeys.encryptionPublicKey,
                encryptionKeySignature: replacementKeys.signEncryptionKey()
            )
        }

        let hostSink = RelayFrameSink()
        let mobileSink = RelayFrameSink()
        let hostConnection = try await coordinator.attach(
            token: hostSession.token,
            send: { data in await hostSink.append(data); return true },
            close: { await hostSink.close() }
        )
        let mobileConnection = try await coordinator.attach(
            token: mobileSession.token,
            send: { data in await mobileSink.append(data); return true },
            close: { await mobileSink.close() }
        )
        var envelope = RemoteSealedEnvelope(
            from: mobileID,
            to: first.device.id,
            kind: "core.http",
            ciphertext: Data()
        )
        let secret = Data(#"{"path":"/v1/projects","method":"GET"}"#.utf8)
        envelope.ciphertext = try mobileKeys.seal(
            secret,
            envelope: envelope,
            recipientPublicKey: first.device.encryptionPublicKey
        )
        try await coordinator.route(
            envelope,
            senderID: mobileID,
            connectionID: mobileConnection.connectionID
        )
        let delivered = try #require(await hostSink.frames().first)
        let forwarded = try JSONDecoder().decode(RemoteSealedEnvelope.self, from: delivered)
        #expect(forwarded.ciphertext != secret)
        #expect(try firstKeys.open(
            forwarded,
            senderPublicKey: mobileKeys.encryptionPublicKey
        ) == secret)
        await #expect(throws: ManagedRelayError.replay) {
            try await coordinator.route(
                envelope, senderID: mobileID,
                connectionID: mobileConnection.connectionID
            )
        }
        var crossSpace = envelope
        crossSpace.id = UUID()
        crossSpace.to = second.device.id
        await #expect(throws: ManagedRelayError.crossSpaceRoute) {
            try await coordinator.route(
                crossSpace, senderID: mobileID,
                connectionID: mobileConnection.connectionID
            )
        }
        let metrics = await coordinator.metrics()
        #expect(metrics.pairingsApproved == 2)
        #expect(metrics.crossTenantDenials == 1)
        #expect(metrics.routedEnvelopes == 1)

        try await coordinator.revokeDevice(id: mobileID, token: hostSession.token)
        #expect(await mobileSink.isClosed())
        await #expect(throws: ManagedRelayError.unauthorized) {
            _ = try await coordinator.authorize(token: mobileSession.token)
        }
        await #expect(throws: ManagedRelayError.unauthorized) {
            try await coordinator.route(
                envelope, senderID: mobileID,
                connectionID: mobileConnection.connectionID
            )
        }
        await coordinator.detach(deviceID: first.device.id, connectionID: hostConnection.connectionID)
        let audit = try await store.listAuditEvents()
        #expect(audit.contains { $0.action == "space.enroll" && $0.spaceID == first.space.id })
        #expect(audit.contains { $0.action == "pairing.approve" && $0.targetID == mobileID })
        #expect(audit.contains { $0.action == "recovery_codes.rotate" && $0.spaceID == first.space.id })
        #expect(audit.contains { $0.action == "space.recover" && $0.targetID == replacement.id })
        #expect(audit.contains { $0.action == "device.revoke" && $0.targetID == mobileID })
    }
}

private actor RelayFrameSink {
    private var received: [Data] = []
    private var closed = false

    func append(_ data: Data) { received.append(data) }
    func frames() -> [Data] { received }
    func close() { closed = true }
    func isClosed() -> Bool { closed }
}
