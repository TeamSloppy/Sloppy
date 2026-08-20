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
    private let config: ConfigService
    private let auth: AuthService
    private let taskSync: TaskSyncService

    public init(
        baseURL: URL = URL(string: "http://localhost:25101")!,
        authToken: String = "",
        session: URLSession = .shared,
        logger: Logger = Logger(label: "sloppy.api-client")
    ) {
        self.baseURL = baseURL
        let http = BackendHTTPClient(baseURL: baseURL, authToken: authToken, session: session, logger: logger)
        self.http = http
        self.projects = ProjectService(http: http)
        self.agents = AgentService(http: http)
        self.sessions = SessionService(http: http)
        self.config = ConfigService(http: http)
        self.auth = AuthService(http: http)
        self.taskSync = TaskSyncService(http: http)
    }

    public func setAuthToken(_ token: String) async {
        await http.setAuthToken(token)
    }

    public func fetchAuthChallenge() async throws -> AuthChallenge {
        try await auth.fetchAuthChallenge()
    }

    public func loginIdentityUser(login: String, password: String) async throws -> AuthSession {
        let session = try await auth.loginIdentityUser(login: login, password: password)
        await setAuthToken(session.accessToken)
        return session
    }

    public func fetchProjects() async throws -> [APIProjectRecord] {
        try await projects.fetchProjects()
    }

    public func fetchProject(id: String) async throws -> APIProjectRecord {
        try await projects.fetchProject(id: id)
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

    // MARK: - Task sync

    public func fetchTaskSyncProviders() async throws -> [APITaskSyncProviderDescriptor] {
        try await taskSync.providers()
    }

    public func fetchTaskSyncSettings(projectId: String) async throws -> APIProjectTaskSyncSettings {
        try await taskSync.settings(projectId: projectId)
    }

    public func fetchTaskSyncTokenStatus(projectId: String, providerId: String = "startrek") async throws -> APIProjectTaskSyncTokenStatus {
        try await taskSync.tokenStatus(projectId: projectId, providerId: providerId)
    }

    public func setTaskSyncToken(projectId: String, providerId: String = "startrek", token: String) async throws -> APIProjectTaskSyncTokenStatus {
        try await taskSync.setToken(projectId: projectId, providerId: providerId, token: token)
    }

    public func discoverTaskSync(projectId: String, request: APIProjectTaskSyncDiscoverRequest) async throws -> APIProjectTaskSyncDiscoveryResponse {
        try await taskSync.discover(projectId: projectId, request: request)
    }

    public func linkTaskSync(projectId: String, request: APIProjectTaskSyncLinkRequest) async throws -> APIProjectTaskSyncResponse {
        try await taskSync.link(projectId: projectId, request: request)
    }

    public func unlinkTaskSync(projectId: String) async throws -> APIProjectTaskSyncResponse {
        try await taskSync.unlink(projectId: projectId)
    }

    public func syncTasksNow(projectId: String) async throws -> APIProjectTaskSyncNowResponse {
        try await taskSync.syncNow(projectId: projectId)
    }

    public func fetchTaskComments(projectId: String, taskId: String) async throws -> [APITaskComment] {
        try await taskSync.comments(projectId: projectId, taskId: taskId)
    }

    public func addTaskComment(projectId: String, taskId: String, content: String) async throws -> APITaskComment {
        try await taskSync.addComment(projectId: projectId, taskId: taskId, content: content)
    }

    // MARK: - Session REST API

    public func fetchAgentSessions(agentId: String, projectId: String? = nil) async throws -> [ChatSessionSummary] {
        try await sessions.fetchAgentSessions(agentId: agentId, projectId: projectId)
    }

    public func fetchAgentSession(agentId: String, sessionId: String) async throws -> ChatSessionDetail {
        try await sessions.fetchAgentSession(agentId: agentId, sessionId: sessionId)
    }

    public func fetchAgentSessionData(agentId: String, sessionId: String) async throws -> Data {
        try await sessions.fetchAgentSessionData(agentId: agentId, sessionId: sessionId)
    }

    public func createAgentSession(agentId: String, title: String? = nil, projectId: String? = nil) async throws -> ChatSessionSummary {
        try await sessions.createAgentSession(agentId: agentId, title: title, projectId: projectId)
    }

    public func postSessionMessage(
        agentId: String,
        sessionId: String,
        content: String,
        userId: String = "user"
    ) async throws -> ChatSessionSummary {
        try await sessions.postSessionMessage(agentId: agentId, sessionId: sessionId, content: content, userId: userId)
    }

    public func deleteAgentSession(agentId: String, sessionId: String) async throws {
        try await sessions.deleteAgentSession(agentId: agentId, sessionId: sessionId)
    }

    // MARK: - Config API

    public func fetchConfig() async throws -> SloppyConfig {
        try await config.fetchConfig()
    }

    public func updateConfig(_ config: SloppyConfig) async throws -> SloppyConfig {
        try await self.config.updateConfig(config)
    }
}
