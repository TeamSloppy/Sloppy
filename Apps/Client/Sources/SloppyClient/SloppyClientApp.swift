import AdaEngine
#if canImport(AdaMCPPlugin)
import AdaMCPPlugin
#endif
import SloppyClientCore
import SloppyFeatureOverview
import SloppyFeatureProjects
import SloppyFeatureAgents

@main
struct SloppyClientApp: App {
    private var baseScene: some AppScene {
        WindowGroup {
            RootShellView()
        }
        .windowMode(.windowed)
        .windowTitle("Sloppy")
    }

    var body: some AppScene {
        #if canImport(AdaMCPPlugin)
        baseScene.addPlugins(
            MCPPlugin(configuration: .init(
                enableHTTP: true,
                enableStdio: false,
                host: "127.0.0.1",
                port: 25102,
                endpoint: "/mcp",
                serverName: "sloppy-client",
                serverVersion: "0.1.0",
                instructions: "Inspect the live Sloppy client AdaEngine runtime."
            ))
        )
        #else
        baseScene
        #endif
    }
}
