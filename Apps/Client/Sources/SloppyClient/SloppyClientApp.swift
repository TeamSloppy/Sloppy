import AdaEngine
#if canImport(AdaMCPPlugin)
import AdaMCPPlugin
#endif
#if canImport(AdaRuntimeDebugPlugin)
import AdaRuntimeDebugPlugin
#endif
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureOverview
import SloppyFeatureProjects
import SloppyFeatureAgents
import SloppyFeatureChat
import SloppyFeatureSettings

@main
struct SloppyClientApp: App {
    private var baseScene: some AppScene {
        WindowGroup {
            #if canImport(AdaRuntimeDebugPlugin)
            RuntimeDebugContainer {
                RootShellView()
                    .theme(.sloppyDark)
            }
            #else
            RootShellView()
                .theme(.sloppyDark)
            #endif
        }
        .windowMode(.windowed)
        .windowTitle("Sloppy")
    }

    var body: some AppScene {
        #if canImport(AdaMCPPlugin) && canImport(AdaRuntimeDebugPlugin)
        baseScene.addPlugins(
            MCPPlugin(configuration: .init(
                enableHTTP: true,
                enableStdio: false,
                host: "127.0.0.1",
                port: 2510,
                endpoint: "/mcp",
                serverName: "sloppy-client",
                serverVersion: "0.1.0",
                instructions: "Inspect the live Sloppy client AdaEngine runtime."
            )),
            RuntimeDebugPlugin()
        )
        #elseif canImport(AdaMCPPlugin)
        baseScene.addPlugins(
            MCPPlugin(configuration: .init(
                enableHTTP: true,
                enableStdio: false,
                host: "127.0.0.1",
                port: 2510,
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
