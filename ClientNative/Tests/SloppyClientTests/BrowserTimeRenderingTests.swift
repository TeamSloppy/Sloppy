#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser time rendering", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct BrowserTimeRenderingTests {
    @Test func focusControlsWorkOnTheRenderedTimeScreen() async throws {
        AppKitTestAccessibility.enable()
        let name = "BrowserTimeRendering.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let history = WorkspaceBrowserHistory(defaults: defaults)
        let state = BrowserWorkspaceState(defaults: defaults, history: history)
        state.time.setFocusSite("example.com", enabled: true)
        let host = NSHostingView(rootView: BrowserTimeView(state: state).theme(.sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 900),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(250))
        let start = try #require(AppKitTestAccessibility.element(in: host, identifier: "browser-focus-start"))
        #expect(AppKitTestAccessibility.press(start))
        #expect(state.time.phase == .focus)
        #expect(state.time.block(for: URL(string: "https://example.com")) == .focus)
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/sloppy-browser-time-dark.png"))
        state.time.stopFocus()
    }

    @Test func navigationPolicyCancelsFocusSitesBeforeLoading() async throws {
        let name = "BrowserTimeNavigation.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let state = BrowserWorkspaceState(defaults: defaults)
        state.createBlankTab()
        let page = try #require(state.selectedPage)
        state.time.setFocusSite("example.com", enabled: true)
        state.time.startFocus()
        let runtime = page.ensureBrowserRuntime()
        do {
            _ = try await runtime.open(url: "https://example.com/blocked")
            Issue.record("Focus navigation should fail before the site loads")
        } catch {
            #expect(error is WorkspaceBrowserRuntimeError)
        }
        #expect(page.timeBlock == .focus)
        #expect(runtime.webView.url == nil || runtime.webView.url?.absoluteString == "about:blank")
        #expect(state.history.sites.allSatisfy { $0.url.host != "example.com" })
        state.time.stopFocus()
    }
}
#endif
