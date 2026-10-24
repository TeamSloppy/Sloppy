import Foundation
import Testing
import Protocols
@testable import sloppy

@Suite("Workflow input continuation", .timeLimit(.minutes(1)))
struct WorkflowInputResumeTests {
    @Test(arguments: [PlanInputResponseStatus.answered, .cancelled])
    func agentInputContinuesOriginalWorkflowSession(status: PlanInputResponseStatus) async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.overrideModelProviderForTests(WorkflowModelProvider(probe: WorkflowModelProbe(requestsInput: true)), defaultModel: "mock:test-model")
        let projectID = "input-\(UUID().uuidString.lowercased())"
        let agentID = "worker-\(UUID().uuidString.lowercased())"
        _ = try await service.createProject(.init(id: projectID, name: "Input", description: "", channels: []))
        _ = try await service.createAgent(.init(id: agentID, displayName: "Worker", role: "Assistant"))
        let definition = try await service.createWorkflowDefinition(projectID: projectID, request: graph(agentID: agentID))
        let paused = try await service.startWorkflowRun(projectID: projectID, workflowID: definition.id,
            request: .init(startedBy: "human", input: ["ticket": .string("WF-42")]))
        #expect(paused.run.status == .waitingForAgent)
        let step = try #require(paused.steps.first { $0.nodeId == "work" })
        #expect(step.status == .waiting)
        let sessionID = try #require(step.output["sessionId"]?.asString)
        let session = try await service.getAgentSession(agentID: agentID, sessionID: sessionID)
        let input = try #require(session.events.compactMap(\.inputRequest).last)
        _ = try await service.answerAgentPlanInput(agentID: agentID, sessionID: sessionID, requestID: input.id,
            payload: .init(status: status, answers: status == .answered ? [.init(questionId: "choice", selectedOptionId: "yes")] : [], userId: "owner"))
        let finished = try await service.getWorkflowRunDetail(projectID: projectID, runID: paused.run.id)
        #expect(finished.run.status == (status == .answered ? .completed : .failed))
        #expect(try await service.listAgentSessions(agentID: agentID).count == 1)
        #expect(finished.steps.first { $0.nodeId == "work" }?.id == step.id)
        if status == .answered {
            #expect(finished.steps.first { $0.nodeId == "after" }?.output["stdout"] == .string("Workflow model answer:WF-42"))
        } else { #expect(!finished.steps.contains { $0.nodeId == "after" }) }
        await service.shutdownChannelPlugins()
    }

    @Test
    func manualInputRequiresAndPassesTheResponse() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let projectID = "manual-\(UUID().uuidString.lowercased())"
        _ = try await service.createProject(.init(id: projectID, name: "Manual", description: "", channels: []))
        let definition = try await service.createWorkflowDefinition(projectID: projectID, request: graph())
        let paused = try await service.startWorkflowRun(projectID: projectID, workflowID: definition.id,
            request: .init(startedBy: "human", input: ["ticket": .string("WF-42")]))
        let action = try #require(paused.pendingActions.first)
        #expect(action.decisions == [.approved])
        await #expect(throws: CoreService.WorkflowError.self) {
            _ = try await service.resolveWorkflowPendingAction(projectID: projectID, actionID: action.id,
                request: .init(decision: .approved, resolvedBy: "owner"))
        }
        let finished = try await service.resolveWorkflowPendingAction(projectID: projectID, actionID: action.id,
            request: .init(decision: .approved, comment: "ship", resolvedBy: "owner"))
        #expect(finished.run.status == .completed)
        #expect(finished.steps.first { $0.nodeId == "after" }?.output["stdout"] == .string("ship:WF-42"))
        await service.shutdownChannelPlugins()
    }

    private func graph(agentID: String? = nil) -> WorkflowDefinitionUpsertRequest {
        let config: [String: JSONValue] = agentID.map {
            ["blockKind": .string("agent"), "agentId": .string($0), "mode": .string("plan"), "prompt": .string("Ask the owner before continuing.")]
        } ?? ["prompt": .string("Provide a release label")]
        let reference = agentID == nil ? "comment" : "text"
        return .init(name: "Input", lanes: [.init(id: "s", title: "System", kind: .system)], nodes: [
            .init(id: "start", type: .trigger, title: "Start", laneId: "s"),
            .init(id: "work", type: agentID == nil ? .humanInput : .agentStep, title: "Input", laneId: "s", config: config),
            .init(id: "after", type: .toolCheck, title: "After", laneId: "s", config: ["blockKind": .string("bash"), "command": .string("printf '%s' '{{nodes.work.output.\(reference)}}:{{input.ticket}}'")]),
            .init(id: "done", type: .end, title: "Done", laneId: "s")
        ], edges: [.init(id: "e1", sourceNodeId: "start", targetNodeId: "work"),
                   .init(id: "e2", sourceNodeId: "work", targetNodeId: "after"),
                   .init(id: "e3", sourceNodeId: "after", targetNodeId: "done")])
    }
}
