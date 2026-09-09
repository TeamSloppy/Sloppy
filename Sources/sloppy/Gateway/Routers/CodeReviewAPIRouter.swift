import Foundation
import Protocols

struct CodeReviewAPIRouter: APIRouter {
    private let service: CoreService

    init(service: CoreService) {
        self.service = service
    }

    func configure(on router: CoreRouterRegistrar) {
        router.get(
            "/v1/code-reviews/providers",
            metadata: RouteMetadata(
                summary: "List code-review providers",
                description: "Returns built-in and plugin-backed Pull Requests providers",
                tags: ["Code Review"]
            )
        ) { _ in
            let providers = await service.listCodeReviewProviders()
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: providers)
        }

        router.get(
            "/v1/code-reviews",
            metadata: RouteMetadata(
                summary: "List pull requests",
                description: "Aggregates pull requests from connected code-review providers",
                tags: ["Code Review"]
            )
        ) { request in
            let state = CodeReviewState(rawValue: request.queryParam("state") ?? "open") ?? .open
            let roles = (request.queryParam("roles") ?? "authored,review_requested")
                .split(separator: ",")
                .compactMap { CodeReviewRole(rawValue: String($0)) }
            let providerIDs = Set(
                (request.queryParam("providers") ?? "")
                    .split(separator: ",")
                    .map(String.init)
            )
            let limit = Int(request.queryParam("limit") ?? "") ?? 100
            let response = await service.codeReviewInbox(
                query: CodeReviewQuery(state: state, roles: roles, limit: limit),
                providerIDs: providerIDs
            )
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
        }
    }
}
