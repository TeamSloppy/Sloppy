import Foundation
import ManagedRelayCore
import SloppyRemoteProtocol
import Testing

@Suite("Managed relay")
struct ManagedRelayTests {
    @Test("personal spaces isolate devices with matching names and route IDs")
    func isolatesSpaces() async throws {
        let relay = ManagedRelay(pepper: Data(repeating: 7, count: 32))
        let firstKeys = RemoteDeviceKeys()
        let secondKeys = RemoteDeviceKeys()
        let firstInvite = try await relay.createServiceInvite(expiresAt: Date().addingTimeInterval(60))
        let secondInvite = try await relay.createServiceInvite(expiresAt: Date().addingTimeInterval(60))
        let first = try await relay.enroll(
            invite: firstInvite,
            hostName: "same-name",
            signingPublicKey: firstKeys.signingPublicKey,
            encryptionPublicKey: firstKeys.encryptionPublicKey,
            encryptionKeySignature: firstKeys.signEncryptionKey()
        )
        let second = try await relay.enroll(
            invite: secondInvite,
            hostName: "same-name",
            signingPublicKey: secondKeys.signingPublicKey,
            encryptionPublicKey: secondKeys.encryptionPublicKey,
            encryptionKeySignature: secondKeys.signEncryptionKey()
        )
        let challenge = try await relay.challenge(deviceID: first.device.id)
        let session = try await relay.authenticate(
            challengeID: challenge.id,
            signature: firstKeys.sign(challenge.nonce)
        )
        let listed = try await relay.listDevices(token: session.token)
        #expect(listed.map(\.id) == [first.device.id])
        try await relay.setOnline(deviceID: second.device.id, online: true)
        let envelope = RemoteSealedEnvelope(
            from: first.device.id,
            to: second.device.id,
            kind: "core.http",
            ciphertext: Data([1, 2, 3])
        )
        await #expect(throws: ManagedRelayError.crossSpaceRoute) {
            try await relay.route(envelope, authenticatedSenderID: first.device.id)
        }
    }

    @Test("QR claim waits for host approval")
    func requiresHostApproval() async throws {
        let relay = ManagedRelay(pepper: Data(repeating: 8, count: 32))
        let hostKeys = RemoteDeviceKeys()
        let mobileKeys = RemoteDeviceKeys()
        let invite = try await relay.createServiceInvite(expiresAt: Date().addingTimeInterval(60))
        let host = try await relay.enroll(
            invite: invite,
            hostName: "Mac",
            signingPublicKey: hostKeys.signingPublicKey,
            encryptionPublicKey: hostKeys.encryptionPublicKey,
            encryptionKeySignature: hostKeys.signEncryptionKey()
        )
        let challenge = try await relay.challenge(deviceID: host.device.id)
        let session = try await relay.authenticate(
            challengeID: challenge.id,
            signature: hostKeys.sign(challenge.nonce)
        )
        let code = try await relay.createPairing(
            token: session.token,
            kind: .mobile,
            relayURL: URL(string: "https://relay.sloppy.team")!
        )
        let mobileID = UUID()
        let pending = try await relay.claimPairing(
            id: code.pairingID,
            nonce: code.claimNonce,
            deviceID: mobileID,
            name: "iPhone",
            signingPublicKey: mobileKeys.signingPublicKey,
            encryptionPublicKey: mobileKeys.encryptionPublicKey,
            encryptionKeySignature: mobileKeys.signEncryptionKey(),
            claimSignature: mobileKeys.sign(Data("sloppy-remote-pair-v1:\(code.pairingID):\(code.claimNonce)".utf8))
        )
        #expect(pending.status == .pending)
        await #expect(throws: ManagedRelayError.unauthorized) {
            _ = try await relay.challenge(deviceID: mobileID)
        }
        let approved = try await relay.decidePairing(
            id: code.pairingID,
            token: session.token,
            approve: true
        )
        #expect(approved?.id == mobileID)
        _ = try await relay.challenge(deviceID: mobileID)
    }

    @Test("sealed payload opens only with the recipient key and bound route")
    func keepsPayloadEndToEndEncrypted() throws {
        let sender = RemoteDeviceKeys()
        let recipient = RemoteDeviceKeys()
        let unrelated = RemoteDeviceKeys()
        var envelope = RemoteSealedEnvelope(
            from: UUID(),
            to: UUID(),
            kind: "core.http",
            ciphertext: Data()
        )
        let plaintext = Data(#"{"method":"POST","path":"/v1/agents"}"#.utf8)
        envelope.ciphertext = try sender.seal(
            plaintext,
            envelope: envelope,
            recipientPublicKey: recipient.encryptionPublicKey
        )

        #expect(try recipient.open(
            envelope,
            senderPublicKey: sender.encryptionPublicKey
        ) == plaintext)
        #expect(throws: Error.self) {
            _ = try unrelated.open(envelope, senderPublicKey: sender.encryptionPublicKey)
        }
        var retargeted = envelope
        retargeted.to = UUID()
        #expect(throws: Error.self) {
            _ = try recipient.open(retargeted, senderPublicKey: sender.encryptionPublicKey)
        }
    }

    @Test("service invite and recovery code are one-time")
    func consumesSecretsOnce() async throws {
        let relay = ManagedRelay(pepper: Data(repeating: 9, count: 32))
        let keys = RemoteDeviceKeys()
        let invite = try await relay.createServiceInvite(expiresAt: Date().addingTimeInterval(60))
        let enrolled = try await relay.enroll(
            invite: invite,
            hostName: "Mac",
            signingPublicKey: keys.signingPublicKey,
            encryptionPublicKey: keys.encryptionPublicKey,
            encryptionKeySignature: keys.signEncryptionKey()
        )
        await #expect(throws: ManagedRelayError.inviteConsumed) {
            _ = try await relay.enroll(
                invite: invite,
                hostName: "Another Mac",
                signingPublicKey: keys.signingPublicKey,
                encryptionPublicKey: keys.encryptionPublicKey,
                encryptionKeySignature: keys.signEncryptionKey()
            )
        }
        let replacement = RemoteDeviceKeys()
        let code = try #require(enrolled.recoveryCodes.first)
        _ = try await relay.recover(
            spaceID: enrolled.space.id,
            code: code,
            name: "Replacement",
            signingPublicKey: replacement.signingPublicKey,
            encryptionPublicKey: replacement.encryptionPublicKey,
            encryptionKeySignature: replacement.signEncryptionKey()
        )
        await #expect(throws: ManagedRelayError.invalidRecoveryCode) {
            _ = try await relay.recover(
                spaceID: enrolled.space.id,
                code: code,
                name: "Replay",
                signingPublicKey: replacement.signingPublicKey,
                encryptionPublicKey: replacement.encryptionPublicKey,
                encryptionKeySignature: replacement.signEncryptionKey()
            )
        }
    }
}
