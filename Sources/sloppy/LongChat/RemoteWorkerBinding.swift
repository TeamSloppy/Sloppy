import Foundation
import Protocols

/// Transport binding onto the existing durable Long Chat queue, not a second scheduler.
struct RemoteWorkerBinding: Codable, Sendable {
    var peerId: String
    var request: RemoteWorkerStart
    var remoteParentId: String
    var remoteTaskId: String?
    var worktreePath: String?
    var preparationFailed: Bool
}

enum RemoteExecutionError: Error, LocalizedError, Equatable {
    case invalidTarget, offline, forbidden, capacity, conflictingStart, interruptedPreparation, invalidBase, resultTooLarge, unsupportedExecution
    var errorDescription: String? {
        "Remote execution error (\(String(describing: self))). No local fallback was attempted."
    }
}
