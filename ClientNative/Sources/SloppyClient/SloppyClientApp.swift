import SwiftUI
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureAgents
import SloppyFeatureChat
import SloppyFeatureOverview
import SloppyFeatureProjects
import SloppyFeatureSettings

@main
struct SloppyClientApp: App {
    var body: some Scene {
        WindowGroup {
            RootShellView()
        }
    }
}
