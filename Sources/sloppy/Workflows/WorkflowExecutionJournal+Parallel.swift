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
        try await persistParallelChange()
    }

    private func saveBranch(_ id: String, step: WorkflowRunStep) async throws {
        guard let parallel = state.parallel, let index = parallel.branches.firstIndex(where: { $0.id == id }) else { throw CoreService.WorkflowError.storageFailure }
        var branch = parallel.branches[index]
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
}
