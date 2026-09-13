import Foundation

/// CPU work explicitly leaves the caller's actor, including with Swift 6.2
/// caller-isolated async defaults. Cancellation remains with the calling task.
public enum ClientBackgroundWork {
    @concurrent
    public static func run<Value: Sendable>(
        _ operation: @Sendable () throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        let value = try operation()
        try Task.checkCancellation()
        return value
    }
}
