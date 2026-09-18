import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import SloppyClientCore

@Suite("Session creation", .serialized)
struct SessionCreationTests {
    @Test("forked session sends its parent and preserves scope")
    func forkedSessionPayload() async throws {
        let capture = SessionCreationRequestCapture()
        SessionCreationURLProtocol.install { request in
            capture.set(request)
            let response = try #require(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let body = Data(
                #"{"id":"child-session","agentId":"agent/one","title":"Fork: response","messageCount":0,"updatedAt":"2026-09-17T08:00:00Z","kind":"chat","projectId":"project-1","workspaceId":"workspace-1"}"#.utf8
            )
            return (response, body)
        }
        defer { SessionCreationURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionCreationURLProtocol.self]
        let client = SloppyAPIClient(
            baseURL: URL(string: "https://sessions.sloppy.test")!,
            session: URLSession(configuration: configuration),
            authSessionStore: AuthSessionStore(persistence: .memory)
        )

        let session = try await client.createAgentSession(
            agentId: "agent/one",
            title: "Fork: response",
            parentSessionId: "parent-session",
            projectId: "project-1",
            workspaceId: "workspace-1"
        )

        #expect(session.id == "child-session")
        let request = try #require(capture.snapshot())
        #expect(request.url?.path == "/v1/agents/agent/one/sessions")
        #expect(request.url?.absoluteString.contains("/v1/agents/agent%2Fone/sessions") == true)
        let data = try #require(request.httpBody ?? request.httpBodyStream?.sessionCreationReadAllData())
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(payload["title"] as? String == "Fork: response")
        #expect(payload["parentSessionId"] as? String == "parent-session")
        #expect(payload["projectId"] as? String == "project-1")
        #expect(payload["workspaceId"] as? String == "workspace-1")
        #expect(payload["kind"] as? String == "chat")
    }
}

private final class SessionCreationRequestCapture: @unchecked Sendable {
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
    func sessionCreationReadAllData() -> Data {
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

private final class SessionCreationURLProtocol: URLProtocol, @unchecked Sendable {
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
