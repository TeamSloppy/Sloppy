import Foundation
import Protocols

struct MemoryImportsAPIRouter: APIRouter {
    let service: CoreService

    func configure(on router: CoreRouterRegistrar) {
        let base = "/v1/agents/:agentId/memory-imports"
        router.post(base, metadata: .init(summary: "Start verified memory import", description: "Archives sources and starts a durable background import.", tags: ["Memory"])) { request in
            guard let body = request.body, let payload = CoreRouter.decode(body, as: MemoryImportRequest.self) else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            return await respond { try await service.startMemoryImport(agentID: request.pathParam("agentId") ?? "", request: payload) }
        }
        router.post(base + "/from-session/:sessionId", metadata: .init(summary: "Import existing session attachments", description: "Archives and imports Markdown already uploaded to a session.", tags: ["Memory"])) { request in
            await respond { try await service.importSessionAttachments(agentID: request.pathParam("agentId") ?? "", sessionID: request.pathParam("sessionId") ?? "") }
        }
        router.get(base, metadata: .init(summary: "List memory imports", description: "Returns durable import progress and history.", tags: ["Memory"])) { request in
            await respond { try await service.listMemoryImports(agentID: request.pathParam("agentId") ?? "") }
        }
        router.get(base + "/for-memory/:memoryId", metadata: .init(summary: "Find archived memory evidence", description: "Finds reviewed source passages, including confirmed duplicates from legacy imports.", tags: ["Memory"])) { request in
            await respond { try await service.memoryImportSourceLocations(agentID: request.pathParam("agentId") ?? "", memoryID: request.pathParam("memoryId") ?? "") }
        }
        router.get(base + "/:jobId", metadata: .init(summary: "Get memory import", description: "Returns verified coverage and saved counts.", tags: ["Memory"])) { request in
            await respond { try await service.getMemoryImport(agentID: request.pathParam("agentId") ?? "", id: request.pathParam("jobId") ?? "") }
        }
        router.post(base + "/:jobId/resume", metadata: .init(summary: "Resume memory import", description: "Continues unprocessed parts using archived sources.", tags: ["Memory"])) { request in
            await respond { try await service.resumeMemoryImport(agentID: request.pathParam("agentId") ?? "", id: request.pathParam("jobId") ?? "") }
        }
        router.post(base + "/:jobId/cancel", metadata: .init(summary: "Cancel memory import", description: "Stops processing while preserving progress and sources for resumption.", tags: ["Memory"])) { request in
            await respond { try await service.cancelMemoryImport(agentID: request.pathParam("agentId") ?? "", id: request.pathParam("jobId") ?? "") }
        }
        router.get(base + "/:jobId/sources/:sourceId", metadata: .init(summary: "Read archived memory source", description: "Reads an integrity-checked immutable source snapshot, independent of the chat's lifetime.", tags: ["Memory"])) { request in
            await respond { try await service.memoryImportSource(agentID: request.pathParam("agentId") ?? "", id: request.pathParam("jobId") ?? "", sourceID: request.pathParam("sourceId") ?? "") }
        }
    }

    private func respond<T: Encodable & Sendable>(_ action: () async throws -> T) async -> CoreRouterResponse {
        do { return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await action()) }
        catch MemoryImportError.notFound { return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": "memory_import_not_found"]) }
        catch CoreService.AgentStorageError.notFound { return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": ErrorCode.agentNotFound]) }
        catch CoreService.AgentStorageError.invalidID { return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidAgentId]) }
        catch let error as CoreService.AgentSessionError { return CoreRouter.agentSessionErrorResponse(error, fallback: ErrorCode.sessionWriteFailed) }
        catch let error as MemoryImportError { return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": error.localizedDescription]) }
        catch { return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": "memory_import_failed", "message": error.localizedDescription]) }
    }
}
