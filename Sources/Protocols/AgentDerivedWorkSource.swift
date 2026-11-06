import Foundation

/// Immutable provenance for internal work derived from a completed foreground run.
/// This envelope identifies the source; current policy must still authorize every effect.
public struct AgentDerivedWorkSource: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case memoryCheckpoint = "memory_checkpoint"
        case selfImprovementProposal = "self_improvement_proposal"
    }
    public var schemaVersion: Int = 1
    public var kind: Kind = .memoryCheckpoint
    public var agentID: String
    public var sessionID: String
    public var owner: AgentInputOwner
    public var terminalEventID: String
    public var model: String
    public var projectID: String?
    public var taskID: String?

    public init(agentID: String, sessionID: String, owner: AgentInputOwner,
                terminalEventID: String, model: String, projectID: String? = nil, taskID: String? = nil) {
        self.agentID = agentID; self.sessionID = sessionID; self.owner = owner
        self.terminalEventID = terminalEventID; self.model = model
        self.projectID = projectID; self.taskID = taskID
    }

    public var isValid: Bool {
        schemaVersion == 1 && !agentID.isEmpty && !sessionID.isEmpty && !owner.runId.isEmpty &&
            !owner.userTurnId.isEmpty && owner.generation >= 0 && !terminalEventID.isEmpty && !model.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, kind, owner, model
        case agentID = "agentId", sessionID = "sessionId", terminalEventID = "terminalEventId"
        case projectID = "projectId", taskID = "taskId"
    }
}
