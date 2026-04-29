import Foundation
import Logging

public actor SloppyAPIClient {
    public nonisolated let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger: Logger

    public init(
        baseURL: URL = URL(string: "http://localhost:25101")!,
        session: URLSession = .shared,
        logger: Logger = Logger(label: "sloppy.api-client")
    ) {
        self.baseURL = baseURL
        self.session = session
        self.logger = logger

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = ISO8601DateFormatter().date(from: str) { return date }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(str)"
            )
        }
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    public func fetchProjects() async throws -> [APIProjectRecord] {
        try await get("/v1/projects")
    }

    public func fetchProject(id: String) async throws -> APIProjectRecord {
        try await get("/v1/projects/\(id)")
    }

    public func fetchAgents() async throws -> [APIAgentRecord] {
        try await get("/v1/agents")
    }

    public func fetchAgent(id: String) async throws -> APIAgentRecord {
        try await get("/v1/agents/\(id)")
    }

    public func fetchAgentTasks(agentId: String) async throws -> [APIAgentTaskRecord] {
        try await get("/v1/agents/\(agentId)/tasks")
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

    public func fetchAgentSessions(agentId: String) async throws -> [ChatSessionSummary] {
        try await get("/v1/agents/\(agentId)/sessions")
    }

    public func fetchAgentSession(agentId: String, sessionId: String) async throws -> ChatSessionDetail {
        try await get("/v1/agents/\(agentId)/sessions/\(sessionId)")
    }

    public func fetchAgentSessionData(agentId: String, sessionId: String) async throws -> Data {
        try await getData("/v1/agents/\(agentId)/sessions/\(sessionId)")
    }

    public func createAgentSession(agentId: String, title: String? = nil) async throws -> ChatSessionSummary {
        struct Payload: Encodable {
            var title: String?
            var kind: String = "chat"
        }
        return try await post("/v1/agents/\(agentId)/sessions", body: Payload(title: title))
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
        let response: Response = try await post(
            "/v1/agents/\(agentId)/sessions/\(sessionId)/messages",
            body: Payload(userId: userId, content: content)
        )
        return response.summary
    }

    public func deleteAgentSession(agentId: String, sessionId: String) async throws {
        try await delete("/v1/agents/\(agentId)/sessions/\(sessionId)")
    }

    // MARK: - Config API

    public func fetchConfig() async throws -> SloppyConfig {
        try await get("/v1/config")
    }

    public func updateConfig(_ config: SloppyConfig) async throws -> SloppyConfig {
        try await put("/v1/config", body: config)
    }

    // MARK: - Private helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await getData(path)
        return try decoder.decode(T.self, from: data)
    }

    private func getData(_ path: String) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        logger.debug("GET \(url.absoluteString)")
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode)
        }

        return data
    }

    private func put<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)

        logger.debug("PUT \(url.absoluteString)")
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode)
        }

        return try decoder.decode(T.self, from: data)
    }

    private func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)

        logger.debug("POST \(url.absoluteString)")
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode)
        }

        return try decoder.decode(T.self, from: data)
    }

    private func delete(_ path: String) async throws {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        logger.debug("DELETE \(url.absoluteString)")
        let (_, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode)
        }
    }
}

public enum APIError: Error, Sendable {
    case invalidResponse
    case httpError(statusCode: Int)
}
