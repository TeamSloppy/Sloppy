import Foundation

/// Explicit location; agent and model remain independent selections.
public struct RemoteExecutionSelection: Codable, Sendable, Equatable {
    public var targetId: String
    /// Filled by the server; prevents registry remapping from moving an existing worker.
    public var nodeId: String?
    public var baseRevision: String
    public var agentId: String
    public var selectedModel: String?

    public init(targetId: String, baseRevision: String, agentId: String, selectedModel: String? = nil, nodeId: String? = nil) {
        self.nodeId = nodeId
        self.targetId = targetId
        self.baseRevision = baseRevision
        self.agentId = agentId
        self.selectedModel = selectedModel
    }
}

/// Operator-owned registry. Aliases are data, never environment substitutions.
public struct RemoteExecutionTarget: Codable, Sendable, Equatable {
    public var id: String
    public var alias: String
    public var nodeId: String
    public var projectId: String
    public var sharedProjectId: String
    public var allowedPeerIds: [String]
    public var allowedAgentIds: [String]
    public var toolIDs: [String]
    public var requiredCapabilities: [String]
    public var maxConcurrentTasks: Int

    public init(id: String, alias: String, nodeId: String, projectId: String, sharedProjectId: String,
                allowedPeerIds: [String], allowedAgentIds: [String], toolIDs: [String],
                requiredCapabilities: [String], maxConcurrentTasks: Int) {
        self.id = id
        self.alias = alias
        self.nodeId = nodeId
        self.projectId = projectId
        self.sharedProjectId = sharedProjectId
        self.allowedPeerIds = allowedPeerIds
        self.allowedAgentIds = allowedAgentIds
        self.toolIDs = toolIDs
        self.requiredCapabilities = requiredCapabilities
        self.maxConcurrentTasks = maxConcurrentTasks
    }
}

public struct RemoteWorkerStart: Codable, Sendable, Equatable {
    public var parentSessionId: String
    public var taskId: String
    public var attemptId: String
    public var selection: RemoteExecutionSelection
    public var projectId: String
    public var title: String
    public var objective: String
    public var readOnly: Bool
    public var toolIDs: [String]

    public init(
        parentSessionId: String, taskId: String, attemptId: String, selection: RemoteExecutionSelection,
        projectId: String, title: String, objective: String, readOnly: Bool, toolIDs: [String]
    ) {
        self.parentSessionId = parentSessionId
        self.taskId = taskId
        self.attemptId = attemptId
        self.selection = selection
        self.projectId = projectId
        self.title = title
        self.objective = objective
        self.readOnly = readOnly
        self.toolIDs = toolIDs
    }
}

public struct RemoteWorkerOperation: Codable, Sendable {
    public var attemptId: String
    public var cursor: Int?
    public var messageId: String?
    public var content: String?

    public init(attemptId: String, cursor: Int? = nil, messageId: String? = nil, content: String? = nil) {
        self.attemptId = attemptId
        self.cursor = cursor
        self.messageId = messageId
        self.content = content
    }
}

public struct RemoteExecutionSnapshot: Codable, Sendable, Equatable {
    public var nodeId: String
    public var parentSessionId: String
    public var taskId: String
    public var attemptId: String
    public var remoteAgentId: String
    public var remoteSessionId: String?
    public var status: LongChatTaskStatus
    public var cursor: Int
    public var summary: String?
    public var executionStopped: Bool
    public var evidence: [String]
    public var artifacts: [String]
    public var baseRevision: String
    public var diff: String?
    public var diffSizeBytes: Int?
    public var diffSHA256: String?
    public var resultApplied: Bool

    public init(
        nodeId: String, parentSessionId: String, taskId: String, attemptId: String,
        remoteAgentId: String, remoteSessionId: String?, status: LongChatTaskStatus, cursor: Int,
        summary: String?, executionStopped: Bool, evidence: [String], artifacts: [String],
        baseRevision: String, diff: String?, diffSizeBytes: Int?, diffSHA256: String?, resultApplied: Bool
    ) {
        self.nodeId = nodeId
        self.parentSessionId = parentSessionId
        self.taskId = taskId
        self.attemptId = attemptId
        self.remoteAgentId = remoteAgentId
        self.remoteSessionId = remoteSessionId
        self.status = status
        self.cursor = cursor
        self.summary = summary
        self.executionStopped = executionStopped
        self.evidence = evidence
        self.artifacts = artifacts
        self.baseRevision = baseRevision
        self.diff = diff
        self.diffSizeBytes = diffSizeBytes
        self.diffSHA256 = diffSHA256
        self.resultApplied = resultApplied
    }
}
