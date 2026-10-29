import Foundation
import Testing
import SloppyA2UI

@Test(arguments: ["brief", "comparison", "parameters"])
func a2uiFormExamplesAreValidAndEditable(_ name: String) throws {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    let surface = try A2UITransaction(json: String(contentsOf: url, encoding: .utf8)).applying(
        to: nil, fallbackText: "Answer in text or use /ui")
    try surface.validate()
    var values = surface.initialValues
    #expect(!surface.validationErrors(values).isEmpty)
    if name == "brief" {
        values["/goal"] = .string("Ship")
        values["/platform"] = .string("ios")
    }
    if name == "comparison" { values["/choice"] = .string("fast") }
    if name == "parameters" {
        values["/count"] = .string("12")
        #expect(!surface.validationErrors(values).isEmpty)
        values["/count"] = .string("2")
    }
    #expect(surface.validationErrors(values).isEmpty)
    var draft = A2UIDraft(surface: surface)
    draft.values = values
    let action = draft.submission(for: "submit", surface: surface)
    let duplicate = draft.submission(for: "submit", surface: surface)
    #expect(action == duplicate)
    let accepted = try surface.accepting(action)
    #expect(accepted.submittedActionId == action.actionId && accepted.revision == 2)
    #expect(throws: (any Error).self) { try accepted.accepting(action) }
    #expect(throws: (any Error).self) {
        try surface.accepting(
            .init(
                actionId: UUID().uuidString, revision: 1, componentId: "submit",
                values: values.merging(["/private": .string("bad")]) { _, v in v }))
    }
    var next = surface
    next.revision += 1
    draft.reconcile(next)
    #expect(draft.values[values.keys.sorted().first ?? ""] == values[values.keys.sorted().first ?? ""])
}

@Test func a2uiDraftKeepsEditsAcrossServerDefaultsAndRestore() throws {
    let json =
        #"[{"version":"v0.9.1","createSurface":{"surfaceId":"draft","catalogId":"urn:sloppy:a2ui:catalog:v1"}},{"version":"v0.9.1","updateComponents":{"surfaceId":"draft","components":[{"id":"root","component":"Column","children":["name","go"]},{"id":"name","component":"TextField","label":"Name","binding":"/name"},{"id":"go","component":"Button","label":"Continue","action":"go"}]}}]"#
    var surface = try A2UITransaction(json: json).applying(to: nil, fallbackText: "Name")
    var draft = A2UIDraft(surface: surface)
    draft.values["/name"] = .string("My edit")
    surface.revision = 2
    surface.dataModel = .object(["name": .string("Server default")])
    draft.reconcile(surface)
    #expect(draft.values["/name"] == .string("My edit"))
    let restored = try JSONDecoder().decode(A2UIDraft.self, from: JSONEncoder().encode(draft))
    #expect(restored == draft)
}

@Test func a2uiFormRejectsBindingsThroughScalarModels() throws {
    let url = try #require(Bundle.module.url(forResource: "brief", withExtension: "json", subdirectory: "Fixtures"))
    var surface = try A2UITransaction(json: String(contentsOf: url, encoding: .utf8)).applying(to: nil, fallbackText: "Brief")
    surface.dataModel = .null
    #expect(throws: (any Error).self) { try surface.validate() }
    surface.dataModel = nil
    try surface.validate()
}
