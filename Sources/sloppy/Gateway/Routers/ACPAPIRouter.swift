import Foundation
import Protocols

struct ACPAPIRouter: APIRouter {
    private let service: CoreService

    init(service: CoreService) {
        self.service = service
    }

    func configure(on router: CoreRouterRegistrar) {
        router.post("/v1/acp/targets/probe", metadata: RouteMetadata(summary: "Probe ACP target", description: "Launches and initializes an ACP target to validate connectivity and capabilities", tags: ["ACP"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: ACPTargetProbeRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let response = try await service.probeACPTarget(request: payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch {
                return CoreRouter.encodable(
                    status: HTTPStatus.ok,
                    payload: ACPTargetProbeResponse(
                        ok: false,
                        targetId: payload.target.id,
                        targetTitle: payload.target.title,
                        message: error.localizedDescription
                    )
                )
            }
        }
    }
}
