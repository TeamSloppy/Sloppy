import Foundation
import Testing
import Protocols
@testable import sloppy

@Suite("Workflow parallel input", .timeLimit(.minutes(1)))
struct WorkflowParallelInputTests {
    @Test
    func approvalContinuesBeforeSiblingModelCompletes() async throws {
        let probe = WorkflowModelProbe(gated: true)
        let (service, _, graph, agent) = try await fixture(probe: probe, mode: "ask")
        defer { Task { await probe.release(); await service.shutdownChannelPlugins() } }
        let receipt = try await service.startWorkflowRun(projectID: graph.projectId, workflowID: graph.id,
            request: .init(startedBy: "owner", input: ["ticket": .string("WF-42")]))
        #expect(receipt.run.status == .queued)
        var starts = probe.started.makeAsyncIterator()
        _ = await starts.next()
        let paused = try await wait(service, run: receipt.run) { $0.pendingActions.contains { $0.resolvedAt == nil } }
        let action = try #require(paused.pendingActions.first)
        #expect(action.prompt == "Approve WF-42")
        _ = try await service.resolveWorkflowPendingAction(projectID: graph.projectId, actionID: action.id,
            request: .init(decision: .approved, resolvedBy: "owner"))
        let advanced = try await wait(service, run: receipt.run) { $0.steps.contains { $0.nodeId == "effect" && $0.status == .succeeded } }
        #expect(!advanced.steps.contains { $0.nodeId == "join" })
        #expect(advanced.steps.first { $0.nodeId == "agent" }?.status == .running)
        await probe.release()
        let completed = try await wait(service, run: receipt.run) { $0.run.status == .completed }
        #expect(completed.steps.filter { $0.nodeId == "approve" }.count == 1)
        #expect(completed.steps.first { $0.nodeId == "after" }?.output["stdout"] == .string("approved:Workflow model answer:WF-42"))
        #expect(try await service.listAgentSessions(agentID: agent).count == 1)
    }

    @Test(arguments: [PlanInputResponseStatus.answered, .cancelled])
    func mixedWaitsSurviveRestartAndCancellationRetiresSibling(status: PlanInputResponseStatus) async throws {
        let (service, config, graph, agent) = try await fixture(probe: WorkflowModelProbe(requestsInput: true))
        let receipt = try await service.startWorkflowRun(projectID: graph.projectId, workflowID: graph.id,
            request: .init(startedBy: "owner", input: ["ticket": .string("WF-42")]))
        let paused = try await wait(service, run: receipt.run) { detail in
            detail.pendingActions.contains { $0.resolvedAt == nil } && detail.steps.contains { $0.nodeId == "agent" && $0.status == .waiting }
        }
        let step = try #require(paused.steps.first { $0.nodeId == "agent" })
        let action = try #require(paused.pendingActions.first)
        let session = try #require(step.output["sessionId"]?.asString)
        let request = try #require(try await service.getAgentSession(agentID: agent, sessionID: session).events.compactMap(\.inputRequest).last)
        await service.shutdownChannelPlugins()
        let restarted = CoreService(config: config)
        await restarted.overrideModelProviderForTests(WorkflowModelProvider(probe: WorkflowModelProbe()), defaultModel: "mock:test-model")
        defer { Task { await restarted.shutdownChannelPlugins() } }
        await restarted.waitForStartup()
        if status == .answered {
            _ = try await restarted.resolveWorkflowPendingAction(projectID: graph.projectId, actionID: action.id,
                request: .init(decision: .approved, resolvedBy: "owner"))
            let advanced = try await wait(restarted, run: receipt.run) { $0.steps.contains { $0.nodeId == "effect" && $0.status == .succeeded } }
            #expect(!advanced.steps.contains { $0.nodeId == "join" })
        }
        _ = try await restarted.answerAgentPlanInput(agentID: agent, sessionID: session, requestID: request.id,
            payload: .init(status: status, answers: status == .answered ? [.init(questionId: "choice", selectedOptionId: "yes")] : [], userId: "owner"))
        let finished = try await wait(restarted, run: receipt.run) { [.completed, .failed, .blocked, .cancelled].contains($0.run.status) }
        #expect(finished.run.status == (status == .answered ? .completed : .cancelled))
        #expect(finished.steps.first { $0.nodeId == "agent" }?.id == step.id)
        #expect(finished.pendingActions.allSatisfy { $0.resolvedAt != nil })
        #expect(try await restarted.listAgentSessions(agentID: agent).count == 1)
        if status == .answered {
            #expect(finished.steps.first { $0.nodeId == "after" }?.output["stdout"] == .string("approved:Workflow model answer:WF-42"))
        } else {
            #expect(!finished.steps.contains { ["join", "effect", "after"].contains($0.nodeId) })
            #expect(finished.steps.first { $0.nodeId == "approve" }?.status == .skipped)
        }
    }

    @Test
    func failedToolCancelsPendingNativeQuestion() async throws {
        let (service, _, graph, agent) = try await fixture(probe: WorkflowModelProbe(requestsInput: true))
        defer { Task { await service.shutdownChannelPlugins() } }
        var nodes = graph.nodes
        nodes[3].config["command"] = .string("exit 7")
        _ = try await service.updateWorkflowDefinition(projectID: graph.projectId, workflowID: graph.id,
            request: .init(name: graph.name, lanes: graph.lanes, nodes: nodes, edges: graph.edges))
        let receipt = try await service.startWorkflowRun(projectID: graph.projectId, workflowID: graph.id,
            request: .init(startedBy: "owner", input: ["ticket": .string("WF-42")]))
        let paused = try await wait(service, run: receipt.run) {
            $0.pendingActions.contains { $0.resolvedAt == nil } && $0.steps.contains { $0.nodeId == "agent" && $0.status == .waiting }
        }
        let action = try #require(paused.pendingActions.first)
        let session = try #require(paused.steps.first { $0.nodeId == "agent" }?.output["sessionId"]?.asString)
        _ = try await service.resolveWorkflowPendingAction(projectID: graph.projectId, actionID: action.id,
            request: .init(decision: .approved, resolvedBy: "owner"))
        let finished = try await wait(service, run: receipt.run) { $0.run.status == .failed }
        #expect(!finished.steps.contains { $0.nodeId == "join" })
        let events = try await service.getAgentSession(agentID: agent, sessionID: session).events
        #expect(events.contains { $0.inputResponse?.status == .cancelled })
        #expect(events.contains { $0.runControl?.action == .interrupt })
        #expect(await service.listWorkflowPendingActions(projectID: graph.projectId).isEmpty)
    }

    @Test
    func failureInterruptsRunningSiblingBeforeWaitingForItsProvider() async throws {
        let probe = WorkflowModelProbe(gated: true)
        let (service, _, graph, agent) = try await fixture(probe: probe, mode: "ask")
        defer { Task { await probe.release(); await service.shutdownChannelPlugins() } }
        var nodes = graph.nodes
        nodes[3].config["command"] = .string("exit 7")
        _ = try await service.updateWorkflowDefinition(projectID: graph.projectId, workflowID: graph.id,
            request: .init(name: graph.name, lanes: graph.lanes, nodes: nodes, edges: graph.edges))
        let receipt = try await service.startWorkflowRun(projectID: graph.projectId, workflowID: graph.id,
            request: .init(startedBy: "owner", input: ["ticket": .string("WF-42")]))
        var starts = probe.started.makeAsyncIterator()
        _ = await starts.next()
        let paused = try await wait(service, run: receipt.run) { $0.pendingActions.contains { $0.resolvedAt == nil } }
        let action = try #require(paused.pendingActions.first)
        let session = try #require(paused.steps.first { $0.nodeId == "agent" }?.output["sessionId"]?.asString)
        _ = try await service.resolveWorkflowPendingAction(projectID: graph.projectId, actionID: action.id,
            request: .init(decision: .approved, resolvedBy: "owner"))
        var interrupted = false
        for _ in 0..<300 {
            interrupted = try await service.getAgentSession(agentID: agent, sessionID: session).events.contains { $0.runControl?.action == .interrupt }
            if interrupted { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(interrupted)
        await probe.release()
        let finished = try await wait(service, run: receipt.run) { $0.run.status == .failed }
        #expect(!finished.steps.contains { $0.nodeId == "join" })
    }

    private func fixture(probe: WorkflowModelProbe, mode: String = "plan") async throws -> (CoreService, CoreConfig, WorkflowDefinition, String) {
        let config = CoreConfig.test
        let service = CoreService(config: config)
        await service.overrideModelProviderForTests(WorkflowModelProvider(probe: probe), defaultModel: "mock:test-model")
        let project = "parallel-input-\(UUID().uuidString.lowercased())"
        let agent = "worker-\(UUID().uuidString.lowercased())"
        _ = try await service.createProject(.init(id: project, name: "Parallel Input", description: "", channels: []))
        _ = try await service.createAgent(.init(id: agent, displayName: "Worker", role: "Assistant"))
        let graph = try await service.createWorkflowDefinition(projectID: project, request: .init(name: "Parallel Input",
            lanes: [.init(id: "s", title: "System", kind: .system)], nodes: [
                .init(id: "start", type: .trigger, title: "Start", laneId: "s"),
                .init(id: "fork", type: .parallel, title: "Parallel", laneId: "s", config: ["joinNodeId": .string("join")]),
                .init(id: "approve", type: .humanApproval, title: "Approve", laneId: "s", config: ["prompt": .string("Approve {{input.ticket}}")]),
                .init(id: "effect", type: .toolCheck, title: "Effect", laneId: "s", config: ["blockKind": .string("bash"), "command": .string("printf '%s' '{{nodes.approve.output.decision}}'")]),
                .init(id: "agent", type: .agentStep, title: "Agent", laneId: "s", config: ["agentId": .string(agent), "mode": .string(mode), "prompt": .string("Work on {{input.ticket}}")]),
                .init(id: "join", type: .join, title: "Join", laneId: "s"),
                .init(id: "after", type: .toolCheck, title: "After", laneId: "s", config: ["blockKind": .string("bash"), "command": .string("printf '%s' '{{nodes.effect.output.stdout}}:{{nodes.agent.output.text}}:{{input.ticket}}'")]),
                .init(id: "done", type: .end, title: "Done", laneId: "s")
            ], edges: [.init(id: "0", sourceNodeId: "start", targetNodeId: "fork"), .init(id: "1", sourceNodeId: "fork", targetNodeId: "approve"),
                .init(id: "2", sourceNodeId: "fork", targetNodeId: "agent"), .init(id: "3", sourceNodeId: "approve", targetNodeId: "effect"),
                .init(id: "4", sourceNodeId: "effect", targetNodeId: "join"), .init(id: "5", sourceNodeId: "agent", targetNodeId: "join"),
                .init(id: "6", sourceNodeId: "join", targetNodeId: "after"), .init(id: "7", sourceNodeId: "after", targetNodeId: "done")]))
        return (service, config, graph, agent)
    }

    private func wait(_ service: CoreService, run: WorkflowRun, until predicate: (WorkflowRunDetail) -> Bool) async throws -> WorkflowRunDetail {
        var last = try await service.getWorkflowRunDetail(projectID: run.projectId, runID: run.id)
        for _ in 0..<500 {
            if predicate(last) { return last }
            try await Task.sleep(for: .milliseconds(20))
            last = try await service.getWorkflowRunDetail(projectID: run.projectId, runID: run.id)
        }
        #expect(predicate(last), "Last workflow status: \(last.run.status), steps: \(last.steps.map { "\($0.nodeId):\($0.status)" })")
        return last
    }
}
