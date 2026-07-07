import Foundation
import Protocols
import SloppyNodeCore

struct AuthenticatedUserContext: Sendable, Equatable {
    var user: AuthUserProfile
}

enum CoreIdentityAuthError: Error, Sendable {
    case disabled
    case bootstrapAlreadyCompleted
    case bootstrapRequired
    case invalidCredentials
    case invalidInvite
    case inviteExpired
    case inviteConsumed
    case forbidden
}

actor CoreIdentityAuthService {
    static let accessTokenLifetimeSeconds = 900
    static let refreshTokenLifetimeSeconds = 604_800
    static let defaultPasswordHashIterations = 120_000

    private struct StoredUser: Sendable {
        var profile: AuthUserProfile
        var passwordHash: String
    }

    private struct StoredInvite: Sendable {
        var record: AuthInviteRecord
        var tokenHash: String
    }

    private var enabled = false
    private var usersByID: [String: StoredUser] = [:]
    private var userIDByLogin: [String: String] = [:]
    private var accessTokens: [String: (userID: String, expiresAt: Date)] = [:]
    private var refreshTokens: [String: (userID: String, expiresAt: Date)] = [:]
    private var invitesByID: [String: StoredInvite] = [:]
    private let passwordHashIterations: Int

    init(passwordHashIterations: Int = 120_000) {
        self.passwordHashIterations = max(1, passwordHashIterations)
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
    }

    func isEnabled() -> Bool {
        enabled
    }

    func challenge() -> AuthChallengeResponse {
        AuthChallengeResponse(
            mode: enabled ? .loginPassword : .token,
            bootstrapRequired: enabled && usersByID.isEmpty,
            passkeySupported: false,
            accessTokenExpiresInSeconds: Self.accessTokenLifetimeSeconds,
            refreshTokenExpiresInSeconds: Self.refreshTokenLifetimeSeconds
        )
    }

    func bootstrapAdmin(_ request: AuthBootstrapAdminRequest) throws -> AuthSessionResponse {
        guard enabled else {
            throw CoreIdentityAuthError.disabled
        }
        guard usersByID.isEmpty else {
            throw CoreIdentityAuthError.bootstrapAlreadyCompleted
        }
        let login = normalizedLogin(request.login)
        guard !login.isEmpty, !request.password.isEmpty else {
            throw CoreIdentityAuthError.invalidCredentials
        }
        let profile = AuthUserProfile(
            id: makeID(prefix: "user"),
            login: login,
            name: request.name.trimmingCharacters(in: .whitespacesAndNewlines),
            avatar: request.avatar,
            description: request.description,
            role: .admin
        )
        usersByID[profile.id] = StoredUser(
            profile: profile,
            passwordHash: PasswordHash.make(for: request.password, iterations: passwordHashIterations)
        )
        userIDByLogin[profile.login] = profile.id
        return makeSession(for: profile)
    }

    func login(_ request: AuthLoginRequest) throws -> AuthSessionResponse {
        guard enabled else {
            throw CoreIdentityAuthError.disabled
        }
        guard !usersByID.isEmpty else {
            throw CoreIdentityAuthError.bootstrapRequired
        }
        let login = normalizedLogin(request.login)
        guard let userID = userIDByLogin[login],
              let stored = usersByID[userID],
              stored.profile.status == .active,
              PasswordHash.verify(password: request.password, hash: stored.passwordHash)
        else {
            throw CoreIdentityAuthError.invalidCredentials
        }
        return makeSession(for: stored.profile)
    }

    func createInvite(_ request: AuthInviteCreateRequest, actor: AuthenticatedUserContext) throws -> AuthInviteRecord {
        try requireAdmin(actor)
        let ttl = max(60, min(request.ttlSeconds, Self.refreshTokenLifetimeSeconds))
        let token = "slp_inv_" + NodeIdentityGenerator.randomToken(byteCount: 24)
        let now = Date()
        let record = AuthInviteRecord(
            id: makeID(prefix: "invite"),
            token: token,
            role: request.role,
            expiresAt: now.addingTimeInterval(TimeInterval(ttl)),
            createdAt: now
        )
        invitesByID[record.id] = StoredInvite(
            record: record,
            tokenHash: PasswordHash.make(for: token, iterations: passwordHashIterations)
        )
        return record
    }

    func register(_ request: AuthRegisterRequest) throws -> AuthSessionResponse {
        guard enabled else {
            throw CoreIdentityAuthError.disabled
        }
        let now = Date()
        guard let inviteID = invitesByID.first(where: {
            PasswordHash.verify(password: request.inviteToken, hash: $0.value.tokenHash)
        })?.key,
              var invite = invitesByID[inviteID]
        else {
            throw CoreIdentityAuthError.invalidInvite
        }
        guard invite.record.consumedAt == nil else {
            throw CoreIdentityAuthError.inviteConsumed
        }
        guard invite.record.expiresAt > now else {
            throw CoreIdentityAuthError.inviteExpired
        }

        let login = normalizedLogin(request.login)
        guard !login.isEmpty, !request.password.isEmpty, userIDByLogin[login] == nil else {
            throw CoreIdentityAuthError.invalidCredentials
        }

        let profile = AuthUserProfile(
            id: makeID(prefix: "user"),
            login: login,
            name: request.name.trimmingCharacters(in: .whitespacesAndNewlines),
            avatar: request.avatar,
            description: request.description,
            role: invite.record.role
        )
        usersByID[profile.id] = StoredUser(
            profile: profile,
            passwordHash: PasswordHash.make(for: request.password, iterations: passwordHashIterations)
        )
        userIDByLogin[profile.login] = profile.id
        invite.record.consumedAt = now
        invite.record.token = nil
        invitesByID[inviteID] = invite
        return makeSession(for: profile)
    }

    func authenticateAccessToken(_ token: String?) -> AuthenticatedUserContext? {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty,
              let session = accessTokens[trimmed],
              session.expiresAt > Date(),
              let stored = usersByID[session.userID],
              stored.profile.status == .active
        else {
            return nil
        }
        return AuthenticatedUserContext(user: stored.profile)
    }

    func requireAdmin(_ actor: AuthenticatedUserContext) throws {
        guard actor.user.role == .admin else {
            throw CoreIdentityAuthError.forbidden
        }
    }

    private func makeSession(for profile: AuthUserProfile) -> AuthSessionResponse {
        let now = Date()
        let accessToken = "slp_at_" + NodeIdentityGenerator.randomToken(byteCount: 32)
        let refreshToken = "slp_rt_" + NodeIdentityGenerator.randomToken(byteCount: 32)
        let accessExpiresAt = now.addingTimeInterval(TimeInterval(Self.accessTokenLifetimeSeconds))
        let refreshExpiresAt = now.addingTimeInterval(TimeInterval(Self.refreshTokenLifetimeSeconds))
        accessTokens[accessToken] = (profile.id, accessExpiresAt)
        refreshTokens[refreshToken] = (profile.id, refreshExpiresAt)
        return AuthSessionResponse(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accessTokenExpiresAt: accessExpiresAt,
            refreshTokenExpiresAt: refreshExpiresAt,
            user: profile
        )
    }

    private func normalizedLogin(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func makeID(prefix: String) -> String {
        prefix + "_" + NodeIdentityGenerator.randomToken(byteCount: 12)
    }
}

private enum PasswordHash {
    static let outputBytes = 32

    static func make(for password: String, iterations: Int) -> String {
        let salt = NodeIdentityGenerator.randomToken(byteCount: 24)
        let derived = pbkdf2(password: password, salt: Data(salt.utf8), iterations: iterations, outputBytes: outputBytes)
        return "pbkdf2-sha256:\(iterations):\(salt):\(base64URL(derived))"
    }

    static func verify(password: String, hash: String) -> Bool {
        let parts = hash.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4,
              parts[0] == "pbkdf2-sha256",
              let iterations = Int(parts[1])
        else {
            return false
        }
        let derived = pbkdf2(password: password, salt: Data(parts[2].utf8), iterations: iterations, outputBytes: outputBytes)
        return constantTimeEquals(base64URL(derived), parts[3])
    }

    private static func pbkdf2(password: String, salt: Data, iterations: Int, outputBytes: Int) -> [UInt8] {
        let blocks = Int(ceil(Double(outputBytes) / 32.0))
        var derived: [UInt8] = []
        let key = [UInt8](password.utf8)
        let saltBytes = [UInt8](salt)
        for blockIndex in 1...blocks {
            var blockSalt = saltBytes
            blockSalt.append(contentsOf: [
                UInt8((blockIndex >> 24) & 0xff),
                UInt8((blockIndex >> 16) & 0xff),
                UInt8((blockIndex >> 8) & 0xff),
                UInt8(blockIndex & 0xff),
            ])
            var u = TaskSyncCrypto.hmacSHA256(key: key, message: blockSalt)
            var block = u
            for _ in 1..<iterations {
                u = TaskSyncCrypto.hmacSHA256(key: key, message: u)
                for index in block.indices {
                    block[index] ^= u[index]
                }
            }
            derived.append(contentsOf: block)
        }
        return Array(derived.prefix(outputBytes))
    }

    private static func base64URL(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let a = [UInt8](lhs.utf8)
        let b = [UInt8](rhs.utf8)
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for index in a.indices {
            diff |= a[index] ^ b[index]
        }
        return diff == 0
    }
}
