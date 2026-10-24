import Foundation
import Protocols

struct WorkflowRunner {
    struct Context: Sendable {
        var projectId: String
        var taskId: String?
        var startedBy: String
        var input: [String: JSONValue]
        var runId: String? = nil
        var stepId: String? = nil
        var stepStartedAt: Date? = nil
        var reportProgress: (@Sendable ([String: JSONValue]) async throws -> Void)? = nil
    }

    struct Persistence: Sendable {
        var saveRun: @Sendable (WorkflowRun) async throws -> Void
        var saveStep: @Sendable (WorkflowRunStep) async throws -> Void
        var saveAction: @Sendable (WorkflowPendingAction) async throws -> Void
    }

    typealias ToolExecutor = @Sendable (WorkflowNode, Context, [String: JSONValue]) async -> ToolInvocationResult?

    enum Result: Sendable, Equatable {
        case completed(WorkflowRun)
        case waitingForHuman(WorkflowRun, WorkflowPendingAction)
        case failed(WorkflowRun, String)
    }

    func validate(definition: WorkflowDefinition) -> [WorkflowValidationIssue] {
        var issues: [WorkflowValidationIssue] = []
        let starts = definition.nodes.filter { $0.type == .trigger }
        if starts.count != 1 {
            issues.append(WorkflowValidationIssue(severity: "error", message: "Workflow must have exactly one trigger node."))
        }

        let laneIDs = Set(definition.lanes.map(\.id))
        let nodeIDs = Set(definition.nodes.map(\.id))
        if laneIDs.count != definition.lanes.count {
            issues.append(WorkflowValidationIssue(severity: "error", message: "Workflow contains duplicate lane identifiers."))
        }
        if nodeIDs.count != definition.nodes.count {
            issues.append(WorkflowValidationIssue(severity: "error", message: "Workflow contains duplicate node identifiers."))
        }
        for node in definition.nodes where !laneIDs.contains(node.laneId) {
            issues.append(WorkflowValidationIssue(severity: "error", message: "Workflow node references a missing lane.", nodeId: node.id))
        }
        for edge in definition.edges where !nodeIDs.contains(edge.sourceNodeId) || !nodeIDs.contains(edge.targetNodeId) {
            issues.append(WorkflowValidationIssue(severity: "error", message: "Workflow contains an edge with missing source or target node.", nodeId: edge.sourceNodeId))
        }
        return issues
    }

    func start(
        definition: WorkflowDefinition,
        context: Context,
        persistence: Persistence,
        updateTask: @Sendable (String, String, String) async throws -> Void,
        executeTool: ToolExecutor? = nil
    ) async -> Result {
        var context = context
        context.runId = context.runId ?? "run_\(UUID().uuidString.lowercased())"
        do {
            guard validate(definition: definition).filter({ $0.severity == "error" }).isEmpty else {
                let run = makeRun(definition: definition, context: context, status: .failed, currentNodeIds: [], finishedAt: Date())
                try await persistence.saveRun(run)
                return .failed(run, "Workflow definition is invalid.")
            }
            guard let startNode = definition.nodes.first(where: { $0.type == .trigger }) else {
                let run = makeRun(definition: definition, context: context, status: .failed, currentNodeIds: [], finishedAt: Date())
                try await persistence.saveRun(run)
                return .failed(run, "Workflow has no trigger node.")
            }
            let run = makeRun(definition: definition, context: context, status: .running, currentNodeIds: [startNode.id])
            var runContext = context
            runContext.runId = run.id
            try await persistence.saveRun(run)
            return try await walk(
                definition: definition,
                run: run,
                currentNodeID: startNode.id,
                context: runContext,
                initialOutput: context.input,
                persistence: persistence,
                updateTask: updateTask,
                executeTool: executeTool
            )
        } catch {
            return .failed(makeRun(definition: definition, context: context, status: .failed, currentNodeIds: [], finishedAt: Date()), "Workflow checkpoint failed: \(error)")
        }
    }

    func resume(
        definition: WorkflowDefinition,
        run: WorkflowRun,
        resolvedNodeID: String,
        output: [String: JSONValue],
        persistence: Persistence,
        updateTask: @Sendable (String, String, String) async throws -> Void,
        executeTool: ToolExecutor? = nil,
        originalInput: [String: JSONValue]? = nil,
        previousSteps: [WorkflowRunStep] = [],
        resolvedStepID: String? = nil
    ) async -> Result {
        do {
            let context = Context(projectId: run.projectId, taskId: run.taskId, startedBy: run.startedBy, input: originalInput ?? output, runId: run.id)
            let waitingStep = WorkflowRunStep(
                id: resolvedStepID ?? "step_\(UUID().uuidString.lowercased())",
                runId: run.id,
                nodeId: resolvedNodeID,
                status: .succeeded,
                input: previousSteps.last(where: { $0.id == resolvedStepID })?.input ?? [:],
                output: output,
                startedAt: previousSteps.last(where: { $0.id == resolvedStepID })?.startedAt ?? Date(),
                finishedAt: Date()
            )
            try await persistence.saveStep(waitingStep)
            guard let nextNodeID = nextNodeID(after: resolvedNodeID, output: output, definition: definition) else {
                return try await failStep(run: run, nodeID: resolvedNodeID, input: output,
                                      message: "No matching transition after node \(resolvedNodeID).", persistence: persistence)
            }
            var resumed = run
            resumed.status = .running
            resumed.currentNodeIds = [nextNodeID]
            try await persistence.saveRun(resumed)
            return try await walk(
                definition: definition,
                run: resumed,
                currentNodeID: nextNodeID,
                context: context,
                initialOutput: output,
                persistence: persistence,
                updateTask: updateTask,
                executeTool: executeTool,
                previousSteps: previousSteps
            )
        } catch {
            return .failed(run, "Workflow checkpoint failed: \(error)")
        }
    }

    private func walk(
        definition: WorkflowDefinition,
        run: WorkflowRun,
        currentNodeID: String,
        context: Context,
        initialOutput: [String: JSONValue],
        persistence: Persistence,
        updateTask: @Sendable (String, String, String) async throws -> Void,
        executeTool: ToolExecutor?,
        previousSteps: [WorkflowRunStep] = []
    ) async throws -> Result {
        var run = run
        var nodeID: String? = currentNodeID
        var previousOutput = initialOutput
        var nodeOutputs: [String: JSONValue] = [:]
        var visitedCounts: [String: Int] = [:]
        for step in previousSteps {
            visitedCounts[step.nodeId, default: 0] += 1
            if step.status == .succeeded { nodeOutputs[step.nodeId] = .object(["output": .object(step.output)]) }
        }

        while let activeNodeID = nodeID {
            visitedCounts[activeNodeID, default: 0] += 1
            guard visitedCounts[activeNodeID, default: 0] <= 25 else {
                return try await fail(run: run, message: "Workflow exceeded the maximum step attempt limit.", persistence: persistence)
            }
            guard let node = definition.nodes.first(where: { $0.id == activeNodeID }) else {
                return try await fail(run: run, message: "Workflow node was not found.", persistence: persistence)
            }

            run.status = .running
            run.currentNodeIds = [node.id]
            try await persistence.saveRun(run)
            let scopedInput = workflowScopedInput(current: previousOutput, contextInput: context.input, nodeOutputs: nodeOutputs)

            let stepID = "step_\(UUID().uuidString.lowercased())"
            let startedAt = Date()
            switch node.type {
            case .humanApproval, .humanInput:
                let action = makePendingAction(node: node, run: run, context: context)
                let step = WorkflowRunStep(
                    id: stepID,
                    runId: run.id,
                    nodeId: node.id,
                    status: .waiting,
                    input: scopedInput,
                    output: ["status": .string("waiting")],
                    startedAt: startedAt
                )
                try await persistence.saveStep(step)
                run.status = .waitingForHuman
                run.currentNodeIds = [node.id]
                try await persistence.saveRun(run)
                try await persistence.saveAction(action)
                return .waitingForHuman(run, action)

            case .end:
                guard let terminalStatus = endStatus(from: node) else {
                    return try await failStep(run: run, nodeID: node.id, input: scopedInput,
                                          message: "End node has an invalid terminal status.", persistence: persistence)
                }
                let output = node.config
                let step = WorkflowRunStep(
                    id: stepID,
                    runId: run.id,
                    nodeId: node.id,
                    status: .succeeded,
                    input: scopedInput,
                    output: output,
                    startedAt: startedAt,
                    finishedAt: Date()
                )
                try await persistence.saveStep(step)
                run.status = terminalStatus
                run.currentNodeIds = []
                run.finishedAt = Date()
                try await persistence.saveRun(run)
                return run.status == .completed ? .completed(run) : .failed(run, "Workflow ended with \(run.status.rawValue).")

            case .updateTask:
                do {
                    guard let taskId = context.taskId, let status = stringValue(node.config["status"]) else {
                        return try await failStep(run: run, nodeID: node.id, input: scopedInput,
                                              message: "Update Task requires taskId and status.", persistence: persistence)
                    }
                    try await updateTask(context.projectId, taskId, status)
                } catch {
                    return try await failStep(run: run, nodeID: node.id, input: scopedInput,
                                          message: "Failed to update project task.", persistence: persistence)
                }
                previousOutput = node.config.merging(["status": .string("succeeded")]) { current, _ in current }

            case .condition:
                let blockKind = stringValue(node.config["blockKind"]) ?? stringValue(node.config["block_kind"])
                if stringValue(node.config["expression"]) != nil || blockKind == "expression" || blockKind == "merge" || blockKind == "loop" {
                    return try await failStep(run: run, nodeID: node.id, input: scopedInput,
                                          message: "Expression, Loop and Merge execution is not implemented.", persistence: persistence)
                }
                previousOutput = previousOutput.merging(node.config) { _, new in new }

            case .agentStep, .toolCheck:
                try await persistence.saveStep(WorkflowRunStep(
                    id: stepID, runId: run.id, nodeId: node.id, status: .running,
                    input: scopedInput, startedAt: startedAt
                ))
                var stepContext = context
                stepContext.stepId = stepID
                stepContext.stepStartedAt = startedAt
                let progressStep = WorkflowRunStep(id: stepID, runId: run.id, nodeId: node.id, status: .running, input: scopedInput, startedAt: startedAt)
                stepContext.reportProgress = { output in
                    var step = progressStep
                    step.output = output
                    try await persistence.saveStep(step)
                }
                let toolResult = await executeTool?(node, stepContext, scopedInput) ?? ToolInvocationResult(
                    tool: "project.workflow", ok: false,
                    error: ToolErrorPayload(code: "workflow_executor_unavailable",
                                            message: "No executor for workflow node \(node.id).", retryable: false)
                )
                guard toolResult.ok else {
                    var failedOutput = toolResult.dataObject
                    failedOutput["errorCode"] = toolResult.error.map { .string($0.code) } ?? .string("workflow_execution_incomplete")
                    let message = toolResult.error?.message ?? "Workflow node did not complete successfully."
                    try await persistence.saveStep(WorkflowRunStep(
                        id: stepID, runId: run.id, nodeId: node.id, status: .failed,
                        input: scopedInput, output: failedOutput, error: message,
                        startedAt: startedAt, finishedAt: Date()
                    ))
                    return try await fail(run: run, message: message, persistence: persistence)
                }
                previousOutput = toolResult.dataObject.merging([
                    "status": .string("succeeded"), "tool": .string(toolResult.tool)
                ]) { current, _ in current }

            case .projectTask, .notify:
                return try await failStep(run: run, nodeID: node.id, input: scopedInput,
                                      message: "Workflow node type \(node.type.rawValue) is not implemented.", persistence: persistence)

            case .trigger:
                previousOutput = node.config.merging(["status": .string("succeeded")]) { current, _ in current }
            }

            guard let next = nextNodeID(after: node.id, output: previousOutput, definition: definition) else {
                return try await failStep(run: run, nodeID: node.id, input: scopedInput,
                                      message: "No matching transition after node \(node.id).", persistence: persistence,
                                      stepID: stepID, startedAt: startedAt, output: previousOutput)
            }

            let step = WorkflowRunStep(
                id: stepID,
                runId: run.id,
                nodeId: node.id,
                status: .succeeded,
                input: scopedInput,
                output: previousOutput,
                startedAt: startedAt,
                finishedAt: Date()
            )
            try await persistence.saveStep(step)
            nodeOutputs[node.id] = .object(["output": .object(previousOutput)])
            nodeID = next
        }

        return try await fail(run: run, message: "Workflow stopped before an End node.", persistence: persistence)
    }

    private func makeRun(
        definition: WorkflowDefinition,
        context: Context,
        status: WorkflowRunStatus,
        currentNodeIds: [String],
        finishedAt: Date? = nil
    ) -> WorkflowRun {
        WorkflowRun(
            id: context.runId ?? "run_\(UUID().uuidString.lowercased())",
            workflowId: definition.id,
            workflowVersion: definition.version,
            projectId: context.projectId,
            taskId: context.taskId,
            status: status,
            currentNodeIds: currentNodeIds,
            startedBy: context.startedBy,
            startedAt: Date(),
            finishedAt: finishedAt
        )
    }

    private func makePendingAction(node: WorkflowNode, run: WorkflowRun, context: Context) -> WorkflowPendingAction {
        WorkflowPendingAction(
            id: "action_\(UUID().uuidString.lowercased())",
            projectId: context.projectId,
            workflowRunId: run.id,
            nodeId: node.id,
            taskId: context.taskId,
            assignee: stringValue(node.config["assignee"]) ?? context.startedBy,
            prompt: stringValue(node.config["prompt"]) ?? node.title,
            decisions: [.approved, .rejected, .changesRequested],
            createdAt: Date()
        )
    }

    private func failStep(
        run: WorkflowRun, nodeID: String, input: [String: JSONValue],
        message: String, persistence: Persistence, stepID: String? = nil,
        startedAt: Date = Date(), output: [String: JSONValue] = [:]
    ) async throws -> Result {
        try await persistence.saveStep(WorkflowRunStep(
            id: stepID ?? "step_\(UUID().uuidString.lowercased())", runId: run.id, nodeId: nodeID,
            status: .failed, input: input, output: output, error: message, startedAt: startedAt, finishedAt: Date()
        ))
        return try await fail(run: run, message: message, persistence: persistence)
    }

    private func fail(run: WorkflowRun, message: String, persistence: Persistence) async throws -> Result {
        var failed = run
        failed.status = .failed
        failed.currentNodeIds = []
        failed.finishedAt = Date()
        try await persistence.saveRun(failed)
        return .failed(failed, message)
    }

    private func workflowScopedInput(
        current: [String: JSONValue],
        contextInput: [String: JSONValue],
        nodeOutputs: [String: JSONValue]
    ) -> [String: JSONValue] {
        current.merging([
            "input": .object(contextInput),
            "nodes": .object(nodeOutputs)
        ]) { _, reserved in reserved }
    }

    private func nextNodeID(after nodeID: String, output: [String: JSONValue], definition: WorkflowDefinition) -> String? {
        let edges = definition.edges.filter { $0.sourceNodeId == nodeID }
        if let matched = edges.first(where: { edgeMatches($0.conditionKey, output: output) }) {
            return matched.targetNodeId
        }
        return edges.first(where: { $0.conditionKey == nil })?.targetNodeId
    }

    private func edgeMatches(_ conditionKey: String?, output: [String: JSONValue]) -> Bool {
        guard let conditionKey, !conditionKey.isEmpty else {
            return false
        }
        if case .bool(true)? = output[conditionKey] {
            return true
        }
        for key in ["conditionKey", "decision", "status", "result"] {
            if stringValue(output[key]) == conditionKey {
                return true
            }
        }
        return false
    }

    private func endStatus(from node: WorkflowNode) -> WorkflowRunStatus? {
        guard node.config["status"] != nil else {
            return .completed
        }
        guard let raw = stringValue(node.config["status"]), let status = WorkflowRunStatus(rawValue: raw),
              [.completed, .failed, .blocked, .cancelled].contains(status) else { return nil }
        return status
    }

    private func stringValue(_ value: JSONValue?) -> String? {
        guard case .string(let raw)? = value else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension ToolInvocationResult {
    var dataObject: [String: JSONValue] {
        if let object = data?.asObject {
            return object
        }
        if let data {
            return ["data": data]
        }
        return [:]
    }
}
