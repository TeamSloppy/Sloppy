import Foundation
import Testing
import Protocols
@testable import sloppy

@Suite("Workflow winner recovery", .timeLimit(.minutes(1)))
struct WorkflowRaceRecoveryTests {
    @Test(arguments: [WorkflowRunStatus.waitingForWorkflow, .running, .cancelled])
    func persistedWinnerCancelsQueuedLosingChildBeforeEffects(interrupted: WorkflowRunStatus) async throws {
        let h = try await WorkflowCompletionHarness.make(disk: true)
        let child = try await h.define([h.shell("effect", "printf x >> losing-child-effect")])
        let parent = try await h.service.createWorkflowDefinition(projectID: h.project, request: .init(name: "Race recovery", lanes: [.init(id: "s", title: "System", kind: .system)], nodes: [
            .init(id: "start", type: .trigger, title: "Start", laneId: "s"),
            .init(id: "fork", type: .parallel, title: "Race", laneId: "s", config: ["joinNodeId": .string("join")]),
            h.shell("a", "printf A"),
            .init(id: "child", type: .toolCheck, title: "Child", laneId: "s", config: ["blockKind": .string("sub_workflow"), "workflowId": .string(child.id)]),
            .init(id: "join", type: .join, title: "Join", laneId: "s", config: ["strategy": .string("first_completed")]),
            .init(id: "end", type: .end, title: "End", laneId: "s")
        ], edges: [
            .init(id: "1", sourceNodeId: "start", targetNodeId: "fork"), .init(id: "2", sourceNodeId: "fork", targetNodeId: "a"),
            .init(id: "3", sourceNodeId: "fork", targetNodeId: "child"), .init(id: "4", sourceNodeId: "a", targetNodeId: "join"),
            .init(id: "5", sourceNodeId: "child", targetNodeId: "join"), .init(id: "6", sourceNodeId: "join", targetNodeId: "end")]))
        let parentID = "run_\(UUID().uuidString.lowercased())"
        let key = UUID().uuidString.lowercased()
        let childID = "run_\(key)"
        var environment = try await h.service.planWorkflowEnvironment(projectID: h.project, runID: parentID, request: .init(startedBy: "owner"))
        environment.preparation = .ready
        let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(environment))
        let input: [String: JSONValue] = ["environment": value, "cwd": .string(environment.workingDirectory), "__workflowAncestors": .array([.string(parent.id)])]
        let fork = WorkflowRunStep(id: "step_fork", runId: parentID, nodeId: "fork", status: .running,
            input: ["input": .object(input), "environment": value, "nodes": .object([:])], startedAt: Date())
        var a = WorkflowRunStep(id: "step_a", runId: "branch-a", nodeId: "a", status: .succeeded, output: ["stdout": .string("A"), "exitCode": .number(0)], startedAt: Date())
        var losing = WorkflowRunStep(id: "step_\(key)", runId: "branch-child", nodeId: "child", status: .waiting,
            output: ["childRunId": .string(childID), "childWorkflowId": .string(child.id), "childStatus": .string("queued")], startedAt: Date())
        let winner = WorkflowParallelBranch(id: "a", run: .init(id: "branch-a", workflowId: parent.id, workflowVersion: parent.version,
            projectId: h.project, status: .completed, startedBy: "owner"), steps: [a])
        let loser = WorkflowParallelBranch(id: "child", run: .init(id: "branch-child", workflowId: parent.id, workflowVersion: parent.version,
            projectId: h.project, status: interrupted == .cancelled ? .running : interrupted, currentNodeIds: ["child"], startedBy: "owner"), steps: [losing])
        a.runId = parentID; losing.runId = parentID
        let state = WorkflowExecutionState(definition: parent, originalInput: input,
            run: .init(id: parentID, workflowId: parent.id, workflowVersion: parent.version, projectId: h.project, status: interrupted == .cancelled ? .cancelled : .running,
                currentNodeIds: ["fork"], startedBy: "owner", finishedAt: interrupted == .cancelled ? Date() : nil, environment: environment), steps: [fork, a, losing],
            parallel: .init(nodeID: "fork", stepID: fork.id, branches: [winner, loser], visitCounts: ["fork": 1], winner: interrupted == .cancelled ? nil : "a"))
        var childInput = input; childInput["__workflowAncestors"] = .array([.string(parent.id), .string(child.id)])
        let queued = WorkflowExecutionState(definition: child, originalInput: childInput,
            run: .init(id: childID, workflowId: child.id, workflowVersion: child.version, projectId: h.project, status: .queued, startedBy: "owner", environment: environment),
            startRequest: .init(startedBy: "owner", input: [:], background: true, idempotencyKey: key))
        // The child is deliberately written first: index ordering must not decide whether it replays.
        try await h.service.workflowExecutionFiles.save(queued)
        try await h.service.workflowExecutionFiles.save(state)
        await h.service.shutdownChannelPlugins()
        let restarted = CoreService(config: h.config)
        defer { Task { await restarted.shutdownChannelPlugins() } }
        _ = try await h.wait(parentID, service: restarted) { $0.run.status == (interrupted == .cancelled ? .cancelled : .completed) }
        let cancelled = try await h.wait(childID, service: restarted) { $0.run.status == .cancelled }
        #expect(cancelled.run.status == .cancelled)
        #expect(!FileManager.default.fileExists(atPath: URL(fileURLWithPath: environment.workingDirectory).appendingPathComponent("losing-child-effect").path))
    }
}

@Suite("Workflow parallel result projection", .timeLimit(.minutes(1)))
struct WorkflowParallelProjectionTests {
    @Test
    func acceptedAggregateDoesNotExecuteCompletedBranchesAgain() async throws {
        let h = try await WorkflowCompletionHarness.make()
        defer { Task { await h.service.shutdownChannelPlugins() } }
        let graph = try await makeGraph(h, race: false, schema: true)
        let receipt = try await h.service.startWorkflowRun(projectID: h.project, workflowID: graph.id, request: .init(startedBy: "owner"))
        let failed = try await h.wait(receipt.run.id) { $0.run.status == .failed }
        let fork = try #require(failed.steps.first { $0.nodeId == "fork" })
        _ = try await h.service.retryWorkflowRun(projectID: h.project, runID: receipt.run.id,
            request: .init(stepId: fork.id, decision: .acceptResult, evidence: "Both branches completed; verified the aggregate contract.", output: ["verified": .bool(true)], userId: "owner"))
        let waiting = try await h.wait(receipt.run.id) { $0.run.status == .waitingForHuman }
        let path = try #require(waiting.run.environment?.workingDirectory)
        for id in ["a", "b"] {
            #expect(waiting.steps.filter { $0.nodeId == id }.count == 1)
            #expect(try String(contentsOf: URL(fileURLWithPath: path).appendingPathComponent(id + "-projection"), encoding: .utf8) == "x")
        }
        #expect(waiting.steps.filter { $0.nodeId == "fork" }.count == 1)
    }

    @Test
    func completedLoserHistoryIsNotExportedWhenResumingAfterWinner() async throws {
        let h = try await WorkflowCompletionHarness.make(disk: true)
        let graph = try await makeGraph(h, race: true, schema: false)
        let run = WorkflowRun(id: "run_\(UUID().uuidString.lowercased())", workflowId: graph.id, workflowVersion: graph.version,
            projectId: h.project, status: .waitingForHuman, currentNodeIds: ["approval"], startedBy: "owner")
        let aggregate: [String: JSONValue] = ["branches": .object(["a": .object(["stdout": .string("A")])])]
        let action = WorkflowPendingAction(id: "action_\(UUID().uuidString)", projectId: h.project, workflowRunId: run.id,
            nodeId: "approval", assignee: "owner", prompt: "Continue?", decisions: [.approved])
        let steps: [WorkflowRunStep] = [
            .init(id: "a", runId: run.id, nodeId: "a", status: .succeeded, output: ["stdout": .string("A")]),
            .init(id: "b", runId: run.id, nodeId: "b", status: .succeeded, output: ["stdout": .string("B")]),
            .init(id: "fork", runId: run.id, nodeId: "fork", status: .succeeded, output: aggregate),
            .init(id: "join", runId: run.id, nodeId: "join", status: .succeeded, output: aggregate),
            .init(id: "approval", runId: run.id, nodeId: "approval", status: .waiting)
        ]
        try await h.service.workflowExecutionFiles.save(.init(definition: graph, originalInput: [:], run: run, steps: steps, actions: [action]))
        await h.service.shutdownChannelPlugins()
        let restarted = CoreService(config: h.config)
        defer { Task { await restarted.shutdownChannelPlugins() } }
        let result = try await restarted.resolveWorkflowPendingAction(projectID: h.project, actionID: action.id,
            request: .init(decision: .approved, resolvedBy: "owner"))
        #expect(result.run.status == .failed)
        #expect(result.steps.first { $0.nodeId == "after" }?.error?.contains("Missing workflow reference") == true)
    }

    private func makeGraph(_ h: WorkflowCompletionHarness, race: Bool, schema: Bool) async throws -> WorkflowDefinition {
        var forkConfig: [String: JSONValue] = ["joinNodeId": .string("join")]
        if schema { forkConfig["outputSchema"] = .object(["type": .string("object"), "required": .array([.string("verified")]), "properties": .object(["verified": .object(["type": .string("boolean")])])]) }
        let nodes: [WorkflowNode] = [
            .init(id: "start", type: .trigger, title: "Start", laneId: "s"),
            .init(id: "fork", type: .parallel, title: "Fork", laneId: "s", config: forkConfig),
            h.shell("a", "printf x >> a-projection; printf A"), h.shell("b", "printf x >> b-projection; printf B"),
            .init(id: "join", type: .join, title: "Join", laneId: "s", config: ["strategy": .string(race ? "first_completed" : "all")]),
            .init(id: "approval", type: .humanApproval, title: "Approve", laneId: "s"),
            h.shell("after", "printf '%s' '{{nodes.b.output.stdout}}'"),
            .init(id: "end", type: .end, title: "End", laneId: "s")
        ]
        let pairs = [("start", "fork"), ("fork", "a"), ("fork", "b"), ("a", "join"), ("b", "join"), ("join", "approval"), ("approval", "after"), ("after", "end")]
        return try await h.service.createWorkflowDefinition(projectID: h.project, request: .init(name: "Projection", lanes: [.init(id: "s", title: "System", kind: .system)], nodes: nodes,
            edges: pairs.enumerated().map { .init(id: "e\($0.offset)", sourceNodeId: $0.element.0, targetNodeId: $0.element.1) }))
    }
}
