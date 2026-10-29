import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Workspace documents")
struct WorkspaceDocumentsTests {
    @Test func transactionRetainsBoundsContentAndExpectedRevisions() throws {
        let element = CanvasWorkspaceElement(id: "note", kind: .sticky, bounds: .init(x: 25, y: 50, width: 220, height: 160),
            data: ["text": .string("**Hello**"), "futureMetadata": .object(["keep": .bool(true)])], revision: 7)
        let request = CanvasWorkspaceTransactionRequest(id: "tx", baseRevision: 9, expectedElementRevisions: ["note": 7],
            operations: [.init(kind: .updateElement, element: element)], summary: "Moved note")
        let value = try JSONDecoder().decode(CanvasWorkspaceTransactionRequest.self, from: JSONEncoder().encode(request))
        #expect(value == request)
        #expect(value.operations.first?.element?.data["futureMetadata"] == .object(["keep": .bool(true)]))
    }
    @Test func decodesOlderWorkspaceSummary() throws {
        let value = try JSONDecoder().decode(CanvasWorkspaceSummary.self, from: Data(#"{"id":"notes","title":"Notes","revision":2}"#.utf8))
        #expect(value.title == "Notes")
        #expect(!value.isArchived)
        #expect(value.updatedAt == .distantPast)
    }
    @Test func deleteOperationCarriesTargetWithoutElement() throws {
        let op = CanvasWorkspaceOperation(kind: .deleteElement, targetId: "note")
        let value = try ConfigJSONValue.encoded(op)
        #expect(value["kind"].string == "element.delete")
        #expect(value["targetId"].string == "note")
        #expect(value["element"] == .null)
    }
}
