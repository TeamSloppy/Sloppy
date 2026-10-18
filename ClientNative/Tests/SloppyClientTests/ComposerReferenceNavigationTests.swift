import Foundation
import SloppyClientCore
import SloppyFeatureChat
import Testing
@testable import SloppyClient

@Suite("Composer reference navigation", .serialized)
@MainActor
struct ComposerReferenceNavigationTests {
    @Test func referencesOpenScopedSideTabsWithoutReplacingPrimaryChat() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReferenceNavigationURLProtocol.self]
        let api = SloppyAPIClient(baseURL: try #require(URL(string: "http://reference-navigation.invalid")),
            session: URLSession(configuration: configuration), authSessionStore: AuthSessionStore(persistence: .memory))
        let settings = ClientSettings()
        let previous = (settings.lastAgentId, settings.lastProjectId, settings.lastSessionId)
        let model = MainViewModel(endpoint: api.endpoint, settings: settings,
            connectionMonitor: ConnectionMonitor(baseURL: api.baseURL), cacheStore: ClientCacheStore(path: ":memory:"),
            apiClient: api, responseNotificationScheduler: ReferenceNavigationNotifications(),
            onOpenSettings: { _ in }, onOpenWorkspace: {})
        model.createBlankChatTab()
        let primaryID = try #require(model.selectedTabID)
        let primary = try #require(model.tabStates[primaryID]?.chatState?.viewModel)
        await primary.waitForInitialData()
        primary.selectedSessionId = "primary"
        primary.composerDraft.text = "Keep this draft"
        defer {
            for tab in model.workspaceDockState.tabs { tab.chat?.closeSession() }
            primary.closeSession()
            model.chatViewModel.closeSession()
            settings.lastAgentId = previous.0
            settings.lastProjectId = previous.1
            settings.lastSessionId = previous.2
        }
        let session = ChatComposerReference(rawText: "session", title: "Another discussion",
            target: .session(agentId: "reader", sessionId: "referenced"))
        model.openComposerReference(session, from: primary)
        let dock = model.workspaceDockState
        let tab = try #require(dock.selectedTab)
        let side = try #require(tab.chat)
        await side.waitForInitialData()
        #expect(side.selectedSessionId == "referenced")
        #expect(primary.selectedSessionId == "primary")
        #expect(primary.composerDraft.text == "Keep this draft")
        #expect(model.selectedTabID == primaryID)
        model.openComposerReference(session, from: primary)
        #expect(dock.selectedID == tab.id)
        #expect(dock.tabs.count == 1)

        let command = ChatComposerReference(rawText: "/abort", title: "/abort", target: .command(agentId: "reader", name: "abort"))
        model.openComposerReference(command, from: primary)
        let commandPreview = try #require(dock.selectedTab?.referencePreview)
        await commandPreview.load()
        #expect(commandPreview.detail == "Abort current processing")
        #expect(commandPreview.errorMessage == nil)
        let commandTab = dock.selectedID
        model.openComposerReference(command, from: primary)
        #expect(dock.selectedID == commandTab)
        let files = model.openWorkspaceDockTab(.files)
        #expect(files.id != commandTab)
        #expect(files.referencePreview == nil)

        let skill = ChatComposerReference(rawText: "@review", title: "Code review", target: .skill(agentId: "reader", skillId: "review"))
        model.openComposerReference(skill, from: primary)
        let skillPreview = try #require(dock.selectedTab?.referencePreview)
        await skillPreview.load()
        #expect(skillPreview.sourcePath == "skills/review/SKILL.md")
        #expect(skillPreview.document == "# Code review\nRead this skill.")
        #expect(skillPreview.errorMessage == nil)

        let remote = SloppyInstanceEndpoint.direct(baseURL: try #require(URL(string: "http://other-reference.invalid")))
        let file = ChatComposerReference(rawText: "@Package.swift", title: "Package.swift",
            target: .file(projectId: "other-project", path: "Package.swift"), endpoint: remote)
        model.openComposerReference(file, from: primary)
        let source = try #require(dock.selectedTab?.sourceFile)
        #expect(source.apiClient.endpoint == remote)
        #expect(source.scope == .project("other-project"))
        #expect(source.reference.path == "Package.swift")
        #expect(model.selectedTabID == primaryID)
        #expect(primary.composerDraft.text == "Keep this draft")
    }
}

@MainActor
private final class ReferenceNavigationNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}

private final class ReferenceNavigationURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "reference-navigation.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let data: Data
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        switch url.path {
        case "/v1/agents":
            data = (try? encoder.encode([APIAgentRecord(id: "reader", displayName: "Reader")])) ?? Data()
        case "/v1/agents/reader/chat-slash-commands":
            data = (try? encoder.encode(AgentChatSlashCommandsResponse(commands: [
                .init(source: "builtin", name: "abort", description: "Abort current processing"),
            ]))) ?? Data()
        case "/v1/agents/reader/skills":
            data = (try? encoder.encode(AgentSkillsResponse(agentId: "reader", skills: [
                .init(id: "review", owner: "", repo: "", name: "Code review", description: "Review source",
                      localPath: "/remote/reader/skills/review"),
            ], skillsPath: "/remote/reader/skills"))) ?? Data()
        case "/v1/agents/reader/files/content":
            data = (try? encoder.encode(ProjectFileContentResponse(path: "skills/review/SKILL.md",
                content: "# Code review\nRead this skill.", sizeBytes: 30))) ?? Data()
        case "/v1/agents/reader/sessions/referenced":
            let summary = ChatSessionSummary(id: "referenced", agentId: "reader", title: "Another discussion")
            let encoded = (try? encoder.encode(summary)) ?? Data()
            let object = (try? JSONSerialization.jsonObject(with: encoded)) ?? [:]
            data = (try? JSONSerialization.data(withJSONObject: ["summary": object, "events": []])) ?? Data()
        default: data = Data("[]".utf8)
        }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                            headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
