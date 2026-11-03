import Foundation
import SloppyClientCore
import Testing
@testable import SloppyFeatureChat

@Suite("Chat session mutations", .serialized)
@MainActor
struct ChatSessionMutationTests {
    @Test("closing a chat cancels an approval read before its URLSession is invalidated")
    func closeCancelsQueuedApprovalRead() async throws {
        let fixture = try MutationFixture.make()
        fixture.model.restoreApprovalMode(agentId: "agent", sessionId: "source")
        let read = try #require(fixture.model.approvalModeLoadTask)
        fixture.finish()
        #expect(!fixture.model.isLoadingApprovalMode)
        await read.value
        #expect(fixture.model.approvalModeErrorMessage == nil)
        #expect(fixture.model.approvalModeLoadTask == nil)
    }

    @Test("forking a response sends an immutable history boundary and preserves its scope")
    func forkUsesSelectedResponse() async throws {
        let fixture = try MutationFixture.make()
        defer { fixture.finish() }
        let response = ChatMessage(id: "selected-response", role: .assistant,
            segments: [.init(kind: .text, text: "An earlier response")])
        fixture.model.forkSession(from: response)
        try await fixture.wait { !fixture.model.isForkingSession && fixture.model.selectedSessionId == "fork" }
        let payload = try #require(fixture.server.createdPayload)
        #expect(payload["forkFromSessionId"] as? String == "source")
        #expect(payload["forkThroughMessageId"] as? String == response.id)
        #expect(payload["parentSessionId"] == nil)
        #expect(payload["projectId"] as? String == "project")
        #expect(payload["taskId"] as? String == "task")
        #expect(payload["workspaceId"] as? String == "workspace")
        #expect(payload["separateChat"] as? Bool == true)
        #expect(fixture.model.sendErrorMessage == nil)
    }

    @Test("deleting a chat cannot restore it from cache when the next refresh is offline")
    func deletedChatStaysDeletedOffline() async throws {
        let fixture = try MutationFixture.make()
        defer { fixture.finish() }
        let summary = try #require(fixture.model.sessions.first)
        let detail = ChatSessionDetail(summary: summary, messages: [
            .init(id: "cached-message", role: .assistant, segments: [.init(kind: .text, text: "deletedchattext")])
        ])
        await fixture.cache.cacheSessions(agentId: summary.agentId, projectId: nil, sessions: [summary])
        await fixture.cache.cacheSessionDetail(agentId: summary.agentId, detail: detail)
        fixture.model.deleteSession(summary)
        try await fixture.wait { fixture.model.sessions.isEmpty }
        #expect(fixture.server.deleted)
        fixture.server.offline = true
        await fixture.model.loadSessions(for: fixture.agent)
        #expect(fixture.model.sessions.isEmpty)
        #expect(await fixture.cache.loadSessionDetail(agentId: summary.agentId, sessionId: summary.id) == nil)
        #expect(await fixture.cache.searchMessages(query: "deletedchattext").isEmpty)
    }
}

@MainActor
private struct MutationFixture {
    let model: ChatScreenViewModel
    let server: MutationServer
    let cache: ClientCacheStore
    let agent: APIAgentRecord
    let session: URLSession
    let settings: ClientSettings
    let previous: (String?, String?, String?)

    static func make() throws -> Self {
        let server = MutationServer()
        MutationURLProtocol.install(server)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MutationURLProtocol.self]
        let session = URLSession(configuration: config)
        let api = SloppyAPIClient(baseURL: try #require(URL(string: "https://chat-mutations.invalid")),
            session: session, authSessionStore: AuthSessionStore(persistence: .memory))
        let cache = ClientCacheStore(path: ":memory:")
        let settings = ClientSettings()
        let previous = (settings.lastAgentId, settings.lastSessionId, settings.lastProjectId)
        let model = ChatScreenViewModel(apiClient: api, cacheStore: cache, settings: settings,
            connectionMonitor: ConnectionMonitor(baseURL: api.baseURL), restoresLastSession: false,
            responseNotificationScheduler: MutationNotifications(),
            sessionStreamProvider: { _, _ in AsyncStream { $0.finish() } }, onOpenSettings: { _ in })
        let agent = APIAgentRecord(id: "agent", displayName: "Agent")
        model.agents = [agent]
        model.selectedAgent = agent
        model.sessions = [.init(id: "source", agentId: "agent", title: "Source", projectId: "project", taskId: "task", workspaceId: "workspace")]
        model.selectedSessionId = "source"
        return .init(model: model, server: server, cache: cache, agent: agent, session: session,
                     settings: settings, previous: previous)
    }

    func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw URLError(.timedOut)
    }

    func finish() {
        model.closeSession()
        session.invalidateAndCancel()
        MutationURLProtocol.install(nil)
        settings.lastAgentId = previous.0
        settings.lastSessionId = previous.1
        settings.lastProjectId = previous.2
    }
}

@MainActor
private final class MutationNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}

private final class MutationServer: @unchecked Sendable {
    private let lock = NSLock()
    private var payload: [String: Any]?
    private var didDelete = false
    private var isOffline = false
    var createdPayload: [String: Any]? { lock.withLock { payload } }
    var deleted: Bool { lock.withLock { didDelete } }
    var offline: Bool {
        get { lock.withLock { isOffline } }
        set { lock.withLock { isOffline = newValue } }
    }

    func respond(to request: URLRequest) throws -> (HTTPURLResponse, Data) {
        if offline { throw URLError(.notConnectedToInternet) }
        let path = request.url!.path
        var body = "{}"
        var status = 200
        if request.httpMethod == "DELETE" {
            lock.withLock { didDelete = true }
        } else if request.httpMethod == "POST", path.hasSuffix("/sessions") {
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(buffer, count: count)
                }
            }
            let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            lock.withLock { payload = decoded }
            body = #"{"id":"fork","agentId":"agent","title":"Fork","messageCount":2,"updatedAt":"2026-10-31T12:00:00Z","kind":"chat","projectId":"project","workspaceId":"workspace"}"#
        } else if path.hasSuffix("/sessions/fork") {
            body = #"{"summary":{"id":"fork","agentId":"agent","title":"Fork","messageCount":0,"updatedAt":"2026-10-31T12:00:00Z","kind":"chat"},"messages":[]}"#
        } else {
            status = 404
        }
        return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                headerFields: ["Content-Type": "application/json"])!, Data(body.utf8))
    }
}

private final class MutationURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var server: MutationServer?
    static func install(_ value: MutationServer?) { lock.withLock { server = value } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let server = Self.lock.withLock({ Self.server }) else { throw URLError(.cancelled) }
            let (response, data) = try server.respond(to: request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
