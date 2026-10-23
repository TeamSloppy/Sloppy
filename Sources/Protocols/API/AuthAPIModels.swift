import Foundation

public enum AuthMode: String, Codable, Sendable, Equatable {
    case token
    case loginPassword = "login_password"
    case console
}

public enum AuthUserRole: String, Codable, Sendable, Equatable, CaseIterable {
    case admin
    case user
    case `operator`
    case approver
    case auditor
    case viewer

    public var isCommunityRole: Bool {
        self == .admin || self == .user
    }
}

public enum AuthUserStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case active
    case disabled
}

public struct AuthUserProfile: Codable, Sendable, Equatable {
    public var id: String
    public var login: String
    public var name: String
    public var avatar: String
    public var description: String
    public var role: AuthUserRole
    public var status: AuthUserStatus

    public init(
        id: String,
        login: String,
        name: String,
        avatar: String = "",
        description: String = "",
        role: AuthUserRole,
        status: AuthUserStatus = .active
    ) {
        self.id = id
        self.login = login
        self.name = name
        self.avatar = avatar
        self.description = description
        self.role = role
        self.status = status
    }
}

public struct AuthChallengeResponse: Codable, Sendable, Equatable {
    public var mode: AuthMode
    public var bootstrapRequired: Bool
    public var passkeySupported: Bool
    public var accessTokenExpiresInSeconds: Int
    public var refreshTokenExpiresInSeconds: Int

    public init(
        mode: AuthMode,
        bootstrapRequired: Bool,
        passkeySupported: Bool,
        accessTokenExpiresInSeconds: Int,
        refreshTokenExpiresInSeconds: Int
    ) {
        self.mode = mode
        self.bootstrapRequired = bootstrapRequired
        self.passkeySupported = passkeySupported
        self.accessTokenExpiresInSeconds = accessTokenExpiresInSeconds
        self.refreshTokenExpiresInSeconds = refreshTokenExpiresInSeconds
    }
}

public struct AuthModeUpdateRequest: Codable, Sendable, Equatable {
    public var mode: AuthMode
    public var confirmIrreversible: Bool

    public init(mode: AuthMode, confirmIrreversible: Bool) {
        self.mode = mode
        self.confirmIrreversible = confirmIrreversible
    }
}

public struct AuthSessionResponse: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var accessTokenExpiresAt: Date
    public var refreshTokenExpiresAt: Date
    public var user: AuthUserProfile

    public init(
        accessToken: String,
        refreshToken: String,
        accessTokenExpiresAt: Date,
        refreshTokenExpiresAt: Date,
        user: AuthUserProfile
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
        self.user = user
    }
}

public struct AuthLoginRequest: Codable, Sendable, Equatable {
    public var login: String
    public var password: String

    public init(login: String, password: String) {
        self.login = login
        self.password = password
    }
}

public struct AuthRefreshRequest: Codable, Sendable, Equatable {
    public var refreshToken: String

    public init(refreshToken: String) {
        self.refreshToken = refreshToken
    }
}

public struct AuthDevicePairingCreateRequest: Codable, Sendable, Equatable {
    public var clientName: String
    public var ttlSeconds: Int

    public init(clientName: String = "Sloppy Client", ttlSeconds: Int = 120) {
        self.clientName = clientName
        self.ttlSeconds = ttlSeconds
    }
}

public struct AuthDevicePairingRecord: Codable, Sendable, Equatable {
    public var id: String
    public var token: String
    public var clientName: String
    public var createdAt: Date
    public var expiresAt: Date
    public var user: AuthUserProfile
    public var setupCode: String?
    public var serverURL: String?

    public init(
        id: String,
        token: String,
        clientName: String,
        createdAt: Date = Date(),
        expiresAt: Date,
        user: AuthUserProfile,
        setupCode: String? = nil,
        serverURL: String? = nil
    ) {
        self.id = id
        self.token = token
        self.clientName = clientName
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.user = user
        self.setupCode = setupCode
        self.serverURL = serverURL
    }
}

public struct AuthDevicePairingSetupPayload: Codable, Sendable, Equatable {
    public var version: Int
    public var url: String
    public var urls: [String]?
    public var bootstrapToken: String
    public var expiresAt: Date
    public var tlsFingerprint: String?
    public var label: String?

    public init(
        version: Int = 1,
        url: String,
        urls: [String]? = nil,
        bootstrapToken: String,
        expiresAt: Date,
        tlsFingerprint: String? = nil,
        label: String? = nil
    ) {
        self.version = version
        self.url = url
        self.urls = urls
        self.bootstrapToken = bootstrapToken
        self.expiresAt = expiresAt
        self.tlsFingerprint = tlsFingerprint
        self.label = label
    }
}

public struct AuthTLSCertificateFingerprintResponse: Codable, Sendable, Equatable {
    public var url: String
    public var algorithm: String
    public var fingerprint: String

    public init(url: String, algorithm: String = "sha256", fingerprint: String) {
        self.url = url
        self.algorithm = algorithm
        self.fingerprint = fingerprint
    }
}

public struct AuthDevicePairingRedeemRequest: Codable, Sendable, Equatable {
    public var token: String

    public init(token: String) {
        self.token = token
    }
}

public struct AuthApplicationTokenCreateRequest: Codable, Sendable, Equatable {
    public var name: String
    public var expiresInSeconds: Int?

    public init(name: String, expiresInSeconds: Int? = nil) {
        self.name = name
        self.expiresInSeconds = expiresInSeconds
    }
}

public struct AuthApplicationTokenRecord: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var token: String?
    public var tokenPrefix: String
    public var createdAt: Date
    public var expiresAt: Date

    public init(
        id: String,
        name: String,
        token: String? = nil,
        tokenPrefix: String,
        createdAt: Date = Date(),
        expiresAt: Date
    ) {
        self.id = id
        self.name = name
        self.token = token
        self.tokenPrefix = tokenPrefix
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

public struct AuthBootstrapAdminRequest: Codable, Sendable, Equatable {
    public var login: String
    public var password: String
    public var name: String
    public var avatar: String
    public var description: String

    public init(
        login: String,
        password: String,
        name: String,
        avatar: String = "",
        description: String = ""
    ) {
        self.login = login
        self.password = password
        self.name = name
        self.avatar = avatar
        self.description = description
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        login = try container.decode(String.self, forKey: .login)
        password = try container.decode(String.self, forKey: .password)
        name = try container.decode(String.self, forKey: .name)
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
    }
}

public struct AuthInviteCreateRequest: Codable, Sendable, Equatable {
    public var role: AuthUserRole
    public var ttlSeconds: Int

    public init(role: AuthUserRole, ttlSeconds: Int) {
        self.role = role
        self.ttlSeconds = ttlSeconds
    }
}

public struct AuthInviteRecord: Codable, Sendable, Equatable {
    public var id: String
    public var token: String?
    public var role: AuthUserRole
    public var expiresAt: Date
    public var consumedAt: Date?
    public var createdAt: Date

    public init(
        id: String,
        token: String? = nil,
        role: AuthUserRole,
        expiresAt: Date,
        consumedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.token = token
        self.role = role
        self.expiresAt = expiresAt
        self.consumedAt = consumedAt
        self.createdAt = createdAt
    }
}

public struct AuthRegisterRequest: Codable, Sendable, Equatable {
    public var inviteToken: String
    public var login: String
    public var password: String
    public var name: String
    public var avatar: String
    public var description: String

    public init(
        inviteToken: String,
        login: String,
        password: String,
        name: String,
        avatar: String = "",
        description: String = ""
    ) {
        self.inviteToken = inviteToken
        self.login = login
        self.password = password
        self.name = name
        self.avatar = avatar
        self.description = description
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inviteToken = try container.decode(String.self, forKey: .inviteToken)
        login = try container.decode(String.self, forKey: .login)
        password = try container.decode(String.self, forKey: .password)
        name = try container.decode(String.self, forKey: .name)
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
    }
}

public struct AuthUserUpdateRequest: Codable, Sendable, Equatable {
    public var name: String?
    public var avatar: String?
    public var description: String?
    public var role: AuthUserRole?
    public var status: AuthUserStatus?

    public init(
        name: String? = nil,
        avatar: String? = nil,
        description: String? = nil,
        role: AuthUserRole? = nil,
        status: AuthUserStatus? = nil
    ) {
        self.name = name
        self.avatar = avatar
        self.description = description
        self.role = role
        self.status = status
    }
}

public struct AuthRecoveryCodesResponse: Codable, Sendable, Equatable {
    public var codes: [String]

    public init(codes: [String]) {
        self.codes = codes
    }
}

public struct AuthPasswordChangeRequest: Codable, Sendable, Equatable {
    public var currentPassword: String
    public var newPassword: String

    public init(currentPassword: String, newPassword: String) {
        self.currentPassword = currentPassword
        self.newPassword = newPassword
    }
}

public struct AuthPasswordResetRequest: Codable, Sendable, Equatable {
    public var login: String
    public var resetToken: String?
    public var recoveryCode: String?
    public var newPassword: String

    public init(
        login: String,
        resetToken: String? = nil,
        recoveryCode: String? = nil,
        newPassword: String
    ) {
        self.login = login
        self.resetToken = resetToken
        self.recoveryCode = recoveryCode
        self.newPassword = newPassword
    }
}

public struct AuthAdminPasswordResetResponse: Codable, Sendable, Equatable {
    public var resetToken: String
    public var expiresAt: Date

    public init(resetToken: String, expiresAt: Date) {
        self.resetToken = resetToken
        self.expiresAt = expiresAt
    }
}

public struct AuthPasskeyCredentialRecord: Codable, Sendable, Equatable {
    public var id: String
    public var userId: String
    public var credentialId: String
    public var displayName: String
    public var createdAt: Date
    public var lastUsedAt: Date?

    public init(
        id: String,
        userId: String,
        credentialId: String,
        displayName: String,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.credentialId = credentialId
        self.displayName = displayName
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}
