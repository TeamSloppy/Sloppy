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
            for id in try workflowExecutionFiles.identifiers() {
                guard !workflowIsStopping, !Task.isCancelled else { return }
                guard activeWorkflowRuns.insert(id).inserted else { continue }
                var restore = false
                do {
                    if let state = try workflowExecutionFiles.load(id) {
                        let journal = WorkflowExecutionJournal(state: state, files: workflowExecutionFiles, store: store)
                        workflowJournals[id] = journal
                        try await journal.flush()
                        if state.run.status == .waitingForAgent,
                           let step = state.steps.last(where: { $0.nodeId == state.run.currentNodeIds.first }),
                           let agentID = step.output["agentId"]?.asString, let sessionID = step.output["sessionId"]?.asString {
                            workflowWaitingSessions[sessionChannelID(agentID: agentID, sessionID: sessionID), default: []].insert(id)
                        }
                        restore = workflowNeedsRecovery(state)
                    }
                } catch { logger.error("workflow.checkpoint_restore_failed", metadata: ["run_id": .string(id), "error": .string(String(describing: error))]) }
                releaseWorkflowExecution(id)
                if restore { scheduleWorkflowRecovery(id) }
            }
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
            workflowRecoveryTasks[id] = nil
            if workflowReconciliationPending.remove(id) != nil { scheduleWorkflowRecovery(id) }
        }
        guard !workflowIsStopping, activeWorkflowRuns.insert(id).inserted else { return }
        defer { releaseWorkflowExecution(id) }
        do {
            guard let state = try workflowExecutionFiles.load(id), workflowNeedsRecovery(state) else { return }
            let journal = WorkflowExecutionJournal(state: state, files: workflowExecutionFiles, store: store)
            workflowJournals[id] = journal
            _ = await WorkflowRunner().restore(state: state.runnable, persistence: await journal.persistence,
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
        switch state.run.status {
        case .queued, .running, .waitingForAgent: return true
        case .waitingForHuman:
            return !state.actions.contains { $0.nodeId == state.run.currentNodeIds.first && $0.resolvedAt == nil }
        default: return false
        }
    }

    func releaseWorkflowExecution(_ id: String) {
        activeWorkflowRuns.remove(id)
        workflowJournals[id] = nil
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
