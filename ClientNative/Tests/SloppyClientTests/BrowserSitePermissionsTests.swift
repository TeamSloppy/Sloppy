import Foundation
import Testing
@testable import SloppyClient

@MainActor
struct BrowserSitePermissionsTests {
    @Test func bindsChoicesToOriginAndRemembersOnlyAlways() async throws {
        let key = "site-permissions-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        let store = BrowserSitePermissions(defaults: defaults)
        let origin = try #require(BrowserSiteOrigin(URL(string: "http://user:secret@EXAMPLE.com:80/path")!))
        #expect(origin.id == "http://example.com")
        var prompts = 0
        #expect(await store.authorize(origin, resource: .http) { prompts += 1; return .once })
        #expect(store.decision(for: origin, resource: .http) == .ask)
        #expect(!((await store.authorize(origin, resource: .http) { prompts += 1; return .cancel })))
        #expect(prompts == 2)
        #expect(await store.authorize(origin, resource: .http) { .always })
        let restored = BrowserSitePermissions(defaults: defaults)
        #expect(restored.decision(for: origin, resource: .http) == .allow)
        for raw in ["http://example.com:8080", "https://example.com", "http://sub.example.com", "http://example.com.evil"] {
            #expect(restored.decision(for: try #require(BrowserSiteOrigin(URL(string: raw)!)), resource: .http) == .ask)
        }
        restored.set(.block, for: origin, resource: .http)
        #expect(!((await restored.authorize(origin, resource: .http) { Issue.record("Blocked origins must not prompt"); return .always })))
        restored.reset(origin)
        #expect(BrowserSitePermissions(defaults: defaults).decision(for: origin, resource: .http) == .ask)
        #expect(BrowserSiteOrigin(URL(string: "file:///tmp/secret")!) == nil)
    }

    @Test func settingsRevocationWinsAgainstAnOpenPrompt() async throws {
        let key = "site-revocation-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        let store = BrowserSitePermissions(defaults: defaults)
        let origin = try #require(BrowserSiteOrigin(URL(string: "http://example.com")!))
        #expect(!((await store.authorize(origin, resource: .http) {
            store.set(.block, for: origin, resource: .http)
            return .always
        })))
    }
}
