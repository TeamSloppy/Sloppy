import Foundation
import Protocols

struct SourceControlAPIRouter: APIRouter {
    private let service: CoreService

    init(service: CoreService) {
        self.service = service
    }

    func configure(on router: CoreRouterRegistrar) {
        router.get(
            "/v1/source-control/providers",
            metadata: RouteMetadata(
                summary: "List source-control providers",
                description: "Returns registered source-control providers available for project worktree isolation",
                tags: ["Source Control"]
            )
        ) { _ in
            let providers = await service.listSourceControlProviders()
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: providers)
        }
    }
}
