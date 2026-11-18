import Foundation
import Protocols
import SloppyNodeCore

/// Pure preflight shared by server validation and contract tests. No networking or execution.
enum RemoteExecutionRegistry {
    static func validate(_ targets: [RemoteExecutionTarget]) throws {
        guard Set(targets.map(\.id)).count == targets.count,
              Set(targets.map(\.alias)).count == targets.count,
              targets.allSatisfy({ !$0.id.isEmpty && !$0.alias.isEmpty && !$0.nodeId.isEmpty && $0.maxConcurrentTasks > 0 }),
              targets.allSatisfy({ target in
                  !targets.contains { $0.id != target.id && ($0.alias == target.id || $0.id == target.alias) }
              }) else { throw RemoteExecutionError.invalidTarget }
    }

    /// Exact operator-owned ID or alias, never shell expansion or text heuristics.
    static func resolve(_ selection: RemoteExecutionSelection, projectID: String?, peerID: String,
                        targets: [RemoteExecutionTarget], nodes: [MeshNodeRecord]) throws -> RemoteExecutionSelection {
        try validate(targets)
        guard let target = targets.first(where: { $0.id == selection.targetId || $0.alias == selection.targetId }) else {
            throw RemoteExecutionError.invalidTarget
        }
        guard target.projectId == projectID, target.allowedAgentIds.contains(selection.agentId),
              target.allowedPeerIds.contains(peerID),
              selection.nodeId == nil || selection.nodeId == target.nodeId else { throw RemoteExecutionError.forbidden }
        guard [40, 64].contains(selection.baseRevision.count), selection.baseRevision.allSatisfy(\.isHexDigit) else {
            throw RemoteExecutionError.invalidBase
        }
        guard let node = nodes.first(where: { $0.id == target.nodeId }), node.status == .online else {
            throw RemoteExecutionError.offline
        }
        guard Set(target.requiredCapabilities + ["sloppy.core.remote"]).isSubset(of: Set(node.capabilities)) else {
            throw RemoteExecutionError.forbidden
        }
        var result = selection
        result.targetId = target.id
        result.nodeId = target.nodeId
        return result
    }

    static func validateReuse(original: RemoteExecutionSelection?, requested: RemoteExecutionSelection?,
                              originalProject: String?, requestedProject: String?, originalKeys: [String],
                              requestedKeys: [String], originalReadOnly: Bool, requestedReadOnly: Bool) throws {
        guard original?.targetId == requested?.targetId, original?.nodeId == requested?.nodeId,
              original?.baseRevision == requested?.baseRevision, original?.agentId == requested?.agentId,
              originalProject == requestedProject, Set(originalKeys) == Set(requestedKeys),
              !originalReadOnly || requestedReadOnly else { throw CoreService.SubagentReuseError.scopeMismatch }
    }

    /// No configuration override: transport execution has not passed its safety gates.
    static func requireSupportedExecutor() throws {
        throw RemoteExecutionError.unsupportedExecution
    }
}
