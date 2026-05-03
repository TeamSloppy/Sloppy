import AdaEngine
#if canImport(AdaMCPPlugin)
import AdaMCPPlugin
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
            RootShellView()
                .theme(.sloppyDark)
        }
        .windowMode(.windowed)
        .minimumSize(width: 1280, height: 800)
        .windowTitle("")
        .windowTitleBar(.overlay)
        .windowTrafficLightOffset(x: 6, y: 6)
    }

    var body: some AppScene {
        #if canImport(AdaMCPPlugin)
        baseScene.addPlugins(
            MCPPlugin(configuration: .init(
                enableHTTP: true,
                enableStdio: false,
                host: "127.0.0.1",
                port: 2510,
                endpoint: "/mcp",
                serverName: "sloppy-client",
                serverVersion: "0.1.0",
                instructions: "Inspect the live Sloppy client AdaEngine runtime.",
                traceRecorder: nil
            )),
            AdaUIDebug3DPlugin()
        )
        #else
        baseScene
        #endif
    }
}
