import Foundation
import Testing
import PluginSDK
import Protocols

@Test
func entitlementUsesPerpetualReleaseFallback() {
    let cutoff = Date(timeIntervalSince1970: 2_000)
    let entitlement = EntitlementSnapshot(
        licenseID: "license-1",
        customer: "Example Corp",
        customerID: "example",
        features: [.oidc, .auditExport],
        activeHumanUserLimit: 50,
        issuedAt: Date(timeIntervalSince1970: 1_000),
        updatesUntil: cutoff
    )

    #expect(entitlement.allows(.oidc))
    #expect(!entitlement.allows(.authorizationPolicies))
    #expect(entitlement.allowsRelease(publishedAt: cutoff))
    #expect(entitlement.allowsRelease(publishedAt: Date(timeIntervalSince1970: 1_999)))
    #expect(!entitlement.allowsRelease(publishedAt: Date(timeIntervalSince1970: 2_001)))
}

@Test
func signedEntitlementEnvelopeRoundTripsWithoutImplicitVerification() throws {
    let envelope = SignedEntitlementEnvelope(
        keyID: "ed25519-2026-01",
        payload: "cGF5bG9hZA==",
        signature: "c2lnbmF0dXJl"
    )

    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(SignedEntitlementEnvelope.self, from: data)

    #expect(decoded == envelope)
}

@Test
func enterpriseRolesAreStableWireValues() {
    #expect(AuthUserRole.operator.rawValue == "operator")
    #expect(AuthUserRole.approver.rawValue == "approver")
    #expect(AuthUserRole.auditor.rawValue == "auditor")
    #expect(AuthUserRole.viewer.rawValue == "viewer")
    #expect(AuthUserRole.admin.isCommunityRole)
    #expect(AuthUserRole.user.isCommunityRole)
    #expect(!AuthUserRole.operator.isCommunityRole)
}
