import Foundation
import Protocols

struct PluginsAPIRouter: APIRouter {
    private let service: CoreService

    init(service: CoreService) {
        self.service = service
    }

    func configure(on router: CoreRouterRegistrar) {
        router.get("/v1/plugins", metadata: RouteMetadata(summary: "List channel plugins", description: "Returns a list of all available channel plugins", tags: ["Plugins"])) { _ in
            let plugins = await service.listChannelPlugins()
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: plugins)
        }

        router.post("/v1/plugins", metadata: RouteMetadata(summary: "Create channel plugin", description: "Creates a new channel plugin", tags: ["Plugins"])) { request in
            let payload: ChannelPluginCreateRequest
            switch decodePluginPayload(
                request.body,
                as: ChannelPluginCreateRequest.self,
                expected: "Expected JSON object with non-empty `type` and `baseUrl`, plus optional `id`, `channelIds`, `config`, and `enabled`."
            ) {
            case .success(let decoded):
                payload = decoded
            case .failure(let failure):
                return invalidPluginPayloadResponse(failure.message)
            }
            do {
                let plugin = try await service.createChannelPlugin(payload)
                return CoreRouter.encodable(status: HTTPStatus.created, payload: plugin)
            } catch let error as CoreService.ChannelPluginError {
                return CoreRouter.channelPluginErrorResponse(error)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: [
                    "error": ErrorCode.invalidPluginPayload,
                    "message": error.localizedDescription,
                ])
            }
        }

        router.post("/v1/plugins/install", metadata: RouteMetadata(summary: "Install source plugin", description: "Clones, builds, caches, and loads a source plugin", tags: ["Plugins"])) { request in
            let payload: ChannelPluginInstallRequest
            switch decodePluginPayload(
                request.body,
                as: ChannelPluginInstallRequest.self,
                expected: "Expected JSON object with `sourceUrl` as a Git URL or local plugin package directory. Optional fields: `ref`, `force`, `enabled`, `localDirectory`. Local plugin packages must contain `plugin.json`; Swift plugins also need `Package.swift`."
            ) {
            case .success(let decoded):
                payload = decoded
            case .failure(let failure):
                return invalidPluginPayloadResponse(failure.message)
            }
            do {
                let installed = try await service.installSourceChannelPlugin(payload)
                return CoreRouter.encodable(status: HTTPStatus.created, payload: installed)
            } catch let error as CoreService.ChannelPluginError {
                return CoreRouter.channelPluginErrorResponse(error)
            } catch let error as PluginPackageInstallError {
                let status = pluginInstallHTTPStatus(error)
                return CoreRouter.json(
                    status: status,
                    payload: ["error": ErrorCode.pluginInstallFailed, "message": error.localizedDescription]
                )
            } catch let error as PluginPackageBuildError {
                return CoreRouter.json(
                    status: HTTPStatus.internalServerError,
                    payload: ["error": ErrorCode.pluginInstallFailed, "message": error.localizedDescription]
                )
            } catch {
                return CoreRouter.json(
                    status: HTTPStatus.internalServerError,
                    payload: ["error": ErrorCode.pluginInstallFailed, "message": "\(error)"]
                )
            }
        }

        router.get("/v1/plugins/:pluginId", metadata: RouteMetadata(summary: "Get channel plugin", description: "Returns details of a specific channel plugin", tags: ["Plugins"])) { request in
            let pluginId = request.pathParam("pluginId") ?? ""
            do {
                let plugin = try await service.getChannelPlugin(id: pluginId)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: plugin)
            } catch let error as CoreService.ChannelPluginError {
                return CoreRouter.channelPluginErrorResponse(error)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.pluginNotFound])
            }
        }

        router.put("/v1/plugins/:pluginId", metadata: RouteMetadata(summary: "Update channel plugin", description: "Updates an existing channel plugin", tags: ["Plugins"])) { request in
            let pluginId = request.pathParam("pluginId") ?? ""
            let payload: ChannelPluginUpdateRequest
            switch decodePluginPayload(
                request.body,
                as: ChannelPluginUpdateRequest.self,
                expected: "Expected JSON object with at least one plugin field to update: `type`, `baseUrl`, `channelIds`, `config`, or `enabled`. `type` and `baseUrl` cannot be empty when provided."
            ) {
            case .success(let decoded):
                payload = decoded
            case .failure(let failure):
                return invalidPluginPayloadResponse(failure.message)
            }
            do {
                let plugin = try await service.updateChannelPlugin(id: pluginId, request: payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: plugin)
            } catch let error as CoreService.ChannelPluginError {
                return CoreRouter.channelPluginErrorResponse(error)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: [
                    "error": ErrorCode.invalidPluginPayload,
                    "message": error.localizedDescription,
                ])
            }
        }

        router.delete("/v1/plugins/:pluginId", metadata: RouteMetadata(summary: "Delete channel plugin", description: "Deletes a specific channel plugin", tags: ["Plugins"])) { request in
            let pluginId = request.pathParam("pluginId") ?? ""
            do {
                try await service.deleteChannelPlugin(id: pluginId)
                return CoreRouter.json(status: HTTPStatus.ok, payload: ["ok": "true"])
            } catch let error as CoreService.ChannelPluginError {
                return CoreRouter.channelPluginErrorResponse(error)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.pluginNotFound])
            }
        }
    }
}

private func invalidPluginPayloadResponse(_ message: String) -> CoreRouterResponse {
    CoreRouter.json(status: HTTPStatus.badRequest, payload: [
        "error": ErrorCode.invalidPluginPayload,
        "message": message,
    ])
}

private func decodePluginPayload<T: Decodable>(
    _ body: Data?,
    as type: T.Type,
    expected: String
) -> Result<T, PluginPayloadDecodeFailure> {
    guard let body, !body.isEmpty else {
        return .failure(PluginPayloadDecodeFailure(message: "Plugin request body is required. \(expected)"))
    }

    do {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return .success(try decoder.decode(type, from: body))
    } catch {
        return .failure(PluginPayloadDecodeFailure(message: "Invalid plugin payload. \(expected) \(pluginPayloadDecodeMessage(error))"))
    }
}

private struct PluginPayloadDecodeFailure: Error {
    var message: String
}

private func pluginPayloadDecodeMessage(_ error: Error) -> String {
    guard let decodingError = error as? DecodingError else {
        return error.localizedDescription
    }

    switch decodingError {
    case .keyNotFound(let key, let context):
        return "Missing required field `\(key.stringValue)` at \(pluginPayloadPath(context.codingPath))."
    case .typeMismatch(let type, let context):
        return "Field at \(pluginPayloadPath(context.codingPath)) has the wrong type. Expected \(type). \(context.debugDescription)"
    case .valueNotFound(let type, let context):
        return "Field at \(pluginPayloadPath(context.codingPath)) is null or missing. Expected \(type). \(context.debugDescription)"
    case .dataCorrupted(let context):
        return "JSON value at \(pluginPayloadPath(context.codingPath)) is invalid. \(context.debugDescription)"
    @unknown default:
        return decodingError.localizedDescription
    }
}

private func pluginPayloadPath(_ codingPath: [CodingKey]) -> String {
    guard !codingPath.isEmpty else { return "`$`" }
    return "`" + codingPath.map(\.stringValue).joined(separator: ".") + "`"
}

private func pluginInstallHTTPStatus(_ error: PluginPackageInstallError) -> Int {
    switch error {
    case .conflict:
        return HTTPStatus.conflict
    case .gitCommandFailed, .moveFailed:
        return HTTPStatus.internalServerError
    case .invalidSourceURL,
         .localDirectoryNotFound,
         .localSourceNotDirectory,
         .missingPackageSwift,
         .missingOrInvalidManifest,
         .unsupportedProtocol,
         .invalidPluginName:
        return HTTPStatus.badRequest
    }
}
