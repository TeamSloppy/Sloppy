import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols

public struct SloppyClientConfiguration: Sendable, Equatable {
    public var baseURL: URL
    public var bearerToken: String?
    public var timeoutInterval: TimeInterval

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:7331")!,
        bearerToken: String? = nil,
        timeoutInterval: TimeInterval = 120
    ) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.timeoutInterval = timeoutInterval
    }
}

public struct SloppyAPIErrorBody: Codable, Sendable, Equatable {
    public var error: String?
    public var message: String?

    public init(error: String? = nil, message: String? = nil) {
        self.error = error
        self.message = message
    }
}

public enum SloppySDKError: Error, Sendable, Equatable {
    case invalidURL
    case invalidHTTPResponse
    case httpStatus(status: Int, error: String?, message: String?)
    case emptyResponse
}

extension SloppySDKError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Could not build a valid Sloppy Core API URL."
        case .invalidHTTPResponse:
            "Sloppy Core API returned a non-HTTP response."
        case let .httpStatus(status, error, message):
            [String(status), error, message]
                .compactMap { $0 }
                .joined(separator: ": ")
        case .emptyResponse:
            "Sloppy Core API returned an empty response."
        }
    }
}

public protocol SloppyHTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: SloppyHTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SloppySDKError.invalidHTTPResponse
        }
        return (data, httpResponse)
    }
}

public struct SloppyDeleteResponse: Codable, Sendable, Equatable {
    public var ok: String?

    public init(ok: String? = nil) {
        self.ok = ok
    }
}

public final class SloppyClient {
    public let configuration: SloppyClientConfiguration
    private let transport: any SloppyHTTPTransport
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        configuration: SloppyClientConfiguration = SloppyClientConfiguration(),
        transport: any SloppyHTTPTransport = URLSession.shared
    ) {
        self.configuration = configuration
        self.transport = transport
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public convenience init(
        baseURL: URL,
        bearerToken: String? = nil,
        timeoutInterval: TimeInterval = 120,
        transport: any SloppyHTTPTransport = URLSession.shared
    ) {
        self.init(
            configuration: SloppyClientConfiguration(
                baseURL: baseURL,
                bearerToken: bearerToken,
                timeoutInterval: timeoutInterval
            ),
            transport: transport
        )
    }

    public func listAgents(includeSystem: Bool = true) async throws -> [AgentSummary] {
        try await request(
            method: "GET",
            path: ["v1", "agents"],
            query: [URLQueryItem(name: "system", value: includeSystem ? "true" : "false")],
            response: [AgentSummary].self
        )
    }

    public func createAgent(_ body: AgentCreateRequest) async throws -> AgentSummary {
        try await request(
            method: "POST",
            path: ["v1", "agents"],
            body: body,
            response: AgentSummary.self
        )
    }

    public func getAgent(agentID: String) async throws -> AgentSummary {
        try await request(
            method: "GET",
            path: ["v1", "agents", agentID],
            response: AgentSummary.self
        )
    }

    public func deleteAgent(agentID: String) async throws -> SloppyDeleteResponse {
        try await request(
            method: "DELETE",
            path: ["v1", "agents", agentID],
            response: SloppyDeleteResponse.self
        )
    }

    public func listAgentSessions(
        agentID: String,
        projectID: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) async throws -> [AgentSessionSummary] {
        var query: [URLQueryItem] = []
        if let projectID {
            query.append(URLQueryItem(name: "projectId", value: projectID))
        }
        if let limit {
            query.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if let offset {
            query.append(URLQueryItem(name: "offset", value: String(offset)))
        }
        return try await request(
            method: "GET",
            path: ["v1", "agents", agentID, "sessions"],
            query: query,
            response: [AgentSessionSummary].self
        )
    }

    public func createAgentSession(
        agentID: String,
        request body: AgentSessionCreateRequest = AgentSessionCreateRequest()
    ) async throws -> AgentSessionSummary {
        try await request(
            method: "POST",
            path: ["v1", "agents", agentID, "sessions"],
            body: body,
            response: AgentSessionSummary.self
        )
    }

    public func getAgentSession(agentID: String, sessionID: String) async throws -> AgentSessionDetail {
        try await request(
            method: "GET",
            path: ["v1", "agents", agentID, "sessions", sessionID],
            response: AgentSessionDetail.self
        )
    }

    public func postAgentSessionMessage(
        agentID: String,
        sessionID: String,
        request body: AgentSessionPostMessageRequest
    ) async throws -> AgentSessionMessageResponse {
        try await request(
            method: "POST",
            path: ["v1", "agents", agentID, "sessions", sessionID, "messages"],
            body: body,
            response: AgentSessionMessageResponse.self
        )
    }

    public func sendMessage(
        agentID: String,
        sessionID: String,
        userID: String,
        content: String,
        mode: AgentChatMode? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        selectedModel: String? = nil
    ) async throws -> AgentSessionMessageResponse {
        try await postAgentSessionMessage(
            agentID: agentID,
            sessionID: sessionID,
            request: AgentSessionPostMessageRequest(
                userId: userID,
                content: content,
                reasoningEffort: reasoningEffort,
                selectedModel: selectedModel,
                mode: mode
            )
        )
    }

    public func addAgentSessionDirectory(
        agentID: String,
        sessionID: String,
        path: String
    ) async throws -> AgentSessionDirectoryResponse {
        try await request(
            method: "POST",
            path: ["v1", "agents", agentID, "sessions", sessionID, "directories"],
            body: AgentSessionDirectoryRequest(path: path),
            response: AgentSessionDirectoryResponse.self
        )
    }

    public func controlAgentSession(
        agentID: String,
        sessionID: String,
        request body: AgentSessionControlRequest
    ) async throws -> AgentSessionMessageResponse {
        try await request(
            method: "POST",
            path: ["v1", "agents", agentID, "sessions", sessionID, "control"],
            body: body,
            response: AgentSessionMessageResponse.self
        )
    }

    public func interruptAgentSession(
        agentID: String,
        sessionID: String,
        requestedBy: String,
        reason: String? = nil,
        includeSubsessions: Bool = true
    ) async throws -> AgentSessionMessageResponse {
        try await controlAgentSession(
            agentID: agentID,
            sessionID: sessionID,
            request: AgentSessionControlRequest(
                action: includeSubsessions ? .interruptTree : .interrupt,
                requestedBy: requestedBy,
                reason: reason
            )
        )
    }

    public func appendAgentSessionEvents(
        agentID: String,
        sessionID: String,
        events: [AgentSessionEvent]
    ) async throws -> AgentSessionMessageResponse {
        try await request(
            method: "POST",
            path: ["v1", "agents", agentID, "sessions", sessionID, "events"],
            body: AgentSessionAppendEventsRequest(events: events),
            response: AgentSessionMessageResponse.self
        )
    }

    public func deleteAgentSession(agentID: String, sessionID: String) async throws -> SloppyDeleteResponse {
        try await request(
            method: "DELETE",
            path: ["v1", "agents", agentID, "sessions", sessionID],
            response: SloppyDeleteResponse.self
        )
    }

    public func postChannelMessage(
        channelID: String,
        request body: ChannelMessageRequest
    ) async throws -> ChannelRouteDecision {
        try await request(
            method: "POST",
            path: ["v1", "channels", channelID, "messages"],
            body: body,
            response: ChannelRouteDecision.self
        )
    }

    public func listChannelEvents(
        channelID: String,
        limit: Int? = nil,
        cursor: String? = nil
    ) async throws -> ChannelEventsResponse {
        var query: [URLQueryItem] = []
        if let limit {
            query.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return try await request(
            method: "GET",
            path: ["v1", "channels", channelID, "events"],
            query: query,
            response: ChannelEventsResponse.self
        )
    }

    public func controlChannel(
        channelID: String,
        request body: ChannelControlRequest
    ) async throws -> ChannelControlResponse {
        try await request(
            method: "POST",
            path: ["v1", "channels", channelID, "control"],
            body: body,
            response: ChannelControlResponse.self
        )
    }
}

private extension SloppyClient {
    func request<Response: Decodable>(
        method: String,
        path: [String],
        query: [URLQueryItem] = [],
        response: Response.Type
    ) async throws -> Response {
        try await request(method: method, path: path, query: query, body: Optional<String>.none, response: response)
    }

    func request<Body: Encodable, Response: Decodable>(
        method: String,
        path: [String],
        query: [URLQueryItem] = [],
        body: Body?,
        response: Response.Type
    ) async throws -> Response {
        let url = try endpoint(path: path, query: query)
        var request = URLRequest(url: url, timeoutInterval: configuration.timeoutInterval)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = configuration.bearerToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        let (data, httpResponse) = try await transport.send(request)
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorBody = try? decoder.decode(SloppyAPIErrorBody.self, from: data)
            throw SloppySDKError.httpStatus(
                status: httpResponse.statusCode,
                error: errorBody?.error,
                message: errorBody?.message
            )
        }
        guard !data.isEmpty else {
            throw SloppySDKError.emptyResponse
        }
        return try decoder.decode(response, from: data)
    }

    func endpoint(path: [String], query: [URLQueryItem]) throws -> URL {
        var url = configuration.baseURL
        for segment in path {
            url.appendPathComponent(segment)
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SloppySDKError.invalidURL
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let resolved = components.url else {
            throw SloppySDKError.invalidURL
        }
        return resolved
    }
}
