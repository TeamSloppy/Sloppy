import Foundation
import Protocols

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol SloppyTUIBackend: Sendable {
    var isRemote: Bool { get }
    var displayName: String { get }

    func waitForStartup() async
    func shutdown() async
    func shutdownChannelPlugins() async
    func listChannelPlugins() async -> [ChannelPluginRecord]
    func getConfig() async -> CoreConfig
    func updateConfig(_ config: CoreConfig) async throws -> CoreConfig
    func listProjects() async throws -> [ProjectRecord]
    func getProject(id: String) async throws -> ProjectRecord
    func getActorBoard() async throws -> ActorBoardSnapshot
    func resolveOrCreateProjectForCurrentDirectory(_ cwd: String) async throws -> ProjectRecord
    func resolveProjectWorkspaceRoot(projectID: String) async throws -> URL
    func listAgents(includeSystem: Bool) async throws -> [AgentSummary]
    func createAgent(_ request: AgentCreateRequest) async throws -> AgentSummary
    func getAgentConfig(agentID: String) async throws -> AgentConfigDetail
    func updateAgentConfig(agentID: String, request: AgentConfigUpdateRequest) async throws -> AgentConfigDetail
    func buildAgentChatSlashCommands(agentID: String) async throws -> AgentChatSlashCommandsResponse
    func listAgentSkills(agentID: String) async throws -> AgentSkillsResponse
    func listAgentSessions(agentID: String, projectID: String?, limit: Int?, offset: Int?) async throws -> [AgentSessionSummary]
    func createAgentSession(agentID: String, request: AgentSessionCreateRequest) async throws -> AgentSessionSummary
    func getAgentSession(agentID: String, sessionID: String) async throws -> AgentSessionDetail
    func deleteAgentSession(agentID: String, sessionID: String) async throws
    func postAgentSessionMessage(agentID: String, sessionID: String, request: AgentSessionPostMessageRequest) async throws -> AgentSessionMessageResponse
    func addAgentSessionDirectory(agentID: String, sessionID: String, request: AgentSessionDirectoryRequest) async throws -> AgentSessionDirectoryResponse
    func controlAgentSession(agentID: String, sessionID: String, request: AgentSessionControlRequest) async throws -> AgentSessionMessageResponse
    func answerAgentPlanInput(agentID: String, sessionID: String, requestID: String, payload: PlanInputAnswerRequest) async throws -> AgentSessionMessageResponse
    func streamAgentSessionEvents(agentID: String, sessionID: String) async throws -> AsyncStream<AgentSessionStreamUpdate>
    func streamProjectWorkingTreeChanges(projectID: String) async throws -> AsyncStream<ProjectWorkingTreeChangeBatch>
    func projectWorkingTreeSourceControl(projectID: String) async throws -> ProjectWorkingTreeSourceControlResponse
    func searchProjectFiles(projectID: String, query: String, limit: Int) async throws -> [ProjectFileSearchEntry]
    func readProjectFile(projectID: String, path: String) async throws -> ProjectFileContentResponse
    func listMCPServerStatuses() async -> [MCPServerStatus]
    func getAgentTokenUsage(agentID: String) async throws -> AgentTokenUsageResponse
    func listTokenUsage(channelId: String?, taskId: String?, from: Date?, to: Date?) async -> TokenUsageResponse
    func hasLiveAgentRuntimeSession(agentID: String, sessionID: String) async -> Bool
    func requestAgentMemoryCheckpoint(agentID: String, sessionID: String, reason: String?) async throws -> AgentMemoryCheckpointResponse
    func probeProvider(request: ProviderProbeRequest) async -> ProviderProbeResponse
    func startOpenAIDeviceCode() async throws -> OpenAIDeviceCodeStartResponse
    func pollOpenAIDeviceCode(request: OpenAIDeviceCodePollRequest) async throws -> OpenAIDeviceCodePollResponse
    func startAnthropicOAuth(request: AnthropicOAuthStartRequest) async throws -> AnthropicOAuthStartResponse
    func completeAnthropicOAuth(request: AnthropicOAuthCompleteRequest) async throws -> AnthropicOAuthCompleteResponse
}

extension SloppyTUIBackend {
    func listAgentSessions(agentID: String) async throws -> [AgentSessionSummary] {
        try await listAgentSessions(agentID: agentID, projectID: nil, limit: nil, offset: nil)
    }

    func listAgentSessions(agentID: String, projectID: String) async throws -> [AgentSessionSummary] {
        try await listAgentSessions(agentID: agentID, projectID: projectID, limit: nil, offset: nil)
    }

    func listAgentSessions(agentID: String, limit: Int) async throws -> [AgentSessionSummary] {
        try await listAgentSessions(agentID: agentID, projectID: nil, limit: limit, offset: nil)
    }

    func listAgentSessions(agentID: String, projectID: String, limit: Int) async throws -> [AgentSessionSummary] {
        try await listAgentSessions(agentID: agentID, projectID: projectID, limit: limit, offset: nil)
    }

    func listTokenUsage(channelId: String?) async -> TokenUsageResponse {
        await listTokenUsage(channelId: channelId, taskId: nil, from: nil, to: nil)
    }
}

struct LocalSloppyTUIBackend: SloppyTUIBackend {
    let service: CoreService

    var isRemote: Bool { false }
    var displayName: String { "Local" }

    func waitForStartup() async { await service.waitForStartup() }
    func shutdown() async { await service.shutdownChannelPlugins() }
    func shutdownChannelPlugins() async { await service.shutdownChannelPlugins() }
    func listChannelPlugins() async -> [ChannelPluginRecord] { await service.listChannelPlugins() }
    func getConfig() async -> CoreConfig { await service.getConfig() }
    func updateConfig(_ config: CoreConfig) async throws -> CoreConfig { try await service.updateConfig(config) }
    func listProjects() async throws -> [ProjectRecord] { await service.listProjects() }
    func getProject(id: String) async throws -> ProjectRecord { try await service.getProject(id: id) }
    func getActorBoard() async throws -> ActorBoardSnapshot { try await service.getActorBoard() }
    func resolveOrCreateProjectForCurrentDirectory(_ cwd: String) async throws -> ProjectRecord {
        try await service.resolveOrCreateProjectForCurrentDirectory(cwd)
    }
    func resolveProjectWorkspaceRoot(projectID: String) async throws -> URL {
        try await service.resolveProjectWorkspaceRoot(projectID: projectID)
    }
    func listAgents(includeSystem: Bool) async throws -> [AgentSummary] {
        try await service.listAgents(includeSystem: includeSystem)
    }
    func createAgent(_ request: AgentCreateRequest) async throws -> AgentSummary {
        try await service.createAgent(request)
    }
    func getAgentConfig(agentID: String) async throws -> AgentConfigDetail {
        try await service.getAgentConfig(agentID: agentID)
    }
    func updateAgentConfig(agentID: String, request: AgentConfigUpdateRequest) async throws -> AgentConfigDetail {
        try await service.updateAgentConfig(agentID: agentID, request: request)
    }
    func buildAgentChatSlashCommands(agentID: String) async throws -> AgentChatSlashCommandsResponse {
        try await service.buildAgentChatSlashCommands(agentID: agentID)
    }
    func listAgentSkills(agentID: String) async throws -> AgentSkillsResponse {
        try await service.listAgentSkills(agentID: agentID)
    }
    func listAgentSessions(agentID: String, projectID: String?, limit: Int?, offset: Int?) async throws -> [AgentSessionSummary] {
        try await service.listAgentSessions(agentID: agentID, projectID: projectID, limit: limit, offset: offset ?? 0)
    }
    func createAgentSession(agentID: String, request: AgentSessionCreateRequest) async throws -> AgentSessionSummary {
        try await service.createAgentSession(agentID: agentID, request: request)
    }
    func getAgentSession(agentID: String, sessionID: String) async throws -> AgentSessionDetail {
        try await service.getAgentSession(agentID: agentID, sessionID: sessionID)
    }
    func deleteAgentSession(agentID: String, sessionID: String) async throws {
        try await service.deleteAgentSession(agentID: agentID, sessionID: sessionID)
    }
    func postAgentSessionMessage(agentID: String, sessionID: String, request: AgentSessionPostMessageRequest) async throws -> AgentSessionMessageResponse {
        try await service.postAgentSessionMessage(agentID: agentID, sessionID: sessionID, request: request)
    }
    func addAgentSessionDirectory(agentID: String, sessionID: String, request: AgentSessionDirectoryRequest) async throws -> AgentSessionDirectoryResponse {
        try await service.addAgentSessionDirectory(agentID: agentID, sessionID: sessionID, request: request)
    }
    func controlAgentSession(agentID: String, sessionID: String, request: AgentSessionControlRequest) async throws -> AgentSessionMessageResponse {
        try await service.controlAgentSession(agentID: agentID, sessionID: sessionID, request: request)
    }
    func answerAgentPlanInput(agentID: String, sessionID: String, requestID: String, payload: PlanInputAnswerRequest) async throws -> AgentSessionMessageResponse {
        try await service.answerAgentPlanInput(agentID: agentID, sessionID: sessionID, requestID: requestID, payload: payload)
    }
    func streamAgentSessionEvents(agentID: String, sessionID: String) async throws -> AsyncStream<AgentSessionStreamUpdate> {
        try await service.streamAgentSessionEvents(agentID: agentID, sessionID: sessionID)
    }
    func streamProjectWorkingTreeChanges(projectID: String) async throws -> AsyncStream<ProjectWorkingTreeChangeBatch> {
        try await service.streamProjectWorkingTreeChanges(projectID: projectID)
    }
    func projectWorkingTreeSourceControl(projectID: String) async throws -> ProjectWorkingTreeSourceControlResponse {
        try await service.projectWorkingTreeSourceControl(projectID: projectID)
    }
    func searchProjectFiles(projectID: String, query: String, limit: Int) async throws -> [ProjectFileSearchEntry] {
        try await service.searchProjectFiles(projectID: projectID, query: query, limit: limit)
    }
    func readProjectFile(projectID: String, path: String) async throws -> ProjectFileContentResponse {
        try await service.readProjectFile(projectID: projectID, path: path)
    }
    func listMCPServerStatuses() async -> [MCPServerStatus] { await service.listMCPServerStatuses() }
    func getAgentTokenUsage(agentID: String) async throws -> AgentTokenUsageResponse {
        try await service.getAgentTokenUsage(agentID: agentID)
    }
    func listTokenUsage(channelId: String?, taskId: String?, from: Date?, to: Date?) async -> TokenUsageResponse {
        await service.listTokenUsage(channelId: channelId, taskId: taskId, from: from, to: to)
    }
    func hasLiveAgentRuntimeSession(agentID: String, sessionID: String) async -> Bool {
        (try? await service.hasLiveAgentRuntimeSession(agentID: agentID, sessionID: sessionID)) ?? false
    }
    func requestAgentMemoryCheckpoint(agentID: String, sessionID: String, reason: String?) async throws -> AgentMemoryCheckpointResponse {
        try await service.requestAgentMemoryCheckpoint(agentID: agentID, sessionID: sessionID, reason: reason)
    }
    func probeProvider(request: ProviderProbeRequest) async -> ProviderProbeResponse {
        await service.probeProvider(request: request)
    }
    func startOpenAIDeviceCode() async throws -> OpenAIDeviceCodeStartResponse {
        try await service.startOpenAIDeviceCode()
    }
    func pollOpenAIDeviceCode(request: OpenAIDeviceCodePollRequest) async throws -> OpenAIDeviceCodePollResponse {
        try await service.pollOpenAIDeviceCode(request: request)
    }
    func startAnthropicOAuth(request: AnthropicOAuthStartRequest) async throws -> AnthropicOAuthStartResponse {
        try await service.startAnthropicOAuth(request: request)
    }
    func completeAnthropicOAuth(request: AnthropicOAuthCompleteRequest) async throws -> AnthropicOAuthCompleteResponse {
        try await service.completeAnthropicOAuth(request: request)
    }
}

enum RemoteSloppyTUIBackendError: Error, LocalizedError {
    case missingProject
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .missingProject:
            return "Select a remote project before using this action."
        case .unsupported(let action):
            return "\(action) is not available for remote Sloppy instances yet."
        }
    }
}

struct RemoteSloppyTUIBackend: SloppyTUIBackend {
    let client: SloppyCLIClient
    let node: CoreConfig.Node
    let projectID: String?
    let environment: [String: String]

    var isRemote: Bool { true }
    var displayName: String { node.displayTitle }

    init(node: CoreConfig.Node, projectID: String? = nil, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.node = node
        self.projectID = projectID
        self.environment = environment
        let token = node.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? environment[node.tokenEnv]?.trimmingCharacters(in: .whitespacesAndNewlines)
            : node.token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.client = SloppyCLIClient(
            baseURL: node.url.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            token: token?.isEmpty == false ? token! : "dev-token",
            verbose: false
        )
    }

    func waitForStartup() async {}
    func shutdown() async {}
    func shutdownChannelPlugins() async {}
    func listChannelPlugins() async -> [ChannelPluginRecord] { [] }
    func getConfig() async -> CoreConfig { (try? await get("/v1/config", as: CoreConfig.self)) ?? .default }
    func updateConfig(_ config: CoreConfig) async throws -> CoreConfig {
        try await put("/v1/config", body: config, as: CoreConfig.self)
    }
    func listProjects() async throws -> [ProjectRecord] { try await get("/v1/projects", as: [ProjectRecord].self) }
    func getProject(id: String) async throws -> ProjectRecord { try await get("/v1/projects/\(Self.escape(id))", as: ProjectRecord.self) }
    func getActorBoard() async throws -> ActorBoardSnapshot { try await get("/v1/actors/board", as: ActorBoardSnapshot.self) }
    func resolveOrCreateProjectForCurrentDirectory(_ cwd: String) async throws -> ProjectRecord {
        guard let projectID else { throw RemoteSloppyTUIBackendError.missingProject }
        return try await getProject(id: projectID)
    }
    func resolveProjectWorkspaceRoot(projectID: String) async throws -> URL {
        URL(fileURLWithPath: "/remote/\(projectID)", isDirectory: true)
    }
    func listAgents(includeSystem: Bool) async throws -> [AgentSummary] {
        try await get("/v1/agents", query: ["includeSystem": includeSystem ? "true" : "false"], as: [AgentSummary].self)
    }
    func createAgent(_ request: AgentCreateRequest) async throws -> AgentSummary {
        try await post("/v1/agents", body: request, as: AgentSummary.self)
    }
    func getAgentConfig(agentID: String) async throws -> AgentConfigDetail {
        try await get("/v1/agents/\(Self.escape(agentID))/config", as: AgentConfigDetail.self)
    }
    func updateAgentConfig(agentID: String, request: AgentConfigUpdateRequest) async throws -> AgentConfigDetail {
        try await put("/v1/agents/\(Self.escape(agentID))/config", body: request, as: AgentConfigDetail.self)
    }
    func buildAgentChatSlashCommands(agentID: String) async throws -> AgentChatSlashCommandsResponse {
        try await get("/v1/agents/\(Self.escape(agentID))/chat-slash-commands", as: AgentChatSlashCommandsResponse.self)
    }
    func listAgentSkills(agentID: String) async throws -> AgentSkillsResponse {
        try await get("/v1/agents/\(Self.escape(agentID))/skills", as: AgentSkillsResponse.self)
    }
    func listAgentSessions(agentID: String, projectID: String?, limit: Int?, offset: Int?) async throws -> [AgentSessionSummary] {
        var query: [String: String] = [:]
        if let projectID { query["projectId"] = projectID }
        if let limit { query["limit"] = String(limit) }
        if let offset { query["offset"] = String(offset) }
        return try await get("/v1/agents/\(Self.escape(agentID))/sessions", query: query, as: [AgentSessionSummary].self)
    }
    func createAgentSession(agentID: String, request: AgentSessionCreateRequest) async throws -> AgentSessionSummary {
        try await post("/v1/agents/\(Self.escape(agentID))/sessions", body: request, as: AgentSessionSummary.self)
    }
    func getAgentSession(agentID: String, sessionID: String) async throws -> AgentSessionDetail {
        try await get("/v1/agents/\(Self.escape(agentID))/sessions/\(Self.escape(sessionID))", as: AgentSessionDetail.self)
    }
    func deleteAgentSession(agentID: String, sessionID: String) async throws {
        _ = try await client.delete("/v1/agents/\(Self.escape(agentID))/sessions/\(Self.escape(sessionID))")
    }
    func postAgentSessionMessage(agentID: String, sessionID: String, request: AgentSessionPostMessageRequest) async throws -> AgentSessionMessageResponse {
        try await post("/v1/agents/\(Self.escape(agentID))/sessions/\(Self.escape(sessionID))/messages", body: request, as: AgentSessionMessageResponse.self)
    }
    func addAgentSessionDirectory(agentID: String, sessionID: String, request: AgentSessionDirectoryRequest) async throws -> AgentSessionDirectoryResponse {
        try await post("/v1/agents/\(Self.escape(agentID))/sessions/\(Self.escape(sessionID))/directories", body: request, as: AgentSessionDirectoryResponse.self)
    }
    func controlAgentSession(agentID: String, sessionID: String, request: AgentSessionControlRequest) async throws -> AgentSessionMessageResponse {
        try await post("/v1/agents/\(Self.escape(agentID))/sessions/\(Self.escape(sessionID))/control", body: request, as: AgentSessionMessageResponse.self)
    }
    func answerAgentPlanInput(agentID: String, sessionID: String, requestID: String, payload: PlanInputAnswerRequest) async throws -> AgentSessionMessageResponse {
        try await post("/v1/agents/\(Self.escape(agentID))/sessions/\(Self.escape(sessionID))/input-requests/\(Self.escape(requestID))/answer", body: payload, as: AgentSessionMessageResponse.self)
    }
    func streamAgentSessionEvents(agentID: String, sessionID: String) async throws -> AsyncStream<AgentSessionStreamUpdate> {
        stream(path: "/v1/agents/\(Self.escape(agentID))/sessions/\(Self.escape(sessionID))/stream", as: AgentSessionStreamUpdate.self)
    }
    func streamProjectWorkingTreeChanges(projectID: String) async throws -> AsyncStream<ProjectWorkingTreeChangeBatch> {
        stream(path: "/v1/projects/\(Self.escape(projectID))/changes/stream", as: ProjectWorkingTreeChangeBatch.self)
    }
    func projectWorkingTreeSourceControl(projectID: String) async throws -> ProjectWorkingTreeSourceControlResponse {
        try await get("/v1/projects/\(Self.escape(projectID))/source-control/working-tree", as: ProjectWorkingTreeSourceControlResponse.self)
    }
    func searchProjectFiles(projectID: String, query: String, limit: Int) async throws -> [ProjectFileSearchEntry] {
        try await get("/v1/projects/\(Self.escape(projectID))/files/search", query: ["q": query, "limit": String(limit)], as: [ProjectFileSearchEntry].self)
    }
    func readProjectFile(projectID: String, path: String) async throws -> ProjectFileContentResponse {
        try await get("/v1/projects/\(Self.escape(projectID))/files/content", query: ["path": path], as: ProjectFileContentResponse.self)
    }
    func listMCPServerStatuses() async -> [MCPServerStatus] { [] }
    func getAgentTokenUsage(agentID: String) async throws -> AgentTokenUsageResponse {
        try await get("/v1/agents/\(Self.escape(agentID))/token-usage", as: AgentTokenUsageResponse.self)
    }
    func listTokenUsage(channelId: String?, taskId: String?, from: Date?, to: Date?) async -> TokenUsageResponse {
        var query: [String: String] = [:]
        if let channelId { query["channelId"] = channelId }
        if let taskId { query["taskId"] = taskId }
        return (try? await get("/v1/token-usage", query: query, as: TokenUsageResponse.self)) ?? TokenUsageResponse(items: [])
    }
    func hasLiveAgentRuntimeSession(agentID: String, sessionID: String) async -> Bool { false }
    func requestAgentMemoryCheckpoint(agentID: String, sessionID: String, reason: String?) async throws -> AgentMemoryCheckpointResponse {
        try await post("/v1/agents/\(Self.escape(agentID))/sessions/\(Self.escape(sessionID))/checkpoint", body: AgentMemoryCheckpointRequest(reason: reason), as: AgentMemoryCheckpointResponse.self)
    }
    func probeProvider(request: ProviderProbeRequest) async -> ProviderProbeResponse {
        (try? await post("/v1/providers/probe", body: request, as: ProviderProbeResponse.self))
            ?? ProviderProbeResponse(providerId: request.providerId, ok: false, usedEnvironmentKey: false, message: "Remote probe failed", models: [])
    }
    func startOpenAIDeviceCode() async throws -> OpenAIDeviceCodeStartResponse {
        try await postEmpty("/v1/providers/openai/oauth/device-code/start", as: OpenAIDeviceCodeStartResponse.self)
    }
    func pollOpenAIDeviceCode(request: OpenAIDeviceCodePollRequest) async throws -> OpenAIDeviceCodePollResponse {
        try await post("/v1/providers/openai/oauth/device-code/poll", body: request, as: OpenAIDeviceCodePollResponse.self)
    }
    func startAnthropicOAuth(request: AnthropicOAuthStartRequest) async throws -> AnthropicOAuthStartResponse {
        try await post("/v1/providers/anthropic/oauth/start", body: request, as: AnthropicOAuthStartResponse.self)
    }
    func completeAnthropicOAuth(request: AnthropicOAuthCompleteRequest) async throws -> AnthropicOAuthCompleteResponse {
        try await post("/v1/providers/anthropic/oauth/complete", body: request, as: AnthropicOAuthCompleteResponse.self)
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:], as type: T.Type) async throws -> T {
        try decode(try await client.get(path, query: query), as: type)
    }

    private func post<T: Decodable, Body: Encodable>(_ path: String, body: Body, as type: T.Type) async throws -> T {
        try decode(try await client.post(path, body: try client.encode(body)), as: type)
    }

    private func postEmpty<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        try decode(try await client.post(path), as: type)
    }

    private func put<T: Decodable, Body: Encodable>(_ path: String, body: Body, as type: T.Type) async throws -> T {
        try decode(try await client.put(path, body: try client.encode(body)), as: type)
    }

    private func decode<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    private func stream<T: Decodable & Sendable>(path: String, as type: T.Type) -> AsyncStream<T> {
        AsyncStream(bufferingPolicy: .bufferingNewest(128)) { continuation in
            let task = Task {
                guard let url = URL(string: client.baseURL + path) else {
                    continuation.finish()
                    return
                }
                var request = URLRequest(url: url, timeoutInterval: 60 * 60)
                request.setValue("Bearer \(client.token)", forHTTPHeaderField: "Authorization")
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode ?? 500 < 400 else {
                        continuation.finish()
                        return
                    }
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst("data: ".count))
                        guard let data = payload.data(using: .utf8),
                              let value = try? decoder.decode(type, from: data)
                        else { continue }
                        continuation.yield(value)
                    }
                } catch {
                    continuation.finish()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func escape(_ raw: String) -> String {
        raw.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? raw
    }
}
