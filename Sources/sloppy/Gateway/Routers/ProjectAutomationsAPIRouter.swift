import Foundation
import Protocols

struct ProjectAutomationsAPIRouter: APIRouter {
    private let service: CoreService

    init(service: CoreService) {
        self.service = service
    }

    func configure(on router: CoreRouterRegistrar) {
        router.get("/v1/projects/:projectId/automations", metadata: RouteMetadata(summary: "List project automations", description: "Returns automation definitions for a project", tags: ["Automations"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            do {
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.listAutomationDefinitions(projectID: projectId))
            } catch {
                return automationErrorResponse(error, fallback: ErrorCode.projectReadFailed)
            }
        }

        router.post("/v1/projects/:projectId/automations", metadata: RouteMetadata(summary: "Create project automation", description: "Creates an automation definition", tags: ["Automations"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: AutomationDefinitionUpsertRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                return CoreRouter.encodable(status: HTTPStatus.created, payload: try await service.createAutomationDefinition(projectID: projectId, request: payload))
            } catch {
                return automationErrorResponse(error, fallback: ErrorCode.projectUpdateFailed)
            }
        }

        router.get("/v1/projects/:projectId/automations/:automationId", metadata: RouteMetadata(summary: "Get project automation", description: "Returns one automation definition", tags: ["Automations"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            let automationId = request.pathParam("automationId") ?? ""
            do {
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.getAutomationDefinition(projectID: projectId, automationID: automationId))
            } catch {
                return automationErrorResponse(error, fallback: ErrorCode.projectReadFailed)
            }
        }

        router.put("/v1/projects/:projectId/automations/:automationId", metadata: RouteMetadata(summary: "Update project automation", description: "Updates one automation definition", tags: ["Automations"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            let automationId = request.pathParam("automationId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: AutomationDefinitionUpsertRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.updateAutomationDefinition(projectID: projectId, automationID: automationId, request: payload))
            } catch {
                return automationErrorResponse(error, fallback: ErrorCode.projectUpdateFailed)
            }
        }

        router.delete("/v1/projects/:projectId/automations/:automationId", metadata: RouteMetadata(summary: "Delete project automation", description: "Deletes one automation definition", tags: ["Automations"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            let automationId = request.pathParam("automationId") ?? ""
            do {
                try await service.deleteAutomationDefinition(projectID: projectId, automationID: automationId)
                return CoreRouterResponse(status: 204, body: Data(), contentType: "application/json")
            } catch {
                return automationErrorResponse(error, fallback: ErrorCode.projectUpdateFailed)
            }
        }

        router.post("/v1/projects/:projectId/automations/:automationId/run", metadata: RouteMetadata(summary: "Run automation manually", description: "Starts one automation run manually", tags: ["Automations"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            let automationId = request.pathParam("automationId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: AutomationManualRunRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            do {
                return CoreRouter.encodable(status: HTTPStatus.created, payload: try await service.startAutomationRun(projectID: projectId, automationID: automationId, request: payload))
            } catch {
                return automationErrorResponse(error, fallback: ErrorCode.projectUpdateFailed)
            }
        }

        router.get("/v1/projects/:projectId/automation-runs", metadata: RouteMetadata(summary: "List automation runs", description: "Lists automation runs for a project", tags: ["Automations"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            do {
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.listAutomationRuns(projectID: projectId))
            } catch {
                return automationErrorResponse(error, fallback: ErrorCode.projectReadFailed)
            }
        }

        router.get("/v1/projects/:projectId/automation-runs/:runId", metadata: RouteMetadata(summary: "Get automation run", description: "Returns one automation run detail", tags: ["Automations"])) { request in
            let projectId = request.pathParam("projectId") ?? ""
            let runId = request.pathParam("runId") ?? ""
            do {
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.getAutomationRunDetail(projectID: projectId, runID: runId))
            } catch {
                return automationErrorResponse(error, fallback: ErrorCode.projectReadFailed)
            }
        }
    }
}

private func automationErrorResponse(_ error: Error, fallback: String) -> CoreRouterResponse {
    if let projectError = error as? CoreService.ProjectError {
        return CoreRouter.projectErrorResponse(projectError, fallback: fallback)
    }
    if let workflowError = error as? CoreService.WorkflowError {
        switch workflowError {
        case .workflowNotFound, .runNotFound, .actionNotFound, .projectNotFound:
            return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": ErrorCode.projectNotFound])
        case .invalidPayload, .validationFailed:
            return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
        case .storageFailure:
            return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": fallback])
        }
    }
    if let automationError = error as? CoreService.AutomationError {
        switch automationError {
        case .automationNotFound, .workflowNotFound, .runNotFound, .projectNotFound:
            return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": ErrorCode.projectNotFound])
        case .invalidPayload, .disabled:
            return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
        case .storageFailure:
            return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": fallback])
        }
    }
    return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": fallback])
}
