import Foundation

public struct WorkflowRunRetryRequest: Codable, Sendable, Equatable {
    public enum Decision: String, Codable, Sendable { case retry; case acceptResult = "accept_result" }
    public var stepId: String
    public var decision: Decision
    public var evidence: String
    public var output: [String: JSONValue]?
    public var userId: String
    public init(stepId: String, decision: Decision, evidence: String, output: [String: JSONValue]? = nil, userId: String) {
        self.stepId = stepId; self.decision = decision; self.evidence = evidence; self.output = output; self.userId = userId
    }
}

public struct WorkflowRunCancelRequest: Codable, Sendable {
    public var userId: String
    public init(userId: String) { self.userId = userId }
}

public struct WorkflowReconciliation: Codable, Sendable, Equatable {
    public var request: WorkflowRunRetryRequest
    public var previousStep: WorkflowRunStep
    public var createdAt: Date
    public init(request: WorkflowRunRetryRequest, previousStep: WorkflowRunStep, createdAt: Date = Date()) {
        self.request = request; self.previousStep = previousStep; self.createdAt = createdAt
    }
}
