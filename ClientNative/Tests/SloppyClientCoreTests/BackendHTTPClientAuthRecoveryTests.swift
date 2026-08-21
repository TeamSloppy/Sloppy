import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging
import Testing
@testable import SloppyClientCore

@Suite("Backend HTTP auth recovery", .serialized)
struct BackendHTTPClientAuthRecoveryTests {
    @Test("401 auth challenge falls back to dashboard token authentication")
    func resolvesProtectedChallengeAsLegacyTokenAuth() async throws {
        let baseURL = try #require(URL(string: "https://token-auth.sloppy.test"))
        let store = AuthSessionStore(persistence: .memory)

        StubURLProtocol.install { request in
            switch request.url?.path {
            case "/v1/auth/challenge":
                return try Self.response(
                    for: request,
                    status: 401,
                    body: Data(#"{"error":"unauthorized"}"#.utf8)
                )
            case "/v1/dashboard/auth/status":
                return try Self.response(
                    for: request,
                    status: 200,
                    body: Data(#"{"enabled":true}"#.utf8)
                )
            default:
                return try Self.response(for: request, status: 404, body: Data())
            }
        }
        defer { StubURLProtocol.reset() }

        let client = SloppyAPIClient(
            baseURL: baseURL,
            session: Self.makeSession(),
            authSessionStore: store
        )
        let challenge = try await client.fetchConnectionAuthChallenge()

        #expect(challenge == .legacyToken)
        #expect(challenge.mode == "token")
        #expect(challenge.bootstrapRequired == false)
    }

    @Test("HTTP lifecycle logs expose status but never the bearer token")
    func logsSafeRequestLifecycle() async throws {
        let baseURL = try #require(URL(string: "https://logs.sloppy.test"))
        let store = AuthSessionStore(persistence: .memory)
        let secret = "never-log-this-token"
        await store.saveStaticToken(secret, for: baseURL)
        let recorder = HTTPLogRecorder()

        StubURLProtocol.install { request in
            try Self.response(for: request, status: 200, body: Data("ok".utf8))
        }
        defer { StubURLProtocol.reset() }

        let client = BackendHTTPClient(
            baseURL: baseURL,
            session: Self.makeSession(),
            authSessionStore: store,
            logger: makeHTTPLogger(recorder)
        )
        _ = try await client.getData("/v1/projects")

        let logs = recorder.snapshot()
        #expect(logs.contains { record in
            record.message == "http.request.started"
                && record.metadata["auth"] == "present"
                && record.metadata["path"] == "/v1/projects"
        })
        #expect(logs.contains { record in
            record.message == "http.request.completed"
                && record.metadata["status"] == "200"
        })
        #expect(!logs.contains { record in
            record.message.contains(secret)
                || record.metadata.values.contains(where: { $0.contains(secret) })
        })
    }

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

    @Test("device pairing exchanges a one-time token and installs the returned session")
    func redeemsDevicePairing() async throws {
        let baseURL = try #require(URL(string: "https://pairing.sloppy.test"))
        let store = AuthSessionStore(persistence: .memory)
        let returnedSession = AuthSession(
            accessToken: "paired-access",
            refreshToken: "paired-refresh"
        )

        StubURLProtocol.install { request in
            guard request.url?.path == "/v1/auth/device-pairing/redeem",
                  request.httpMethod == "POST",
                  String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("slp_pair_once") == true else {
                return try Self.response(for: request, status: 400, body: Data())
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return try Self.response(
                for: request,
                status: 200,
                body: encoder.encode(returnedSession)
            )
        }
        defer { StubURLProtocol.reset() }

        let client = SloppyAPIClient(
            baseURL: baseURL,
            session: Self.makeSession(),
            authSessionStore: store
        )

        let session = try await client.redeemDevicePairing(token: "slp_pair_once")

        #expect(session == returnedSession)
        #expect(await client.currentAccessToken() == "paired-access")
        #expect(await store.session(for: baseURL) == returnedSession)
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

private final class HTTPLogRecorder: @unchecked Sendable {
    struct Record {
        var message: String
        var metadata: [String: String]
    }

    private let lock = NSLock()
    private var records: [Record] = []

    func append(message: Logger.Message, metadata: Logger.Metadata) {
        lock.withLock {
            records.append(Record(
                message: message.description,
                metadata: metadata.mapValues { String(describing: $0) }
            ))
        }
    }

    func snapshot() -> [Record] {
        lock.withLock { records }
    }
}

private struct HTTPRecordingLogHandler: LogHandler {
    let recorder: HTTPLogRecorder
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .trace

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata explicitMetadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        var merged = metadata
        if let explicitMetadata {
            for (key, value) in explicitMetadata {
                merged[key] = value
            }
        }
        recorder.append(message: message, metadata: merged)
    }
}

private func makeHTTPLogger(_ recorder: HTTPLogRecorder) -> Logger {
    Logger(label: "test.sloppy.http") { _ in
        HTTPRecordingLogHandler(recorder: recorder)
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
