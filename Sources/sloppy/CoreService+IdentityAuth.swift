import Foundation
import Protocols

extension CoreService {
    func setIdentityAuthEnabled(_ enabled: Bool) async {
        await identityAuthService.setEnabled(enabled)
    }

    func identityAuthEnabled() async -> Bool {
        await identityAuthService.isEnabled()
    }

    func identityAuthChallenge() async -> AuthChallengeResponse {
        await identityAuthService.challenge()
    }

    func bootstrapIdentityAdmin(_ request: AuthBootstrapAdminRequest) async throws -> AuthSessionResponse {
        try await identityAuthService.bootstrapAdmin(request)
    }

    func loginIdentityUser(_ request: AuthLoginRequest) async throws -> AuthSessionResponse {
        try await identityAuthService.login(request)
    }

    func refreshIdentitySession(_ request: AuthRefreshRequest) async throws -> AuthSessionResponse {
        try await identityAuthService.refresh(request)
    }

    func createIdentityDevicePairing(
        _ request: AuthDevicePairingCreateRequest,
        actor: AuthenticatedUserContext
    ) async throws -> AuthDevicePairingRecord {
        try await identityAuthService.createDevicePairing(request, actor: actor)
    }

    func redeemIdentityDevicePairing(_ request: AuthDevicePairingRedeemRequest) async throws -> AuthSessionResponse {
        try await identityAuthService.redeemDevicePairing(request)
    }

    func registerIdentityUser(_ request: AuthRegisterRequest) async throws -> AuthSessionResponse {
        try await identityAuthService.register(request)
    }

    func createIdentityInvite(_ request: AuthInviteCreateRequest, actor: AuthenticatedUserContext) async throws -> AuthInviteRecord {
        try await identityAuthService.createInvite(request, actor: actor)
    }

    func listIdentityUsers(actor: AuthenticatedUserContext) async throws -> [AuthUserProfile] {
        try await identityAuthService.listUsers(actor: actor)
    }

    func updateIdentityUser(login: String, request: AuthUserUpdateRequest, actor: AuthenticatedUserContext) async throws -> AuthUserProfile {
        try await identityAuthService.updateUser(login: login, request: request, actor: actor)
    }

    func updateCurrentIdentityUser(
        request: AuthUserUpdateRequest,
        actor: AuthenticatedUserContext
    ) async throws -> AuthUserProfile {
        try await identityAuthService.updateCurrentUser(request: request, actor: actor)
    }

    func generateIdentityRecoveryCodes(actor: AuthenticatedUserContext) async throws -> AuthRecoveryCodesResponse {
        try await identityAuthService.generateRecoveryCodes(actor: actor)
    }

    func changeIdentityPassword(_ request: AuthPasswordChangeRequest, actor: AuthenticatedUserContext) async throws -> AuthSessionResponse {
        try await identityAuthService.changePassword(request, actor: actor)
    }

    func createIdentityPasswordResetToken(login: String, actor: AuthenticatedUserContext) async throws -> AuthAdminPasswordResetResponse {
        try await identityAuthService.createPasswordResetToken(login: login, actor: actor)
    }

    func resetIdentityPassword(_ request: AuthPasswordResetRequest) async throws -> AuthSessionResponse {
        try await identityAuthService.resetPassword(request)
    }

    func createIdentityApplicationToken(
        _ request: AuthApplicationTokenCreateRequest,
        actor: AuthenticatedUserContext
    ) async throws -> AuthApplicationTokenRecord {
        try await identityAuthService.createApplicationToken(request, actor: actor)
    }

    func listIdentityApplicationTokens(actor: AuthenticatedUserContext) async throws -> [AuthApplicationTokenRecord] {
        try await identityAuthService.listApplicationTokens(actor: actor)
    }

    func revokeIdentityApplicationToken(id: String, actor: AuthenticatedUserContext) async throws {
        try await identityAuthService.revokeApplicationToken(id: id, actor: actor)
    }

    func authenticateIdentityAccessToken(_ token: String?) async -> AuthenticatedUserContext? {
        if let localIdentity = await identityAuthService.authenticateAccessToken(token) {
            return localIdentity
        }
        guard let token,
              let enterpriseIdentity = await authenticateEnterpriseIdentity(bearerToken: token)
        else {
            return nil
        }
        return AuthenticatedUserContext(
            user: enterpriseIdentity.profile,
            groups: enterpriseIdentity.groups,
            identityProviderID: enterpriseIdentity.providerID
        )
    }
}
