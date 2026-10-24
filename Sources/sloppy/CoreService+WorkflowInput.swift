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
                    workflowReconciliationPending.insert(runID)
                    continue
                }
                guard state.run.status == .waitingForAgent,
                      let step = state.steps.last(where: { $0.nodeId == state.run.currentNodeIds.first }),
                      step.output["agentId"]?.asString == agentID, step.output["sessionId"]?.asString == sessionID else { continue }
                activeWorkflowRuns.insert(state.run.id)
                let journal = WorkflowExecutionJournal(state: state, files: workflowExecutionFiles, store: store)
                workflowJournals[state.run.id] = journal
                defer { releaseWorkflowExecution(state.run.id) }
                _ = try await finishWaitingWorkflowAgent(journal: journal, response: response)
            }
        } catch {
            logger.error("workflow.agent_reconciliation_failed", metadata: ["error": .string(String(describing: error))])
        }
    }

    func finishWaitingWorkflowAgent(journal: WorkflowExecutionJournal, response: AgentSessionMessageResponse? = nil) async throws -> WorkflowRunDetail {
        let state = await journal.snapshot()
        guard state.run.status == .waitingForAgent,
              let step = state.steps.last(where: { $0.nodeId == state.run.currentNodeIds.first }),
              let agentID = step.output["agentId"]?.asString, let sessionID = step.output["sessionId"]?.asString
        else { return await workflowRunDetail(run: state.run) }
        let key = sessionChannelID(agentID: agentID, sessionID: sessionID)
        workflowWaitingSessions[key, default: []].insert(state.run.id)
        let resolved: AgentSessionMessageResponse
        if let response { resolved = response }
        else {
            let detail = try getAgentSession(agentID: agentID, sessionID: sessionID)
            resolved = .init(summary: detail.summary, appendedEvents: detail.events, routeDecision: nil)
        }
        let result = Self.workflowAgentResult(response: resolved, output: step.output)
        let stage = resolved.appendedEvents.filter { $0.importOrigin == nil }.compactMap(\.runStatus).last?.stage
        if stage != .done && stage != .interrupted && !WorkflowAgentOutcome.isWaiting(result) {
            return await workflowRunDetail(run: state.run)
        }
        try await journal.recordAgentResult(stepID: step.id, result: result)
        if !WorkflowAgentOutcome.isWaiting(result) { workflowWaitingSessions[key]?.remove(state.run.id) }
        if result.ok { return try await continueWorkflow(journal: journal, nodeID: step.nodeId, output: result.data?.asObject ?? [:]) }
        return await workflowRunDetail(run: journal.snapshot().run)
    }
}
