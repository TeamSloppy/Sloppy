import SwiftUI
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureAgents
import SloppyFeatureChat
import SloppyFeatureOverview
import SloppyFeatureProjects
import SloppyFeatureSettings

#if os(macOS)
private struct WorkspaceCommands: Commands {
    @FocusedValue(\.toggleWorkspaceTerminal) private var toggleWorkspaceTerminal

    var body: some Commands {
        CommandMenu("Workspace") {
            Button("Toggle Terminal") {
                toggleWorkspaceTerminal?()
            }
            .keyboardShortcut("j", modifiers: [.command])
            .disabled(toggleWorkspaceTerminal == nil)
        }
    }
}
#endif

@main
struct SloppyClientApp: App {
    @State private var viewModel: RootShellViewModel

    init() {
        _viewModel = State(initialValue: RootShellViewModel())
    }

    var body: some Scene {
        WindowGroup {
            RootShellView(viewModel: viewModel)
            #if os(macOS)
                .containerBackground(.clear, for: .window)
            #endif
        }
        #if os(macOS)
        .commands {
            WorkspaceCommands()
        }
        #endif

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
