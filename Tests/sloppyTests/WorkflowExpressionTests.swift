import Foundation
import Testing
import Protocols
@testable import sloppy

@Suite("Workflow expressions")
struct WorkflowExpressionTests {
    @Test
    func typedOperatorsPrecedenceAndShortCircuit() throws {
        let input: [String: JSONValue] = ["input": .object(["ready": .bool(true), "count": .number(3)]), "result": .string("ok")]
        #expect(try WorkflowExpression.parse("input.ready && input.count * 2 >= 6 && result == 'ok'").evaluate(input) == .bool(true))
        #expect(try WorkflowExpression.parse("false && missing.path").evaluate(input) == .bool(false))
        #expect(try WorkflowExpression.parse("!exists(missing.path) && 0 !== false").evaluate(input) == .bool(true))
        #expect(throws: (any Error).self) { try WorkflowExpression.parse("missing.path > 0").evaluate(input) }
        #expect(throws: (any Error).self) { try WorkflowExpression.parse("1 / 0 > 0").evaluate(input) }
        #expect(throws: (any Error).self) { try WorkflowExpression.parse("process.exit()") }
    }

    @Test
    func legacyBlockKindCannotBypassLoopBudgetOrJoinOwnership() throws {
        let loop = WorkflowNode(id: "loop", type: .condition, title: "Loop", laneId: "s",
            config: ["block_kind": .string("loop"), "expression": .string("true"), "maxIterations": .number(1)])
        #expect(throws: (any Error).self) { try WorkflowExpression.run(node: loop, input: [:], iteration: 2) }
        let merge = WorkflowNode(id: "merge", type: .condition, title: "Merge", laneId: "s", config: ["block_kind": .string("merge")])
        let graph = WorkflowDefinition(id: "g", projectId: "p", name: "Legacy", lanes: [.init(id: "s", title: "System", kind: .system)], nodes: [
            .init(id: "start", type: .trigger, title: "Start", laneId: "s"), merge, .init(id: "end", type: .end, title: "End", laneId: "s")
        ], edges: [.init(id: "1", sourceNodeId: "start", targetNodeId: "merge"), .init(id: "2", sourceNodeId: "merge", targetNodeId: "end")])
        #expect(WorkflowRunner().validate(definition: graph).contains { $0.nodeId == "merge" && $0.severity == "error" })
    }

    @Test
    func loopBudgetUsesPersistedVisitCount() throws {
        let node = WorkflowNode(id: "repeat", type: .condition, title: "Repeat", laneId: "s",
            config: ["blockKind": .string("loop"), "expression": .string("iteration <= 2"), "maxIterations": .number(2)])
        #expect(try WorkflowExpression.run(node: node, input: [:], iteration: 2)["result"] == .bool(true))
        #expect(try WorkflowExpression.run(node: node, input: [:], iteration: 3)["result"] == .bool(false))
        var infinite = node; infinite.config["expression"] = .string("true")
        #expect(throws: (any Error).self) { try WorkflowExpression.run(node: infinite, input: [:], iteration: 3) }
    }
}
