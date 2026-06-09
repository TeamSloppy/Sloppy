import Foundation
import SloppyNodeCore

struct NodeMeshAPIRouter: APIRouter {
    private let service: CoreService

    init(service: CoreService) {
        self.service = service
    }

    func configure(on router: CoreRouterRegistrar) {
        router.get("/v1/node/mesh/nodes", metadata: RouteMetadata(summary: "List mesh nodes", description: "Returns known SloppyNode mesh nodes and statuses", tags: ["Node Mesh"])) { _ in
            do {
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.listMeshNodes())
            } catch {
                return meshErrorResponse(error)
            }
        }

        router.get("/v1/node/mesh/shared-projects", metadata: RouteMetadata(summary: "List shared projects", description: "Returns SloppyNode mesh shared projects and members", tags: ["Node Mesh"])) { _ in
            do {
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.listMeshSharedProjects())
            } catch {
                return meshErrorResponse(error)
            }
        }

        router.post("/v1/node/mesh/shared-projects", metadata: RouteMetadata(summary: "Create shared project", description: "Creates a SloppyNode mesh shared project", tags: ["Node Mesh"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: MeshSharedProjectCreateRequest.self) else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                return CoreRouter.encodable(status: HTTPStatus.created, payload: try await service.createMeshSharedProject(payload))
            } catch {
                return meshErrorResponse(error)
            }
        }

        router.patch("/v1/node/mesh/shared-projects/:projectId", metadata: RouteMetadata(summary: "Update shared project", description: "Updates SloppyNode mesh shared project metadata", tags: ["Node Mesh"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: MeshSharedProjectUpdateRequest.self) else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let projectId = request.pathParam("projectId") ?? ""
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.updateMeshSharedProject(id: projectId, request: payload))
            } catch {
                return meshErrorResponse(error)
            }
        }

        router.post("/v1/node/mesh/shared-projects/:projectId/members", metadata: RouteMetadata(summary: "Attach shared project member", description: "Adds or updates a mesh node member for a shared project", tags: ["Node Mesh"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: MeshSharedProjectMemberRequest.self) else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let projectId = request.pathParam("projectId") ?? ""
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.attachMeshSharedProjectMember(projectId: projectId, request: payload))
            } catch {
                return meshErrorResponse(error)
            }
        }

        router.get("/v1/node/mesh/tasks", metadata: RouteMetadata(summary: "List mesh tasks", description: "Returns SloppyNode mesh task lifecycle records", tags: ["Node Mesh"])) { request in
            do {
                let projectId = request.queryParam("projectId")
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.listMeshTasks(projectId: projectId))
            } catch {
                return meshErrorResponse(error)
            }
        }

        router.post("/v1/node/mesh/tasks", metadata: RouteMetadata(summary: "Dispatch mesh task", description: "Creates and dispatches a task to a mesh node", tags: ["Node Mesh"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: MeshTaskCreateRequest.self) else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                return CoreRouter.encodable(status: HTTPStatus.created, payload: try await service.createMeshTask(payload))
            } catch {
                return meshErrorResponse(error)
            }
        }

        router.patch("/v1/node/mesh/tasks/:taskId", metadata: RouteMetadata(summary: "Update mesh task", description: "Updates mesh task lifecycle state and review metadata", tags: ["Node Mesh"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: MeshTaskUpdateRequest.self) else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let taskId = request.pathParam("taskId") ?? ""
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.updateMeshTask(id: taskId, request: payload))
            } catch {
                return meshErrorResponse(error)
            }
        }

        router.get("/v1/node/mesh/audit-log", metadata: RouteMetadata(summary: "List mesh audit log", description: "Returns mesh authorization, routing, and task audit entries", tags: ["Node Mesh"])) { _ in
            do {
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.listMeshAuditLog())
            } catch {
                return meshErrorResponse(error)
            }
        }
    }
}

private func meshErrorResponse(_ error: Error) -> CoreRouterResponse {
    let message = error.localizedDescription
    if let meshError = error as? NodeMeshStoreError {
        switch meshError {
        case .nodeMissing, .projectMissing, .taskMissing:
            return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": "mesh_not_found", "message": message])
        case .permissionDenied:
            return CoreRouter.json(status: HTTPStatus.forbidden, payload: ["error": "mesh_forbidden", "message": message])
        case .inviteMissing, .inviteExpired, .inviteConsumed:
            return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": "mesh_invalid_request", "message": message])
        }
    }
    return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": "mesh_store_failed", "message": message])
}
