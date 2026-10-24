import Foundation
import Testing
import Protocols
@testable import sloppy

@Suite("Workflow transition contracts")
struct WorkflowTransitionTests {
    @Test
    func rejectsAmbiguousDefinitionsAndUnknownReferences() {
        var graph = definition()
        graph.edges.append(.init(id: "second", sourceNodeId: "work", targetNodeId: "start"))
        #expect(WorkflowRunner().validate(definition: graph).contains { $0.message.contains("default transition") })
        graph = definition()
        graph.edges[1].conditionKey = "yes"
        graph.edges.append(.init(id: "duplicate", sourceNodeId: "work", targetNodeId: "start", conditionKey: "yes"))
        #expect(WorkflowRunner().validate(definition: graph).contains { $0.message.contains("Duplicate transition condition") })
        graph.nodes[1].config["prompt"] = .string("Read {{nodes.absent.output.text}}")
        #expect(WorkflowRunner().validate(definition: graph).contains { $0.nodeId == "work" && $0.message.contains("Unknown node output") })
        graph.nodes[1].config["prompt"] = .string("Read {{input..ticket}}")
        #expect(WorkflowRunner().validate(definition: graph).contains { $0.message.contains("Invalid workflow reference") })
    }

    @Test
    func invalidUpdatePreservesSavedVersion() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let projectID = "validation-\(UUID().uuidString.lowercased())"
        _ = try await service.createProject(.init(id: projectID, name: "Validation", description: "", channels: []))
        let graph = definition()
        let saved = try await service.createWorkflowDefinition(projectID: projectID,
            request: .init(name: graph.name, lanes: graph.lanes, nodes: graph.nodes, edges: graph.edges))
        var invalid = saved
        invalid.edges.append(.init(id: "ambiguous", sourceNodeId: "work", targetNodeId: "start"))
        await #expect(throws: CoreService.WorkflowError.self) {
            _ = try await service.updateWorkflowDefinition(projectID: projectID, workflowID: saved.id,
                request: .init(name: "Invalid", lanes: invalid.lanes, nodes: invalid.nodes, edges: invalid.edges))
        }
        #expect(try await service.getWorkflowDefinition(projectID: projectID, workflowID: saved.id) == saved)
        await service.shutdownChannelPlugins()
    }

    @Test(arguments: ["input.absent", "nodes.skipped.output.text"])
    func missingReferenceStopsBeforeExternalExecution(path: String) async throws {
        var graph = definition()
        graph.nodes[1].config["command"] = .string("echo {{\(path)}}")
        graph.nodes.append(.init(id: "skipped", type: .toolCheck, title: "Skipped", laneId: "s"))
        let capture = TransitionCapture()
        let result = await WorkflowRunner().start(definition: graph, context: .init(projectId: "p", startedBy: "owner", input: [:]),
            persistence: capture.persistence, updateTask: { _, _, _ in }, executeTool: { _, _, _ in
                await capture.executed()
                return .init(tool: "test", ok: true)
            })
        guard case .failed(_, let message) = result else { Issue.record("Missing references must fail"); return }
        #expect(message.contains(path))
        #expect(await capture.executions == 0)
        #expect(await capture.steps.last?.status == .failed)
    }

    @Test
    func typedConditionsPreserveValueTypes() throws {
        for value in [JSONValue.bool(false), .number(0), .string("0"), .null] {
            var graph = definition()
            graph.edges[1].condition = .init(path: "result.items.0", equals: value)
            let output: [String: JSONValue] = ["result": .object(["items": .array([value])])]
            #expect(try WorkflowGraphContracts.next(after: "work", output: output, definition: graph) == "done")
            let different: JSONValue = value == .string("0") ? .number(0) : .string("0")
            #expect(throws: WorkflowGraphContracts.Violation.self) {
                try WorkflowGraphContracts.next(after: "work", output: ["result": .object(["items": .array([different])])], definition: graph)
            }
        }
    }

    @Test
    func missingTypedOutputAndOverlappingLegacyMatchesFail() throws {
        var graph = definition()
        graph.edges[1].condition = .init(path: "result.verdict", equals: .string("yes"))
        graph.edges.append(.init(id: "fallback", sourceNodeId: "work", targetNodeId: "start"))
        #expect(throws: WorkflowGraphContracts.Violation.self) {
            try WorkflowGraphContracts.next(after: "work", output: [:], definition: graph)
        }
        graph.edges[1].condition = nil
        graph.edges[1].conditionKey = "yes"
        graph.edges[2].conditionKey = "no"
        #expect(throws: WorkflowGraphContracts.Violation.self) {
            try WorkflowGraphContracts.next(after: "work", output: ["yes": .bool(true), "decision": .string("no")], definition: graph)
        }
    }

    @Test
    func resumedAmbiguousOutputFailsTheOriginalAttempt() async {
        var graph = definition()
        graph.edges[1].conditionKey = "yes"
        graph.edges.append(.init(id: "other", sourceNodeId: "work", targetNodeId: "start", conditionKey: "no"))
        let run = WorkflowRun(id: "run", workflowId: graph.id, workflowVersion: 1, projectId: "p", status: .waitingForHuman, startedBy: "owner")
        let capture = TransitionCapture()
        let result = await WorkflowRunner().resume(definition: graph, run: run, resolvedNodeID: "work",
            output: ["yes": .bool(true), "no": .bool(true)], persistence: capture.persistence,
            updateTask: { _, _, _ in }, resolvedStepID: "original")
        guard case .failed(let failed, _) = result else { Issue.record("Ambiguous resume must fail"); return }
        #expect(failed.status == .failed)
        #expect(await capture.steps.last?.id == "original")
        #expect(await capture.steps.last?.status == .failed)
    }

    @Test
    func exactTemplateBindingsRetainObjectsArraysAndNull() throws {
        let input: [String: JSONValue] = ["input": .object(["items": .array([.number(7)]), "optional": .null])]
        #expect(resolveWorkflowTemplateValue(.string("{{input.items}}"), input: input) == .array([.number(7)]))
        #expect(resolveWorkflowTemplateValue(.string("{{input.optional}}"), input: input) == .null)
        #expect(resolveWorkflowTemplateString("item={{input.items.0}}", input: input) == "item=7")
        #expect(throws: WorkflowGraphContracts.Violation.self) { try WorkflowGraphContracts.references(in: .string("{{input.items")) }
        let legacy = try JSONDecoder().decode(WorkflowEdge.self, from: Data(#"{"id":"e","sourceNodeId":"a","targetNodeId":"b"}"#.utf8))
        #expect(legacy.condition == nil)
        var typed = legacy
        typed.condition = .init(path: "result.ok", equals: .bool(true))
        #expect(try JSONDecoder().decode(WorkflowEdge.self, from: JSONEncoder().encode(typed)) == typed)
    }

    private func definition() -> WorkflowDefinition {
        .init(id: "graph", projectId: "p", name: "Validation", lanes: [.init(id: "s", title: "System", kind: .system)], nodes: [
            .init(id: "start", type: .trigger, title: "Start", laneId: "s"),
            .init(id: "work", type: .toolCheck, title: "Work", laneId: "s"),
            .init(id: "done", type: .end, title: "Done", laneId: "s")
        ], edges: [.init(id: "begin", sourceNodeId: "start", targetNodeId: "work"), .init(id: "finish", sourceNodeId: "work", targetNodeId: "done")])
    }
}

private actor TransitionCapture {
    var steps: [WorkflowRunStep] = []
    var executions = 0
    func executed() { executions += 1 }
    var persistence: WorkflowRunner.Persistence {
        .init(saveRun: { _ in }, saveStep: { await self.save($0) }, saveAction: { _ in })
    }
    private func save(_ step: WorkflowRunStep) { steps.append(step) }
}
