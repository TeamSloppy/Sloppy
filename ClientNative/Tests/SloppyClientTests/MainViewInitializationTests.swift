#if os(macOS)
import Foundation
import SwiftUI
import Testing
import SloppyClientCore
@testable import SloppyClient

@Suite("Main view initialization", .serialized)
@MainActor
struct MainViewInitializationTests {
    @Test func constructingUninstalledViewsDoesNotRestoreBrowserOrOpenDatabases() throws {
        let url = try #require(URL(string: "http://startup-\(UUID().uuidString).invalid:25101"))
        let endpoint = SloppyInstanceEndpoint.direct(baseURL: url)
        let settings = ClientSettings()
        let monitor = ConnectionMonitor(baseURL: url)
        let path = ClientCacheStore.defaultDatabasePath(namespace: endpoint.cacheNamespace)
        let projectPath = ClientCacheStore.defaultDatabasePath(
            namespace: endpoint.cacheNamespace + ":inbox-projects:" + settings.instanceDirectoryKey
        )
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: projectPath)
        }
        let time = BrowserTimeStore.shared
        let clock = time.clock

        // SwiftUI constructs new View values while retaining their installed State.
        // These discarded values must not restore browsing or open new caches.
        let views = (0..<20).map { _ in
            MainView(endpoint: endpoint, settings: settings, connectionMonitor: monitor,
                     onOpenSettings: { _ in }, onOpenWorkspace: {})
        }

        withExtendedLifetime(views) {
            #expect(time.clock == clock)
            #expect(!FileManager.default.fileExists(atPath: path))
            #expect(!FileManager.default.fileExists(atPath: projectPath))
        }
    }
}
#endif
