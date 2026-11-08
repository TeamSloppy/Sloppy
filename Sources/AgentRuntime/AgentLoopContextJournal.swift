import Foundation
import PluginSDK
import Protocols

public struct AgentLoopCompactionPlan: Sendable {
    public var checkpoint: SessionProjectionCheckpoint
    public var history: String
    public var sourceDigest: String
    public var projectedMessageIDs: Set<String>
    public var owner: AgentInputOwner
    public var inputBudget: Int

    public init(checkpoint: SessionProjectionCheckpoint, history: String, sourceDigest: String,
        projectedMessageIDs: Set<String>, owner: AgentInputOwner, inputBudget: Int) {
        self.checkpoint = checkpoint; self.history = history; self.sourceDigest = sourceDigest
        self.projectedMessageIDs = projectedMessageIDs; self.owner = owner; self.inputBudget = inputBudget
    }
}

/// Projection storage proposes and atomically commits a byte-bound summary; it never generates.
public protocol AgentLoopProjectionJournal: AgentLoopJournal {
    func makeCompactionPlan(for request: ModelStepRequest, inputBudget: Int) async throws -> AgentLoopCompactionPlan?
    func commitCompaction(_ plan: AgentLoopCompactionPlan, summary: String, request: ModelStepRequest) async throws -> ModelStepRequest
}

/// The loop explicitly requests a bounded context recovery from its runtime/storage bridge.
public protocol AgentLoopContextJournal: AgentLoopJournal {
    func compactContext(_ request: ModelStepRequest, inputBudget: Int) async throws -> ModelStepRequest?
}
