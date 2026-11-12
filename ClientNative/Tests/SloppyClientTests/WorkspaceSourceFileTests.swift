import Foundation
import Testing
import SloppyClientCore
import SloppyFeatureChat
@testable import SloppyClient

@Suite("Workspace source file navigation", .serialized)
@MainActor
struct WorkspaceSourceFileTests {
    @Test func opensUsingTheConversationEndpointRatherThanTheMainEndpoint() throws {
        let mainAPI = SloppyAPIClient(baseURL: URL(string: "https://main.invalid")!)
        let originAPI = SloppyAPIClient(endpoint: .managed(relayURL: URL(string: "https://relay.invalid")!, targetDeviceID: UUID()))
        let notifications = SourceFileNavigationNotifications()
        let main = MainViewModel(endpoint: mainAPI.endpoint, settings: ClientSettings(),
            connectionMonitor: ConnectionMonitor(baseURL: mainAPI.baseURL), cacheStore: ClientCacheStore(path: ":memory:"),
            apiClient: mainAPI, responseNotificationScheduler: notifications, onOpenSettings: { _ in }, onOpenWorkspace: {})
        let origin = ChatScreenViewModel(apiClient: originAPI, cacheStore: ClientCacheStore(path: ":memory:"), settings: ClientSettings(),
            connectionMonitor: ConnectionMonitor(baseURL: originAPI.baseURL), responseNotificationScheduler: notifications, onOpenSettings: { _ in })
        defer { main.chatViewModel.closeSession(); origin.closeSession() }
        main.openSourceFile(.init(path: "/projects/project/workflows/flow"), from: origin)
        let workflow = try #require(main.workspaceDockState.selectedTab)
        #expect(workflow.workflowReference?.workflowID == "flow")
        #expect(workflow.workflowReference?.projectID == "project")
        #expect(workflow.workflowEndpoint == originAPI.endpoint)
        #expect(workflow.sourceFile == nil)
        main.openSourceFile(.init(path: "/projects/project/workflows/flow"), from: origin)
        #expect(main.workspaceDockState.selectedTab === workflow)
        #expect(main.workspaceDockState.tabs.count == 1)
        #expect(main.workspaceDockState.open(.files) !== workflow)
        main.openSourceFile(.init(path: "/remote/File.swift", line: 42), from: origin)
        let file = try #require(main.workspaceDockState.selectedTab?.sourceFile)
        #expect(file.apiClient.endpoint == originAPI.endpoint)
        #expect(file.apiClient.endpoint != mainAPI.endpoint)
        #expect(file.reference.line == 42)
        #expect(main.workspaceDockState.isPresented)
    }

    @Test func reusesFileTabAndKeepsOtherFilesAndTools() throws {
        let api = SloppyAPIClient(baseURL: URL(string: "https://file-test.invalid")!)
        let dock = WorkspaceDockState()
        let browser = dock.open(.browser)
        let first = dock.openSourceFile(.init(path: "Sources/First.swift", line: 10), apiClient: api, scope: .project("one"))
        let second = dock.openSourceFile(.init(path: "Sources/Second.swift", line: 20), apiClient: api, scope: .project("one"))
        dock.hide()
        let reopened = dock.openSourceFile(.init(path: "Sources/First.swift", line: 30), apiClient: api, scope: .project("one"))
        #expect(reopened === first)
        #expect(dock.tabs.count == 3)
        #expect(dock.isPresented)
        #expect(dock.selectedID == first.id)
        #expect(first.title == "First.swift")
        #expect(first.sourceFile?.reference.line == 30)
        #expect(second.sourceFile?.reference.line == 20)
        #expect(dock.tabs.contains { $0 === browser })
        let files = dock.open(.files)
        #expect(files.sourceFile == nil)
        #expect(files !== first && files !== second)
        dock.close(first.id)
        #expect(!dock.tabs.contains { $0 === first })
    }

    @Test func samePathOnDifferentServersOrProjectsHasSeparateTabs() {
        let api = SloppyAPIClient(baseURL: URL(string: "https://first.invalid")!)
        let remote = SloppyAPIClient(endpoint: .managed(relayURL: URL(string: "https://relay.invalid")!, targetDeviceID: UUID()))
        let dock = WorkspaceDockState()
        let ref = SourceFileReference(path: "File.swift", line: 1)
        dock.openSourceFile(ref, apiClient: api, scope: .project("one"))
        dock.openSourceFile(ref, apiClient: api, scope: .project("two"))
        dock.openSourceFile(ref, apiClient: remote, scope: .project("one"))
        #expect(dock.tabs.count == 3)
        #expect(dock.selectedTab?.sourceFile?.apiClient.endpoint == remote.endpoint)
    }

    @Test func loadsThroughOriginAPIAndNormalizesLines() async throws {
        let fixture = SourceFileFixture()
        let model = WorkspaceSourceFileViewModel(reference: .init(path: "/remote/File.swift", line: 2),
            apiClient: fixture.api, scope: .project("project"))
        await model.loadIfNeeded()
        #expect(model.lines == ["first", "second", "third", ""])
        #expect(model.targetLine == 2)
        #expect(model.errorMessage == nil)
        let request = try #require(fixture.requests.first)
        #expect(request.url?.path == "/v1/projects/project/files/content")
        #expect(URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "/remote/File.swift")
        model.navigate(to: .init(path: "/remote/File.swift", line: 999))
        await model.loadIfNeeded()
        #expect(model.targetLine == 4)
        #expect(model.isLineOutsideFile)
        #expect(fixture.requests.count == 1)
        model.reload()
        await model.loadIfNeeded()
        #expect(fixture.requests.count == 2)
        #expect(model.reference.line == 999)
        #expect(model.content != nil)
    }

    @Test func loadsLargeTextWithoutSizeError() async {
        let text = String(repeating: "large line\n", count: 220_000)
        let fixture = SourceFileFixture(content: text, delay: 0.1)
        let model = WorkspaceSourceFileViewModel(reference: .init(path: "/remote/File.swift"),
            apiClient: fixture.api, scope: .project("project"))
        let loading = Task { await model.loadIfNeeded() }
        for _ in 0..<100 {
            if model.isLoading { break }
            await Task.yield()
        }
        #expect(model.isLoading)
        await loading.value
        #expect(!model.isLoading)
        #expect(model.content?.content == text)
        #expect(model.lines.count == 220_001)
        #expect(model.errorMessage == nil)
    }

    @Test func decodesImageInsteadOfTreatingItAsSource() async throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6X8AAAAASUVORK5CYII=")!
        let fixture = SourceFileFixture(content: "", imageData: png)
        let model = WorkspaceSourceFileViewModel(reference: .init(path: "/remote/screen.png"),
            apiClient: fixture.api, scope: .project("project"))
        await model.loadIfNeeded()
        #expect(model.image != nil)
        #expect(model.lines.isEmpty)
        #expect(!model.isLoading)
        #expect(model.errorMessage == nil)
    }

    @Test func navigationDuringLoadKeepsRequestAndLatestLine() async {
        let fixture = SourceFileFixture(delay: 0.1)
        let model = WorkspaceSourceFileViewModel(reference: .init(path: "/remote/File.swift", line: 1),
            apiClient: fixture.api, scope: .project("project"))
        let load = Task { await model.loadIfNeeded() }
        for _ in 0..<100 {
            if model.isLoading { break }
            await Task.yield()
        }
        let revision = model.loadRevision
        model.navigate(to: .init(path: "/remote/File.swift", line: 3))
        await model.loadIfNeeded()
        #expect(model.loadRevision == revision)
        await load.value
        #expect(model.content != nil)
        #expect(model.targetLine == 3)
        #expect(!model.isLoading)
        #expect(fixture.requests.count == 1)
    }

    @Test func invalidImageShowsErrorAndStopsLoading() async {
        let fixture = SourceFileFixture(content: "", imageData: Data([0, 1, 2]))
        let model = WorkspaceSourceFileViewModel(reference: .init(path: "/remote/screen.png"),
            apiClient: fixture.api, scope: .project("project"))
        await model.loadIfNeeded()
        #expect(model.image == nil)
        #expect(model.errorMessage != nil)
        #expect(!model.isLoading)
    }

    @Test func agentWorkspaceAndFailureStayInPanel() async throws {
        let fixture = SourceFileFixture()
        let model = WorkspaceSourceFileViewModel(reference: .init(path: "missing.swift"),
            apiClient: fixture.api, scope: .agent("agent"))
        await model.loadIfNeeded()
        #expect(fixture.requests.first?.url?.path == "/v1/agents/agent/files/content")
        #expect(model.content == nil)
        #expect(model.errorMessage != nil)
        let unavailable = WorkspaceSourceFileViewModel(reference: .init(path: "File.swift"), apiClient: fixture.api, scope: .unavailable)
        await unavailable.loadIfNeeded()
        #expect(unavailable.errorMessage != nil)
        #expect(fixture.requests.count == 1)
    }

    @Test func pullToRefreshReloadsCachedFileAndPreservesItsLocation() async {
        let fixture = SourceFileFixture()
        let model = WorkspaceSourceFileViewModel(reference: .init(path: "/remote/File.swift", line: 2),
            apiClient: fixture.api, scope: .project("project"))
        await model.loadIfNeeded()
        await model.loadIfNeeded()
        #expect(fixture.requests.count == 1)
        await model.loadIfNeeded(force: true)
        #expect(fixture.requests.count == 2)
        #expect(model.reference.path == "/remote/File.swift")
        #expect(model.targetLine == 2)
        #expect(model.lines == ["first", "second", "third", ""])
        #expect(model.errorMessage == nil)
    }
}

@MainActor
private final class SourceFileNavigationNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}

final class SourceFileFixture: @unchecked Sendable {
    let api: SloppyAPIClient
    private let host = "source-file-\(UUID().uuidString).invalid"
    init(content: String = "first\r\nsecond\rthird\n", imageData: Data? = nil, delay: TimeInterval = 0) {
        SourceFileURLProtocol.register(content: content, imageData: imageData, delay: delay, host: host)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SourceFileURLProtocol.self]
        api = SloppyAPIClient(baseURL: URL(string: "https://\(host)")!, session: URLSession(configuration: config),
                              authSessionStore: AuthSessionStore(persistence: .memory))
    }
    var requests: [URLRequest] { SourceFileURLProtocol.requests(for: host) }
}

private final class SourceFileURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var captured: [URLRequest] = []
    nonisolated(unsafe) private static var contents: [String: String] = [:]
    nonisolated(unsafe) private static var images: [String: Data] = [:]
    nonisolated(unsafe) private static var delays: [String: TimeInterval] = [:]
    static func register(content: String, imageData: Data?, delay: TimeInterval, host: String) {
        lock.withLock { contents[host] = content; images[host] = imageData; delays[host] = delay }
    }
    static func requests(for host: String) -> [URLRequest] {
        lock.withLock { captured.filter { $0.url?.host == host } }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.withLock { Self.captured.append(request) }
        guard let url = request.url else { return }
        let delay = Self.lock.withLock { Self.delays[url.host ?? ""] ?? 0 }
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        let missing = url.query?.contains("missing.swift") == true
        let response = HTTPURLResponse(url: url, statusCode: missing ? 404 : 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        let text = Self.lock.withLock { Self.contents[url.host ?? ""] ?? "" }
        let image = Self.lock.withLock { Self.images[url.host ?? ""] }
        let content = ProjectFileContentResponse(path: "/remote/File.swift", content: text, sizeBytes: image?.count ?? text.utf8.count, imageData: image, mediaType: image == nil ? nil : "image/png")
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: missing ? Data("{}".utf8) : (try! JSONEncoder().encode(content)))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
