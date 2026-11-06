import Foundation

/// Exactly one generation. There are declarations in the request, never executable tool closures.
/// Consumers require one final response and stream settlement before authorizing any tool.
public protocol ModelStepProvider: Sendable {
    func streamStep(_ request: ModelStepRequest) -> AsyncThrowingStream<ModelStepEvent, Error>
}

/// Optional companion capability. Existing ModelProvider witnesses and plugin boxes stay unchanged.
public protocol ModelStepProviderFactory: Sendable {
    func supportsModelSteps(for modelName: String) -> Bool
    func createModelStepProvider(for modelName: String, usageContext: ModelUsageContext?) async throws -> (any ModelStepProvider)?
}

/// For bufferingOldest streams, a dropped value is the new value, so the single producer
/// can suspend and retry it. Keep final/preview ordering without growing the event queue.
enum ModelStepEventDelivery {
    static func yield(_ event: ModelStepEvent,
                      into continuation: AsyncThrowingStream<ModelStepEvent, Error>.Continuation) async throws {
        while true {
            try Task.checkCancellation()
            switch continuation.yield(event) {
            case .enqueued: return
            case .terminated: throw CancellationError()
            case .dropped: try await Task.sleep(for: .milliseconds(1))
            @unknown default: throw CancellationError()
            }
        }
    }
}
