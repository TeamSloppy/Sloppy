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

public typealias AgentUISubmission = A2UISubmission
public typealias AgentUIComponent = A2UIComponent

public struct AgentUIActionReceipt: Codable, Sendable {
    public var actionId: String
    public var surfaceId: String
    public var revision: Int
    public var status: String
    public init(actionId: String, surfaceId: String, revision: Int, status: String) {
        self.actionId = actionId; self.surfaceId = surfaceId; self.revision = revision; self.status = status
    }
}
