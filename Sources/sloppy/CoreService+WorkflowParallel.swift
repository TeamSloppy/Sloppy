import Foundation
import Protocols

extension CoreService {
    func executeWorkflowParallel(node: WorkflowNode, context: WorkflowRunner.Context, input: [String: JSONValue]) async -> ToolInvocationResult {
        func failure(_ message: String, code: String = "workflow_parallel_failed", data: [String: JSONValue] = [:]) -> ToolInvocationResult {
            .init(tool: "workflow.parallel", ok: false, data: .object(data), error: .init(code: code, message: message, retryable: false))
        }
        guard let runID = context.runId, let stepID = context.stepId, let journal = workflowJournals[runID] else {
            return failure("Parallel execution requires a durable run journal.")
        }
        do {
            var state = await journal.snapshot()
            let topology = try WorkflowParallelTopology(definition: state.definition, fork: node)
            if state.parallel == nil {
                let branches = topology.branches.keys.sorted().map { id in
                    WorkflowParallelBranch(id: id, run: WorkflowRun(id: "branch_\(UUID().uuidString.lowercased())",
                        workflowId: state.run.workflowId, workflowVersion: state.run.workflowVersion, projectId: state.run.projectId,
                        taskId: state.run.taskId, status: .queued, currentNodeIds: [id], startedBy: state.run.startedBy))
                }
                let visits = state.steps.reduce(into: [String: Int]()) { $0[$1.nodeId, default: 0] += 1 }
                try await journal.beginParallel(.init(nodeID: node.id, stepID: stepID, branches: branches, visitCounts: visits))
                state = await journal.snapshot()
            }
            guard let parallel = state.parallel, parallel.nodeID == node.id, parallel.stepID == stepID else {
                return failure("Parallel checkpoint does not match the active step.")
            }
            let checkpoint = state
            let failed = await withTaskGroup(of: (String, Bool).self, returning: Bool.self) { group in
                for branch in parallel.branches where parallel.winner == nil || parallel.winner == branch.id {
                    group.addTask { [weak self] in
                        guard let self else { return (branch.id, true) }
                        return (branch.id, await self.executeWorkflowBranch(branch, state: checkpoint, topology: topology, journal: journal, input: input))
                    }
                }
                var failed = false
                var winner = parallel.winner
                for await (id, result) in group {
                    let won = !result && !failed && topology.strategy == "first_completed" && winner == nil
                    if won { try? await journal.selectParallelWinner(id); winner = id }
                    if (result && winner == nil) || won {
                        group.cancelAll()
                        if (!failed || won), await !journal.suspended {
                            let current = await journal.snapshot()
                            let agents = current.parallel?.branches.filter { $0.run.status != .completed }.compactMap { branch in
                                branch.steps.last { $0.output["sessionId"]?.asString != nil }
                            } ?? []
                            await cancelParallelAgentWaits(agents)
                            await cancelParallelChildWaits(current, except: winner)
                        }
                        if result { failed = true }
                    }
                }
                return failed
            }
            state = await journal.snapshot()
            if await !journal.suspended, failed || state.parallel?.winner != nil {
                await cancelParallelChildWaits(state, except: state.parallel?.winner)
            }
            guard let branches = state.parallel?.branches else { return failure("Parallel checkpoint is unavailable.") }
            let winner = state.parallel?.winner
            if failed || (winner == nil && branches.contains(where: { $0.run.status != .completed })) {
                if await !journal.suspended {
                    try await journal.cancelParallelWaits()
                    registerWorkflowWaits(await journal.snapshot())
                }
                let blocked = branches.contains { $0.run.status == .blocked }
                let stopped = branches.filter { $0.run.status != .completed }
                let cancelled = Task.isCancelled || stopped.allSatisfy { ["workflow_cancelled", "workflow_agent_cancelled"].contains($0.failureCode ?? "") }
                let failures = Dictionary(uniqueKeysWithValues: branches.map {
                    ($0.id, JSONValue.object(["status": .string($0.run.status.rawValue),
                        "error": ($0.failure ?? $0.steps.last?.error).map(JSONValue.string) ?? .null,
                        "output": .object($0.steps.last?.output ?? [:])]))
                })
                return failure(blocked ? "A parallel operation needs reconciliation before it can be retried." : "A parallel branch failed or could not complete.",
                    code: blocked ? "workflow_reconciliation_required" : cancelled ? "workflow_parallel_cancelled" : "workflow_parallel_failed", data: ["branches": .object(failures)])
            }
            if winner != nil { try await journal.cancelParallelWaits() }
            registerWorkflowWaits(await journal.snapshot())
            registerWorkflowChildWaits(await journal.snapshot())
            let joined = branches.filter { winner == nil || $0.id == winner }
            let results = Dictionary(uniqueKeysWithValues: joined.map { branch in
                (branch.id, JSONValue.object(branch.steps.last(where: { $0.status == .succeeded })?.output ?? [:]))
            })
            let outputs = joined.flatMap(\.steps).filter { $0.status == .succeeded }.reduce(into: [String: JSONValue]()) {
                $0[$1.nodeId] = .object(["output": .object($1.output)])
            }
            return .init(tool: "workflow.parallel", ok: true, data: .object(["branches": .object(results), "branchNodeOutputs": .object(outputs)]))
        } catch { return failure("Parallel checkpoint failed: \(error)") }
    }

    private func executeWorkflowBranch(_ branch: WorkflowParallelBranch, state: WorkflowExecutionState, topology: WorkflowParallelTopology,
                                       journal: WorkflowExecutionJournal, input: [String: JSONValue]) async -> Bool {
        while true {
            let revision = await journal.parallelInputVersion()
            let latest = await journal.snapshot()
            guard let branch = latest.parallel?.branches.first(where: { $0.id == branch.id }) else { return true }
            let suspended = await journal.suspended
            if Task.isCancelled || suspended {
                if await !journal.suspended { try? await journal.recordBranchFailure(branch.id, message: "Parallel execution cancelled.", code: "workflow_cancelled") }
                return true
            }
            if branch.run.status == .completed { return false }
            if [.failed, .blocked, .cancelled].contains(branch.run.status) { return true }
            if branch.run.status == .waitingForHuman && branch.actions.contains(where: { $0.resolvedAt == nil }) {
                await journal.waitForParallelInput(after: revision)
                continue
            }
            let child = WorkflowExecutionState(resumeAfterShutdown: state.resumeAfterShutdown, definition: state.definition,
                originalInput: state.originalInput, run: branch.run, steps: branch.steps, actions: branch.actions, retryStepId: branch.retryStepId)
            var context = WorkflowRunner.Context(projectId: state.run.projectId, taskId: state.run.taskId, startedBy: state.run.startedBy,
                input: state.originalInput, runId: branch.run.id)
            context.startNodeId = branch.id
            context.stopNodeId = topology.joinID
            context.initialNodeOutputs = input["nodes"]?.asObject ?? [:]
            context.initialOutput = input.filter { $0.key != "nodes" && $0.key != "input" }
            context.initialVisitCounts = state.parallel?.visitCounts ?? [:]
            let result = await WorkflowRunner().restore(state: child, persistence: await journal.branchPersistence(branch.id),
                updateTask: workflowTaskUpdater(), executeTool: { [weak self] node, context, input in
                    await self?.executeWorkflowToolNode(node: node, context: context, input: input)
                }, branchContext: context)
            switch result {
            case .completed: return false
            case .failed(_, let message):
                let failed = await journal.snapshot().parallel?.branches.first { $0.id == branch.id }
                let code = Task.isCancelled ? "workflow_cancelled" : failed?.steps.last?.output["errorCode"]?.asString ?? "workflow_branch_failed"
                if await !journal.suspended { try? await journal.recordBranchFailure(branch.id, message: message, code: code) }
                return true
            case .waitingForHuman, .waitingForAgent, .waitingForWorkflow:
                let waiting = await journal.snapshot()
                registerWorkflowWaits(waiting)
                registerWorkflowChildWaits(waiting)
                if workflowWaitingChildSteps(waiting).contains(where: { $0.runId == branch.run.id && workflowChildReady($0) }) { continue }
                if workflowWaitingAgentSteps(waiting).contains(where: { $0.runId == branch.run.id && workflowAgentInputReady($0) }) { continue }
                await journal.waitForParallelInput(after: revision)
            }
        }
    }
}
