import Foundation

public typealias ProjectWorkflowJSONValue = ProjectAutomationJSONValue

public struct ProjectWorkflow: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let projectId: String
    public let name: String
    public let version: Int
    public let enabled: Bool
    public let lanes: [ProjectWorkflowLane]
    public let nodes: [ProjectWorkflowNode]
    public let edges: [ProjectWorkflowEdge]
}

public struct ProjectWorkflowLane: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let kind: String
    public let actorId: String?
    public let teamId: String?
}

public struct ProjectWorkflowNode: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let type: String
    public let title: String
    public let laneId: String
    public let config: [String: ProjectWorkflowJSONValue]
}

public struct ProjectWorkflowEdge: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let sourceNodeId: String
    public let targetNodeId: String
    public let conditionKey: String?
    public let condition: Condition?

    public struct Condition: Decodable, Sendable, Equatable {
        public let path: String
        public let equals: ProjectWorkflowJSONValue
    }

    public var label: String? {
        if let condition { return "\(condition.path) = \(ProjectWorkflowFormatting.json(condition.equals))" }
        return conditionKey
    }
}

public struct ProjectWorkflowRun: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let projectId: String
    public let workflowId: String
    public let workflowVersion: Int
    public let taskId: String?
    public let status: String
    public let currentNodeIds: [String]
    public let startedAt: Date
    public let finishedAt: Date?
}

public struct ProjectWorkflowRunDetail: Decodable, Sendable, Equatable {
    public let run: ProjectWorkflowRun
    public let steps: [ProjectWorkflowRunStep]
    public let pendingActions: [ProjectWorkflowPendingAction]
}

public struct ProjectWorkflowRunStep: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let runId: String
    public let nodeId: String
    public let status: String
    public let input: [String: ProjectWorkflowJSONValue]
    public let output: [String: ProjectWorkflowJSONValue]
    public let error: String?
    public let startedAt: Date
    public let finishedAt: Date?
}

public struct ProjectWorkflowPendingAction: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let nodeId: String
    public let prompt: String
    public let assignee: String
    public let resolvedAt: Date?
}

public enum ProjectWorkflowFormatting {
    public static func title(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    public static func json<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
