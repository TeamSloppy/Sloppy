#if os(macOS)
import AppKit
import ScreenCaptureKit
import SwiftUI
import WebKit
import SloppyClientUI
import SloppyUITestSupport
import Testing
@testable import SloppyClient

@Suite("Browser assistant rendering", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct BrowserAgentChatRenderingTests {
    @Test func toolbarSummaryReadsTheSelectedPageAndKeepsDraft() async throws {
        AppKitTestAccessibility.enable()
        let fixture = try BrowserAgentChatTestFixture()
        defer { fixture.close() }
        let name = "BrowserSummaryRendering.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let site = try BrowserHTTPFixture(html: """
        <!doctype html><html><head><title>Loaded through HTTP</title><style>
        body{margin:0;background:#242429;color:#e8e6e3;font:16px system-ui}
        header{position:fixed;top:0;left:0;right:0;height:44px;padding:0 24px;display:flex;align-items:center;background:#303036;border-bottom:1px solid #444}
        main{padding:64px 28px}h1{font-size:30px}p{color:#b5b5ba}input{padding:10px;background:#303036;color:#eee;border:1px solid #555;border-radius:6px}
        </style></head><body><header>Example article</header><main><h1>Sloppy browser smoke test</h1>
        <p>Swift actors isolate mutable state. Async functions suspend without blocking the current thread.</p>
        <input id="name" aria-label="Notes" placeholder="Your notes"></main></body></html>
        """)
        let url = try await site.start()
        let browser = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        try site.allowHTTP(in: browser)
        browser.open(url, inNewTab: true)
        let page = try #require(browser.selectedPage)
        let controller = NSHostingController(rootView:
            BrowserWorkspaceView(state: browser, onAskAgent: { _ in }, onCollect: { _ in }, agentChat: fixture.state)
                .theme(.sloppyDark).preferredColorScheme(.dark))
        controller.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1360, height: 880),
            styleMask: [.titled, .resizable, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = NSToolbar(identifier: "browser-summary-test")
        window.toolbarStyle = .unified
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1360, height: 880))
        window.makeKeyAndOrderFront(nil)
        defer { window.contentViewController = nil; window.close() }
        try await waitForPage(page)
        await fixture.chat.waitForInitialData()
        fixture.chat.useStarterPrompt("Keep my unfinished draft")
        try await Task.sleep(for: .milliseconds(250))
        let webView = try #require(page.nativeWebView)
        _ = try await webView.evaluateJavaScript("document.querySelector('#name').value='Keep my form input'")
        try await screenshot(window, view: controller.view, name: "browser-toolbar-compact.png")
        let frameView = try #require(window.contentView?.superview)
        let summarize = try #require(AppKitTestAccessibility.element(in: frameView, identifier: "browser-summarize-page"))
        // NSToolbarItemViewer can dispatch the action while returning false from AXPress.
        _ = AppKitTestAccessibility.press(summarize)
        for _ in 0..<200 {
            if fixture.chat.messages.contains(where: { $0.role == .assistant }) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(fixture.state.panel.isPresented)
        #expect(fixture.probe.posts.count == 1)
        #expect(fixture.probe.posts.first?.contains("Sloppy browser smoke test") == true)
        #expect(fixture.probe.posts.first?.contains(url.absoluteString) == true)
        #expect(fixture.chat.messages.contains { $0.role == .assistant })
        #expect(fixture.chat.composerDraft.text == "Keep my unfinished draft")
        #expect(browser.selectedPage === page)
        #expect(try await webView.evaluateJavaScript("document.querySelector('#name').value") as? String == "Keep my form input")
        let inset = page.ensureBrowserRuntime().documentInset.inset
        #expect(inset > 0 && inset < 95)
        try await Task.sleep(for: .milliseconds(300))
        try await screenshot(window, view: controller.view, name: "browser-page-summary.png")
    }

    @Test func sidebarSharesThePageKeepsDraftsAndSendsThroughTheNativeComposer() async throws {
        AppKitTestAccessibility.enable()
        let fixture = try BrowserAgentChatTestFixture()
        defer { fixture.close() }
        let name = "BrowserAssistantRendering.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let site = try BrowserHTTPFixture()
        let url = try await site.start()
        let browser = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        try site.allowHTTP(in: browser)
        browser.open(url, inNewTab: true)
        let firstID = try #require(browser.selectedID)
        let firstPage = try #require(browser.selectedPage)
        let controller = NSHostingController(rootView:
            BrowserWorkspaceView(state: browser, onAskAgent: { fixture.state.show(prompt: $0) }, onCollect: { _ in },
                onAnnotateSelection: { fixture.state.makeAnnotationReceiver() }, agentChat: fixture.state)
                .theme(.sloppyDark).preferredColorScheme(.dark))
        controller.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1440, height: 900),
            styleMask: [.titled, .resizable, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = NSToolbar(identifier: "browser-assistant-test")
        window.toolbarStyle = .unified
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1440, height: 900))
        window.makeKeyAndOrderFront(nil)
        defer { window.contentViewController = nil; window.close() }
        try await waitForPage(firstPage)
        let webView = try #require(firstPage.nativeWebView)
        let fullWidth = webView.bounds.width
        _ = try await webView.evaluateJavaScript("document.querySelector('#name').value='Preserve form input'")
        fixture.state.show()
        await fixture.chat.waitForInitialData()
        try await Task.sleep(for: .milliseconds(350))
        #expect(webView.bounds.width < fullWidth - 250)
        #expect(webView.bounds.width > 300)
        try await screenshot(window, view: controller.view, name: "browser-assistant-empty.png")

        fixture.chat.useStarterPrompt("Keep this question")
        let add = try #require(AppKitTestAccessibility.element(in: controller.view, identifier: "browser-agent-add-page"))
        #expect(AppKitTestAccessibility.press(add))
        for _ in 0..<100 {
            if !fixture.chat.composerQuotes.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(fixture.chat.composerQuotes.first?.browserSource?.url == url)
        #expect(fixture.chat.composerQuotes.first?.text.contains("Sloppy browser smoke test") == true)
        #expect(fixture.chat.composerDraft.text == "Keep this question")
        #expect(fixture.probe.posts.isEmpty)
        let close = try #require(AppKitTestAccessibility.element(in: controller.view, identifier: "browser-agent-close"))
        #expect(AppKitTestAccessibility.press(close))
        try await Task.sleep(for: .milliseconds(300))
        #expect(!fixture.state.panel.isPresented)
        #expect(webView.bounds.width > fullWidth - 30)
        fixture.state.show()
        try await Task.sleep(for: .milliseconds(300))
        #expect(firstPage.nativeWebView === webView)
        #expect(try await webView.evaluateJavaScript("document.querySelector('#name').value") as? String == "Preserve form input")
        let send = try #require(AppKitTestAccessibility.element(in: controller.view, identifier: "chat.composer.trailing-action"))
        #expect(AppKitTestAccessibility.press(send))
        for _ in 0..<200 {
            if fixture.chat.messages.contains(where: { $0.role == .assistant }) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(fixture.probe.posts.count == 1)
        #expect(fixture.probe.posts.first?.contains(url.absoluteString) == true)
        #expect(fixture.chat.messages.contains { $0.role == .assistant })
        #expect(browser.isBrowsing)
        await fixture.state.synchronizeBrowser(browser)
        let binding = try #require(fixture.state.browserConnection?.binding.bridgeId)
        browser.open(url.appendingPathComponent("other"), inNewTab: true)
        try await waitForPage(try #require(browser.selectedPage))
        await fixture.state.synchronizeBrowser(browser)
        #expect(fixture.state.browserConnection?.binding.bridgeId == binding)
        #expect(fixture.state.browserConnection?.viewModel === browser.selectedPage)
        browser.select(firstID)
        #expect(fixture.chat.selectedSessionId == "browse-session")
        #expect(browser.selectedPage?.nativeWebView === webView)
        fixture.state.panel.preferredWidth = 360
        window.setContentSize(NSSize(width: 1100, height: 780))
        try await Task.sleep(for: .milliseconds(300))
        #expect(webView.bounds.width > 300)
        let composer = try #require(AppKitTestAccessibility.element(in: controller.view, identifier: "chat.composer.trailing-action"))
        let composerFrame = try #require(AppKitTestAccessibility.frame(of: composer))
        #expect(composerFrame.maxX <= window.frame.maxX)
        #expect(composerFrame.minX > window.frame.minX + 600)
        try await screenshot(window, view: controller.view, name: "browser-assistant-conversation.png")
        browser.isBrowsing = false
        await fixture.state.synchronizeBrowser(browser)
        #expect(fixture.state.browserConnection == nil)
    }

    private func waitForPage(_ page: WorkspaceWebViewModel) async throws {
        for _ in 0..<250 {
            if page.nativeWebView?.title == "Loaded through HTTP", !page.isLoading { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("The fixture page did not load")
    }

    private func screenshot(_ window: NSWindow, view: NSView, name: String) async throws {
        guard let directory = ProcessInfo.processInfo.environment["SLOPPY_BROWSER_SCREENSHOTS"] else { return }
        let destination = URL(fileURLWithPath: directory).appendingPathComponent(name)
        if CGPreflightScreenCaptureAccess() {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            if let own = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) {
                let configuration = SCStreamConfiguration()
                configuration.width = Int(window.frame.width * window.backingScaleFactor)
                configuration.height = Int(window.frame.height * window.backingScaleFactor)
                configuration.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(desktopIndependentWindow: own), configuration: configuration)
                try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: destination)
                return
            }
        }
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: destination)
    }
}
#endif
