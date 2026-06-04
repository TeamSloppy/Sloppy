import Foundation
import Testing
@testable import sloppy
import Protocols

@Test
func workflowDefinitionStoreCreatesListsUpdatesAndDeletesDefinitions() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = WorkflowDefinitionFileStore(workspaceRootURL: root)
    let request = WorkflowDefinitionUpsertRequest(
        name: "Bug Fix",
        lanes: [WorkflowLane(id: "system", title: "System", kind: .system)],
        nodes: [WorkflowNode(id: "start", type: .trigger, title: "Start", laneId: "system")],
        edges: [],
        enabled: true
    )

    let created = try store.create(projectID: "proj", request: request)
    #expect(created.projectId == "proj")
    #expect(created.version == 1)
    #expect(created.name == "Bug Fix")
    #expect(try store.list(projectID: "proj").map(\.id) == [created.id])

    let updated = try store.update(
        projectID: "proj",
        workflowID: created.id,
        request: WorkflowDefinitionUpsertRequest(
            name: "Bug Fix Updated",
            lanes: request.lanes,
            nodes: request.nodes,
            edges: request.edges,
            enabled: false
        )
    )
    #expect(updated.version == 2)
    #expect(updated.enabled == false)
    #expect(updated.createdAt == created.createdAt)

    try store.delete(projectID: "proj", workflowID: created.id)
    #expect(try store.list(projectID: "proj").isEmpty)
}

@Test
func workflowDefinitionStoreRejectsEdgesToMissingNodes() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = WorkflowDefinitionFileStore(workspaceRootURL: root)
    let request = WorkflowDefinitionUpsertRequest(
        name: "Broken",
        lanes: [WorkflowLane(id: "system", title: "System", kind: .system)],
        nodes: [WorkflowNode(id: "start", type: .trigger, title: "Start", laneId: "system")],
        edges: [WorkflowEdge(id: "bad", sourceNodeId: "start", targetNodeId: "missing")]
    )

    #expect(throws: WorkflowDefinitionFileStore.StoreError.invalidPayload) {
        _ = try store.create(projectID: "proj", request: request)
    }
}
