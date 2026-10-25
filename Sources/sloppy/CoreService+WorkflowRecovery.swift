import Foundation
import Protocols

extension CoreService {
    func restoreWorkflowExecutionsIfNeeded() async {
        guard !workflowIsStopping else { return }
        if let task = workflowRecoveryIndexTask { await task.value; return }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.indexWorkflowExecutions()
        }
        workflowRecoveryIndexTask = task
        await task.value
    }

    private func indexWorkflowExecutions() async {
        do {
            var pending: [String] = []
            for id in try workflowExecutionFiles.identifiers() {
                guard !workflowIsStopping, !Task.isCancelled else { return }
                guard activeWorkflowRuns.insert(id).inserted else { continue }
                var restore = false
                do {
                    if let state = try workflowExecutionFiles.load(id) {
                        let journal = WorkflowExecutionJournal(state: state, files: workflowExecutionFiles, store: store)
                        workflowJournals[id] = journal
                        try await journal.flush()
                        registerWorkflowTaskOwner(state)
                        registerWorkflowWaits(state)
                        registerWorkflowChildWaits(state)
                        restore = workflowNeedsRecovery(state)
                    }
                } catch { logger.error("workflow.checkpoint_restore_failed", metadata: ["run_id": .string(id), "error": .string(String(describing: error))]) }
                releaseWorkflowExecution(id)
                if restore { pending.append(id) }
            }
            // All parent/child bindings must be registered before any child can resume.
            for id in pending { scheduleWorkflowRecovery(id) }
        } catch { logger.error("workflow.checkpoint_index_failed", metadata: ["error": .string(String(describing: error))]) }
    }

    func scheduleWorkflowRecovery(_ id: String) {
        guard !workflowIsStopping, workflowRecoveryTasks[id] == nil else { return }
        workflowRecoveryTasks[id] = Task { [weak self] in
            guard let self else { return }
            await self.recoverWorkflow(id)
        }
    }

    private func recoverWorkflow(_ id: String) async {
        defer {
            notifyWorkflowParents(id)
            workflowRecoveryTasks[id] = nil
            if !activeWorkflowRuns.contains(id), workflowReconciliationPending.remove(id) != nil { scheduleWorkflowRecovery(id) }
        }
        guard !workflowIsStopping, activeWorkflowRuns.insert(id).inserted else { return }
        defer { releaseWorkflowExecution(id) }
        do {
            guard let state = try workflowExecutionFiles.load(id), workflowNeedsRecovery(state) else { return }
            if workflowChildLostRace(id) {
                _ = try await cancelWorkflowRun(projectID: state.run.projectId, runID: id, request: .init(userId: "workflow"))
                return
            }
            let journal = WorkflowExecutionJournal(state: state, files: workflowExecutionFiles, store: store)
            workflowJournals[id] = journal
            guard try await prepareWorkflowEnvironment(journal) else { return }
            let prepared = await journal.snapshot()
            _ = await WorkflowRunner().restore(state: prepared.runnable, persistence: await journal.persistence,
                updateTask: workflowTaskUpdater(), executeTool: { [weak self] node, context, input in
                    await self?.executeWorkflowToolNode(node: node, context: context, input: input)
                })
            guard await !journal.suspended, await !journal.failed else { return }
            _ = try await finishWaitingWorkflowAgent(journal: journal)
        } catch {
            if !workflowIsStopping { logger.error("workflow.recovery_failed", metadata: ["run_id": .string(id), "error": .string(String(describing: error))]) }
        }
    }

    private func workflowNeedsRecovery(_ state: WorkflowExecutionState) -> Bool {
        if state.parallel != nil, ![WorkflowRunStatus.completed, .failed, .blocked, .cancelled].contains(state.run.status) { return true }
        switch state.run.status {
        case .queued, .running, .waitingForAgent, .waitingForWorkflow: return true
        case .waitingForHuman:
            return !state.actions.contains { $0.nodeId == state.run.currentNodeIds.first && $0.resolvedAt == nil }
        default: return false
        }
    }

    func releaseWorkflowExecution(_ id: String) {
        activeWorkflowRuns.remove(id)
        workflowJournals[id] = nil
        if let state = try? workflowExecutionFiles.load(id) { registerWorkflowTaskOwner(state) }
        else { for key in Array(workflowTaskOwners.keys) where workflowTaskOwners[key] == id { workflowTaskOwners[key] = nil } }
        if workflowRecoveryTasks[id] == nil, workflowReconciliationPending.remove(id) != nil { scheduleWorkflowRecovery(id) }
    }

    func stopWorkflowExecutions() async {
        workflowIsStopping = true
        workflowRecoveryIndexTask?.cancel()
        for journal in Array(workflowJournals.values) {
            do { try await journal.suspend() }
            catch { logger.error("workflow.shutdown_checkpoint_failed", metadata: ["error": .string(String(describing: error))]) }
        }
        await workflowRecoveryIndexTask?.value
        for task in workflowRecoveryTasks.values { task.cancel() }
    }
}
