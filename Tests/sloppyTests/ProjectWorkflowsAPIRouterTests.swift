import Foundation
import Testing
@testable import sloppy
import Protocols

@Test
func projectWorkflowRoutesCreateRunAndResolveHumanAction() async throws {
    let service = CoreService(config: CoreConfig.test, persistenceBuilder: InMemoryCorePersistenceBuilder())
    let router = CoreRouter(service: service)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let projectId = "workflow-router-\(UUID().uuidString)"
    let createProjectBody = try encoder.encode(
        ProjectCreateRequest(id: projectId, name: "Workflow Router", description: "Test", channels: [])
    )
    let projectResponse = await router.handle(method: "POST", path: "/v1/projects", body: createProjectBody)
    #expect(projectResponse.status == 201)

    let workflowBody = try encoder.encode(starterWorkflowRequest())
    let createWorkflow = await router.handle(method: "POST", path: "/v1/projects/\(projectId)/workflows", body: workflowBody)
    #expect(createWorkflow.status == 201)
    let workflow = try decoder.decode(WorkflowDefinition.self, from: createWorkflow.body)
    #expect(workflow.version == 1)

    let listWorkflows = await router.handle(method: "GET", path: "/v1/projects/\(projectId)/workflows", body: nil)
    #expect(listWorkflows.status == 200)
    let workflows = try decoder.decode([WorkflowDefinition].self, from: listWorkflows.body)
    #expect(workflows.map(\.id) == [workflow.id])

    let updateBody = try encoder.encode(WorkflowDefinitionUpsertRequest(
        name: "Dashboard Approval Updated",
        lanes: workflow.lanes,
        nodes: workflow.nodes,
        edges: workflow.edges
    ))
    let updateWorkflow = await router.handle(method: "PUT", path: "/v1/projects/\(projectId)/workflows/\(workflow.id)", body: updateBody)
    #expect(updateWorkflow.status == 200)
    let updated = try decoder.decode(WorkflowDefinition.self, from: updateWorkflow.body)
    #expect(updated.version == 2)

    let runBody = try encoder.encode(WorkflowRunCreateRequest(taskId: nil, startedBy: "human:admin", input: [:]))
    let startRun = await router.handle(method: "POST", path: "/v1/projects/\(projectId)/workflows/\(workflow.id)/runs", body: runBody)
    #expect(startRun.status == 201)
    let runDetail = try decoder.decode(WorkflowRunDetail.self, from: startRun.body)
    #expect(runDetail.run.status == .waitingForHuman)
    let action = try #require(runDetail.pendingActions.first)

    let runsResponse = await router.handle(method: "GET", path: "/v1/projects/\(projectId)/workflow-runs", body: nil)
    #expect(runsResponse.status == 200)
    let runs = try decoder.decode([WorkflowRun].self, from: runsResponse.body)
    #expect(runs.first?.id == runDetail.run.id)

    let detailResponse = await router.handle(method: "GET", path: "/v1/projects/\(projectId)/workflow-runs/\(runDetail.run.id)", body: nil)
    #expect(detailResponse.status == 200)

    let actionsResponse = await router.handle(method: "GET", path: "/v1/projects/\(projectId)/workflow-actions", body: nil)
    #expect(actionsResponse.status == 200)
    let actions = try decoder.decode([WorkflowPendingAction].self, from: actionsResponse.body)
    #expect(actions.map(\.id) == [action.id])

    let resolveBody = try encoder.encode(WorkflowActionResolveRequest(decision: .approved, comment: "Ship it", resolvedBy: "human:admin"))
    let resolve = await router.handle(method: "POST", path: "/v1/projects/\(projectId)/workflow-actions/\(action.id)/resolve", body: resolveBody)
    #expect(resolve.status == 200)
    let resolved = try decoder.decode(WorkflowRunDetail.self, from: resolve.body)
    #expect(resolved.run.status == .completed)
}

private func starterWorkflowRequest() -> WorkflowDefinitionUpsertRequest {
    WorkflowDefinitionUpsertRequest(
        name: "Dashboard Approval",
        lanes: [
            WorkflowLane(id: "system", title: "System", kind: .system),
            WorkflowLane(id: "owner", title: "Owner", kind: .human, actorId: "human:admin")
        ],
        nodes: [
            WorkflowNode(id: "start", type: .trigger, title: "Manual start", laneId: "system", config: ["mode": .string("manual")], positionX: 80, positionY: 80),
            WorkflowNode(id: "approval", type: .humanApproval, title: "Approve", laneId: "owner", config: ["prompt": .string("Approve this workflow run?")], positionX: 360, positionY: 80),
            WorkflowNode(id: "done", type: .end, title: "Done", laneId: "system", config: ["status": .string("completed")], positionX: 640, positionY: 80)
        ],
        edges: [
            WorkflowEdge(id: "e_start_approval", sourceNodeId: "start", targetNodeId: "approval"),
            WorkflowEdge(id: "e_approval_done", sourceNodeId: "approval", targetNodeId: "done", conditionKey: "approved")
        ]
    )
}
