import Foundation
import Protocols

struct ActorsAPIRouter: APIRouter {
    private let service: CoreService

    init(service: CoreService) {
        self.service = service
    }

    func configure(on router: CoreRouterRegistrar) {
        router.get("/v1/actors/board", metadata: RouteMetadata(summary: "Get actor board", description: "Returns the current state of the actor board", tags: ["Actors"])) { _ in
            do {
                let board = try await service.getActorBoard()
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: board)
            } catch let error as CoreService.ActorBoardError {
                return CoreRouter.actorBoardErrorResponse(error, fallback: ErrorCode.actorBoardReadFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.actorBoardReadFailed])
            }
        }

        router.put("/v1/actors/board", metadata: RouteMetadata(summary: "Update actor board", description: "Updates the current state of the actor board", tags: ["Actors"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: ActorBoardUpdateRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidActorPayload])
            }

            do {
                let board = try await service.updateActorBoard(request: payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: board)
            } catch let error as CoreService.ActorBoardError {
                return CoreRouter.actorBoardErrorResponse(error, fallback: ErrorCode.actorBoardWriteFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.actorBoardWriteFailed])
            }
        }

        router.put("/v1/actors/nodes/:actorId", metadata: RouteMetadata(summary: "Update actor node", description: "Updates a specific actor node", tags: ["Actors"])) { request in
            let actorId = request.pathParam("actorId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: ActorNode.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidActorPayload])
            }

            do {
                let board = try await service.updateActorNode(actorID: actorId, node: payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: board)
            } catch let error as CoreService.ActorBoardError {
                return CoreRouter.actorBoardErrorResponse(error, fallback: ErrorCode.actorBoardWriteFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.actorBoardWriteFailed])
            }
        }

        router.put("/v1/actors/links/:linkId", metadata: RouteMetadata(summary: "Update actor link", description: "Updates a specific actor link", tags: ["Actors"])) { request in
            let linkId = request.pathParam("linkId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: ActorLink.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidActorPayload])
            }

            do {
                let board = try await service.updateActorLink(linkID: linkId, link: payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: board)
            } catch let error as CoreService.ActorBoardError {
                return CoreRouter.actorBoardErrorResponse(error, fallback: ErrorCode.actorBoardWriteFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.actorBoardWriteFailed])
            }
        }

        router.put("/v1/actors/teams/:teamId", metadata: RouteMetadata(summary: "Update actor team", description: "Updates a specific actor team", tags: ["Actors"])) { request in
            let teamId = request.pathParam("teamId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: ActorTeam.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidActorPayload])
            }

            do {
                let board = try await service.updateActorTeam(teamID: teamId, team: payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: board)
            } catch let error as CoreService.ActorBoardError {
                return CoreRouter.actorBoardErrorResponse(error, fallback: ErrorCode.actorBoardWriteFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.actorBoardWriteFailed])
            }
        }

        router.post("/v1/actors/nodes", metadata: RouteMetadata(summary: "Create actor node", description: "Creates a new node in the actor board", tags: ["Actors"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: ActorNode.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidActorPayload])
            }

            do {
                let board = try await service.createActorNode(node: payload)
                return CoreRouter.encodable(status: HTTPStatus.created, payload: board)
            } catch let error as CoreService.ActorBoardError {
                return CoreRouter.actorBoardErrorResponse(error, fallback: ErrorCode.actorBoardWriteFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.actorBoardWriteFailed])
            }
        }

        router.post("/v1/actors/links", metadata: RouteMetadata(summary: "Create actor link", description: "Creates a new link between actor nodes", tags: ["Actors"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: ActorLink.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidActorPayload])
            }

            do {
                let board = try await service.createActorLink(link: payload)
                return CoreRouter.encodable(status: HTTPStatus.created, payload: board)
            } catch let error as CoreService.ActorBoardError {
                return CoreRouter.actorBoardErrorResponse(error, fallback: ErrorCode.actorBoardWriteFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.actorBoardWriteFailed])
            }
        }

        router.post("/v1/actors/teams", metadata: RouteMetadata(summary: "Create actor team", description: "Creates a new team of actors", tags: ["Actors"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: ActorTeam.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidActorPayload])
            }

            do {
                let board = try await service.createActorTeam(team: payload)
                return CoreRouter.encodable(status: HTTPStatus.created, payload: board)
            } catch let error as CoreService.ActorBoardError {
                return CoreRouter.actorBoardErrorResponse(error, fallback: ErrorCode.actorBoardWriteFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.actorBoardWriteFailed])
            }
        }

        router.post("/v1/actors/route", metadata: RouteMetadata(summary: "Route actor request", description: "Resolves the routing for an actor request", tags: ["Actors"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: ActorRouteRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidActorPayload])
            }

            do {
                let response = try await service.resolveActorRoute(request: payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch let error as CoreService.ActorBoardError {
                return CoreRouter.actorBoardErrorResponse(error, fallback: ErrorCode.actorRouteFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.actorRouteFailed])
            }
        }

        router.delete("/v1/actors/nodes/:actorId", metadata: RouteMetadata(summary: "Delete actor node", description: "Deletes a specific actor node", tags: ["Actors"])) { request in
            let actorId = request.pathParam("actorId") ?? ""

            do {
                let board = try await service.deleteActorNode(actorID: actorId)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: board)
            } catch let error as CoreService.ActorBoardError {
                return CoreRouter.actorBoardErrorResponse(error, fallback: ErrorCode.actorBoardWriteFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.actorBoardWriteFailed])
            }
        }

        router.delete("/v1/actors/links/:linkId", metadata: RouteMetadata(summary: "Delete actor link", description: "Deletes a specific actor link", tags: ["Actors"])) { request in
            let linkId = request.pathParam("linkId") ?? ""

            do {
                let board = try await service.deleteActorLink(linkID: linkId)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: board)
            } catch let error as CoreService.ActorBoardError {
                return CoreRouter.actorBoardErrorResponse(error, fallback: ErrorCode.actorBoardWriteFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.actorBoardWriteFailed])
            }
        }

        router.delete("/v1/actors/teams/:teamId", metadata: RouteMetadata(summary: "Delete actor team", description: "Deletes a specific actor team", tags: ["Actors"])) { request in
            let teamId = request.pathParam("teamId") ?? ""

            do {
                let board = try await service.deleteActorTeam(teamID: teamId)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: board)
            } catch let error as CoreService.ActorBoardError {
                return CoreRouter.actorBoardErrorResponse(error, fallback: ErrorCode.actorBoardWriteFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.actorBoardWriteFailed])
            }
        }
    }
}
