import Foundation
import PluginSDK

extension CoreService {
    /// Returns Community without consulting a key server when no private
    /// modules were supplied by the process bootstrap.
    public func enterpriseRuntimeStatus() async -> EnterpriseRuntimeStatus {
        guard !enterpriseModules.isEmpty else {
            return EnterpriseRuntimeStatus(
                edition: .community,
                modules: [],
                capabilities: [],
                uiContributions: []
            )
        }

        let descriptors = enterpriseModules
            .map(\.descriptor)
            .sorted { $0.id < $1.id }
        var entitlementSummary: EntitlementSummary?
        var entitledFeatures: Set<EnterpriseFeature>?
        var hasEntitlementProvider = false
        for module in enterpriseModules {
            guard let provider = module.entitlementProvider else {
                continue
            }
            hasEntitlementProvider = true
            guard let snapshot = try? await provider.currentEntitlement() else {
                continue
            }
            entitlementSummary = EntitlementSummary(
                customer: snapshot.customer,
                activeHumanUserLimit: snapshot.activeHumanUserLimit,
                updatesUntil: snapshot.updatesUntil
            )
            entitledFeatures = Set(snapshot.features)
            break
        }

        let declaredCapabilities = Set(descriptors.flatMap(\.capabilities))
        let effectiveCapabilities: Set<EnterpriseFeature>
        if let entitledFeatures {
            effectiveCapabilities = declaredCapabilities.intersection(entitledFeatures)
        } else if hasEntitlementProvider {
            effectiveCapabilities = []
        } else {
            effectiveCapabilities = declaredCapabilities
        }
        let capabilities = Array(effectiveCapabilities)
            .sorted { $0.rawValue < $1.rawValue }
        let contributions = enterpriseModules
            .flatMap(\.uiContributions)
            .filter { contribution in
                guard let requiredFeature = contribution.requiredFeature else {
                    return true
                }
                return capabilities.contains(requiredFeature)
            }
            .sorted { $0.id < $1.id }

        return EnterpriseRuntimeStatus(
            edition: .enterprise,
            modules: descriptors,
            capabilities: capabilities,
            uiContributions: contributions,
            entitlement: entitlementSummary
        )
    }

    /// Private OIDC modules can validate bearer tokens while the built-in
    /// local admin flow remains available as a break-glass path.
    public func authenticateEnterpriseIdentity(
        bearerToken: String
    ) async -> EnterpriseIdentity? {
        for module in enterpriseModules {
            guard let provider = module.identityProvider else {
                continue
            }
            if let identity = try? await provider.authenticate(bearerToken: bearerToken) {
                return identity
            }
        }
        return nil
    }

    /// Applies every installed policy provider. Missing providers preserve
    /// Community behavior; a provider failure or denial fails closed.
    public func evaluateEnterpriseAuthorization(
        _ request: AuthorizationRequest
    ) async -> AuthorizationDecision {
        var evaluatedPolicy = false
        for module in enterpriseModules {
            guard let provider = module.authorizationPolicyProvider else {
                continue
            }
            evaluatedPolicy = true
            do {
                let decision = try await provider.evaluate(request)
                if !decision.allowed {
                    return decision
                }
            } catch {
                return .deny(reason: "authorization_policy_unavailable")
            }
        }
        return .allow(policyID: evaluatedPolicy ? "enterprise" : nil)
    }

    /// Fans an already-redacted event out to all configured append-only sinks.
    /// A sink failure does not stop other sinks from receiving the event.
    public func recordEnterpriseAudit(_ event: AuditEvent) async {
        for module in enterpriseModules {
            guard let sink = module.auditSink else {
                continue
            }
            try? await sink.record(event)
        }
    }

    /// Seat limits apply only when activating another human user; an existing
    /// running system is never disabled by this helper.
    public func canActivateEnterpriseUser(activeHumanUsers: Int) async -> Bool {
        var userLimits: [Int] = []
        for module in enterpriseModules {
            guard let provider = module.entitlementProvider else {
                continue
            }
            do {
                let entitlement = try await provider.currentEntitlement()
                userLimits.append(entitlement.activeHumanUserLimit)
            } catch {
                return false
            }
        }
        guard let effectiveLimit = userLimits.min() else {
            return true
        }
        return activeHumanUsers < effectiveLimit
    }

    /// Allows private OIDC modules to expose only their authorization and
    /// callback endpoints before a Sloppy session exists.
    public func isEnterprisePublicIdentityRoute(method: String, path: String) -> Bool {
        let normalizedMethod = method.uppercased()
        guard normalizedMethod == "GET" || normalizedMethod == "POST" else {
            return false
        }
        return enterpriseModules.contains { module in
            guard let descriptor = module.identityProvider?.descriptor else {
                return false
            }
            return path == descriptor.authorizationPath || path == descriptor.callbackPath
        }
    }
}
