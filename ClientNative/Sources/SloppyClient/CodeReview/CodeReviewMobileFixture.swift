#if DEBUG && os(iOS)
import Foundation
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureAgents
import SloppyFeatureChat
import SloppyFeatureSettings
import SwiftUI

/// Isolated QA entry point; no live account, chat or model is used.
@MainActor
struct CodeReviewMobileFixture: View {
    private let item = CodeReviewItem(id: "github:team/repo#42", providerId: "github", providerName: "GitHub",
        repository: "team/repo", number: 42, title: "Keep cancellation and review feedback scoped to the working task",
        url: "https://example.invalid/pr/42")
    private let api: SloppyAPIClient
    @State private var submitted: CodeReviewSubmission?
    @State private var selectedTab = 2
    @State private var isShowingSettings = ProcessInfo.processInfo.arguments.contains("--settings-ui-fixture")
    @State private var chat: ChatScreenViewModel
    @State private var inboxSearchText = ""
    @State private var searchPresentation: IOSInboxSearchPresentation?
    @State private var isSearchChatPresented = false
    @State private var attention = AttentionInbox(fetchAgents: { [] }, fetchInbox: { _ in .init(findings: []) },
        updateFinding: { _, _, _ in throw APIError.invalidResponse })

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodeReviewFixtureURLProtocol.self]
        api = SloppyAPIClient(baseURL: URL(string: "https://mobile-review-ui.invalid")!,
            session: URLSession(configuration: configuration), authSessionStore: AuthSessionStore(persistence: .memory))
        _chat = State(initialValue: ChatScreenViewModel(apiClient: api, cacheStore: ClientCacheStore(path: ":memory:"),
            settings: ClientSettings(), connectionMonitor: ConnectionMonitor(baseURL: api.baseURL),
            restoresLastSession: false, onOpenSettings: { _ in }))
        if ProcessInfo.processInfo.arguments.contains("--composer-ui-fixture") { _selectedTab = State(initialValue: 0) }
    }

    private var review: some View {
        NavigationStack {
            PullRequestsScreen(apiClient: api, onLinkChat: { _, _ in },
                onSendReview: { detail, submission in
                    _ = try await api.sendCodeReview(detail.item, agentId: "qa", submission: submission)
                    submitted = submission
                })

        }
    }

    @ViewBuilder
    private var inboxContent: some View {
        let query = inboxSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            ScrollView { Text("All").font(.largeTitle.bold()).frame(maxWidth: .infinity, alignment: .leading).padding(20) }
        } else {
            IOSInboxSearchResults(query: query, sessions: [], projects: [], endpoints: [api.endpoint], apiClient: api,
                onOpenSession: { session in
                    chat.openSessionFromSummary(session)
                    inboxSearchText = ""
                    isSearchChatPresented = true
                },
                onOpenMessage: { searchPresentation = .init(query: query, selected: $0) },
                onSearchText: { searchPresentation = .init(query: query) },
                onOpenProject: { _ in })
        }
    }

    private func openSearchSession(_ item: LocatedTextSearchHit) {
        guard let agentID = item.hit.agentId else { return }
        chat.openSessionFromSummary(.init(id: item.hit.sessionId, agentId: agentID, title: item.hit.title))
        inboxSearchText = ""
        isSearchChatPresented = true
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Inbox", systemImage: "tray", value: 0) {
                NavigationStack {
                    inboxContent
                        .mobileScreenBackground()
                        .navigationTitle("Inbox")
                        .searchable(text: $inboxSearchText, placement: .toolbar, prompt: "Search all messages and projects")
                        .navigationDestination(isPresented: $isSearchChatPresented) {
                            ChatScreen(viewModel: chat, showsContextToolbar: false)
                                .onDisappear { chat.closeSession() }
                        }
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Settings", systemImage: "gearshape") {
                                    isShowingSettings = true
                                }
                                .labelStyle(.iconOnly)
                                .accessibilityIdentifier("inbox.settings")
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Search all chats", systemImage: "text.magnifyingglass") {
                                    searchPresentation = .init(query: inboxSearchText)
                                }
                            }
                        }
                }
                .modifier(IOSComposerContainer(composer: {
                    AnyView(ChatComposerOverlay(viewModel: chat, contentWidth: ChatComposerView.panelWidth,
                        composerBottomInset: 8, tabs: [], tabActions: nil))
                }, viewModel: chat))
            }
            Tab("Attention", systemImage: "bell.badge", value: 1) {
                NavigationStack { AttentionScreen(inbox: attention) }
            }
            Tab("Pull Requests", systemImage: "arrow.triangle.branch", value: 2) { review }
            Tab("Workspace", systemImage: "square.grid.2x2", value: 4) {
                Color.clear.mobileScreenBackground()
            }
        }
        .fullScreenCover(isPresented: $isShowingSettings) {
            SettingsScreen(onDismiss: { isShowingSettings = false }, apiClient: api)
                .theme(.sloppyDark)
                .preferredColorScheme(.dark)
        }
        .sheet(item: $searchPresentation) { presentation in
            SessionTextSearchView(endpoints: [api.endpoint], apiClient: api, onOpenSession: openSearchSession,
                query: presentation.query, selected: presentation.selected)
        }
        .sheet(item: $submitted) { submission in
            NavigationStack {
                ScrollView { Text(submission.content).textSelection(.enabled).padding(16) }
                    .navigationTitle("PR #42")
            }
        }
        .theme(.sloppyDark)
        .preferredColorScheme(.dark)
    }

}

private final class CodeReviewFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    private static let searchBody = "В старом чате сохранён важный ответ про поиск: deployment checklist."
    private static var searchHit: [String: Any] {
        ["id": "search-message", "source": "agent", "agentId": "qa", "sessionId": "search-chat",
         "title": "Release checklist", "eventId": "search-event", "messageId": "search-message", "before": "128",
         "kind": "message", "role": "assistant", "createdAt": "2026-10-26T12:00:00Z", "snippet": searchBody]
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let summary = #"{"id":"review-chat","agentId":"qa","title":"PR #42","messageCount":1,"updatedAt":"2026-10-07T12:00:00Z","kind":"chat"}"#
        var json: String
        if request.url?.path == "/v1/config" {
            if ProcessInfo.processInfo.arguments.contains("--settings-error-ui-fixture") {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            json = String(decoding: (try? JSONEncoder().encode(SloppyConfig())) ?? Data(), as: UTF8.self)
        } else if request.url?.path == "/v1/auth/me" {
            json = #"{"id":"fixture","login":"testuser","name":"Test Profile","role":"admin","status":"active"}"#
        } else if request.url?.path == "/v1/auth/application-tokens" {
            json = "[]"
        } else if request.url?.path == "/v1/providers/openai/models" || request.url?.path == "/v1/providers/probe" {
            json = #"{"ok":true,"models":[{"id":"openai:sample","title":"Sample model"}]}"#
        } else if request.url?.path == "/v1/token-usage" {
            json = #"{"items":[]}"#
        } else if request.url?.path == "/v1/agents" {
            json = #"[{"id":"qa","displayName":"QA","role":"Engineer"}]"#
        } else if request.url?.path == "/v1/projects" || request.url?.path == "/v1/providers/models" {
            json = "[]"
        } else if request.url?.path == "/v1/search" {
            let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                .queryItems?.first(where: { $0.name == "q" })?.value ?? ""
            let items: [[String: Any]] = !query.isEmpty && Self.searchBody.localizedCaseInsensitiveContains(query)
                ? [Self.searchHit] : []
            let response: [String: Any] = ["items": items, "hasMore": false, "indexing": false,
                "indexedSources": 1, "failedSources": 0, "durationMs": 1]
            json = String(decoding: (try? JSONSerialization.data(withJSONObject: response)) ?? Data(), as: UTF8.self)
        } else if request.url?.path == "/v1/search/document" {
            json = String(decoding: (try? JSONSerialization.data(withJSONObject: ["hit": Self.searchHit, "text": Self.searchBody])) ?? Data(), as: UTF8.self)
        } else if request.url?.path == "/v1/agents/qa/sessions/search-chat" {
            json = #"{"summary":{"id":"search-chat","agentId":"qa","title":"Release checklist","messageCount":1,"updatedAt":"2026-10-26T12:00:00Z","kind":"chat"},"messages":[{"id":"search-message","role":"assistant","segments":[{"kind":"text","text":"В старом чате сохранён важный ответ про поиск: deployment checklist."}],"createdAt":"2026-10-26T12:00:00Z"}]}"#
        } else if request.url?.path == "/v1/node/mesh/nodes" {
            json = "[]"
        } else if request.url?.path == "/v1/usage/breakdown" {
            json = #"{"requestCount":0,"reportedRequestCount":0,"completeRequestCount":0,"providerUsage":{"prompt":0,"completion":0,"cachedInput":0,"cacheCreationInput":0,"reasoning":0},"groups":[],"calls":[]}"#
        } else if request.url?.path.hasSuffix("/messages") == true {
            json = "{\"summary\":\(summary),\"appendedEvents\":[]}"
        } else if request.url?.path.hasSuffix("/sessions") == true {
            json = request.httpMethod == "POST" ? summary : "[]"
        } else {
            json = #"{"item":{"id":"github:team/repo#42","providerId":"github","providerName":"GitHub","repository":"team/repo","number":42,"title":"Keep cancellation and review feedback scoped to the working task","url":"https://example.invalid/pr/42","state":"open","isDraft":false,"roles":[],"labels":[]},"sourceBranch":"codex/cancellation","targetBranch":"main","reviewers":["Reviewer"],"comments":[{"id":"comment-1","author":"Reviewer","body":"The operation should stop when its parent stops.","filePath":"Sources/Worker.swift","line":3,"side":"RIGHT"}],"diff":"diff --git a/Sources/Worker.swift b/Sources/Worker.swift\n--- a/Sources/Worker.swift\n+++ b/Sources/Worker.swift\n@@ -1,5 +1,5 @@\n func start() async {\n     guard !Task.isCancelled else { return }\n-    await run()\n+    let work = Task { await runLongOperationAndSaveItsResult() }\n     await save()\n }","diffTruncated":false}"#
        }
        if request.url?.path == "/v1/code-reviews", let data = json.data(using: .utf8),
           let detail = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let item = detail["item"],
           let inbox = try? JSONSerialization.data(withJSONObject: ["items": [item], "providers": [["id": "github", "displayName": "GitHub", "capabilities": ["list_pull_requests"]]], "failures": [:]]) {
            json = String(decoding: inbox, as: UTF8.self)
        }
        if let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                               headerFields: ["Content-Type": "application/json"]) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
#endif
