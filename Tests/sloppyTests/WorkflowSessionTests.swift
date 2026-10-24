import Foundation
import Testing
import Protocols
@testable import sloppy

@Suite("Workflow session policy", .timeLimit(.minutes(1)))
struct WorkflowSessionTests {
    @Test
    func sharedStepsProduceSeparateAnswersAndRunsRemainIsolated() async throws {
        let (service, _, projectID, agentID) = try await fixture(answers: ["first", "second", "third", "fourth"])
        let definition = try await service.createWorkflowDefinition(projectID: projectID, request: graph(agentID: agentID))
        let first = try await service.startWorkflowRun(projectID: projectID, workflowID: definition.id, request: .init(startedBy: "owner"))
        let second = try await service.startWorkflowRun(projectID: projectID, workflowID: definition.id, request: .init(startedBy: "owner"))
        #expect(first.run.status == .completed && second.run.status == .completed)
        let firstWork = try #require(first.steps.first { $0.nodeId == "work" })
        let firstReview = try #require(first.steps.first { $0.nodeId == "review" })
        let secondWork = try #require(second.steps.first { $0.nodeId == "work" })
        #expect(firstWork.output["sessionId"] == firstReview.output["sessionId"])
        #expect(firstWork.output["sessionId"] != secondWork.output["sessionId"])
        #expect(firstWork.output["text"] == .string("first"))
        #expect(firstReview.output["text"] == .string("second"))
        #expect(second.steps.first { $0.nodeId == "review" }?.output["text"] == .string("fourth"))
        #expect(firstReview.output["sessionAfterEventId"]?.asString != nil)
        #expect(try await service.listAgentSessions(agentID: agentID).count == 2)
        let session = try await service.getAgentSession(agentID: agentID, sessionID: firstWork.output["sessionId"]?.asString ?? "")
        #expect(session.events.filter { $0.message?.role == .user }.count == 2)
        #expect(session.events.compactMap(\.message).last { $0.role == .user }?.segments.contains { $0.text?.contains("Review first") == true } == true)
        await #expect(throws: WorkflowGraphContracts.Violation.self) {
            _ = try await service.selectWorkflowAgentSession(node: definition.nodes[2], context: .init(projectId: "other", startedBy: "owner", input: [:]),
                input: ["nodes": .object(["work": .object(["output": .object(firstWork.output)])])], agentID: agentID)
        }
        await service.shutdownChannelPlugins()
    }

    @Test
    func sharedJSONStepWaitsForItsOwnInputAndUsesOnlyItsOwnAnswer() async throws {
        let (service, _, projectID, agentID) = try await fixture(answers: ["first", #"{"verdict":"approved"}"#], requestsInput: true, inputAfter: 1)
        var request = graph(agentID: agentID)
        request.nodes[2].config["mode"] = .string("plan")
        request.nodes[2].config["outputFormat"] = .string("json")
        request.nodes[2].config["outputSchema"] = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"type":"object","required":["result"],"properties":{"result":{"type":"object","required":["verdict"]}}}"#.utf8))
        let definition = try await service.createWorkflowDefinition(projectID: projectID, request: request)
        let paused = try await service.startWorkflowRun(projectID: projectID, workflowID: definition.id, request: .init(startedBy: "owner"))
        #expect(paused.run.status == .waitingForAgent)
        let review = try #require(paused.steps.first { $0.nodeId == "review" })
        let sessionID = try #require(review.output["sessionId"]?.asString)
        let input = try #require(try await service.getAgentSession(agentID: agentID, sessionID: sessionID).events.compactMap(\.inputRequest).last)
        _ = try await service.answerAgentPlanInput(agentID: agentID, sessionID: sessionID, requestID: input.id,
            payload: .init(status: .answered, answers: [.init(questionId: "choice", selectedOptionId: "yes")], userId: "owner"))
        let finished = try await wait(service, run: paused.run)
        #expect(finished.run.status == .completed)
        #expect(finished.steps.first { $0.nodeId == "work" }?.output["text"] == .string("first"))
        #expect(finished.steps.first { $0.id == review.id }?.output["result"]?.asObject?["verdict"] == .string("approved"))
        #expect(try await service.listAgentSessions(agentID: agentID).count == 1)
        await service.shutdownChannelPlugins()
    }

    @Test
    func restartBetweenSharedBindingAndPostingDoesNotReuseThePreviousAnswer() async throws {
        let (service, config, projectID, agentID) = try await fixture(answers: ["first"], disk: true)
        let request = graph(agentID: agentID)
        let definition = try await service.createWorkflowDefinition(projectID: projectID, request: request)
        let original: [String: JSONValue] = ["ticket": .string("WF-42")]
        let first = await service.executeWorkflowAgentNode(node: definition.nodes[1], context: .init(projectId: projectID, startedBy: "owner", input: original),
            input: ["input": .object(original)])
        #expect(first.ok)
        let output = try #require(first.data?.asObject)
        let sessionID = try #require(output["sessionId"]?.asString)
        let session = try await service.getAgentSession(agentID: agentID, sessionID: sessionID)
        let cursor = try #require(session.events.last?.id)
        let run = WorkflowRun(id: "run_\(UUID().uuidString.lowercased())", workflowId: definition.id, workflowVersion: definition.version,
            projectId: projectID, status: .running, currentNodeIds: ["review"], startedBy: "owner")
        let scoped: [String: JSONValue] = ["input": .object(original), "nodes": .object(["work": .object(["output": .object(output)])])]
        let steps: [WorkflowRunStep] = [
            .init(id: "first", runId: run.id, nodeId: "work", status: .succeeded, output: output, startedAt: Date()),
            .init(id: "review", runId: run.id, nodeId: "review", status: .running, input: scoped,
                  output: ["agentId": .string(agentID), "sessionId": .string(sessionID), "sessionAfterEventId": .string(cursor)], startedAt: Date())
        ]
        try await service.workflowExecutionFiles.save(.init(definition: definition, originalInput: original, run: run, steps: steps))
        await service.shutdownChannelPlugins()
        var restartedConfig = config
        restartedConfig.disableModelInference = false // Built-in local mock:test-model, no external credentials.
        let restarted = CoreService(config: restartedConfig)
        let finished = try await wait(restarted, run: run)
        #expect(finished.run.status == .completed)
        let review = try #require(finished.steps.first { $0.id == "review" })
        #expect(review.output["sessionId"] == .string(sessionID))
        #expect(review.output["text"]?.asString?.isEmpty == false)
        #expect(review.output["text"] != .string("first"))
        let history = try await restarted.getAgentSession(agentID: agentID, sessionID: sessionID)
        #expect(history.events.filter { $0.message?.role == .user }.count == 2)
        #expect(history.events.compactMap(\.message).last { $0.role == .user }?.segments.contains { $0.text?.contains("Review first") == true } == true)
        await restarted.shutdownChannelPlugins()
    }

    @Test
    func unexecutedSourceFailsInsteadOfFallingBackToANewSession() async throws {
        let (service, _, projectID, agentID) = try await fixture(answers: ["unexpected"])
        var request = graph(agentID: agentID)
        request.edges[0].conditionKey = "take_work"
        request.edges.append(.init(id: "skip", sourceNodeId: "start", targetNodeId: "review"))
        let definition = try await service.createWorkflowDefinition(projectID: projectID, request: request)
        let failed = try await service.startWorkflowRun(projectID: projectID, workflowID: definition.id, request: .init(startedBy: "owner"))
        #expect(failed.run.status == .failed)
        #expect(try await service.listAgentSessions(agentID: agentID).isEmpty)
        await service.shutdownChannelPlugins()
    }

    @Test(arguments: ["absent", "different_agent", "self", "future", "invalid_mode", "numeric_mode"])
    func rejectsInvalidSessionPolicies(kind: String) {
        var request = graph(agentID: "worker")
        switch kind {
        case "absent": request.nodes[2].config["sessionSourceNodeId"] = .string("missing")
        case "different_agent": request.nodes[2].config["agentId"] = .string("other")
        case "self": request.nodes[2].config["sessionSourceNodeId"] = .string("review")
        case "future": request.nodes[2].config["sessionSourceNodeId"] = .string("done")
        case "invalid_mode": request.nodes[2].config["sessionMode"] = .string("continue_maybe")
        default: request.nodes[2].config["sessionMode"] = .number(1)
        }
        let definition = WorkflowDefinition(id: "g", projectId: "p", name: request.name, lanes: request.lanes, nodes: request.nodes, edges: request.edges)
        #expect(WorkflowRunner().validate(definition: definition).contains { $0.severity == "error" && $0.nodeId == "review" })
    }

    @Test
    func aMissingHistoryBoundaryFailsClosedAndLegacyCheckpointsStillWork() {
        let events = [AgentSessionEvent(id: "old", agentId: "agent", sessionId: "session", type: .runStatus,
            runStatus: .init(stage: .done, label: "Done", executionOutcome: .completed))]
        let response = AgentSessionMessageResponse(summary: .init(id: "session", agentId: "agent", title: "Shared"), appendedEvents: events, routeDecision: nil)
        #expect(CoreService.workflowAgentResult(response: response, output: [:]).ok)
        let absent = CoreService.workflowAgentResult(response: response, output: ["sessionAfterEventId": .string("lost"), "agentOutcome": .string("waiting_input")])
        #expect(!absent.ok && !WorkflowAgentOutcome.isWaiting(absent))
        #expect(absent.error?.code == "workflow_agent_history_missing")
        #expect(!CoreService.workflowAgentResult(response: response, output: ["sessionAfterEventId": .string("old")]).ok)
    }

    private func fixture(answers: [String], requestsInput: Bool = false, inputAfter: Int = 0, disk: Bool = false) async throws -> (CoreService, CoreConfig, String, String) {
        let config = CoreConfig.test
        let service = disk ? CoreService(config: config) : CoreService(config: config, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.overrideModelProviderForTests(WorkflowModelProvider(probe: WorkflowModelProbe(requestsInput: requestsInput, answers: answers, inputAfter: inputAfter)), defaultModel: "mock:test-model")
        let id = UUID().uuidString.lowercased()
        _ = try await service.createProject(.init(id: id, name: "Shared", description: "", channels: []))
        _ = try await service.createAgent(.init(id: id, displayName: "Worker", role: "Assistant"))
        return (service, config, id, id)
    }

    private func graph(agentID: String) -> WorkflowDefinitionUpsertRequest {
        .init(name: "Session policy", lanes: [.init(id: "s", title: "System", kind: .system)], nodes: [
            .init(id: "start", type: .trigger, title: "Start", laneId: "s"),
            .init(id: "work", type: .agentStep, title: "Work", laneId: "s", config: ["agentId": .string(agentID), "prompt": .string("First request"), "mode": .string("ask")]),
            .init(id: "review", type: .agentStep, title: "Review", laneId: "s", config: ["agentId": .string(agentID), "prompt": .string("Review {{nodes.work.output.text}}"), "mode": .string("ask"), "sessionMode": .string("shared"), "sessionSourceNodeId": .string("work")]),
            .init(id: "done", type: .end, title: "Done", laneId: "s")
        ], edges: [.init(id: "a", sourceNodeId: "start", targetNodeId: "work"), .init(id: "b", sourceNodeId: "work", targetNodeId: "review"), .init(id: "c", sourceNodeId: "review", targetNodeId: "done")])
    }

    private func wait(_ service: CoreService, run: WorkflowRun) async throws -> WorkflowRunDetail {
        await service.waitForStartup()
        var last = try await service.getWorkflowRunDetail(projectID: run.projectId, runID: run.id)
        for _ in 0..<500 {
            if last.run.status == .completed || last.run.status == .failed { return last }
            try await Task.sleep(for: .milliseconds(20))
            last = try await service.getWorkflowRunDetail(projectID: run.projectId, runID: run.id)
        }
        return last
    }
}
