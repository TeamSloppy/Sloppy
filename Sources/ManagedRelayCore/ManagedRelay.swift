import Foundation
import SloppyRemoteProtocol

public enum ManagedRelayError: Error, Sendable, Equatable {
    case unauthorized
    case forbidden
    case invalidInvite
    case inviteExpired
    case inviteConsumed
    case invalidPairing
    case pairingExpired
    case pairingAlreadyClaimed
    case pairingNotPending
    case challengeExpired
    case invalidSignature
    case deviceRevoked
    case spaceSuspended
    case hostOffline
    case crossSpaceRoute
    case plaintextPayload
    case replay
    case invalidRecoveryCode
}

public actor ManagedRelay {
    private struct ServiceInvite: Sendable {
        var hash: Data
        var expiresAt: Date
        var consumed: Bool
    }

    private struct Pairing: Sendable {
        var request: ManagedPairingRequest
        var nonceHash: Data
    }

    private struct Challenge: Sendable {
        var deviceID: UUID
        var nonce: Data
        var expiresAt: Date
    }

    private struct Session: Sendable {
        var tokenHash: Data
        var deviceID: UUID
        var expiresAt: Date
    }

    private let pepper: Data
    private var spaces: [UUID: ManagedPersonalSpace] = [:]
    private var devices: [UUID: RemoteDevice] = [:]
    private var invites: [UUID: ServiceInvite] = [:]
    private var pairings: [UUID: Pairing] = [:]
    private var challenges: [UUID: Challenge] = [:]
    private var sessions: [Data: Session] = [:]
    private var recoveryCodes: [UUID: Set<Data>] = [:]
    private var onlineDevices: Set<UUID> = []
    private var routedEnvelopeIDs: Set<UUID> = []

    public init(pepper: Data) {
        self.pepper = pepper
    }

    public func createServiceInvite(expiresAt: Date, now: Date = Date()) throws -> String {
        guard expiresAt > now else { throw ManagedRelayError.inviteExpired }
        let id = UUID()
        let secret = RemoteSecret.random()
        invites[id] = ServiceInvite(
            hash: RemoteSecret.digest(secret, pepper: pepper),
            expiresAt: expiresAt,
            consumed: false
        )
        return "\(id.uuidString).\(secret)"
    }

    public func enroll(
        invite: String,
        hostName: String,
        signingPublicKey: Data,
        encryptionPublicKey: Data,
        encryptionKeySignature: Data,
        now: Date = Date()
    ) throws -> ManagedEnrollment {
        let pieces = invite.split(separator: ".", maxSplits: 1).map(String.init)
        guard pieces.count == 2,
              let inviteID = UUID(uuidString: pieces[0]),
              var record = invites[inviteID],
              record.hash == RemoteSecret.digest(pieces[1], pepper: pepper) else {
            throw ManagedRelayError.invalidInvite
        }
        guard !record.consumed else { throw ManagedRelayError.inviteConsumed }
        guard record.expiresAt > now else { throw ManagedRelayError.inviteExpired }
        guard signingPublicKey.count == 32, encryptionPublicKey.count == 32,
              RemoteDeviceKeys.verifyEncryptionKey(
                signingPublicKey: signingPublicKey,
                encryptionPublicKey: encryptionPublicKey,
                signature: encryptionKeySignature
              ) else {
            throw ManagedRelayError.invalidSignature
        }

        record.consumed = true
        invites[inviteID] = record
        let space = ManagedPersonalSpace(label: String(hostName.prefix(80)))
        let principalID = UUID()
        let device = RemoteDevice(
            spaceID: space.id,
            principalID: principalID,
            kind: .host,
            name: String(hostName.prefix(80)),
            signingPublicKey: signingPublicKey,
            encryptionPublicKey: encryptionPublicKey,
            encryptionKeySignature: encryptionKeySignature,
            capabilities: ["sloppy.core.remote", "sloppy.terminal.control"]
        )
        spaces[space.id] = space
        devices[device.id] = device
        let codes = (0..<10).map { _ in RemoteSecret.random(byteCount: 16) }
        recoveryCodes[space.id] = Set(codes.map { RemoteSecret.digest($0, pepper: pepper) })
        return ManagedEnrollment(space: space, device: device, recoveryCodes: codes)
    }

    public func challenge(deviceID: UUID, now: Date = Date()) throws -> (id: UUID, nonce: Data) {
        _ = try activeDevice(deviceID)
        let id = UUID()
        let nonce = Data(RemoteSecret.random().utf8)
        challenges[id] = Challenge(deviceID: deviceID, nonce: nonce, expiresAt: now.addingTimeInterval(60))
        return (id, nonce)
    }

    public func authenticate(
        challengeID: UUID,
        signature: Data,
        now: Date = Date()
    ) throws -> ManagedDeviceSession {
        guard let challenge = challenges.removeValue(forKey: challengeID),
              challenge.expiresAt > now else {
            throw ManagedRelayError.challengeExpired
        }
        let device = try activeDevice(challenge.deviceID)
        guard RemoteDeviceKeys.verify(
            signature: signature,
            challenge: challenge.nonce,
            publicKey: device.signingPublicKey
        ) else {
            throw ManagedRelayError.invalidSignature
        }
        let token = RemoteSecret.random()
        let expiry = now.addingTimeInterval(15 * 60)
        let hash = RemoteSecret.digest(token, pepper: pepper)
        sessions[hash] = Session(tokenHash: hash, deviceID: device.id, expiresAt: expiry)
        return ManagedDeviceSession(device: device, token: token, expiresAt: expiry)
    }

    public func device(for token: String, now: Date = Date()) throws -> RemoteDevice {
        let hash = RemoteSecret.digest(token, pepper: pepper)
        guard let session = sessions[hash], session.expiresAt > now else {
            throw ManagedRelayError.unauthorized
        }
        return try activeDevice(session.deviceID)
    }

    public func listDevices(token: String, now: Date = Date()) throws -> [RemoteDevice] {
        let caller = try device(for: token, now: now)
        return devices.values
            .filter { $0.spaceID == caller.spaceID && $0.status == .active }
            .sorted { $0.name < $1.name }
    }

    public func createPairing(
        token: String,
        kind: RemoteDeviceKind,
        relayURL: URL,
        now: Date = Date()
    ) throws -> RemotePairingCode {
        let caller = try device(for: token, now: now)
        guard caller.kind == .host, kind == .mobile || kind == .host,
              relayURL.scheme == "https" else {
            throw ManagedRelayError.forbidden
        }
        let id = UUID()
        let nonce = RemoteSecret.random()
        let expiry = now.addingTimeInterval(120)
        let request = ManagedPairingRequest(
            id: id,
            spaceID: caller.spaceID,
            createdByDeviceID: caller.id,
            kind: kind,
            status: .open,
            expiresAt: expiry
        )
        pairings[id] = Pairing(
            request: request,
            nonceHash: RemoteSecret.digest(nonce, pepper: pepper)
        )
        return RemotePairingCode(
            relayURL: relayURL,
            pairingID: id,
            claimNonce: nonce,
            expiresAt: expiry
        )
    }

    public func claimPairing(
        id: UUID,
        nonce: String,
        deviceID: UUID,
        name: String,
        signingPublicKey: Data,
        encryptionPublicKey: Data,
        encryptionKeySignature: Data,
        claimSignature: Data,
        now: Date = Date()
    ) throws -> ManagedPairingRequest {
        guard var pairing = pairings[id],
              pairing.nonceHash == RemoteSecret.digest(nonce, pepper: pepper) else {
            throw ManagedRelayError.invalidPairing
        }
        guard pairing.request.expiresAt > now else { throw ManagedRelayError.pairingExpired }
        guard pairing.request.status == .open else { throw ManagedRelayError.pairingAlreadyClaimed }
        guard signingPublicKey.count == 32, encryptionPublicKey.count == 32,
              RemoteDeviceKeys.verify(
                signature: claimSignature,
                challenge: Data("sloppy-remote-pair-v1:\(id):\(nonce)".utf8),
                publicKey: signingPublicKey
              ),
              RemoteDeviceKeys.verifyEncryptionKey(
                signingPublicKey: signingPublicKey,
                encryptionPublicKey: encryptionPublicKey,
                signature: encryptionKeySignature
              ) else {
            throw ManagedRelayError.invalidSignature
        }
        pairing.request.status = .pending
        pairing.request.claimedDeviceID = deviceID
        pairing.request.claimedName = String(name.prefix(80))
        pairing.request.claimedSigningPublicKey = signingPublicKey
        pairing.request.claimedEncryptionPublicKey = encryptionPublicKey
        pairing.request.claimedEncryptionKeySignature = encryptionKeySignature
        pairings[id] = pairing
        return pairing.request
    }

    public func pairingStatus(id: UUID, nonce: String, now: Date = Date()) throws -> ManagedPairingRequest {
        guard let pairing = pairings[id],
              pairing.nonceHash == RemoteSecret.digest(nonce, pepper: pepper) else {
            throw ManagedRelayError.invalidPairing
        }
        guard pairing.request.expiresAt > now else { throw ManagedRelayError.pairingExpired }
        return pairing.request
    }

    public func decidePairing(
        id: UUID,
        token: String,
        approve: Bool,
        now: Date = Date()
    ) throws -> RemoteDevice? {
        let caller = try device(for: token, now: now)
        guard var pairing = pairings[id], pairing.request.spaceID == caller.spaceID,
              pairing.request.createdByDeviceID == caller.id,
              caller.kind == .host else {
            throw ManagedRelayError.forbidden
        }
        guard pairing.request.expiresAt > now else { throw ManagedRelayError.pairingExpired }
        guard pairing.request.status == .pending else { throw ManagedRelayError.pairingNotPending }
        pairing.request.status = approve ? .approved : .rejected
        pairings[id] = pairing
        guard approve,
              let deviceID = pairing.request.claimedDeviceID,
              let name = pairing.request.claimedName,
              let signingKey = pairing.request.claimedSigningPublicKey,
              let encryptionKey = pairing.request.claimedEncryptionPublicKey,
              let keySignature = pairing.request.claimedEncryptionKeySignature
        else { return nil }
        let grantedCapabilities: Set<String> = pairing.request.kind == .host
            ? ["sloppy.core.remote", "sloppy.terminal.control"]
            : ["sloppy.core.remote"]
        let device = RemoteDevice(
            id: deviceID,
            spaceID: caller.spaceID,
            principalID: caller.principalID,
            kind: pairing.request.kind,
            name: name,
            signingPublicKey: signingKey,
            encryptionPublicKey: encryptionKey,
            encryptionKeySignature: keySignature,
            capabilities: grantedCapabilities
        )
        devices[device.id] = device
        return device
    }

    public func setOnline(deviceID: UUID, online: Bool) throws {
        _ = try activeDevice(deviceID)
        if online { onlineDevices.insert(deviceID) } else { onlineDevices.remove(deviceID) }
    }

    public func route(_ envelope: RemoteSealedEnvelope, authenticatedSenderID: UUID) throws {
        let sender = try activeDevice(authenticatedSenderID)
        guard envelope.from == sender.id else { throw ManagedRelayError.forbidden }
        let target = try activeDevice(envelope.to)
        guard sender.spaceID == target.spaceID else { throw ManagedRelayError.crossSpaceRoute }
        guard !envelope.ciphertext.isEmpty else { throw ManagedRelayError.plaintextPayload }
        guard !routedEnvelopeIDs.contains(envelope.id) else { throw ManagedRelayError.replay }
        guard onlineDevices.contains(target.id) else { throw ManagedRelayError.hostOffline }
        routedEnvelopeIDs.insert(envelope.id)
    }

    public func revokeDevice(id: UUID, token: String, now: Date = Date()) throws {
        let caller = try device(for: token, now: now)
        guard let target = devices[id], caller.spaceID == target.spaceID,
              caller.kind == .host else { throw ManagedRelayError.forbidden }
        var revoked = target
        revoked.status = .revoked
        devices[id] = revoked
        onlineDevices.remove(id)
        sessions = sessions.filter { $0.value.deviceID != id }
    }

    public func recover(
        spaceID: UUID,
        code: String,
        name: String,
        signingPublicKey: Data,
        encryptionPublicKey: Data,
        encryptionKeySignature: Data
    ) throws -> RemoteDevice {
        let hash = RemoteSecret.digest(code, pepper: pepper)
        guard var codes = recoveryCodes[spaceID], codes.remove(hash) != nil,
              let space = spaces[spaceID], !space.isSuspended else {
            throw ManagedRelayError.invalidRecoveryCode
        }
        guard RemoteDeviceKeys.verifyEncryptionKey(
            signingPublicKey: signingPublicKey,
            encryptionPublicKey: encryptionPublicKey,
            signature: encryptionKeySignature
        ) else { throw ManagedRelayError.invalidSignature }
        recoveryCodes[spaceID] = codes
        let principalID = devices.values.first { $0.spaceID == spaceID }?.principalID ?? UUID()
        let device = RemoteDevice(
            spaceID: spaceID,
            principalID: principalID,
            kind: .host,
            name: String(name.prefix(80)),
            signingPublicKey: signingPublicKey,
            encryptionPublicKey: encryptionPublicKey,
            encryptionKeySignature: encryptionKeySignature,
            capabilities: ["sloppy.core.remote", "sloppy.terminal.control"]
        )
        devices[device.id] = device
        return device
    }

    private func activeDevice(_ id: UUID) throws -> RemoteDevice {
        guard let device = devices[id] else { throw ManagedRelayError.unauthorized }
        guard device.status == .active else { throw ManagedRelayError.deviceRevoked }
        guard let space = spaces[device.spaceID], !space.isSuspended else {
            throw ManagedRelayError.spaceSuspended
        }
        return device
    }
}
