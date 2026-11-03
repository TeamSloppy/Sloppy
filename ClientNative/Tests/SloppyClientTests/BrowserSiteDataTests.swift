#if os(macOS)
import Foundation
import WebKit
import Testing
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser site data", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct BrowserSiteDataTests {
    @Test func matchesOnlyTheRequestedWebKitDomain() {
        #expect(BrowserSiteData.matches(host: "docs.example.com", record: "example.com"))
        #expect(!BrowserSiteData.matches(host: "example.com.evil", record: "example.com"))
        #expect(!BrowserSiteData.matches(host: "example.com", record: "other.com"))
        #expect(!BrowserSiteData.matches(host: "example.com", record: ""))
    }

    @Test func removesOneSitesCookiesAndStorageAndPreservesAnother() async throws {
        let server = try BrowserHTTPFixture(responseDelay: 0)
        let first = try await server.start()
        let second = try #require(URL(string: first.absoluteString.replacingOccurrences(of: "127.0.0.1", with: "localhost")))
        let permissions = try server.permissionStore()
        permissions.set(.allow, for: try #require(BrowserSiteOrigin(second)), resource: .http)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let runtime = WorkspaceBrowserToolRuntime(webView: WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 650), configuration: config), sitePermissions: permissions)
        _ = try await runtime.open(url: first.absoluteString)
        _ = try await runtime.evaluate(expression: "(() => { localStorage.setItem('saved', 'first'); document.cookie = 'site=first; path=/'; return true; })()")
        _ = try await runtime.open(url: second.absoluteString)
        _ = try await runtime.evaluate(expression: "(() => { localStorage.setItem('saved', 'second'); document.cookie = 'site=second; path=/'; return true; })()")
        let data = BrowserSiteData(origin: try #require(BrowserSiteOrigin(first)), dataStore: config.websiteDataStore)
        await data.inspect()
        #expect(!data.records.isEmpty)
        #expect(await data.clear(includingCookiesAndStorage: true))
        let cookies = await config.websiteDataStore.httpCookieStore.allCookies()
        #expect(!cookies.contains { $0.domain == "127.0.0.1" })
        #expect(cookies.contains { $0.domain == "localhost" && $0.value == "second" })
        _ = try await runtime.open(url: first.absoluteString)
        #expect(try await runtime.evaluate(expression: "localStorage.getItem('saved')") == .null)
        _ = try await runtime.open(url: second.absoluteString)
        #expect(try await runtime.evaluate(expression: "localStorage.getItem('saved')") == .string("second"))
    }
}
#endif
