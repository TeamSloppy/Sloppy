#if os(macOS)
import AppKit
import Testing
import WebKit
import SwiftUI
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser full reload", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct BrowserFullReloadTests {
    @Test func clearsFetchCacheButKeepsCookiesAndStorage() async throws {
        let server = try BrowserHTTPFixture(responseDelay: 0)
        let url = try await server.start()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let runtime = WorkspaceBrowserToolRuntime(webView: WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 650), configuration: config), sitePermissions: try server.permissionStore())
        _ = try await runtime.open(url: url.absoluteString)
        _ = try await runtime.evaluate(expression: """
        (async () => {
          localStorage.setItem('saved', 'keep'); document.cookie = 'session=keep; path=/';
          const cache = await caches.open('stale'); await cache.put('/cached', new Response('old'));
          return true;
        })()
        """)
        #expect(try await runtime.evaluate(expression: "caches.has('stale')") == .bool(true))
        let model = WorkspaceWebViewModel()
        model.browserRuntime = runtime
        model.nativeWebView = runtime.webView
        let previousRequests = server.requestCount
        await model.reloadWithoutCache()
        _ = try await runtime.read()
        #expect(server.requestCount > previousRequests)
        #expect(try await runtime.evaluate(expression: "caches.has('stale')") == .bool(false))
        #expect(try await runtime.evaluate(expression: "localStorage.getItem('saved')") == .string("keep"))
        #expect(try await runtime.evaluate(expression: "document.cookie.includes('session=keep')") == .bool(true))
        #expect(!model.isReloadingWithoutCache)
        await WorkspaceWebViewModel().reloadWithoutCache()
    }

    @Test func rendersSiteControls() async throws {
        let key = "site-controls-render-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let cookie = try #require(HTTPCookie(properties: [.domain: "example.com", .path: "/", .name: "fixture", .value: "1"]))
        await config.websiteDataStore.httpCookieStore.setCookie(cookie)
        let page = WorkspaceWebViewModel()
        page.nativeWebView = WKWebView(frame: .zero, configuration: config)
        let view = BrowserSiteSettingsView(url: URL(string: "http://example.com")!, permissions: BrowserSitePermissions(defaults: defaults), page: page)
            .frame(width: 560, height: 650).environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 560, height: 650)
        let window = NSWindow(contentRect: host.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: ".artifacts/browser-agent-controls/site-settings.png"))
    }
}
#endif
