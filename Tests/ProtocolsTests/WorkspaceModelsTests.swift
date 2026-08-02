import Foundation
import Testing
@testable import Protocols

@Test
func workspaceModelsRoundTripStructuredCanvasPayload() throws {
    let element = WorkspaceElement(
        id: "table-1",
        kind: .table,
        bounds: WorkspaceRect(x: 120, y: 80, width: 480, height: 260),
        zIndex: 4,
        parentId: "frame-1",
        style: ["background": .string("#111111")],
        data: [
            "columns": .array([.string("Item"), .string("Owner")]),
            "rows": .array([
                .array([.string("Research"), .string("Agent")]),
            ]),
        ],
        revision: 7
    )
    let document = WorkspaceDocument(
        workspaceId: "ws-roundtrip",
        revision: 7,
        elements: [element],
        connections: []
    )
    let encoded = try JSONEncoder().encode(document)
    let decoded = try JSONDecoder().decode(WorkspaceDocument.self, from: encoded)

    #expect(decoded == document)
    #expect(decoded.elements.first?.kind == .table)
    #expect(decoded.elements.first?.data["rows"] != nil)
}

@Test
func agentSessionWorkspaceScopeIsBackwardCompatible() throws {
    let request = AgentSessionCreateRequest(
        title: "Canvas agent",
        projectId: "project-1",
        workspaceId: "ws-1"
    )
    let encoded = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(AgentSessionCreateRequest.self, from: encoded)
    #expect(decoded.workspaceId == "ws-1")

    let legacy = Data(#"{"title":"Legacy","kind":"chat"}"#.utf8)
    let legacyDecoded = try JSONDecoder().decode(AgentSessionCreateRequest.self, from: legacy)
    #expect(legacyDecoded.workspaceId == nil)
}
