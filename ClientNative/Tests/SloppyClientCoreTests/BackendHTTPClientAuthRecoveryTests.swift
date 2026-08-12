import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import SloppyClientCore

@Suite("Backend HTTP auth recovery", .serialized)
struct BackendHTTPClientAuthRecoveryTests {
    @Test("stored access token is available to an embedded authenticated surface")
    func exposesStoredAccessToken() async throws {
        let baseURL = try #require(URL(string: "https://workspace.sloppy.test"))
        let store = AuthSessionStore(persistence: .memory)
        await store.save(
            AuthSession(accessToken: "workspace-access", refreshToken: "workspace-refresh"),
            for: baseURL
        )
        let client = BackendHTTPClient(
            baseURL: baseURL,
            session: Self.makeSession(),
            authSessionStore: store
        )

        #expect(await client.currentAccessToken() == "workspace-access")
    }

    @Test("401 refreshes the saved session and retries the original request once")
    func refreshesAndRetriesUnauthorizedRequest() async throws {
        let baseURL = try #require(URL(string: "https://sloppy.test"))
        let store = AuthSessionStore(persistence: .memory)
        await store.save(
            AuthSession(accessToken: "expired-access", refreshToken: "valid-refresh"),
            for: baseURL
        )
        let recorder = RequestRecorder()

        StubURLProtocol.install { request in
            let path = request.url?.path ?? ""
            if path == "/v1/auth/refresh" {
                recorder.recordRefresh(request)
                let refreshed = AuthSession(
                    accessToken: "fresh-access",
                    refreshToken: "fresh-refresh"
                )
                return try Self.response(for: request, status: 200, body: JSONEncoder().encode(refreshed))
            }

            recorder.recordProtected(request)
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer expired-access" {
                return try Self.response(for: request, status: 401, body: Data(#"{"error":"unauthorized"}"#.utf8))
            }
            return try Self.response(for: request, status: 200, body: Data("ok".utf8))
        }
        defer { StubURLProtocol.reset() }

        let client = BackendHTTPClient(
            baseURL: baseURL,
            session: Self.makeSession(),
            authSessionStore: store
        )
        let data = try await client.getData("/v1/projects")

        #expect(String(data: data, encoding: .utf8) == "ok")
        #expect(recorder.snapshot().protectedTokens == ["Bearer expired-access", "Bearer fresh-access"])
        #expect(recorder.snapshot().refreshCount == 1)
        #expect(await store.session(for: baseURL)?.accessToken == "fresh-access")
        #expect(await store.session(for: baseURL)?.refreshToken == "fresh-refresh")
    }

    @Test("parallel 401 responses share one refresh operation")
    func concurrentRequestsShareRefresh() async throws {
        let baseURL = try #require(URL(string: "https://parallel.sloppy.test"))
        let store = AuthSessionStore(persistence: .memory)
        await store.save(
            AuthSession(accessToken: "expired", refreshToken: "refresh"),
            for: baseURL
        )
        let recorder = RequestRecorder()

        StubURLProtocol.install { request in
            if request.url?.path == "/v1/auth/refresh" {
                recorder.recordRefresh(request)
                Thread.sleep(forTimeInterval: 0.05)
                let refreshed = AuthSession(accessToken: "fresh", refreshToken: "rotated")
                return try Self.response(for: request, status: 200, body: JSONEncoder().encode(refreshed))
            }
            recorder.recordProtected(request)
            let status = request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh" ? 200 : 401
            return try Self.response(for: request, status: status, body: Data("ok".utf8))
        }
        defer { StubURLProtocol.reset() }

        let session = Self.makeSession()
        let clients = (0..<3).map { _ in
            BackendHTTPClient(baseURL: baseURL, session: session, authSessionStore: store)
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for client in clients {
                group.addTask {
                    _ = try await client.getData("/v1/projects")
                }
            }
            try await group.waitForAll()
        }

        #expect(recorder.snapshot().refreshCount == 1)
    }

    @Test("failed refresh clears the saved session and preserves the 401 error")
    func failedRefreshClearsSession() async throws {
        let baseURL = try #require(URL(string: "https://expired.sloppy.test"))
        let store = AuthSessionStore(persistence: .memory)
        await store.save(
            AuthSession(accessToken: "expired", refreshToken: "expired-refresh"),
            for: baseURL
        )

        StubURLProtocol.install { request in
            try Self.response(
                for: request,
                status: 401,
                body: Data(#"{"error":"unauthorized"}"#.utf8)
            )
        }
        defer { StubURLProtocol.reset() }

        let client = BackendHTTPClient(
            baseURL: baseURL,
            session: Self.makeSession(),
            authSessionStore: store
        )

        do {
            _ = try await client.getData("/v1/projects")
            Issue.record("Expected a 401 error")
        } catch let error as APIError {
            #expect(error.statusCode == 401)
        }
        #expect(await store.session(for: baseURL) == nil)
    }

    @Test("a repeated 401 after refresh clears the rotated session")
    func repeatedUnauthorizedResponseClearsRefreshedSession() async throws {
        let baseURL = try #require(URL(string: "https://rejected.sloppy.test"))
        let store = AuthSessionStore(persistence: .memory)
        await store.save(
            AuthSession(accessToken: "expired", refreshToken: "refresh"),
            for: baseURL
        )

        StubURLProtocol.install { request in
            if request.url?.path == "/v1/auth/refresh" {
                let refreshed = AuthSession(accessToken: "rejected", refreshToken: "rotated")
                return try Self.response(for: request, status: 200, body: JSONEncoder().encode(refreshed))
            }
            return try Self.response(
                for: request,
                status: 401,
                body: Data(#"{"error":"unauthorized"}"#.utf8)
            )
        }
        defer { StubURLProtocol.reset() }

        let client = BackendHTTPClient(
            baseURL: baseURL,
            session: Self.makeSession(),
            authSessionStore: store
        )
        do {
            _ = try await client.getData("/v1/projects")
            Issue.record("Expected a repeated 401 error")
        } catch let error as APIError {
            #expect(error.statusCode == 401)
        }
        #expect(await store.session(for: baseURL) == nil)
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(
        for request: URLRequest,
        status: Int,
        body: Data
    ) throws -> (HTTPURLResponse, Data) {
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ))
        return (response, body)
    }
}

private final class RequestRecorder: @unchecked Sendable {
    struct Snapshot {
        var protectedTokens: [String]
        var refreshCount: Int
    }

    private let lock = NSLock()
    private var protectedTokens: [String] = []
    private var refreshCount = 0

    func recordProtected(_ request: URLRequest) {
        lock.withLock {
            protectedTokens.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
        }
    }

    func recordRefresh(_ request: URLRequest) {
        lock.withLock {
            refreshCount += 1
        }
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(
                protectedTokens: protectedTokens,
                refreshCount: refreshCount
            )
        }
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
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
