import Foundation
import SloppyClientCore
import SloppyFeatureChat
import SloppyUITestSupport
import Testing
@testable import SloppyClient

@Suite("Browser agent chat", .serialized, .appKitIsolation)
@MainActor
struct BrowserAgentChatTests {
    @Test func launcherPromptSurvivesBootstrapAndDoesNotSendAutomatically() async throws {
        let fixture = try BrowserAgentChatTestFixture()
        defer { fixture.close() }
        fixture.state.show(prompt: "Compare these pages")
        await fixture.chat.waitForInitialData()
        #expect(fixture.state.panel.isPresented)
        #expect(fixture.chat.selectedAgent?.id == "agent")
        #expect(fixture.chat.selectedSessionId == nil)
        #expect(fixture.chat.composerDraft.text == "Compare these pages")
        #expect(fixture.probe.posts.isEmpty)
        fixture.state.hide()
        fixture.state.show(prompt: "Keep the comparison short")
        #expect(fixture.chat.composerDraft.text.contains("Compare these pages"))
        #expect(fixture.chat.composerDraft.text.contains("Keep the comparison short"))
        #expect(fixture.probe.posts.isEmpty)
    }

    @Test func hidingKeepsTheDraftAndRejectsStaleSelectionMenus() async throws {
        let fixture = try BrowserAgentChatTestFixture()
        defer { fixture.close() }
        fixture.state.show()
        await fixture.chat.waitForInitialData()
        fixture.chat.useStarterPrompt("Keep my question")
        let quote = ChatComposerQuote(text: "A selected passage", browserSource:
            .init(url: try #require(URL(string: "https://example.com/article")), title: "Article"))
        let old = try #require(fixture.state.makeAnnotationReceiver())
        #expect(old(quote))
        fixture.state.hide()
        #expect(fixture.state.makeAnnotationReceiver() == nil)
        #expect(!old(quote))
        fixture.state.show()
        #expect(!old(quote))
        #expect(fixture.chat.composerDraft.text == "Keep my question")
        #expect(fixture.chat.composerQuotes == [quote])
        let current = try #require(fixture.state.makeAnnotationReceiver())
        fixture.chat.selectedSessionId = "other-session"
        #expect(!current(quote))
    }

    @Test func explicitSendCreatesABrowserConversationAndReceivesAReply() async throws {
        let fixture = try BrowserAgentChatTestFixture()
        defer { fixture.close() }
        fixture.state.show(prompt: "Help me understand this page")
        await fixture.chat.waitForInitialData()
        #expect(fixture.chat.sendMessage(content: fixture.chat.composerDraft.text))
        for _ in 0..<200 {
            if fixture.chat.messages.contains(where: { $0.role == .assistant }) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(fixture.chat.selectedSessionId == "browse-session")
        #expect(fixture.probe.posts == ["Help me understand this page"])
        #expect(fixture.chat.messages.contains { $0.role == .assistant })
        #expect(fixture.chat.composerDraft.text.isEmpty)
        #expect(fixture.state.panel.isPresented)
    }
}

@MainActor
final class BrowserAgentChatTestFixture {
    let api: SloppyAPIClient
    let chat: ChatScreenViewModel
    let state: BrowserAgentChatState
    let probe = BrowserAgentChatTestProbe()
    let settings = ClientSettings()
    private let host: String
    private let previousSelection: (String?, String?, String?)

    init() throws {
        host = UUID().uuidString.lowercased() + ".browse-chat.invalid"
        previousSelection = (settings.lastAgentId, settings.lastSessionId, settings.lastProjectId)
        BrowserAgentChatTestProtocol.install(probe, host: host)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BrowserAgentChatTestProtocol.self]
        let url = try #require(URL(string: "https://\(host)"))
        api = SloppyAPIClient(baseURL: url, session: URLSession(configuration: configuration),
            authSessionStore: AuthSessionStore(persistence: .memory))
        chat = ChatScreenViewModel(apiClient: api, cacheStore: ClientCacheStore(path: ":memory:"),
            settings: settings, connectionMonitor: ConnectionMonitor(baseURL: url), restoresLastSession: false,
            responseNotificationScheduler: BrowserAgentChatTestNotifications(),
            sessionStreamProvider: { _, _ in AsyncStream { $0.finish() } }, onOpenSettings: { _ in })
        chat.applyNavigationRequest(.init(id: 1, context: .blank))
        state = BrowserAgentChatState(chat: chat, apiClient: api)
    }

    func close() {
        state.stopBrowserConnection()
        chat.closeSession()
        settings.lastAgentId = previousSelection.0
        settings.lastSessionId = previousSelection.1
        settings.lastProjectId = previousSelection.2
        BrowserAgentChatTestProtocol.install(nil, host: host)
    }
}

final class BrowserAgentChatTestProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [String] = []
    private var clientMessageID = "user"
    var posts: [String] { lock.withLock { sent } }

    func response(_ request: URLRequest, body: Data) throws -> Data {
        let path = request.url?.path ?? ""
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let summary = ChatSessionSummary(id: "browse-session", agentId: "agent", title: "Browse")
        if path == "/v1/config/chat-approval-default" || path.hasSuffix("/approval-policy") {
            return try encoder.encode(ChatApprovalPolicy(mode: .askForApproval))
        }
        if path == "/v1/agents" { return try encoder.encode([APIAgentRecord(id: "agent", displayName: "Agent")]) }
        if path.hasSuffix("/sessions"), request.httpMethod == "POST" { return try encoder.encode(summary) }
        if path.hasSuffix("/messages"), request.httpMethod == "POST" {
            let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            if let content = payload?["content"] as? String {
                lock.withLock {
                    sent.append(content)
                    clientMessageID = payload?["clientMessageId"] as? String ?? "user"
                }
            }
            return try encoder.encode(["summary": summary])
        }
        if path.hasSuffix("/browse-session") {
            let user = lock.withLock { (sent.last, clientMessageID) }
            let messages: [ChatMessage] = user.0.map { content in [
                .init(id: user.1, role: .user, segments: [.init(kind: .text, text: content)]),
                .init(id: "reply", role: .assistant, segments: [.init(kind: .text, text: "Here is the page summary.")])
            ] } ?? []
            let summaryJSON = try JSONSerialization.jsonObject(with: encoder.encode(summary))
            let messagesJSON = try JSONSerialization.jsonObject(with: encoder.encode(messages))
            let events: [[String: Any]] = messages.isEmpty ? [] : [
                ["id": "done", "type": "run_status", "runStatus": ["stage": "done", "label": "Done"]]
            ]
            return try JSONSerialization.data(withJSONObject: ["summary": summaryJSON, "messages": messagesJSON, "events": events])
        }
        if path.hasSuffix("/poll") { return Data("{\"commands\":[]}".utf8) }
        if path.contains("workspace-browser") { return Data("{}".utf8) }
        if path == "/v1/tool-approvals/pending" || path.hasSuffix("/sessions")
            || path == "/v1/projects" || path == "/v1/providers/models" { return Data("[]".utf8) }
        return Data("{}".utf8)
    }
}

private final class BrowserAgentChatTestProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var probes: [String: BrowserAgentChatTestProbe] = [:]

    static func install(_ probe: BrowserAgentChatTestProbe?, host: String) { lock.withLock { probes[host] = probe } }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".browse-chat.invalid") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let url = request.url, let host = url.host,
                  let probe = Self.lock.withLock({ Self.probes[host] }),
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                      headerFields: ["Content-Type": "application/json"]) else { throw URLError(.badServerResponse) }
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            let data = try probe.response(request, body: body)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
private final class BrowserAgentChatTestNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}
