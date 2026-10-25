import Foundation
import Testing
import Protocols
import PluginSDK
@testable import sloppy

@Suite("Workflow completion plan", .timeLimit(.minutes(1)))
struct WorkflowCompletionTests {
    @Test
    func compactCreatesCheckpointedSummaryAndFreshTargetSession() async throws {
        let h = try await WorkflowCompletionHarness.make(answers: ["source", "handoff", "target"])
        defer { Task { await h.service.shutdownChannelPlugins() } }
        let other = "reviewer-\(UUID().uuidString)"
        _ = try await h.service.createAgent(.init(id: other, displayName: "Reviewer", role: "Assistant"))
        let graph = try await h.define([
            .init(id: "source", type: .agentStep, title: "Source", laneId: "s", config: ["agentId": .string(h.agent), "mode": .string("ask"), "prompt": .string("Implement")]),
            .init(id: "handoff", type: .agentStep, title: "Handoff", laneId: "s", config: ["agentId": .string(other), "mode": .string("ask"), "prompt": .string("Review"), "sessionMode": .string("compact"), "sessionSourceNodeId": .string("source")])
        ])
        let result = try await h.start(graph)
        #expect(result.run.status == .completed)
        let source = try #require(result.steps.first { $0.nodeId == "source" })
        let compact = try #require(result.steps.first { $0.nodeId == "handoff" })
        #expect(compact.output["handoffSummary"] == .string("handoff"))
        #expect(compact.output["text"] == .string("target"))
        #expect(compact.output["contextPhase"] == .string("working"))
        #expect(compact.output["sessionId"] != source.output["sessionId"])
        #expect(compact.output["sessionId"] != compact.output["compactSessionId"])
        #expect(try await h.service.listAgentSessions(agentID: other).count == 2)
        let session = try await h.service.getAgentSession(agentID: other, sessionID: compact.output["sessionId"]?.asString ?? "")
        #expect(session.events.compactMap(\.message).contains { $0.role == .user && $0.segments.contains { $0.text?.contains("[Previous phase handoff]\nhandoff") == true } })
    }

    @Test
    func childApprovalSurvivesRestartAndDeletedLiveDefinition() async throws {
        let h = try await WorkflowCompletionHarness.make(disk: true)
        let child = try await h.define([
            .init(id: "ask", type: .humanInput, title: "Ask", laneId: "s"),
            h.shell("work", "printf '%s' '{{input.ticket}}:{{nodes.ask.output.comment}}'")
        ])
        let parent = try await h.define([
            .init(id: "child", type: .toolCheck, title: "Child", laneId: "s", config: ["blockKind": .string("sub_workflow"), "workflowId": .string(child.id)]),
            h.shell("after", "printf '%s' '{{nodes.child.output.nodes.work.stdout}}'")
        ])
        let receipt = try await h.service.startWorkflowRun(projectID: h.project, workflowID: parent.id,
            request: .init(startedBy: "owner", input: ["ticket": .string("WF-42")]))
        let waiting = try await h.wait(receipt.run.id) { $0.run.status == .waitingForWorkflow }
        let step = try #require(waiting.steps.first { $0.nodeId == "child" })
        let childID = try #require(step.output["childRunId"]?.asString)
        let childWait = try await h.wait(childID) { $0.run.status == .waitingForHuman }
        let action = try #require(childWait.pendingActions.first)
        try await h.service.deleteWorkflowDefinition(projectID: h.project, workflowID: child.id)
        await h.service.shutdownChannelPlugins()
        let restarted = CoreService(config: h.config)
        defer { Task { await restarted.shutdownChannelPlugins() } }
        _ = try await restarted.resolveWorkflowPendingAction(projectID: h.project, actionID: action.id,
            request: .init(decision: .approved, comment: "ship", resolvedBy: "owner"))
        let completed = try await h.wait(receipt.run.id, service: restarted) { $0.run.status == .completed }
        #expect(completed.steps.first { $0.nodeId == "after" }?.output["stdout"] == .string("WF-42:ship"))
        #expect(completed.steps.filter { $0.nodeId == "child" }.count == 1)
        #expect(await restarted.listWorkflowRuns(projectID: h.project).count == 2)
    }

    @Test
    func childFailureAndRecursionNeverCompleteParent() async throws {
        let h = try await WorkflowCompletionHarness.make()
        defer { Task { await h.service.shutdownChannelPlugins() } }
        let child = try await h.define([h.shell("work", "exit 8")])
        let parent = try await h.define([.init(id: "child", type: .toolCheck, title: "Child", laneId: "s",
            config: ["blockKind": .string("sub_workflow"), "workflowId": .string(child.id)]), h.shell("after", "echo wrong")])
        let receipt = try await h.service.startWorkflowRun(projectID: h.project, workflowID: parent.id, request: .init(startedBy: "owner"))
        let failed = try await h.wait(receipt.run.id) { $0.run.status == .failed }
        #expect(!failed.steps.contains { $0.nodeId == "after" })
        var nodes = parent.nodes; nodes[1].config["workflowId"] = .string(parent.id)
        _ = try await h.service.updateWorkflowDefinition(projectID: h.project, workflowID: parent.id,
            request: .init(name: parent.name, lanes: parent.lanes, nodes: nodes, edges: parent.edges))
        let recursive = try await h.service.startWorkflowRun(projectID: h.project, workflowID: parent.id, request: .init(startedBy: "owner"))
        let stopped = try await h.wait(recursive.run.id) { $0.run.status == .failed }
        #expect(stopped.steps.first { $0.nodeId == "child" }?.output["errorCode"] == .string("workflow_child_failed"))
    }

    @Test
    func retryRetainsCompletedEffectsAndRecordsEvidence() async throws {
        let h = try await WorkflowCompletionHarness.make()
        defer { Task { await h.service.shutdownChannelPlugins() } }
        let graph = try await h.define([h.shell("before", "printf x >> before-marker"), h.shell("effect", "test -f allow || exit 7; printf fixed")])
        let failed = try await h.start(graph)
        #expect(failed.run.status == .failed)
        let step = try #require(failed.steps.first { $0.nodeId == "effect" })
        await #expect(throws: (any Error).self) {
            _ = try await h.service.retryWorkflowRun(projectID: h.project, runID: failed.run.id,
                request: .init(stepId: step.id, decision: .retry, evidence: "", userId: "owner"))
        }
        let root = try #require(failed.run.environment?.workingDirectory)
        try Data().write(to: URL(fileURLWithPath: root).appendingPathComponent("allow"))
        _ = try await h.service.retryWorkflowRun(projectID: h.project, runID: failed.run.id,
            request: .init(stepId: step.id, decision: .retry, evidence: "Inspected failed command; prerequisite is now present.", userId: "owner"))
        let completed = try await h.wait(failed.run.id) { $0.run.status == .completed }
        #expect(completed.steps.filter { $0.nodeId == "effect" }.count == 2)
        #expect(completed.steps.filter { $0.nodeId == "before" }.count == 1)
        #expect(try String(contentsOf: URL(fileURLWithPath: root).appendingPathComponent("before-marker"), encoding: .utf8) == "x")
        #expect(completed.reconciliations?.first?.previousStep.id == step.id)
    }

    @Test
    func cancelRetiresApprovalAndRetryCreatesANewDecision() async throws {
        let h = try await WorkflowCompletionHarness.make()
        defer { Task { await h.service.shutdownChannelPlugins() } }
        let graph = try await h.define([.init(id: "approval", type: .humanApproval, title: "Approve", laneId: "s"), h.shell("after", "printf done")])
        let paused = try await h.start(graph)
        let action = try #require(paused.pendingActions.first)
        let step = try #require(paused.steps.first { $0.nodeId == "approval" })
        let cancelled = try await h.service.cancelWorkflowRun(projectID: h.project, runID: paused.run.id, request: .init(userId: "owner"))
        #expect(cancelled.run.status == .cancelled)
        #expect(await h.service.listWorkflowPendingActions(projectID: h.project).isEmpty)
        let duplicate = try await h.service.resolveWorkflowPendingAction(projectID: h.project, actionID: action.id, request: .init(decision: .approved, resolvedBy: "owner"))
        #expect(duplicate.run.status == .cancelled)
        _ = try await h.service.retryWorkflowRun(projectID: h.project, runID: paused.run.id,
            request: .init(stepId: step.id, decision: .retry, evidence: "Owner requests a fresh approval.", userId: "owner"))
        let waiting = try await h.wait(paused.run.id) { $0.run.status == .waitingForHuman }
        let next = try #require(waiting.pendingActions.first { $0.resolvedAt == nil })
        #expect(next.id != action.id)
        _ = try await h.service.resolveWorkflowPendingAction(projectID: h.project, actionID: next.id, request: .init(decision: .approved, resolvedBy: "owner"))
        #expect(try await h.service.getWorkflowRunDetail(projectID: h.project, runID: paused.run.id).run.status == .completed)
    }

    @Test
    func taskNodeAndNotificationUseRealSnapshotAndDeliveryReceipt() async throws {
        let h = try await WorkflowCompletionHarness.make()
        defer { Task { await h.service.shutdownChannelPlugins() } }
        let channel = "workflow:test"
        _ = try await h.service.createProjectChannel(projectID: h.project, request: .init(title: "Workflow", channelId: channel))
        let plugin = WorkflowRecordingGateway(channel: channel)
        await h.service.channelDelivery.registerPlugin(plugin)
        let project = try await h.service.createProjectTask(projectID: h.project, request: .init(title: "Notify task"))
        let task = try #require(project.tasks.first)
        let graph = try await h.define([
            .init(id: "task", type: .projectTask, title: "Task", laneId: "s"),
            .init(id: "notify", type: .notify, title: "Notify", laneId: "s", config: ["channelId": .string(channel), "message": .string("Done: {{nodes.task.output.title}}")])
        ])
        let completed = try await h.service.startWorkflowRun(projectID: h.project, workflowID: graph.id,
            request: .init(taskId: task.id, startedBy: "owner", background: false))
        #expect(completed.run.status == .completed)
        #expect(completed.steps.first { $0.nodeId == "notify" }?.output["delivered"] == .bool(true))
        #expect(await plugin.sent == ["Done: Notify task"])
    }
}

struct WorkflowCompletionHarness {
    var service: CoreService
    var config: CoreConfig
    var project: String
    var agent: String
    static func make(disk: Bool = false, answers: [String] = ["answer"]) async throws -> Self {
        var config = CoreConfig.test
        config.compactor.enabled = false // This fixture tests explicit workflow handoffs, not background memory jobs.
        let service = disk ? CoreService(config: config) : CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let id = "completion-\(UUID().uuidString.lowercased())"
        await service.overrideModelProviderForTests(WorkflowModelProvider(probe: WorkflowModelProbe(answers: answers)), defaultModel: "mock:test-model")
        _ = try await service.createProject(.init(id: id, name: "Completion", description: "", channels: []))
        _ = try await service.createAgent(.init(id: id, displayName: "Worker", role: "Assistant"))
        return .init(service: service, config: config, project: id, agent: id)
    }
    func shell(_ id: String, _ command: String) -> WorkflowNode {
        .init(id: id, type: .toolCheck, title: id, laneId: "s", config: ["blockKind": .string("bash"), "command": .string(command)])
    }
    func define(_ body: [WorkflowNode]) async throws -> WorkflowDefinition {
        let nodes = [WorkflowNode(id: "start", type: .trigger, title: "Start", laneId: "s")] + body + [.init(id: "end", type: .end, title: "End", laneId: "s")]
        let edges = zip(nodes, nodes.dropFirst()).enumerated().map { index, pair in WorkflowEdge(id: "edge-\(index)", sourceNodeId: pair.0.id, targetNodeId: pair.1.id) }
        return try await service.createWorkflowDefinition(projectID: project, request: .init(name: "Completion", lanes: [.init(id: "s", title: "System", kind: .system)], nodes: nodes, edges: edges))
    }
    func start(_ graph: WorkflowDefinition) async throws -> WorkflowRunDetail {
        try await service.startWorkflowRun(projectID: project, workflowID: graph.id, request: .init(startedBy: "owner", background: false))
    }
    func wait(_ id: String, service other: CoreService? = nil, until predicate: (WorkflowRunDetail) -> Bool) async throws -> WorkflowRunDetail {
        let service = other ?? service
        var detail = try await service.getWorkflowRunDetail(projectID: project, runID: id)
        for _ in 0..<500 {
            if predicate(detail) { return detail }
            try await Task.sleep(for: .milliseconds(20))
            detail = try await service.getWorkflowRunDetail(projectID: project, runID: id)
        }
        #expect(predicate(detail), "Last status: \(detail.run.status), errors: \(detail.steps.compactMap(\.error))")
        return detail
    }
}

private actor WorkflowRecordingGateway: GatewayPlugin {
    nonisolated let id = "workflow-test-gateway"
    nonisolated let channelIds: [String]
    var sent: [String] = []
    init(channel: String) { channelIds = [channel] }
    func start(inboundReceiver: any InboundMessageReceiver) async throws {}
    func stop() async {}
    func send(channelId: String, message: String, topicId: String?) async throws { sent.append(message) }
}

@Suite("Workflow child and compact recovery", .timeLimit(.minutes(1)))
struct WorkflowChildCompactRecoveryTests {
    @Test
    func malformedChildInputNeverStartsAnEmptyInputRun() async throws {
        let h = try await WorkflowCompletionHarness.make()
        defer { Task { await h.service.shutdownChannelPlugins() } }
        let child = try await h.define([h.shell("effect", "printf should-not-run")])
        let parent = try await h.define([.init(id: "child", type: .toolCheck, title: "Child", laneId: "s", config: ["blockKind": .string("sub_workflow"), "workflowId": .string(child.id), "input": .array([])])])
        let receipt = try await h.service.startWorkflowRun(projectID: h.project, workflowID: parent.id, request: .init(startedBy: "owner"))
        _ = try await h.wait(receipt.run.id) { $0.run.status == .failed }
        #expect(await h.service.listWorkflowRuns(projectID: h.project).count == 1)
    }

    @Test
    func retryingParentKeepsExistingChildAndItsCompletedEffects() async throws {
        let h = try await WorkflowCompletionHarness.make()
        defer { Task { await h.service.shutdownChannelPlugins() } }
        let child = try await h.define([h.shell("before", "printf x >> child-before"), h.shell("effect", "test -f allow-child || exit 7; printf repaired")])
        let parent = try await h.define([.init(id: "child", type: .toolCheck, title: "Child", laneId: "s", config: ["blockKind": .string("sub_workflow"), "workflowId": .string(child.id)])])
        let receipt = try await h.service.startWorkflowRun(projectID: h.project, workflowID: parent.id, request: .init(startedBy: "owner"))
        let failed = try await h.wait(receipt.run.id) { $0.run.status == .failed }
        let parentStep = try #require(failed.steps.first { $0.nodeId == "child" })
        let childID = try #require(parentStep.output["childRunId"]?.asString)
        let childRun = try await h.service.getWorkflowRunDetail(projectID: h.project, runID: childID)
        let effect = try #require(childRun.steps.first { $0.nodeId == "effect" })
        let path = try #require(childRun.run.environment?.workingDirectory)
        try Data().write(to: URL(fileURLWithPath: path).appendingPathComponent("allow-child"))
        _ = try await h.service.retryWorkflowRun(projectID: h.project, runID: childID,
            request: .init(stepId: effect.id, decision: .retry, evidence: "Inspected child side effects; fixed prerequisite.", userId: "owner"))
        _ = try await h.wait(childID) { $0.run.status == .completed }
        _ = try await h.service.retryWorkflowRun(projectID: h.project, runID: receipt.run.id,
            request: .init(stepId: parentStep.id, decision: .retry, evidence: "The original child is now completed.", userId: "owner"))
        let finished = try await h.wait(receipt.run.id) { $0.run.status == .completed }
        #expect(finished.steps.last { $0.nodeId == "child" }?.output["childRunId"] == .string(childID))
        #expect(await h.service.listWorkflowRuns(projectID: h.project).count == 2)
        #expect(try String(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("child-before"), encoding: .utf8) == "x")
    }

    @Test
    func compactWorkingSessionBindingSurvivesRestartBeforePost() async throws {
        let h = try await WorkflowCompletionHarness.make(disk: true, answers: ["source", "handoff", "target"])
        let graph = try await h.define([
            .init(id: "source", type: .agentStep, title: "Source", laneId: "s", config: ["agentId": .string(h.agent), "mode": .string("ask"), "prompt": .string("Work")]),
            .init(id: "compact", type: .agentStep, title: "Compact", laneId: "s", config: ["agentId": .string(h.agent), "mode": .string("ask"), "model": .string("mock:test-model"), "prompt": .string("Continue"), "sessionMode": .string("compact"), "sessionSourceNodeId": .string("source")])
        ])
        let finished = try await h.start(graph)
        #expect(finished.run.status == .completed)
        var state = try #require(try await h.service.workflowExecutionFiles.load(finished.run.id))
        let fresh = try await h.service.createAgentSession(agentID: h.agent, request: .init(title: "Prepared working session", separateChat: true, projectId: h.project))
        state.run.status = .running; state.run.finishedAt = nil; state.run.currentNodeIds = ["compact"]
        state.steps.removeAll { $0.nodeId == "end" }
        let index = try #require(state.steps.firstIndex { $0.nodeId == "compact" })
        let compactSession = state.steps[index].output["compactSessionId"]
        state.steps[index].status = .running
        state.steps[index].output["sessionId"] = .string(fresh.id)
        state.steps[index].output["sessionAfterEventId"] = .null
        try await h.service.workflowExecutionFiles.save(state)
        await h.service.shutdownChannelPlugins()
        var config = h.config; config.disableModelInference = false
        let restarted = CoreService(config: config)
        defer { Task { await restarted.shutdownChannelPlugins() } }
        let completed = try await h.wait(finished.run.id, service: restarted) { $0.run.status == .completed }
        let step = try #require(completed.steps.first { $0.nodeId == "compact" })
        #expect(step.output["sessionId"] == .string(fresh.id))
        #expect(step.output["compactSessionId"] == compactSession)
        #expect(step.output["handoffSummary"] == .string("handoff"))
        let history = try await restarted.getAgentSession(agentID: h.agent, sessionID: fresh.id)
        #expect(history.events.filter { $0.message?.role == .user }.count == 1)
        let directory = await restarted.toolContextForSession(sessionID: fresh.id, sessionTitle: fresh.title, projectID: h.project)
        #expect(directory.workingDirectory == state.run.environment?.workingDirectory)
        let summarySession = try #require(step.output["compactSessionId"]?.asString)
        #expect(await restarted.workflowSessionDirectory(summarySession) == state.run.environment?.workingDirectory)
    }

    @Test
    func verifiedAgentResultPreservesSessionBoundaryAndAllowsCompact() async throws {
        let h = try await WorkflowCompletionHarness.make(answers: ["first", "not-json", "handoff", "final"])
        defer { Task { await h.service.shutdownChannelPlugins() } }
        let graph = try await h.define([
            .init(id: "source", type: .agentStep, title: "Source", laneId: "s", config: ["agentId": .string(h.agent), "mode": .string("ask"), "prompt": .string("Work")]),
            .init(id: "review", type: .agentStep, title: "Review", laneId: "s", config: ["agentId": .string(h.agent), "mode": .string("ask"), "prompt": .string("Review"), "sessionMode": .string("shared"), "sessionSourceNodeId": .string("source"), "outputFormat": .string("json")]),
            .init(id: "compact", type: .agentStep, title: "Compact", laneId: "s", config: ["agentId": .string(h.agent), "mode": .string("ask"), "prompt": .string("Continue"), "sessionMode": .string("compact"), "sessionSourceNodeId": .string("review")])
        ])
        let failed = try await h.start(graph)
        #expect(failed.run.status == .failed)
        let review = try #require(failed.steps.first { $0.nodeId == "review" })
        let boundary = try #require(review.output["sessionAfterEventId"]?.asString)
        _ = try await h.service.retryWorkflowRun(projectID: h.project, runID: failed.run.id,
            request: .init(stepId: review.id, decision: .acceptResult, evidence: "Inspected the completed native turn and corrected its serialized result.",
                output: ["result": .object(["verdict": .string("approved")])], userId: "owner"))
        let completed = try await h.wait(failed.run.id) { $0.run.status == .completed }
        let accepted = try #require(completed.steps.first { $0.nodeId == "review" })
        #expect(accepted.output["sessionAfterEventId"] == .string(boundary))
        #expect(accepted.output["agentId"] == review.output["agentId"] && accepted.output["sessionId"] == review.output["sessionId"])
        #expect(accepted.output["agentOutcome"] == .string("completed"))
        #expect(completed.steps.first { $0.nodeId == "compact" }?.output["handoffSummary"] == .string("handoff"))
    }

    @Test
    func idempotentStartReturnsPinnedRunAndRejectsDifferentInput() async throws {
        let h = try await WorkflowCompletionHarness.make()
        defer { Task { await h.service.shutdownChannelPlugins() } }
        let graph = try await h.define([h.shell("effect", "printf x >> idempotent-marker")])
        let request = WorkflowRunCreateRequest(startedBy: "owner", background: false, idempotencyKey: UUID().uuidString)
        let first = try await h.service.startWorkflowRun(projectID: h.project, workflowID: graph.id, request: request)
        let second = try await h.service.startWorkflowRun(projectID: h.project, workflowID: graph.id, request: request)
        #expect(first.run.id == second.run.id)
        let path = try #require(first.run.environment?.workingDirectory)
        #expect(try String(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("idempotent-marker"), encoding: .utf8) == "x")
        var changed = request; changed.input = ["different": .bool(true)]
        await #expect(throws: CoreService.WorkflowError.self) { _ = try await h.service.startWorkflowRun(projectID: h.project, workflowID: graph.id, request: changed) }
    }
}

@Suite("Workflow task ownership through child repair", .timeLimit(.minutes(1)))
struct WorkflowChildTaskOwnershipTests {
    @Test
    func repairedChildKeepsTaskReservedUntilParentCompletes() async throws {
        let h = try await WorkflowCompletionHarness.make()
        defer { Task { await h.service.shutdownChannelPlugins() } }
        let project = try await h.service.createProjectTask(projectID: h.project, request: .init(title: "Child repair"))
        let task = try #require(project.tasks.first)
        let child = try await h.define([h.shell("effect", "test -f allow-repair || exit 7; printf fixed"),
            .init(id: "approval", type: .humanApproval, title: "Confirm repair", laneId: "s")])
        let parent = try await h.define([.init(id: "child", type: .toolCheck, title: "Child", laneId: "s", config: ["blockKind": .string("sub_workflow"), "workflowId": .string(child.id)])])
        let receipt = try await h.service.startWorkflowRun(projectID: h.project, workflowID: parent.id, request: .init(taskId: task.id, startedBy: "owner"))
        let failed = try await h.wait(receipt.run.id) { $0.run.status == .failed }
        let parentStep = try #require(failed.steps.first { $0.nodeId == "child" })
        let childID = try #require(parentStep.output["childRunId"]?.asString)
        let childFailure = try await h.service.getWorkflowRunDetail(projectID: h.project, runID: childID)
        let effect = try #require(childFailure.steps.first { $0.nodeId == "effect" })
        let path = try #require(childFailure.run.environment?.workingDirectory)
        try Data().write(to: URL(fileURLWithPath: path).appendingPathComponent("allow-repair"))
        _ = try await h.service.retryWorkflowRun(projectID: h.project, runID: childID,
            request: .init(stepId: effect.id, decision: .retry, evidence: "Fixed the inspected prerequisite.", userId: "owner"))
        let waiting = try await h.wait(childID) { $0.run.status == .waitingForHuman }
        #expect(await h.service.workflowTaskOwner(projectID: h.project, taskID: task.id) == childID)
        await #expect(throws: CoreService.ProjectError.self) {
            _ = try await h.service.startWorkflowRun(projectID: h.project, workflowID: parent.id, request: .init(taskId: task.id, startedBy: "competing"))
        }
        _ = try await h.service.retryWorkflowRun(projectID: h.project, runID: receipt.run.id,
            request: .init(stepId: parentStep.id, decision: .retry, evidence: "Continue waiting on the original repaired child.", userId: "owner"))
        _ = try await h.wait(receipt.run.id) { $0.run.status == .waitingForWorkflow }
        #expect(await h.service.workflowTaskOwner(projectID: h.project, taskID: task.id) == receipt.run.id)
        let action = try #require(waiting.pendingActions.first { $0.resolvedAt == nil })
        _ = try await h.service.resolveWorkflowPendingAction(projectID: h.project, actionID: action.id, request: .init(decision: .approved, resolvedBy: "owner"))
        _ = try await h.wait(receipt.run.id) { $0.run.status == .completed }
        for _ in 0..<100 where await h.service.workflowTaskOwner(projectID: h.project, taskID: task.id) != nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(await h.service.workflowTaskOwner(projectID: h.project, taskID: task.id) == nil)
    }
}
