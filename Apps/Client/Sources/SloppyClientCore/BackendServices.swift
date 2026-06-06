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
