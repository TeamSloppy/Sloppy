import Foundation
import Protocols

struct InitiativesAPIRouter: APIRouter {
    private let service: CoreService

    init(service: CoreService) {
        self.service = service
    }

    func configure(on router: CoreRouterRegistrar) {
        router.get("/v1/projects/:projectId/initiatives", metadata: RouteMetadata(summary: "List initiatives", description: "Returns durable initiative records for a project", tags: ["Projects"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            do {
                let response = try await service.listInitiatives(projectID: projectId)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch let error as CoreService.ProjectError {
                return CoreRouter.projectErrorResponse(error, fallback: ErrorCode.projectReadFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.projectReadFailed])
            }
        }

        router.post("/v1/projects/:projectId/initiatives", metadata: RouteMetadata(summary: "Create initiative", description: "Creates a durable initiative record for a project", tags: ["Projects"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: CreateInitiativeRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                let response = try await service.createInitiative(projectID: projectId, request: payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch let error as CoreService.ProjectError {
                return CoreRouter.projectErrorResponse(error, fallback: ErrorCode.projectUpdateFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.projectUpdateFailed])
            }
        }

        router.get("/v1/projects/:projectId/initiatives/:initiativeId", metadata: RouteMetadata(summary: "Get initiative", description: "Returns one durable initiative record", tags: ["Projects"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            let initiativeId = request.pathParam("initiativeId") ?? ""
            do {
                let response = try await service.getInitiative(projectID: projectId, initiativeID: initiativeId)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch let error as CoreService.ProjectError {
                return CoreRouter.projectErrorResponse(error, fallback: ErrorCode.projectReadFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.projectReadFailed])
            }
        }

        router.patch("/v1/projects/:projectId/initiatives/:initiativeId", metadata: RouteMetadata(summary: "Update initiative", description: "Updates mutable initiative state such as phase or resume point", tags: ["Projects"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            let initiativeId = request.pathParam("initiativeId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: UpdateInitiativeRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                let response = try await service.updateInitiative(projectID: projectId, initiativeID: initiativeId, request: payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch let error as CoreService.ProjectError {
                return CoreRouter.projectErrorResponse(error, fallback: ErrorCode.projectUpdateFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.projectUpdateFailed])
            }
        }

        router.get("/v1/projects/:projectId/initiatives/:initiativeId/decision-packets", metadata: RouteMetadata(summary: "List initiative decision packets", description: "Returns human-decision packets attached to one initiative", tags: ["Projects"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            let initiativeId = request.pathParam("initiativeId") ?? ""
            do {
                let response = try await service.listInitiativeDecisionPackets(projectID: projectId, initiativeID: initiativeId)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch let error as CoreService.ProjectError {
                return CoreRouter.projectErrorResponse(error, fallback: ErrorCode.projectReadFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.projectReadFailed])
            }
        }

        router.post("/v1/projects/:projectId/initiatives/:initiativeId/decision-packets", metadata: RouteMetadata(summary: "Create initiative decision packet", description: "Creates a human-decision packet for an initiative", tags: ["Projects"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            let initiativeId = request.pathParam("initiativeId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: CreateDecisionPacketRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                let response = try await service.createInitiativeDecisionPacket(
                    projectID: projectId,
                    initiativeID: initiativeId,
                    request: payload
                )
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch let error as CoreService.ProjectError {
                return CoreRouter.projectErrorResponse(error, fallback: ErrorCode.projectUpdateFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.projectUpdateFailed])
            }
        }

        router.patch("/v1/projects/:projectId/initiatives/:initiativeId/decision-packets/:packetId", metadata: RouteMetadata(summary: "Update initiative decision packet", description: "Updates the status of an initiative decision packet and may resume the initiative", tags: ["Projects"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            let initiativeId = request.pathParam("initiativeId") ?? ""
            let packetId = request.pathParam("packetId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: UpdateDecisionPacketRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                let response = try await service.updateInitiativeDecisionPacket(
                    projectID: projectId,
                    initiativeID: initiativeId,
                    packetID: packetId,
                    request: payload
                )
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch let error as CoreService.ProjectError {
                return CoreRouter.projectErrorResponse(error, fallback: ErrorCode.projectUpdateFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.projectUpdateFailed])
            }
        }
    }
}
