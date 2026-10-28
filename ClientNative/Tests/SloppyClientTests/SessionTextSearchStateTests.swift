import Foundation
import Testing
import SloppyClientCore
@testable import SloppyClient

@MainActor
struct SessionTextSearchStateTests {
    @Test func searchesMessageHistoryAcrossChatsWithoutTitleOrCurrentSessionFilters() async throws {
        let fixture = try GlobalSearchFixture(response: .init(items: [hit("one", agent: "first", session: "old-chat"),
            hit("two", agent: "second", session: "other-chat")], hasMore: false, indexing: false,
            indexedSources: 2, failedSources: 0, durationMs: 1))
        let state = SessionTextSearchState()
        await state.search("needle", endpoints: [fixture.api.endpoint], primaryClient: fixture.api)
        #expect(Set(state.items.map { $0.hit.sessionId }) == ["old-chat", "other-chat"])
        #expect(Set(state.items.compactMap { $0.hit.agentId }) == ["first", "second"])
        #expect(state.items.allSatisfy { !$0.hit.title.contains("needle") })
        #expect(state.items.allSatisfy { $0.endpoint == fixture.api.endpoint })
        let url = try #require(fixture.requests.first?.url)
        #expect(url.path == "/v1/search")
        let parameters = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(parameters.first { $0.name == "q" }?.value == "needle")
        #expect(parameters.allSatisfy { !["agentId", "sessionId", "projectId"].contains($0.name) })
        #expect(!state.isLoading)
    }

    @Test func clearingTheQueryClearsResultsWithoutAnotherRequest() async throws {
        let fixture = try GlobalSearchFixture(response: .init(items: [hit("one", agent: "first", session: "old-chat")],
            hasMore: true, indexing: false, indexedSources: 1, failedSources: 2, durationMs: 1))
        let state = SessionTextSearchState()
        await state.search("needle", endpoints: [fixture.api.endpoint], primaryClient: fixture.api)
        #expect(state.hasMore)
        #expect(state.failedSources == 2)
        await state.search(" \n ", endpoints: [fixture.api.endpoint], primaryClient: fixture.api)
        #expect(state.items.isEmpty)
        #expect(!state.isLoading)
        #expect(!state.hasMore)
        #expect(state.failedSources == 0)
        #expect(fixture.requests.count == 1)
    }

    @Test func failedSearchIsVisibleAndCanBeRetried() async throws {
        let fixture = try GlobalSearchFixture(response: .init(items: [], hasMore: false, indexing: false,
            indexedSources: 0, failedSources: 0, durationMs: 1), status: 503)
        let state = SessionTextSearchState()
        await state.search("needle", endpoints: [fixture.api.endpoint], primaryClient: fixture.api)
        #expect(state.error != nil)
        #expect(!state.isLoading)
        #expect(state.items.isEmpty)
        fixture.setStatus(200)
        await state.search("needle", endpoints: [fixture.api.endpoint], primaryClient: fixture.api)
        #expect(state.error == nil)
        #expect(fixture.requests.count == 2)
    }

    private func hit(_ id: String, agent: String, session: String) -> TextSearchHit {
        .init(id: id, source: "agent", agentId: agent, sessionId: session, projectId: nil,
            title: "Release checklist", eventId: id, messageId: id, before: "128", kind: "message",
            role: "assistant", createdAt: "2026-10-26T12:00:00Z", snippet: "An older message contains needle.")
    }
}

private final class GlobalSearchFixture: @unchecked Sendable {
    let api: SloppyAPIClient
    private let host = "search-\(UUID().uuidString).invalid"

    init(response: TextSearchResponse, status: Int = 200) throws {
        GlobalSearchURLProtocol.register(host: host, data: try JSONEncoder().encode(response), status: status)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GlobalSearchURLProtocol.self]
        api = SloppyAPIClient(baseURL: URL(string: "https://\(host)")!, session: URLSession(configuration: configuration),
            authSessionStore: AuthSessionStore(persistence: .memory))
    }

    var requests: [URLRequest] { GlobalSearchURLProtocol.requests(host: host) }
    func setStatus(_ status: Int) { GlobalSearchURLProtocol.setStatus(status, host: host) }
}

private final class GlobalSearchURLProtocol: URLProtocol, @unchecked Sendable {
    private struct Reply {
        let data: Data
        var status: Int
        var requests: [URLRequest] = []
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [String: Reply] = [:]

    static func register(host: String, data: Data, status: Int) {
        lock.withLock { replies[host] = Reply(data: data, status: status) }
    }
    static func requests(host: String) -> [URLRequest] { lock.withLock { replies[host]?.requests ?? [] } }
    static func setStatus(_ status: Int, host: String) { lock.withLock { replies[host]?.status = status } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let reply = Self.lock.withLock {
            Self.replies[url.host ?? ""]?.requests.append(request)
            return Self.replies[url.host ?? ""]
        }
        guard let reply, let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
