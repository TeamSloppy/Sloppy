import Foundation
import Protocols

struct ProjectWorkflowsAPIRouter: APIRouter {
    private let service: CoreService

    init(service: CoreService) {
        self.service = service
    }

    func configure(on router: CoreRouterRegistrar) {
        router.get("/v1/projects/:projectId/workflows", metadata: RouteMetadata(summary: "List project workflows", description: "Returns workflow definitions for a project", tags: ["Project Workflows"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            do {
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.listWorkflowDefinitions(projectID: projectId))
            } catch {
                return workflowErrorResponse(error, fallback: ErrorCode.projectReadFailed)
            }
        }

        router.post("/v1/projects/:projectId/workflows", metadata: RouteMetadata(summary: "Create project workflow", description: "Creates a workflow definition", tags: ["Project Workflows"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: WorkflowDefinitionUpsertRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                return CoreRouter.encodable(status: HTTPStatus.created, payload: try await service.createWorkflowDefinition(projectID: projectId, request: payload))
            } catch {
                return workflowErrorResponse(error, fallback: ErrorCode.projectUpdateFailed)
            }
        }

        router.get("/v1/projects/:projectId/workflows/:workflowId", metadata: RouteMetadata(summary: "Get project workflow", description: "Returns one workflow definition", tags: ["Project Workflows"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            let workflowId = request.pathParam("workflowId") ?? ""
            do {
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.getWorkflowDefinition(projectID: projectId, workflowID: workflowId))
            } catch {
                return workflowErrorResponse(error, fallback: ErrorCode.projectReadFailed)
            }
        }

        router.put("/v1/projects/:projectId/workflows/:workflowId", metadata: RouteMetadata(summary: "Update project workflow", description: "Updates one workflow definition", tags: ["Project Workflows"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            let workflowId = request.pathParam("workflowId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: WorkflowDefinitionUpsertRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.updateWorkflowDefinition(projectID: projectId, workflowID: workflowId, request: payload))
            } catch {
                return workflowErrorResponse(error, fallback: ErrorCode.projectUpdateFailed)
            }
        }

        router.delete("/v1/projects/:projectId/workflows/:workflowId", metadata: RouteMetadata(summary: "Delete project workflow", description: "Deletes one workflow definition", tags: ["Project Workflows"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            let workflowId = request.pathParam("workflowId") ?? ""
            do {
                try await service.deleteWorkflowDefinition(projectID: projectId, workflowID: workflowId)
                return CoreRouterResponse(status: 204, body: Data(), contentType: "application/json")
            } catch {
                return workflowErrorResponse(error, fallback: ErrorCode.projectUpdateFailed)
            }
        }

        router.post("/v1/projects/:projectId/workflows/:workflowId/runs", metadata: RouteMetadata(summary: "Start workflow run", description: "Starts a manual project workflow run", tags: ["Project Workflows"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            let workflowId = request.pathParam("workflowId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: WorkflowRunCreateRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                return CoreRouter.encodable(status: HTTPStatus.created, payload: try await service.startWorkflowRun(projectID: projectId, workflowID: workflowId, request: payload))
            } catch {
                return workflowErrorResponse(error, fallback: ErrorCode.projectUpdateFailed)
            }
        }

        router.get("/v1/projects/:projectId/workflow-runs", metadata: RouteMetadata(summary: "List workflow runs", description: "Lists workflow runs for a project", tags: ["Project Workflows"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: await service.listWorkflowRuns(projectID: projectId))
        }

        router.get("/v1/projects/:projectId/workflow-runs/:runId", metadata: RouteMetadata(summary: "Get workflow run", description: "Returns workflow run detail", tags: ["Project Workflows"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            let runId = request.pathParam("runId") ?? ""
            do {
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.getWorkflowRunDetail(projectID: projectId, runID: runId))
            } catch {
                return workflowErrorResponse(error, fallback: ErrorCode.projectReadFailed)
            }
        }

        router.get("/v1/projects/:projectId/workflow-actions", metadata: RouteMetadata(summary: "List workflow actions", description: "Lists unresolved Dashboard workflow actions", tags: ["Project Workflows"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: await service.listWorkflowPendingActions(projectID: projectId))
        }

        router.post("/v1/projects/:projectId/workflow-actions/:actionId/resolve", metadata: RouteMetadata(summary: "Resolve workflow action", description: "Resolves one Dashboard workflow action", tags: ["Project Workflows"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            let actionId = request.pathParam("actionId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: WorkflowActionResolveRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.resolveWorkflowPendingAction(projectID: projectId, actionID: actionId, request: payload))
            } catch {
                return workflowErrorResponse(error, fallback: ErrorCode.projectUpdateFailed)
            }
        }
    }
}

private func workflowErrorResponse(_ error: Error, fallback: String) -> CoreRouterResponse {
    if let projectError = error as? CoreService.ProjectError {
        return CoreRouter.projectErrorResponse(projectError, fallback: fallback)
    }
    if let workflowError = error as? CoreService.WorkflowError {
        switch workflowError {
        case .invalidPayload, .validationFailed:
            return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
        case .workflowNotFound, .runNotFound, .actionNotFound, .projectNotFound:
            return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": ErrorCode.projectNotFound])
        case .storageFailure:
            return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": fallback])
        }
    }
    return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": fallback])
}
