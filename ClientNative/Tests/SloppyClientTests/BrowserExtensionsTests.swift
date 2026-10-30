#if os(macOS)
import Foundation
import Testing
import WebKit
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser Web Extensions", .serialized, .appKitIsolation)
@MainActor
struct BrowserExtensionsTests {
    @Test func installationStartsDisabledAndDoesNotGrantWebsiteAccess() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let manager = BrowserExtensions(defaults: fixture.defaults)
        try await manager.importExtensions(at: fixture.url)
        let record = try #require(manager.records.first)
        let context = try #require(manager.contexts[record.id])
        #expect(record.name == "Sloppy extension test")
        #expect(!record.enabled)
        #expect(!context.isLoaded)
        #expect(context.grantedPermissionMatchPatterns.isEmpty)
        #expect(context.grantedPermissions.isEmpty)
        manager.setPermission("https://example.com/*", allowed: true, id: record.id, website: true)
        #expect(context.hasAccess(to: URL(string: "https://example.com/page")!))
        #expect(!context.hasAccess(to: URL(string: "https://other.example/page")!))
        manager.setEnabled(true, id: record.id)
        #expect(context.isLoaded)
        manager.setEnabled(false, id: record.id)
        #expect(!context.isLoaded)
        manager.setPermission("https://example.com/*", allowed: false, id: record.id, website: true)
        #expect(!context.hasAccess(to: URL(string: "https://example.com/page")!))
    }

    @Test func restoresIdentityAndExplicitPermissionsAndRemoval() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let manager = BrowserExtensions(defaults: fixture.defaults)
        try await manager.importExtensions(at: fixture.url)
        let record = try #require(manager.records.first)
        manager.setPermission("storage", allowed: true, id: record.id, website: false)
        manager.setPermission("https://example.com/*", allowed: true, id: record.id, website: true)
        let restored = BrowserExtensions(defaults: fixture.defaults)
        await restored.restore()
        let context = try #require(restored.contexts[record.id])
        #expect(context.uniqueIdentifier == record.id.uuidString)
        #expect(context.baseURL == manager.contexts[record.id]?.baseURL)
        #expect(context.hasPermission(.storage))
        #expect(context.hasAccess(to: URL(string: "https://example.com/")!))
        #expect(!context.isLoaded)
        restored.remove(record.id)
        #expect(restored.records.isEmpty)
        #expect(BrowserExtensions(defaults: fixture.defaults).records.isEmpty)
    }

    @Test func invalidAndDuplicateImportsLeaveExistingInstallationsIntact() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let manager = BrowserExtensions(defaults: fixture.defaults)
        try await manager.importExtensions(at: fixture.url)
        await #expect(throws: (any Error).self) { try await manager.importExtensions(at: fixture.url) }
        let invalid = fixture.url.appendingPathComponent("invalid")
        try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: true)
        await #expect(throws: (any Error).self) { try await manager.importExtensions(at: invalid) }
        #expect(manager.records.count == 1)
        manager.setPermission("<all_urls>", allowed: true, id: manager.records[0].id, website: true)
        #expect(manager.records[0].allowedSites.isEmpty)
    }

    private func makeFixture() throws -> Fixture {
        let name = "BrowserExtensionsTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("""
        {"manifest_version":3,"name":"Sloppy extension test","version":"1.0","permissions":["storage"],
         "host_permissions":["https://example.com/*"],"content_scripts":[{"matches":["https://example.com/*"],"js":["content.js"]}]}
        """.utf8).write(to: url.appendingPathComponent("manifest.json"))
        try Data("document.documentElement.dataset.sloppyExtension = 'loaded';".utf8).write(to: url.appendingPathComponent("content.js"))
        return Fixture(name: name, defaults: defaults, url: url)
    }

    private struct Fixture {
        let name: String
        let defaults: UserDefaults
        let url: URL
        func clean() {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: url)
        }
    }
}
#endif
