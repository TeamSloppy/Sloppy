import AnyLanguageModel
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(AppKit)
import AppKit
#endif
import AgentRuntime
import ChannelPluginDiscord
import ChannelPluginTelegram
import Logging
import Protocols
import PluginSDK
import CodexBarCore

public enum AgentSessionStreamUpdateKind: String, Codable, Sendable {
    case sessionReady = "session_ready"
    case sessionEvent = "session_event"
    case sessionDelta = "session_delta"
    case heartbeat
    case sessionClosed = "session_closed"
    case sessionError = "session_error"
}

public struct AgentSessionStreamUpdate: Codable, Sendable {
    public var kind: AgentSessionStreamUpdateKind
    public var cursor: Int
    public var summary: AgentSessionSummary?
    public var event: AgentSessionEvent?
    public var message: String?
    public var createdAt: Date

    public init(
        kind: AgentSessionStreamUpdateKind,
        cursor: Int,
        summary: AgentSessionSummary? = nil,
        event: AgentSessionEvent? = nil,
        message: String? = nil,
        createdAt: Date = Date()
    ) {
        self.kind = kind
        self.cursor = cursor
        self.summary = summary
        self.event = event
        self.message = message
        self.createdAt = createdAt
    }
}

struct BuiltInGatewayPluginFactory: Sendable {
    let makeTelegram: @Sendable (CoreConfig.ChannelConfig.Telegram) -> any GatewayPlugin
    let makeDiscord: @Sendable (CoreConfig.ChannelConfig.Discord) -> any GatewayPlugin

    static let live = BuiltInGatewayPluginFactory(
        makeTelegram: { config in
            TelegramGatewayPlugin(
                botToken: config.botToken,
                channelChatMap: config.channelChatMap,
                allowedUserIds: config.allowedUserIds,
                allowedChatIds: config.allowedChatIds,
                logger: Logger(label: "sloppy.plugin.telegram")
            )
        },
        makeDiscord: { config in
            DiscordGatewayPlugin(
                botToken: config.botToken,
                channelDiscordChannelMap: config.channelDiscordChannelMap,
                allowedGuildIds: config.allowedGuildIds,
                allowedChannelIds: config.allowedChannelIds,
                allowedUserIds: config.allowedUserIds,
                logger: Logger(label: "sloppy.plugin.discord")
            )
        }
    )
}

public actor CoreService {
    static let heartbeatSuccessToken = "SLOPPY_ACTION_OK"
    static let agentMemoryGraphSeedLimit = 50
    static let agentMemoryGraphNeighborLimit = 150

    public enum AgentStorageError: Error {
        case invalidID
        case invalidPayload
        case alreadyExists
        case notFound
    }

    public enum AgentSessionError: Error {
        case invalidAgentID
        case invalidSessionID
        case invalidPayload
        case agentNotFound
        case sessionNotFound
        case storageFailure
    }

    public enum AgentConfigError: Error {
        case invalidAgentID
        case invalidPayload
        case invalidModel
        case agentNotFound
        case storageFailure
        case documentLengthExceeded(resource: String, limit: Int)
    }

    public enum AgentToolsError: Error {
        case invalidAgentID
        case invalidPayload
        case agentNotFound
        case storageFailure
    }

    public enum ToolInvocationError: Error {
        case invalidAgentID
        case invalidSessionID
        case invalidPayload
        case agentNotFound
        case sessionNotFound
        case forbidden(ToolErrorPayload)
        case storageFailure
    }

    public enum SystemLogsError: Error {
        case storageFailure
    }

    public enum ActorBoardError: Error {
        case invalidPayload
        case actorNotFound
        case linkNotFound
        case teamNotFound
        case protectedActor
        case storageFailure
    }

    public enum ProjectError: Error {
        case invalidProjectID
        case invalidChannelID
        case invalidTaskID
        case invalidPayload
        case notFound
        case conflict
    }

    public enum ChannelPluginError: Error {
        case invalidID
        case invalidPayload
        case notFound
        case conflict
    }

    public enum AgentSkillsError: Error {
        case invalidAgentID
        case invalidPayload
        case agentNotFound
        case skillNotFound
        case skillAlreadyExists
        case storageFailure
        case networkFailure
        case downloadFailure
    }

    public enum GenerateError: Error {
        case noModelProvider
        case noModelAvailable
        case generationFailed
    }

    public enum AgentCronTaskError: Error {
        case invalidAgentID
        case invalidPayload
        case notFound
        case storageFailure
    }

    /// Retained for checkpoint / one-off model sessions (also held inside `runtime`).
    var modelProvider: (any ModelProvider)?
    let runtime: RuntimeSystem
    let memoryStore: any MemoryStore
    let hybridMemoryStore: HybridMemoryStore?
    let persistenceBuilder: any CorePersistenceBuilding
    var store: any PersistenceStore
    let openAIProviderCatalog: OpenAIProviderCatalogService
    let openAIOAuthService: OpenAIOAuthService
    let githubAuthService: GitHubAuthService
    let providerProbeService: ProviderProbeService
    let searchProviderService: SearchProviderService
    let agentCatalogStore: AgentCatalogFileStore
    let sessionStore: AgentSessionFileStore
    let actorBoardStore: ActorBoardFileStore
    let sessionOrchestrator: AgentSessionOrchestrator
    let acpSessionManager: ACPSessionManager
    let toolsAuthorization: ToolAuthorizationService
    var toolExecution: ToolExecutionService
    let mcpRegistry: MCPClientRegistry
    let systemLogStore: SystemLogFileStore
    var channelDelivery: ChannelDeliveryService
    let channelSessionStore: ChannelSessionFileStore
    let agentSkillsStore: AgentSkillsFileStore
    let skillsRegistryService: SkillsRegistryService
    let skillsGitHubClient: SkillsGitHubClient
    let updateChecker: UpdateCheckerService
    let swarmPlanner: SwarmPlanner
    let gitWorktreeService: GitWorktreeService
    let logger: Logger
    let configPath: String
    let builtInGatewayPluginFactory: BuiltInGatewayPluginFactory
    let channelModelStore: ChannelModelStore
    var workspaceRootURL: URL
    var agentsRootURL: URL
    var currentConfig: CoreConfig
    var eventTask: Task<Void, Never>?
    var activeGatewayPlugins: [any GatewayPlugin] = []
    var visorScheduler: VisorScheduler?
    var cronRunner: CronRunner?
    var heartbeatRunner: HeartbeatRunner?
    var memoryOutboxIndexer: MemoryOutboxIndexer?
    var recoveryManager: RecoveryManager
    var oauthModelCache: [String: ProviderModelOption] = [:]
    var liveSessionStreamContinuations: [String: [UUID: AsyncStream<AgentSessionStreamUpdate>.Continuation]] = [:]
    var liveSessionStreamCursor: [String: Int] = [:]
    var sessionExtraRoots: [String: [String]] = [:]
    /// When set, only these tool IDs may execute for the session (subagent isolation overlay).
    var sessionSubagentToolAllowList: [String: Set<String>] = [:]
    /// Prevents overlapping memory checkpoints per agent/session pair.
    var memoryCheckpointLocks: Set<String> = []
    public let notificationService: NotificationService
    public let pendingApprovalService: PendingApprovalService

    /// Creates core orchestration service with runtime and persistence backend.
    public init(
        config: CoreConfig,
        configPath: String = CoreConfig.defaultConfigPath,
        persistenceBuilder: any CorePersistenceBuilding = DefaultCorePersistenceBuilder(),
        searchProviderService: SearchProviderService? = nil
    ) {
        self.init(
            config: config,
            configPath: configPath,
            persistenceBuilder: persistenceBuilder,
            searchProviderService: searchProviderService,
            builtInGatewayPluginFactory: .live
        )
    }

    init(
        config: CoreConfig,
        configPath: String = CoreConfig.defaultConfigPath,
        persistenceBuilder: any CorePersistenceBuilding = DefaultCorePersistenceBuilder(),
        searchProviderService: SearchProviderService? = nil,
        providerProbeService: ProviderProbeService? = nil,
        builtInGatewayPluginFactory: BuiltInGatewayPluginFactory
    ) {
        let workspaceRootURL = config.resolvedWorkspaceRootURL(currentDirectory: FileManager.default.currentDirectoryPath)
        self.openAIOAuthService = OpenAIOAuthService(workspaceRootURL: workspaceRootURL)
        self.githubAuthService = GitHubAuthService(workspaceRootURL: workspaceRootURL)
        self.mcpRegistry = MCPClientRegistry(
            config: config.mcp,
            logger: Logger(label: "sloppy.mcp")
        )
        let oauthService = self.openAIOAuthService
        let hasOAuth = oauthService.currentAccessToken() != nil
        let resolvedModels = CoreModelProviderFactory.resolveModelIdentifiers(
            config: config,
            hasOAuthCredentials: hasOAuth
        )
        let modelProvider = CoreModelProviderFactory.buildModelProvider(
            config: config,
            resolvedModels: resolvedModels,
            tools: ToolRegistry.makeDefault().allTools,
            oauthTokenProvider: { oauthService.currentAccessToken() },
            oauthAccountId: oauthService.currentAccountId(),
            oauthTokenRefresh: { try await oauthService.ensureValidToken() },
            systemInstructions: "You are Sloppy core channel assistant.",
            proxySession: ProxySessionFactory.makeSession(proxy: config.proxy)
        )
        let runtimeMemoryStore: any MemoryStore
        let hybridMemoryStore: HybridMemoryStore?
        if persistenceBuilder is InMemoryCorePersistenceBuilder {
            hybridMemoryStore = nil
            runtimeMemoryStore = InMemoryMemoryStore()
        } else {
            let embeddingService = EmbeddingService.make(
                config: config,
                logger: Logger(label: "sloppy.memory.embedding")
            )
            let store = HybridMemoryStore(
                config: config,
                mcpRegistry: self.mcpRegistry,
                embeddingService: embeddingService
            )
            hybridMemoryStore = store
            runtimeMemoryStore = store
        }
        let visorCompletionProvider = Self.buildVisorCompletionProvider(
            modelProvider: modelProvider,
            visorModel: config.visor.model,
            resolvedModels: resolvedModels
        )
        let visorStreamingProvider = Self.buildVisorStreamingProvider(
            modelProvider: modelProvider,
            visorModel: config.visor.model,
            resolvedModels: resolvedModels
        )
        self.modelProvider = modelProvider
        let runtime = RuntimeSystem(
            modelProvider: modelProvider,
            defaultModel: modelProvider?.supportedModels.first ?? resolvedModels.first,
            memoryStore: runtimeMemoryStore,
            visorCompletionProvider: visorCompletionProvider,
            visorStreamingProvider: visorStreamingProvider,
            visorBulletinMaxWords: config.visor.bulletinMaxWords
        )
        self.runtime = runtime
        self.memoryStore = runtimeMemoryStore
        self.hybridMemoryStore = hybridMemoryStore
        self.persistenceBuilder = persistenceBuilder
        self.store = persistenceBuilder.makeStore(config: config)
        self.workspaceRootURL = config
            .resolvedWorkspaceRootURL(currentDirectory: FileManager.default.currentDirectoryPath)
        self.openAIProviderCatalog = OpenAIProviderCatalogService()
        self.providerProbeService = providerProbeService ?? ProviderProbeService()
        self.searchProviderService = searchProviderService ?? SearchProviderService(config: config.searchTools)
        self.configPath = configPath
        self.agentsRootURL = self.workspaceRootURL
            .appendingPathComponent("agents", isDirectory: true)
        self.agentCatalogStore = AgentCatalogFileStore(agentsRootURL: self.agentsRootURL)
        self.sessionStore = AgentSessionFileStore(agentsRootURL: self.agentsRootURL)
        self.systemLogStore = SystemLogFileStore(workspaceRootURL: self.workspaceRootURL)
        self.channelDelivery = ChannelDeliveryService(store: self.store)
        self.actorBoardStore = ActorBoardFileStore(workspaceRootURL: self.workspaceRootURL)
        self.channelSessionStore = ChannelSessionFileStore(workspaceRootURL: self.workspaceRootURL)
        self.channelModelStore = ChannelModelStore(workspaceRootURL: self.workspaceRootURL)
        self.agentSkillsStore = AgentSkillsFileStore(agentsRootURL: self.agentsRootURL)
        self.skillsRegistryService = SkillsRegistryService()
        let githubAuth = self.githubAuthService
        self.skillsGitHubClient = SkillsGitHubClient(tokenProvider: { githubAuth.currentToken() })
        self.updateChecker = UpdateCheckerService()
        self.swarmPlanner = SwarmPlanner { prompt, maxTokens in
            await runtime.complete(prompt: prompt, maxTokens: maxTokens)
        }
        self.gitWorktreeService = GitWorktreeService()
        let orchestratorCatalogStore = AgentCatalogFileStore(agentsRootURL: self.agentsRootURL)
        let orchestratorSessionStore = AgentSessionFileStore(agentsRootURL: self.agentsRootURL)
        let orchestratorSkillsStore = AgentSkillsFileStore(agentsRootURL: self.agentsRootURL)
        let initialAvailableAgentModels = Self.availableAgentModels(config: config, hasOAuthCredentials: hasOAuth)
        self.acpSessionManager = ACPSessionManager(
            config: config.acp,
            workspaceRootURL: self.workspaceRootURL,
            agentsRootURL: self.agentsRootURL
        )
        self.sessionOrchestrator = AgentSessionOrchestrator(
            runtime: self.runtime,
            sessionStore: orchestratorSessionStore,
            agentCatalogStore: orchestratorCatalogStore,
            agentSkillsStore: orchestratorSkillsStore,
            acpSessionManager: self.acpSessionManager,
            availableModels: initialAvailableAgentModels
        )
        let toolsStore = AgentToolsFileStore(agentsRootURL: self.agentsRootURL)
        self.toolsAuthorization = ToolAuthorizationService(store: toolsStore, mcpRegistry: self.mcpRegistry)
        let processRegistry = SessionProcessRegistry()
        self.toolExecution = ToolExecutionService(
            workspaceRootURL: self.workspaceRootURL,
            runtime: self.runtime,
            memoryStore: self.memoryStore,
            sessionStore: self.sessionStore,
            agentCatalogStore: self.agentCatalogStore,
            processRegistry: processRegistry,
            channelSessionStore: self.channelSessionStore,
            store: self.store,
            searchProviderService: self.searchProviderService,
            mcpRegistry: self.mcpRegistry,
            lspConfig: config.lsp
        )
        self.logger = Logger(label: "sloppy.core.visor")
        self.builtInGatewayPluginFactory = builtInGatewayPluginFactory
        if let hybridMemoryStore {
            self.memoryOutboxIndexer = MemoryOutboxIndexer(
                store: hybridMemoryStore,
                logger: Logger(label: "sloppy.memory.outbox")
            )
        } else {
            self.memoryOutboxIndexer = nil
        }
        self.recoveryManager = RecoveryManager(store: self.store, runtime: self.runtime, logger: self.logger)
        self.notificationService = NotificationService()
        self.pendingApprovalService = PendingApprovalService(
            workspaceDirectory: config
                .resolvedWorkspaceRootURL(currentDirectory: FileManager.default.currentDirectoryPath).path
        )
        self.currentConfig = config
        Task { [weak self] in
            guard let self else {
                return
            }
            await self.configureToolExecutionServices()
            await self.runtime.updateWorkerExecutor(
                ToolExecutionWorkerExecutorAdapter(
                    toolExecutionService: self.toolExecution,
                    agentRunner: { [weak self] agentID, taskID, objective, workingDirectory in
                        guard let self else { return nil }
                        return await self.runAgentTask(
                            agentID: agentID,
                            taskID: taskID,
                            objective: objective,
                            workingDirectory: workingDirectory
                        )
                    }
                )
            )
            await self.sessionOrchestrator.updateToolInvoker { [weak self] agentID, sessionID, request in
                guard let self else {
                    return ToolInvocationResult(
                        tool: request.tool,
                        ok: false,
                        error: ToolErrorPayload(
                            code: "tool_invoker_unavailable",
                            message: "Tool invoker is unavailable.",
                            retryable: true
                        )
                    )
                }
                return await self.invokeToolFromRuntime(
                    agentID: agentID,
                    sessionID: sessionID,
                    request: request,
                    recordSessionEvents: false
                )
            }
            await self.sessionOrchestrator.updateResponseChunkObserver { [weak self] agentID, sessionID, chunk in
                guard let self else {
                    return
                }
                await self.publishLiveSessionDelta(agentID: agentID, sessionID: sessionID, chunk: chunk)
            }
            await self.sessionOrchestrator.updateEventAppendObserver { [weak self] agentID, sessionID, summary, events in
                guard let self else {
                    return
                }
                await self.publishLiveSessionEvents(
                    agentID: agentID,
                    sessionID: sessionID,
                    summary: summary,
                    events: events
                )
                await self.applyPetProgressForAgentSessionEvents(
                    agentID: agentID,
                    sessionID: sessionID,
                    summary: summary,
                    events: events
                )
            }
        }
    }

    deinit {
        eventTask?.cancel()
    }

    // MARK: - Review Flow

    // MARK: - Task Activity

    func projectForChannel(channelId: String, topicId: String? = nil) async -> ProjectRecord? {
        let projects = await store.listProjects()
        if let topicId, !topicId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let compositeId = "\(channelId):\(topicId)"
            if let found = projects
                .sorted(by: { $0.createdAt < $1.createdAt })
                .first(where: { project in
                    project.channels.contains(where: { $0.channelId == compositeId })
                }) {
                return found
            }
        }
        return projects
            .sorted(by: { $0.createdAt < $1.createdAt })
            .first(where: { project in
                project.channels.contains(where: { $0.channelId == channelId })
            })
    }

    func resolveTask(reference: TaskApprovalReference, in project: ProjectRecord) -> ProjectTask? {
        switch reference {
        case .taskID(let taskID):
            let lowercasedTaskID = taskID.lowercased()
            return project.tasks.first(where: { task in
                task.id == taskID || task.id.lowercased() == lowercasedTaskID
            })
        case .index(let oneBasedIndex):
            guard oneBasedIndex > 0 else {
                return nil
            }
            let ordered = project.tasks.sorted(by: { $0.createdAt < $1.createdAt })
            let zeroBasedIndex = oneBasedIndex - 1
            guard ordered.indices.contains(zeroBasedIndex) else {
                return nil
            }
            return ordered[zeroBasedIndex]
        }
    }

    func resolveTask(reference: String, in project: ProjectRecord) throws -> ProjectTask {
        guard let normalizedReference = normalizeTaskReference(reference) else {
            throw ProjectError.invalidTaskID
        }

        let lowercasedTaskID = normalizedReference.lowercased()
        guard let task = project.tasks.first(where: { task in
            task.id == normalizedReference || task.id.lowercased() == lowercasedTaskID
        }) else {
            throw ProjectError.notFound
        }

        return task
    }

    var activeProjectTaskStatuses: Set<String> {
        Set([
            ProjectTaskStatus.pendingApproval.rawValue,
            ProjectTaskStatus.backlog.rawValue,
            ProjectTaskStatus.ready.rawValue,
            ProjectTaskStatus.inProgress.rawValue,
            ProjectTaskStatus.needsReview.rawValue,
        ])
    }

    func normalizedTaskTitleKey(_ value: String) -> String {
        normalizeWhitespace(value).lowercased()
    }

    func normalizeWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isModelProviderError(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("model provider error:")
    }

    func captureGroup(_ source: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let nsSource = source as NSString
        let fullRange = NSRange(location: 0, length: nsSource.length)
        guard let match = regex.firstMatch(in: source, options: [], range: fullRange),
              match.numberOfRanges > 1
        else {
            return nil
        }

        let range = match.range(at: 1)
        guard range.location != NSNotFound else {
            return nil
        }
        return nsSource.substring(with: range)
    }

    func extractTaskReferences(from content: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"#([A-Za-z0-9._-]+-\d+)"#) else {
            return []
        }

        let nsContent = content as NSString
        let range = NSRange(location: 0, length: nsContent.length)
        let matches = regex.matches(in: content, options: [], range: range)
        guard !matches.isEmpty else {
            return []
        }

        var unique: Set<String> = []
        var ordered: [String] = []
        for match in matches where match.numberOfRanges > 1 {
            let tokenRange = match.range(at: 1)
            guard tokenRange.location != NSNotFound else {
                continue
            }

            let token = nsContent.substring(with: tokenRange).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else {
                continue
            }

            let normalizedToken = token.uppercased()
            if unique.insert(normalizedToken).inserted {
                ordered.append(normalizedToken)
            }
        }
        return ordered
    }

    func mapAgentStorageError(_ error: Error) -> AgentStorageError {
        guard let storeError = error as? AgentCatalogFileStore.StoreError else {
            return .invalidPayload
        }

        switch storeError {
        case .invalidID:
            return .invalidID
        case .invalidPayload, .invalidModel, .storageFailure:
            return .invalidPayload
        case .alreadyExists:
            return .alreadyExists
        case .notFound:
            return .notFound
        }
    }

    func mapAgentConfigError(_ error: Error) -> AgentConfigError {
        if let lengthError = error as? AgentDocumentLengthError,
           case .exceeded(let resource, let limit) = lengthError {
            return .documentLengthExceeded(resource: resource, limit: limit)
        }

        guard let storeError = error as? AgentCatalogFileStore.StoreError else {
            return .storageFailure
        }

        switch storeError {
        case .invalidID:
            return .invalidAgentID
        case .invalidPayload:
            return .invalidPayload
        case .invalidModel:
            return .invalidModel
        case .notFound:
            return .agentNotFound
        case .alreadyExists, .storageFailure:
            return .storageFailure
        }
    }

    func mapAgentToolsError(_ error: Error) -> AgentToolsError {
        guard let storeError = error as? AgentToolsFileStore.StoreError else {
            return .storageFailure
        }

        switch storeError {
        case .invalidAgentID:
            return .invalidAgentID
        case .invalidPayload:
            return .invalidPayload
        case .agentNotFound:
            return .agentNotFound
        case .storageFailure:
            return .storageFailure
        }
    }

    func mapActorBoardError(_ error: Error) -> ActorBoardError {
        if let actorBoardError = error as? ActorBoardError {
            return actorBoardError
        }

        guard let storeError = error as? ActorBoardFileStore.StoreError else {
            return .storageFailure
        }

        switch storeError {
        case .invalidPayload:
            return .invalidPayload
        case .actorNotFound:
            return .actorNotFound
        case .storageFailure:
            return .storageFailure
        }
    }

    func updateActorBoardSnapshot(
        nodes: [ActorNode],
        links: [ActorLink],
        teams: [ActorTeam],
        agents: [AgentSummary]
    ) throws -> ActorBoardSnapshot {
        do {
            return try actorBoardStore.saveBoard(
                ActorBoardUpdateRequest(nodes: nodes, links: links, teams: teams),
                agents: agents
            )
        } catch {
            throw mapActorBoardError(error)
        }
    }

    func isProtectedSystemActorID(_ id: String) -> Bool {
        id == "human:admin" || id.hasPrefix("agent:")
    }

    func normalizedActorEntityID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:/")
        if trimmed.rangeOfCharacter(from: allowed.inverted) != nil {
            return nil
        }

        guard trimmed.count <= 180 else {
            return nil
        }

        return trimmed
    }

    func normalizedAgentID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        if trimmed.rangeOfCharacter(from: allowed.inverted) != nil {
            return nil
        }

        guard trimmed.count <= 120 else {
            return nil
        }

        return trimmed
    }

    func normalizedSessionID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        if trimmed.rangeOfCharacter(from: allowed.inverted) != nil {
            return nil
        }

        guard trimmed.count <= 160 else {
            return nil
        }

        return trimmed
    }

}

private extension JSONValue {
    var objectValue: [String: JSONValue] {
        if case .object(let object) = self {
            return object
        }
        return [:]
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    var stringArrayValue: [String]? {
        guard case .array(let values) = self else {
            return nil
        }
        return values.compactMap { value in
            if case .string(let stringValue) = value {
                return stringValue
            }
            return nil
        }
    }
}


// MARK: - ProjectToolService conformance

extension CoreService: ProjectToolService {
    func findProjectForChannel(channelId: String, topicId: String?) async -> ProjectRecord? {
        await projectForChannel(channelId: channelId, topicId: topicId)
    }

    func createTask(projectID: String, request: ProjectTaskCreateRequest) async throws -> ProjectRecord {
        try await createProjectTask(projectID: projectID, request: request)
    }

    func updateTask(projectID: String, taskID: String, request: ProjectTaskUpdateRequest) async throws -> ProjectRecord {
        try await updateProjectTask(projectID: projectID, taskID: taskID, request: request)
    }

    func cancelTaskWithReason(projectID: String, taskID: String, reason: String?) async throws -> ProjectRecord {
        try await cancelProjectTask(projectID: projectID, taskID: taskID, reason: reason)
    }

    func getTask(reference: String) async throws -> AgentTaskRecord {
        try await getProjectTask(taskReference: reference)
    }

    func deliverMessage(channelId: String, content: String) async {
        await deliverToChannelPlugin(channelId: channelId, content: content)
    }

    func actorBoard() async throws -> ActorBoardSnapshot {
        try getActorBoard()
    }

    func listAllProjects() async -> [ProjectRecord] {
        await listProjects()
    }
}

extension CoreService: RuntimeConfigToolService {
    func runtimeConfig() async -> CoreConfig {
        currentConfig
    }

    func updateRuntimeConfig(_ config: CoreConfig) async throws -> CoreConfig {
        try await updateConfig(config)
    }
}

extension CoreService: SkillsToolService {}

