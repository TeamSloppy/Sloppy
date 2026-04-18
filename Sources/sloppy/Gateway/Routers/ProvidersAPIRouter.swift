import Foundation
import Protocols

struct ProvidersAPIRouter: APIRouter {
    private let service: CoreService

    init(service: CoreService) {
        self.service = service
    }

    func configure(on router: CoreRouterRegistrar) {
        router.get("/v1/providers/openai/status", metadata: RouteMetadata(summary: "OpenAI status", description: "Returns the current status of the OpenAI provider", tags: ["Providers"])) { _ in
            let status = await service.openAIProviderStatus()
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: status)
        }

        router.get("/v1/providers/anthropic/status", metadata: RouteMetadata(summary: "Anthropic status", description: "Returns the current status of the Anthropic provider", tags: ["Providers"])) { _ in
            let status = await service.anthropicProviderStatus()
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: status)
        }

        router.post("/v1/providers/openai/oauth/start", metadata: RouteMetadata(summary: "Start OpenAI OAuth", description: "Creates an OpenAI OAuth authorization URL", tags: ["Providers"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: OpenAIOAuthStartRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let response = try await service.startOpenAIOAuth(request: payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
        }

        router.post("/v1/providers/openai/oauth/complete", metadata: RouteMetadata(summary: "Complete OpenAI OAuth", description: "Exchanges the OpenAI OAuth authorization code for tokens", tags: ["Providers"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: OpenAIOAuthCompleteRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let response = try await service.completeOpenAIOAuth(request: payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch {
                return CoreRouter.encodable(
                    status: HTTPStatus.ok,
                    payload: OpenAIOAuthCompleteResponse(
                        ok: false,
                        message: error.localizedDescription
                    )
                )
            }
        }

        router.post("/v1/providers/openai/oauth/device-code/start", metadata: RouteMetadata(summary: "Start device code flow", description: "Requests a device code for OpenAI OAuth device authorization", tags: ["Providers"])) { _ in
            do {
                let response = try await service.startOpenAIDeviceCode()
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": error.localizedDescription])
            }
        }

        router.post("/v1/providers/openai/oauth/device-code/poll", metadata: RouteMetadata(summary: "Poll device code", description: "Polls the device code authorization status", tags: ["Providers"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: OpenAIDeviceCodePollRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let response = try await service.pollOpenAIDeviceCode(request: payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch {
                return CoreRouter.encodable(
                    status: HTTPStatus.ok,
                    payload: OpenAIDeviceCodePollResponse(
                        status: "error",
                        ok: false,
                        message: error.localizedDescription
                    )
                )
            }
        }

        router.post("/v1/providers/openai/oauth/disconnect", metadata: RouteMetadata(summary: "Disconnect OpenAI OAuth", description: "Removes stored OpenAI OAuth credentials", tags: ["Providers"])) { _ in
            do {
                try await service.disconnectOpenAIOAuth()
                return CoreRouter.json(status: HTTPStatus.ok, payload: ["ok": "true"])
            } catch {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": error.localizedDescription])
            }
        }

        router.post("/v1/providers/anthropic/oauth/start", metadata: RouteMetadata(summary: "Start Anthropic OAuth", description: "Creates an Anthropic OAuth authorization URL", tags: ["Providers"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: AnthropicOAuthStartRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let response = try await service.startAnthropicOAuth(request: payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": error.localizedDescription])
            }
        }

        router.post("/v1/providers/anthropic/oauth/complete", metadata: RouteMetadata(summary: "Complete Anthropic OAuth", description: "Exchanges the Anthropic OAuth authorization code for tokens", tags: ["Providers"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: AnthropicOAuthCompleteRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let response = try await service.completeAnthropicOAuth(request: payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch {
                return CoreRouter.encodable(
                    status: HTTPStatus.ok,
                    payload: AnthropicOAuthCompleteResponse(
                        ok: false,
                        message: error.localizedDescription
                    )
                )
            }
        }

        router.post("/v1/providers/anthropic/oauth/import-claude", metadata: RouteMetadata(summary: "Import Claude Code credentials", description: "Imports refreshable Claude Code credentials into Sloppy", tags: ["Providers"])) { _ in
            do {
                let response = try await service.importAnthropicClaudeCredentials()
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch {
                return CoreRouter.encodable(
                    status: HTTPStatus.ok,
                    payload: AnthropicOAuthImportClaudeResponse(
                        ok: false,
                        message: error.localizedDescription
                    )
                )
            }
        }

        router.post("/v1/providers/anthropic/oauth/disconnect", metadata: RouteMetadata(summary: "Disconnect Anthropic OAuth", description: "Removes stored Anthropic OAuth credentials", tags: ["Providers"])) { _ in
            do {
                try await service.disconnectAnthropicOAuth()
                return CoreRouter.json(status: HTTPStatus.ok, payload: ["ok": "true"])
            } catch {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": error.localizedDescription])
            }
        }

        router.get("/v1/providers/search/status", metadata: RouteMetadata(summary: "Search status", description: "Returns the current status of the search provider", tags: ["Providers"])) { _ in
            let status = await service.searchProviderStatus()
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: status)
        }

        router.post("/v1/providers/probe", metadata: RouteMetadata(summary: "Probe provider", description: "Tests a specific provider configuration", tags: ["Providers"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: ProviderProbeRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            let response = await service.probeProvider(request: payload)
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
        }

        router.post("/v1/providers/openai/models", metadata: RouteMetadata(summary: "List OpenAI models", description: "Returns a list of available models for OpenAI", tags: ["Providers"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: OpenAIProviderModelsRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            let response = await service.listOpenAIModels(request: payload)
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
        }
    }
}
