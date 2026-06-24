import Foundation
import Protocols

struct ArtifactsAPIRouter: APIRouter {
    private let service: CoreService

    init(service: CoreService) {
        self.service = service
    }

    func configure(on router: CoreRouterRegistrar) {
        router.get("/v1/artifacts", metadata: RouteMetadata(summary: "List artifacts", description: "Returns local artifact metadata", tags: ["Artifacts"])) { _ in
            let response = await service.listArtifacts()
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
        }

        router.get("/v1/artifacts/:artifactId", metadata: RouteMetadata(summary: "Get artifact", description: "Returns metadata for a specific artifact", tags: ["Artifacts"])) { request in
            let artifactId = request.pathParam("artifactId") ?? ""
            guard let response = await service.getArtifact(id: artifactId) else {
                return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": ErrorCode.artifactNotFound])
            }
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
        }

        router.get("/v1/artifacts/:artifactId/content", metadata: RouteMetadata(summary: "Get artifact content", description: "Returns the content of a specific artifact", tags: ["Artifacts"])) { request in
            let artifactId = request.pathParam("artifactId") ?? ""
            guard let response = await service.getArtifactContent(id: artifactId) else {
                return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": ErrorCode.artifactNotFound])
            }
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
        }
    }
}
