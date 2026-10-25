import Foundation
import Protocols

extension CoreService {
    func executeWorkflowChild(node: WorkflowNode, context: WorkflowRunner.Context, input: [String: JSONValue]) async -> ToolInvocationResult {
        func failure(_ message: String, code: String = "workflow_child_failed", data: [String: JSONValue] = [:]) -> ToolInvocationResult {
            .init(tool: "workflow.child", ok: false, data: .object(data), error: .init(code: code, message: message, retryable: false))
        }
        var bindingOutput: [String: JSONValue] = [:]
        do {
            guard let target = node.config["workflowId"]?.asString, let step = context.stepId else { return failure("Sub-workflow requires a workflowId and durable attempt.") }
            let saved = context.resumingStep?.output ?? context.retryOutput ?? [:]
            let key = saved["childRunId"]?.asString.map { $0.replacingOccurrences(of: "run_", with: "") }
                ?? step.replacingOccurrences(of: "step_", with: "")
            guard UUID(uuidString: key) != nil else { return failure("Invalid durable child binding.") }
            if saved["childStatus"] != nil, try workflowExecutionFiles.load("run_\(key.lowercased())") == nil {
                return failure("The acknowledged child checkpoint is missing; reconcile its effects before retrying.", code: "workflow_reconciliation_required")
            }
            let ancestors = context.input["__workflowAncestors"]?.asArray?.compactMap(\.asString) ?? []
            guard !ancestors.contains(target), ancestors.count < 8 else { return failure("Recursive workflow calls are not allowed.") }
            var output: [String: JSONValue] = ["childRunId": .string("run_\(key.lowercased())"), "childWorkflowId": .string(target)]
            bindingOutput = output
            try await context.reportProgress?(output)
            let environment = try context.input["environment"].map { try JSONDecoder().decode(WorkflowEnvironmentBinding.self, from: JSONEncoder().encode($0)) }
            var childInput = context.input
            if let configured = node.config["input"], configured != .null {
                guard let object = resolveWorkflowTemplateValue(configured, input: input).asObject else { throw WorkflowGraphContracts.Violation("Child workflow input must be a JSON object.") }
                childInput = object
            }
            childInput.removeValue(forKey: "__workflowAncestors")
            childInput.removeValue(forKey: "environment"); childInput.removeValue(forKey: "cwd"); childInput.removeValue(forKey: "task")
            try Task.checkCancellation()
            let detail = try await startBoundWorkflowRun(projectID: context.projectId, workflowID: target,
                request: .init(taskId: context.taskId, startedBy: context.startedBy, input: childInput, background: true, idempotencyKey: key),
                inheritedEnvironment: environment, ancestors: ancestors, taskSnapshot: context.input["task"])
            output["childStatus"] = .string(detail.run.status.rawValue)
            output["childWorkflowVersion"] = .number(Double(detail.run.workflowVersion))
            switch detail.run.status {
            case .completed:
                output["nodes"] = .object(detail.steps.filter { $0.status == .succeeded }.reduce(into: [:]) { $0[$1.nodeId] = .object($1.output) })
                return .init(tool: "workflow.child", ok: true, data: .object(output))
            case .failed: return failure("Child workflow failed.", data: output)
            case .blocked: return failure("Child workflow requires reconciliation.", code: "workflow_reconciliation_required", data: output)
            case .cancelled: return failure("Child workflow was cancelled.", code: "workflow_child_cancelled", data: output)
            default: return failure("Waiting for child workflow completion.", code: "workflow_child_waiting", data: output)
            }
        } catch { return failure(String(describing: error), data: bindingOutput) }
    }

    func workflowWaitingChildSteps(_ state: WorkflowExecutionState) -> [WorkflowRunStep] {
        guard ![WorkflowRunStatus.completed, .failed, .blocked, .cancelled].contains(state.run.status) else { return [] }
        if let parallel = state.parallel {
            return parallel.branches.filter { $0.run.status == .waitingForWorkflow }.compactMap { branch in branch.steps.last { $0.nodeId == branch.run.currentNodeIds.first } }
        }
        return state.run.status == .waitingForWorkflow ? Array(state.steps.suffix(1)) : []
    }

    func workflowChildLostRace(_ child: String) -> Bool {
        let explicitResume = (try? workflowExecutionFiles.load(child))?.reconciliations?.last?.createdAt ?? .distantPast
        for parent in workflowWaitingChildren[child] ?? [] {
            guard let state = try? workflowExecutionFiles.load(parent) else { continue }
            if state.run.status == .cancelled, explicitResume <= (state.run.finishedAt ?? .distantFuture) { return true }
            guard let parallel = state.parallel, let winner = parallel.winner,
                  explicitResume <= (parallel.branches.first(where: { $0.id == winner })?.run.finishedAt ?? .distantFuture) else { continue }
            if parallel.branches.contains(where: { $0.id != winner && $0.steps.contains { $0.output["childRunId"]?.asString == child } }) { return true }
        }
        return false
    }

    func workflowChildReady(_ step: WorkflowRunStep) -> Bool {
        guard let id = step.output["childRunId"]?.asString else { return true }
        guard let state = try? workflowExecutionFiles.load(id) else { return true }
        return [WorkflowRunStatus.completed, .failed, .blocked, .cancelled].contains(state.run.status)
    }

    func registerWorkflowChildWaits(_ state: WorkflowExecutionState) {
        for key in Array(workflowWaitingChildren.keys) {
            workflowWaitingChildren[key]?.remove(state.run.id)
            if workflowWaitingChildren[key]?.isEmpty == true { workflowWaitingChildren[key] = nil }
        }
        var steps = workflowWaitingChildSteps(state)
        if state.run.status == .cancelled { steps += state.steps }
        if let parallel = state.parallel, let winner = parallel.winner {
            steps += parallel.branches.filter { $0.id != winner }.flatMap(\.steps)
        }
        for step in steps where state.definition.nodes.contains(where: { $0.id == step.nodeId && WorkflowGraphContracts.blockKind($0) == "sub_workflow" }) {
            if let child = step.output["childRunId"]?.asString { workflowWaitingChildren[child, default: []].insert(state.run.id) }
        }
    }

    func notifyWorkflowParents(_ child: String) {
        guard let state = try? workflowExecutionFiles.load(child), [.completed, .failed, .blocked, .cancelled].contains(state.run.status) else { return }
        for parent in workflowWaitingChildren[child] ?? [] {
            if let journal = workflowJournals[parent], activeWorkflowRuns.contains(parent) {
                Task { await journal.signalParallelInput() }
                workflowReconciliationPending.insert(parent)
            } else { scheduleWorkflowRecovery(parent) }
        }
    }
}
