import Foundation
import Protocols
import SloppyNodeCore

extension CoreService {
    /// Deliberately operator-controlled, outside agent-writable project roots.
    func remoteExecutionTargets() throws -> [RemoteExecutionTarget] {
        let url = workspaceRootURL.appendingPathComponent("remote-execution-targets.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let targets = try JSONDecoder().decode([RemoteExecutionTarget].self, from: Data(contentsOf: url))
        try RemoteExecutionRegistry.validate(targets)
        return targets
    }

    func remoteTarget(_ selection: RemoteExecutionSelection, projectID: String?) throws -> RemoteExecutionTarget {
        guard let target = try remoteExecutionTargets().first(where: { $0.id == selection.targetId }),
              target.projectId == projectID, target.allowedAgentIds.contains(selection.agentId) else {
            throw RemoteExecutionError.invalidTarget
        }
        guard selection.nodeId == nil || selection.nodeId == target.nodeId else { throw RemoteExecutionError.forbidden }
        guard [40, 64].contains(selection.baseRevision.count), selection.baseRevision.allSatisfy(\.isHexDigit) else {
            throw RemoteExecutionError.invalidBase
        }
        return target
    }

    func resolveRemoteSelection(_ selection: RemoteExecutionSelection, projectID: String?) throws -> RemoteExecutionSelection {
        try RemoteExecutionRegistry.resolve(selection, projectID: projectID,
            peerID: nodeConfigStore.load().identity.nodeId,
            targets: remoteExecutionTargets(), nodes: nodeMeshStore.listNodes())
    }

    func validateRemoteDelegation(_ task: LongChatTaskRequest, parentID: String) throws {
        guard let selection = task.executionTarget else { return }
        _ = try resolveRemoteSelection(selection, projectID: task.projectId)
        if let reuse = task.reuseSessionId {
            guard let previous = try longChats().conversation(sessionId: parentID).assignments.flatMap(\.tasks).last(where: {
                $0.attempts.last?.remoteExecution?.remoteSessionId == reuse
            }) else { throw SubagentReuseError.unavailable }
            try RemoteExecutionRegistry.validateReuse(original: previous.executionTarget, requested: task.executionTarget,
                originalProject: previous.projectId, requestedProject: task.projectId,
                originalKeys: previous.resourceKeys, requestedKeys: task.resourceKeys,
                originalReadOnly: previous.readOnly ?? true, requestedReadOnly: task.readOnly ?? true)
        }
        try RemoteExecutionRegistry.requireSupportedExecutor()
    }

    /// Reserved authenticated Mesh method namespace. No remote task may start in this slice.
    func handleRemoteWorkerRPC(envelope: MeshEnvelope, method: String, params: JSONValue) async -> JSONValue {
        .object(["ok": .bool(false), "error": .object([
            "code": .string("remote_execution_unsupported"),
            "message": .string("Remote execution is not enabled in this build. No local fallback.")
        ])])
    }

    func remoteBinding(taskID: String) throws -> RemoteWorkerBinding? {
        try longChats().state.remoteExecutions?.values.first(where: { $0.remoteTaskId == taskID })
    }

    func sendRemoteWorkerRPC<T: Encodable>(target: RemoteExecutionTarget, method: String, request: T) async throws -> RemoteExecutionSnapshot {
        throw RemoteExecutionError.unsupportedExecution
    }

    func dispatchRemoteLongChatWorker(conversation: LongChatConversation, task: LongChatTask) {
        // Old experimental starts have uncertain outcomes; retain locks until operator reconciliation.
        guard let attempt = task.attempts.last else { return }
        try? longChats().updateTask(sessionId: conversation.sessionId, taskId: task.id) {
            guard $0.attempts.last?.id == attempt.id else { return }
            let i = $0.attempts.count - 1
            $0.attempts[i].automaticRetryAllowed = false
            $0.attempts[i].executionStopped = false
            $0.attempts[i].summary = "Remote execution unsupported in this build; operator reconciliation required. No local fallback."
        }
    }
}
