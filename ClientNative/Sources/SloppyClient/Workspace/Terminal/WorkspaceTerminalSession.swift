import Foundation

@MainActor
final class WorkspaceTerminalSession {
    let id: UUID
    let workingDirectory: URL
    private(set) var isRunning = false

    init(id: UUID, workingDirectory: URL) {
        self.id = id
        self.workingDirectory = workingDirectory
    }

    func startIfNeeded() {
        guard !isRunning else {
            return
        }
        isRunning = true
    }

    func terminate() {
        isRunning = false
    }
}
