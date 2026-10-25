import Foundation
import Protocols

extension WorkflowExecutionJournal {
    func reconcile(_ request: WorkflowRunRetryRequest) async throws {
        guard let index = state.steps.firstIndex(where: { $0.id == request.stepId }) else { throw CoreService.WorkflowError.invalidPayload }
        let original = state.steps[index]
        state.reconciliations = (state.reconciliations ?? []) + [.init(request: request, previousStep: original)]
        if original.nodeId == "__environment", var binding = state.run.environment {
            binding.error = nil
            binding.preparation = request.decision == .acceptResult ? .ready
                : binding.request.mode == .newWorktree && FileManager.default.fileExists(atPath: binding.workingDirectory) ? .creating : .pending
            state.run.environment = binding
            state.originalInput["environment"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(binding))
            state.steps[index].status = .succeeded
            if state.run.currentNodeIds.isEmpty { state.run.status = .queued }
            else { state.run.status = .running }
        } else {
            if request.decision == .acceptResult {
                state.steps[index].status = .succeeded
                state.steps[index].output = request.output ?? [:]
                state.steps[index].error = nil
                state.steps[index].finishedAt = Date()
            }
            if var parallel = state.parallel {
                if original.id == parallel.stepID {
                    if request.decision == .acceptResult {
                        state.parallel = nil
                        let accepted = state.steps[index]
                        state.steps.removeAll { $0.id == accepted.id }
                        state.steps.append(accepted)
                    }
                    else {
                        for position in parallel.branches.indices where parallel.branches[position].run.status != .completed {
                            parallel.branches[position].retryStepId = parallel.branches[position].steps.last?.id
                            parallel.branches[position].run.status = parallel.branches[position].steps.isEmpty ? .queued : .running
                            if parallel.branches[position].run.currentNodeIds.isEmpty { parallel.branches[position].run.currentNodeIds = [parallel.branches[position].steps.last?.nodeId ?? parallel.branches[position].id] }
                            parallel.branches[position].failure = nil; parallel.branches[position].failureCode = nil
                        }
                        parallel.winner = nil
                        state.parallel = parallel
                    }
                } else {
                    guard let branch = parallel.branches.firstIndex(where: { $0.steps.contains { $0.id == original.id } }),
                          let attempt = parallel.branches[branch].steps.firstIndex(where: { $0.id == original.id }) else { throw CoreService.WorkflowError.invalidPayload }
                    if request.decision == .acceptResult {
                        var accepted = state.steps[index]; accepted.runId = parallel.branches[branch].run.id
                        parallel.branches[branch].steps[attempt] = accepted
                    } else { parallel.branches[branch].retryStepId = original.id }
                    parallel.branches[branch].run.status = .running
                    parallel.branches[branch].run.currentNodeIds = [original.nodeId]
                    parallel.branches[branch].failure = nil; parallel.branches[branch].failureCode = nil
                    state.parallel = parallel
                }
                if var prepared = state.parallel {
                    let unresolved = prepared.branches.contains { [.failed, .blocked, .cancelled].contains($0.run.status) }
                    if unresolved {
                        state.run.status = .blocked
                        state.run.finishedAt = nil
                        try await flush()
                        return
                    }
                    let parent = WorkflowRunStep(id: "step_\(UUID().uuidString.lowercased())", runId: state.run.id,
                        nodeId: prepared.nodeID, status: .running,
                        input: state.steps.first(where: { $0.id == prepared.stepID })?.input ?? [:], startedAt: Date())
                    state.steps.append(parent)
                    prepared.stepID = parent.id; state.parallel = prepared
                    state.run.currentNodeIds = [prepared.nodeID]
                } else { state.run.currentNodeIds = [original.nodeId] }
            } else {
                state.run.currentNodeIds = [original.nodeId]
                state.retryStepId = request.decision == .retry ? original.id : nil
            }
            state.run.status = .running
        }
        state.run.finishedAt = nil
        try await flush()
    }

    func cancelRun() async throws {
        state.run.status = .cancelled; state.run.finishedAt = Date()
        for index in state.actions.indices where state.actions[index].resolvedAt == nil { state.actions[index].resolvedAt = Date() }
        for index in state.steps.indices where [.running, .waiting].contains(state.steps[index].status) {
            state.steps[index].status = .waiting
            state.steps[index].error = "Execution cancelled. Reconcile external effects before retry."
        }
        if state.steps.isEmpty, let trigger = state.definition.nodes.first(where: { $0.type == .trigger }) {
            state.steps.append(.init(id: "step_\(UUID().uuidString.lowercased())", runId: state.run.id, nodeId: trigger.id, status: .skipped, startedAt: Date()))
        }
        try await flush()
        suspended = true
        signalParallelInput()
    }
}
