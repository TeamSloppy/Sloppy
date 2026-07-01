import Foundation

public struct HealthCheckResult: Sendable {
    public let isHealthy: Bool
    public let failureMessage: String?

    public init(isHealthy: Bool, failureMessage: String? = nil) {
        self.isHealthy = isHealthy
        self.failureMessage = failureMessage
    }
}

public struct AccessUser: Codable, Sendable, Identifiable {
    public var id: String
    public var platform: String
    public var platformUserId: String
    public var displayName: String
    public var status: String
    public var createdAt: Date

    public init(
        id: String,
        platform: String,
        platformUserId: String,
        displayName: String,
        status: String,
        createdAt: Date
    ) {
        self.id = id
        self.platform = platform
        self.platformUserId = platformUserId
        self.displayName = displayName
        self.status = status
        self.createdAt = createdAt
    }
}

public actor HealthService {
    private let http: BackendHTTPClient

    public init(http: BackendHTTPClient) {
        self.http = http
    }

    public init(baseURL: URL = URL(string: "http://localhost:25101")!) {
        self.init(http: BackendHTTPClient(baseURL: baseURL))
    }

    public nonisolated var baseURL: URL { http.baseURL }

    public func check(timeout: TimeInterval = 5) async -> HealthCheckResult {
        do {
            _ = try await http.getData("/health", timeout: timeout)
            return HealthCheckResult(isHealthy: true)
        } catch let apiError as APIError {
            switch apiError {
            case .invalidResponse:
                return HealthCheckResult(isHealthy: false, failureMessage: "Invalid HTTP response")
            case let .httpError(statusCode, _):
                return HealthCheckResult(isHealthy: false, failureMessage: "HTTP \(statusCode)")
            case let .decodingFailed(message):
                return HealthCheckResult(isHealthy: false, failureMessage: message)
            }
        } catch {
            let nsError = error as NSError
            return HealthCheckResult(
                isHealthy: false,
                failureMessage: "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
            )
        }
    }

    public func isHealthy(timeout: TimeInterval = 5) async -> Bool {
        await check(timeout: timeout).isHealthy
    }
}

public actor ProjectService {
    private let http: BackendHTTPClient

    public init(http: BackendHTTPClient) {
        self.http = http
    }

    public func fetchProjects() async throws -> [APIProjectRecord] {
        try await http.get("/v1/projects")
    }

    public func fetchProject(id: String) async throws -> APIProjectRecord {
        try await http.get("/v1/projects/\(BackendHTTPClient.encodePathSegment(id))")
    }

    public func fetchProjectFiles(projectId: String, path: String = "") async throws -> [ProjectFileEntry] {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = trimmedPath.isEmpty ? "" : "?path=\(BackendHTTPClient.encodeQueryValue(trimmedPath))"
        return try await http.get(
            "/v1/projects/\(BackendHTTPClient.encodePathSegment(projectId))/files\(query)"
        )
    }

    public func fetchProjectFileContent(projectId: String, path: String) async throws -> ProjectFileContentResponse {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await http.get(
            "/v1/projects/\(BackendHTTPClient.encodePathSegment(projectId))/files/content?path=\(BackendHTTPClient.encodeQueryValue(trimmedPath))"
        )
    }
}

public actor AgentService {
    private let http: BackendHTTPClient

    public init(http: BackendHTTPClient) {
        self.http = http
    }

    public func fetchAgents() async throws -> [APIAgentRecord] {
        try await http.get("/v1/agents")
    }

    public func fetchAgent(id: String) async throws -> APIAgentRecord {
        try await http.get("/v1/agents/\(BackendHTTPClient.encodePathSegment(id))")
    }

    public func fetchAgentTasks(agentId: String) async throws -> [APIAgentTaskRecord] {
        try await http.get("/v1/agents/\(BackendHTTPClient.encodePathSegment(agentId))/tasks")
    }
}

public actor SessionService {
    private let http: BackendHTTPClient

    public init(http: BackendHTTPClient) {
        self.http = http
    }

    public func fetchAgentSessions(agentId: String, projectId: String? = nil) async throws -> [ChatSessionSummary] {
        var path = "/v1/agents/\(BackendHTTPClient.encodePathSegment(agentId))/sessions"
        if let projectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines), !projectId.isEmpty {
            path += "?projectId=\(BackendHTTPClient.encodeQueryValue(projectId))"
        }
        return try await http.get(path)
    }

    public func fetchAgentSession(agentId: String, sessionId: String) async throws -> ChatSessionDetail {
        try await http.get("/v1/agents/\(BackendHTTPClient.encodePathSegment(agentId))/sessions/\(BackendHTTPClient.encodePathSegment(sessionId))")
    }

    public func fetchAgentSessionData(agentId: String, sessionId: String) async throws -> Data {
        try await http.getData("/v1/agents/\(BackendHTTPClient.encodePathSegment(agentId))/sessions/\(BackendHTTPClient.encodePathSegment(sessionId))")
    }

    public func createAgentSession(agentId: String, title: String? = nil, projectId: String? = nil) async throws -> ChatSessionSummary {
        struct Payload: Encodable {
            var title: String?
            var kind: String = "chat"
            var projectId: String?
        }
        let normalizedProjectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await http.post(
            "/v1/agents/\(BackendHTTPClient.encodePathSegment(agentId))/sessions",
            body: Payload(title: title, projectId: normalizedProjectId?.isEmpty == false ? normalizedProjectId : nil)
        )
    }

    public func postSessionMessage(
        agentId: String,
        sessionId: String,
        content: String,
        userId: String = "user"
    ) async throws -> ChatSessionSummary {
        struct Payload: Encodable {
            var userId: String
            var content: String
            var attachments: [String] = []
            var spawnSubSession: Bool = false
        }
        struct Response: Decodable {
            var summary: ChatSessionSummary
        }
        let response: Response = try await http.post(
            "/v1/agents/\(BackendHTTPClient.encodePathSegment(agentId))/sessions/\(BackendHTTPClient.encodePathSegment(sessionId))/messages",
            body: Payload(userId: userId, content: content)
        )
        return response.summary
    }

    public func deleteAgentSession(agentId: String, sessionId: String) async throws {
        try await http.delete("/v1/agents/\(BackendHTTPClient.encodePathSegment(agentId))/sessions/\(BackendHTTPClient.encodePathSegment(sessionId))")
    }
}

public actor MeshService {
    private let http: BackendHTTPClient

    public init(http: BackendHTTPClient) {
        self.http = http
    }

    public func listNodes() async throws -> [MeshNodeRecord] {
        try await http.get("/v1/node/mesh/nodes")
    }

    public func acceptInvite(_ request: MeshInviteAcceptRequest) async throws -> MeshNodeRecord {
        struct Response: Decodable {
            var id: String
            var name: String
            var publicKey: String
            var roles: [String]
            var endpoint: String?
            var status: MeshNodeStatus
            var lastSeenAt: Date
            var capabilities: [String]
        }

        let response: Response = try await http.post("/v1/node/mesh/invites/accept", body: request)
        return MeshNodeRecord(
            id: response.id,
            name: response.name,
            publicKey: response.publicKey,
            roles: response.roles,
            endpoint: response.endpoint,
            status: response.status,
            lastSeenAt: response.lastSeenAt,
            capabilities: response.capabilities
        )
    }

    public func listTasks(projectId: String?) async throws -> [MeshTaskRecord] {
        let encodedProjectId = projectId.flatMap(BackendHTTPClient.encodeQueryValue) ?? ""
        let path = encodedProjectId.isEmpty ? "/v1/node/mesh/tasks" : "/v1/node/mesh/tasks?projectId=\(encodedProjectId)"
        return try await http.get(path)
    }

    public func createTask(_ request: MeshTaskCreateRequest) async throws -> MeshTaskRecord {
        try await http.post("/v1/node/mesh/tasks", body: request)
    }
}

public actor ConfigService {
    private let http: BackendHTTPClient

    public init(http: BackendHTTPClient) {
        self.http = http
    }

    public func fetchConfig() async throws -> SloppyConfig {
        try await http.get("/v1/config")
    }

    public func updateConfig(_ config: SloppyConfig) async throws -> SloppyConfig {
        try await http.put("/v1/config", body: config)
    }

    public func fetchAccessUsers(platform: String? = nil) async throws -> [AccessUser] {
        let trimmed = platform?.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = (trimmed?.isEmpty == false) ? "?platform=\(BackendHTTPClient.encodeQueryValue(trimmed!))" : ""
        return try await http.get("/v1/channel-approvals/users\(query)")
    }

    public func deleteAccessUser(_ userId: String) async throws {
        try await http.delete("/v1/channel-approvals/users/\(BackendHTTPClient.encodePathSegment(userId))")
    }
}
