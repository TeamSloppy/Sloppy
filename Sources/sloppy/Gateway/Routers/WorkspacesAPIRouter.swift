import Foundation
import Protocols

private struct WorkspaceListResponse: Encodable {
    let workspaces: [WorkspaceRecord]
}

private struct WorkspaceDocumentResponse: Encodable {
    let document: WorkspaceDocument
    let transactions: [WorkspaceCommittedTransaction]
}

private struct WorkspaceArchiveRequest: Decodable {
    let archived: Bool
}

private struct WorkspaceTemplatesResponse: Encodable {
    let templates: [WorkspaceTemplate]
}

private struct WorkspaceMembersResponse: Encodable {
    let members: [WorkspaceMember]
}

private struct WorkspaceConflictResponse: Encodable {
    let error: String
    let latestRevision: Int
    let conflictElementIds: [String]
}

struct WorkspacesAPIRouter: APIRouter {
    private let service: CoreService

    init(service: CoreService) {
        self.service = service
    }

    func configure(on router: CoreRouterRegistrar) {
        router.get("/v1/workspaces", metadata: RouteMetadata(summary: "List workspaces", description: "Lists canvas workspaces visible to the current identity", tags: ["Workspaces"])) { request in
            let context = await actorContext(request)
            let records = await service.listCanvasWorkspaces(
                principalKind: .user,
                principalId: context.actor.id,
                isAdmin: context.isAdmin,
                projectId: request.queryParam("projectId"),
                includeArchived: request.queryParam("archived") == "true"
            )
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: WorkspaceListResponse(workspaces: records))
        }

        router.post("/v1/workspaces", metadata: RouteMetadata(summary: "Create workspace", description: "Creates a blank or template-backed canvas workspace", tags: ["Workspaces"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: WorkspaceCreateRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            let context = await actorContext(request)
            do {
                let record = try await service.createCanvasWorkspace(
                    request: payload,
                    ownerKind: .user,
                    ownerId: context.actor.id
                )
                return CoreRouter.encodable(status: HTTPStatus.created, payload: record)
            } catch {
                return workspaceErrorResponse(error)
            }
        }

        router.get("/v1/workspaces/:workspaceId", metadata: RouteMetadata(summary: "Get workspace", description: "Returns canvas workspace metadata", tags: ["Workspaces"])) { request in
            let context = await actorContext(request)
            do {
                let record = try await service.getCanvasWorkspace(
                    id: request.pathParam("workspaceId") ?? "",
                    principalKind: .user,
                    principalId: context.actor.id,
                    isAdmin: context.isAdmin
                )
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: record)
            } catch {
                return workspaceErrorResponse(error)
            }
        }

        router.patch("/v1/workspaces/:workspaceId", metadata: RouteMetadata(summary: "Update workspace", description: "Updates canvas workspace metadata and project link", tags: ["Workspaces"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: WorkspaceUpdateRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            let context = await actorContext(request)
            do {
                let record = try await service.updateCanvasWorkspace(
                    id: request.pathParam("workspaceId") ?? "",
                    request: payload,
                    principalKind: .user,
                    principalId: context.actor.id,
                    isAdmin: context.isAdmin
                )
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: record)
            } catch {
                return workspaceErrorResponse(error)
            }
        }

        router.post("/v1/workspaces/:workspaceId/archive", metadata: RouteMetadata(summary: "Archive workspace", description: "Archives or restores a canvas workspace", tags: ["Workspaces"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: WorkspaceArchiveRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            let context = await actorContext(request)
            do {
                let record = try await service.archiveCanvasWorkspace(
                    id: request.pathParam("workspaceId") ?? "",
                    archived: payload.archived,
                    principalKind: .user,
                    principalId: context.actor.id,
                    isAdmin: context.isAdmin
                )
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: record)
            } catch {
                return workspaceErrorResponse(error)
            }
        }

        router.get("/v1/workspaces/:workspaceId/document", metadata: RouteMetadata(summary: "Get workspace document", description: "Returns a canvas snapshot and optional transaction delta", tags: ["Workspaces"])) { request in
            let context = await actorContext(request)
            let afterRevision = max(0, Int(request.queryParam("revision") ?? "") ?? 0)
            do {
                async let document = service.canvasWorkspaceDocument(
                    id: request.pathParam("workspaceId") ?? "",
                    principalKind: .user,
                    principalId: context.actor.id,
                    isAdmin: context.isAdmin
                )
                async let transactions = service.canvasWorkspaceTransactions(
                    id: request.pathParam("workspaceId") ?? "",
                    afterRevision: afterRevision,
                    principalKind: .user,
                    principalId: context.actor.id,
                    isAdmin: context.isAdmin
                )
                return try await CoreRouter.encodable(
                    status: HTTPStatus.ok,
                    payload: WorkspaceDocumentResponse(document: document, transactions: transactions)
                )
            } catch {
                return workspaceErrorResponse(error)
            }
        }

        router.post("/v1/workspaces/:workspaceId/transactions", metadata: RouteMetadata(summary: "Commit workspace transaction", description: "Atomically mutates canvas content", tags: ["Workspaces"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: WorkspaceTransactionRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            let context = await actorContext(request)
            do {
                let committed = try await service.commitCanvasWorkspaceTransaction(
                    workspaceId: request.pathParam("workspaceId") ?? "",
                    request: payload,
                    actor: context.actor,
                    isAdmin: context.isAdmin
                )
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: committed)
            } catch {
                return workspaceErrorResponse(error)
            }
        }

        router.post("/v1/workspaces/:workspaceId/transactions/:transactionId/undo", metadata: RouteMetadata(summary: "Undo workspace transaction", description: "Creates a compensating canvas transaction", tags: ["Workspaces"])) { request in
            let context = await actorContext(request)
            do {
                let committed = try await service.undoCanvasWorkspaceTransaction(
                    workspaceId: request.pathParam("workspaceId") ?? "",
                    transactionId: request.pathParam("transactionId") ?? "",
                    actor: context.actor,
                    isAdmin: context.isAdmin
                )
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: committed)
            } catch {
                return workspaceErrorResponse(error)
            }
        }

        router.post("/v1/workspaces/:workspaceId/realtime-ticket", metadata: RouteMetadata(summary: "Create workspace realtime ticket", description: "Creates a short-lived one-use WebSocket ticket", tags: ["Workspaces"])) { request in
            let context = await actorContext(request)
            do {
                let ticket = try await service.createCanvasWorkspaceRealtimeTicket(
                    workspaceId: request.pathParam("workspaceId") ?? "",
                    actor: context.actor,
                    isAdmin: context.isAdmin
                )
                return CoreRouter.encodable(status: HTTPStatus.created, payload: ticket)
            } catch {
                return workspaceErrorResponse(error)
            }
        }

        router.get("/v1/workspaces/:workspaceId/members", metadata: RouteMetadata(summary: "List workspace members", description: "Lists human and agent workspace access", tags: ["Workspaces"])) { request in
            let context = await actorContext(request)
            do {
                let members = try await service.listCanvasWorkspaceMembers(
                    workspaceId: request.pathParam("workspaceId") ?? "",
                    principalKind: .user,
                    principalId: context.actor.id,
                    isAdmin: context.isAdmin
                )
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: WorkspaceMembersResponse(members: members))
            } catch {
                return workspaceErrorResponse(error)
            }
        }

        router.put("/v1/workspaces/:workspaceId/members/:principalId", metadata: RouteMetadata(summary: "Save workspace member", description: "Creates or updates workspace access", tags: ["Workspaces"])) { request in
            guard let body = request.body,
                  let decoded = CoreRouter.decode(body, as: WorkspaceMember.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            let context = await actorContext(request)
            let member = WorkspaceMember(
                workspaceId: request.pathParam("workspaceId") ?? "",
                principalKind: decoded.principalKind,
                principalId: request.pathParam("principalId") ?? "",
                role: decoded.role,
                createdAt: decoded.createdAt
            )
            do {
                let saved = try await service.saveCanvasWorkspaceMember(
                    member,
                    actorKind: .user,
                    actorId: context.actor.id,
                    isAdmin: context.isAdmin
                )
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: saved)
            } catch {
                return workspaceErrorResponse(error)
            }
        }

        router.get("/v1/workspace-templates", metadata: RouteMetadata(summary: "List workspace templates", description: "Lists built-in, personal, and team templates", tags: ["Workspaces"])) { request in
            let context = await actorContext(request)
            let templates = await service.workspaceTemplates(principalId: context.actor.id)
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: WorkspaceTemplatesResponse(templates: templates))
        }

        router.post("/v1/workspace-templates", metadata: RouteMetadata(summary: "Create workspace template", description: "Saves a personal or team canvas template", tags: ["Workspaces"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: WorkspaceTemplateCreateRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            let context = await actorContext(request)
            do {
                let template = try await service.createWorkspaceTemplate(
                    request: payload,
                    ownerId: context.actor.id
                )
                return CoreRouter.encodable(status: HTTPStatus.created, payload: template)
            } catch {
                return workspaceErrorResponse(error)
            }
        }

        router.post("/v1/workspaces/:workspaceId/templates/:templateId/apply", metadata: RouteMetadata(summary: "Apply workspace template", description: "Adds a remapped template fragment as one transaction", tags: ["Workspaces"])) { request in
            let context = await actorContext(request)
            do {
                let committed = try await service.applyWorkspaceTemplate(
                    workspaceId: request.pathParam("workspaceId") ?? "",
                    templateId: request.pathParam("templateId") ?? "",
                    actor: context.actor,
                    isAdmin: context.isAdmin
                )
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: committed)
            } catch {
                return workspaceErrorResponse(error)
            }
        }

        router.get("/v1/projects/:projectId/workspaces", metadata: RouteMetadata(summary: "List project workspaces", description: "Lists canvas workspaces linked to a project", tags: ["Projects", "Workspaces"])) { request in
            let context = await actorContext(request)
            let records = await service.listCanvasWorkspaces(
                principalKind: .user,
                principalId: context.actor.id,
                isAdmin: context.isAdmin,
                projectId: request.pathParam("projectId"),
                includeArchived: false
            )
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: WorkspaceListResponse(workspaces: records))
        }
    }

    private func actorContext(_ request: HTTPRequest) async -> (actor: WorkspaceActor, isAdmin: Bool) {
        if await service.identityAuthEnabled(),
           let identity = await CoreRouter.identityActor(for: request, service: service) {
            return (
                WorkspaceActor(kind: .user, id: identity.user.id, displayName: identity.user.name),
                identity.user.role == .admin
            )
        }
        return (WorkspaceActor(kind: .user, id: "dashboard", displayName: "Dashboard"), true)
    }

    private func workspaceErrorResponse(_ error: Error) -> CoreRouterResponse {
        guard let error = error as? CoreService.WorkspaceError else {
            return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": "workspace_failed"])
        }
        switch error {
        case .invalidID, .invalidPayload:
            return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": "invalid_workspace_payload"])
        case .notFound:
            return CoreRouter.json(status: HTTPStatus.notFound, payload: ["error": "workspace_not_found"])
        case .forbidden:
            return CoreRouter.json(status: HTTPStatus.forbidden, payload: ["error": "workspace_forbidden"])
        case .conflict(let latestRevision, let elementIds):
            return CoreRouter.encodable(
                status: HTTPStatus.conflict,
                payload: WorkspaceConflictResponse(
                    error: "workspace_conflict",
                    latestRevision: latestRevision,
                    conflictElementIds: elementIds
                )
            )
        }
    }
}
