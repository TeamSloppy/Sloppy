import Foundation
import Protocols

enum WorkflowSessionPolicy: String {
    case new, shared, compact

    static func mode(_ node: WorkflowNode) -> Self? {
        guard let value = node.config["sessionMode"] else { return .new }
        return value.asString.flatMap(Self.init(rawValue:))
    }

    static func validationIssue(node: WorkflowNode, definition: WorkflowDefinition) -> String? {
        guard node.config["sessionMode"] != nil || node.config["sessionSourceNodeId"] != nil else { return nil }
        guard node.type == .agentStep, let mode = mode(node) else {
            return "sessionMode must be new, shared or compact on an agent step."
        }
        guard mode != .new else {
            return node.config["sessionSourceNodeId"] == nil ? nil : "A session source requires shared mode."
        }
        guard let sourceID = node.config["sessionSourceNodeId"]?.asString, sourceID != node.id,
              let source = definition.nodes.first(where: { $0.id == sourceID }), source.type == .agentStep,
              let agentID = node.config["agentId"]?.asString, !agentID.isEmpty,
              (mode == .compact || source.config["agentId"]?.asString == agentID) else {
            return "Shared sessions require a different source agent step using the same agent."
        }
        var ancestors: Set<String> = []
        var pending = [node.id]
        while let target = pending.popLast() {
            for edge in definition.edges where edge.targetNodeId == target {
                if ancestors.insert(edge.sourceNodeId).inserted { pending.append(edge.sourceNodeId) }
            }
        }
        return ancestors.contains(sourceID) ? nil : "The shared-session source must precede this step in the graph."
    }
}

extension CoreService {
    func selectWorkflowAgentSession(node: WorkflowNode, context: WorkflowRunner.Context, input: [String: JSONValue], agentID: String) async throws -> AgentSessionSummary {
        guard let policy = WorkflowSessionPolicy.mode(node) else {
            throw WorkflowGraphContracts.Violation("Invalid workflow session policy.")
        }
        if policy == .new {
            return try await createAgentSession(agentID: agentID, request: .init(title: "Workflow: \(node.title)", separateChat: true,
                projectId: context.projectId, taskId: context.taskId))
        }
        guard let source = node.config["sessionSourceNodeId"]?.asString,
              let output = input["nodes"]?.asObject?[source]?.asObject?["output"]?.asObject,
              output["agentId"]?.asString == agentID, output["agentOutcome"]?.asString == ExecutionState.completed.rawValue,
              let sessionID = output["sessionId"]?.asString else {
            throw WorkflowGraphContracts.Violation("The shared-session source has no completed output in this run.")
        }
        let detail = try getAgentSession(agentID: agentID, sessionID: sessionID)
        guard detail.summary.projectId == context.projectId, detail.summary.taskId == context.taskId else {
            throw WorkflowGraphContracts.Violation("Shared session belongs to a different project or task.")
        }
        let status = detail.events.filter { $0.importOrigin == nil }.compactMap(\.runStatus).last
        guard status?.stage == .done, status?.executionOutcome?.state == .completed else {
            throw WorkflowGraphContracts.Violation("Shared session must be completed and idle before the next step.")
        }
        return detail.summary
    }

    static func workflowAgentEvents(_ events: [AgentSessionEvent], output: [String: JSONValue]) throws -> [AgentSessionEvent] {
        // Legacy checkpoints contain fresh sessions and have no boundary marker.
        guard let cursor = output["sessionAfterEventId"], cursor != .null else { return events.filter { $0.importOrigin == nil } }
        guard let id = cursor.asString, let index = events.lastIndex(where: { $0.id == id }) else {
            throw WorkflowGraphContracts.Violation("Workflow session history no longer contains the saved step boundary.")
        }
        return events.dropFirst(index + 1).filter { $0.importOrigin == nil }
    }
}
