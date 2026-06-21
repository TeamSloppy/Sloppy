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

    public init(
        baseURL: URL = URL(string: "http://localhost:25101")!,
        session: URLSession = .shared,
        logger: Logger = Logger(label: "sloppy.api-client")
    ) {
        self.baseURL = baseURL
        let http = BackendHTTPClient(baseURL: baseURL, session: session, logger: logger)
        self.http = http
        self.projects = ProjectService(http: http)
        self.agents = AgentService(http: http)
        self.sessions = SessionService(http: http)
        self.mesh = MeshService(http: http)
        self.config = ConfigService(http: http)
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
