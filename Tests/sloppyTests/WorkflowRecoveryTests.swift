import Foundation
import Testing
import Protocols
@testable import sloppy

@Suite("Workflow startup recovery", .timeLimit(.minutes(1)))
struct WorkflowRecoveryTests {
    @Test
    func queuedRunExecutesOnceAndCompletedRunNeverReplays() async throws {
        let (service, config, state, marker) = try await fixture()
        try await service.workflowExecutionFiles.save(state)
        await service.shutdownChannelPlugins()
        let restarted = CoreService(config: config)
        let finished = try await wait(restarted, run: state.run, status: .completed)
        #expect(finished.run.id == state.run.id)
        #expect(try String(contentsOf: marker, encoding: .utf8) == "x")
        await restarted.shutdownChannelPlugins()
        let again = CoreService(config: config)
        await again.waitForStartup()
        #expect(try await again.getWorkflowRunDetail(projectID: state.run.projectId, runID: state.run.id).run.status == .completed)
        #expect(try String(contentsOf: marker, encoding: .utf8) == "x")
        await again.shutdownChannelPlugins()
    }

    @Test(arguments: [WorkflowStepStatus.running, .succeeded])
    func interruptedToolIsBlockedOrSkippedAccordingToCheckpoint(status: WorkflowStepStatus) async throws {
        let (service, config, initial, marker) = try await fixture()
        var state = initial
        state.run.status = .running
        state.run.currentNodeIds = ["effect"]
        state.steps = [.init(id: "attempt", runId: state.run.id, nodeId: "effect", status: status, output: ["stdout": .string("done")], startedAt: Date())]
        try Data("x".utf8).write(to: marker)
        try await service.workflowExecutionFiles.save(state)
        await service.shutdownChannelPlugins()
        let restarted = CoreService(config: config)
        let finished = try await wait(restarted, run: state.run, status: status == .running ? .blocked : .completed)
        #expect(try String(contentsOf: marker, encoding: .utf8) == "x")
        #expect(finished.steps.filter { $0.nodeId == "effect" }.count == 1)
        #expect(finished.steps.first?.id == "attempt")
        await restarted.shutdownChannelPlugins()
    }

    @Test(arguments: [PlanInputResponseStatus.answered, .cancelled])
    func userAnswersPersistedQuestionAfterRestart(status: PlanInputResponseStatus) async throws {
        let config = CoreConfig.test
        let service = CoreService(config: config)
        await service.overrideModelProviderForTests(WorkflowModelProvider(probe: WorkflowModelProbe(requestsInput: true)), defaultModel: "mock:test-model")
        let projectID = "question-\(UUID().uuidString.lowercased())"
        let agentID = "worker-\(UUID().uuidString.lowercased())"
        _ = try await service.createProject(.init(id: projectID, name: "Question", description: "", channels: []))
        _ = try await service.createAgent(.init(id: agentID, displayName: "Worker", role: "Assistant"))
        let definition = try await service.createWorkflowDefinition(projectID: projectID, request: WorkflowInputResumeTests().graph(agentID: agentID))
        let paused = try await service.startWorkflowRun(projectID: projectID, workflowID: definition.id,
            request: .init(startedBy: "owner", input: ["ticket": .string("WF-42")]))
        let step = try #require(paused.steps.first { $0.nodeId == "work" })
        let sessionID = try #require(step.output["sessionId"]?.asString)
        let input = try #require(try await service.getAgentSession(agentID: agentID, sessionID: sessionID).events.compactMap(\.inputRequest).last)
        await service.shutdownChannelPlugins()
        let restarted = CoreService(config: config)
        await restarted.overrideModelProviderForTests(WorkflowModelProvider(probe: WorkflowModelProbe()), defaultModel: "mock:test-model")
        await restarted.waitForStartup()
        _ = try await restarted.answerAgentPlanInput(agentID: agentID, sessionID: sessionID, requestID: input.id,
            payload: .init(status: status, answers: status == .answered ? [.init(questionId: "choice", selectedOptionId: "yes")] : [], userId: "owner"))
        let finished = try await wait(restarted, run: paused.run, status: status == .answered ? .completed : .failed)
        #expect(finished.steps.first { $0.nodeId == "work" }?.id == step.id)
        #expect(try await restarted.listAgentSessions(agentID: agentID).count == 1)
        if status == .answered { #expect(finished.steps.first { $0.nodeId == "after" }?.output["stdout"] == .string("Workflow model answer:WF-42")) }
        await restarted.shutdownChannelPlugins()
    }

    @Test
    func runningAgentContinuesSameSessionAfterShutdown() async throws {
        let config = CoreConfig.test
        let service = CoreService(config: config)
        let probe = WorkflowModelProbe(gated: true)
        await service.overrideModelProviderForTests(WorkflowModelProvider(probe: probe), defaultModel: "mock:test-model")
        let projectID = "running-\(UUID().uuidString.lowercased())"
        let agentID = "worker-\(UUID().uuidString.lowercased())"
        _ = try await service.createProject(.init(id: projectID, name: "Running", description: "", channels: []))
        _ = try await service.createAgent(.init(id: agentID, displayName: "Worker", role: "Assistant"))
        var graph = WorkflowInputResumeTests().graph(agentID: agentID)
        graph.nodes[1].config["mode"] = .string("ask")
        graph.nodes.removeAll { $0.id == "after" }
        graph.edges = [graph.edges[0], .init(id: "finish", sourceNodeId: "work", targetNodeId: "done")]
        let definition = try await service.createWorkflowDefinition(projectID: projectID, request: graph)
        let task = Task { try await service.startWorkflowRun(projectID: projectID, workflowID: definition.id, request: .init(startedBy: "owner", input: ["ticket": .string("WF-42")])) }
        defer { task.cancel(); Task { await probe.release() } }
        var starts = probe.started.makeAsyncIterator()
        _ = await starts.next()
        let run = try #require(await service.listWorkflowRuns(projectID: projectID).first)
        let before = try await service.getWorkflowRunDetail(projectID: projectID, runID: run.id)
        let step = try #require(before.steps.first { $0.nodeId == "work" })
        let sessionID = try #require(step.output["sessionId"]?.asString)
        await service.shutdownChannelPlugins()
        task.cancel()
        await probe.release()
        _ = try? await task.value
        var resumedConfig = config
        resumedConfig.disableModelInference = false // local mock:test-model provider; no external credentials
        let restarted = CoreService(config: resumedConfig)
        let finished = try await wait(restarted, run: run, status: .completed)
        #expect(finished.steps.first { $0.nodeId == "work" }?.id == step.id)
        #expect(finished.steps.first { $0.nodeId == "work" }?.output["sessionId"] == .string(sessionID))
        #expect(try await restarted.listAgentSessions(agentID: agentID).count == 1)
        let session = try await restarted.getAgentSession(agentID: agentID, sessionID: sessionID)
        #expect(session.events.filter { $0.message?.role == .user }.count == 2)
        await restarted.shutdownChannelPlugins()
    }

    @Test(arguments: [false, true])
    func unfinishedNativeToolRequiresReconciliation(hasUncertainResult: Bool) async throws {
        let (service, config, initial, _) = try await fixture()
        let agentID = "reconcile-\(UUID().uuidString.lowercased())"
        _ = try await service.createAgent(.init(id: agentID, displayName: "Worker", role: "Assistant"))
        let session = try await service.createAgentSession(agentID: agentID, request: .init(separateChat: true, projectId: initial.run.projectId))
        var events = [AgentSessionEvent(id: "unfinished", agentId: agentID, sessionId: session.id, type: .toolCall,
            toolCall: .init(tool: "runtime.exec", arguments: [:]))]
        if hasUncertainResult {
            events.append(.init(agentId: agentID, sessionId: session.id, type: .toolResult,
                toolResult: .init(tool: "runtime.exec", ok: false, callEventId: "unfinished",
                                  executionOutcome: .init(state: .interrupted, requiresReconciliation: true))))
        }
        _ = try await service.appendAgentSessionEvents(agentID: agentID, sessionID: session.id, request: .init(events: events))
        var state = initial
        state.definition.nodes[1].type = .agentStep
        state.definition.nodes[1].config = ["agentId": .string(agentID), "prompt": .string("Continue work"), "mode": .string("ask")]
        state.run.status = .running
        state.run.currentNodeIds = ["effect"]
        state.steps = [.init(id: "attempt", runId: state.run.id, nodeId: "effect", status: .running,
                            output: ["agentId": .string(agentID), "sessionId": .string(session.id)], startedAt: Date())]
        try await service.workflowExecutionFiles.save(state)
        await service.shutdownChannelPlugins()
        let restarted = CoreService(config: config)
        let blocked = try await wait(restarted, run: state.run, status: .blocked)
        #expect(blocked.steps.last?.error?.contains("persisted result") == true)
        await restarted.shutdownChannelPlugins()
    }

    @Test
    func backgroundStartReturnsBeforeTheAgentFinishes() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let probe = WorkflowModelProbe(gated: true)
        await service.overrideModelProviderForTests(WorkflowModelProvider(probe: probe), defaultModel: "mock:test-model")
        let projectID = "background-\(UUID().uuidString.lowercased())"
        let agentID = "worker-\(UUID().uuidString.lowercased())"
        _ = try await service.createProject(.init(id: projectID, name: "Background", description: "", channels: []))
        _ = try await service.createAgent(.init(id: agentID, displayName: "Worker", role: "Assistant"))
        var graph = WorkflowInputResumeTests().graph(agentID: agentID)
        graph.nodes[1].config["mode"] = .string("ask")
        let definition = try await service.createWorkflowDefinition(projectID: projectID, request: graph)
        defer { Task { await probe.release(); await service.shutdownChannelPlugins() } }
        let queued = try await service.startWorkflowRun(projectID: projectID, workflowID: definition.id,
            request: .init(startedBy: "owner", input: ["ticket": .string("WF-42")], background: true))
        #expect(queued.run.status == .queued)
        var starts = probe.started.makeAsyncIterator()
        _ = await starts.next()
        #expect(try await service.getWorkflowRunDetail(projectID: projectID, runID: queued.run.id).run.status == .running)
        await probe.release()
        _ = try await wait(service, run: queued.run, status: .completed)
    }

    @Test
    func backgroundAnswerResumesThePersistedDecision() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let projectID = "background-input-\(UUID().uuidString.lowercased())"
        _ = try await service.createProject(.init(id: projectID, name: "Input", description: "", channels: []))
        let definition = try await service.createWorkflowDefinition(projectID: projectID, request: WorkflowInputResumeTests().graph())
        let paused = try await service.startWorkflowRun(projectID: projectID, workflowID: definition.id,
            request: .init(startedBy: "owner", input: ["ticket": .string("WF-42")]))
        let action = try #require(paused.pendingActions.first)
        let accepted = try await service.resolveWorkflowPendingAction(projectID: projectID, actionID: action.id,
            request: .init(decision: .approved, comment: "ship", resolvedBy: "owner", background: true))
        #expect(accepted.run.status == .running)
        let finished = try await wait(service, run: paused.run, status: .completed)
        #expect(finished.steps.first { $0.nodeId == "after" }?.output["stdout"] == .string("ship:WF-42"))
        await service.shutdownChannelPlugins()
    }

    private func fixture() async throws -> (CoreService, CoreConfig, WorkflowExecutionState, URL) {
        let config = CoreConfig.test
        let service = CoreService(config: config)
        let projectID = "recovery-\(UUID().uuidString.lowercased())"
        _ = try await service.createProject(.init(id: projectID, name: "Recovery", description: "", channels: []))
        await service.waitForStartup()
        let marker = await service.workspaceRootURL.appendingPathComponent("effects.txt")
        let definition = try await service.createWorkflowDefinition(projectID: projectID, request: .init(name: "Recovery", lanes: [.init(id: "s", title: "S", kind: .system)], nodes: [
            .init(id: "start", type: .trigger, title: "Start", laneId: "s"),
            .init(id: "effect", type: .toolCheck, title: "Effect", laneId: "s", config: ["blockKind": .string("bash"), "command": .string("printf x >> '\(marker.path)'")]),
            .init(id: "done", type: .end, title: "Done", laneId: "s")
        ], edges: [.init(id: "e1", sourceNodeId: "start", targetNodeId: "effect"), .init(id: "e2", sourceNodeId: "effect", targetNodeId: "done")]))
        let run = WorkflowRun(id: "run_\(UUID().uuidString.lowercased())", workflowId: definition.id, workflowVersion: definition.version, projectId: projectID, status: .queued, startedBy: "owner")
        return (service, config, .init(definition: definition, originalInput: ["ticket": .string("WF-42")], run: run), marker)
    }

    private func wait(_ service: CoreService, run: WorkflowRun, status: WorkflowRunStatus) async throws -> WorkflowRunDetail {
        await service.waitForStartup()
        var last = try await service.getWorkflowRunDetail(projectID: run.projectId, runID: run.id)
        for _ in 0..<500 {
            if last.run.status == status { return last }
            try await Task.sleep(for: .milliseconds(20))
            last = try await service.getWorkflowRunDetail(projectID: run.projectId, runID: run.id)
        }
        #expect(last.run.status == status)
        return last
    }
}
