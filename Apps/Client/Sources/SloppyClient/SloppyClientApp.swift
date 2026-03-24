import AdaEngine
import SloppyClientCore
import SloppyFeatureOverview
import SloppyFeatureProjects
import SloppyFeatureAgents

@main
struct SloppyClientApp: App {
    var body: some AppScene {
        WindowGroup {
            RootShellView()
        }
        .windowMode(.windowed)
        .windowTitle("Sloppy")
    }
}
