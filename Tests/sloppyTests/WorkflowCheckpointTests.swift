import Foundation
import Testing
import Protocols
@testable import sloppy

@Suite("Workflow checkpoints")
struct WorkflowCheckpointTests {
    @Test
    func approvalUsesPinnedGraphAndRestoresOriginalContextAfterRestart() async throws {
        let config = CoreConfig.test
        let service = CoreService(config: config)
        let projectID = "checkpoint-\(UUID().uuidString.lowercased())"
        _ = try await service.createProject(.init(id: projectID, name: "Checkpoint", description: "", channels: []))
        let definition = try await service.createWorkflowDefinition(projectID: projectID, request: request())
        let paused = try await service.startWorkflowRun(projectID: projectID, workflowID: definition.id,
                                                       request: .init(startedBy: "human", input: ["ticket": .string("WF-42")]))
        #expect(paused.run.status == .waitingForHuman)
        let action = try #require(paused.pendingActions.first)
        let waitingStep = try #require(paused.steps.first { $0.nodeId == "approval" })
        _ = try await service.updateWorkflowDefinition(projectID: projectID, workflowID: definition.id,
            request: .init(name: "Changed", lanes: definition.lanes, nodes: [definition.nodes[0]], edges: []))
        try await service.deleteWorkflowDefinition(projectID: projectID, workflowID: definition.id)
        await service.shutdownChannelPlugins()

        let restarted = CoreService(config: config)
        let resolved = try await restarted.resolveWorkflowPendingAction(projectID: projectID, actionID: action.id,
            request: .init(decision: .approved, comment: "accepted", resolvedBy: "owner"))
        #expect(resolved.run.status == .completed)
        #expect(resolved.run.workflowVersion == 1)
        #expect(resolved.steps.first { $0.nodeId == "after" }?.output["stdout"] == .string("plan:WF-42:accepted"))
        #expect(resolved.steps.filter { $0.nodeId == "before" }.count == 1)
        #expect(resolved.steps.first { $0.nodeId == "approval" }?.id == waitingStep.id)
        let duplicate = try await restarted.resolveWorkflowPendingAction(projectID: projectID, actionID: action.id,
            request: .init(decision: .approved, resolvedBy: "owner"))
        #expect(duplicate.steps.count == resolved.steps.count)
        #expect(duplicate.run.status == .completed)
        await restarted.shutdownChannelPlugins()
    }

    @Test
    func durableWriteFailureStopsBeforeAnyExecution() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not a directory".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let definition = WorkflowDefinition(id: "wf", projectId: "p", name: "Failure", lanes: [.init(id: "s", title: "S", kind: .system)],
            nodes: [.init(id: "start", type: .trigger, title: "Start", laneId: "s"),
                    .init(id: "tool", type: .toolCheck, title: "Tool", laneId: "s")],
            edges: [.init(id: "e", sourceNodeId: "start", targetNodeId: "tool")])
        let run = WorkflowRun(id: "run", workflowId: "wf", workflowVersion: 1, projectId: "p", status: .queued, startedBy: "human")
        let journal = WorkflowExecutionJournal(state: .init(definition: definition, originalInput: [:], run: run),
                                               files: .init(root: root), store: InMemoryPersistenceStore())
        let result = await WorkflowRunner().start(definition: definition,
            context: .init(projectId: "p", startedBy: "human", input: [:], runId: run.id), persistence: await journal.persistence,
            updateTask: { _, _, _ in Issue.record("No external updates after persistence failure") },
            executeTool: { _, _, _ in Issue.record("No tools after persistence failure"); return nil })
        guard case .failed = result else { Issue.record("Write failure must stop execution"); return }
        #expect(await journal.failed)
    }

    @Test
    func approvalLoopsKeepAttemptBudgetAcrossResumes() async throws {
        let service = CoreService(config: .test, persistenceBuilder: InMemoryCorePersistenceBuilder())
        let projectID = "loop-\(UUID().uuidString.lowercased())"
        _ = try await service.createProject(.init(id: projectID, name: "Loop", description: "", channels: []))
        var graph = request()
        graph.nodes = [graph.nodes[0], graph.nodes[2]]
        graph.edges = [.init(id: "start", sourceNodeId: "start", targetNodeId: "approval"),
                       .init(id: "repeat", sourceNodeId: "approval", targetNodeId: "approval", conditionKey: "approved")]
        // File definitions reject self edges, so use a separate typed routing node.
        graph.nodes.append(.init(id: "again", type: .condition, title: "Again", laneId: "s"))
        graph.edges[1].targetNodeId = "again"
        graph.edges.append(.init(id: "back", sourceNodeId: "again", targetNodeId: "approval"))
        let definition = try await service.createWorkflowDefinition(projectID: projectID, request: graph)
        var detail = try await service.startWorkflowRun(projectID: projectID, workflowID: definition.id, request: .init(startedBy: "human", input: [:]))
        for _ in 0..<25 {
            let action = try #require(detail.pendingActions.last { $0.resolvedAt == nil })
            detail = try await service.resolveWorkflowPendingAction(projectID: projectID, actionID: action.id,
                request: .init(decision: .approved, resolvedBy: "owner"))
        }
        #expect(detail.run.status == .failed)
        await service.shutdownChannelPlugins()
    }

    private func request() -> WorkflowDefinitionUpsertRequest {
        .init(name: "Checkpoint", lanes: [.init(id: "s", title: "System", kind: .system)], nodes: [
            .init(id: "start", type: .trigger, title: "Start", laneId: "s"),
            .init(id: "before", type: .toolCheck, title: "Before", laneId: "s", config: ["blockKind": .string("bash"), "command": .string("printf plan")]),
            .init(id: "approval", type: .humanApproval, title: "Approve", laneId: "s"),
            .init(id: "after", type: .toolCheck, title: "After", laneId: "s", config: ["blockKind": .string("bash"), "command": .string("printf '%s' '{{nodes.before.output.stdout}}:{{input.ticket}}:{{nodes.approval.output.comment}}'")]),
            .init(id: "done", type: .end, title: "Done", laneId: "s")
        ], edges: [
            .init(id: "e1", sourceNodeId: "start", targetNodeId: "before"),
            .init(id: "e2", sourceNodeId: "before", targetNodeId: "approval"),
            .init(id: "e3", sourceNodeId: "approval", targetNodeId: "after", conditionKey: "approved"),
            .init(id: "e4", sourceNodeId: "after", targetNodeId: "done")
        ])
    }
}
