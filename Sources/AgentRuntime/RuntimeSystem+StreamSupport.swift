import Foundation

struct StreamIdleTimeoutError: Error, LocalizedError {
    var errorDescription: String? { "Model stream idle timeout" }
}

/// Legacy name retained while transport consumers migrate to the turn-owned state.
typealias StreamActivityTracker = RunState
