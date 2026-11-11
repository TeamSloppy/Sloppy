import Foundation
import SloppyClientCore
import Testing
@testable import SloppyFeatureChat

@Suite("Chat bootstrap independence", .serialized)
@MainActor
struct ChatBootstrapIndependenceTests {
    @Test(arguments: [200, 503])
    func fastAgentCatalogAppearsBeforeSlowAgentCompletes(slowStatus: Int) async throws {
        let gate = CatalogGate.shared
        gate.reset(status: slowStatus)
        defer { gate.release() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CatalogGateURLProtocol.self]
        let api = SloppyAPIClient(baseURL: URL(string: "http://catalog.invalid")!,
                                  session: URLSession(configuration: configuration),
                                  authSessionStore: AuthSessionStore(persistence: .memory))
        let settings = ClientSettings()
        let previousAgent = settings.lastAgentId, previousSession = settings.lastSessionId
        let previousProject = settings.lastProjectId
        settings.lastProjectId = nil
        settings.lastSessionId = nil
        defer {
            settings.lastAgentId = previousAgent
            settings.lastSessionId = previousSession
            settings.lastProjectId = previousProject
        }
        let cache = ClientCacheStore(path: ":memory:")
        await cache.cacheSessions(agentId: "slow", projectId: nil, sessions: [
            ChatSessionSummary(id: "cached-slow", agentId: "slow", title: "Cached slow")
        ])
        let model = ChatScreenViewModel(apiClient: api, cacheStore: cache,
                                        settings: settings, connectionMonitor: ConnectionMonitor(baseURL: api.baseURL),
                                        restoresLastSession: false, loadsGlobalSessionCatalog: true,
                                        responseNotificationScheduler: BootstrapNotifications(), onOpenSettings: { _ in })
        defer { model.closeSession() }
        model.loadInitialData()
        let deadline = ContinuousClock.now + .seconds(1)
        while !model.sessionCatalog.contains(where: { $0.id == "fast-chat" }), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        // Slow HTTP response is held by a gate, not a wall-clock delay.
        #expect(model.sessionCatalog.contains { $0.id == "fast-chat" })
        #expect(!model.sessionCatalog.contains { $0.id == "slow-chat" })
        #expect(model.sessionCatalog.contains { $0.id == "cached-slow" })
        gate.release()
        await model.waitForInitialData()
        #expect(Set(model.sessionCatalog.map(\.id)) == ["fast-chat", slowStatus == 200 ? "slow-chat" : "cached-slow"])
    }

    @Test func chatsAndSubmissionBecomeAvailableWhileModelDiscoveryIsStillPending() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BootstrapURLProtocol.self]
        let api = SloppyAPIClient(baseURL: URL(string: "http://bootstrap.invalid")!,
                                  session: URLSession(configuration: configuration),
                                  authSessionStore: AuthSessionStore(persistence: .memory))
        let settings = ClientSettings()
        let previousAgent = settings.lastAgentId, previousSession = settings.lastSessionId
        let previousProject = settings.lastProjectId
        settings.lastProjectId = nil
        settings.lastSessionId = nil
        defer {
            settings.lastAgentId = previousAgent
            settings.lastSessionId = previousSession
            settings.lastProjectId = previousProject
        }
        let model = ChatScreenViewModel(apiClient: api, cacheStore: ClientCacheStore(path: ":memory:"),
                                        settings: settings, connectionMonitor: ConnectionMonitor(baseURL: api.baseURL),
                                        loadsGlobalSessionCatalog: true,
                                        responseNotificationScheduler: BootstrapNotifications(), onOpenSettings: { _ in })
        defer { model.closeSession() }
        model.loadInitialData()
        let deadline = ContinuousClock.now + .seconds(1)
        while (model.sessionCatalog.isEmpty || model.projects.isEmpty), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.canSubmitMessage)
        #expect(model.sessionCatalog.map(\.id) == ["existing-chat"])
        #expect(model.availableModels.isEmpty)
        #expect(model.projects.map(\.id) == ["workspace"])
        #expect(!model.sendMessage(content: ""))
        await model.waitForInitialData()
    }
}

@MainActor
private final class BootstrapNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}

private final class BootstrapURLProtocol: URLProtocol, @unchecked Sendable {
    private var responseWork: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data: Data
        switch url.path {
        case "/v1/agents":
            data = (try? encoder.encode([APIAgentRecord(id: "first", displayName: "First")])) ?? Data()
        case "/v1/projects":
            data = (try? encoder.encode([APIProjectRecord(id: "workspace", name: "Workspace", kind: .workspace)])) ?? Data()
        case "/v1/agents/first/sessions", "/v1/agent-sessions":
            data = (try? encoder.encode([ChatSessionSummary(id: "existing-chat", agentId: "first", title: "Existing chat")])) ?? Data()
        default:
            data = Data("[]".utf8)
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                          headerFields: ["Content-Type": "application/json"]) else { return }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        responseWork = work
        DispatchQueue.global().asyncAfter(deadline: .now() + (url.path == "/v1/providers/models" ? 2 : 0), execute: work)
    }
    override func stopLoading() { responseWork?.cancel() }
}

private final class CatalogGate: @unchecked Sendable {
    static let shared = CatalogGate()
    private let lock = NSLock()
    private var released = false
    private var responseStatus = 200
    var status: Int { lock.withLock { responseStatus } }
    private var pending: [@Sendable () -> Void] = []
    func reset(status: Int) { lock.withLock { released = false; pending = []; responseStatus = status } }
    func hold(_ response: @escaping @Sendable () -> Void) {
        let run = lock.withLock {
            if released { return true }
            pending.append(response)
            return false
        }
        if run { response() }
    }
    func release() {
        let responses = lock.withLock {
            released = true
            let result = pending
            pending = []
            return result
        }
        for response in responses { response() }
    }
}

private final class CatalogGateURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data: Data
        let agent = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "agentId" }?.value
        switch url.path {
        case "/v1/agents":
            data = (try? encoder.encode([APIAgentRecord(id: "fast", displayName: "Fast"), APIAgentRecord(id: "slow", displayName: "Slow")])) ?? Data()
        case "/v1/agent-sessions":
            let id = agent ?? "fast"
            data = (try? encoder.encode([ChatSessionSummary(id: "\(id)-chat", agentId: id, title: id)])) ?? Data()
        default: data = Data("[]".utf8)
        }
        let response: @Sendable () -> Void = { [self] in
            guard let http = HTTPURLResponse(url: url, statusCode: agent == "slow" ? CatalogGate.shared.status : 200, httpVersion: nil,
                                            headerFields: ["Content-Type": "application/json"]) else { return }
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        if url.path == "/v1/agent-sessions", agent == "slow" { CatalogGate.shared.hold(response) }
        else { response() }
    }
    override func stopLoading() {}
}
