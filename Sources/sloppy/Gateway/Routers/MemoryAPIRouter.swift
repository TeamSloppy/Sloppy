import Foundation
import Protocols

struct MemoryAPIRouter: APIRouter {
    let service: CoreService

    func configure(on router: CoreRouterRegistrar) {
        router.get("/v1/memories", metadata: RouteMetadata(
            summary: "Browse memory across scopes",
            description: "Returns active memory records across agents, projects, channels and shared memory.",
            tags: ["Memory"]
        )) { request in
            let scope = request.queryParam("scope") ?? "all"
            guard ["all", "global"].contains(scope),
                  let filter = AgentMemoryFilter(rawValue: request.queryParam("filter") ?? "all") else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            let response = await service.listMemories(
                search: request.queryParam("search"), filter: filter, sharedOnly: scope == "global",
                limit: Int(request.queryParam("limit") ?? "") ?? 20,
                offset: Int(request.queryParam("offset") ?? "") ?? 0
            )
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
        }
    }
}
