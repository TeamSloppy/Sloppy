import SloppyA2UI

public typealias AgentUISurfaceSnapshot = A2UISurfaceSnapshot
public typealias AgentUITransaction = A2UITransaction
public typealias AgentUITransactionFailure = A2UITransaction.Failure

public struct AgentUIRenderRequest: Codable, Sendable {
    public var messages: String
    public var expectedRevision: Int
    public var fallbackText: String

    public init(messages: String, expectedRevision: Int, fallbackText: String) {
        self.messages = messages
        self.expectedRevision = expectedRevision
        self.fallbackText = fallbackText
    }
}
