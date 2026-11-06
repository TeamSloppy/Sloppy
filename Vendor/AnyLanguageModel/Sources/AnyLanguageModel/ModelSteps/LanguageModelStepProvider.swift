import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One generation with schema-only tools. The caller owns tool execution and subsequent steps.
public protocol LanguageModelStepProvider: Sendable {
    func streamStep(_ request: LanguageModelStepRequest) -> AsyncThrowingStream<LanguageModelStepEvent, Error>
}

public struct StepCodeAssistSettings: Sendable {
    public var baseURL: URL
    public var projectID: @Sendable () -> String?
    public var headers: [String: String]
    public var userAgent: String
    public var refreshCredentials: (@Sendable () async throws -> Void)?
    public init(baseURL: URL, projectID: @escaping @Sendable () -> String?,
                headers: [String: String], userAgent: String,
                refreshCredentials: (@Sendable () async throws -> Void)? = nil) {
        self.baseURL = baseURL; self.projectID = projectID
        self.headers = headers; self.userAgent = userAgent
        self.refreshCredentials = refreshCredentials
    }
}

enum ModelStepEventDelivery {
    static func yield(_ event: LanguageModelStepEvent,
                      into continuation: AsyncThrowingStream<LanguageModelStepEvent, Error>.Continuation) async throws {
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
