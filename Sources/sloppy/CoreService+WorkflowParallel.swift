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
            let failed = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
                for branch in parallel.branches {
                    group.addTask { [weak self] in
                        guard let self else { return true }
                        return await self.executeWorkflowBranch(branch, state: checkpoint, topology: topology, journal: journal, input: input)
                    }
                }
                var failed = false
                for await result in group {
                    if result { failed = true; group.cancelAll() }
                }
                return failed
            }
            state = await journal.snapshot()
            guard let branches = state.parallel?.branches else { return failure("Parallel checkpoint is unavailable.") }
            if failed || branches.contains(where: { $0.run.status != .completed }) {
                let blocked = branches.contains { $0.run.status == .blocked }
                let failures = Dictionary(uniqueKeysWithValues: branches.map {
                    ($0.id, JSONValue.object(["status": .string($0.run.status.rawValue),
                        "error": $0.steps.last?.error.map(JSONValue.string) ?? .null,
                        "output": .object($0.steps.last?.output ?? [:])]))
                })
                return failure(blocked ? "A parallel operation needs reconciliation before it can be retried." : "A parallel branch failed or could not complete.",
                    code: blocked ? "workflow_reconciliation_required" : "workflow_parallel_failed", data: ["branches": .object(failures)])
            }
            let results = Dictionary(uniqueKeysWithValues: branches.map { branch in
                (branch.id, JSONValue.object(branch.steps.last(where: { $0.status == .succeeded })?.output ?? [:]))
            })
            let outputs = branches.flatMap(\.steps).filter { $0.status == .succeeded }.reduce(into: [String: JSONValue]()) {
                $0[$1.nodeId] = .object(["output": .object($1.output)])
            }
            return .init(tool: "workflow.parallel", ok: true, data: .object(["branches": .object(results), "branchNodeOutputs": .object(outputs)]))
        } catch { return failure("Parallel checkpoint failed: \(error)") }
    }

    private func executeWorkflowBranch(_ branch: WorkflowParallelBranch, state: WorkflowExecutionState, topology: WorkflowParallelTopology,
                                       journal: WorkflowExecutionJournal, input: [String: JSONValue]) async -> Bool {
        if branch.run.status == .completed { return false }
        if [.failed, .blocked, .cancelled].contains(branch.run.status) { return true }
        let child = WorkflowExecutionState(resumeAfterShutdown: state.resumeAfterShutdown, definition: state.definition,
            originalInput: state.originalInput, run: branch.run, steps: branch.steps, actions: branch.actions)
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
        if case .completed = result { return false }
        return true
    }
}
