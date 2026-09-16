import Foundation
import Protocols

struct WorkspaceBrowserAPIRouter: APIRouter {
    let service: CoreService

    func configure(on router: CoreRouterRegistrar) {
        router.post("/v1/workspace-browser/register", metadata: RouteMetadata(summary: "Connect task browser", description: "Attach an in-app browser to an existing agent session", tags: ["Browser"])) { request in
            guard let body = request.body, let binding = CoreRouter.decode(body, as: WorkspaceBrowserBinding.self) else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": "invalid_body"])
            }
            do {
                _ = try await service.getAgentSession(agentID: binding.agentId, sessionID: binding.sessionId)
                try await service.toolExecution.browserService.workspaceBridge.register(binding)
                return CoreRouter.json(status: HTTPStatus.ok, payload: ["status": "connected"])
            } catch WorkspaceBrowserBridgeError.conflict {
                return CoreRouter.json(status: HTTPStatus.conflict, payload: ["error": "browser_already_connected"])
            } catch {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": "browser_session_unavailable"])
            }
        }
        router.post("/v1/workspace-browser/poll", metadata: RouteMetadata(summary: "Poll task browser", description: "Retrieve commands for this client's browser binding", tags: ["Browser"])) { request in
            guard let body = request.body, let binding = CoreRouter.decode(body, as: WorkspaceBrowserBinding.self) else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": "invalid_body"])
            }
            do {
                let result = try await service.toolExecution.browserService.workspaceBridge.poll(binding)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: result)
            } catch {
                return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": "browser_binding_unavailable"])
            }
        }
        router.post("/v1/workspace-browser/complete", metadata: RouteMetadata(summary: "Complete task browser command", description: "Deliver a result to the waiting agent tool", tags: ["Browser"])) { request in
            guard let body = request.body, let result = CoreRouter.decode(body, as: WorkspaceBrowserCompletion.self) else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": "invalid_body"])
            }
            do {
                try await service.toolExecution.browserService.workspaceBridge.complete(result)
                return CoreRouter.json(status: HTTPStatus.ok, payload: ["status": "completed"])
            } catch {
                return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": "browser_command_unavailable"])
            }
        }
        router.post("/v1/workspace-browser/disconnect", metadata: RouteMetadata(summary: "Disconnect task browser", description: "Release the browser and fail pending commands", tags: ["Browser"])) { request in
            guard let body = request.body, let binding = CoreRouter.decode(body, as: WorkspaceBrowserBinding.self) else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": "invalid_body"])
            }
            await service.toolExecution.browserService.workspaceBridge.disconnect(binding)
            return CoreRouter.json(status: HTTPStatus.ok, payload: ["status": "disconnected"])
        }
    }
}
