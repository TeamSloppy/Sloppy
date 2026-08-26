import Foundation
import Protocols

#if canImport(CryptoKit)
import CryptoKit
#endif

public enum NodeMeshPayloadCryptoError: LocalizedError, Sendable {
    case unavailable
    case missingKey(String)
    case invalidKeyBinding(String)
    case invalidPayload

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "Mesh payload encryption is unavailable on this platform."
        case .missingKey(let nodeID):
            "Mesh encryption key is missing for \(nodeID)."
        case .invalidKeyBinding(let nodeID):
            "Mesh encryption key binding is invalid for \(nodeID)."
        case .invalidPayload:
            "Encrypted mesh payload is invalid."
        }
    }
}

enum NodeMeshPayloadCrypto {
    static let sealedKey = "sealedPayload"

    static func seal(
        _ payload: JSONValue,
        envelope: MeshEnvelope,
        sender: NodeIdentity,
        recipient: MeshNodeRecord
    ) throws -> JSONValue {
        #if canImport(CryptoKit)
        guard let senderPrivateKey = sender.encryptionPrivateKey,
              let senderPublicKey = sender.encryptionPublicKey,
              let senderKeySignature = sender.encryptionKeySignature
        else {
            throw NodeMeshPayloadCryptoError.missingKey(sender.nodeId)
        }
        guard let recipientPublicKey = recipient.encryptionPublicKey,
              let recipientKeySignature = recipient.encryptionKeySignature,
              NodeIdentityGenerator.verifyEncryptionKeyBinding(
                  nodeId: recipient.id,
                  encryptionPublicKey: recipientPublicKey,
                  signature: recipientKeySignature,
                  signingPublicKey: recipient.publicKey
              )
        else {
            throw NodeMeshPayloadCryptoError.invalidKeyBinding(recipient.id)
        }

        let privateKey = try Curve25519.KeyAgreement.PrivateKey(
            rawRepresentation: decodeKeyMaterial(senderPrivateKey, prefix: "x25519:")
        )
        let publicKey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: decodeKeyMaterial(recipientPublicKey, prefix: "x25519:")
        )
        let symmetricKey = try deriveKey(privateKey: privateKey, publicKey: publicKey, envelope: envelope)
        let plaintext = try JSONEncoder().encode(payload)
        let sealedBox = try ChaChaPoly.seal(plaintext, using: symmetricKey, authenticating: associatedData(for: envelope))
        let combined = sealedBox.combined
        var routing = routingMetadata(from: payload)
        routing[sealedKey] = .string(combined.base64EncodedString())
        routing["senderEncryptionPublicKey"] = .string(senderPublicKey)
        routing["senderEncryptionKeySignature"] = .string(senderKeySignature)
        return .object(routing)
        #else
        throw NodeMeshPayloadCryptoError.unavailable
        #endif
    }

    static func open(
        _ payload: JSONValue,
        envelope: MeshEnvelope,
        recipient: NodeIdentity,
        senderSigningPublicKey: String
    ) throws -> JSONValue {
        #if canImport(CryptoKit)
        guard let object = payload.asObject,
              let combinedValue = object[sealedKey]?.asString,
              let combined = Data(base64Encoded: combinedValue),
              let senderPublicKey = object["senderEncryptionPublicKey"]?.asString,
              let senderKeySignature = object["senderEncryptionKeySignature"]?.asString,
              let recipientPrivateKey = recipient.encryptionPrivateKey
        else {
            throw NodeMeshPayloadCryptoError.invalidPayload
        }
        guard NodeIdentityGenerator.verifyEncryptionKeyBinding(
            nodeId: envelope.from,
            encryptionPublicKey: senderPublicKey,
            signature: senderKeySignature,
            signingPublicKey: senderSigningPublicKey
        ) else {
            throw NodeMeshPayloadCryptoError.invalidKeyBinding(envelope.from)
        }

        let privateKey = try Curve25519.KeyAgreement.PrivateKey(
            rawRepresentation: decodeKeyMaterial(recipientPrivateKey, prefix: "x25519:")
        )
        let publicKey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: decodeKeyMaterial(senderPublicKey, prefix: "x25519:")
        )
        let symmetricKey = try deriveKey(privateKey: privateKey, publicKey: publicKey, envelope: envelope)
        let sealedBox = try ChaChaPoly.SealedBox(combined: combined)
        let plaintext = try ChaChaPoly.open(sealedBox, using: symmetricKey, authenticating: associatedData(for: envelope))
        return try JSONDecoder().decode(JSONValue.self, from: plaintext)
        #else
        throw NodeMeshPayloadCryptoError.unavailable
        #endif
    }

    static func isSealed(_ payload: JSONValue) -> Bool {
        payload.asObject?[sealedKey]?.asString != nil
    }

    private static func routingMetadata(from payload: JSONValue) -> [String: JSONValue] {
        let object = payload.asObject ?? [:]
        return ["method", "requestId", "streamId", "kind"].reduce(into: [:]) { result, key in
            if let value = object[key] {
                result[key] = value
            }
        }
    }

    #if canImport(CryptoKit)
    private static func deriveKey(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        publicKey: Curve25519.KeyAgreement.PublicKey,
        envelope: MeshEnvelope
    ) throws -> SymmetricKey {
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        return secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("sloppy-mesh-e2e-v1".utf8),
            sharedInfo: associatedData(for: envelope),
            outputByteCount: 32
        )
    }
    #endif

    private static func associatedData(for envelope: MeshEnvelope) -> Data {
        Data([
            "v1",
            envelope.id,
            envelope.type.rawValue,
            envelope.from,
            envelope.to ?? "",
            envelope.scope ?? "",
        ].joined(separator: "\n").utf8)
    }

    private static func decodeKeyMaterial(_ value: String, prefix: String) throws -> Data {
        var encoded = value.hasPrefix(prefix) ? String(value.dropFirst(prefix.count)) : value
        encoded = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = encoded.count % 4
        if remainder > 0 {
            encoded += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: encoded), !data.isEmpty else {
            throw NodeMeshPayloadCryptoError.invalidPayload
        }
        return data
    }
}
