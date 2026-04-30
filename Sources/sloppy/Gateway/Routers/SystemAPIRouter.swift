import ChannelPluginSupport
import Foundation
import Protocols

private struct RuntimeConfigResponse: Encodable {
    var config: CoreConfig
    var debugEnabled: Bool

    func encode(to encoder: Encoder) throws {
        try config.encode(to: encoder)
        var container = encoder.container(keyedBy: RuntimeConfigResponseKeys.self)
        try container.encode(debugEnabled, forKey: .debugEnabled)
    }

    private enum RuntimeConfigResponseKeys: String, CodingKey {
        case debugEnabled
    }
}

private struct UpdateStatusResponse: Encodable {
    var currentVersion: String
    var latestVersion: String?
    var updateAvailable: Bool
    var releaseUrl: String?
    var publishedAt: Date?
    var lastCheckedAt: Date?
    var isReleaseBuild: Bool
    var deploymentKind: DeploymentKind
    var currentCommit: String?
    var currentBranch: String?
    var currentCommitDate: Date?
    var latestCommit: String?
    var latestCommitDate: Date?
    var latestBranch: String?
    var updateKind: UpdateKind
}

private struct SelectDirectoryResponse: Encodable {
    var path: String?
}

private struct DashboardAuthValidateResponse: Encodable {
    struct Capabilities: Encodable {
        var acceptsLegacyToken: Bool
        var mutatingRoutesProtected: Bool
        var terminalWebSocketProtected: Bool
    }

    var ok: Bool
    var capabilities: Capabilities
}

private extension UpdateStatusResponse {
    init(_ status: UpdateStatus) {
        self.currentVersion = status.currentVersion
        self.latestVersion = status.latestVersion
        self.updateAvailable = status.updateAvailable
        self.releaseUrl = status.releaseUrl
        self.publishedAt = status.publishedAt
        self.lastCheckedAt = status.lastCheckedAt
        self.isReleaseBuild = status.isReleaseBuild
        self.deploymentKind = status.deploymentKind
        self.currentCommit = status.currentCommit
        self.currentBranch = status.currentBranch
        self.currentCommitDate = status.currentCommitDate
        self.latestCommit = status.latestCommit
        self.latestCommitDate = status.latestCommitDate
        self.latestBranch = status.latestBranch
        self.updateKind = status.updateKind
    }
}

struct SystemAPIRouter: APIRouter {
    private let service: CoreService

    init(service: CoreService) {
        self.service = service
    }

    func configure(on router: CoreRouterRegistrar) {
        router.get("/health", metadata: RouteMetadata(summary: "Health check", description: "Returns the current status of the sloppy service", tags: ["System"])) { _ in
            CoreRouter.json(status: HTTPStatus.ok, payload: ["status": "ok"])
        }

        router.get("/v1/channel/slash-commands", metadata: RouteMetadata(summary: "List channel slash commands", description: "Returns the same command metadata as Telegram/Discord channel plugins (ChannelCommandHandler)", tags: ["System"])) { _ in
            let items: [ChannelSlashCommandItem] = ChannelCommandHandler.commands.map { cmd in
                ChannelSlashCommandItem(name: cmd.name, description: cmd.description, argument: cmd.argument)
            }
            let payload = ChannelSlashCommandsResponse(commands: items)
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: payload)
        }

        router.get("/v1/bulletins", metadata: RouteMetadata(summary: "List bulletins", description: "Returns a list of active system bulletins", tags: ["System"])) { _ in
            let bulletins = await service.getBulletins()
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: bulletins)
        }

        router.get("/v1/visor/ready", metadata: RouteMetadata(summary: "Visor readiness", description: "Returns whether Visor has completed its first supervision tick", tags: ["System"])) { _ in
            let ready = await service.isVisorReady()
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: VisorReadyResponse(ready: ready))
        }

        router.post("/v1/visor/chat", metadata: RouteMetadata(summary: "Ask Visor", description: "Sends a question to Visor and returns an answer", tags: ["System"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: VisorChatRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            let answer = await service.postVisorChat(question: payload.question)
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: VisorChatResponse(answer: answer))
        }

        router.get("/v1/visor/chat/stream", metadata: RouteMetadata(summary: "Stream Visor answer", description: "Streams a Visor answer as SSE delta events for a given question query param", tags: ["System"])) { request in
            let question = request.queryParam("question") ?? ""
            guard !question.isEmpty else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }
            let stream = await service.streamVisorChat(question: question)
            return CoreRouter.sseText(status: HTTPStatus.ok, stream: stream)
        }

        router.get("/v1/workers", metadata: RouteMetadata(summary: "List workers", description: "Returns a list of active worker runtimes", tags: ["System"])) { _ in
            let workers = await service.workerSnapshots()
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: workers)
        }

        router.get("/v1/config", metadata: RouteMetadata(summary: "Get config", description: "Returns the current sloppy configuration", tags: ["System"])) { _ in
            let config = await service.getConfig()
            let response = RuntimeConfigResponse(config: config, debugEnabled: !SloppyVersion.isReleaseBuild)
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
        }

        router.post("/v1/dashboard/auth/validate", metadata: RouteMetadata(summary: "Validate dashboard token", description: "Validates dashboard operator auth and returns current capability flags", tags: ["System"])) { _ in
            let status = await service.dashboardAuthStatus()
            return CoreRouter.encodable(
                status: HTTPStatus.ok,
                payload: DashboardAuthValidateResponse(
                    ok: true,
                    capabilities: .init(
                        acceptsLegacyToken: status.acceptsLegacyToken,
                        mutatingRoutesProtected: status.protectsMutatingRoutes,
                        terminalWebSocketProtected: status.protectsTerminalWebSocket
                    )
                )
            )
        }

        router.get("/v1/logs", metadata: RouteMetadata(summary: "Get logs", description: "Returns the system logs", tags: ["System"])) { _ in
            do {
                let response = try await service.getSystemLogs()
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch let error as CoreService.SystemLogsError {
                return CoreRouter.systemLogsErrorResponse(error, fallback: ErrorCode.systemLogsReadFailed)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.systemLogsReadFailed])
            }
        }

        router.post("/v1/support/issue-report", metadata: RouteMetadata(summary: "Create issue report", description: "Builds a GitHub issue URL with sanitized diagnostic logs", tags: ["System"])) { request in
            let payload: IssueReportRequest
            if let body = request.body {
                guard let decoded = CoreRouter.decode(body, as: IssueReportRequest.self) else {
                    return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
                }
                payload = decoded
            } else {
                payload = IssueReportRequest()
            }

            do {
                let response = try await service.createIssueReport(request: payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.issueReportFailed])
            }
        }

        router.put("/v1/config", metadata: RouteMetadata(summary: "Update config", description: "Updates the sloppy configuration", tags: ["System"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: CoreConfig.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let config = try await service.updateConfig(payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: config)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": ErrorCode.configWriteFailed])
            }
        }

        router.post("/v1/workers", metadata: RouteMetadata(summary: "Create worker", description: "Registers a new worker runtime", tags: ["System"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: WorkerCreateRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            let workerId = await service.postWorker(request: payload)
            return CoreRouter.encodable(status: HTTPStatus.created, payload: WorkerCreateResponse(workerId: workerId))
        }

        router.get("/v1/token-usage", metadata: RouteMetadata(summary: "List token usage", description: "Returns token usage statistics across all projects and agents", tags: ["System"])) { request in
            let channelId = request.queryParam("channelId")
            let taskId = request.queryParam("taskId")
            let from: Date? = request.queryParam("from").flatMap { CoreRouter.isoDate(from: $0) }
            let to: Date? = request.queryParam("to").flatMap { CoreRouter.isoDate(from: $0) }

            let response = await service.listTokenUsage(channelId: channelId, taskId: taskId, from: from, to: to)
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
        }

        router.get("/v1/updates/check", metadata: RouteMetadata(summary: "Get update status", description: "Returns the current and latest available version of Sloppy", tags: ["System"])) { _ in
            let status = await service.getUpdateStatus()
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: UpdateStatusResponse(status))
        }

        router.post("/v1/updates/check", metadata: RouteMetadata(summary: "Force update check", description: "Forces a fresh check against GitHub releases and returns the result", tags: ["System"])) { _ in
            let status = await service.forceUpdateCheck()
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: UpdateStatusResponse(status))
        }

        router.post("/v1/generate", metadata: RouteMetadata(summary: "Generate text", description: "Generates text using the configured model provider for one-shot completion tasks", tags: ["System"])) { request in
            guard let body = request.body,
                  let payload = CoreRouter.decode(body, as: GenerateTextRequest.self)
            else {
                return CoreRouter.json(status: HTTPStatus.badRequest, payload: ["error": ErrorCode.invalidBody])
            }

            do {
                let response = try await service.generateText(request: payload)
                return CoreRouter.encodable(status: HTTPStatus.ok, payload: response)
            } catch {
                return CoreRouter.json(status: HTTPStatus.internalServerError, payload: ["error": "generation_failed"])
            }
        }

        router.post("/v1/system/select-directory", metadata: RouteMetadata(summary: "Select local directory", description: "Opens a native directory picker and returns the selected directory path", tags: ["System"])) { _ in
            let path = await service.selectDirectory()
            return CoreRouter.encodable(status: HTTPStatus.ok, payload: SelectDirectoryResponse(path: path))
        }
    }
}
