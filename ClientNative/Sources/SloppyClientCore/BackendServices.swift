import Foundation

public struct HealthCheckResult: Sendable {
    public let isHealthy: Bool
    public let failureMessage: String?

    public init(isHealthy: Bool, failureMessage: String? = nil) {
        self.isHealthy = isHealthy
        self.failureMessage = failureMessage
    }
}

public struct ChatAttachmentUpload: Codable, Sendable, Equatable {
    public var name: String
    public var mimeType: String
    public var sizeBytes: Int
    public var contentBase64: String

    public init(name: String, mimeType: String, sizeBytes: Int, contentBase64: String) {
        self.name = name
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.contentBase64 = contentBase64
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

    public init(
        accessToken: String,
        refreshToken: String,
        accessTokenExpiresAt: Date? = nil,
        refreshTokenExpiresAt: Date? = nil,
        user: AuthUserProfile? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
        self.user = user
    }
}

public struct DashboardAuthStatus: Codable, Sendable, Equatable {
    public var enabled: Bool
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

    public func fetchCurrentUser() async throws -> AuthUserProfile {
        try await http.get("/v1/auth/me")
    }

    public func fetchDashboardAuthStatus() async throws -> DashboardAuthStatus {
        try await http.get("/v1/dashboard/auth/status")
    }

    public func validateCurrentToken() async throws {
        struct EmptyPayload: Encodable {}
        struct ValidationResponse: Decodable { var ok: Bool }

        let response: ValidationResponse = try await http.post(
            "/v1/dashboard/auth/validate",
            body: EmptyPayload()
        )
        guard response.ok else {
            throw APIError.invalidResponse
        }
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

    public func createProject(_ request: APIProjectCreateRequest) async throws -> APIProjectRecord {
        let result: APIProjectCreateResult = try await http.post("/v1/projects", body: request)
        return result.project
    }

    public func updateProject(id: String, request: APIProjectUpdateRequest) async throws -> APIProjectRecord {
        try await http.patch(
            "/v1/projects/\(BackendHTTPClient.encodePathSegment(id))",
            body: request
        )
    }

    public func createTask(
        projectId: String,
        request: APIProjectTaskCreateRequest
    ) async throws -> APIProjectRecord {
        try await http.post(
            "/v1/projects/\(BackendHTTPClient.encodePathSegment(projectId))/tasks",
            body: request
        )
    }

    public func fetchTaskComments(projectId: String, taskId: String) async throws -> [TaskComment] {
        try await http.get(
            "/v1/projects/\(BackendHTTPClient.encodePathSegment(projectId))/tasks/\(BackendHTTPClient.encodePathSegment(taskId))/comments"
        )
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

    public func fetchChatSlashCommands(agentId: String) async throws -> AgentChatSlashCommandsResponse {
        try await http.get("/v1/agents/\(BackendHTTPClient.encodePathSegment(agentId))/chat-slash-commands")
    }
}

public actor SessionService {
    private let http: BackendHTTPClient

    public enum SessionControlAction: String, Encodable, Sendable {
        case interrupt
        case interruptTree = "interruptTree"
    }

    public init(http: BackendHTTPClient) {
        self.http = http
    }

    public func fetchAgentSessions(
        agentId: String,
        projectId: String? = nil,
        limit: Int? = nil
    ) async throws -> [ChatSessionSummary] {
        var path = "/v1/agents/\(BackendHTTPClient.encodePathSegment(agentId))/sessions"
        var queryItems: [String] = []
        if let projectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines), !projectId.isEmpty {
            queryItems.append("projectId=\(BackendHTTPClient.encodeQueryValue(projectId))")
        }
        if let limit {
            queryItems.append("limit=\(max(0, limit))")
        }
        if !queryItems.isEmpty {
            path += "?\(queryItems.joined(separator: "&"))"
        }
        return try await http.get(path)
    }

    public func fetchAgentSession(agentId: String, sessionId: String) async throws -> ChatSessionDetail {
        try await http.get("/v1/agents/\(BackendHTTPClient.encodePathSegment(agentId))/sessions/\(BackendHTTPClient.encodePathSegment(sessionId))")
    }

    public func fetchAgentSessionData(agentId: String, sessionId: String) async throws -> Data {
        try await http.getData("/v1/agents/\(BackendHTTPClient.encodePathSegment(agentId))/sessions/\(BackendHTTPClient.encodePathSegment(sessionId))")
    }

    public func createAgentSession(
        agentId: String,
        title: String? = nil,
        projectId: String? = nil,
        workspaceId: String? = nil
    ) async throws -> ChatSessionSummary {
        struct Payload: Encodable {
            var title: String?
            var kind: String = "chat"
            var projectId: String?
            var workspaceId: String?
        }
        let normalizedProjectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedWorkspaceId = workspaceId?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await http.post(
            "/v1/agents/\(BackendHTTPClient.encodePathSegment(agentId))/sessions",
            body: Payload(
                title: title,
                projectId: normalizedProjectId?.isEmpty == false ? normalizedProjectId : nil,
                workspaceId: normalizedWorkspaceId?.isEmpty == false ? normalizedWorkspaceId : nil
            )
        )
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
        struct Payload: Encodable {
            var userId: String
            var content: String
            var attachments: [ChatAttachmentUpload]
            var spawnSubSession: Bool = false
            var selectedModel: String?
            var reasoningEffort: String?
        }
        struct Response: Decodable {
            var summary: ChatSessionSummary
        }
        let normalizedSelectedModel = selectedModel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReasoningEffort = reasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines)
        let response: Response = try await http.post(
            "/v1/agents/\(BackendHTTPClient.encodePathSegment(agentId))/sessions/\(BackendHTTPClient.encodePathSegment(sessionId))/messages",
            body: Payload(
                userId: userId,
                content: content,
                attachments: attachments,
                selectedModel: normalizedSelectedModel?.isEmpty == false ? normalizedSelectedModel : nil,
                reasoningEffort: normalizedReasoningEffort?.isEmpty == false ? normalizedReasoningEffort : nil
            )
        )
        return response.summary
    }

    public func answerInputRequest(
        agentId: String,
        sessionId: String,
        requestId: String,
        request: ChatPlanInputAnswerRequest
    ) async throws -> ChatSessionSummary {
        struct Response: Decodable {
            var summary: ChatSessionSummary
        }

        let response: Response = try await http.post(
            "/v1/agents/\(BackendHTTPClient.encodePathSegment(agentId))/sessions/\(BackendHTTPClient.encodePathSegment(sessionId))/input-requests/\(BackendHTTPClient.encodePathSegment(requestId))/answer",
            body: request
        )
        return response.summary
    }

    public func deleteAgentSession(agentId: String, sessionId: String) async throws {
        try await http.delete("/v1/agents/\(BackendHTTPClient.encodePathSegment(agentId))/sessions/\(BackendHTTPClient.encodePathSegment(sessionId))")
    }

    public func controlAgentSession(
        agentId: String,
        sessionId: String,
        action: SessionControlAction,
        requestedBy: String = "apple-client",
        reason: String? = nil
    ) async throws {
        struct Payload: Encodable {
            var action: SessionControlAction
            var requestedBy: String
            var reason: String?
        }

        try await http.post(
            "/v1/agents/\(BackendHTTPClient.encodePathSegment(agentId))/sessions/\(BackendHTTPClient.encodePathSegment(sessionId))/control",
            body: Payload(action: action, requestedBy: requestedBy, reason: reason)
        )
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

    public func fetchAvailableModels() async throws -> [ChatModelOption] {
        try await http.get("/v1/providers/models")
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
