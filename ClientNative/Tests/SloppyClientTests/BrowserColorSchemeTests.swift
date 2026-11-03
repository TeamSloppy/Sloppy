#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SloppyUITestSupport
import WebKit
@testable import SloppyClient

@Suite("Browser color scheme", .serialized, .appKitIsolation)
@MainActor
struct BrowserColorSchemeTests {
    @Test func embeddedPageUsesSwiftUIColorScheme() async throws {
        let app = NSApplication.shared
        let original = app.appearance
        defer { app.appearance = original }
        app.appearance = NSAppearance(named: .aqua)
        let model = WorkspaceWebViewModel()
        let host = NSHostingView(rootView: WorkspaceWebView(viewModel: model).environment(\.colorScheme, .dark))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let window = NSWindow(contentRect: host.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let runtime = model.ensureBrowserRuntime()
        runtime.webView.loadHTMLString("""
        <!doctype html><script>
        window.initialDark = matchMedia('(prefers-color-scheme: dark)').matches;
        </script><body>Theme fixture</body>
        """, baseURL: nil)
        _ = try await runtime.read()
        #expect(try await runtime.evaluate(expression: "matchMedia('(prefers-color-scheme: dark)').matches") == .bool(true))
        host.rootView = WorkspaceWebView(viewModel: model).environment(\.colorScheme, .light)
        host.layoutSubtreeIfNeeded()
        for _ in 0..<40 {
            if try await runtime.evaluate(expression: "matchMedia('(prefers-color-scheme: dark)').matches") == .bool(false) { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(try await runtime.evaluate(expression: "matchMedia('(prefers-color-scheme: dark)').matches") == .bool(false))
        #expect(try await runtime.evaluate(expression: "window.initialDark") == .bool(true))
        #expect(model.nativeWebView === runtime.webView)
    }

    @Test func browserIdentifiesItsSafariCompatibilityWithoutReplacingWebKitUserAgent() async throws {
        let runtime = WorkspaceBrowserToolRuntime()
        runtime.webView.loadHTMLString("<!doctype html><body>Browser identity fixture</body>", baseURL: nil)
        _ = try await runtime.read()
        let agent = try #require(try await runtime.webView.evaluateJavaScript("navigator.userAgent") as? String)
        #expect(agent.contains("AppleWebKit/"))
        #expect(agent.contains("Version/26.0 Safari/605.1.15"))
        #expect(runtime.webView.customUserAgent?.isEmpty != false)
    }

    @Test func detachedPageUsesApplicationAppearanceAtDocumentStart() async throws {
        let app = NSApplication.shared
        let original = app.appearance
        defer { app.appearance = original }
        app.appearance = NSAppearance(named: .darkAqua)
        let runtime = WorkspaceBrowserToolRuntime()
        runtime.webView.loadHTMLString("""
        <!doctype html><script>
        window.initialDark = matchMedia('(prefers-color-scheme: dark)').matches;
        </script><body>Theme fixture</body>
        """, baseURL: nil)
        _ = try await runtime.read()
        #expect(runtime.webView.window == nil)
        #expect(try await runtime.evaluate(expression: "window.initialDark") == .bool(true))
        #expect(try await runtime.evaluate(expression: "matchMedia('(prefers-color-scheme: dark)').matches") == .bool(true))
    }
}
#endif
