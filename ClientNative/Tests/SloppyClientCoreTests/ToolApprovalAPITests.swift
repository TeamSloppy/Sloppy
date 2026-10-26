import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import SloppyClientCore

@Suite("Tool approval API", .serialized)
struct ToolApprovalAPITests {
    @Test("the server default uses a focused configuration endpoint", arguments: ChatApprovalMode.allCases)
    func defaultChatApprovalPolicy(mode: ChatApprovalMode) async throws {
        let capture = ToolApprovalRequestCapture()
        ToolApprovalURLProtocol.install { request in
            capture.set(request)
            return (try #require(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)),
                    try JSONEncoder().encode(ChatApprovalPolicy(mode: mode)))
        }
        defer { ToolApprovalURLProtocol.reset() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ToolApprovalURLProtocol.self]
        let client = SloppyAPIClient(baseURL: URL(string: "https://defaults.sloppy.test")!,
            session: URLSession(configuration: configuration), authSessionStore: AuthSessionStore(persistence: .memory))
        #expect(try await client.setDefaultChatApprovalPolicy(mode: mode).mode == mode)
        let request = try #require(capture.snapshot())
        #expect(request.url?.path == "/v1/config/chat-approval-default")
        #expect(request.httpMethod == "PUT")
        #expect(try payload(request)["mode"] as? String == mode.rawValue)
        #expect(try await client.fetchDefaultChatApprovalPolicy().mode == mode)
        #expect(capture.snapshot()?.httpMethod == "GET")
    }

    @Test("chat policy is scoped to the encoded agent and session", arguments: ChatApprovalMode.allCases)
    func chatApprovalPolicy(mode: ChatApprovalMode) async throws {
        let capture = ToolApprovalRequestCapture()
        ToolApprovalURLProtocol.install { request in
            capture.set(request)
            return (
                try #require(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)),
                try JSONEncoder().encode(ChatApprovalPolicy(mode: mode))
            )
        }
        defer { ToolApprovalURLProtocol.reset() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ToolApprovalURLProtocol.self]
        let client = SloppyAPIClient(baseURL: URL(string: "https://approvals.sloppy.test")!,
            session: URLSession(configuration: configuration), authSessionStore: AuthSessionStore(persistence: .memory))

        let saved = try await client.setChatApprovalPolicy(agentId: "agent/one", sessionId: "chat/two", mode: mode)
        #expect(saved.mode == mode)
        let request = try #require(capture.snapshot())
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString.contains("/agents/agent%2Fone/sessions/chat%2Ftwo/approval-policy") == true)
        #expect(try payload(request)["mode"] as? String == mode.rawValue)
        #expect(try await client.fetchChatApprovalPolicy(agentId: "agent/one", sessionId: "chat/two").mode == mode)
        #expect(capture.snapshot()?.httpMethod == "GET")
    }

    @Test("approval scopes reach the server", arguments: ClientToolApprovalDecisionScope.allCases)
    func approvalScopePayload(scope: ClientToolApprovalDecisionScope) async throws {
        let capture = ToolApprovalRequestCapture()
        ToolApprovalURLProtocol.install { request in
            capture.set(request)
            return (
                try #require(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)),
                Data(#"{"id":"approval/1"}"#.utf8)
            )
        }
        defer { ToolApprovalURLProtocol.reset() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ToolApprovalURLProtocol.self]
        let client = SloppyAPIClient(
            baseURL: URL(string: "https://approvals.sloppy.test")!,
            session: URLSession(configuration: configuration),
            authSessionStore: AuthSessionStore(persistence: .memory)
        )

        try await client.resolveToolApproval(id: "approval/1", approved: true, scope: scope)
        let request = try #require(capture.snapshot())
        #expect(request.url?.absoluteString.contains("/v1/tool-approvals/approval%2F1/approve") == true)
        let payload = try payload(request)
        #expect(payload["scope"] as? String == scope.rawValue)
        #expect(payload["decidedBy"] as? String == "SloppyClient")

        try await client.resolveToolApproval(id: "approval/1", approved: false, scope: scope)
        let rejection = try #require(capture.snapshot())
        #expect(rejection.url?.path.hasSuffix("/reject") == true)
        #expect(try self.payload(rejection)["scope"] as? String == "once")

        try await client.resolveToolApproval(id: "approval/1", approved: true)
        #expect(try self.payload(#require(capture.snapshot()))["scope"] as? String == "once")
    }

    private func payload(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody ?? request.httpBodyStream?.toolApprovalReadAllData())
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class ToolApprovalRequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?

    func set(_ request: URLRequest) {
        lock.withLock { self.request = request }
    }

    func snapshot() -> URLRequest? {
        lock.withLock { request }
    }
}

private extension InputStream {
    func toolApprovalReadAllData() -> Data {
        open()
        defer { close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while hasBytesAvailable {
            let count = read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class ToolApprovalURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?

    static func install(_ handler: @escaping Handler) {
        lock.withLock { self.handler = handler }
    }

    static func reset() {
        lock.withLock { handler = nil }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.lock.withLock { Self.handler }
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
