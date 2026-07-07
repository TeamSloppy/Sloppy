import Foundation
import Protocols

struct AuthAPIRouter: APIRouter {
    private let service: CoreService

    init(service: CoreService) {
        self.service = service
    }

    func configure(on router: CoreRouterRegistrar) {
        router.get("/v1/auth/challenge", metadata: RouteMetadata(summary: "Get auth challenge", description: "Returns the authentication challenge expected by this Core instance", tags: ["Auth"])) { _ in
            CoreRouter.encodable(status: HTTPStatus.ok, payload: await service.identityAuthChallenge())
        }

        router.post("/v1/auth/bootstrap", metadata: RouteMetadata(summary: "Bootstrap first admin", description: "Creates the first Admin account for login/password auth", tags: ["Auth"])) { request in
            guard let payload = request.decode(AuthBootstrapAdminRequest.self) else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                return CoreRouter.encodable(status: HTTPStatus.created, payload: try await service.bootstrapIdentityAdmin(payload))
            } catch {
                return authErrorResponse(error)
            }
        }

        router.post("/v1/auth/login", metadata: RouteMetadata(summary: "Login", description: "Creates an auth session from login and password", tags: ["Auth"])) { request in
            guard let payload = request.decode(AuthLoginRequest.self) else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.loginIdentityUser(payload))
            } catch {
                return authErrorResponse(error)
            }
        }

        router.post("/v1/auth/refresh", metadata: RouteMetadata(summary: "Refresh auth session", description: "Rotates a refresh token and returns a new auth session", tags: ["Auth"])) { request in
            guard let payload = request.decode(AuthRefreshRequest.self) else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.refreshIdentitySession(payload))
            } catch {
                return authErrorResponse(error)
            }
        }

        router.post("/v1/auth/register", metadata: RouteMetadata(summary: "Register invited user", description: "Consumes an invite and creates a user account", tags: ["Auth"])) { request in
            guard let payload = request.decode(AuthRegisterRequest.self) else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                return CoreRouter.encodable(status: HTTPStatus.created, payload: try await service.registerIdentityUser(payload))
            } catch {
                return authErrorResponse(error)
            }
        }

        router.post("/v1/auth/invites", metadata: RouteMetadata(summary: "Create auth invite", description: "Creates an invite token for another user", tags: ["Auth"])) { request in
            guard let actor = await CoreRouter.identityActor(for: request, service: service) else {
                return CoreRouter.json(status: HTTPStatus.unauthorized, payload: ["error": ErrorCode.unauthorized])
            }
            guard actor.user.role == .admin else {
                return CoreRouter.json(status: HTTPStatus.forbidden, payload: ["error": "forbidden"])
            }
            guard let payload = request.decode(AuthInviteCreateRequest.self) else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                return CoreRouter.encodable(status: HTTPStatus.created, payload: try await service.createIdentityInvite(payload, actor: actor))
            } catch {
                return authErrorResponse(error)
            }
        }

        router.post("/v1/auth/recovery-codes", metadata: RouteMetadata(summary: "Generate recovery codes", description: "Generates one-time recovery codes for the authenticated user", tags: ["Auth"])) { request in
            guard let actor = await CoreRouter.identityActor(for: request, service: service) else {
                return CoreRouter.json(status: HTTPStatus.unauthorized, payload: ["error": ErrorCode.unauthorized])
            }
            do {
                return CoreRouter.encodable(status: HTTPStatus.created, payload: try await service.generateIdentityRecoveryCodes(actor: actor))
            } catch {
                return authErrorResponse(error)
            }
        }

        router.post("/v1/auth/users/:login/password-reset-token", metadata: RouteMetadata(summary: "Create password reset token", description: "Creates a short-lived admin password reset token for a user", tags: ["Auth"])) { request in
            guard let actor = await CoreRouter.identityActor(for: request, service: service) else {
                return CoreRouter.json(status: HTTPStatus.unauthorized, payload: ["error": ErrorCode.unauthorized])
            }
            guard actor.user.role == .admin else {
                return CoreRouter.json(status: HTTPStatus.forbidden, payload: ["error": "forbidden"])
            }
            do {
                return CoreRouter.encodable(
                    status: HTTPStatus.created,
                    payload: try await service.createIdentityPasswordResetToken(
                        login: request.pathParam("login") ?? "",
                        actor: actor
                    )
                )
            } catch {
                return authErrorResponse(error)
            }
        }

        router.post("/v1/auth/password-reset", metadata: RouteMetadata(summary: "Reset password", description: "Resets a password with a recovery code or admin reset token", tags: ["Auth"])) { request in
            guard let payload = request.decode(AuthPasswordResetRequest.self) else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.resetIdentityPassword(payload))
            } catch {
                return authErrorResponse(error)
            }
        }
    }
}

private func authErrorResponse(_ error: Error) -> CoreRouterResponse {
    switch error {
    case CoreIdentityAuthError.forbidden:
        return CoreRouter.json(status: HTTPStatus.forbidden, payload: ["error": "forbidden"])
    case CoreIdentityAuthError.bootstrapAlreadyCompleted:
        return CoreRouter.json(status: HTTPStatus.conflict, payload: ["error": "bootstrap_completed"])
    case CoreIdentityAuthError.bootstrapRequired:
        return CoreRouter.json(status: HTTPStatus.conflict, payload: ["error": "bootstrap_required"])
    case CoreIdentityAuthError.disabled:
        return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": "auth_disabled"])
    case CoreIdentityAuthError.invalidCredentials,
         CoreIdentityAuthError.invalidInvite,
         CoreIdentityAuthError.inviteExpired,
         CoreIdentityAuthError.inviteConsumed,
         CoreIdentityAuthError.invalidRecoverySecret:
        return CoreRouter.json(status: HTTPStatus.unauthorized, payload: ["error": ErrorCode.unauthorized])
    default:
        return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": "auth_failed"])
    }
}
