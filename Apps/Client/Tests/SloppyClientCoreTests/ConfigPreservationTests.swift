import Foundation
import Testing
@testable import SloppyClientCore

@Suite("Configuration preservation")
struct ConfigPreservationTests {
    private func json(_ source: String) throws -> ConfigJSONValue {
        try JSONDecoder().decode(ConfigJSONValue.self, from: Data(source.utf8))
    }
    @Test func preservesNewServerFieldsWhileEditingNestedValue() throws {
        let raw = try json(#"{"browser":{"enabled":false,"futureFlag":"keep"},"futureSection":{"x":1}}"#)
        let old = try json(#"{"browser":{"enabled":false}}"#)
        let new = try json(#"{"browser":{"enabled":true}}"#)
        let expected = try json(#"{"browser":{"enabled":true,"futureFlag":"keep"},"futureSection":{"x":1}}"#)
        #expect(raw.applyingChanges(from: old, to: new) == expected)
    }
    @Test func preservesUnknownArrayMetadataAcrossReorderAndRemoval() throws {
        let raw = try json(#"[{"id":"a","enabled":false,"secret":"keep-a"},{"id":"b","enabled":false,"secret":"keep-b"}]"#)
        let old = try json(#"[{"id":"a","enabled":false},{"id":"b","enabled":false}]"#)
        let new = try json(#"[{"id":"b","enabled":true}]"#)
        let expected = try json(#"[{"id":"b","enabled":true,"secret":"keep-b"}]"#)
        #expect(raw.applyingChanges(from: old, to: new) == expected)
    }
    @Test func decodesNativeConfigurationAndLegacyNodes() throws {
        let config = try json(#"{"listen":{"host":"localhost","port":25101},"auth":{"token":""},"memory":{"backend":"sqlite-local-vectors"},"nodes":["local",{"id":"remote","url":"http://node"}],"browser":{"enabled":true},"mcp":{"servers":[]},"modelRouting":{"fast":"provider/model"}}"#).decoded(SloppyConfig.self)
        #expect(config.nodes.map(\.id) == ["local", "remote"])
        #expect(config.nodes.first?.kind == "local")
        #expect(config.browser.enabled)
        #expect(config.modelRouting["fast"] == "provider/model")
    }
    @Test func sessionMentionsEscapeLabelsAndEncodeImmutableIDs() {
        let mention = ChatSessionReference(agentId: "a&b", sessionId: "one/two").markdown(title: "Same [title]\nnext")
        #expect(mention.hasPrefix("[@Same \\[title\\] next](sloppy://session?"))
        #expect(mention.contains("a%26b"))
        #expect(mention.contains("sessionId=one/two"))
    }
}
