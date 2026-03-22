import Foundation
import Protocols

struct SkillsAPIRouter: APIRouter {
    private let service: CoreService

    init(service: CoreService) {
        self.service = service
    }

    func configure(on router: CoreRouterRegistrar) {
        router.get("/v1/skills/registry", metadata: RouteMetadata(summary: "List skills registry", description: "Returns a list of skills available in the registry", tags: ["Skills"])) { request in
            let search = request.queryParam("search")
            let sort = request.queryParam("sort") ?? "installs"
            let limit = Int(request.queryParam("limit") ?? "") ?? 20
            let offset = Int(request.queryParam("offset") ?? "") ?? 0
            CoreRouter.logger.debug("[skills.registry] path=\(request.path) query=\(request.query) -> search=\(search ?? "nil") sort=\(sort) limit=\(limit) offset=\(offset)")
            do {
                let response = try await service.fetchSkillsRegistry(search: search, sort: sort, limit: limit, offset: offset)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.skillsRegistryFailed])
            }
        }

        router.get("/v1/agents/:agentId/skills", metadata: RouteMetadata(summary: "List agent skills", description: "Returns a list of skills installed for an agent", tags: ["Skills"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            do {
                let response = try await service.listAgentSkills(agentID: agentId)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch let error as CoreService.AgentSkillsError {
                return CoreRouter.agentSkillsErrorResponse(error, fallback: ErrorCode.skillsListFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.skillsListFailed])
            }
        }

        router.post("/v1/agents/:agentId/skills", metadata: RouteMetadata(summary: "Install agent skill", description: "Installs a new skill for an agent", tags: ["Skills"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: SkillInstallRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let skill = try await service.installAgentSkill(agentID: agentId, request: payload)
                return CoreRouter.encodable(status: HTTPStatus.created, payload: skill)
            } catch let error as CoreService.AgentSkillsError {
                return CoreRouter.agentSkillsErrorResponse(error, fallback: ErrorCode.skillsInstallFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.skillsInstallFailed])
            }
        }

        router.delete("/v1/agents/:agentId/skills/:skillId", metadata: RouteMetadata(summary: "Uninstall agent skill", description: "Uninstalls a specific skill from an agent", tags: ["Skills"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            let skillId = request.pathParam("skillId") ?? ""
            do {
                try await service.uninstallAgentSkill(agentID: agentId, skillID: skillId)
                return CoreRouter.json(status: HTTPStatus.ok, payload: ["success": "true"])
            } catch let error as CoreService.AgentSkillsError {
                return CoreRouter.agentSkillsErrorResponse(error, fallback: ErrorCode.skillsUninstallFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.skillsUninstallFailed])
            }
        }
    }
}
