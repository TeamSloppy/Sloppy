import Crypto
import Foundation

public enum RemoteDeviceKind: String, Codable, Sendable {
    case host
    case mobile
    case admin
}

public enum RemoteDeviceStatus: String, Codable, Sendable {
    case active
    case revoked
}

public struct RemoteDevice: Codable, Sendable, Equatable {
    public var id: UUID
    public var spaceID: UUID
    public var principalID: UUID
    public var kind: RemoteDeviceKind
    public var name: String
    public var signingPublicKey: Data
    public var encryptionPublicKey: Data
    public var encryptionKeySignature: Data
    public var capabilities: Set<String>
    public var status: RemoteDeviceStatus
    public var online: Bool?

    public init(
        id: UUID = UUID(),
        spaceID: UUID,
        principalID: UUID,
        kind: RemoteDeviceKind,
        name: String,
        signingPublicKey: Data,
        encryptionPublicKey: Data,
        encryptionKeySignature: Data,
        capabilities: Set<String>,
        status: RemoteDeviceStatus = .active,
        online: Bool? = nil
    ) {
        self.id = id
        self.spaceID = spaceID
        self.principalID = principalID
        self.kind = kind
        self.name = name
        self.signingPublicKey = signingPublicKey
        self.encryptionPublicKey = encryptionPublicKey
        self.encryptionKeySignature = encryptionKeySignature
        self.capabilities = capabilities
        self.status = status
        self.online = online
    }
}

public struct ManagedPersonalSpace: Codable, Sendable, Equatable {
    public var id: UUID
    public var label: String
    public var isSuspended: Bool

    public init(id: UUID = UUID(), label: String, isSuspended: Bool = false) {
        self.id = id
        self.label = label
        self.isSuspended = isSuspended
    }
}

public struct ManagedEnrollment: Codable, Sendable {
    public var space: ManagedPersonalSpace
    public var device: RemoteDevice
    public var recoveryCodes: [String]

    public init(space: ManagedPersonalSpace, device: RemoteDevice, recoveryCodes: [String]) {
        self.space = space
        self.device = device
        self.recoveryCodes = recoveryCodes
    }
}

public struct ManagedPairingRequest: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        case open
        case pending
        case approved
        case rejected
    }

    public var id: UUID
    public var spaceID: UUID
    public var createdByDeviceID: UUID
    public var kind: RemoteDeviceKind
    public var status: Status
    public var expiresAt: Date
    public var claimedDeviceID: UUID?
    public var claimedName: String?
    public var claimedSigningPublicKey: Data?
    public var claimedEncryptionPublicKey: Data?
    public var claimedEncryptionKeySignature: Data?

    public init(
        id: UUID,
        spaceID: UUID,
        createdByDeviceID: UUID,
        kind: RemoteDeviceKind,
        status: Status,
        expiresAt: Date,
        claimedDeviceID: UUID? = nil,
        claimedName: String? = nil,
        claimedSigningPublicKey: Data? = nil,
        claimedEncryptionPublicKey: Data? = nil,
        claimedEncryptionKeySignature: Data? = nil
    ) {
        self.id = id
        self.spaceID = spaceID
        self.createdByDeviceID = createdByDeviceID
        self.kind = kind
        self.status = status
        self.expiresAt = expiresAt
        self.claimedDeviceID = claimedDeviceID
        self.claimedName = claimedName
        self.claimedSigningPublicKey = claimedSigningPublicKey
        self.claimedEncryptionPublicKey = claimedEncryptionPublicKey
        self.claimedEncryptionKeySignature = claimedEncryptionKeySignature
    }
}

public struct ManagedDeviceSession: Codable, Sendable {
    public var device: RemoteDevice
    public var token: String
    public var expiresAt: Date

    public init(device: RemoteDevice, token: String, expiresAt: Date) {
        self.device = device
        self.token = token
        self.expiresAt = expiresAt
    }
}

public struct RemotePairingCode: Codable, Sendable, Equatable {
    public var version: Int
    public var relayURL: URL
    public var pairingID: UUID
    public var claimNonce: String
    public var expiresAt: Date

    public init(relayURL: URL, pairingID: UUID, claimNonce: String, expiresAt: Date) {
        self.version = 1
        self.relayURL = relayURL
        self.pairingID = pairingID
        self.claimNonce = claimNonce
        self.expiresAt = expiresAt
    }

    public func encode() throws -> URL {
        let data = try JSONEncoder().encode(self)
        let code = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard let url = URL(string: "sloppy://remote-pair?code=\(code)") else {
            throw RemoteProtocolError.invalidPairingCode
        }
        return url
    }

    public static func decode(_ url: URL, now: Date = Date()) throws -> Self {
        guard url.scheme == "sloppy", url.host == "remote-pair",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value
        else { throw RemoteProtocolError.invalidPairingCode }
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let decoded = try? JSONDecoder().decode(Self.self, from: data),
              decoded.version == 1,
              decoded.relayURL.scheme == "https",
              decoded.expiresAt > now
        else { throw RemoteProtocolError.invalidPairingCode }
        return decoded
    }
}

public struct RemoteSealedEnvelope: Codable, Sendable, Equatable {
    public var id: UUID
    public var from: UUID
    public var to: UUID
    public var kind: String
    public var createdAt: Date
    public var ciphertext: Data

    public init(
        id: UUID = UUID(),
        from: UUID,
        to: UUID,
        kind: String,
        createdAt: Date = Date(),
        ciphertext: Data
    ) {
        self.id = id
        self.from = from
        self.to = to
        self.kind = kind
        self.createdAt = createdAt
        self.ciphertext = ciphertext
    }

    public var authenticatedMetadata: Data {
        Data("sloppy-remote-v1\n\(id)\n\(from)\n\(to)\n\(kind)".utf8)
    }
}

public struct RemoteCoreRequest: Codable, Sendable {
    public var requestID: UUID
    public var method: String
    public var path: String
    public var body: Data?

    public init(requestID: UUID = UUID(), method: String, path: String, body: Data? = nil) {
        self.requestID = requestID
        self.method = method
        self.path = path
        self.body = body
    }
}

public struct RemoteCoreResponse: Codable, Sendable {
    public var requestID: UUID
    public var status: Int
    public var body: Data
    public var contentType: String

    public init(requestID: UUID, status: Int, body: Data, contentType: String = "application/json") {
        self.requestID = requestID
        self.status = status
        self.body = body
        self.contentType = contentType
    }
}

public struct RemoteStreamFrame: Codable, Sendable {
    public enum Action: String, Codable, Sendable {
        case open
        case data
        case close
    }

    public var streamID: UUID
    public var action: Action
    public var path: String?
    public var data: Data?

    public init(streamID: UUID, action: Action, path: String? = nil, data: Data? = nil) {
        self.streamID = streamID
        self.action = action
        self.path = path
        self.data = data
    }
}

public struct RemoteRelayControlFrame: Codable, Sendable {
    public var type: String
    public var envelopeID: UUID
    public var code: String

    public init(envelopeID: UUID, code: String) {
        self.type = "relay_error"
        self.envelopeID = envelopeID
        self.code = code
    }
}

public struct RemoteRelayReadyFrame: Codable, Sendable {
    public var type: String
    public init() { type = "relay_ready" }
}

public enum RemoteProtocolError: Error, Sendable {
    case invalidPairingCode
    case invalidPublicKey
    case invalidSignature
    case invalidCiphertext
}

public struct RemoteDeviceKeys: Sendable {
    public let signingPrivateKey: Data
    public let signingPublicKey: Data
    public let encryptionPrivateKey: Data
    public let encryptionPublicKey: Data

    public init() {
        let signing = Curve25519.Signing.PrivateKey()
        let encryption = Curve25519.KeyAgreement.PrivateKey()
        signingPrivateKey = signing.rawRepresentation
        signingPublicKey = signing.publicKey.rawRepresentation
        encryptionPrivateKey = encryption.rawRepresentation
        encryptionPublicKey = encryption.publicKey.rawRepresentation
    }

    public init(signingPrivateKey: Data, encryptionPrivateKey: Data) throws {
        let signing = try Curve25519.Signing.PrivateKey(rawRepresentation: signingPrivateKey)
        let encryption = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: encryptionPrivateKey)
        self.signingPrivateKey = signing.rawRepresentation
        self.signingPublicKey = signing.publicKey.rawRepresentation
        self.encryptionPrivateKey = encryption.rawRepresentation
        self.encryptionPublicKey = encryption.publicKey.rawRepresentation
    }

    public func sign(_ challenge: Data) throws -> Data {
        try Curve25519.Signing.PrivateKey(rawRepresentation: signingPrivateKey)
            .signature(for: challenge)
    }

    public func signEncryptionKey() throws -> Data {
        try sign(Self.encryptionBinding(encryptionPublicKey))
    }

    public static func verifyEncryptionKey(
        signingPublicKey: Data,
        encryptionPublicKey: Data,
        signature: Data
    ) -> Bool {
        verify(
            signature: signature,
            challenge: encryptionBinding(encryptionPublicKey),
            publicKey: signingPublicKey
        )
    }

    private static func encryptionBinding(_ key: Data) -> Data {
        Data("sloppy-remote-encryption-v1:".utf8) + key
    }

    public static func verify(signature: Data, challenge: Data, publicKey: Data) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else {
            return false
        }
        return key.isValidSignature(signature, for: challenge)
    }

    public static func fingerprint(signingPublicKey: Data) -> String {
        SHA256.hash(data: signingPublicKey)
            .map { String(format: "%02X", $0) }
            .joined(separator: "")
    }

    public func seal(_ plaintext: Data, envelope: RemoteSealedEnvelope, recipientPublicKey: Data) throws -> Data {
        let sender = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: encryptionPrivateKey)
        let recipient = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientPublicKey)
        let secret = try sender.sharedSecretFromKeyAgreement(with: recipient)
        let key = secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("sloppy-remote-e2e-v1".utf8),
            sharedInfo: envelope.authenticatedMetadata,
            outputByteCount: 32
        )
        return try ChaChaPoly.seal(
            plaintext,
            using: key,
            authenticating: envelope.authenticatedMetadata
        ).combined
    }

    public func open(_ envelope: RemoteSealedEnvelope, senderPublicKey: Data) throws -> Data {
        let recipient = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: encryptionPrivateKey)
        let sender = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: senderPublicKey)
        let secret = try recipient.sharedSecretFromKeyAgreement(with: sender)
        let key = secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("sloppy-remote-e2e-v1".utf8),
            sharedInfo: envelope.authenticatedMetadata,
            outputByteCount: 32
        )
        let box = try ChaChaPoly.SealedBox(combined: envelope.ciphertext)
        return try ChaChaPoly.open(
            box,
            using: key,
            authenticating: envelope.authenticatedMetadata
        )
    }
}

public enum RemoteSecret {
    public static func random(byteCount: Int = 32) -> String {
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func digest(_ secret: String, pepper: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(
            for: Data(secret.utf8),
            using: SymmetricKey(data: pepper)
        ))
    }
}
