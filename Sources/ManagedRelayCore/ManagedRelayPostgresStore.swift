import Foundation
import Logging
import PostgresNIO
import SloppyRemoteProtocol

public enum ManagedRelayDatabaseError: Error, Sendable {
    case invalidDatabaseURL
    case missingSchema
    case inviteUnavailable
    case duplicateDevice
    case adminAlreadyBootstrapped
    case adminUnavailable
}

public struct ManagedRelayAdminDevice: Sendable {
    public var id: UUID
    public var publicKey: Data
    public var name: String
}

public struct ManagedRelaySpaceSummary: Codable, Sendable {
    public var id: UUID
    public var label: String
    public var status: String
    public var deviceCount: Int64
    public var createdAt: Date
}

public struct ManagedRelayInviteSummary: Codable, Sendable {
    public var id: UUID
    public var expiresAt: Date
    public var consumedAt: Date?
}

public struct ManagedRelayAuditSummary: Codable, Sendable {
    public var id: UUID
    public var spaceID: UUID?
    public var actorDeviceID: UUID?
    public var action: String
    public var targetID: UUID?
    public var allowed: Bool
    public var createdAt: Date
}

public struct ManagedRelayDeviceSummary: Codable, Sendable {
    public var id: UUID
    public var spaceID: UUID
    public var name: String
    public var kind: String
    public var status: String
    public var lastSeenAt: Date?
}

/// Durable ownership and pairing records for the managed service.
///
/// The surrounding service must keep PostgresClient.run() active for the lifetime
/// of the relay. Every identity-creating operation uses a database transaction.
public struct ManagedRelayPostgresStore: Sendable {
    public let client: PostgresClient
    private let pepper: Data
    private let logger: Logger

    public init(databaseURL: URL, pepper: Data, logger: Logger = Logger(label: "sloppy.managed-relay.db")) throws {
        guard let scheme = databaseURL.scheme,
              scheme == "postgres" || scheme == "postgresql",
              let host = databaseURL.host,
              let username = databaseURL.user?.removingPercentEncoding,
              let database = databaseURL.pathComponents.dropFirst().first,
              !database.isEmpty else {
            throw ManagedRelayDatabaseError.invalidDatabaseURL
        }
        let socketPath = URLComponents(url: databaseURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "socket" })?.value
        let configuration: PostgresClient.Configuration
        if let socketPath, socketPath.hasPrefix("/"), !socketPath.contains("..") {
            configuration = PostgresClient.Configuration(
                unixSocketPath: socketPath,
                username: username,
                password: databaseURL.password?.removingPercentEncoding,
                database: database
            )
        } else {
            configuration = PostgresClient.Configuration(
                host: host,
                port: databaseURL.port ?? 5432,
                username: username,
                password: databaseURL.password?.removingPercentEncoding,
                database: database,
                tls: .disable
            )
        }
        self.client = PostgresClient(configuration: configuration)
        self.pepper = pepper
        self.logger = logger
    }

    public func migrate() async throws {
        guard let url = Bundle.module.url(forResource: "schema", withExtension: "sql"),
              let sql = try? String(contentsOf: url, encoding: .utf8) else {
            throw ManagedRelayDatabaseError.missingSchema
        }
        for statement in sql.split(separator: ";") {
            let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                try await client.query(PostgresQuery(unsafeSQL: trimmed), logger: logger)
            }
        }
    }

    public func bootstrapAdminDevice(
        publicKey: Data,
        name: String
    ) async throws -> UUID {
        guard publicKey.count == 32 else { throw ManagedRelayError.invalidSignature }
        let id = UUID()
        try await client.withTransaction(logger: logger) { connection in
            try await connection.query("SELECT pg_advisory_xact_lock(74821001)", logger: logger)
            let rows = try await connection.query(
                "SELECT count(*) FROM admin_devices",
                logger: logger
            )
            var count: Int64 = 0
            for try await value in rows.decode(Int64.self) { count = value }
            guard count == 0 else { throw ManagedRelayDatabaseError.adminAlreadyBootstrapped }
            try await connection.query(
                """
                INSERT INTO admin_devices (id, signing_public_key, name, status)
                VALUES (\(id), \(publicKey), \(String(name.prefix(80))), 'active')
                """,
                logger: logger
            )
        }
        return id
    }

    public func adminDevice(id: UUID) async throws -> ManagedRelayAdminDevice? {
        let rows = try await client.query(
            """
            SELECT id, signing_public_key, name FROM admin_devices
            WHERE id = \(id) AND status = 'active'
            """,
            logger: logger
        )
        for try await row in rows.decode((UUID, Data, String).self) {
            return ManagedRelayAdminDevice(id: row.0, publicKey: row.1, name: row.2)
        }
        return nil
    }

    public func saveAdminSession(token: String, adminDeviceID: UUID, expiresAt: Date) async throws {
        let hash = RemoteSecret.digest(token, pepper: pepper)
        try await client.query(
            """
            INSERT INTO admin_sessions (token_hash, admin_device_id, expires_at)
            VALUES (\(hash), \(adminDeviceID), \(expiresAt))
            """,
            logger: logger
        )
    }

    public func adminDevice(forSessionToken token: String) async throws -> ManagedRelayAdminDevice? {
        let hash = RemoteSecret.digest(token, pepper: pepper)
        let rows = try await client.query(
            """
            SELECT d.id FROM admin_sessions s
            JOIN admin_devices d ON d.id = s.admin_device_id
            WHERE s.token_hash = \(hash) AND s.expires_at > now()
              AND s.revoked_at IS NULL AND d.status = 'active'
            """,
            logger: logger
        )
        for try await id in rows.decode(UUID.self) {
            return try await adminDevice(id: id)
        }
        return nil
    }

    public func listSpaces() async throws -> [ManagedRelaySpaceSummary] {
        let rows = try await client.query(
            """
            SELECT s.id, s.label, s.status, count(d.id), s.created_at
            FROM personal_spaces s
            LEFT JOIN devices d ON d.space_id = s.id AND d.status = 'active'
            GROUP BY s.id ORDER BY s.created_at DESC
            """,
            logger: logger
        )
        var spaces: [ManagedRelaySpaceSummary] = []
        for try await row in rows.decode((UUID, String, String, Int64, Date).self) {
            spaces.append(ManagedRelaySpaceSummary(
                id: row.0, label: row.1, status: row.2,
                deviceCount: row.3, createdAt: row.4
            ))
        }
        return spaces
    }

    public func listInvites() async throws -> [ManagedRelayInviteSummary] {
        let rows = try await client.query(
            """
            SELECT id, expires_at, consumed_at FROM service_invites
            ORDER BY created_at DESC LIMIT 200
            """,
            logger: logger
        )
        var invites: [ManagedRelayInviteSummary] = []
        for try await row in rows.decode((UUID, Date, Date?).self) {
            invites.append(ManagedRelayInviteSummary(
                id: row.0, expiresAt: row.1, consumedAt: row.2
            ))
        }
        return invites
    }

    public func listAuditEvents() async throws -> [ManagedRelayAuditSummary] {
        let rows = try await client.query(
            "SELECT id, space_id, actor_device_id, action, target_id, allowed, created_at FROM audit_events ORDER BY created_at DESC LIMIT 200",
            logger: logger
        )
        var events: [ManagedRelayAuditSummary] = []
        for try await row in rows.decode((UUID, UUID?, UUID?, String, UUID?, Bool, Date).self) {
            events.append(ManagedRelayAuditSummary(
                id: row.0, spaceID: row.1, actorDeviceID: row.2,
                action: row.3, targetID: row.4, allowed: row.5, createdAt: row.6
            ))
        }
        return events
    }

    public func listDeviceSummaries(spaceID: UUID) async throws -> [ManagedRelayDeviceSummary] {
        let rows = try await client.query(
            "SELECT id, space_id, name, kind, status, last_seen_at FROM devices WHERE space_id = \(spaceID) ORDER BY created_at",
            logger: logger
        )
        var devices: [ManagedRelayDeviceSummary] = []
        for try await row in rows.decode((UUID, UUID, String, String, String, Date?).self) {
            devices.append(ManagedRelayDeviceSummary(
                id: row.0, spaceID: row.1, name: row.2,
                kind: row.3, status: row.4, lastSeenAt: row.5
            ))
        }
        return devices
    }

    public func revokeDeviceAsAdmin(id: UUID) async throws -> UUID {
        try await client.withTransaction(logger: logger) { connection in
            let rows = try await connection.query(
                "UPDATE devices SET status = 'revoked' WHERE id = \(id) AND status = 'active' RETURNING space_id",
                logger: logger
            )
            var spaceID: UUID?
            for try await value in rows.decode(UUID.self) { spaceID = value }
            guard let spaceID else { throw ManagedRelayError.forbidden }
            try await connection.query(
                "UPDATE device_sessions SET revoked_at = now() WHERE device_id = \(id) AND revoked_at IS NULL",
                logger: logger
            )
            try await connection.query(
                "INSERT INTO audit_events (id, space_id, action, target_id, allowed) VALUES (\(UUID()), \(spaceID), 'admin.device.revoke', \(id), true)",
                logger: logger
            )
            return spaceID
        }
    }

    public func touchDevice(id: UUID) async throws {
        try await client.query(
            "UPDATE devices SET last_seen_at = now() WHERE id = \(id)",
            logger: logger
        )
    }

    public func rotateRecoveryCodes(actor: RemoteDevice) async throws -> [String] {
        guard actor.kind == .host, actor.status == .active else {
            throw ManagedRelayError.forbidden
        }
        let codes = (0..<10).map { _ in RemoteSecret.random(byteCount: 16) }
        let hashes = codes.map { RemoteSecret.digest($0, pepper: pepper) }
        try await client.withTransaction(logger: logger) { connection in
            try await connection.query(
                "DELETE FROM recovery_codes WHERE space_id = \(actor.spaceID)",
                logger: logger
            )
            for hash in hashes {
                try await connection.query(
                    "INSERT INTO recovery_codes (space_id, code_hash, pepper_version) VALUES (\(actor.spaceID), \(hash), 1)",
                    logger: logger
                )
            }
            try await connection.query(
                "INSERT INTO audit_events (id, space_id, actor_device_id, action, allowed) VALUES (\(UUID()), \(actor.spaceID), \(actor.id), 'recovery_codes.rotate', true)",
                logger: logger
            )
        }
        return codes
    }

    public func revokeInvite(id: UUID) async throws {
        try await client.query(
            "UPDATE service_invites SET consumed_at = now() WHERE id = \(id) AND consumed_at IS NULL",
            logger: logger
        )
    }

    public func setSpaceSuspended(id: UUID, suspended: Bool) async throws {
        try await client.query(
            "UPDATE personal_spaces SET status = \(suspended ? "suspended" : "active") WHERE id = \(id)",
            logger: logger
        )
        if suspended {
            try await client.query(
                """
                UPDATE device_sessions SET revoked_at = now()
                WHERE device_id IN (SELECT id FROM devices WHERE space_id = \(id))
                  AND revoked_at IS NULL
                """,
                logger: logger
            )
        }
    }

    public func createServiceInvite(
        adminDeviceID: UUID,
        expiresAt: Date
    ) async throws -> String {
        let id = UUID()
        let secret = RemoteSecret.random()
        let hash = RemoteSecret.digest(secret, pepper: pepper)
        let rows = try await client.query(
            """
            INSERT INTO service_invites (id, token_hash, created_by_admin_device_id, expires_at)
            SELECT \(id), \(hash), id, \(expiresAt)
            FROM admin_devices
            WHERE id = \(adminDeviceID) AND status = 'active'
            RETURNING id
            """,
            logger: logger
        )
        var issued = false
        for try await _ in rows.decode(UUID.self) { issued = true }
        guard issued else { throw ManagedRelayDatabaseError.adminUnavailable }
        return "\(id.uuidString).\(secret)"
    }

    public func consumeServiceInvite(
        _ invite: String,
        hostName: String,
        signingPublicKey: Data,
        encryptionPublicKey: Data,
        encryptionKeySignature: Data
    ) async throws -> ManagedEnrollment {
        let pieces = invite.split(separator: ".", maxSplits: 1).map(String.init)
        guard pieces.count == 2,
              let inviteID = UUID(uuidString: pieces[0]),
              RemoteDeviceKeys.verifyEncryptionKey(
                signingPublicKey: signingPublicKey,
                encryptionPublicKey: encryptionPublicKey,
                signature: encryptionKeySignature
              ) else {
            throw ManagedRelayDatabaseError.inviteUnavailable
        }
        let hash = RemoteSecret.digest(pieces[1], pepper: pepper)
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
        let codes = (0..<10).map { _ in RemoteSecret.random(byteCount: 16) }
        let codeHashes = codes.map { RemoteSecret.digest($0, pepper: pepper) }

        try await client.withTransaction(logger: logger) { connection in
            let inviteRows = try await connection.query(
                """
                UPDATE service_invites SET consumed_at = now()
                WHERE id = \(inviteID) AND token_hash = \(hash)
                  AND consumed_at IS NULL AND expires_at > now()
                RETURNING id
                """,
                logger: logger
            )
            var consumed = false
            for try await _ in inviteRows.decode(UUID.self) {
                consumed = true
            }
            guard consumed else { throw ManagedRelayDatabaseError.inviteUnavailable }
            try await connection.query(
                "INSERT INTO personal_spaces (id, label, status) VALUES (\(space.id), \(space.label), 'active')",
                logger: logger
            )
            try await connection.query(
                "INSERT INTO principals (id, space_id, role) VALUES (\(principalID), \(space.id), 'owner')",
                logger: logger
            )
            try await connection.query(
                """
                INSERT INTO devices
                    (id, space_id, principal_id, kind, name, signing_public_key,
                     encryption_public_key, encryption_key_signature, capabilities, status)
                VALUES
                    (\(device.id), \(space.id), \(principalID), 'host', \(device.name),
                     \(signingPublicKey), \(encryptionPublicKey), \(encryptionKeySignature),
                     ARRAY['sloppy.core.remote','sloppy.terminal.control'], 'active')
                """,
                logger: logger
            )
            for codeHash in codeHashes {
                try await connection.query(
                    "INSERT INTO recovery_codes (space_id, code_hash, pepper_version) VALUES (\(space.id), \(codeHash), 1)",
                    logger: logger
                )
            }
            try await connection.query(
                "INSERT INTO audit_events (id, space_id, actor_device_id, action, target_id, allowed) VALUES (\(UUID()), \(space.id), \(device.id), 'space.enroll', \(device.id), true)",
                logger: logger
            )
        }
        return ManagedEnrollment(space: space, device: device, recoveryCodes: codes)
    }

    public func device(id: UUID) async throws -> RemoteDevice? {
        let rows = try await client.query(
            """
            SELECT id, space_id, principal_id, kind, name, signing_public_key,
                   encryption_public_key, encryption_key_signature,
                   array_to_string(capabilities, ','), status
            FROM devices WHERE id = \(id)
            """,
            logger: logger
        )
        for try await row in rows.decode(
            (UUID, UUID, UUID, String, String, Data, Data, Data, String, String).self
        ) {
            guard let kind = RemoteDeviceKind(rawValue: row.3),
                  let status = RemoteDeviceStatus(rawValue: row.9) else {
                continue
            }
            return RemoteDevice(
                id: row.0,
                spaceID: row.1,
                principalID: row.2,
                kind: kind,
                name: row.4,
                signingPublicKey: row.5,
                encryptionPublicKey: row.6,
                encryptionKeySignature: row.7,
                capabilities: Set(row.8.split(separator: ",").map(String.init)),
                status: status
            )
        }
        return nil
    }

    public func devices(spaceID: UUID) async throws -> [RemoteDevice] {
        let rows = try await client.query(
            "SELECT id FROM devices WHERE space_id = \(spaceID) AND status = 'active' ORDER BY name",
            logger: logger
        )
        var result: [RemoteDevice] = []
        for try await id in rows.decode(UUID.self) {
            if let device = try await device(id: id) {
                result.append(device)
            }
        }
        return result
    }

    public func createPairing(
        creator: RemoteDevice,
        kind: RemoteDeviceKind,
        relayURL: URL,
        now: Date = Date()
    ) async throws -> RemotePairingCode {
        guard creator.status == .active, creator.kind == .host,
              kind == .mobile || kind == .host,
              relayURL.scheme == "https" else {
            throw ManagedRelayError.forbidden
        }
        let id = UUID()
        let nonce = RemoteSecret.random()
        let expiresAt = now.addingTimeInterval(120)
        let hash = RemoteSecret.digest(nonce, pepper: pepper)
        try await client.query(
            """
            INSERT INTO device_pairings
                (id, space_id, created_by_device_id, claim_nonce_hash,
                 requested_kind, status, expires_at)
            VALUES
                (\(id), \(creator.spaceID), \(creator.id), \(hash),
                 \(kind.rawValue), 'open', \(expiresAt))
            """,
            logger: logger
        )
        return RemotePairingCode(
            relayURL: relayURL,
            pairingID: id,
            claimNonce: nonce,
            expiresAt: expiresAt
        )
    }

    public func claimPairing(
        id: UUID,
        nonce: String,
        claimedDeviceID: UUID,
        kind: RemoteDeviceKind,
        name: String,
        signingPublicKey: Data,
        encryptionPublicKey: Data,
        encryptionKeySignature: Data,
        claimSignature: Data
    ) async throws {
        guard RemoteDeviceKeys.verify(
            signature: claimSignature,
            challenge: Data("sloppy-remote-pair-v1:\(id):\(nonce)".utf8),
            publicKey: signingPublicKey
        ), RemoteDeviceKeys.verifyEncryptionKey(
            signingPublicKey: signingPublicKey,
            encryptionPublicKey: encryptionPublicKey,
            signature: encryptionKeySignature
        ) else { throw ManagedRelayError.invalidSignature }
        let hash = RemoteSecret.digest(nonce, pepper: pepper)
        let rows = try await client.query(
            """
            UPDATE device_pairings
            SET status = 'pending', claimed_device_id = \(claimedDeviceID),
                claimed_name = \(String(name.prefix(80))),
                claimed_signing_public_key = \(signingPublicKey),
                claimed_encryption_public_key = \(encryptionPublicKey),
                claimed_encryption_key_signature = \(encryptionKeySignature)
            WHERE id = \(id) AND claim_nonce_hash = \(hash)
              AND requested_kind = \(kind.rawValue)
              AND status = 'open' AND expires_at > now()
            RETURNING id
            """,
            logger: logger
        )
        var claimed = false
        for try await _ in rows.decode(UUID.self) { claimed = true }
        guard claimed else { throw ManagedRelayError.invalidPairing }
    }

    public func pairingStatus(id: UUID, nonce: String) async throws -> ManagedPairingRequest? {
        let hash = RemoteSecret.digest(nonce, pepper: pepper)
        let rows = try await client.query(
            """
            SELECT space_id, created_by_device_id, requested_kind, status,
                   expires_at, claimed_device_id, claimed_name,
                   claimed_signing_public_key, claimed_encryption_public_key,
                   claimed_encryption_key_signature
            FROM device_pairings
            WHERE id = \(id) AND claim_nonce_hash = \(hash)
            """,
            logger: logger
        )
        for try await row in rows.decode(
            (UUID, UUID, String, String, Date, UUID?, String?, Data?, Data?, Data?).self
        ) {
            guard row.4 > Date(),
                  let kind = RemoteDeviceKind(rawValue: row.2),
                  let status = ManagedPairingRequest.Status(rawValue: row.3) else {
                return nil
            }
            return ManagedPairingRequest(
                id: id,
                spaceID: row.0,
                createdByDeviceID: row.1,
                kind: kind,
                status: status,
                expiresAt: row.4,
                claimedDeviceID: row.5,
                claimedName: row.6,
                claimedSigningPublicKey: row.7,
                claimedEncryptionPublicKey: row.8,
                claimedEncryptionKeySignature: row.9
            )
        }
        return nil
    }

    public func pendingPairings(spaceID: UUID, creatorID: UUID) async throws -> [ManagedPairingRequest] {
        let rows = try await client.query(
            """
            SELECT id FROM device_pairings
            WHERE space_id = \(spaceID) AND created_by_device_id = \(creatorID)
              AND status = 'pending' AND expires_at > now()
            ORDER BY created_at
            """,
            logger: logger
        )
        var requests: [ManagedPairingRequest] = []
        for try await id in rows.decode(UUID.self) {
            let requestRows = try await client.query(
                """
                SELECT space_id, created_by_device_id, requested_kind, status, expires_at,
                       claimed_device_id, claimed_name, claimed_signing_public_key,
                       claimed_encryption_public_key, claimed_encryption_key_signature
                FROM device_pairings WHERE id = \(id)
                """,
                logger: logger
            )
            for try await row in requestRows.decode(
                (UUID, UUID, String, String, Date, UUID?, String?, Data?, Data?, Data?).self
            ) {
                guard let kind = RemoteDeviceKind(rawValue: row.2),
                      let status = ManagedPairingRequest.Status(rawValue: row.3) else { continue }
                requests.append(ManagedPairingRequest(
                    id: id,
                    spaceID: row.0,
                    createdByDeviceID: row.1,
                    kind: kind,
                    status: status,
                    expiresAt: row.4,
                    claimedDeviceID: row.5,
                    claimedName: row.6,
                    claimedSigningPublicKey: row.7,
                    claimedEncryptionPublicKey: row.8,
                    claimedEncryptionKeySignature: row.9
                ))
            }
        }
        return requests
    }

    public func decidePairing(
        id: UUID,
        approvingHost: RemoteDevice,
        approve: Bool
    ) async throws -> RemoteDevice? {
        guard approvingHost.kind == .host, approvingHost.status == .active else {
            throw ManagedRelayError.forbidden
        }
        return try await client.withTransaction(logger: logger) { connection in
            let rows = try await connection.query(
                """
                SELECT space_id, created_by_device_id, requested_kind,
                       claimed_device_id, claimed_name, claimed_signing_public_key,
                       claimed_encryption_public_key, claimed_encryption_key_signature
                FROM device_pairings
                WHERE id = \(id) AND status = 'pending' AND expires_at > now()
                FOR UPDATE
                """,
                logger: logger
            )
            var pending: (UUID, UUID, String, UUID, String, Data, Data, Data)?
            for try await row in rows.decode(
                (UUID, UUID, String, UUID, String, Data, Data, Data).self
            ) {
                pending = row
            }
            guard let pending,
                  pending.0 == approvingHost.spaceID,
                  pending.1 == approvingHost.id,
                  let kind = RemoteDeviceKind(rawValue: pending.2) else {
                throw ManagedRelayError.forbidden
            }
            try await connection.query(
                "UPDATE device_pairings SET status = \(approve ? "approved" : "rejected") WHERE id = \(id)",
                logger: logger
            )
            try await connection.query(
                "INSERT INTO audit_events (id, space_id, actor_device_id, action, target_id, allowed) VALUES (\(UUID()), \(approvingHost.spaceID), \(approvingHost.id), \(approve ? "pairing.approve" : "pairing.reject"), \(pending.3), true)",
                logger: logger
            )
            guard approve else { return nil }
            let capabilities: Set<String> = kind == .host
                ? ["sloppy.core.remote", "sloppy.terminal.control"]
                : ["sloppy.core.remote", "sloppy.terminal.control"]
            let device = RemoteDevice(
                id: pending.3,
                spaceID: pending.0,
                principalID: approvingHost.principalID,
                kind: kind,
                name: pending.4,
                signingPublicKey: pending.5,
                encryptionPublicKey: pending.6,
                encryptionKeySignature: pending.7,
                capabilities: capabilities
            )
            try await connection.query(
                """
                INSERT INTO devices
                    (id, space_id, principal_id, kind, name, signing_public_key,
                     encryption_public_key, encryption_key_signature, capabilities, status)
                VALUES
                    (\(device.id), \(device.spaceID), \(device.principalID),
                     \(kind.rawValue), \(device.name), \(device.signingPublicKey),
                     \(device.encryptionPublicKey), \(device.encryptionKeySignature),
                     ARRAY['sloppy.core.remote','sloppy.terminal.control'], 'active')
                """,
                logger: logger
            )
            return device
        }
    }

    public func saveSession(token: String, deviceID: UUID, expiresAt: Date) async throws {
        let hash = RemoteSecret.digest(token, pepper: pepper)
        try await client.query(
            "INSERT INTO device_sessions (token_hash, device_id, expires_at) VALUES (\(hash), \(deviceID), \(expiresAt))",
            logger: logger
        )
    }

    public func device(forSessionToken token: String, now: Date = Date()) async throws -> RemoteDevice? {
        let hash = RemoteSecret.digest(token, pepper: pepper)
        let rows = try await client.query(
            """
            SELECT s.device_id
            FROM device_sessions s
            JOIN devices d ON d.id = s.device_id
            JOIN personal_spaces p ON p.id = d.space_id
            WHERE s.token_hash = \(hash) AND s.expires_at > \(now)
              AND s.revoked_at IS NULL AND d.status = 'active' AND p.status = 'active'
            """,
            logger: logger
        )
        for try await id in rows.decode(UUID.self) {
            return try await device(id: id)
        }
        return nil
    }

    public func revokeDevice(id: UUID, actor: RemoteDevice) async throws {
        guard actor.kind == .host, actor.status == .active else {
            throw ManagedRelayError.forbidden
        }
        try await client.withTransaction(logger: logger) { connection in
            let rows = try await connection.query(
                """
                UPDATE devices SET status = 'revoked'
                WHERE id = \(id) AND space_id = \(actor.spaceID) AND status = 'active'
                RETURNING id
                """,
                logger: logger
            )
            var revoked = false
            for try await _ in rows.decode(UUID.self) { revoked = true }
            guard revoked else { throw ManagedRelayError.forbidden }
            try await connection.query(
                "UPDATE device_sessions SET revoked_at = now() WHERE device_id = \(id) AND revoked_at IS NULL",
                logger: logger
            )
            try await connection.query(
                "INSERT INTO audit_events (id, space_id, actor_device_id, action, target_id, allowed) VALUES (\(UUID()), \(actor.spaceID), \(actor.id), 'device.revoke', \(id), true)",
                logger: logger
            )
        }
    }

    public func recover(
        spaceID: UUID,
        code: String,
        name: String,
        signingPublicKey: Data,
        encryptionPublicKey: Data,
        encryptionKeySignature: Data
    ) async throws -> RemoteDevice {
        guard RemoteDeviceKeys.verifyEncryptionKey(
            signingPublicKey: signingPublicKey,
            encryptionPublicKey: encryptionPublicKey,
            signature: encryptionKeySignature
        ) else { throw ManagedRelayError.invalidSignature }
        let hash = RemoteSecret.digest(code, pepper: pepper)
        return try await client.withTransaction(logger: logger) { connection in
            let codeRows = try await connection.query(
                """
                UPDATE recovery_codes SET consumed_at = now()
                WHERE space_id = \(spaceID) AND code_hash = \(hash)
                  AND consumed_at IS NULL
                RETURNING space_id
                """,
                logger: logger
            )
            var consumed = false
            for try await _ in codeRows.decode(UUID.self) { consumed = true }
            guard consumed else { throw ManagedRelayError.invalidRecoveryCode }
            let ownerRows = try await connection.query(
                """
                SELECT p.id FROM principals p
                JOIN personal_spaces s ON s.id = p.space_id
                WHERE p.space_id = \(spaceID) AND p.role = 'owner' AND s.status = 'active'
                LIMIT 1
                """,
                logger: logger
            )
            var ownerID: UUID?
            for try await id in ownerRows.decode(UUID.self) { ownerID = id }
            guard let ownerID else { throw ManagedRelayError.invalidRecoveryCode }
            let device = RemoteDevice(
                spaceID: spaceID,
                principalID: ownerID,
                kind: .host,
                name: String(name.prefix(80)),
                signingPublicKey: signingPublicKey,
                encryptionPublicKey: encryptionPublicKey,
                encryptionKeySignature: encryptionKeySignature,
                capabilities: ["sloppy.core.remote", "sloppy.terminal.control"]
            )
            try await connection.query(
                """
                INSERT INTO devices
                    (id, space_id, principal_id, kind, name, signing_public_key,
                     encryption_public_key, encryption_key_signature, capabilities, status)
                VALUES
                    (\(device.id), \(spaceID), \(ownerID), 'host', \(device.name),
                     \(signingPublicKey), \(encryptionPublicKey), \(encryptionKeySignature),
                     ARRAY['sloppy.core.remote','sloppy.terminal.control'], 'active')
                """,
                logger: logger
            )
            try await connection.query(
                "INSERT INTO audit_events (id, space_id, action, target_id, allowed) VALUES (\(UUID()), \(spaceID), 'space.recover', \(device.id), true)",
                logger: logger
            )
            return device
        }
    }
}
