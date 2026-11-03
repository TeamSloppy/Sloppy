#if os(macOS)
import AppKit
import ScreenCaptureKit
import SwiftUI
import Testing
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser collapsed sidebar", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct BrowserCollapsedSidebarTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func hoverOverlaysSidebarWithoutMovingOrReloadingThePage(_ scheme: ColorScheme) async throws {
        AppKitTestAccessibility.enable()
        let name = "BrowserCollapsedSidebar.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let server = try BrowserHTTPFixture()
        let url = try await server.start()
        let state = BrowserWorkspaceState(defaults: defaults)
        try server.allowHTTP(in: state)
        state.open(url, inNewTab: true)
        state.columnVisibility = .detailOnly
        let assistant = try BrowserAgentChatTestFixture()
        defer { assistant.close() }
        let controller = NSHostingController(rootView:
            BrowserWorkspaceView(state: state, onAskAgent: { _ in }, onCollect: { _ in }, agentChat: assistant.state)
                .theme(scheme == .dark ? .sloppyDark : .sloppyLight).preferredColorScheme(scheme))
        let window = NSWindow(contentRect: NSRect(x: 150, y: 150, width: 1200, height: 800),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.titlebarAppearsTransparent = true
        window.toolbar = NSToolbar(identifier: "collapsed-browser-test")
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1200, height: 800))
        window.makeKeyAndOrderFront(nil)
        window.acceptsMouseMovedEvents = true
        let cursor = NSEvent.mouseLocation
        defer {
            moveMouse(screenPoint: cursor, window: window)
            window.contentViewController = nil
            window.close()
        }
        let page = try #require(state.selectedPage)
        for _ in 0..<100 where page.pageTitle != "Loaded through HTTP" || page.isLoading {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(page.pageTitle == "Loaded through HTTP")
        let webView = try #require(page.nativeWebView)
        _ = try await page.ensureBrowserRuntime().open(url: url.appendingPathComponent("second").absoluteString)
        #expect(page.canGoBack)
        _ = try await webView.evaluateJavaScript("document.querySelector('#name').value='Keep this draft'; document.body.style.background='white'")
        try await Task.sleep(for: .milliseconds(300))
        let pageFrame = webView.convert(webView.bounds, to: nil)
        let content = try #require(window.contentView)
        let fullFrame = content.convert(content.bounds, to: nil)
        #expect(abs(pageFrame.minX - fullFrame.minX) < 1)
        #expect(abs(pageFrame.maxX - fullFrame.maxX) < 1)
        let chrome = try #require(content.superview)
        for identifier in ["browser-sidebar-toggle", "browser-page-title", "browser-agent-toggle"] {
            #expect(AppKitTestAccessibility.element(in: chrome, identifier: identifier) != nil)
        }
        let variant = "\(scheme)"
        try await save(window, name: "collapsed-white-page-\(variant)")
        _ = try await webView.evaluateJavaScript("document.body.style.background='#111'; document.body.style.color='white'")
        try await Task.sleep(for: .milliseconds(150))
        try await save(window, name: "collapsed-dark-page-\(variant)")
        _ = try await webView.evaluateJavaScript("document.body.style.background='white'; document.body.style.color='black'")

        moveMouse(screenPoint: window.convertPoint(toScreen: NSPoint(x: fullFrame.minX + 3, y: fullFrame.midY)), window: window)
        try await Task.sleep(for: .milliseconds(350))
        #expect(AppKitTestAccessibility.element(in: controller.view, identifier: "browser-address") != nil)
        #expect(state.columnVisibility == .detailOnly)
        #expect(webView.convert(webView.bounds, to: nil) == pageFrame)
        try await save(window, name: "sidebar-peek-\(variant)")

        // Moving from the edge into the temporary sidebar must keep it open.
        moveMouse(screenPoint: window.convertPoint(toScreen: NSPoint(x: 180, y: fullFrame.midY)), window: window)
        try await Task.sleep(for: .milliseconds(250))
        #expect(AppKitTestAccessibility.element(in: controller.view, identifier: "browser-address") != nil)
        moveMouse(screenPoint: window.convertPoint(toScreen: NSPoint(x: 600, y: fullFrame.midY)), window: window)
        try await Task.sleep(for: .milliseconds(350))
        #expect(AppKitTestAccessibility.element(in: controller.view, identifier: "browser-address") == nil)
        #expect(webView.convert(webView.bounds, to: nil) == pageFrame)
        #expect(state.selectedPage?.nativeWebView === webView)
        #expect(try await webView.evaluateJavaScript("document.querySelector('#name').value") as? String == "Keep this draft")

        let toggle = try #require(AppKitTestAccessibility.element(in: chrome, identifier: "browser-sidebar-toggle"))
        _ = AppKitTestAccessibility.press(toggle)
        try await Task.sleep(for: .milliseconds(350))
        #expect(state.columnVisibility == .all)
        #expect(AppKitTestAccessibility.element(in: controller.view, identifier: "browser-address") != nil)
        #expect(webView.convert(webView.bounds, to: nil).minX > pageFrame.minX + 200)
    }

    private func moveMouse(screenPoint: NSPoint, window: NSWindow) {
        let screenHeight = NSScreen.screens.first?.frame.maxY ?? 0
        CGWarpMouseCursorPosition(CGPoint(x: screenPoint.x, y: screenHeight - screenPoint.y))
        if let event = NSEvent.mouseEvent(with: .mouseMoved, location: window.convertPoint(fromScreen: screenPoint),
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
            NSApp.sendEvent(event)
        }
    }

    private func save(_ window: NSWindow, name: String) async throws {
        guard let directory = ProcessInfo.processInfo.environment["SLOPPY_BROWSER_SCREENSHOTS"],
              CGPreflightScreenCaptureAccess() else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let own = try #require(content.windows.first { $0.windowID == CGWindowID(window.windowNumber) })
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * window.backingScaleFactor)
        configuration.height = Int(window.frame.height * window.backingScaleFactor)
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: own), configuration: configuration)
        try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }
}
#endif
