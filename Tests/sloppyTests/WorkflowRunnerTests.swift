import Foundation
import Testing
@testable import sloppy
import Protocols

@Test
func workflowRunnerCompletesUpdateTaskFlow() async throws {
    let runner = WorkflowRunner()
    let definition = workflowDefinition(nodes: [
        WorkflowNode(id: "start", type: .trigger, title: "Start", laneId: "system"),
        WorkflowNode(id: "task", type: .updateTask, title: "Update", laneId: "system", config: ["status": .string("needs_review")]),
        WorkflowNode(id: "done", type: .end, title: "Done", laneId: "system", config: ["status": .string("completed")])
    ], edges: [
        WorkflowEdge(id: "e1", sourceNodeId: "start", targetNodeId: "task"),
        WorkflowEdge(id: "e2", sourceNodeId: "task", targetNodeId: "done")
    ])
    let recorder = WorkflowRecorder()

    let result = await runner.start(
        definition: definition,
        context: .init(projectId: "project-1", taskId: "task-1", startedBy: "human:admin", input: [:]),
        persistence: recorder.persistence,
        updateTask: recorder.updateTask
    )

    guard case .completed(let run) = result else {
        Issue.record("Expected completed workflow run.")
        return
    }
    #expect(run.status == .completed)
    #expect(await recorder.taskUpdates == ["project-1:task-1:needs_review"])
}

@Test
func workflowRunnerPausesForHumanApproval() async throws {
    let runner = WorkflowRunner()
    let definition = workflowDefinition(nodes: [
        WorkflowNode(id: "start", type: .trigger, title: "Start", laneId: "system"),
        WorkflowNode(id: "approval", type: .humanApproval, title: "Approve", laneId: "owner", config: ["prompt": .string("Approve?")]),
        WorkflowNode(id: "done", type: .end, title: "Done", laneId: "system")
    ], edges: [
        WorkflowEdge(id: "e1", sourceNodeId: "start", targetNodeId: "approval"),
        WorkflowEdge(id: "e2", sourceNodeId: "approval", targetNodeId: "done", conditionKey: "approved")
    ])
    let recorder = WorkflowRecorder()

    let result = await runner.start(
        definition: definition,
        context: .init(projectId: "project-1", taskId: "task-1", startedBy: "human:admin", input: [:]),
        persistence: recorder.persistence,
        updateTask: recorder.updateTask
    )

    guard case .waitingForHuman(let run, let action) = result else {
        Issue.record("Expected waiting workflow run.")
        return
    }
    #expect(run.status == .waitingForHuman)
    #expect(action.nodeId == "approval")
    #expect(action.prompt == "Approve?")
    #expect(await recorder.actions.count == 1)
}

@Test
func workflowRunnerResumesApprovedActionAndCompletes() async throws {
    let runner = WorkflowRunner()
    let definition = workflowDefinition(nodes: [
        WorkflowNode(id: "start", type: .trigger, title: "Start", laneId: "system"),
        WorkflowNode(id: "approval", type: .humanApproval, title: "Approve", laneId: "owner"),
        WorkflowNode(id: "done", type: .end, title: "Done", laneId: "system")
    ], edges: [
        WorkflowEdge(id: "e1", sourceNodeId: "start", targetNodeId: "approval"),
        WorkflowEdge(id: "e2", sourceNodeId: "approval", targetNodeId: "done", conditionKey: "approved")
    ])
    let recorder = WorkflowRecorder()
    let waiting = WorkflowRun(
        id: "run-1",
        workflowId: definition.id,
        workflowVersion: definition.version,
        projectId: "project-1",
        taskId: "task-1",
        status: .waitingForHuman,
        currentNodeIds: ["approval"],
        startedBy: "human:admin"
    )

    let result = await runner.resume(
        definition: definition,
        run: waiting,
        resolvedNodeID: "approval",
        output: ["decision": .string("approved")],
        persistence: recorder.persistence,
        updateTask: recorder.updateTask
    )

    guard case .completed(let run) = result else {
        Issue.record("Expected resumed workflow to complete.")
        return
    }
    #expect(run.status == .completed)
}

@Test
func workflowRunnerConditionFollowsMatchingConditionKey() async throws {
    let runner = WorkflowRunner()
    let definition = workflowDefinition(nodes: [
        WorkflowNode(id: "start", type: .trigger, title: "Start", laneId: "system"),
        WorkflowNode(id: "condition", type: .condition, title: "Condition", laneId: "system", config: ["status": .string("rejected")]),
        WorkflowNode(id: "rejected", type: .end, title: "Rejected", laneId: "system", config: ["status": .string("blocked")]),
        WorkflowNode(id: "done", type: .end, title: "Done", laneId: "system")
    ], edges: [
        WorkflowEdge(id: "e1", sourceNodeId: "start", targetNodeId: "condition"),
        WorkflowEdge(id: "e2", sourceNodeId: "condition", targetNodeId: "done", conditionKey: "approved"),
        WorkflowEdge(id: "e3", sourceNodeId: "condition", targetNodeId: "rejected", conditionKey: "rejected")
    ])
    let recorder = WorkflowRecorder()

    let result = await runner.start(
        definition: definition,
        context: .init(projectId: "project-1", taskId: nil, startedBy: "human:admin", input: [:]),
        persistence: recorder.persistence,
        updateTask: recorder.updateTask
    )

    guard case .failed(let run, _) = result else {
        Issue.record("Expected rejected branch to end blocked.")
        return
    }
    #expect(run.status == .blocked)
    #expect(await recorder.steps.contains { $0.nodeId == "rejected" })
}

@Test
func workflowRunnerRecordsAgentAndToolStepsAsWorkflowActions() async throws {
    let runner = WorkflowRunner()
    let definition = workflowDefinition(nodes: [
        WorkflowNode(id: "start", type: .trigger, title: "Start", laneId: "system"),
        WorkflowNode(id: "agent", type: .agentStep, title: "Agent", laneId: "system", config: ["blockKind": .string("agent")]),
        WorkflowNode(id: "tool", type: .toolCheck, title: "Tool", laneId: "system", config: ["blockKind": .string("bash")]),
        WorkflowNode(id: "done", type: .end, title: "Done", laneId: "system")
    ], edges: [
        WorkflowEdge(id: "e1", sourceNodeId: "start", targetNodeId: "agent"),
        WorkflowEdge(id: "e2", sourceNodeId: "agent", targetNodeId: "tool"),
        WorkflowEdge(id: "e3", sourceNodeId: "tool", targetNodeId: "done")
    ])
    let recorder = WorkflowRecorder()

    let result = await runner.start(
        definition: definition,
        context: .init(projectId: "project-1", taskId: nil, startedBy: "human:admin", input: [:]),
        persistence: recorder.persistence,
        updateTask: recorder.updateTask
    )

    guard case .completed(let run) = result else {
        Issue.record("Expected completed workflow run.")
        return
    }
    #expect(run.status == .completed)
    #expect(await recorder.steps.contains { $0.nodeId == "agent" && $0.status == .succeeded })
    #expect(await recorder.steps.contains { $0.nodeId == "tool" && $0.status == .succeeded })
}

@Test
func workflowRunnerExecutesToolCheckThroughInjectedExecutor() async throws {
    let runner = WorkflowRunner()
    let definition = workflowDefinition(nodes: [
        WorkflowNode(id: "start", type: .trigger, title: "Start", laneId: "system"),
        WorkflowNode(id: "bash", type: .toolCheck, title: "Bash", laneId: "system", config: ["blockKind": .string("bash")]),
        WorkflowNode(id: "done", type: .end, title: "Done", laneId: "system")
    ], edges: [
        WorkflowEdge(id: "e1", sourceNodeId: "start", targetNodeId: "bash"),
        WorkflowEdge(id: "e2", sourceNodeId: "bash", targetNodeId: "done")
    ])
    let recorder = WorkflowRecorder()

    let result = await runner.start(
        definition: definition,
        context: .init(projectId: "project-1", taskId: nil, startedBy: "agent:test", input: [:]),
        persistence: recorder.persistence,
        updateTask: recorder.updateTask,
        executeTool: { node, _, _ in
            #expect(node.id == "bash")
            return ToolInvocationResult(tool: "runtime.exec", ok: true, data: .object(["stdout": .string("ok")]))
        }
    )

    guard case .completed(let run) = result else {
        Issue.record("Expected completed workflow run.")
        return
    }
    #expect(run.status == .completed)
    #expect(await recorder.steps.contains { $0.nodeId == "bash" && $0.output["stdout"] == .string("ok") })
}

@Test
func workflowRunnerPassesPreviousNodeOutputsToLaterToolInputs() async throws {
    let runner = WorkflowRunner()
    let definition = workflowDefinition(nodes: [
        WorkflowNode(id: "start", type: .trigger, title: "Start", laneId: "system"),
        WorkflowNode(id: "first", type: .toolCheck, title: "First", laneId: "system", config: ["blockKind": .string("tool")]),
        WorkflowNode(id: "second", type: .toolCheck, title: "Second", laneId: "system", config: ["blockKind": .string("tool")]),
        WorkflowNode(id: "done", type: .end, title: "Done", laneId: "system")
    ], edges: [
        WorkflowEdge(id: "e1", sourceNodeId: "start", targetNodeId: "first"),
        WorkflowEdge(id: "e2", sourceNodeId: "first", targetNodeId: "second"),
        WorkflowEdge(id: "e3", sourceNodeId: "second", targetNodeId: "done")
    ])
    let recorder = WorkflowRecorder()

    let result = await runner.start(
        definition: definition,
        context: .init(projectId: "project-1", taskId: nil, startedBy: "agent:test", input: ["message": .string("hello")]),
        persistence: recorder.persistence,
        updateTask: recorder.updateTask,
        executeTool: { node, _, input in
            if node.id == "first" {
                return ToolInvocationResult(tool: "project.first", ok: true, data: .object(["value": .string("from-first")]))
            }
            let nodes = input["nodes"]?.asObject
            let firstOutput = nodes?["first"]?.asObject?["output"]?.asObject
            #expect(firstOutput?["value"] == .string("from-first"))
            #expect(input["input"]?.asObject?["message"] == .string("hello"))
            return ToolInvocationResult(tool: "project.second", ok: true, data: .object(["value": .string("from-second")]))
        }
    )

    guard case .completed(let run) = result else {
        Issue.record("Expected completed workflow run.")
        return
    }
    #expect(run.status == .completed)
}

@Test
func workflowTemplateResolverSubstitutesNodeOutputPaths() throws {
    let input: [String: JSONValue] = [
        "input": .object(["message": .string("hello")]),
        "nodes": .object([
            "web-request": .object([
                "output": .object([
                    "status": .number(200),
                    "body": .string("ok")
                ])
            ])
        ])
    ]

    #expect(resolveWorkflowTemplateString("echo {{nodes.web-request.output.body}}", input: input) == "echo ok")
    #expect(resolveWorkflowTemplateString("status={{nodes.web-request.output.status}}", input: input) == "status=200")
    #expect(resolveWorkflowTemplateString("msg={{input.message}}", input: input) == "msg=hello")
}

@Test
func workflowRunnerFailsWhenInjectedExecutorFails() async throws {
    let runner = WorkflowRunner()
    let definition = workflowDefinition(nodes: [
        WorkflowNode(id: "start", type: .trigger, title: "Start", laneId: "system"),
        WorkflowNode(id: "tool", type: .toolCheck, title: "Tool", laneId: "system", config: ["blockKind": .string("tool")]),
        WorkflowNode(id: "done", type: .end, title: "Done", laneId: "system")
    ], edges: [
        WorkflowEdge(id: "e1", sourceNodeId: "start", targetNodeId: "tool"),
        WorkflowEdge(id: "e2", sourceNodeId: "tool", targetNodeId: "done")
    ])
    let recorder = WorkflowRecorder()

    let result = await runner.start(
        definition: definition,
        context: .init(projectId: "project-1", taskId: nil, startedBy: "agent:test", input: [:]),
        persistence: recorder.persistence,
        updateTask: recorder.updateTask,
        executeTool: { _, _, _ in
            ToolInvocationResult(
                tool: "project.task_get",
                ok: false,
                error: ToolErrorPayload(code: "failed", message: "tool failed", retryable: false)
            )
        }
    )

    guard case .failed(let run, let message) = result else {
        Issue.record("Expected failed workflow run.")
        return
    }
    #expect(run.status == .failed)
    #expect(message == "tool failed")
    #expect(await recorder.steps.contains { $0.nodeId == "tool" && $0.status == .failed && $0.error == "tool failed" })
}

private func workflowDefinition(nodes: [WorkflowNode], edges: [WorkflowEdge]) -> WorkflowDefinition {
    WorkflowDefinition(
        id: "workflow-1",
        projectId: "project-1",
        name: "Workflow",
        lanes: [
            WorkflowLane(id: "system", title: "System", kind: .system),
            WorkflowLane(id: "owner", title: "Owner", kind: .human)
        ],
        nodes: nodes,
        edges: edges
    )
}

private actor WorkflowRecorder {
    private(set) var runs: [WorkflowRun] = []
    private(set) var steps: [WorkflowRunStep] = []
    private(set) var actions: [WorkflowPendingAction] = []
    private(set) var taskUpdates: [String] = []

    var persistence: WorkflowRunner.Persistence {
        WorkflowRunner.Persistence(
            saveRun: { [weak self] run in await self?.save(run: run) },
            saveStep: { [weak self] step in await self?.save(step: step) },
            saveAction: { [weak self] action in await self?.save(action: action) }
        )
    }

    func updateTask(projectId: String, taskId: String, status: String) async throws {
        taskUpdates.append("\(projectId):\(taskId):\(status)")
    }

    private func save(run: WorkflowRun) {
        runs.append(run)
    }

    private func save(step: WorkflowRunStep) {
        steps.append(step)
    }

    private func save(action: WorkflowPendingAction) {
        actions.append(action)
    }
}
