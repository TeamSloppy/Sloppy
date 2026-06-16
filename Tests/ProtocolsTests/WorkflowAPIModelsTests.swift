import Foundation
import Testing
@testable import Protocols

@Test
func workflowDefinitionRoundTrips() throws {
    let now = Date(timeIntervalSince1970: 1_778_000_000)
    let definition = WorkflowDefinition(
        id: "wf_bug_fix",
        projectId: "proj",
        name: "Bug Fix",
        version: 1,
        lanes: [
            WorkflowLane(id: "system", title: "System", kind: .system),
            WorkflowLane(id: "owner", title: "Owner", kind: .human, actorId: "human:admin")
        ],
        nodes: [
            WorkflowNode(id: "start", type: .trigger, title: "Start", laneId: "system", config: ["mode": .string("manual")], positionX: 100, positionY: 80),
            WorkflowNode(id: "approval", type: .humanApproval, title: "Approve", laneId: "owner", config: ["prompt": .string("Approve task?")], positionX: 360, positionY: 80)
        ],
        edges: [
            WorkflowEdge(
                id: "edge_start_approval",
                sourceNodeId: "start",
                targetNodeId: "approval",
                sourceSocket: "right",
                targetSocket: "left"
            )
        ],
        enabled: true,
        createdAt: now,
        updatedAt: now
    )

    let data = try JSONEncoder().encode(definition)
    let decoded = try JSONDecoder().decode(WorkflowDefinition.self, from: data)

    #expect(decoded == definition)
    #expect(decoded.edges.first?.sourceSocket == "right")
    #expect(decoded.edges.first?.targetSocket == "left")
}

@Test
func workflowRunRequestRoundTrips() throws {
    let request = WorkflowRunCreateRequest(taskId: "task-1", startedBy: "human:admin", input: ["source": .string("manual")])
    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(WorkflowRunCreateRequest.self, from: data)

    #expect(decoded == request)
}
