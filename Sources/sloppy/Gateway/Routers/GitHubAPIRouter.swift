import Foundation
import Protocols

struct GitHubAPIRouter: APIRouter {
    private let service: CoreService

    init(service: CoreService) {
        self.service = service
    }

    func configure(on router: CoreRouterRegistrar) {
        router.get(
            "/v1/providers/github/status",
            metadata: RouteMetadata(
                summary: "GitHub auth status",
                description: "Returns the current GitHub authentication status",
                tags: ["Providers"]
            )
        ) { _ in
            let status = await service.gitHubAuthStatus()
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: status)
        }

        router.post(
            "/v1/providers/github/connect",
            metadata: RouteMetadata(
                summary: "Connect GitHub",
                description: "Saves and validates a GitHub Personal Access Token",
                tags: ["Providers"]
            )
        ) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: GitHubConnectRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let response = try await service.connectGitHub(request: payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch {
                return CoreRouter.encodable(
                    status: HTTPStatus.ok,
                    payload: GitHubConnectResponse(ok: false, message: error.localizedDescription)
                )
            }
        }

        router.post(
            "/v1/providers/github/disconnect",
            metadata: RouteMetadata(
                summary: "Disconnect GitHub",
                description: "Removes stored GitHub Personal Access Token",
                tags: ["Providers"]
            )
        ) { _ in
            do {
                try await service.disconnectGitHub()
                return CoreRouter.json(status: HTTPStatus.ok, payload: ["ok": "true"])
            } catch {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": error.localizedDescription])
            }
        }
    }
}
