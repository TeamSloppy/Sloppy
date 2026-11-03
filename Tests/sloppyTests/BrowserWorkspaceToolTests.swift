import Foundation
import Protocols
import Testing
@testable import sloppy

struct BrowserWorkspaceToolTests {
    @Test func rejectsMalformedPollingFieldsAndDropsUnrelatedArguments() throws {
        #expect(throws: (any Error).self) {
            try validatedBrowserWorkspaceInput(["title": .number(1)], required: ["title"], optional: [])
        }
        #expect(throws: (any Error).self) {
            try validatedBrowserWorkspaceInput(["operation": .string("move"), "tabIds": .array([.number(1)])], required: ["operation"], optional: [], arrays: ["tabIds"])
        }
        let input = try validatedBrowserWorkspaceInput(["title": .string("Note"), "text": .string("Body"), "x": .string("poisoned field")], required: ["title"], optional: ["text"])
        #expect(input.asObject?["x"] == nil)
        #expect(input.asObject?["title"] == .string("Note"))
    }

    @Test func discoveryExportsActualRequiredArguments() async throws {
        let payload = await ToolCatalog.listToolsPayload(mcpRegistry: nil)
        for (name, required) in [("browser.tabs", "operation"), ("browser.groups", "operation"),
                                  ("browser.create_note", "title"), ("browser.create_todo", "title")] {
            let entry = try #require(payload.first { $0.asObject?["name"]?.asString == name }?.asObject)
            let schema = try #require(entry["parameters"]?.asObject)
            #expect(schema["type"]?.asString == "object")
            #expect(schema["properties"]?.asObject?[required] != nil)
            #expect(schema["required"]?.asArray?.contains(.string(required)) == true)
        }
        let groups = try #require(payload.first { $0.asObject?["name"]?.asString == "browser.groups" }?.asObject)
        #expect(groups["parameters"]?.asObject?["properties"]?.asObject?["tabIds"]?.asObject?["type"]?.asString == "array")
    }
}
