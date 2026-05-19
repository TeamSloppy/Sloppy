import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Protocols
import SloppySDK
import Testing

private final class MockTransport: SloppyHTTPTransport, @unchecked Sendable {
    var handler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    init(handler: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await handler(request)
    }
}

private func response(url: URL, status: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
}

private func encoded<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(value)
}

@Test
func listAgentsBuildsTypedRequest() async throws {
    let transport = MockTransport { request in
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/api/v1/agents")
        #expect(request.url?.query == "system=false")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")

        let payload = [
            AgentSummary(
                id: "builder",
                displayName: "Builder",
                role: "Builds features"
            )
        ]
        return try (encoded(payload), response(url: request.url!))
    }

    let client = SloppyClient(
        baseURL: URL(string: "http://127.0.0.1:7331/api")!,
        bearerToken: "test-token",
        transport: transport
    )

    let agents = try await client.listAgents(includeSystem: false)

    #expect(agents.map(\.id) == ["builder"])
}

@Test
func createAgentSessionEncodesRequestBody() async throws {
    let transport = MockTransport { request in
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/agents/coder/sessions")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(AgentSessionCreateRequest.self, from: request.httpBody ?? Data())
        #expect(payload.title == "Initial harness session")
        #expect(payload.projectId == "sloppy")

        let summary = AgentSessionSummary(
            id: "session-1",
            agentId: "coder",
            title: "Initial harness session",
            projectId: "sloppy"
        )
        return try (encoded(summary), response(url: request.url!, status: 201))
    }

    let client = SloppyClient(
        baseURL: URL(string: "http://127.0.0.1:7331")!,
        transport: transport
    )

    let session = try await client.createAgentSession(
        agentID: "coder",
        request: AgentSessionCreateRequest(title: "Initial harness session", projectId: "sloppy")
    )

    #expect(session.id == "session-1")
    #expect(session.projectId == "sloppy")
}

@Test
func httpErrorsExposeCoreErrorCode() async throws {
    let transport = MockTransport { request in
        let payload = try encoded(SloppyAPIErrorBody(error: "agent_not_found"))
        return (payload, response(url: request.url!, status: 404))
    }
    let client = SloppyClient(
        baseURL: URL(string: "http://127.0.0.1:7331")!,
        transport: transport
    )

    do {
        _ = try await client.getAgentSession(agentID: "missing", sessionID: "s1")
        Issue.record("Expected HTTP status error")
    } catch let error as SloppySDKError {
        #expect(error == .httpStatus(status: 404, error: "agent_not_found", message: nil))
    }
}
