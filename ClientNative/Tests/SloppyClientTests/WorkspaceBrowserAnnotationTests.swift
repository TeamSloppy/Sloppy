#if os(macOS)
import AppKit
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat
import SloppyUITestSupport
import SwiftUI
import Testing
@testable import SloppyClient

@Suite("Browser element annotations", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct WorkspaceBrowserAnnotationTests {
    @Test func nativeElementPickAddsScreenshotAndCommentWithoutActivatingPage() async throws {
        AppKitTestAccessibility.enable()
        let api = SloppyAPIClient()
        let chat = ChatScreenViewModel(apiClient: api, cacheStore: ClientCacheStore(path: ":memory:"),
            settings: ClientSettings(), connectionMonitor: ConnectionMonitor(baseURL: api.baseURL),
            restoresLastSession: false, responseNotificationScheduler: BrowserAnnotationNotifications(), onOpenSettings: { _ in })
        let suite = "BrowserAnnotationTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let browser = WorkspaceWebViewModel(history: WorkspaceBrowserHistory(defaults: defaults))
        let host = NSHostingView(rootView: WorkspaceBrowserPanelView(viewModel: browser,
            onAnnotate: { chat.makeBrowserAnnotationReceiver() })
            .environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 650),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        window.acceptsMouseMovedEvents = true
        window.makeKeyAndOrderFront(nil)
        defer { browser.annotations.cancel(); window.orderOut(nil) }
        let server = try BrowserHTTPFixture()
        let url = try await server.start()
        let runtime = browser.ensureBrowserRuntime()
        _ = try await runtime.open(url: url.absoluteString)
        try await Task.sleep(for: .milliseconds(200))
        let annotate = try #require(AppKitTestAccessibility.element(in: host, identifier: "workspace-browser-annotate"))
        #expect(AppKitTestAccessibility.press(annotate))
        for _ in 0..<100 where !browser.annotations.isSelecting { try await Task.sleep(for: .milliseconds(20)) }
        #expect(browser.annotations.isSelecting)
        #expect(try await runtime.webView.evaluateJavaScript("typeof globalThis.__sloppyAnnotation") as? String == "undefined")
        let values = try #require(try await runtime.webView.evaluateJavaScript("""
        (() => { const r = document.querySelector('#check').getBoundingClientRect();
          return [(r.left + r.width / 2) / innerWidth, (r.top + r.height / 2) / innerHeight]; })()
        """) as? [Double])
        let webView = runtime.webView
        try await Task.sleep(for: .milliseconds(150))
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let picker = try #require(descendants(host).compactMap { $0 as? BrowserAnnotationPointerView }.first)
        #expect(window.firstResponder === picker)
        let point = picker.convert(NSPoint(x: values[0] * picker.bounds.width, y: values[1] * picker.bounds.height), to: nil)
        let hitPoint = host.superview?.convert(point, from: nil) ?? point
        #expect(host.hitTest(hitPoint) === picker)
        for type in [NSEvent.EventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            switch type {
            case .mouseMoved: picker.mouseMoved(with: event)
            case .leftMouseDown: picker.mouseDown(with: event)
            default: picker.mouseUp(with: event)
            }
            try await Task.sleep(for: .milliseconds(80))
        }
        for _ in 0..<200 where browser.annotations.draft == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(browser.annotations.errorMessage == nil)
        #expect(!browser.annotations.isSelecting)
        #expect(!browser.annotations.isCapturing)
        let draft = try #require(browser.annotations.draft)
        #expect(draft.element.selector == "#check")
        #expect(draft.element.region.width > 0 && draft.element.region.height > 0)
        #expect(draft.data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]))
        #expect(try await webView.evaluateJavaScript("document.querySelector('#result').textContent") as? String == "Ready")
        for _ in 0..<100 where !(window.firstResponder is NSTextView) { try await Task.sleep(for: .milliseconds(10)) }
        let editor = try #require(window.firstResponder as? NSTextView)
        editor.insertText("Make this button larger", replacementRange: NSRange(location: 0, length: 0))
        try await Task.sleep(for: .milliseconds(100))
        if let directory = ProcessInfo.processInfo.environment["SLOPPY_BROWSER_ANNOTATION_SCREENSHOTS"] {
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = try #require(bitmap.representation(using: .png, properties: [:]))
            try image.write(to: URL(fileURLWithPath: directory).appendingPathComponent("browser-element-comment.png"))
        }
        let save = try #require(AppKitTestAccessibility.element(in: host, identifier: "workspace-browser-annotation-save"))
        #expect(AppKitTestAccessibility.press(save))
        let attachment = try #require(chat.composerAttachments.first)
        #expect(attachment.annotations.first?.comment == "Make this button larger")
        #expect(attachment.annotations.first?.browserSource?.url == url)
        #expect(attachment.annotations.first?.browserSource?.selector == "#check")
        #expect(browser.annotations.draft == nil)
        #expect(chat.composerDraft.text.isEmpty)
        #expect(!chat.isSending)
        await browser.annotations.begin(in: webView, receive: chat.makeBrowserAnnotationReceiver())
        _ = try await runtime.open(url: "about:blank")
        #expect(!browser.annotations.isSelecting)
        #expect(browser.annotations.draft == nil)
        #expect(chat.composerAttachments.count == 1)
        withExtendedLifetime(server) {}
    }

    @Test func browseAssistantPicksElementsAndKeepsHTMLMetadataInItsDraft() async throws {
        AppKitTestAccessibility.enable()
        let fixture = try BrowserAgentChatTestFixture()
        defer { fixture.close() }
        let suite = "BrowseElementAnnotation.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let server = try BrowserHTTPFixture()
        let url = try await server.start()
        let browser = BrowserWorkspaceState(defaults: defaults, history: WorkspaceBrowserHistory(defaults: defaults))
        browser.open(url, inNewTab: true)
        let page = try #require(browser.selectedPage)
        let host = NSHostingView(rootView:
            BrowserWorkspaceView(state: browser, onAskAgent: { fixture.state.show(prompt: $0) },
                                 onCollect: { _ in }, agentChat: fixture.state)
                .environment(\.theme, .sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1400, height: 850),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        window.acceptsMouseMovedEvents = true
        window.makeKeyAndOrderFront(nil)
        defer { fixture.state.hide(); window.orderOut(nil) }
        for _ in 0..<250 where page.currentURL == nil || page.isLoading {
            try await Task.sleep(for: .milliseconds(20))
        }
        let webView = try #require(page.nativeWebView)
        fixture.state.show()
        await fixture.chat.waitForInitialData()
        fixture.chat.useStarterPrompt("Keep my question")
        try await Task.sleep(for: .milliseconds(300))
        _ = try await webView.evaluateJavaScript("document.querySelector('#check').className = 'primary action'")
        let button = try #require(AppKitTestAccessibility.element(in: host, identifier: "browser-agent-annotate"))
        #expect(AppKitTestAccessibility.press(button))
        for _ in 0..<100 where !page.annotations.isSelecting { try await Task.sleep(for: .milliseconds(20)) }
        #expect(page.annotations.isSelecting)
        let values = try #require(try await webView.evaluateJavaScript("""
        (() => { const r = document.querySelector('#check').getBoundingClientRect();
          return [(r.left + r.width / 2) / innerWidth, (r.top + r.height / 2) / innerHeight]; })()
        """) as? [Double])
        try await Task.sleep(for: .milliseconds(100))
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let picker = try #require(descendants(host).compactMap { $0 as? BrowserAnnotationPointerView }.first)
        #expect(abs(picker.bounds.height - webView.bounds.height) < 1)
        let point = picker.convert(NSPoint(x: values[0] * picker.bounds.width, y: values[1] * picker.bounds.height), to: nil)
        let hitPoint = host.superview?.convert(point, from: nil) ?? point
        #expect(host.hitTest(hitPoint) === picker)
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        picker.mouseDown(with: event)
        for _ in 0..<200 where page.annotations.draft == nil { try await Task.sleep(for: .milliseconds(20)) }
        let draft = try #require(page.annotations.draft)
        #expect(draft.element.tag == "button")
        #expect(draft.element.elementID == "check")
        #expect(draft.element.classNames == ["primary", "action"])
        #expect(draft.element.selector == "#check")
        #expect(try await webView.evaluateJavaScript("document.querySelector('#result').textContent") as? String == "Ready")
        page.annotations.draft?.comment = "Make this button larger"
        try await Task.sleep(for: .milliseconds(150))
        if let directory = ProcessInfo.processInfo.environment["SLOPPY_BROWSER_ANNOTATION_SCREENSHOTS"] {
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = try #require(bitmap.representation(using: .png, properties: [:]))
            try image.write(to: URL(fileURLWithPath: directory).appendingPathComponent("browse-assistant-element.png"))
        }
        let save = try #require(AppKitTestAccessibility.element(in: host, identifier: "workspace-browser-annotation-save"))
        #expect(AppKitTestAccessibility.press(save))
        let attachment = try #require(fixture.chat.composerAttachments.first)
        let source = try #require(attachment.annotations.first?.browserSource)
        #expect(source.tag == "button")
        #expect(source.elementID == "check")
        #expect(source.classNames == ["primary", "action"])
        #expect(source.selector == "#check")
        #expect(source.url == url)
        #expect(attachment.data.starts(with: [137, 80, 78, 71]))
        #expect(fixture.chat.composerDraft.text == "Keep my question")
        #expect(fixture.probe.posts.isEmpty)
        await fixture.state.toggleElementAnnotation(in: browser)
        #expect(page.annotations.isSelecting)
        fixture.state.hide()
        #expect(!page.annotations.isSelecting)
        #expect(page.annotations.draft == nil)
        fixture.state.show()
        try await Task.sleep(for: .milliseconds(150))
        await fixture.state.toggleElementAnnotation(in: browser)
        page.annotations.pick(at: CGPoint(x: values[0], y: values[1]))
        for _ in 0..<200 where page.annotations.draft == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(page.annotations.draft != nil)
        fixture.chat.selectedSessionId = "different-chat"
        try await Task.sleep(for: .milliseconds(150))
        #expect(page.annotations.draft == nil)
        #expect(fixture.chat.composerAttachments.count == 1)
        await fixture.state.toggleElementAnnotation(in: browser)
        page.annotations.pick(at: CGPoint(x: values[0], y: values[1]))
        for _ in 0..<200 where page.annotations.draft == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(page.annotations.draft != nil)
        _ = try await page.ensureBrowserRuntime().open(url: "about:blank")
        #expect(page.annotations.draft == nil)
        #expect(fixture.chat.composerAttachments.count == 1)
        withExtendedLifetime(server) {}
    }

    @Test func staleOrInvalidSelectionsAreRejected() throws {
        let url = try #require(URL(string: "https://example.com/page"))
        let valid: [String: Any] = ["nonce": "current", "pageURL": url.absoluteString, "title": "Page",
            "selector": "#button", "tag": "button", "elementID": "button", "classNames": ["primary"], "x": 0.1, "y": 0.2, "width": 0.3, "height": 0.1]
        #expect(try WorkspaceBrowserElementSelection.decode(valid, url: url, nonce: "current").selector == "#button")
        #expect(throws: (any Error).self) { try WorkspaceBrowserElementSelection.decode(valid, url: url, nonce: "old") }
        #expect(throws: (any Error).self) { try WorkspaceBrowserElementSelection.decode(valid, url: URL(string: "https://other.example/"), nonce: "current") }
        var invalid = valid
        invalid["width"] = 2.0
        #expect(throws: (any Error).self) { try WorkspaceBrowserElementSelection.decode(invalid, url: url, nonce: "current") }
        invalid["classNames"] = Array(repeating: "class", count: 65)
        invalid["width"] = 0.3
        #expect(throws: (any Error).self) { try WorkspaceBrowserElementSelection.decode(invalid, url: url, nonce: "current") }
        invalid["classNames"] = ["primary"]
        invalid["width"] = Double.nan
        #expect(throws: (any Error).self) { try WorkspaceBrowserElementSelection.decode(invalid, url: url, nonce: "current") }
    }
}

@MainActor
private final class BrowserAnnotationNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}
#endif
