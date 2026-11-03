#if os(macOS)
import AppKit
import ScreenCaptureKit
import SwiftUI
import Testing
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser page title", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct BrowserPageTitleTests {
    @Test func titleStaysVisibleDuringPageInteractionAndTracksTheSelectedPage() async throws {
        AppKitTestAccessibility.enable()
        let assistant = try BrowserAgentChatTestFixture()
        defer { assistant.close() }
        let name = "BrowserPageTitle.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let server = try BrowserHTTPFixture()
        let url = try await server.start()
        let state = BrowserWorkspaceState(defaults: defaults)
        try server.allowHTTP(in: state)
        state.open(url, inNewTab: true)
        let page = try #require(state.selectedPage)
        let controller = NSHostingController(rootView:
            BrowserWorkspaceView(state: state, onAskAgent: { _ in }, onCollect: { _ in }, agentChat: assistant.state)
                .theme(.sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.toolbar = NSToolbar(identifier: "browser-page-title-test")
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        defer { window.contentViewController = nil; window.close() }
        for _ in 0..<200 where page.isLoading || page.pageTitle != "Loaded through HTTP" {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(page.pageTitle == "Loaded through HTTP")
        let webView = try #require(page.nativeWebView)

        func checkTitle(_ expected: String) throws {
            controller.view.layoutSubtreeIfNeeded()
            let chrome = try #require(window.contentView?.superview)
            let title = try #require(AppKitTestAccessibility.element(in: chrome, identifier: "browser-page-title"))
            let value = title.perform(NSSelectorFromString("accessibilityValue"))?.takeUnretainedValue() as? String
            #expect(value == expected)
            let frame = try #require(AppKitTestAccessibility.frame(of: title))
            #expect(frame.width > 0 && frame.height > 0)
            #expect(frame.minY >= window.convertToScreen(window.contentLayoutRect).maxY - 1)
        }

        try await Task.sleep(for: .milliseconds(250))
        try checkTitle("Loaded through HTTP")
        for type in [NSEvent.EventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: 700, y: 400),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
            window.sendEvent(event)
            try await Task.sleep(for: .milliseconds(50))
            try checkTitle("Loaded through HTTP")
        }
        _ = try await webView.evaluateJavaScript("document.querySelector('#name').focus()")
        window.makeFirstResponder(webView)
        let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
        window.sendEvent(key)
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await webView.evaluateJavaScript("document.querySelector('#name').value") as? String == "a")
        try checkTitle("Loaded through HTTP")

        if let directory = ProcessInfo.processInfo.environment["SLOPPY_BROWSER_TITLE_SCREENSHOTS"], CGPreflightScreenCaptureAccess() {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let own = try #require(content.windows.first { $0.windowID == CGWindowID(window.windowNumber) })
            let configuration = SCStreamConfiguration()
            configuration.width = Int(window.frame.width * window.backingScaleFactor)
            configuration.height = Int(window.frame.height * window.backingScaleFactor)
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: own), configuration: configuration)
            try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("after-typing.png"))
        }

        _ = try await webView.evaluateJavaScript("document.title = 'Updated page title'")
        for _ in 0..<40 where state.selectedTab?.title != "Updated page title" {
            try await Task.sleep(for: .milliseconds(25))
        }
        try await Task.sleep(for: .milliseconds(100))
        try checkTitle("Updated page title")
        state.showHome()
        try await Task.sleep(for: .milliseconds(250))
        try checkTitle("Browse")
    }
}
#endif
