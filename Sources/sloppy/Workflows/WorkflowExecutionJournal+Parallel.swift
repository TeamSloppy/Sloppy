import Foundation
import Protocols

extension WorkflowExecutionJournal {
    func beginParallel(_ parallel: WorkflowParallelState) async throws {
        state.parallel = parallel
        try await flush()
    }

    func branchPersistence(_ id: String) -> WorkflowRunner.Persistence {
        .init(saveRun: { try await self.saveBranch(id, run: $0) },
              saveStep: { try await self.saveBranch(id, step: $0) },
              saveAction: { try await self.saveBranch(id, action: $0) })
    }

    private func saveBranch(_ id: String, run: WorkflowRun) async throws {
        guard let index = state.parallel?.branches.firstIndex(where: { $0.id == id }) else { throw CoreService.WorkflowError.storageFailure }
        state.parallel?.branches[index].run = run
        let cursors = state.parallel?.branches.filter { $0.run.status != .completed }.flatMap { $0.run.currentNodeIds } ?? []
        state.run.currentNodeIds = cursors.isEmpty ? [state.parallel?.nodeID ?? ""] : cursors
        let statuses = state.parallel?.branches.map { $0.run.status } ?? []
        if statuses.allSatisfy({ [.waitingForHuman, .waitingForAgent, .waitingForWorkflow, .completed].contains($0) }) {
            state.run.status = statuses.contains(.waitingForHuman) ? .waitingForHuman : statuses.contains(.waitingForAgent) ? .waitingForAgent : statuses.contains(.waitingForWorkflow) ? .waitingForWorkflow : .running
        } else { state.run.status = .running }
        try await persistParallelChange()
    }

    private func saveBranch(_ id: String, step: WorkflowRunStep) async throws {
        guard let parallel = state.parallel, let index = parallel.branches.firstIndex(where: { $0.id == id }) else { throw CoreService.WorkflowError.storageFailure }
        var branch = parallel.branches[index]
        if let retry = branch.retryStepId, step.id != retry, branch.steps.first(where: { $0.id == retry })?.nodeId == step.nodeId { branch.retryStepId = nil }
        if let existing = branch.steps.firstIndex(where: { $0.id == step.id }) { branch.steps[existing] = step } else { branch.steps.append(step) }
        state.parallel?.branches[index] = branch
        var visible = step
        visible.runId = state.run.id
        if let existing = state.steps.firstIndex(where: { $0.id == step.id }) { state.steps[existing] = visible } else { state.steps.append(visible) }
        try await persistParallelChange(step: visible)
    }

    private func saveBranch(_ id: String, action: WorkflowPendingAction) async throws {
        guard let index = state.parallel?.branches.firstIndex(where: { $0.id == id }) else { throw CoreService.WorkflowError.storageFailure }
        state.parallel?.branches[index].actions.append(action)
        var visible = action
        visible.workflowRunId = state.run.id
        state.actions.append(visible)
        try await persistParallelChange(action: visible)
    }

    func selectParallelWinner(_ id: String) async throws {
        guard state.parallel?.winner == nil, state.parallel?.branches.contains(where: { $0.id == id && $0.run.status == .completed }) == true else { return }
        state.parallel?.winner = id
        try await persistParallelChange()
    }

    func recordBranchFailure(_ id: String, message: String, code: String) async throws {
        guard let index = state.parallel?.branches.firstIndex(where: { $0.id == id }) else { throw CoreService.WorkflowError.storageFailure }
        state.parallel?.branches[index].failure = message
        state.parallel?.branches[index].failureCode = code
        if code == "workflow_cancelled" { state.parallel?.branches[index].run.status = .cancelled }
        try await persistParallelChange()
    }

    func cancelParallelWaits() async throws {
        guard var parallel = state.parallel else { return }
        let date = Date()
        for index in parallel.branches.indices where parallel.branches[index].run.status != .completed {
            for actionIndex in parallel.branches[index].actions.indices where parallel.branches[index].actions[actionIndex].resolvedAt == nil {
                parallel.branches[index].actions[actionIndex].resolvedAt = date
                let action = parallel.branches[index].actions[actionIndex]
                if let position = state.actions.firstIndex(where: { $0.id == action.id }) { state.actions[position].resolvedAt = date }
            }
            for stepIndex in parallel.branches[index].steps.indices where parallel.branches[index].steps[stepIndex].status == .waiting {
                parallel.branches[index].steps[stepIndex].status = .skipped
                parallel.branches[index].steps[stepIndex].error = "Cancelled because another parallel branch stopped."
                parallel.branches[index].steps[stepIndex].finishedAt = date
                var step = parallel.branches[index].steps[stepIndex]
                step.runId = state.run.id
                if let position = state.steps.firstIndex(where: { $0.id == step.id }) { state.steps[position] = step }
            }
        }
        state.parallel = parallel
        state.run.currentNodeIds = [parallel.nodeID]
        state.run.status = .running
        try await flush()
    }
}
