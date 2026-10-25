import Foundation
import Protocols

extension CoreService {
    func reconcileWorkflowAgentSession(agentID: String, sessionID: String, response: AgentSessionMessageResponse? = nil) async {
        guard !workflowIsStopping else { return }
        do {
            let key = sessionChannelID(agentID: agentID, sessionID: sessionID)
            for runID in workflowWaitingSessions[key] ?? [] {
                guard let state = try workflowExecutionFiles.load(runID) else {
                    workflowWaitingSessions[key]?.remove(runID)
                    continue
                }
                if activeWorkflowRuns.contains(runID) {
                    if state.parallel != nil, let journal = workflowJournals[runID] { await journal.signalParallelInput() }
                    else { workflowReconciliationPending.insert(runID) }
                    continue
                }
                guard workflowWaitingAgentSteps(state).contains(where: {
                    $0.output["agentId"]?.asString == agentID && $0.output["sessionId"]?.asString == sessionID
                }) else { continue }
                activeWorkflowRuns.insert(state.run.id)
                let journal = WorkflowExecutionJournal(state: state, files: workflowExecutionFiles, store: store)
                workflowJournals[state.run.id] = journal
                defer { releaseWorkflowExecution(state.run.id) }
                _ = try await finishWaitingWorkflowAgent(journal: journal, response: response)
                notifyWorkflowParents(runID)
            }
        } catch {
            logger.error("workflow.agent_reconciliation_failed", metadata: ["error": .string(String(describing: error))])
        }
    }

    func finishWaitingWorkflowAgent(journal: WorkflowExecutionJournal, response: AgentSessionMessageResponse? = nil) async throws -> WorkflowRunDetail {
        let state = await journal.snapshot()
        registerWorkflowChildWaits(state)
        if state.run.status == .waitingForWorkflow {
            if workflowWaitingChildSteps(state).contains(where: workflowChildReady) { workflowReconciliationPending.insert(state.run.id) }
            return await workflowRunDetail(run: state.run)
        }
        if state.parallel != nil { return try await finishParallelInputs(journal: journal) }
        guard state.run.status == .waitingForAgent,
              let step = state.steps.last(where: { $0.nodeId == state.run.currentNodeIds.first }),
              let agentID = step.output["agentId"]?.asString, let sessionID = step.output["sessionId"]?.asString
        else { return await workflowRunDetail(run: state.run) }
        let key = sessionChannelID(agentID: agentID, sessionID: sessionID)
        workflowWaitingSessions[key, default: []].insert(state.run.id)
        let detail = try getAgentSession(agentID: agentID, sessionID: sessionID)
        let resolved = AgentSessionMessageResponse(summary: detail.summary, appendedEvents: detail.events, routeDecision: response?.routeDecision)
        let format = state.definition.nodes.first { $0.id == step.nodeId }?.config["outputFormat"]?.asString ?? "text"
        let result = Self.workflowAgentResult(response: resolved, output: step.output, outputFormat: format)
        let stage = (try? Self.workflowAgentEvents(resolved.appendedEvents, output: step.output))?.compactMap(\.runStatus).last?.stage
        if stage != .done && stage != .interrupted && !WorkflowAgentOutcome.isWaiting(result) && result.error?.code != "workflow_agent_history_missing" {
            return await workflowRunDetail(run: state.run)
        }
        try await journal.recordAgentResult(stepID: step.id, result: result)
        if !WorkflowAgentOutcome.isWaiting(result) { workflowWaitingSessions[key]?.remove(state.run.id) }
        if result.ok {
            let saved = await journal.snapshot()
            return try await continueWorkflow(journal: journal, nodeID: step.nodeId, output: saved.steps.first { $0.id == step.id }?.output ?? [:])
        }
        return await workflowRunDetail(run: journal.snapshot().run)
    }
}
