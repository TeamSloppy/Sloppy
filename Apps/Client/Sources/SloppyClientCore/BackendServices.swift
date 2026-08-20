import Foundation

public struct HealthCheckResult: Sendable {
    public let isHealthy: Bool
    public let failureMessage: String?

    public init(isHealthy: Bool, failureMessage: String? = nil) {
        self.isHealthy = isHealthy
        self.failureMessage = failureMessage
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

public struct AuthChallenge: Codable, Sendable, Equatable {
    public var mode: String
    public var bootstrapRequired: Bool
    public var passkeySupported: Bool?
    public var accessTokenExpiresInSeconds: Int?
    public var refreshTokenExpiresInSeconds: Int?
}

public struct AuthUserProfile: Codable, Sendable, Equatable {
    public var id: String
    public var login: String
    public var name: String
    public var avatar: String?
    public var description: String?
    public var role: String
    public var status: String?
}

public struct AuthSession: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var accessTokenExpiresAt: Date?
    public var refreshTokenExpiresAt: Date?
    public var user: AuthUserProfile?
}

public actor AuthService {
    private let http: BackendHTTPClient

    public init(http: BackendHTTPClient) {
        self.http = http
    }

    public func fetchAuthChallenge() async throws -> AuthChallenge {
        try await http.get("/v1/auth/challenge")
    }

    public func loginIdentityUser(login: String, password: String) async throws -> AuthSession {
        struct Payload: Encodable {
            var login: String
            var password: String
        }
        return try await http.post(
            "/v1/auth/login",
            body: Payload(
                login: login.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
        )
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
}

public actor TaskSyncService {
    private let http: BackendHTTPClient

    public init(http: BackendHTTPClient) {
        self.http = http
    }

    public func providers() async throws -> [APITaskSyncProviderDescriptor] {
        try await http.get("/v1/task-sync/providers")
    }

    public func settings(projectId: String) async throws -> APIProjectTaskSyncSettings {
        try await http.get("/v1/projects/\(BackendHTTPClient.encodePathSegment(projectId))/task-sync")
    }

    public func tokenStatus(projectId: String, providerId: String) async throws -> APIProjectTaskSyncTokenStatus {
        try await http.get(
            "/v1/projects/\(BackendHTTPClient.encodePathSegment(projectId))/task-sync/token?providerId=\(BackendHTTPClient.encodeQueryValue(providerId))"
        )
    }

    public func setToken(projectId: String, providerId: String, token: String) async throws -> APIProjectTaskSyncTokenStatus {
        struct Payload: Encodable { var token: String }
        return try await http.post(
            "/v1/projects/\(BackendHTTPClient.encodePathSegment(projectId))/task-sync/token?providerId=\(BackendHTTPClient.encodeQueryValue(providerId))",
            body: Payload(token: token)
        )
    }

    public func discover(projectId: String, request: APIProjectTaskSyncDiscoverRequest) async throws -> APIProjectTaskSyncDiscoveryResponse {
        try await http.post(
            "/v1/projects/\(BackendHTTPClient.encodePathSegment(projectId))/task-sync/discover",
            body: request
        )
    }

    public func link(projectId: String, request: APIProjectTaskSyncLinkRequest) async throws -> APIProjectTaskSyncResponse {
        try await http.post(
            "/v1/projects/\(BackendHTTPClient.encodePathSegment(projectId))/task-sync/link",
            body: request
        )
    }

    public func unlink(projectId: String) async throws -> APIProjectTaskSyncResponse {
        struct Empty: Encodable {}
        return try await http.post(
            "/v1/projects/\(BackendHTTPClient.encodePathSegment(projectId))/task-sync/unlink",
            body: Empty()
        )
    }

    public func syncNow(projectId: String) async throws -> APIProjectTaskSyncNowResponse {
        struct Empty: Encodable {}
        return try await http.post(
            "/v1/projects/\(BackendHTTPClient.encodePathSegment(projectId))/task-sync/sync-now",
            body: Empty()
        )
    }

    public func comments(projectId: String, taskId: String) async throws -> [APITaskComment] {
        try await http.get(
            "/v1/projects/\(BackendHTTPClient.encodePathSegment(projectId))/tasks/\(BackendHTTPClient.encodePathSegment(taskId))/comments"
        )
    }

    public func addComment(projectId: String, taskId: String, content: String) async throws -> APITaskComment {
        struct Payload: Encodable {
            var content: String
            var authorActorId: String = "user"
        }
        return try await http.post(
            "/v1/projects/\(BackendHTTPClient.encodePathSegment(projectId))/tasks/\(BackendHTTPClient.encodePathSegment(taskId))/comments",
            body: Payload(content: content)
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
}
