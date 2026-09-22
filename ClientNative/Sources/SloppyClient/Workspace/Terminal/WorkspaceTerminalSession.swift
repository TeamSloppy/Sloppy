import Foundation
import SloppyClientCore
#if os(macOS)
import AppKit
import SwiftTerm
#endif

@MainActor
final class WorkspaceTerminalSession {
    struct RemoteConfiguration {
        let apiClient: SloppyAPIClient
        let coordinatorBaseURL: URL
        let targetNodeID: String
        let managedDeviceID: UUID?
        let projectID: String?
    }

    let id: UUID
    let workingDirectory: URL
    let remoteConfiguration: RemoteConfiguration?
    private(set) var isRunning = false
#if os(macOS)
    private var localView: LocalProcessTerminalView?
    private var remoteView: TerminalView?
    private(set) var remoteController: WorkspaceRemoteTerminalMacHostController?

    func localTerminalView() -> LocalProcessTerminalView {
        if let localView { return localView }
        let view = LocalProcessTerminalView(frame: .zero)
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        view.startProcess(executable: shell, args: [], environment: nil,
                          execName: "-" + URL(fileURLWithPath: shell).lastPathComponent,
                          currentDirectory: workingDirectory.path)
        localView = view
        isRunning = true
        return view
    }

    func remoteTerminalView() -> TerminalView {
        if let remoteView { return remoteView }
        let view = TerminalView(frame: .zero)
        let controller = WorkspaceRemoteTerminalMacHostController()
        if let remoteConfiguration { controller.connect(terminalView: view, configuration: remoteConfiguration) }
        remoteView = view
        remoteController = controller
        isRunning = true
        return view
    }
#endif

    init(
        id: UUID,
        workingDirectory: URL,
        remoteConfiguration: RemoteConfiguration? = nil
    ) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.remoteConfiguration = remoteConfiguration
    }

    func startIfNeeded() {
        guard !isRunning else {
            return
        }
        isRunning = true
    }

    func terminate() {
#if os(macOS)
        localView?.terminate()
        localView = nil
        remoteController?.disconnect()
        remoteController = nil
        remoteView = nil
#endif
        isRunning = false
    }
}
