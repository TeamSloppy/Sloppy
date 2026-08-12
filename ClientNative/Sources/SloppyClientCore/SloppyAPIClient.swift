import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging

public actor SloppyAPIClient {
    public nonisolated let baseURL: URL

    private let http: BackendHTTPClient
    private let projects: ProjectService
    private let agents: AgentService
    private let sessions: SessionService
    private let mesh: MeshService
    private let config: ConfigService
    private let auth: AuthService
    private let voice: VoiceService
    private let logger: Logger

    public init(
        baseURL: URL = URL(string: "http://localhost:25101")!,
        authToken: String = "",
        session: URLSession = .shared,
        authSessionStore: AuthSessionStore = .shared,
        logger: Logger = Logger(label: "sloppy.api-client")
    ) {
        self.baseURL = baseURL
        let http = BackendHTTPClient(
            baseURL: baseURL,
            authToken: authToken,
            session: session,
            authSessionStore: authSessionStore,
            logger: logger
        )
        self.http = http
        self.projects = ProjectService(http: http)
        self.agents = AgentService(http: http)
        self.sessions = SessionService(http: http)
        self.mesh = MeshService(http: http)
        self.config = ConfigService(http: http)
        self.auth = AuthService(http: http)
        self.voice = VoiceService(http: http)
        self.logger = logger
    }

    public func setAuthToken(_ token: String) async {
        await http.setAuthToken(token)
    }

    public func fetchAuthChallenge() async throws -> AuthChallenge {
        try await auth.fetchAuthChallenge()
    }

    /// Resolves the authentication UI required for a new connection.
    ///
    /// Dashboard-token deployments protect most API routes and some older Core
    /// versions also protect `/v1/auth/challenge` itself. The dashboard auth
    /// status endpoint remains public, so a 401 challenge response means the
    /// client must ask for the legacy dashboard access token.
    public func fetchConnectionAuthChallenge() async throws -> AuthChallenge {
        do {
            return try await auth.fetchAuthChallenge()
        } catch let error as APIError where error.statusCode == 401 {
            let status = try await auth.fetchDashboardAuthStatus()
            guard status.enabled else { throw error }
            logger.info(
                "auth.challenge.legacy-token-fallback",
                metadata: ["server": .string(Self.serverDescription(baseURL))]
            )
            return .legacyToken
        }
    }

    public func loginIdentityUser(login: String, password: String) async throws -> AuthSession {
        let session = try await auth.loginIdentityUser(login: login, password: password)
        await http.installAuthSession(session)
        return session
    }

    public func fetchCurrentAuthUser() async throws -> AuthUserProfile {
        try await auth.fetchCurrentUser()
    }

    public func fetchDashboardAuthStatus() async throws -> DashboardAuthStatus {
        try await auth.fetchDashboardAuthStatus()
    }

    public func validateCurrentAuthToken() async throws {
        try await auth.validateCurrentToken()
    }

    public func installStaticAuthToken(_ token: String) async {
        await http.installStaticAuthToken(token)
    }

    public func hasStoredAuthSession() async -> Bool {
        await http.hasStoredAuthSession()
    }

    public func currentAccessToken() async -> String? {
        await http.currentAccessToken()
    }

    public func logout() async {
        await http.clearAuthSession()
    }

    private nonisolated static func serverDescription(_ url: URL) -> String {
        guard let host = url.host else { return "unknown-server" }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }

    public func fetchProjects() async throws -> [APIProjectRecord] {
        try await projects.fetchProjects()
    }

    public func fetchProject(id: String) async throws -> APIProjectRecord {
        try await projects.fetchProject(id: id)
    }

    public func fetchCanvasWorkspaces(projectId: String? = nil) async throws -> [CanvasWorkspaceSummary] {
        var path = "/v1/workspaces"
        if let projectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !projectId.isEmpty {
            path += "?projectId=\(BackendHTTPClient.encodeQueryValue(projectId))"
        }
        let response: CanvasWorkspaceListResponse = try await http.get(path)
        return response.workspaces
    }

    public func createCanvasWorkspace(
        title: String,
        description: String? = nil,
        projectId: String? = nil,
        templateId: String? = nil
    ) async throws -> CanvasWorkspaceSummary {
        let request = CanvasWorkspaceCreateRequest(
            title: title,
            description: description,
            projectId: projectId,
            templateId: templateId
        )
        return try await http.post("/v1/workspaces", body: request)
    }

    public func fetchCanvasWorkspaceDocument(workspaceId: String) async throws -> CanvasWorkspaceDocument {
        let response: CanvasWorkspaceDocumentResponse = try await http.get(
            "/v1/workspaces/\(BackendHTTPClient.encodePathSegment(workspaceId))/document"
        )
        return response.document
    }

    public func applyCanvasWorkspaceTransaction(
        workspaceId: String,
        request: CanvasWorkspaceTransactionRequest
    ) async throws -> CanvasWorkspaceCommittedTransaction {
        try await http.post(
            "/v1/workspaces/\(BackendHTTPClient.encodePathSegment(workspaceId))/transactions",
            body: request
        )
    }

    public func fetchCanvasWidgetArtifact(id: String) async throws -> CanvasWidgetArtifact {
        try await http.get("/v1/artifacts/\(BackendHTTPClient.encodePathSegment(id))/widget")
    }

    public func createProject(_ request: APIProjectCreateRequest) async throws -> APIProjectRecord {
        try await projects.createProject(request)
    }

    public func updateProject(id: String, request: APIProjectUpdateRequest) async throws -> APIProjectRecord {
        try await projects.updateProject(id: id, request: request)
    }

    public func createProjectTask(
        projectId: String,
        request: APIProjectTaskCreateRequest
    ) async throws -> APIProjectRecord {
        try await projects.createTask(projectId: projectId, request: request)
    }

    public func fetchTaskComments(projectId: String, taskId: String) async throws -> [TaskComment] {
        try await projects.fetchTaskComments(projectId: projectId, taskId: taskId)
    }

    public func fetchProjectFiles(projectId: String, path: String = "") async throws -> [ProjectFileEntry] {
        try await projects.fetchProjectFiles(projectId: projectId, path: path)
    }

    public func fetchProjectFileContent(projectId: String, path: String) async throws -> ProjectFileContentResponse {
        try await projects.fetchProjectFileContent(projectId: projectId, path: path)
    }

    public func fetchAgents() async throws -> [APIAgentRecord] {
        try await agents.fetchAgents()
    }

    public func fetchAgent(id: String) async throws -> APIAgentRecord {
        try await agents.fetchAgent(id: id)
    }

    public func fetchAgentTasks(agentId: String) async throws -> [APIAgentTaskRecord] {
        try await agents.fetchAgentTasks(agentId: agentId)
    }

    public func fetchChatSlashCommands(agentId: String) async throws -> AgentChatSlashCommandsResponse {
        try await agents.fetchChatSlashCommands(agentId: agentId)
    }

    public func fetchScheduledTasks(agentId: String) async throws -> [ScheduledTask] {
        let agent = BackendHTTPClient.encodePathSegment(agentId)
        return try await http.get("/v1/agents/\(agent)/cron")
    }

    public func createScheduledTask(agentId: String, request: ScheduledTaskCreateRequest) async throws -> ScheduledTask {
        let agent = BackendHTTPClient.encodePathSegment(agentId)
        return try await http.post("/v1/agents/\(agent)/cron", body: request)
    }

    public func updateScheduledTask(agentId: String, taskId: String, request: ScheduledTaskUpdateRequest) async throws -> ScheduledTask {
        let agent = BackendHTTPClient.encodePathSegment(agentId)
        let task = BackendHTTPClient.encodePathSegment(taskId)
        return try await http.put("/v1/agents/\(agent)/cron/\(task)", body: request)
    }

    public func deleteScheduledTask(agentId: String, taskId: String) async throws {
        let agent = BackendHTTPClient.encodePathSegment(agentId)
        let task = BackendHTTPClient.encodePathSegment(taskId)
        try await http.delete("/v1/agents/\(agent)/cron/\(task)")
    }

    public func fetchOverviewData() async throws -> OverviewData {
        async let projectsReq = fetchProjects()
        async let agentsReq = fetchAgents()

        let projects = (try? await projectsReq) ?? []
        let agents = (try? await agentsReq) ?? []

        let summaries = projects.map { $0.toSummary() }
        let agentOverviews = agents.map { $0.toOverview() }

        let allTasks = projects.flatMap { $0.tasks ?? [] }
        let active = allTasks.filter { ["in_progress", "ready", "needs_review"].contains($0.status) }.count
        let completed = allTasks.filter { $0.status == "done" }.count

        return OverviewData(
            projects: summaries,
            agents: agentOverviews,
            activeTasks: active,
            completedTasks: completed
        )
    }

    public func resolveToolApproval(id: String, approved: Bool) async throws {
        struct DecisionPayload: Encodable {
            var decidedBy: String?
            var scope: String
        }
        struct DecisionResponse: Decodable { var id: String }

        let approvalID = BackendHTTPClient.encodePathSegment(id)
        let action = approved ? "approve" : "reject"
        let _: DecisionResponse = try await http.post(
            "/v1/tool-approvals/\(approvalID)/\(action)",
            body: DecisionPayload(decidedBy: "SloppyClient", scope: "once")
        )
    }

    // MARK: - Session REST API

    public func fetchAgentSessions(
        agentId: String,
        projectId: String? = nil,
        limit: Int? = nil
    ) async throws -> [ChatSessionSummary] {
        try await sessions.fetchAgentSessions(agentId: agentId, projectId: projectId, limit: limit)
    }

    public func fetchAgentSession(agentId: String, sessionId: String) async throws -> ChatSessionDetail {
        try await sessions.fetchAgentSession(agentId: agentId, sessionId: sessionId)
    }

    public func fetchAgentSessionData(agentId: String, sessionId: String) async throws -> Data {
        try await sessions.fetchAgentSessionData(agentId: agentId, sessionId: sessionId)
    }

    public func answerSessionInputRequest(
        agentId: String,
        sessionId: String,
        requestId: String,
        request: ChatPlanInputAnswerRequest
    ) async throws -> ChatSessionSummary {
        try await sessions.answerInputRequest(
            agentId: agentId,
            sessionId: sessionId,
            requestId: requestId,
            request: request
        )
    }

    public func createAgentSession(
        agentId: String,
        title: String? = nil,
        projectId: String? = nil,
        workspaceId: String? = nil
    ) async throws -> ChatSessionSummary {
        try await sessions.createAgentSession(
            agentId: agentId,
            title: title,
            projectId: projectId,
            workspaceId: workspaceId
        )
    }

    public func fetchMeshNodes() async throws -> [MeshNodeRecord] {
        try await mesh.listNodes()
    }

    public func acceptMeshInvite(
        token: String,
        endpoint: String? = nil,
        allowRemote: Bool = true
    ) async throws -> MeshNodeRecord {
        try await mesh.acceptInvite(
            MeshInviteAcceptRequest(token: token, endpoint: endpoint, allowRemote: allowRemote)
        )
    }

    public func createMeshTask(
        projectId: String,
        title: String,
        assignedNodeId: String
    ) async throws -> MeshTaskRecord {
        try await mesh.createTask(
            MeshTaskCreateRequest(projectId: projectId, title: title, assignedNodeId: assignedNodeId)
        )
    }

    public func fetchMeshTasks(projectId: String? = nil) async throws -> [MeshTaskRecord] {
        try await mesh.listTasks(projectId: projectId)
    }

    public func postSessionMessage(
        agentId: String,
        sessionId: String,
        content: String,
        userId: String = "user",
        attachments: [ChatAttachmentUpload] = [],
        selectedModel: String? = nil,
        reasoningEffort: String? = nil
    ) async throws -> ChatSessionSummary {
        try await sessions.postSessionMessage(
            agentId: agentId,
            sessionId: sessionId,
            content: content,
            userId: userId,
            attachments: attachments,
            selectedModel: selectedModel,
            reasoningEffort: reasoningEffort
        )
    }

    public func deleteAgentSession(agentId: String, sessionId: String) async throws {
        try await sessions.deleteAgentSession(agentId: agentId, sessionId: sessionId)
    }

    public func interruptAgentSession(
        agentId: String,
        sessionId: String,
        includeSubsessions: Bool = true,
        requestedBy: String = "apple-client",
        reason: String? = nil
    ) async throws {
        try await sessions.controlAgentSession(
            agentId: agentId,
            sessionId: sessionId,
            action: includeSubsessions ? .interruptTree : .interrupt,
            requestedBy: requestedBy,
            reason: reason
        )
    }

    // MARK: - Config API

    public func fetchConfig() async throws -> SloppyConfig {
        try await config.fetchConfig()
    }

    public func fetchAvailableModels() async throws -> [ChatModelOption] {
        try await config.fetchAvailableModels()
    }

    public func updateConfig(_ config: SloppyConfig) async throws -> SloppyConfig {
        try await self.config.updateConfig(config)
    }

    public func fetchAccessUsers(platform: String? = nil) async throws -> [AccessUser] {
        try await config.fetchAccessUsers(platform: platform)
    }

    public func deleteAccessUser(_ userId: String) async throws {
        try await config.deleteAccessUser(userId)
    }

    public func transcribeVoice(_ request: VoiceTranscriptionRequest) async throws -> VoiceTranscriptionResponse {
        try await voice.transcribe(request)
    }
}
