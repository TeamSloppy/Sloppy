#if os(macOS)
import AppKit
import SwiftUI
import SwiftTerm

@MainActor
final class WorkspaceTerminalMacHostController: NSObject, WorkspaceTerminalHosting {
    weak var terminalView: NSView?

    func focus() {
        guard let terminalView else {
            return
        }
        terminalView.window?.makeFirstResponder(terminalView)
    }
}

struct WorkspaceTerminalMacHostView: NSViewRepresentable {
    let session: WorkspaceTerminalSession
    let onHostReady: @MainActor (WorkspaceTerminalHosting) -> Void

    func makeCoordinator() -> WorkspaceTerminalMacHostController {
        WorkspaceTerminalMacHostController()
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminalView = LocalProcessTerminalView(frame: .zero)
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let execName = "-" + URL(fileURLWithPath: shell).lastPathComponent
        terminalView.startProcess(
            executable: shell,
            args: [],
            environment: nil,
            execName: execName,
            currentDirectory: session.workingDirectory.path
        )
        context.coordinator.terminalView = terminalView
        onHostReady(context.coordinator)
        return terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        context.coordinator.terminalView = nsView
    }

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: WorkspaceTerminalMacHostController) {
        nsView.terminate()
        coordinator.terminalView = nil
    }
}
#endif
