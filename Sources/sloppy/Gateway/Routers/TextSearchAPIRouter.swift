import Foundation
import Protocols

struct TextSearchAPIRouter: APIRouter {
    let service: CoreService

    func configure(on router: CoreRouterRegistrar) {
        router.get("/v1/search", metadata: RouteMetadata(summary: "Search all session text", description: "Searches a separate SQLite FTS5 index of agent and channel journals. Literal substrings require three characters; shorter queries match word prefixes.", tags: ["Search"])) { request in
            let query = (request.queryParam("q") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let mode = TextSearchMode(rawValue: request.queryParam("mode") ?? "text"),
                  let limit = Int(request.queryParam("limit") ?? "50"),
                  let offset = Int(request.queryParam("offset") ?? "0"), !query.isEmpty else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": "invalid_search_query"])
            }
            do {
                let search = await service.textSearch
                let response = try await search.search(query: query, mode: mode, agentID: request.queryParam("agentId"),
                    projectID: request.queryParam("projectId"), limit: limit, offset: offset)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch TextSearchDatabase.Failure.invalidQuery {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": "invalid_search_query"])
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": "search_unavailable"])
            }
        }
        router.get("/v1/search/document", metadata: RouteMetadata(summary: "Read a search match", description: "Returns the complete text of one indexed event without loading its session", tags: ["Search"])) { request in
            guard let id = request.queryParam("id"), !id.isEmpty, id.count <= 4_096 else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": "invalid_search_document"])
            }
            do {
                let search = await service.textSearch
                guard let document = try await search.document(id: id) else {
                    return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": "search_document_not_found"])
                }
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: document)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": "search_unavailable"])
            }
        }
    }
}
