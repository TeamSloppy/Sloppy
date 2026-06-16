import Foundation
import Protocols

struct WorkflowRunner {
    struct Context: Sendable {
        var projectId: String
        var taskId: String?
        var startedBy: String
        var input: [String: JSONValue]
    }

    struct Persistence: Sendable {
        var saveRun: @Sendable (WorkflowRun) async -> Void
        var saveStep: @Sendable (WorkflowRunStep) async -> Void
        var saveAction: @Sendable (WorkflowPendingAction) async -> Void
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
        guard validate(definition: definition).filter({ $0.severity == "error" }).isEmpty else {
            let run = makeRun(definition: definition, context: context, status: .failed, currentNodeIds: [], finishedAt: Date())
            await persistence.saveRun(run)
            return .failed(run, "Workflow definition is invalid.")
        }
        guard let startNode = definition.nodes.first(where: { $0.type == .trigger }) else {
            let run = makeRun(definition: definition, context: context, status: .failed, currentNodeIds: [], finishedAt: Date())
            await persistence.saveRun(run)
            return .failed(run, "Workflow has no trigger node.")
        }
        let run = makeRun(definition: definition, context: context, status: .running, currentNodeIds: [startNode.id])
        await persistence.saveRun(run)
        return await walk(
            definition: definition,
            run: run,
            currentNodeID: startNode.id,
            context: context,
            initialOutput: context.input,
            persistence: persistence,
            updateTask: updateTask,
            executeTool: executeTool
        )
    }

    func resume(
        definition: WorkflowDefinition,
        run: WorkflowRun,
        resolvedNodeID: String,
        output: [String: JSONValue],
        persistence: Persistence,
        updateTask: @Sendable (String, String, String) async throws -> Void,
        executeTool: ToolExecutor? = nil
    ) async -> Result {
        let context = Context(projectId: run.projectId, taskId: run.taskId, startedBy: run.startedBy, input: output)
        let waitingStep = WorkflowRunStep(
            id: "step_\(UUID().uuidString.lowercased())",
            runId: run.id,
            nodeId: resolvedNodeID,
            status: .succeeded,
            output: output,
            startedAt: Date(),
            finishedAt: Date()
        )
        await persistence.saveStep(waitingStep)
        guard let nextNodeID = nextNodeID(after: resolvedNodeID, output: output, definition: definition) else {
            var completed = run
            completed.status = .completed
            completed.currentNodeIds = []
            completed.finishedAt = Date()
            await persistence.saveRun(completed)
            return .completed(completed)
        }
        var resumed = run
        resumed.status = .running
        resumed.currentNodeIds = [nextNodeID]
        await persistence.saveRun(resumed)
        return await walk(
            definition: definition,
            run: resumed,
            currentNodeID: nextNodeID,
            context: context,
            initialOutput: output,
            persistence: persistence,
            updateTask: updateTask,
            executeTool: executeTool
        )
    }

    private func walk(
        definition: WorkflowDefinition,
        run: WorkflowRun,
        currentNodeID: String,
        context: Context,
        initialOutput: [String: JSONValue],
        persistence: Persistence,
        updateTask: @Sendable (String, String, String) async throws -> Void,
        executeTool: ToolExecutor?
    ) async -> Result {
        var run = run
        var nodeID: String? = currentNodeID
        var previousOutput = initialOutput
        var visitedCounts: [String: Int] = [:]

        while let activeNodeID = nodeID {
            visitedCounts[activeNodeID, default: 0] += 1
            guard visitedCounts[activeNodeID, default: 0] <= 25 else {
                return await fail(run: run, message: "Workflow exceeded the maximum step attempt limit.", persistence: persistence)
            }
            guard let node = definition.nodes.first(where: { $0.id == activeNodeID }) else {
                return await fail(run: run, message: "Workflow node was not found.", persistence: persistence)
            }

            run.status = .running
            run.currentNodeIds = [node.id]
            await persistence.saveRun(run)

            switch node.type {
            case .humanApproval, .humanInput:
                let action = makePendingAction(node: node, run: run, context: context)
                let step = WorkflowRunStep(
                    id: "step_\(UUID().uuidString.lowercased())",
                    runId: run.id,
                    nodeId: node.id,
                    status: .waiting,
                    input: previousOutput,
                    output: ["status": .string("waiting")],
                    startedAt: Date()
                )
                await persistence.saveStep(step)
                run.status = .waitingForHuman
                run.currentNodeIds = [node.id]
                await persistence.saveRun(run)
                await persistence.saveAction(action)
                return .waitingForHuman(run, action)

            case .end:
                let output = node.config
                let step = WorkflowRunStep(
                    id: "step_\(UUID().uuidString.lowercased())",
                    runId: run.id,
                    nodeId: node.id,
                    status: .succeeded,
                    input: previousOutput,
                    output: output,
                    startedAt: Date(),
                    finishedAt: Date()
                )
                await persistence.saveStep(step)
                run.status = endStatus(from: node)
                run.currentNodeIds = []
                run.finishedAt = Date()
                await persistence.saveRun(run)
                return run.status == .completed ? .completed(run) : .failed(run, "Workflow ended with \(run.status.rawValue).")

            case .updateTask:
                do {
                    if let taskId = context.taskId, let status = stringValue(node.config["status"]) {
                        try await updateTask(context.projectId, taskId, status)
                    }
                } catch {
                    return await fail(run: run, message: "Failed to update project task.", persistence: persistence)
                }
                previousOutput = node.config.merging(["status": .string("succeeded")]) { current, _ in current }

            case .condition:
                previousOutput = context.input.merging(node.config) { _, new in new }

            case .agentStep, .toolCheck:
                if let toolResult = await executeTool?(node, context, previousOutput) {
                    guard toolResult.ok else {
                        let message = toolResult.error?.message ?? "Workflow tool node failed."
                        let failedStep = WorkflowRunStep(
                            id: "step_\(UUID().uuidString.lowercased())",
                            runId: run.id,
                            nodeId: node.id,
                            status: .failed,
                            input: previousOutput,
                            output: toolResult.dataObject,
                            error: message,
                            startedAt: Date(),
                            finishedAt: Date()
                        )
                        await persistence.saveStep(failedStep)
                        return await fail(run: run, message: message, persistence: persistence)
                    }
                    previousOutput = toolResult.dataObject.merging([
                        "status": .string("succeeded"),
                        "tool": .string(toolResult.tool)
                    ]) { current, _ in current }
                } else {
                    previousOutput = node.config.merging(["status": .string("succeeded")]) { current, _ in current }
                }

            case .trigger, .projectTask, .notify:
                previousOutput = node.config.merging(["status": .string("succeeded")]) { current, _ in current }
            }

            let step = WorkflowRunStep(
                id: "step_\(UUID().uuidString.lowercased())",
                runId: run.id,
                nodeId: node.id,
                status: .succeeded,
                input: context.input,
                output: previousOutput,
                startedAt: Date(),
                finishedAt: Date()
            )
            await persistence.saveStep(step)
            nodeID = nextNodeID(after: node.id, output: previousOutput, definition: definition)
        }

        run.status = .completed
        run.currentNodeIds = []
        run.finishedAt = Date()
        await persistence.saveRun(run)
        return .completed(run)
    }

    private func makeRun(
        definition: WorkflowDefinition,
        context: Context,
        status: WorkflowRunStatus,
        currentNodeIds: [String],
        finishedAt: Date? = nil
    ) -> WorkflowRun {
        WorkflowRun(
            id: "run_\(UUID().uuidString.lowercased())",
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

    private func fail(run: WorkflowRun, message: String, persistence: Persistence) async -> Result {
        var failed = run
        failed.status = .failed
        failed.currentNodeIds = []
        failed.finishedAt = Date()
        await persistence.saveRun(failed)
        return .failed(failed, message)
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

    private func endStatus(from node: WorkflowNode) -> WorkflowRunStatus {
        guard let raw = stringValue(node.config["status"]) else {
            return .completed
        }
        return WorkflowRunStatus(rawValue: raw) ?? .completed
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
