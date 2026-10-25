import Foundation
import Testing
import Protocols
@testable import sloppy

@Suite("Workflow output contracts", .timeLimit(.minutes(1)))
struct WorkflowOutputTests {
    private let schema: JSONValue = .object([
        "type": .string("object"), "required": .array([.string("result")]),
        "properties": .object(["result": .object([
            "type": .string("object"), "required": .array([.string("verdict")]),
            "properties": .object(["verdict": .object(["type": .string("string"), "enum": .array([.string("approved"), .string("rejected")])])])
        ])])
    ])

    @Test(arguments: [#"{}"#, #"{"result":null}"#, #"{"result":{"verdict":true}}"#, #"{"result":{"verdict":"maybe"}}"#])
    func rejectsMissingAndInvalidTypedValues(raw: String) throws {
        let node = WorkflowNode(id: "work", type: .agentStep, title: "Work", laneId: "s", config: ["outputSchema": schema])
        let output = try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)).asObject ?? [:]
        #expect(throws: WorkflowGraphContracts.Violation.self) { try WorkflowOutputContract.validate(node: node, output: output) }
    }

    @Test
    func checksNestedArraysClosedObjectsAndNonemptyText() throws {
        let schema = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"type":"object","required":["items"],"additionalProperties":false,"properties":{"items":{"type":"array","items":{"type":"string","minLength":1}}}}"#.utf8))
        let node = WorkflowNode(id: "work", type: .toolCheck, title: "Work", laneId: "s", config: ["outputSchema": schema])
        try WorkflowOutputContract.validate(node: node, output: ["items": .array([.string("ok")])])
        #expect(throws: WorkflowGraphContracts.Violation.self) { try WorkflowOutputContract.validate(node: node, output: ["items": .array([.string("")])]) }
        #expect(throws: WorkflowGraphContracts.Violation.self) { try WorkflowOutputContract.validate(node: node, output: ["items": .array([]), "unexpected": .null]) }
        #expect(throws: WorkflowGraphContracts.Violation.self) { try WorkflowOutputContract.validateDefinition(.object(["type": .string("object"), "$ref": .string("anything")])) }
    }

    @Test(arguments: [#"{"verdict":"approved","agentId":"untrusted"}"#, #"{"verdict":"maybe"}"#, "```json\n{}\n```"])
    func realAgentJSONIsValidatedBeforeTheNextStep(answer: String) async throws {
        let (service, projectID, agentID) = try await fixture(answers: [answer])
        let request = graph(agentID: agentID)
        let definition = try await service.createWorkflowDefinition(projectID: projectID, request: request)
        let result = try await service.startWorkflowRun(projectID: projectID, workflowID: definition.id, request: .init(startedBy: "owner"))
        let valid = answer.contains("untrusted")
        #expect(result.run.status == (valid ? .completed : .failed))
        let step = try #require(result.steps.first { $0.nodeId == "work" })
        #expect(step.output["agentId"] == .string(agentID))
        #expect(step.output["text"] == .string(answer))
        if valid {
            #expect(step.output["result"]?.asObject?["agentId"] == .string("untrusted"))
            #expect(result.steps.first { $0.nodeId == "after" }?.output["stdout"] == .string("approved"))
        } else {
            #expect(step.status == .failed)
            #expect(!result.steps.contains { $0.nodeId == "after" })
        }
        await service.shutdownChannelPlugins()
    }

    @Test
    func JSONContractSurvivesAnAgentInputWait() async throws {
        let (service, projectID, agentID) = try await fixture(answers: [#"{"verdict":"approved"}"#], requestsInput: true)
        var request = graph(agentID: agentID)
        request.nodes[1].config["mode"] = .string("plan")
        let definition = try await service.createWorkflowDefinition(projectID: projectID, request: request)
        let paused = try await service.startWorkflowRun(projectID: projectID, workflowID: definition.id, request: .init(startedBy: "owner"))
        let step = try #require(paused.steps.first { $0.nodeId == "work" })
        let sessionID = try #require(step.output["sessionId"]?.asString)
        let input = try #require(try await service.getAgentSession(agentID: agentID, sessionID: sessionID).events.compactMap(\.inputRequest).last)
        _ = try await service.answerAgentPlanInput(agentID: agentID, sessionID: sessionID, requestID: input.id,
            payload: .init(status: .answered, answers: [.init(questionId: "choice", selectedOptionId: "yes")], userId: "owner"))
        let finished = try await service.getWorkflowRunDetail(projectID: projectID, runID: paused.run.id)
        #expect(finished.run.status == .completed)
        #expect(finished.steps.first { $0.id == step.id }?.output["tool"] == .string("workflow.agent"))
        #expect(finished.steps.first { $0.id == step.id }?.output["result"]?.asObject?["verdict"] == .string("approved"))
        await service.shutdownChannelPlugins()
    }

    @Test
    func schemaFailureAfterHumanAnswerFailsTheOriginalStep() async throws {
        let (service, projectID, _) = try await fixture(answers: [])
        var request = WorkflowInputResumeTests().graph()
        request.nodes[1].config["outputSchema"] = .object(["type": .string("object"), "required": .array([.string("comment")]),
            "properties": .object(["comment": .object(["type": .string("string"), "enum": .array([.string("release")])])])])
        let definition = try await service.createWorkflowDefinition(projectID: projectID, request: request)
        let paused = try await service.startWorkflowRun(projectID: projectID, workflowID: definition.id, request: .init(startedBy: "owner", input: ["ticket": .string("WF-42")]))
        let action = try #require(paused.pendingActions.first)
        let failed = try await service.resolveWorkflowPendingAction(projectID: projectID, actionID: action.id,
            request: .init(decision: .approved, comment: "other", resolvedBy: "owner"))
        #expect(failed.run.status == .failed)
        #expect(failed.steps.first { $0.nodeId == action.nodeId }?.id == paused.steps.first { $0.nodeId == action.nodeId }?.id)
        #expect(!failed.steps.contains { $0.nodeId == "after" })
        await service.shutdownChannelPlugins()
    }

    private func fixture(answers: [String], requestsInput: Bool = false) async throws -> (CoreService, String, String) {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        await service.overrideModelProviderForTests(WorkflowModelProvider(probe: WorkflowModelProbe(requestsInput: requestsInput, answers: answers)), defaultModel: "mock:test-model")
        let id = UUID().uuidString.lowercased()
        _ = try await service.createProject(.init(id: id, name: "Contracts", description: "", channels: []))
        _ = try await service.createAgent(.init(id: id, displayName: "Worker", role: "Assistant"))
        return (service, id, id)
    }

    private func graph(agentID: String) -> WorkflowDefinitionUpsertRequest {
        .init(name: "JSON contract", lanes: [.init(id: "s", title: "System", kind: .system)], nodes: [
            .init(id: "start", type: .trigger, title: "Start", laneId: "s"),
            .init(id: "work", type: .agentStep, title: "Work", laneId: "s", config: ["agentId": .string(agentID), "prompt": .string("Return a verdict."), "mode": .string("ask"), "outputFormat": .string("json"), "outputSchema": schema]),
            .init(id: "after", type: .toolCheck, title: "After", laneId: "s", config: ["blockKind": .string("bash"), "command": .string("printf %s '{{nodes.work.output.result.verdict}}'")]),
            .init(id: "done", type: .end, title: "Done", laneId: "s")
        ], edges: [.init(id: "a", sourceNodeId: "start", targetNodeId: "work"),
                   .init(id: "b", sourceNodeId: "work", targetNodeId: "after", condition: .init(path: "result.verdict", equals: .string("approved"))),
                   .init(id: "c", sourceNodeId: "after", targetNodeId: "done")])
    }
}
