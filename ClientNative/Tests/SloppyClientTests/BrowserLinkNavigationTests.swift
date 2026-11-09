#if os(macOS)
import AppKit
import Testing
import SloppyUITestSupport
import WebKit
@testable import SloppyClient

@Suite("Browser link navigation", .serialized, .appKitIsolation)
@MainActor
struct BrowserLinkNavigationTests {
    @Test(.appKitUI, arguments: ["_self", "_blank"])
    func commandClickCreatesANewTabAndPreservesTheSourcePage(target: String) async throws {
        let server = try BrowserHTTPFixture(responseDelay: 0, html: """
        <!doctype html><style>body { margin: 0 } a { display: block; width: 200px; height: 100px }</style>
        <a href="/destination" target="\(target)">Open</a>
        """)
        let url = try await server.start()
        let suite = "BrowserLinkNavigationTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        try server.allowHTTP(in: state)
        let source = state.createBlankTab()
        let page = try #require(state.selectedPage)
        let runtime = page.ensureBrowserRuntime()
        let view = runtime.webView
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        defer { runtime.stop(); window.close() }
        _ = try await runtime.open(url: url.absoluteString)

        let point = NSPoint(x: 25, y: view.isFlipped ? 25 : view.bounds.height - 25)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(
                with: type, location: view.convert(point, to: nil), modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
            ))
            window.sendEvent(event)
        }

        let deadline = ContinuousClock.now + .seconds(3)
        while state.tabs.count == 1, view.url == url, runtime.popupWindows.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(state.tabs.count == 2)
        #expect(state.tabs.first?.id == source)
        #expect(state.pages[source] === page)
        #expect(state.selectedID != source)
        #expect(state.selectedTab?.url == url.appendingPathComponent("destination"))
        #expect(view.url == url)
        #expect(runtime.popupWindows.isEmpty)
    }

    @Test func onlyCommandLeftClicksOnLinksAreRedirected() async throws {
        let runtime = WorkspaceBrowserToolRuntime()
        let url = try #require(URL(string: "https://example.com/destination"))
        var opened: [URL] = []
        runtime.onOpenLinkInNewTab = { opened.append($0) }
        for action in [
            LinkNavigationAction(url: url, modifiers: []),
            LinkNavigationAction(url: url, modifiers: .control),
            LinkNavigationAction(url: url, modifiers: .command, button: 2),
            LinkNavigationAction(url: url, modifiers: .command, type: .formSubmitted),
            LinkNavigationAction(url: url, modifiers: .command, type: .other),
        ] {
            #expect(await runtime.webView(runtime.webView, decidePolicyFor: action) == .allow)
        }
        #expect(opened.isEmpty)
        let action = LinkNavigationAction(url: url, modifiers: .command)
        #expect(await runtime.webView(runtime.webView, decidePolicyFor: action) == .cancel)
        #expect(opened == [url])
    }

    @Test func downloadsAndUnsupportedURLsDoNotCreateTabs() async throws {
        let runtime = WorkspaceBrowserToolRuntime()
        runtime.onDownload = { _ in }
        var opened: [URL] = []
        runtime.onOpenLinkInNewTab = { opened.append($0) }
        let url = try #require(URL(string: "https://example.com/file"))
        let download = LinkNavigationAction(url: url, modifiers: .command, download: true)
        #expect(await runtime.webView(runtime.webView, decidePolicyFor: download) == .download)
        let unsafe = LinkNavigationAction(url: try #require(URL(string: "javascript:alert(1)")), modifiers: .command)
        #expect(await runtime.webView(runtime.webView, decidePolicyFor: unsafe) == .cancel)
        #expect(opened.isEmpty)
    }

    @Test func externalAppLinksAreHandedOffWithoutReplacingThePage() async throws {
        let runtime = WorkspaceBrowserToolRuntime()
        var opened: [URL] = []
        var errors: [String] = []
        runtime.openExternalURL = { opened.append($0) }
        runtime.onStateChange = { _, error in if let error { errors.append(error) } }
        let url = try #require(URL(string: "telemost://join/meeting"))
        for type in [WKNavigationType.linkActivated, .other] {
            let action = LinkNavigationAction(url: url, modifiers: [], type: type)
            #expect(await runtime.webView(runtime.webView, decidePolicyFor: action) == .cancel)
        }
        let mail = try #require(URL(string: "mailto:demo@example.com"))
        var tabs: [URL] = []
        runtime.onOpenLinkInNewTab = { tabs.append($0) }
        let command = LinkNavigationAction(url: mail, modifiers: .command)
        #expect(await runtime.webView(runtime.webView, decidePolicyFor: command) == .cancel)
        #expect(tabs.isEmpty)
        #expect(opened == [url, url, mail])
        #expect(errors.isEmpty)
        let unsafe = LinkNavigationAction(url: try #require(URL(string: "javascript:alert(1)")), modifiers: [])
        #expect(await runtime.webView(runtime.webView, decidePolicyFor: unsafe) == .cancel)
        #expect(opened == [url, url, mail])
    }

    @Test(.appKitUI, arguments: ["_self", "_blank"])
    func ordinaryLinksStillNavigateTheCurrentPage(target: String) async throws {
        let server = try BrowserHTTPFixture(responseDelay: 0, html: """
        <!doctype html><title>Links</title><a id="link" href="/destination" target="\(target)">Open</a>
        """)
        let url = try await server.start()
        let runtime = WorkspaceBrowserToolRuntime()
        try server.allowHTTP(in: runtime)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = runtime.webView
        defer { runtime.stop(); window.close() }
        var opened: [URL] = []
        runtime.onOpenLinkInNewTab = { opened.append($0) }
        _ = try await runtime.open(url: url.absoluteString)
        _ = try await runtime.click(selector: "#link")
        #expect(try await runtime.read().url == url.appendingPathComponent("destination").absoluteString)
        #expect(opened.isEmpty)
        #expect(runtime.popupWindows.isEmpty)
    }
}

@MainActor
private final class LinkNavigationAction: WKNavigationAction {
    private let url: URL
    private let modifiers: NSEvent.ModifierFlags
    private let button: Int
    private let type: WKNavigationType
    private let download: Bool

    init(url: URL, modifiers: NSEvent.ModifierFlags, button: Int = 1,
         type: WKNavigationType = .linkActivated, download: Bool = false) {
        self.url = url
        self.modifiers = modifiers
        self.button = button
        self.type = type
        self.download = download
        super.init()
    }

    override var request: URLRequest { URLRequest(url: url) }
    override var modifierFlags: NSEvent.ModifierFlags { modifiers }
    override var buttonNumber: Int { button }
    override var navigationType: WKNavigationType { type }
    override var shouldPerformDownload: Bool { download }
    override var targetFrame: WKFrameInfo? { nil }
}
#endif
