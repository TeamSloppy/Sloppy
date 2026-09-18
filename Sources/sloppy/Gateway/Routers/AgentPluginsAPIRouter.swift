import Foundation
import Protocols

struct AgentPluginsAPIRouter: APIRouter {
    private let service: CoreService

    init(service: CoreService) { self.service = service }

    func configure(on router: CoreRouterRegistrar) {
        router.get("/v1/agent-plugins", metadata: .init(summary: "List installed Agent Plugins", tags: ["Agent Plugins"])) { _ in
            CoreRouter.encodable(status: HTTPStatus.ok, payload: await service.listAgentPlugins())
        }
        router.get("/v1/agent-plugins/:pluginId", metadata: .init(summary: "Get an installed Agent Plugin", tags: ["Agent Plugins"])) { request in
            do {
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.getAgentPlugin(id: request.pathParam("pluginId") ?? ""))
            } catch { return Self.errorResponse(error) }
        }
        router.post("/v1/agent-plugins/uploads", metadata: .init(summary: "Upload an Agent Plugin ZIP", tags: ["Agent Plugins"])) { request in
            do {
                guard request.header("content-type")?.lowercased().contains("application/zip") == true else {
                    return CoreRouter.json(status: 415, payload: ["error": "agent_plugin_content_type", "message": "Content-Type must be application/zip"])
                }
                return CoreRouter.encodable(status: HTTPStatus.created, payload: try await service.uploadAgentPlugin(data: request.body ?? Data()))
            } catch { return Self.errorResponse(error) }
        }
        router.post("/v1/agent-plugins/inspections", metadata: .init(summary: "Inspect an Agent Plugin source", tags: ["Agent Plugins"])) { request in
            await Self.decode(request, as: AgentPluginInspectionRequest.self) { payload in
                CoreRouter.encodable(status: HTTPStatus.created, payload: try await service.inspectAgentPlugin(payload))
            }
        }
        router.post("/v1/agent-plugins/plans", metadata: .init(summary: "Create an immutable Agent Plugin install plan", tags: ["Agent Plugins"])) { request in
            await Self.decode(request, as: AgentPluginPlanRequest.self) { payload in
                CoreRouter.encodable(status: HTTPStatus.created, payload: try await service.planAgentPlugin(payload))
            }
        }
        router.post("/v1/agent-plugins/install", metadata: .init(summary: "Install or update an Agent Plugin", tags: ["Agent Plugins"])) { request in
            await Self.decode(request, as: AgentPluginInstallRequest.self) { payload in
                CoreRouter.encodable(status: 202, payload: try await service.installAgentPlugin(payload))
            }
        }
        router.get("/v1/agent-plugins/operations/:operationId", metadata: .init(summary: "Get Agent Plugin operation status", tags: ["Agent Plugins"])) { request in
            do {
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.agentPluginOperation(id: request.pathParam("operationId") ?? ""))
            } catch { return Self.errorResponse(error) }
        }
        router.post("/v1/agent-plugins/:pluginId/uninstall", metadata: .init(summary: "Uninstall an Agent Plugin", tags: ["Agent Plugins"])) { request in
            await Self.decode(request, as: AgentPluginUninstallPlanRequest.self) { payload in
                CoreRouter.encodable(status: 202, payload: try await service.uninstallAgentPlugin(id: request.pathParam("pluginId") ?? "", forceModifiedComponents: payload.forceModifiedComponents))
            }
        }
        router.get("/v1/agent-plugin-registries", metadata: .init(summary: "List Agent Plugin registries", tags: ["Agent Plugins"])) { _ in
            CoreRouter.encodable(status: HTTPStatus.ok, payload: await service.listAgentPluginRegistries())
        }
        router.post("/v1/agent-plugin-registries", metadata: .init(summary: "Add an Agent Plugin registry", tags: ["Agent Plugins"])) { request in
            await Self.decode(request, as: AgentPluginRegistryWriteRequest.self) { payload in
                CoreRouter.encodable(status: HTTPStatus.created, payload: try await service.saveAgentPluginRegistry(id: nil, request: payload))
            }
        }
        router.put("/v1/agent-plugin-registries/:registryId", metadata: .init(summary: "Update an Agent Plugin registry", tags: ["Agent Plugins"])) { request in
            await Self.decode(request, as: AgentPluginRegistryWriteRequest.self) { payload in
                CoreRouter.encodable(status: HTTPStatus.ok, payload: try await service.saveAgentPluginRegistry(id: request.pathParam("registryId"), request: payload))
            }
        }
        router.delete("/v1/agent-plugin-registries/:registryId", metadata: .init(summary: "Delete an Agent Plugin registry", tags: ["Agent Plugins"])) { request in
            do {
                try await service.deleteAgentPluginRegistry(id: request.pathParam("registryId") ?? "")
                return CoreRouter.json(status: HTTPStatus.ok, payload: ["ok": "true"])
            } catch { return Self.errorResponse(error) }
        }
        router.get("/v1/agent-plugin-catalog", metadata: .init(summary: "Search configured Agent Plugin registries", tags: ["Agent Plugins"])) { request in
            let response = await service.searchAgentPluginCatalog(
                search: request.queryParam("search") ?? request.queryParam("q") ?? "",
                registryID: request.queryParam("registryId"),
                cursor: request.queryParam("cursor"),
                limit: Int(request.queryParam("limit") ?? "") ?? 40
            )
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
        }
    }

    private static func decode<T: Decodable>(
        _ request: HTTPRequest,
        as type: T.Type,
        action: (T) async throws -> CoreRouterResponse
    ) async -> CoreRouterResponse {
        guard let body = request.body, let payload = CoreRouter.decode(body, as: type) else {
            return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": "invalid_agent_plugin_payload"])
        }
        do { return try await action(payload) }
        catch { return errorResponse(error) }
    }

    private static func errorResponse(_ error: Error) -> CoreRouterResponse {
        let status: Int
        switch error {
        case AgentPluginManagerError.archiveTooLarge: status = 413
        case AgentPluginManagerError.notFound: status = HTTPStatus.notFound
        case AgentPluginManagerError.conflict, AgentPluginManagerError.approvalRequired, AgentPluginManagerError.expired: status = HTTPStatus.conflict
        default: status = HTTPStatus.badRequest
        }
        return CoreRouter.json(status: status, payload: ["error": "agent_plugin_error", "message": error.localizedDescription])
    }
}
