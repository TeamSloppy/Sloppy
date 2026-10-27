import Foundation
import Testing
@testable import SloppyA2UI

private func fixture() -> A2UISurfaceSnapshot {
    .init(surfaceId: "brief", revision: 1, fallbackText: "Task brief", components: [
        .init(id: "root", component: .column, children: ["title"]),
        .init(id: "title", component: .text, text: "Task brief"),
    ])
}

@Test func a2uiSnapshotRoundTripsLiteralComponents() throws {
    let surface = fixture()
    try surface.validate()
    let data = try JSONEncoder().encode(surface)
    let restored = try JSONDecoder().decode(A2UISurfaceSnapshot.self, from: data)
    try restored.validate()
    #expect(restored == surface)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let components = try #require(json["components"] as? [[String: Any]])
    #expect(components.first?["component"] as? String == "Column")
    #expect(components.last?["text"] as? String == "Task brief")
}

@Test(arguments: ["protocol", "catalog", "revision", "id", "fallback", "text-shape", "column-shape"])
func a2uiSnapshotRejectsInvalidContract(_ fault: String) {
    var surface = fixture()
    switch fault {
    case "protocol": surface.protocolVersion = "1.0"
    case "catalog": surface.catalogId = "urn:unknown"
    case "revision": surface.revision = 0
    case "id": surface.surfaceId = "\nbrief"
    case "fallback": surface.fallbackText = " "
    case "text-shape": surface.components[1].children = []
    default: surface.components[0].text = "unexpected"
    }
    #expect(throws: A2UISurfaceSnapshot.ValidationError.self) { try surface.validate() }
}

@Test(arguments: ["missing-root", "duplicate", "dangling", "cycle", "orphan", "shared", "depth"])
func a2uiSnapshotRejectsUnsafeGraphs(_ fault: String) {
    var surface = fixture()
    switch fault {
    case "missing-root": surface.components[0].id = "other"
    case "duplicate": surface.components.append(surface.components[1])
    case "dangling": surface.components[0].children = ["missing"]
    case "cycle": surface.components[0].children = ["root"]
    case "orphan": surface.components[0].children = []
    case "shared": surface.components[0].children = ["title", "title"]
    default:
        surface.components = (0..<17).map { index in
            .init(id: index == 0 ? "root" : "c\(index)", component: .column,
                  children: index == 16 ? [] : ["c\(index + 1)"])
        }
    }
    #expect(throws: A2UISurfaceSnapshot.ValidationError.self) { try surface.validate() }
}

@Test(arguments: ["text", "fallback", "components", "encoded-size"])
func a2uiSnapshotBoundsUntrustedContent(_ fault: String) {
    var surface = fixture()
    switch fault {
    case "text": surface.components[1].text = String(repeating: "я", count: 8_193)
    case "fallback": surface.fallbackText = String(repeating: "a", count: 16_385)
    case "components": surface.components = Array(repeating: surface.components[1], count: 129)
    default:
        surface.components[0].children = (0..<8).map { "t\($0)" }
        surface.components = [surface.components[0]] + (0..<8).map {
            .init(id: "t\($0)", component: .text, text: String(repeating: "x", count: 10_000))
        }
    }
    #expect(throws: A2UISurfaceSnapshot.ValidationError.self) { try surface.validate() }
}
