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

        router.post("/v1/artifacts/widgets/generate", metadata: RouteMetadata(summary: "Generate widget artifact", description: "Creates a bounded widget artifact from a user description", tags: ["Artifacts"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: WidgetArtifactGenerateRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let response = try await service.generateWidgetArtifact(payload)
                return CoreRouter.encodable(status: HTTPStatus.created, payload: response)
            } catch WidgetArtifactService.WidgetError.invalidSize,
                    WidgetArtifactService.WidgetError.invalidPrompt,
                    WidgetArtifactService.WidgetError.invalidHTML {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.artifactCreateFailed])
            }
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

        router.get("/v1/artifacts/:artifactId/widget", metadata: RouteMetadata(summary: "Get widget artifact", description: "Returns renderable widget HTML and fixed dimensions", tags: ["Artifacts"])) { request in
            let artifactId = request.pathParam("artifactId") ?? ""
            guard let response = await service.getWidgetArtifact(id: artifactId) else {
                return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": ErrorCode.artifactNotFound])
            }
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
        }
    }
}
