import Foundation
import Testing
@testable import SloppyA2UI

private func envelope(_ operation: String, _ extra: [String: Any] = [:], surface: String = "demo") -> [String: Any] {
    ["version": "v0.9.1", operation: extra.merging(["surfaceId": surface]) { _, new in new }]
}
private func creation() -> [[String: Any]] {
    [
        envelope("createSurface", ["catalogId": A2UISurfaceSnapshot.supportedCatalogID]),
        envelope("updateComponents", ["components": [["id": "root", "component": "Text", "text": "Initial"]]]),
    ]
}
private func transaction(_ frames: [[String: Any]]) throws -> A2UITransaction {
    try .init(json: String(decoding: JSONSerialization.data(withJSONObject: frames), as: UTF8.self))
}

@Test func a2uiRootNullSurvivesSnapshotRestoration() throws {
    let surface = try transaction(creation() + [envelope("updateDataModel", ["value": NSNull()])])
        .applying(to: nil, fallbackText: "Null model")
    let restored = try JSONDecoder().decode(A2UISurfaceSnapshot.self, from: JSONEncoder().encode(surface))
    #expect(restored.dataModel == .some(.null))
    #expect(restored == surface)
    #expect(throws: A2UITransaction.Failure.self) {
        try transaction([envelope("updateDataModel", ["path": "/field", "value": 1])])
            .applying(to: restored, fallbackText: "Invalid traversal")
    }
}

@Test func a2uiTransactionPreservesTypedDataAndDeletionHistory() throws {
    let original = try transaction(creation()).applying(to: nil, fallbackText: "Initial")
    let unchanged = try transaction([envelope("updateDataModel", ["path": "/missing/field"])])
        .applying(to: original, fallbackText: "Unchanged")
    #expect(unchanged.dataModel == original.dataModel)
    let updates = [
        envelope("updateDataModel", ["path": "/a~1b/~0key", "value": true]),
        envelope("updateDataModel", ["path": "/rows", "value": ["first", 2]]),
        envelope("updateDataModel", ["path": "/rows/1", "value": NSNull()]),
        envelope("updateComponents", ["components": [["id": "root", "component": "Text", "text": "Updated"]]]),
    ]
    let updated = try transaction(updates).applying(to: original, fallbackText: "Updated")
    #expect(updated.revision == 2)
    #expect(updated.dataModel == .object(["a/b": .object(["~key": .bool(true)]), "rows": .array([.string("first"), .null])]))
    #expect(original.components.first?.text == "Initial")
    let removed = try transaction([envelope("updateDataModel", ["path": "/a~1b/~0key"])]).applying(to: updated, fallbackText: "Removed")
    #expect(removed.dataModel == .object(["a/b": .object([:]), "rows": .array([.string("first"), .null])]))
    let deleted = try transaction([envelope("deleteSurface")]).applying(to: removed, fallbackText: "Closed")
    #expect(deleted.isDeleted == true && deleted.components.isEmpty && deleted.dataModel == nil)
    let recreated = try transaction(creation()).applying(to: deleted, fallbackText: "Reopened")
    #expect(recreated.revision == 5 && recreated.isDeleted == nil)
    #expect(try JSONDecoder().decode(A2UISurfaceSnapshot.self, from: JSONEncoder().encode(recreated)) == recreated)
}

@Test(arguments: [
    "json", "version", "mixed", "unknown", "extra", "duplicate", "missing-root", "before-create", "escape", "scalar", "size", "count",
])
func a2uiTransactionRejectsInvalidBatches(_ fault: String) throws {
    var frames = creation()
    switch fault {
    case "json": #expect(throws: A2UITransaction.Failure.self) { try A2UITransaction(json: "[") }; return
    case "version": frames[0]["version"] = "v1.0"
    case "mixed": frames.append(envelope("deleteSurface", surface: "other"))
    case "unknown": frames.append(envelope("executeCode"))
    case "extra": frames[0]["createSurface"] = ["surfaceId": "demo", "catalogId": A2UISurfaceSnapshot.supportedCatalogID, "theme": [:]]
    case "duplicate":
        frames[1] = envelope(
            "updateComponents", ["components": Array(repeating: ["id": "root", "component": "Text", "text": "x"], count: 2)])
    case "missing-root": frames.removeLast()
    case "before-create": frames.removeFirst()
    case "escape": frames.append(envelope("updateDataModel", ["path": "/bad~2", "value": 1]))
    case "scalar": frames += [envelope("updateDataModel", ["value": 1]), envelope("updateDataModel", ["path": "/key", "value": 2])]
    case "size": frames.append(envelope("updateDataModel", ["value": String(repeating: "x", count: 65_537)]))
    default: frames += Array(repeating: envelope("updateDataModel", ["value": [:]]), count: 32)
    }
    #expect(throws: (any Error).self) { try transaction(frames).applying(to: nil, fallbackText: "Fallback") }
}
