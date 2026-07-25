import Foundation
import Testing
import PluginSDK
import Protocols
@testable import sloppy

private struct TestEntitlementProvider: EntitlementProvider {
    let entitlement: EntitlementSnapshot

    func currentEntitlement() async throws -> EntitlementSnapshot {
        entitlement
    }
}

private struct TestEnterpriseModule: EnterpriseModule {
    let descriptor = EnterpriseModuleDescriptor(
        id: "test-enterprise",
        title: "Test Enterprise",
        version: "2.0.0",
        capabilities: [.oidc, .authorizationPolicies, .auditExport]
    )
    let entitlementProvider: (any EntitlementProvider)?
    let uiContributions = [
        EnterpriseUIContribution(
            id: "audit",
            title: "Audit",
            path: "/enterprise/audit",
            requiredFeature: .auditExport
        ),
        EnterpriseUIContribution(
            id: "policies",
            title: "Policies",
            path: "/enterprise/policies",
            requiredFeature: .authorizationPolicies
        ),
    ]

    init(entitlement: EntitlementSnapshot) {
        self.entitlementProvider = TestEntitlementProvider(entitlement: entitlement)
    }
}

private enum TestEnterpriseError: Error {
    case unavailable
}

private struct ThrowingEntitlementProvider: EntitlementProvider {
    func currentEntitlement() async throws -> EntitlementSnapshot {
        throw TestEnterpriseError.unavailable
    }
}

private struct DenyingPolicyProvider: AuthorizationPolicyProvider {
    func evaluate(_ request: AuthorizationRequest) async throws -> AuthorizationDecision {
        .deny(reason: "test_denied", policyID: "test-policy")
    }
}

private struct FailingPolicyProvider: AuthorizationPolicyProvider {
    func evaluate(_ request: AuthorizationRequest) async throws -> AuthorizationDecision {
        throw TestEnterpriseError.unavailable
    }
}

private struct TestProviderModule: EnterpriseModule {
    let descriptor = EnterpriseModuleDescriptor(
        id: "test-provider",
        title: "Test Provider",
        version: "2.0.0",
        capabilities: [.authorizationPolicies, .offlineEntitlement]
    )
    let entitlementProvider: (any EntitlementProvider)?
    let authorizationPolicyProvider: (any AuthorizationPolicyProvider)?

    init(
        entitlementProvider: (any EntitlementProvider)? = nil,
        authorizationPolicyProvider: (any AuthorizationPolicyProvider)? = nil
    ) {
        self.entitlementProvider = entitlementProvider
        self.authorizationPolicyProvider = authorizationPolicyProvider
    }
}

private func testEnterpriseEntitlement(userLimit: Int = 10) -> EntitlementSnapshot {
    EntitlementSnapshot(
        licenseID: "test-license",
        customer: "Design Partner",
        customerID: "design-partner",
        features: [.oidc, .auditExport],
        activeHumanUserLimit: userLimit,
        issuedAt: Date(timeIntervalSince1970: 1_000),
        updatesUntil: Date(timeIntervalSince1970: 2_000)
    )
}

@Test
func communityRunsWithoutEnterpriseModuleOrEntitlement() async {
    let service = CoreService(
        config: .test,
        persistenceBuilder: InMemoryCorePersistenceBuilder()
    )

    let status = await service.enterpriseRuntimeStatus()

    #expect(status.edition == .community)
    #expect(status.modules.isEmpty)
    #expect(status.capabilities.isEmpty)
    #expect(status.entitlement == nil)
    #expect(await service.canActivateEnterpriseUser(activeHumanUsers: 1_000_000))
}

@Test
func enterpriseModulePublishesOnlyEntitledContributionsAndEnforcesNewUserLimit() async {
    let module = TestEnterpriseModule(entitlement: testEnterpriseEntitlement(userLimit: 10))
    let service = CoreService(
        config: .test,
        persistenceBuilder: InMemoryCorePersistenceBuilder(),
        enterpriseModules: [module]
    )

    let status = await service.enterpriseRuntimeStatus()

    #expect(status.edition == .enterprise)
    #expect(status.modules.map(\.id) == ["test-enterprise"])
    #expect(status.capabilities == [.auditExport, .oidc])
    #expect(status.uiContributions.map(\.id) == ["audit"])
    #expect(status.entitlement?.customer == "Design Partner")
    #expect(await service.canActivateEnterpriseUser(activeHumanUsers: 9))
    #expect(!(await service.canActivateEnterpriseUser(activeHumanUsers: 10)))
}

@Test
func systemEditionEndpointReportsCommunityWithoutPhoneHome() async throws {
    let service = CoreService(
        config: .test,
        persistenceBuilder: InMemoryCorePersistenceBuilder()
    )
    let router = CoreRouter(service: service)

    let response = await router.handle(method: "GET", path: "/v1/system/edition", body: nil)
    let status = try JSONDecoder().decode(EnterpriseRuntimeStatus.self, from: response.body)

    #expect(response.status == 200)
    #expect(status.edition == .community)
}

@Test
func policyDenialAndProviderFailureBothFailClosed() async {
    let subject = AuthorizationSubject(userID: "operator-1", role: .operator)
    let request = AuthorizationRequest(
        subject: subject,
        action: "tool.execute",
        resource: AuthorizationResource(kind: "tool", id: "shell")
    )
    let deniedService = CoreService(
        config: .test,
        persistenceBuilder: InMemoryCorePersistenceBuilder(),
        enterpriseModules: [
            TestProviderModule(authorizationPolicyProvider: DenyingPolicyProvider()),
        ]
    )
    let unavailableService = CoreService(
        config: .test,
        persistenceBuilder: InMemoryCorePersistenceBuilder(),
        enterpriseModules: [
            TestProviderModule(authorizationPolicyProvider: FailingPolicyProvider()),
        ]
    )

    let denied = await deniedService.evaluateEnterpriseAuthorization(request)
    let unavailable = await unavailableService.evaluateEnterpriseAuthorization(request)

    #expect(!denied.allowed)
    #expect(denied.reason == "test_denied")
    #expect(!unavailable.allowed)
    #expect(unavailable.reason == "authorization_policy_unavailable")
}

@Test
func invalidEntitlementBlocksOnlyNewEnterpriseUserActivation() async {
    let service = CoreService(
        config: .test,
        persistenceBuilder: InMemoryCorePersistenceBuilder(),
        enterpriseModules: [
            TestProviderModule(entitlementProvider: ThrowingEntitlementProvider()),
        ]
    )

    #expect(!(await service.canActivateEnterpriseUser(activeHumanUsers: 0)))
    #expect((await service.enterpriseRuntimeStatus()).edition == .enterprise)
}

@Test
func communityIdentityStoreRejectsEnterpriseOnlyRoles() async throws {
    let auth = CoreIdentityAuthService(passwordHashIterations: 1)
    await auth.setEnabled(true)
    let session = try await auth.bootstrapAdmin(
        AuthBootstrapAdminRequest(
            login: "admin",
            password: "admin-password",
            name: "Admin"
        )
    )
    let actor = try #require(await auth.authenticateAccessToken(session.accessToken))

    do {
        _ = try await auth.createInvite(
            AuthInviteCreateRequest(role: .operator, ttlSeconds: 600),
            actor: actor
        )
        Issue.record("Community local auth accepted an Enterprise-only role")
    } catch CoreIdentityAuthError.invalidRole {
        // Expected: only admin/user are valid in Community local auth.
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
