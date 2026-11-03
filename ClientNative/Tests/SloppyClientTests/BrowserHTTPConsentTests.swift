#if os(macOS)
import AppKit
import Testing
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser HTTP consent", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct BrowserHTTPConsentTests {
    @Test func blocksBeforeNetworkIncludingServerRedirects() async throws {
        let key = "http-consent-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        let permissions = BrowserSitePermissions(defaults: defaults)
        let target = try BrowserHTTPFixture(responseDelay: 0)
        let targetURL = try await target.start()
        permissions.set(.block, for: try #require(BrowserSiteOrigin(targetURL)), resource: .http)
        let runtime = WorkspaceBrowserToolRuntime(sitePermissions: permissions)
        await #expect(throws: (any Error).self) { try await runtime.open(url: targetURL.absoluteString) }
        #expect(target.requestCount == 0)
        let redirect = try BrowserHTTPFixture(responseDelay: 0, redirectURL: targetURL)
        let redirectURL = try await redirect.start()
        permissions.set(.allow, for: try #require(BrowserSiteOrigin(redirectURL)), resource: .http)
        await #expect(throws: (any Error).self) { try await runtime.open(url: redirectURL.absoluteString) }
        #expect(redirect.requestCount == 1)
        #expect(target.requestCount == 0)
        permissions.set(.allow, for: try #require(BrowserSiteOrigin(targetURL)), resource: .http)
        #expect(try await runtime.open(url: targetURL.absoluteString).title == "Loaded through HTTP")
        #expect(target.requestCount == 1)
    }

    @Test func asksBeforeLoadingAndCancellationCannotResumeLater() async throws {
        let key = "http-prompt-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        let server = try BrowserHTTPFixture(responseDelay: 0)
        let url = try await server.start()
        let runtime = WorkspaceBrowserToolRuntime(sitePermissions: BrowserSitePermissions(defaults: defaults))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = runtime.webView
        defer { runtime.stop(); window.orderOut(nil) }
        let task = Task { try await runtime.open(url: url.absoluteString) }
        for _ in 0..<100 {
            if window.attachedSheet != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(window.attachedSheet != nil)
        #expect(server.requestCount == 0)
        runtime.stop()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(server.requestCount == 0)
        #expect(!runtime.sitePrompt.isPending)
    }
}
#endif
