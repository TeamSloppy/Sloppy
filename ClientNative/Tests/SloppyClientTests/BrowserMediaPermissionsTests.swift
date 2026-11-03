#if os(macOS)
import Foundation
import Testing
import WebKit
import SloppyUITestSupport
@testable import SloppyClient

@Suite("Browser media policy", .appKitUI, .appKitIsolation)
@MainActor
struct BrowserMediaPermissionsTests {
    @Test func validatesRequestOriginAndBothResourcesBeforeSystemAccess() async throws {
        let server = try BrowserHTTPFixture(responseDelay: 0)
        let url = try await server.start()
        let permissions = try server.permissionStore()
        let origin = try #require(BrowserSiteOrigin(url))
        let runtime = WorkspaceBrowserToolRuntime(sitePermissions: permissions)
        _ = try await runtime.open(url: url.absoluteString)
        var systemRequests: [BrowserSiteResource] = []
        runtime.requestSystemMediaAccess = { systemRequests.append($0); return true }
        permissions.set(.allow, for: origin, resource: .camera)
        permissions.set(.block, for: origin, resource: .microphone)
        #expect(await runtime.authorizeMedia(origin: origin, frameOrigin: origin, resources: [.camera, .microphone]) == .deny)
        #expect(systemRequests.isEmpty)
        permissions.set(.allow, for: origin, resource: .microphone)
        #expect(await runtime.authorizeMedia(origin: origin, frameOrigin: origin, resources: [.camera, .microphone]) == .grant)
        #expect(systemRequests == [.camera, .microphone])
        let other = try #require(BrowserSiteOrigin(URL(string: "https://other.invalid")!))
        #expect(await runtime.authorizeMedia(origin: origin, frameOrigin: other, resources: [.camera]) == .deny)
        #expect(await runtime.authorizeMedia(origin: other, frameOrigin: other, resources: [.camera]) == .deny)
        runtime.requestSystemMediaAccess = { _ in false }
        #expect(await runtime.authorizeMedia(origin: origin, frameOrigin: origin, resources: [.camera]) == .deny)
        permissions.reset(origin)
        #expect(permissions.decision(for: origin, resource: .camera) == .ask)
    }
}
#endif
