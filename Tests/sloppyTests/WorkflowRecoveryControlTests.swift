import Foundation
import Testing
import Protocols
@testable import sloppy

@Suite("Workflow reconciliation and merge", .timeLimit(.minutes(1)))
struct WorkflowRecoveryControlTests {
    @Test
    func verifiedResultAfterRestartDoesNotReplayUncertainProcess() async throws {
        let h = try await WorkflowCompletionHarness.make(disk: true)
        let graph = try await h.define([h.shell("effect", "printf x >> effect-marker; printf original"), h.shell("after", "printf '%s' '{{nodes.effect.output.stdout}}'")])
        let completed = try await h.start(graph)
        var state = try #require(try await h.service.workflowExecutionFiles.load(completed.run.id))
        state.run.status = .running; state.run.finishedAt = nil; state.run.currentNodeIds = ["effect"]
        state.steps.removeAll { !["start", "effect"].contains($0.nodeId) }
        state.steps[1].status = .running
        try await h.service.workflowExecutionFiles.save(state)
        await h.service.shutdownChannelPlugins()
        let restarted = CoreService(config: h.config)
        defer { Task { await restarted.shutdownChannelPlugins() } }
        let blocked = try await h.wait(state.run.id, service: restarted) { $0.run.status == .blocked }
        let step = try #require(blocked.steps.first { $0.nodeId == "effect" })
        _ = try await restarted.retryWorkflowRun(projectID: h.project, runID: state.run.id,
            request: .init(stepId: step.id, decision: .acceptResult, evidence: "Inspected effect-marker; process already completed once.",
                output: ["exitCode": .number(0), "stdout": .string("verified")], userId: "owner"))
        let finished = try await h.wait(state.run.id, service: restarted) { $0.run.status == .completed }
        #expect(finished.steps.first { $0.nodeId == "after" }?.output["stdout"] == .string("verified"))
        let root = try #require(finished.run.environment?.workingDirectory)
        #expect(try String(contentsOf: URL(fileURLWithPath: root).appendingPathComponent("effect-marker"), encoding: .utf8) == "x")
        #expect(finished.reconciliations?.count == 1)
    }

    @Test(arguments: [false, true])
    func mergeCanWaitForAllOrSelectFirstCompleted(race: Bool) async throws {
        let h = try await WorkflowCompletionHarness.make()
        defer { Task { await h.service.shutdownChannelPlugins() } }
        let definition = try await parallel(h, race: race)
        let receipt = try await h.service.startWorkflowRun(projectID: h.project, workflowID: definition.id, request: .init(startedBy: "owner"))
        if race {
            let completed = try await h.wait(receipt.run.id) { $0.run.status == .completed }
            #expect(completed.pendingActions.allSatisfy { $0.resolvedAt != nil })
            #expect(completed.steps.first { $0.nodeId == "after" }?.output["stdout"] == .string("A"))
        } else {
            let paused = try await h.wait(receipt.run.id) { $0.run.status == .waitingForHuman }
            let action = try #require(paused.pendingActions.first { $0.resolvedAt == nil })
            _ = try await h.service.resolveWorkflowPendingAction(projectID: h.project, actionID: action.id, request: .init(decision: .approved, resolvedBy: "owner"))
            let failed = try await h.wait(receipt.run.id) { $0.run.status == .failed }
            let parent = try #require(failed.steps.first { $0.nodeId == "fork" })
            let path = try #require(failed.run.environment?.workingDirectory)
            try Data().write(to: URL(fileURLWithPath: path).appendingPathComponent("allow"))
            _ = try await h.service.retryWorkflowRun(projectID: h.project, runID: receipt.run.id,
                request: .init(stepId: parent.id, decision: .retry, evidence: "Inspected failed branch. Prerequisite fixed; completed A must be retained.", userId: "owner"))
            let finished = try await h.wait(receipt.run.id) { $0.run.status == .completed }
            #expect(finished.steps.filter { $0.nodeId == "a" }.count == 1)
            #expect(finished.steps.filter { $0.nodeId == "fork" }.count == 2)
            #expect(try String(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("a-marker"), encoding: .utf8) == "x")
        }
    }

    @Test
    func taskOwnershipSurvivesRestartAndPreventsCompetingPickup() async throws {
        let h = try await WorkflowCompletionHarness.make(disk: true)
        let project = try await h.service.createProjectTask(projectID: h.project, request: .init(title: "Owned workflow"))
        let task = try #require(project.tasks.first)
        let graph = try await h.define([.init(id: "approve", type: .humanApproval, title: "Approve", laneId: "s")])
        let paused = try await h.service.startWorkflowRun(projectID: h.project, workflowID: graph.id, request: .init(taskId: task.id, startedBy: "owner"))
        await h.service.shutdownChannelPlugins()
        let restarted = CoreService(config: h.config)
        defer { Task { await restarted.shutdownChannelPlugins() } }
        await restarted.waitForStartup()
        #expect(await restarted.workflowTaskOwner(projectID: h.project, taskID: task.id) == paused.run.id)
        await #expect(throws: CoreService.ProjectError.self) {
            _ = try await restarted.startWorkflowRun(projectID: h.project, workflowID: graph.id, request: .init(taskId: task.id, startedBy: "other"))
        }
        _ = try await restarted.updateProjectTask(projectID: h.project, taskID: task.id, request: .init(status: "ready", changedBy: "owner"))
        #expect(try await restarted.getWorkflowRunDetail(projectID: h.project, runID: paused.run.id).run.status == .waitingForHuman)
        _ = try await restarted.cancelProjectTask(projectID: h.project, taskID: task.id, reason: "Owner stopped the task")
        #expect(try await restarted.getWorkflowRunDetail(projectID: h.project, runID: paused.run.id).run.status == .cancelled)
    }

    private func parallel(_ h: WorkflowCompletionHarness, race: Bool) async throws -> WorkflowDefinition {
        let nodes: [WorkflowNode] = [
            .init(id: "start", type: .trigger, title: "Start", laneId: "s"),
            .init(id: "fork", type: .parallel, title: "Fork", laneId: "s", config: ["joinNodeId": .string("merge")]),
            h.shell("a", "printf x >> a-marker; printf A"),
            .init(id: "approve", type: .humanApproval, title: "Approve", laneId: "s"),
            h.shell("b", "test -f allow || exit 7; printf B"),
            .init(id: "merge", type: .condition, title: "Merge", laneId: "s", config: ["blockKind": .string("merge"), "strategy": .string(race ? "first_completed" : "all")]),
            h.shell("after", "printf '%s' '{{nodes.a.output.stdout}}'"),
            .init(id: "end", type: .end, title: "End", laneId: "s")
        ]
        let pairs = [("start", "fork"), ("fork", "a"), ("fork", "approve"), ("a", "merge"), ("approve", "b"), ("b", "merge"), ("merge", "after"), ("after", "end")]
        return try await h.service.createWorkflowDefinition(projectID: h.project, request: .init(name: "Merge", lanes: [.init(id: "s", title: "System", kind: .system)], nodes: nodes,
            edges: pairs.enumerated().map { .init(id: "e\($0.offset)", sourceNodeId: $0.element.0, targetNodeId: $0.element.1) }))
    }
}

@Suite("Workflow environment reconciliation", .timeLimit(.minutes(1)))
struct WorkflowEnvironmentReconciliationTests {
    @Test
    func restoringDirectoryAfterApprovalDoesNotAskAgain() async throws {
        let h = try await WorkflowCompletionHarness.make()
        defer { Task { await h.service.shutdownChannelPlugins() } }
        let graph = try await h.define([.init(id: "approval", type: .humanApproval, title: "Approve", laneId: "s"), h.shell("after", "printf done")])
        let paused = try await h.start(graph)
        let path = try #require(paused.run.environment?.workingDirectory)
        let backup = path + "-moved"
        try FileManager.default.moveItem(atPath: path, toPath: backup)
        let action = try #require(paused.pendingActions.first)
        let blocked = try await h.service.resolveWorkflowPendingAction(projectID: h.project, actionID: action.id,
            request: .init(decision: .approved, resolvedBy: "owner"))
        #expect(blocked.run.status == .blocked)
        try FileManager.default.moveItem(atPath: backup, toPath: path)
        let environment = try #require(blocked.steps.last { $0.nodeId == "__environment" })
        _ = try await h.service.retryWorkflowRun(projectID: h.project, runID: paused.run.id,
            request: .init(stepId: environment.id, decision: .acceptResult, evidence: "Restored the exact original checkout directory.", output: [:], userId: "owner"))
        let finished = try await h.wait(paused.run.id) { $0.run.status == .completed }
        #expect(finished.steps.filter { $0.nodeId == "approval" }.count == 1)
        #expect(finished.pendingActions.count == 1 && finished.pendingActions.first?.resolvedAt != nil)
    }

    @Test
    func missingCheckpointCannotDowngradePinnedEnvironmentToLegacyResume() async throws {
        let h = try await WorkflowCompletionHarness.make(disk: true)
        defer { Task { await h.service.shutdownChannelPlugins() } }
        let graph = try await h.define([.init(id: "approval", type: .humanApproval, title: "Approve", laneId: "s"), h.shell("after", "printf wrong")])
        let paused = try await h.start(graph)
        let action = try #require(paused.pendingActions.first)
        let root = await h.service.workflowExecutionFiles.root
        try FileManager.default.removeItem(at: root.appendingPathComponent(paused.run.id).appendingPathExtension("json"))
        await #expect(throws: CoreService.WorkflowError.self) {
            _ = try await h.service.resolveWorkflowPendingAction(projectID: h.project, actionID: action.id,
                request: .init(decision: .approved, resolvedBy: "owner"))
        }
        #expect(try await h.service.getWorkflowRunDetail(projectID: h.project, runID: paused.run.id).steps.allSatisfy { $0.nodeId != "after" })
    }

    @Test
    func compactHistoryStopsAtSelectedTurn() throws {
        func status(_ id: String) -> AgentSessionEvent {
            .init(id: id, agentId: "a", sessionId: "s", type: .runStatus, runStatus: .init(stage: .done, label: "Done", executionOutcome: .completed))
        }
        let events = [status("first"), status("second"), status("later")]
        #expect(try CoreService.workflowCompactEvents(events, output: [:]).map(\.id) == ["first"])
        #expect(try CoreService.workflowCompactEvents(events, output: ["sessionAfterEventId": .string("first")]).map(\.id) == ["first", "second"])
        #expect(throws: (any Error).self) { try CoreService.workflowCompactEvents(events, output: ["sessionAfterEventId": .string("lost")]) }
    }
}
