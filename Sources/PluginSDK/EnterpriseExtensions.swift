import Foundation
import Protocols

/// Product edition reported by a running Sloppy control plane.
public enum SloppyProductEdition: String, Codable, Sendable, Equatable {
    case community
    case enterprise
}

/// Stable feature identifiers understood by public core and private modules.
public enum EnterpriseFeature: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case oidc
    case groupMapping = "group_mapping"
    case authorizationPolicies = "authorization_policies"
    case auditExport = "audit_export"
    case offlineEntitlement = "offline_entitlement"
}

/// Verified, immutable commercial rights available to a running module.
///
/// Signature parsing and Ed25519 verification intentionally live in the
/// private Enterprise package. Public core only consumes a verified snapshot.
public struct EntitlementSnapshot: Codable, Sendable, Equatable {
    public var licenseID: String
    public var customer: String
    public var customerID: String
    public var permittedAffiliateIDs: [String]
    public var features: [EnterpriseFeature]
    public var activeHumanUserLimit: Int
    public var productionControlPlaneLimit: Int
    public var issuedAt: Date
    public var updatesUntil: Date

    public init(
        licenseID: String,
        customer: String,
        customerID: String,
        permittedAffiliateIDs: [String] = [],
        features: [EnterpriseFeature],
        activeHumanUserLimit: Int,
        productionControlPlaneLimit: Int = 1,
        issuedAt: Date,
        updatesUntil: Date
    ) {
        self.licenseID = licenseID
        self.customer = customer
        self.customerID = customerID
        self.permittedAffiliateIDs = permittedAffiliateIDs
        self.features = features
        self.activeHumanUserLimit = activeHumanUserLimit
        self.productionControlPlaneLimit = productionControlPlaneLimit
        self.issuedAt = issuedAt
        self.updatesUntil = updatesUntil
    }

    public func allows(_ feature: EnterpriseFeature) -> Bool {
        features.contains(feature)
    }

    /// Perpetual fallback: releases published on or before `updatesUntil`
    /// remain eligible even after the updates term has ended.
    public func allowsRelease(publishedAt: Date) -> Bool {
        publishedAt <= updatesUntil
    }
}

/// Transport envelope for an offline entitlement.
///
/// `payload` and `signature` are base64 strings. Verification must happen
/// before constructing an `EntitlementSnapshot`.
public struct SignedEntitlementEnvelope: Codable, Sendable, Equatable {
    public var keyID: String
    public var payload: String
    public var signature: String

    public init(keyID: String, payload: String, signature: String) {
        self.keyID = keyID
        self.payload = payload
        self.signature = signature
    }
}

public protocol EntitlementProvider: Sendable {
    /// Returns only a cryptographically verified entitlement. Invalid,
    /// expired-for-this-release, or mismatched keys should throw.
    func currentEntitlement() async throws -> EntitlementSnapshot
}

public struct IdentityProviderDescriptor: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var authorizationPath: String
    public var callbackPath: String

    public init(
        id: String,
        title: String,
        authorizationPath: String,
        callbackPath: String
    ) {
        self.id = id
        self.title = title
        self.authorizationPath = authorizationPath
        self.callbackPath = callbackPath
    }
}

public struct EnterpriseIdentity: Codable, Sendable, Equatable {
    public var profile: AuthUserProfile
    public var providerID: String
    public var groups: [String]
    public var claims: [String: JSONValue]

    public init(
        profile: AuthUserProfile,
        providerID: String,
        groups: [String] = [],
        claims: [String: JSONValue] = [:]
    ) {
        self.profile = profile
        self.providerID = providerID
        self.groups = groups
        self.claims = claims
    }
}

/// Enterprise identity bridge. A private module owns OIDC discovery, login,
/// callback routes, token verification, and group-to-role mapping.
public protocol IdentityProvider: Sendable {
    var descriptor: IdentityProviderDescriptor { get }
    func authenticate(bearerToken: String) async throws -> EnterpriseIdentity?
}

public struct AuthorizationSubject: Codable, Sendable, Equatable {
    public var userID: String
    public var role: AuthUserRole
    public var groups: [String]
    public var identityProviderID: String?

    public init(
        userID: String,
        role: AuthUserRole,
        groups: [String] = [],
        identityProviderID: String? = nil
    ) {
        self.userID = userID
        self.role = role
        self.groups = groups
        self.identityProviderID = identityProviderID
    }
}

public struct AuthorizationResource: Codable, Sendable, Equatable {
    public var kind: String
    public var id: String
    public var projectID: String?
    public var attributes: [String: JSONValue]

    public init(
        kind: String,
        id: String,
        projectID: String? = nil,
        attributes: [String: JSONValue] = [:]
    ) {
        self.kind = kind
        self.id = id
        self.projectID = projectID
        self.attributes = attributes
    }
}

public struct AuthorizationRequest: Codable, Sendable, Equatable {
    public var subject: AuthorizationSubject
    public var action: String
    public var resource: AuthorizationResource
    public var context: [String: JSONValue]

    public init(
        subject: AuthorizationSubject,
        action: String,
        resource: AuthorizationResource,
        context: [String: JSONValue] = [:]
    ) {
        self.subject = subject
        self.action = action
        self.resource = resource
        self.context = context
    }
}

public struct AuthorizationDecision: Codable, Sendable, Equatable {
    public var allowed: Bool
    public var reason: String?
    public var policyID: String?

    public init(allowed: Bool, reason: String? = nil, policyID: String? = nil) {
        self.allowed = allowed
        self.reason = reason
        self.policyID = policyID
    }

    public static func allow(policyID: String? = nil) -> AuthorizationDecision {
        AuthorizationDecision(allowed: true, policyID: policyID)
    }

    public static func deny(reason: String, policyID: String? = nil) -> AuthorizationDecision {
        AuthorizationDecision(allowed: false, reason: reason, policyID: policyID)
    }
}

public protocol AuthorizationPolicyProvider: Sendable {
    func evaluate(_ request: AuthorizationRequest) async throws -> AuthorizationDecision
}

public enum AuditOutcome: String, Codable, Sendable, Equatable {
    case allowed
    case denied
    case failed
}

public struct AuditEvent: Codable, Sendable, Equatable {
    public var id: String
    public var timestamp: Date
    public var actorID: String?
    public var action: String
    public var resourceKind: String
    public var resourceID: String?
    public var outcome: AuditOutcome
    public var correlationID: String?
    public var metadata: [String: JSONValue]

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        actorID: String? = nil,
        action: String,
        resourceKind: String,
        resourceID: String? = nil,
        outcome: AuditOutcome,
        correlationID: String? = nil,
        metadata: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.actorID = actorID
        self.action = action
        self.resourceKind = resourceKind
        self.resourceID = resourceID
        self.outcome = outcome
        self.correlationID = correlationID
        self.metadata = metadata
    }
}

public enum AuditExportFormat: String, Codable, Sendable, Equatable {
    case jsonLines = "jsonl"
}

public struct AuditExportRequest: Codable, Sendable, Equatable {
    public var from: Date?
    public var through: Date?
    public var maximumEventCount: Int?
    public var format: AuditExportFormat

    public init(
        from: Date? = nil,
        through: Date? = nil,
        maximumEventCount: Int? = nil,
        format: AuditExportFormat = .jsonLines
    ) {
        self.from = from
        self.through = through
        self.maximumEventCount = maximumEventCount
        self.format = format
    }
}

/// Append-only audit boundary. Implementations must redact secrets before
/// persistence and export.
public protocol AuditSink: Sendable {
    func record(_ event: AuditEvent) async throws
    func export(_ request: AuditExportRequest) async throws -> Data
}

public struct EnterpriseUIContribution: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var path: String
    public var icon: String?
    public var requiredFeature: EnterpriseFeature?

    public init(
        id: String,
        title: String,
        path: String,
        icon: String? = nil,
        requiredFeature: EnterpriseFeature? = nil
    ) {
        self.id = id
        self.title = title
        self.path = path
        self.icon = icon
        self.requiredFeature = requiredFeature
    }
}

public struct EnterpriseModuleDescriptor: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var version: String
    public var capabilities: [EnterpriseFeature]

    public init(
        id: String,
        title: String,
        version: String,
        capabilities: [EnterpriseFeature]
    ) {
        self.id = id
        self.title = title
        self.version = version
        self.capabilities = capabilities
    }
}

/// Stable composition point implemented by the private `SloppyEnterprise`
/// package. Community supplies an empty module list.
public protocol EnterpriseModule: Sendable {
    var descriptor: EnterpriseModuleDescriptor { get }
    var entitlementProvider: (any EntitlementProvider)? { get }
    var identityProvider: (any IdentityProvider)? { get }
    var authorizationPolicyProvider: (any AuthorizationPolicyProvider)? { get }
    var auditSink: (any AuditSink)? { get }
    var uiContributions: [EnterpriseUIContribution] { get }
}

public extension EnterpriseModule {
    var entitlementProvider: (any EntitlementProvider)? { nil }
    var identityProvider: (any IdentityProvider)? { nil }
    var authorizationPolicyProvider: (any AuthorizationPolicyProvider)? { nil }
    var auditSink: (any AuditSink)? { nil }
    var uiContributions: [EnterpriseUIContribution] { [] }
}

public struct EnterpriseRuntimeStatus: Codable, Sendable, Equatable {
    public var edition: SloppyProductEdition
    public var modules: [EnterpriseModuleDescriptor]
    public var capabilities: [EnterpriseFeature]
    public var uiContributions: [EnterpriseUIContribution]
    public var entitlement: EntitlementSummary?

    public init(
        edition: SloppyProductEdition,
        modules: [EnterpriseModuleDescriptor],
        capabilities: [EnterpriseFeature],
        uiContributions: [EnterpriseUIContribution],
        entitlement: EntitlementSummary? = nil
    ) {
        self.edition = edition
        self.modules = modules
        self.capabilities = capabilities
        self.uiContributions = uiContributions
        self.entitlement = entitlement
    }
}

public struct EntitlementSummary: Codable, Sendable, Equatable {
    public var customer: String
    public var activeHumanUserLimit: Int
    public var updatesUntil: Date

    public init(customer: String, activeHumanUserLimit: Int, updatesUntil: Date) {
        self.customer = customer
        self.activeHumanUserLimit = activeHumanUserLimit
        self.updatesUntil = updatesUntil
    }
}
