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
    @State private var viewModel = RootShellViewModel()

    var body: some Scene {
        WindowGroup {
            RootShellView(viewModel: viewModel)
                .containerBackground(.clear, for: .window)
        }

        #if os(macOS)
        Settings {
            SettingsScreen(settings: viewModel.settings)
                .frame(minWidth: 1120, minHeight: 760)
        }
        .defaultSize(width: 1360, height: 880)
        .windowResizability(.contentMinSize)
        #endif
    }
}
