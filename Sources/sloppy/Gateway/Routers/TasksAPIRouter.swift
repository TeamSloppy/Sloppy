import Foundation
import Protocols

struct TasksAPIRouter: APIRouter {
    private let service: CoreService

    init(service: CoreService) {
        self.service = service
    }

    func configure(on router: CoreRouterRegistrar) {
        let taskLookupHandler: (HTTPRequest) async -> CoreRouterResponse = { request in
            let taskReference = request.pathParam("taskReference") ?? ""
            do {
                let task = try await service.getProjectTask(taskReference: taskReference)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: task)
            } catch let error as CoreService.ProjectError {
                return CoreRouter.projectErrorResponse(error, fallback: ErrorCode.projectReadFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.projectReadFailed])
            }
        }

        router.get("/v1/tasks/:taskReference", metadata: RouteMetadata(summary: "Get task", description: "Returns details of a specific task by its reference", tags: ["Tasks"]), callback: taskLookupHandler)
        router.get("/tasks/:taskReference", metadata: RouteMetadata(summary: "Get task (legacy)", description: "Returns details of a specific task by its reference (legacy path)", tags: ["Tasks"]), callback: taskLookupHandler)
    }
}
