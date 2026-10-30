#if os(macOS)
import AppKit
import Testing
import WebKit
import SloppyClientCore
import SloppyFeatureChat
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser selection actions", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct WorkspaceBrowserSelectionTests {
    @Test func hiddenMainChatIsNotAnAnnotationDestination() throws {
        let name = "BrowserSelectionVisibility.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let url = try #require(URL(string: "http://127.0.0.1:1"))
        let settings = ClientSettings()
        let monitor = ConnectionMonitor(baseURL: url)
        let model = MainViewModel(endpoint: .direct(baseURL: url), settings: settings, connectionMonitor: monitor,
            cacheStore: ClientCacheStore(path: ":memory:"), responseNotificationScheduler: SelectionTestNotifications(),
            onOpenSettings: { _ in }, onOpenWorkspace: {})
        model.selectAppSection(.chats)
        model.createBlankChatTab()
        let state = BrowserWorkspaceState(defaults: defaults)
        let main = MainView(endpoint: .direct(baseURL: url), settings: settings, connectionMonitor: monitor,
            onOpenSettings: { _ in }, onOpenWorkspace: {}, viewModel: model, browserWorkspace: state)
        let receive = try #require(main.browserTextAnnotationTarget())
        model.selectAppSection(.agents)
        let hiddenTarget = main.browserTextAnnotationTarget()
        #expect(hiddenTarget == nil)
        let acceptedHiddenChat = receive(.init(text: "Selected text", browserSource: .init(url: url, title: "Page")))
        #expect(!acceptedHiddenChat)
        model.selectAppSection(.chats)
        state.isBrowsing = true
        let browsingTarget = main.browserTextAnnotationTarget()
        #expect(browsingTarget == nil)
    }

    @Test func bubbleCachesSelectionWhileMenuFocusesAndAddsAnAnnotation() async throws {
        let api = SloppyAPIClient()
        let chat = ChatScreenViewModel(apiClient: api, cacheStore: ClientCacheStore(path: ":memory:"), settings: ClientSettings(),
            connectionMonitor: ConnectionMonitor(baseURL: api.baseURL), restoresLastSession: false,
            responseNotificationScheduler: SelectionTestNotifications(), onOpenSettings: { _ in })
        let fixture = try await makeFixture()
        defer { fixture.window.orderOut(nil) }
        let browser = fixture.browser
        var requests: [String] = []
        browser.textSelection.onAsk = { requests.append($0) }
        browser.textSelection.annotationTarget = { chat.makeBrowserTextAnnotationReceiver() }
        try await selectResult(in: fixture)
        #expect(requests.isEmpty && chat.composerQuotes.isEmpty)
        try await click("#bubble", in: fixture)
        try await waitUntil { try await value("!root.querySelector('#annotate').hidden", in: fixture) as? Bool == true }
        #expect(try await value("document.activeElement.id", in: fixture) as? String == "sloppy-browser-selection")
        _ = try await value("root.querySelector('#prompt').value = 'Explain the result'", in: fixture)
        try await click("#annotate", in: fixture)
        try await waitUntil { chat.composerQuotes.count == 1 }
        let quote = try #require(chat.composerQuotes.first)
        #expect(quote.text == "Ready")
        #expect(quote.comment == "Explain the result")
        #expect(quote.browserSource?.url == fixture.url)
        #expect(quote.browserSource?.title == "Loaded through HTTP")
        #expect(chat.composerDraft.text.isEmpty && !chat.isSending)
        #expect(requests.isEmpty)
    }

    @Test func offersOnlyAvailableDestinationAndPreparesQuickActionWithoutSending() async throws {
        let fixture = try await makeFixture()
        defer { fixture.window.orderOut(nil) }
        var requests: [String] = []
        fixture.browser.textSelection.onAsk = { requests.append($0) }
        try await selectResult(in: fixture)
        try await click("#bubble", in: fixture)
        #expect(try await value("root.querySelector('#annotate').hidden", in: fixture) as? Bool == true)
        try await click("[data-command='summarize']", in: fixture)
        try await waitUntil { requests.count == 1 }
        #expect(requests[0].contains("Summarize"))
        #expect(requests[0].contains("Ready"))
        #expect(requests[0].contains(fixture.url.absoluteString))
        try await selectResult(in: fixture)
        _ = try await fixture.browser.ensureBrowserRuntime().webView.evaluateJavaScript("getSelection().removeAllRanges()")
        try await waitUntil { try await value("root.querySelector('#bubble').hidden", in: fixture) as? Bool == true }
        #expect(requests.count == 1)
    }

    @Test func keepsControlsStyledAndPositionedUnderStrictSiteCSP() async throws {
        let fixture = try await makeFixture(contentSecurityPolicy: "style-src 'none'")
        defer { fixture.window.orderOut(nil) }
        try await selectResult(in: fixture)
        #expect(try await value("getComputedStyle(root.host).position", in: fixture) as? String == "fixed")
        #expect(try await value("getComputedStyle(root.querySelector('#bubble')).width", in: fixture) as? String == "20px")
        #expect(try await value("getComputedStyle(root.querySelector('#bubble')).position", in: fixture) as? String == "absolute")
        try await click("#bubble", in: fixture)
        #expect(try await value("getComputedStyle(root.querySelector('#menu')).width", in: fixture) as? String == "300px")
        if let path = ProcessInfo.processInfo.environment["SLOPPY_SELECTION_PREVIEW"] {
            try await fixture.browser.ensureBrowserRuntime().screenshot().imageData.write(to: URL(fileURLWithPath: path))
        }
        #expect(try await value("root.querySelector('#menu').getBoundingClientRect().right <= innerWidth", in: fixture) as? Bool == true)
        fixture.window.setContentSize(NSSize(width: 280, height: 500))
        try await waitUntil { try await value("innerWidth", in: fixture) as? Int == 280 }
        try await selectResult(in: fixture)
        try await click("#bubble", in: fixture)
        #expect(try await value("root.querySelector('#menu').getBoundingClientRect().left >= 0 && root.querySelector('#menu').getBoundingClientRect().right <= innerWidth", in: fixture) as? Bool == true)
    }

    private struct Fixture {
        let browser: WorkspaceWebViewModel
        let window: NSWindow
        let server: BrowserHTTPFixture
        let url: URL
    }

    private func makeFixture(contentSecurityPolicy: String? = nil) async throws -> Fixture {
        let browser = WorkspaceWebViewModel()
        let runtime = browser.ensureBrowserRuntime()
        // Only the test shadow root is open so the test can drive the real DOM controls.
        // The message handler and UI script still run in the production private WKContentWorld.
        let controller = runtime.webView.configuration.userContentController
        controller.removeAllUserScripts()
        let script = WorkspaceBrowserSelection.script.replacingOccurrences(of: "mode: \"closed\"", with: "mode: \"open\"")
        #expect(!script.isEmpty)
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd,
                                             forMainFrameOnly: true, in: WorkspaceBrowserSelection.world))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1000, height: 750),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = runtime.webView
        window.makeKeyAndOrderFront(nil)
        let server = try BrowserHTTPFixture(contentSecurityPolicy: contentSecurityPolicy)
        let url = try await server.start()
        _ = try await runtime.open(url: url.absoluteString)
        #expect(try await runtime.webView.evaluateJavaScript("typeof globalThis.__sloppyBrowserSelection") as? String == "undefined")
        return Fixture(browser: browser, window: window, server: server, url: url)
    }

    private func selectResult(in fixture: Fixture) async throws {
        _ = try await fixture.browser.ensureBrowserRuntime().webView.evaluateJavaScript("getSelection().removeAllRanges(); getSelection().selectAllChildren(document.querySelector('#result'))")
        try await waitUntil { try await value("!root.querySelector('#bubble').hidden", in: fixture) as? Bool == true }
    }

    private func click(_ selector: String, in fixture: Fixture) async throws {
        let json = String(decoding: try JSONEncoder().encode(selector), as: UTF8.self)
        _ = try await value("root.querySelector(\(json)).click()", in: fixture)
    }

    private func value(_ script: String, in fixture: Fixture) async throws -> Any? {
        try await fixture.browser.ensureBrowserRuntime().webView.evaluateJavaScript(
            "(() => { const root = document.getElementById('sloppy-browser-selection')?.shadowRoot; if (!root) return null; return (\(script)); })()",
            in: nil, contentWorld: WorkspaceBrowserSelection.world)
    }

    private func waitUntil(_ predicate: @MainActor () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while try await !predicate() {
            guard ContinuousClock.now < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}

@MainActor
private final class SelectionTestNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}
#endif
