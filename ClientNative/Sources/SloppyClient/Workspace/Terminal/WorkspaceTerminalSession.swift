import Foundation
import SloppyClientCore

@MainActor
final class WorkspaceTerminalSession {
    struct RemoteConfiguration {
        let apiClient: SloppyAPIClient
        let coordinatorBaseURL: URL
        let targetNodeID: String
        let projectID: String?
    }

    let id: UUID
    let workingDirectory: URL
    let remoteConfiguration: RemoteConfiguration?
    private(set) var isRunning = false

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
        isRunning = false
    }
}
