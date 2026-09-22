import Foundation
import SloppyRemoteProtocol
#if canImport(Security)
import Security
#endif

public enum ManagedRemoteError: LocalizedError, Sendable {
    case notEnrolled
    case invalidResponse
    case server(Int)
    case pairingRejected
    case pairingExpired
    case timeout
    case hostOffline
    case credentialStorageFailed(recoveryCodes: [String], spaceID: UUID)

    public var errorDescription: String? {
        switch self {
        case .notEnrolled: "This device has not joined Sloppy Remote."
        case .invalidResponse: "The remote relay returned an invalid response."
        case .server(let status): "The remote relay returned HTTP \(status)."
        case .pairingRejected: "The host rejected this device."
        case .pairingExpired: "The pairing code expired."
        case .timeout: "The remote host did not respond in time."
        case .hostOffline: "The remote host is offline."
        case .credentialStorageFailed: "The invite was consumed, but this device could not save its keys. Save the recovery codes now."
        }
    }
}

public struct ManagedRemoteCredential: Codable, Sendable {
    public var relayURL: URL
    public var device: RemoteDevice
    public var signingPrivateKey: Data
    public var encryptionPrivateKey: Data

    public var keys: RemoteDeviceKeys? {
        try? RemoteDeviceKeys(
            signingPrivateKey: signingPrivateKey,
            encryptionPrivateKey: encryptionPrivateKey
        )
    }
}

public enum ManagedRemoteCredentialStore {
    private static let service = "team.sloppy.client.managed-remote"
    private static let account = "active-device"

    public static func load() -> ManagedRemoteCredential? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(ManagedRemoteCredential.self, from: data)
        #else
        return nil
        #endif
    }

    public static func save(_ credential: ManagedRemoteCredential) throws {
        #if canImport(Security)
        let data = try JSONEncoder().encode(credential)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
                throw ManagedRemoteError.invalidResponse
            }
        } else if updateStatus != errSecSuccess {
            throw ManagedRemoteError.invalidResponse
        }
        #endif
    }
}

public actor ManagedRemoteClient {
    public static let productionURL = URL(string: "https://relay.sloppy.team")!

    private let configuredRelayURL: URL?
    private var relayURL: URL {
        configuredRelayURL ?? ManagedRemoteCredentialStore.load()?.relayURL ?? Self.productionURL
    }
    private let session: URLSession
    private var sessionToken: String?
    private var sessionExpiresAt: Date?

    public init(relayURL: URL? = nil, session: URLSession = .shared) {
        self.configuredRelayURL = relayURL
        self.session = session
    }

    public func enableRemote(invite: String, hostName: String) async throws -> ManagedEnrollment {
        let keys = RemoteDeviceKeys()
        let enrollment: ManagedEnrollment = try await request(
            method: "POST",
            path: "/v1/enrollments/consume",
            body: EnrollmentRequest(
                invite: invite,
                hostName: hostName,
                signingPublicKey: keys.signingPublicKey,
                encryptionPublicKey: keys.encryptionPublicKey,
                encryptionKeySignature: try keys.signEncryptionKey()
            )
        )
        do {
            try ManagedRemoteCredentialStore.save(ManagedRemoteCredential(
                relayURL: relayURL,
                device: enrollment.device,
                signingPrivateKey: keys.signingPrivateKey,
                encryptionPrivateKey: keys.encryptionPrivateKey
            ))
        } catch {
            throw ManagedRemoteError.credentialStorageFailed(
                recoveryCodes: enrollment.recoveryCodes,
                spaceID: enrollment.space.id
            )
        }
        return enrollment
    }

    public func recoverHost(spaceID: UUID, code: String, hostName: String) async throws -> RemoteDevice {
        let keys = RemoteDeviceKeys()
        let device: RemoteDevice = try await request(
            method: "POST",
            path: "/v1/recovery",
            body: RecoveryRequest(
                spaceID: spaceID,
                code: code,
                name: hostName,
                signingPublicKey: keys.signingPublicKey,
                encryptionPublicKey: keys.encryptionPublicKey,
                encryptionKeySignature: try keys.signEncryptionKey()
            )
        )
        try ManagedRemoteCredentialStore.save(ManagedRemoteCredential(
            relayURL: relayURL,
            device: device,
            signingPrivateKey: keys.signingPrivateKey,
            encryptionPrivateKey: keys.encryptionPrivateKey
        ))
        return device
    }

    public func authenticate() async throws -> ManagedDeviceSession {
        guard let credential = ManagedRemoteCredentialStore.load(),
              let keys = credential.keys else { throw ManagedRemoteError.notEnrolled }
        let challenge: ChallengeResponse = try await request(
            method: "POST",
            path: "/v1/device-auth/challenge",
            body: ["deviceID": credential.device.id.uuidString]
        )
        let response: ManagedDeviceSession = try await request(
            method: "POST",
            path: "/v1/device-auth/session",
            body: SessionRequest(
                challengeID: challenge.id,
                signature: try keys.sign(challenge.nonce)
            )
        )
        try ManagedRemoteCredentialStore.save(ManagedRemoteCredential(
            relayURL: credential.relayURL,
            device: response.device,
            signingPrivateKey: credential.signingPrivateKey,
            encryptionPrivateKey: credential.encryptionPrivateKey
        ))
        sessionToken = response.token
        sessionExpiresAt = response.expiresAt
        return response
    }

    public func createPhonePairing() async throws -> RemotePairingCode {
        try await createPairing(kind: .mobile)
    }

    public func createPairing(kind: RemoteDeviceKind) async throws -> RemotePairingCode {
        let token = try await activeToken()
        return try await request(
            method: "POST",
            path: "/v1/remote/device-pairings",
            body: ["kind": kind.rawValue],
            token: token
        )
    }

    public func pendingPairings() async throws -> [ManagedPairingRequest] {
        let token = try await activeToken()
        return try await request(
            method: "GET",
            path: "/v1/remote/device-pairings",
            token: token
        )
    }

    public func decidePairing(id: UUID, approve: Bool) async throws {
        let token = try await activeToken()
        let _: PairingDecisionResponse = try await request(
            method: "POST",
            path: "/v1/remote/device-pairings/\(id.uuidString)/\(approve ? "approve" : "reject")",
            body: EmptyRequest(),
            token: token
        )
    }

    public func hosts() async throws -> [RemoteDevice] {
        let token = try await activeToken()
        return try await request(method: "GET", path: "/v1/remote/hosts", token: token)
    }

    public func devices() async throws -> [RemoteDevice] {
        let token = try await activeToken()
        return try await request(method: "GET", path: "/v1/remote/devices", token: token)
    }

    public func revokeDevice(_ id: UUID) async throws {
        let token = try await activeToken()
        let _: StatusResponse = try await request(
            method: "DELETE",
            path: "/v1/remote/devices/\(id.uuidString)",
            token: token
        )
    }

    public func rotateRecoveryCodes() async throws -> [String] {
        let token = try await activeToken()
        let result: RecoveryCodesResponse = try await request(
            method: "POST",
            path: "/v1/remote/recovery-codes/rotate",
            body: EmptyRequest(),
            token: token
        )
        return result.codes
    }

    public func claimPhonePairing(
        _ code: RemotePairingCode,
        name: String
    ) async throws -> RemoteDevice {
        try await claimPairing(code, name: name, expectedKind: .mobile)
    }

    public func claimHostPairing(
        _ code: RemotePairingCode,
        name: String
    ) async throws -> RemoteDevice {
        try await claimPairing(code, name: name, expectedKind: .host)
    }

    private func claimPairing(
        _ code: RemotePairingCode,
        name: String,
        expectedKind: RemoteDeviceKind
    ) async throws -> RemoteDevice {
        guard code.relayURL == relayURL, code.expiresAt > Date() else {
            throw ManagedRemoteError.pairingExpired
        }
        let initial: ManagedPairingRequest = try await request(
            method: "GET",
            path: "/v1/device-pairings/\(code.pairingID.uuidString)/status",
            pairingNonce: code.claimNonce
        )
        guard initial.kind == expectedKind, initial.status == .open else {
            throw ManagedRemoteError.invalidResponse
        }
        let keys = RemoteDeviceKeys()
        let deviceID = UUID()
        let _: StatusResponse = try await request(
            method: "POST",
            path: "/v1/device-pairings/\(code.pairingID.uuidString)/claim",
            body: ClaimRequest(
                nonce: code.claimNonce,
                deviceID: deviceID,
                kind: expectedKind,
                name: name,
                signingPublicKey: keys.signingPublicKey,
                encryptionPublicKey: keys.encryptionPublicKey,
                encryptionKeySignature: try keys.signEncryptionKey(),
                claimSignature: try keys.sign(
                    Data("sloppy-remote-pair-v1:\(code.pairingID):\(code.claimNonce)".utf8)
                )
            )
        )
        while Date() < code.expiresAt {
            try Task.checkCancellation()
            let status: ManagedPairingRequest = try await request(
                method: "GET",
                path: "/v1/device-pairings/\(code.pairingID.uuidString)/status",
                pairingNonce: code.claimNonce
            )
            switch status.status {
            case .approved:
                let credential = ManagedRemoteCredential(
                    relayURL: relayURL,
                    device: RemoteDevice(
                        id: deviceID,
                        spaceID: status.spaceID,
                        principalID: UUID(),
                        kind: expectedKind,
                        name: name,
                        signingPublicKey: keys.signingPublicKey,
                        encryptionPublicKey: keys.encryptionPublicKey,
                        encryptionKeySignature: try keys.signEncryptionKey(),
                        capabilities: ["sloppy.core.remote", "sloppy.terminal.control"]
                    ),
                    signingPrivateKey: keys.signingPrivateKey,
                    encryptionPrivateKey: keys.encryptionPrivateKey
                )
                try ManagedRemoteCredentialStore.save(credential)
                return (try await authenticate()).device
            case .rejected:
                throw ManagedRemoteError.pairingRejected
            case .open, .pending:
                try await Task.sleep(for: .seconds(2))
            }
        }
        throw ManagedRemoteError.pairingExpired
    }

    private func activeToken() async throws -> String {
        if let sessionToken, let sessionExpiresAt,
           sessionExpiresAt > Date().addingTimeInterval(30) {
            return sessionToken
        }
        return try await authenticate().token
    }

    private func request<T: Decodable>(
        method: String,
        path: String,
        token: String? = nil,
        pairingNonce: String? = nil
    ) async throws -> T {
        try await request(method: method, path: path, body: Optional<EmptyRequest>.none,
                          token: token, pairingNonce: pairingNonce)
    }

    private func request<Body: Encodable, T: Decodable>(
        method: String,
        path: String,
        body: Body?,
        token: String? = nil,
        pairingNonce: String? = nil
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: relayURL)?.absoluteURL else {
            throw ManagedRemoteError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if let pairingNonce {
            request.setValue("Pairing \(pairingNonce)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ManagedRemoteError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ManagedRemoteError.server(http.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}

private struct EmptyRequest: Encodable {}
private struct RecoveryCodesResponse: Decodable { var codes: [String] }
private struct EnrollmentRequest: Encodable {
    var invite: String
    var hostName: String
    var signingPublicKey: Data
    var encryptionPublicKey: Data
    var encryptionKeySignature: Data
}
private struct RecoveryRequest: Encodable {
    var spaceID: UUID
    var code: String
    var name: String
    var signingPublicKey: Data
    var encryptionPublicKey: Data
    var encryptionKeySignature: Data
}
private struct ChallengeResponse: Decodable { var id: UUID; var nonce: Data }
private struct SessionRequest: Encodable { var challengeID: UUID; var signature: Data }
private struct ClaimRequest: Encodable {
    var nonce: String
    var deviceID: UUID
    var kind: RemoteDeviceKind
    var name: String
    var signingPublicKey: Data
    var encryptionPublicKey: Data
    var encryptionKeySignature: Data
    var claimSignature: Data
}
private struct StatusResponse: Decodable { var status: String }
private struct PairingDecisionResponse: Decodable { var device: RemoteDevice? }
