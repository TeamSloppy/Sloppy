import Foundation
import Testing
import Protocols
@testable import sloppy

@Suite("Workflow parallel execution", .timeLimit(.minutes(1)))
struct WorkflowParallelTests {
    @Test
    func branchesReallyOverlapAndJoinReceivesBothOutputs() async throws {
        let (service, _, definition, root) = try await fixture(gated: true)
        let result = try await service.startWorkflowRun(projectID: definition.projectId, workflowID: definition.id, request: .init(startedBy: "owner", background: false))
        #expect(result.run.status == .completed)
        #expect(result.steps.first { $0.nodeId == "after" }?.output["stdout"] == .string("A:B"))
        #expect(result.steps.filter { $0.nodeId == "fork" }.count == 1)
        #expect(result.steps.filter { $0.nodeId == "join" }.count == 1)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("a").path))
        await service.shutdownChannelPlugins()
    }

    @Test(arguments: [WorkflowStepStatus.running, .succeeded])
    func restartSkipsCompletedBranchesAndBlocksUncertainOperations(status: WorkflowStepStatus) async throws {
        let (service, config, definition, root) = try await fixture()
        let finished = try await service.startWorkflowRun(projectID: definition.projectId, workflowID: definition.id, request: .init(startedBy: "owner", background: false))
        #expect(finished.run.status == .completed)
        var state = try #require(try await service.workflowExecutionFiles.load(finished.run.id))
        state.run.status = .running
        state.run.finishedAt = nil
        state.run.currentNodeIds = ["b"]
        state.steps.removeAll { !["start", "fork", "a", "b"].contains($0.nodeId) }
        let parentIndex = try #require(state.steps.firstIndex { $0.nodeId == "fork" })
        state.steps[parentIndex].status = .running
        state.steps[parentIndex].finishedAt = nil
        var branches: [WorkflowParallelBranch] = []
        for id in ["a", "b"] {
            var step = try #require(state.steps.first { $0.nodeId == id })
            step.runId = "branch-\(id)"
            if id == "b" { step.status = status }
            let run = WorkflowRun(id: step.runId, workflowId: definition.id, workflowVersion: definition.version,
                projectId: definition.projectId, status: id == "a" ? .completed : .running,
                currentNodeIds: id == "a" ? [] : [id], startedBy: "owner")
            branches.append(.init(id: id, run: run, steps: [step]))
        }
        state.parallel = .init(nodeID: "fork", stepID: state.steps[parentIndex].id, branches: branches, visitCounts: ["start": 1, "fork": 1])
        try await service.workflowExecutionFiles.save(state)
        await service.shutdownChannelPlugins()
        let restarted = CoreService(config: config)
        await restarted.waitForStartup()
        var result = try await restarted.getWorkflowRunDetail(projectID: definition.projectId, runID: state.run.id)
        for _ in 0..<500 {
            if [.completed, .blocked, .failed].contains(result.run.status) { break }
            try await Task.sleep(for: .milliseconds(20))
            result = try await restarted.getWorkflowRunDetail(projectID: definition.projectId, runID: state.run.id)
        }
        #expect(result.run.status == (status == .running ? .blocked : .completed))
        #expect(try String(contentsOf: root.appendingPathComponent("a"), encoding: .utf8) == "x")
        #expect(try String(contentsOf: root.appendingPathComponent("b"), encoding: .utf8) == "x")
        #expect(result.steps.filter { $0.nodeId == "fork" }.count == 1)
        await restarted.shutdownChannelPlugins()
    }

    @Test
    func failedBranchPreventsJoinAndDownstreamExecution() async throws {
        let (service, _, definition, _) = try await fixture()
        var nodes = definition.nodes
        nodes[3].config["command"] = .string("exit 7")
        _ = try await service.updateWorkflowDefinition(projectID: definition.projectId, workflowID: definition.id,
            request: .init(name: definition.name, lanes: definition.lanes, nodes: nodes, edges: definition.edges))
        let result = try await service.startWorkflowRun(projectID: definition.projectId, workflowID: definition.id, request: .init(startedBy: "owner", background: false))
        #expect(result.run.status == .failed)
        #expect(!result.steps.contains { $0.nodeId == "join" || $0.nodeId == "after" })
        #expect(result.steps.first { $0.nodeId == "fork" }?.output["branches"]?.asObject?["b"]?.asObject?["status"] == .string("failed"))
        await service.shutdownChannelPlugins()
    }

    @Test
    func topologyRejectsOverlapsAndForeignJoins() {
        let nodes: [WorkflowNode] = [.init(id: "start", type: .trigger, title: "Start", laneId: "s"),
            .init(id: "fork", type: .parallel, title: "Fork", laneId: "s", config: ["joinNodeId": .string("join")]),
            .init(id: "a", type: .toolCheck, title: "A", laneId: "s"), .init(id: "b", type: .toolCheck, title: "B", laneId: "s"),
            .init(id: "join", type: .join, title: "Join", laneId: "s")]
        let edges: [WorkflowEdge] = [.init(id: "0", sourceNodeId: "start", targetNodeId: "fork"),
            .init(id: "1", sourceNodeId: "fork", targetNodeId: "a"), .init(id: "2", sourceNodeId: "fork", targetNodeId: "b"),
            .init(id: "3", sourceNodeId: "a", targetNodeId: "b"), .init(id: "4", sourceNodeId: "b", targetNodeId: "join")]
        let definition = WorkflowDefinition(id: "g", projectId: "p", name: "Parallel", lanes: [.init(id: "s", title: "System", kind: .system)], nodes: nodes, edges: edges)
        #expect(WorkflowRunner().validate(definition: definition).contains { $0.nodeId == "fork" && $0.severity == "error" })
    }

    private func fixture(gated: Bool = false) async throws -> (CoreService, CoreConfig, WorkflowDefinition, URL) {
        let config = CoreConfig.test
        let service = CoreService(config: config)
        let id = "parallel-\(UUID().uuidString.lowercased())"
        _ = try await service.createProject(.init(id: id, name: "Parallel", description: "", channels: []))
        let root = await service.workspaceRootURL
        func command(_ id: String, other: String) -> JSONValue {
            let wait = gated ? "touch '\(root.appendingPathComponent(id).path)'; for n in $(seq 1 100); do test -f '\(root.appendingPathComponent(other).path)' && break; sleep 0.02; done; test -f '\(root.appendingPathComponent(other).path)' || exit 9; " : "printf x >> '\(root.appendingPathComponent(id).path)'; "
            return .string(wait + "printf %s \(id.uppercased())")
        }
        let definition = try await service.createWorkflowDefinition(projectID: id, request: .init(name: "Parallel", lanes: [.init(id: "s", title: "System", kind: .system)], nodes: [
            .init(id: "start", type: .trigger, title: "Start", laneId: "s"),
            .init(id: "fork", type: .parallel, title: "Fork", laneId: "s", config: ["joinNodeId": .string("join")]),
            .init(id: "a", type: .toolCheck, title: "A", laneId: "s", config: ["blockKind": .string("bash"), "command": command("a", other: "b")]),
            .init(id: "b", type: .toolCheck, title: "B", laneId: "s", config: ["blockKind": .string("bash"), "command": command("b", other: "a")]),
            .init(id: "join", type: .join, title: "Join", laneId: "s"),
            .init(id: "after", type: .toolCheck, title: "After", laneId: "s", config: ["blockKind": .string("bash"), "command": .string("printf %s '{{nodes.a.output.stdout}}:{{nodes.b.output.stdout}}'")]),
            .init(id: "done", type: .end, title: "Done", laneId: "s")
        ], edges: [.init(id: "0", sourceNodeId: "start", targetNodeId: "fork"), .init(id: "1", sourceNodeId: "fork", targetNodeId: "a"),
                   .init(id: "2", sourceNodeId: "fork", targetNodeId: "b"), .init(id: "3", sourceNodeId: "a", targetNodeId: "join"),
                   .init(id: "4", sourceNodeId: "b", targetNodeId: "join"), .init(id: "5", sourceNodeId: "join", targetNodeId: "after"),
                   .init(id: "6", sourceNodeId: "after", targetNodeId: "done")]))
        return (service, config, definition, root)
    }
}
