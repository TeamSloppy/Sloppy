import Foundation
import Protocols

extension CoreService {
    public func retryWorkflowRun(projectID: String, runID: String, request: WorkflowRunRetryRequest) async throws -> WorkflowRunDetail {
        var request = request
        await restoreWorkflowExecutionsIfNeeded()
        for _ in 0..<100 where activeWorkflowRuns.contains(runID) {
            guard let saved = try workflowExecutionFiles.load(runID), [.failed, .blocked, .cancelled].contains(saved.run.status) else { throw WorkflowError.invalidPayload }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard !workflowIsStopping, !activeWorkflowRuns.contains(runID), !request.evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !request.userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let state = try workflowExecutionFiles.load(runID), state.run.projectId == projectID,
              [.failed, .blocked, .cancelled].contains(state.run.status),
              let step = state.steps.first(where: { $0.id == request.stepId }),
              state.steps.last(where: { $0.nodeId == step.nodeId })?.id == step.id,
              [.failed, .waiting, .skipped].contains(step.status) else { throw WorkflowError.invalidPayload }
        if let task = state.run.taskId {
            guard !projectExecutionSessions.values.contains(where: { $0.projectID == projectID && $0.taskID == task }) else { throw ProjectError.conflict }
            if let owner = workflowTaskOwner(projectID: projectID, taskID: task), owner != runID,
               !workflowOwnsDescendant(owner, runID: runID), !workflowOwnsDescendant(runID, runID: owner) { throw ProjectError.conflict }
        }
        if request.decision == .acceptResult {
            guard var output = request.output else { throw WorkflowError.invalidPayload }
            if step.nodeId == "__environment", let binding = state.run.environment { try await validateWorkflowEnvironment(binding) }
            else {
                guard let node = state.definition.nodes.first(where: { $0.id == step.nodeId }) else { throw WorkflowError.invalidPayload }
                if ["bash", "code"].contains(WorkflowGraphContracts.blockKind(node)), output["exitCode"] != .number(0) { throw WorkflowError.invalidPayload }
                if node.type == .agentStep {
                    guard let agent = step.output["agentId"]?.asString, let session = step.output["sessionId"]?.asString else { throw WorkflowError.invalidPayload }
                    if let supplied = output["agentId"], supplied != .string(agent) { throw WorkflowError.invalidPayload }
                    if let supplied = output["sessionId"], supplied != .string(session) { throw WorkflowError.invalidPayload }
                    let detail = try getAgentSession(agentID: agent, sessionID: session)
                    let result = Self.workflowAgentResult(response: .init(summary: detail.summary, appendedEvents: detail.events, routeDecision: nil), output: step.output)
                    guard result.ok else { throw WorkflowError.invalidPayload }
                    let reserved: Set<String> = ["agentId", "sessionId", "sessionAfterEventId", "agentOutcome", "agentStage", "model", "status", "tool", "errorCode", "contextPhase", "handoffSummary", "compactSourceSessionId", "compactSessionId"]
                    var accepted = (result.data?.asObject ?? [:]).merging(output.filter { !reserved.contains($0.key) }) { _, verified in verified }
                    for key in ["sessionAfterEventId", "contextPhase", "handoffSummary", "compactSourceSessionId", "compactSessionId"] { accepted[key] = step.output[key] }
                    accepted["status"] = .string("succeeded"); accepted["tool"] = .string("workflow.agent")
                    accepted.removeValue(forKey: "errorCode"); accepted.removeValue(forKey: "agentStage")
                    output = accepted
                }
                if node.type == .parallel {
                    guard let parallel = state.parallel, parallel.winner != nil || parallel.branches.allSatisfy({ $0.run.status == .completed }) else { throw WorkflowError.invalidPayload }
                    let selected = parallel.branches.filter { parallel.winner == nil || $0.id == parallel.winner }
                    output["branches"] = .object(Dictionary(uniqueKeysWithValues: selected.map { branch in
                        (branch.id, JSONValue.object(branch.steps.last(where: { $0.status == .succeeded })?.output ?? [:]))
                    }))
                    output["status"] = .string("succeeded"); output["tool"] = .string("workflow.parallel")
                }
                if node.type == .notify || WorkflowGraphContracts.blockKind(node) == "channel", output["delivered"] != .bool(true) { throw WorkflowError.invalidPayload }
                if WorkflowGraphContracts.blockKind(node) == "sub_workflow" {
                    guard let child = step.output["childRunId"]?.asString, let childState = try workflowExecutionFiles.load(child), childState.run.status == .completed else { throw WorkflowError.invalidPayload }
                    output = ["childRunId": .string(child), "childWorkflowId": .string(childState.run.workflowId), "childStatus": .string("completed"),
                        "childWorkflowVersion": .number(Double(childState.run.workflowVersion)),
                        "nodes": .object(childState.steps.filter { $0.status == .succeeded }.reduce(into: [:]) { $0[$1.nodeId] = .object($1.output) })]
                }
                try WorkflowOutputContract.validate(node: node, output: output)
                request.output = output
            }
        }
        if state.definition.nodes.contains(where: { $0.id == step.nodeId && $0.type == .parallel }), state.parallel == nil { throw WorkflowError.invalidPayload }
        guard activeWorkflowRuns.insert(runID).inserted else { throw WorkflowError.invalidPayload }
        defer { releaseWorkflowExecution(runID) }
        let journal = WorkflowExecutionJournal(state: state, files: workflowExecutionFiles, store: store)
        workflowJournals[runID] = journal
        try await journal.reconcile(request)
        let updated = await journal.snapshot()
        registerWorkflowTaskOwner(updated)
        if updated.run.status != .blocked { workflowReconciliationPending.insert(runID) }
        notifyWorkflowParents(runID)
        return await workflowRunDetail(run: updated.run)
    }

    public func cancelWorkflowRun(projectID: String, runID: String, request: WorkflowRunCancelRequest) async throws -> WorkflowRunDetail {
        await restoreWorkflowExecutionsIfNeeded()
        guard !workflowIsStopping, !request.userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let run = await store.getWorkflowRun(id: runID), run.projectId == projectID else { throw WorkflowError.runNotFound }
        let journal = try await workflowJournal(run: run)
        let state = await journal.snapshot()
        if [.completed, .failed, .cancelled].contains(state.run.status) { return await workflowRunDetail(run: state.run) }
        try await journal.cancelRun()
        registerWorkflowWaits(await journal.snapshot()); registerWorkflowChildWaits(await journal.snapshot())
        workflowRecoveryTasks[runID]?.cancel()
        let native = state.steps.filter { [.running, .waiting].contains($0.status) && $0.output["sessionId"] != nil }
        await cancelParallelAgentWaits(native)
        await cancelParallelChildWaits(state)
        for id in [runID] + (state.parallel?.branches.map { $0.run.id } ?? []) { await toolExecution.cleanupSessionProcesses("workflow-\(id)") }
        notifyWorkflowParents(runID)
        return await workflowRunDetail(run: journal.snapshot().run)
    }

    func cancelParallelChildWaits(_ state: WorkflowExecutionState, except winner: String? = nil) async {
        let winningNodes = state.parallel?.branches.first(where: { $0.id == winner })?.steps.map(\.nodeId) ?? []
        for step in state.steps where !winningNodes.contains(step.nodeId) && step.status != .succeeded {
            guard state.definition.nodes.contains(where: { $0.id == step.nodeId && WorkflowGraphContracts.blockKind($0) == "sub_workflow" }),
                  let child = step.output["childRunId"]?.asString,
                  let childState = try? workflowExecutionFiles.load(child), childState.run.projectId == state.run.projectId,
                  childState.originalInput["__workflowAncestors"]?.asArray?.contains(.string(state.definition.id)) == true,
                  state.definition.nodes.first(where: { $0.id == step.nodeId })?.config["workflowId"]?.asString == childState.run.workflowId else { continue }
            _ = try? await cancelWorkflowRun(projectID: state.run.projectId, runID: child, request: .init(userId: "workflow"))
        }
    }
}
