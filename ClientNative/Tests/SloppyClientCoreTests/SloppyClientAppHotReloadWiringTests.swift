import Foundation
import Testing

@Suite("SloppyClientApp hot reload wiring")
struct SloppyClientAppHotReloadWiringTests {
    private var appSource: String {
        get throws {
            let packageRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let appURL = packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("SloppyClient")
                .appendingPathComponent("SloppyClientApp.swift")
            return try String(contentsOf: appURL, encoding: .utf8)
        }
    }

    @Test("hot reload plugin is debug-only")
    func hotReloadPluginIsDebugOnly() throws {
        let source = try appSource
        let hotReloadDeclaration = try #require(source.range(of: "private var hotReloadPlugin: AdaUIHotReloadPlugin"))
        let debugGuard = try #require(source.range(of: "#if DEBUG"))

        #expect(debugGuard.lowerBound < hotReloadDeclaration.lowerBound)
        #expect(source.contains("#else"))
    }

    @Test("hot reload plugin watches app source roots")
    func hotReloadPluginWatchesAppSources() throws {
        let source = try appSource

        #expect(source.contains("AdaUIHotReloadPlugin("))
        #expect(source.contains("watchPaths: [\"Sources\"]"))
        #expect(source.contains("reloadStrategy: .automatic"))

        for path in [
            "Sources/SloppyClient",
            "Sources/SloppyClientCore",
            "Sources/SloppyClientUI",
            "Sources/SloppyFeatureOverview",
            "Sources/SloppyFeatureProjects",
            "Sources/SloppyFeatureAgents",
            "Sources/SloppyFeatureChat",
            "Sources/SloppyFeatureSettings"
        ] {
            #expect(source.contains("\"\(path)\""))
        }
    }

    @Test("hot reload plugin is installed with existing plugins")
    func hotReloadPluginIsInstalledWithExistingPlugins() throws {
        let source = try appSource

        #expect(source.contains("MCPPlugin(configuration:"))
        #expect(source.contains("AdaUIDebug3DPlugin(presentation: .separateWindow, isEnabled: false),\n            hotReloadPlugin"))
        #expect(source.contains("AdaUIDebug3DPlugin(presentation: .primaryWindowOverlay),\n            hotReloadPlugin"))
    }
}
