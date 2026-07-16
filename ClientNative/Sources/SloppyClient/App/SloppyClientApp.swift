import SwiftUI
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureAgents
import SloppyFeatureChat
import SloppyFeatureOverview
import SloppyFeatureProjects
import SloppyFeatureSettings

#if os(macOS)
import AppKit

@MainActor
private final class SloppyAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

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

@MainActor
private struct SloppyMenuBarView: View {
    let viewModel: RootShellViewModel

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Chat", systemImage: "square.and.pencil") {
            perform(.newChat)
        }
        .keyboardShortcut("n")

        Button("Scheduled Tasks", systemImage: "clock") {
            perform(.scheduledTasks)
        }

        Divider()

        Button("Open Sloppy", systemImage: "macwindow") {
            showMainWindow()
        }

        SettingsLink {
            Label("Settings…", systemImage: "gearshape")
        }

        Divider()

        Button("Quit Sloppy", systemImage: "power") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func perform(_ action: MenuBarQuickAction) {
        viewModel.requestMenuBarAction(action)
        showMainWindow()
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif

@main
struct SloppyClientApp: App {
    @State private var viewModel: RootShellViewModel
    #if os(macOS)
    @NSApplicationDelegateAdaptor(SloppyAppDelegate.self) private var appDelegate
    #endif

    init() {
        _viewModel = State(initialValue: RootShellViewModel())
    }

    var body: some Scene {
        Window("Sloppy", id: "main") {
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

        MenuBarExtra("Sloppy", systemImage: "waveform.path.ecg") {
            SloppyMenuBarView(viewModel: viewModel)
        }
        #endif
    }
}
