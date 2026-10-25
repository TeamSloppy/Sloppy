import Foundation
import Protocols

extension CoreService {
    func workflowWaitingAgentSteps(_ state: WorkflowExecutionState) -> [WorkflowRunStep] {
        guard ![WorkflowRunStatus.completed, .failed, .blocked, .cancelled].contains(state.run.status) else { return [] }
        if let parallel = state.parallel {
            return parallel.branches.filter { $0.run.status == .waitingForAgent }.compactMap { branch in
                branch.steps.last { $0.nodeId == branch.run.currentNodeIds.first }
            }
        }
        guard state.run.status == .waitingForAgent, let step = state.steps.last(where: { $0.nodeId == state.run.currentNodeIds.first }) else { return [] }
        return [step]
    }

    func registerWorkflowWaits(_ state: WorkflowExecutionState) {
        for key in Array(workflowWaitingSessions.keys) {
            workflowWaitingSessions[key]?.remove(state.run.id)
            if workflowWaitingSessions[key]?.isEmpty == true { workflowWaitingSessions[key] = nil }
        }
        for step in workflowWaitingAgentSteps(state) {
            if let agent = step.output["agentId"]?.asString, let session = step.output["sessionId"]?.asString {
                workflowWaitingSessions[sessionChannelID(agentID: agent, sessionID: session), default: []].insert(state.run.id)
            }
        }
    }

    func workflowAgentInputReady(_ step: WorkflowRunStep) -> Bool {
        guard let agent = step.output["agentId"]?.asString, let session = step.output["sessionId"]?.asString else { return true }
        do {
            let events = try Self.workflowAgentEvents(getAgentSession(agentID: agent, sessionID: session).events, output: step.output)
            let index = events.lastIndex { $0.runStatus != nil } ?? -1
            let stage = events.compactMap(\.runStatus).last?.stage
            if stage == .done || stage == .interrupted || events.contains(where: { $0.inputResponse?.status == .cancelled }) { return true }
            let delivering = activeSessionMessageRuns.contains(session)
                || sessionMessageStorage?.entries.contains { $0.sessionId == session && $0.state == .queued } == true
            return !delivering && (events.lastIndex { $0.inputResponse?.status == .answered } ?? -1) > index
        } catch { return true } // Missing history must reach the executor's fail-closed check.
    }

    func finishParallelInputs(journal: WorkflowExecutionJournal) async throws -> WorkflowRunDetail {
        let state = await journal.snapshot()
        registerWorkflowWaits(state)
        await journal.signalParallelInput()
        workflowReconciliationPending.insert(state.run.id)
        if !activeWorkflowRuns.contains(state.run.id) { scheduleWorkflowRecovery(state.run.id) }
        return await workflowRunDetail(run: state.run)
    }

    func cancelParallelAgentWaits(_ steps: [WorkflowRunStep]) async {
        for step in steps {
            guard let agent = step.output["agentId"]?.asString, let session = step.output["sessionId"]?.asString else { continue }
            do {
                let events = try Self.workflowAgentEvents(getAgentSession(agentID: agent, sessionID: session).events, output: step.output)
                let resolved = Set(events.compactMap { $0.inputResponse?.requestId })
                for request in events.compactMap(\.inputRequest) where !resolved.contains(request.id) {
                    _ = try await answerAgentPlanInput(agentID: agent, sessionID: session, requestID: request.id,
                        payload: .init(status: .cancelled, answers: [], userId: "workflow"))
                }
                _ = try await controlAgentSession(agentID: agent, sessionID: session,
                    request: .init(action: .interrupt, requestedBy: "workflow", reason: "Parallel branch stopped."))
            } catch { logger.error("workflow.parallel_cancel_failed", metadata: ["session_id": .string(session), "error": .string(String(describing: error))]) }
        }
    }
}
