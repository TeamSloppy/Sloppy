import Foundation
import Protocols

private struct ArtifactDeleteResponse: Encodable {
    var deleted: Bool
}

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

        router.get("/v1/artifacts/boards/:boardId", metadata: RouteMetadata(summary: "Get board artifact", description: "Returns a reusable canvas board artifact", tags: ["Artifacts"])) { request in
            let boardId = request.pathParam("boardId") ?? ""
            do {
                guard let response = try await service.getBoardArtifact(id: boardId) else {
                    return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": ErrorCode.artifactNotFound])
                }
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch BoardArtifactService.BoardError.invalidBoardId {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.artifactReadFailed])
            }
        }

        router.put("/v1/artifacts/boards/:boardId", metadata: RouteMetadata(summary: "Save board artifact", description: "Creates or updates a reusable canvas board artifact", tags: ["Artifacts"])) { request in
            let boardId = request.pathParam("boardId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: BoardArtifactRecord.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let response = try await service.saveBoardArtifact(id: boardId, board: payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch BoardArtifactService.BoardError.invalidBoardId,
                    BoardArtifactService.BoardError.invalidBoard {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.artifactCreateFailed])
            }
        }

        router.post("/v1/artifacts/boards/:boardId/assets", metadata: RouteMetadata(summary: "Upload board asset", description: "Stores an image asset under a canvas board artifact", tags: ["Artifacts"])) { request in
            let boardId = request.pathParam("boardId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: BoardAssetUploadRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let response = try await service.uploadBoardAsset(boardId: boardId, request: payload)
                return CoreRouter.encodable(status: HTTPStatus.created, payload: response)
            } catch BoardArtifactService.BoardError.invalidBoardId,
                    BoardArtifactService.BoardError.invalidAsset {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.artifactCreateFailed])
            }
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

        router.delete("/v1/artifacts/:artifactId", metadata: RouteMetadata(summary: "Delete artifact", description: "Removes a persisted local artifact", tags: ["Artifacts"])) { request in
            let artifactId = request.pathParam("artifactId") ?? ""
            guard await service.deleteArtifact(id: artifactId) else {
                return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": ErrorCode.artifactNotFound])
            }
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: ArtifactDeleteResponse(deleted: true))
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
