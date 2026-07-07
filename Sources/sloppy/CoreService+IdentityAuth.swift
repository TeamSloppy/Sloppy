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

    func registerIdentityUser(_ request: AuthRegisterRequest) async throws -> AuthSessionResponse {
        try await identityAuthService.register(request)
    }

    func createIdentityInvite(_ request: AuthInviteCreateRequest, actor: AuthenticatedUserContext) async throws -> AuthInviteRecord {
        try await identityAuthService.createInvite(request, actor: actor)
    }

    func authenticateIdentityAccessToken(_ token: String?) async -> AuthenticatedUserContext? {
        await identityAuthService.authenticateAccessToken(token)
    }
}
