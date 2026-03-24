import Foundation
import Logging

public actor SloppyAPIClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
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

    private func get<T: Decodable>(_ path: String) async throws -> T {
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

        return try decoder.decode(T.self, from: data)
    }
}

public enum APIError: Error, Sendable {
    case invalidResponse
    case httpError(statusCode: Int)
}
