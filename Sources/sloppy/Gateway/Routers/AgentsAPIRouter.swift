import Foundation
import Protocols

struct AgentsAPIRouter: APIRouter {
    private let service: CoreService

    init(service: CoreService) {
        self.service = service
    }

    func configure(on router: CoreRouterRegistrar) {
        router.get("/v1/agents", metadata: RouteMetadata(summary: "List agents", description: "Returns a list of all available agents", tags: ["Agents"])) { request in
            let includeSystem = request.queryParam("system").map { $0 != "false" } ?? true
            do {
                let agents = try await service.listAgents(includeSystem: includeSystem)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: agents)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.agentsListFailed])
            }
        }

        router.get("/v1/agents/:agentId", metadata: RouteMetadata(summary: "Get agent", description: "Returns details of a specific agent", tags: ["Agents"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            do {
                let agent = try await service.getAgent(id: agentId)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: agent)
            } catch CoreService.AgentStorageError.invalidID {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidAgentId])
            } catch CoreService.AgentStorageError.notFound {
                return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": ErrorCode.agentNotFound])
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.agentNotFound])
            }
        }

        router.get("/v1/agents/:agentId/tasks", metadata: RouteMetadata(summary: "List agent tasks", description: "Returns a list of tasks assigned to a specific agent", tags: ["Agents"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            do {
                let tasks = try await service.listAgentTasks(agentID: agentId)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: tasks)
            } catch CoreService.AgentStorageError.invalidID {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidAgentId])
            } catch CoreService.AgentStorageError.notFound {
                return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": ErrorCode.agentNotFound])
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.agentNotFound])
            }
        }

        router.get("/v1/agents/:agentId/memories", metadata: RouteMetadata(summary: "List agent memories", description: "Returns a list of memories for a specific agent", tags: ["Agents"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            let search = request.queryParam("search")
            let rawFilter = request.queryParam("filter")?.lowercased() ?? AgentMemoryFilter.all.rawValue
            guard let filter = AgentMemoryFilter(rawValue: rawFilter) else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            let parsedLimit = Int(request.queryParam("limit") ?? "") ?? 20
            let limit = max(1, min(parsedLimit, 100))
            let offset = max(0, Int(request.queryParam("offset") ?? "") ?? 0)

            do {
                let response = try await service.listAgentMemories(
                    agentID: agentId,
                    search: search,
                    filter: filter,
                    limit: limit,
                    offset: offset
                )
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch CoreService.AgentStorageError.invalidID {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidAgentId])
            } catch CoreService.AgentStorageError.notFound {
                return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": ErrorCode.agentNotFound])
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.agentMemoryReadFailed])
            }
        }

        router.get("/v1/agents/:agentId/memories/graph", metadata: RouteMetadata(summary: "Get agent memory graph", description: "Returns a graph representation of agent memories", tags: ["Agents"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            let search = request.queryParam("search")
            let rawFilter = request.queryParam("filter")?.lowercased() ?? AgentMemoryFilter.all.rawValue
            guard let filter = AgentMemoryFilter(rawValue: rawFilter) else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let response = try await service.agentMemoryGraph(
                    agentID: agentId,
                    search: search,
                    filter: filter
                )
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch CoreService.AgentStorageError.invalidID {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidAgentId])
            } catch CoreService.AgentStorageError.notFound {
                return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": ErrorCode.agentNotFound])
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.agentMemoryReadFailed])
            }
        }

        router.patch("/v1/agents/:agentId/memories/:memoryId", metadata: RouteMetadata(summary: "Update agent memory", description: "Updates a specific memory entry for an agent", tags: ["Agents"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            let memoryId = request.pathParam("memoryId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: AgentMemoryUpdateRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let item = try await service.updateAgentMemory(
                    agentID: agentId,
                    memoryID: memoryId,
                    note: payload.note,
                    summary: payload.summary,
                    kind: payload.kind,
                    importance: payload.importance,
                    confidence: payload.confidence
                )
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: item)
            } catch CoreService.AgentStorageError.invalidID {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidAgentId])
            } catch CoreService.AgentStorageError.notFound {
                return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": ErrorCode.agentMemoryNotFound])
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.agentMemoryUpdateFailed])
            }
        }

        router.delete("/v1/agents/:agentId/memories/:memoryId", metadata: RouteMetadata(summary: "Delete agent memory", description: "Soft-deletes a specific memory entry for an agent", tags: ["Agents"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            let memoryId = request.pathParam("memoryId") ?? ""

            do {
                try await service.deleteAgentMemory(agentID: agentId, memoryID: memoryId)
                return CoreRouter.json(status: HTTPStatus.ok, payload: ["status": "deleted"])
            } catch CoreService.AgentStorageError.invalidID {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidAgentId])
            } catch CoreService.AgentStorageError.notFound {
                return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": ErrorCode.agentMemoryNotFound])
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.agentMemoryDeleteFailed])
            }
        }

        router.get("/v1/agents/:agentId/sessions", metadata: RouteMetadata(summary: "List agent sessions", description: "Returns a list of sessions for a specific agent", tags: ["Agents"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            do {
                let sessions = try await service.listAgentSessions(agentID: agentId)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: sessions)
            } catch let error as CoreService.AgentSessionError {
                return CoreRouter.agentSessionErrorResponse(error, fallback: ErrorCode.sessionListFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.sessionListFailed])
            }
        }

        router.get("/v1/agents/:agentId/config", metadata: RouteMetadata(summary: "Get agent config", description: "Returns the configuration for a specific agent", tags: ["Agents"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            do {
                let detail = try await service.getAgentConfig(agentID: agentId)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: detail)
            } catch let error as CoreService.AgentConfigError {
                return CoreRouter.agentConfigErrorResponse(error, fallback: ErrorCode.agentConfigReadFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.agentConfigReadFailed])
            }
        }

        router.get("/v1/agents/:agentId/tools", metadata: RouteMetadata(summary: "Get agent tools", description: "Returns the tool policy for a specific agent", tags: ["Agents"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            do {
                let policy = try await service.getAgentToolsPolicy(agentID: agentId)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: policy)
            } catch let error as CoreService.AgentToolsError {
                return CoreRouter.agentToolsErrorResponse(error, fallback: ErrorCode.agentToolsReadFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.agentToolsReadFailed])
            }
        }

        router.get("/v1/agents/:agentId/tools/catalog", metadata: RouteMetadata(summary: "Get tool catalog", description: "Returns the catalog of available tools for an agent", tags: ["Agents"])) { _ in
            let catalog = await service.toolCatalog()
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: catalog)
        }

        router.get("/v1/agents/:agentId/token-usage", metadata: RouteMetadata(summary: "Get agent token usage", description: "Returns token usage statistics for a specific agent", tags: ["Agents"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            do {
                let usage = try await service.getAgentTokenUsage(agentID: agentId)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: usage)
            } catch CoreService.AgentStorageError.invalidID {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidAgentId])
            } catch CoreService.AgentStorageError.notFound {
                return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": ErrorCode.agentNotFound])
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.tokenUsageReadFailed])
            }
        }

        router.get("/v1/agents/:agentId/sessions/:sessionId", metadata: RouteMetadata(summary: "Get agent session", description: "Returns details of a specific agent session", tags: ["Agents"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            let sessionId = request.pathParam("sessionId") ?? ""
            do {
                let detail = try await service.getAgentSession(agentID: agentId, sessionID: sessionId)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: detail)
            } catch let error as CoreService.AgentSessionError {
                return CoreRouter.agentSessionErrorResponse(error, fallback: ErrorCode.sessionNotFound)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.sessionNotFound])
            }
        }

        router.get("/v1/agents/:agentId/sessions/:sessionId/stream", metadata: RouteMetadata(summary: "Stream agent session", description: "Open a server-sent events stream for session updates", tags: ["Agents"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            let sessionId = request.pathParam("sessionId") ?? ""
            do {
                let stream = try await service.streamAgentSessionEvents(agentID: agentId, sessionID: sessionId)
                return CoreRouter.sse(status: HTTPStatus.ok, updates: stream)
            } catch let error as CoreService.AgentSessionError {
                return CoreRouter.agentSessionErrorResponse(error, fallback: ErrorCode.sessionStreamFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.sessionStreamFailed])
            }
        }

        router.put("/v1/agents/:agentId/config", metadata: RouteMetadata(summary: "Update agent config", description: "Updates the configuration for a specific agent", tags: ["Agents"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: AgentConfigUpdateRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidAgentConfigPayload])
            }

            do {
                let detail = try await service.updateAgentConfig(agentID: agentId, request: payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: detail)
            } catch let error as CoreService.AgentConfigError {
                return CoreRouter.agentConfigErrorResponse(error, fallback: ErrorCode.agentConfigWriteFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.agentConfigWriteFailed])
            }
        }

        router.put("/v1/agents/:agentId/tools", metadata: RouteMetadata(summary: "Update agent tools", description: "Updates the tool policy for a specific agent", tags: ["Agents"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: AgentToolsUpdateRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidAgentToolsPayload])
            }

            do {
                let policy = try await service.updateAgentToolsPolicy(agentID: agentId, request: payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: policy)
            } catch let error as CoreService.AgentToolsError {
                return CoreRouter.agentToolsErrorResponse(error, fallback: ErrorCode.agentToolsWriteFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.agentToolsWriteFailed])
            }
        }

        router.post("/v1/agents", metadata: RouteMetadata(summary: "Create agent", description: "Creates a new agent", tags: ["Agents"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: AgentCreateRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let agent = try await service.createAgent(payload)
                return CoreRouter.encodable(status: HTTPStatus.created, payload: agent)
            } catch CoreService.AgentStorageError.invalidID {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidAgentId])
            } catch CoreService.AgentStorageError.invalidPayload {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidAgentPayload])
            } catch CoreService.AgentStorageError.alreadyExists {
                return CoreRouter.json(status: HTTPStatus.conflict, payload: ["error": ErrorCode.agentAlreadyExists])
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.agentCreateFailed])
            }
        }

        router.post("/v1/agents/:agentId/sessions", metadata: RouteMetadata(summary: "Create agent session", description: "Starts a new session with an agent", tags: ["Agents"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            let payload: AgentSessionCreateRequest

            if let body = request.body {
                guard let decoded = CoreRouter.decode(body, as: AgentSessionCreateRequest.self) else {
                    return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
                }
                payload = decoded
            } else {
                payload = AgentSessionCreateRequest()
            }

            do {
                let summary = try await service.createAgentSession(agentID: agentId, request: payload)
                return CoreRouter.encodable(status: HTTPStatus.created, payload: summary)
            } catch let error as CoreService.AgentSessionError {
                return CoreRouter.agentSessionErrorResponse(error, fallback: ErrorCode.sessionCreateFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.sessionCreateFailed])
            }
        }

        router.post("/v1/agents/:agentId/sessions/:sessionId/messages", metadata: RouteMetadata(summary: "Post session message", description: "Sends a new message to an active agent session", tags: ["Agents"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            let sessionId = request.pathParam("sessionId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: AgentSessionPostMessageRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let response = try await service.postAgentSessionMessage(
                    agentID: agentId,
                    sessionID: sessionId,
                    request: payload
                )
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch let error as CoreService.AgentSessionError {
                return CoreRouter.agentSessionErrorResponse(error, fallback: ErrorCode.sessionWriteFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.sessionWriteFailed])
            }
        }

        router.post("/v1/agents/:agentId/sessions/:sessionId/control", metadata: RouteMetadata(summary: "Control agent session", description: "Sends a control command (e.g., interrupt) to an agent session", tags: ["Agents"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            let sessionId = request.pathParam("sessionId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: AgentSessionControlRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let response = try await service.controlAgentSession(
                    agentID: agentId,
                    sessionID: sessionId,
                    request: payload
                )
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch let error as CoreService.AgentSessionError {
                return CoreRouter.agentSessionErrorResponse(error, fallback: ErrorCode.sessionWriteFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.sessionWriteFailed])
            }
        }

        router.post("/v1/agents/:agentId/sessions/:sessionId/events", metadata: RouteMetadata(summary: "Append session events", description: "Appends events to a session without triggering agent processing", tags: ["Agents"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            let sessionId = request.pathParam("sessionId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: AgentSessionAppendEventsRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let response = try await service.appendAgentSessionEvents(
                    agentID: agentId,
                    sessionID: sessionId,
                    request: payload
                )
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch let error as CoreService.AgentSessionError {
                return CoreRouter.agentSessionErrorResponse(error, fallback: ErrorCode.sessionWriteFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.sessionWriteFailed])
            }
        }

        router.post("/v1/agents/:agentId/sessions/:sessionId/tools/invoke", metadata: RouteMetadata(summary: "Invoke tool", description: "Manually invokes a tool for an agent session", tags: ["Agents"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            let sessionId = request.pathParam("sessionId") ?? ""
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: ToolInvocationRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidToolInvocationPayload])
            }

            do {
                let result = try await service.invokeTool(agentID: agentId, sessionID: sessionId, request: payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: result)
            } catch let error as CoreService.ToolInvocationError {
                return CoreRouter.toolInvocationErrorResponse(error, fallback: ErrorCode.toolInvokeFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.toolInvokeFailed])
            }
        }

        router.delete("/v1/agents/:agentId/sessions/:sessionId", metadata: RouteMetadata(summary: "Delete agent session", description: "Deletes a specific agent session", tags: ["Agents"])) { request in
            let agentId = request.pathParam("agentId") ?? ""
            let sessionId = request.pathParam("sessionId") ?? ""

            do {
                try await service.deleteAgentSession(agentID: agentId, sessionID: sessionId)
                return CoreRouter.json(status: HTTPStatus.ok, payload: ["status": "deleted"])
            } catch let error as CoreService.AgentSessionError {
                return CoreRouter.agentSessionErrorResponse(error, fallback: ErrorCode.sessionDeleteFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.sessionDeleteFailed])
            }
        }
    }
}
