import AdaEngine
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureAgents
import SloppyFeatureChat
import SloppyFeatureOverview
import SloppyFeatureProjects
import SloppyFeatureSettings

#if canImport(AdaMCPPlugin)
    import AdaMCPPlugin
#endif

@main
struct SloppyClientApp: App {
    private var baseScene: some AppScene {
        WindowGroup {
            RootShellView()
            //                .debugOverlay()
            //                .hotReloading()
        }
        .window(
            with: UIWindow.Configuration(
                title: "",
                minimumSize: Size(width: 1280, height: 800),
                mode: .windowed,
                titleBar: UIWindow.TitleBar(
                    background: .transparent,
                    reservesSafeArea: false,
                    dragRegionHeight: 52,
                    trafficLightOffset: Point(x: 6, y: 6)
                ),
                background: .transparent,
                backgroundEffect: .blur(.underWindowBackground)
            ))
    }

    #if DEBUG
        private var hotReloadPlugin: AdaUIHotReloadPlugin {
            AdaUIHotReloadPlugin(
                sourcePaths: [
                    "Sources/SloppyClient",
                    "Sources/SloppyClientCore",
                    "Sources/SloppyClientUI",
                    "Sources/SloppyFeatureOverview",
                    "Sources/SloppyFeatureProjects",
                    "Sources/SloppyFeatureAgents",
                    "Sources/SloppyFeatureChat",
                    "Sources/SloppyFeatureSettings",
                ],
                watchPaths: ["Sources"],
                reloadStrategy: .automatic
            )
        }
    #endif

    var body: some AppScene {
        #if canImport(AdaMCPPlugin)
            #if DEBUG
                baseScene.addPlugins(
                    MCPPlugin(
                        configuration: .init(
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
//                    hotReloadPlugin
                )
            #else
                baseScene.addPlugins(
                    MCPPlugin(
                        configuration: .init(
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
                    AdaUIDebug3DPlugin(presentation: .separateWindow, isEnabled: false)
                )
            #endif
        #else
            #if DEBUG
                baseScene.addPlugins(
                    AdaUIDebug3DPlugin(presentation: .primaryWindowOverlay),
                    hotReloadPlugin
                )
            #else
                baseScene.addPlugins(
                    AdaUIDebug3DPlugin(presentation: .primaryWindowOverlay)
                )
            #endif
        #endif
    }
}
