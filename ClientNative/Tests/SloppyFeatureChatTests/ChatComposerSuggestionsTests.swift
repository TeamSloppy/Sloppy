import Testing
@testable import SloppyFeatureChat

@Suite("Chat composer suggestions")
struct ChatComposerSuggestionsTests {
    @Test("parses supported triggers at the current token")
    func parsesTriggers() {
        #expect(ChatComposerQuery.parse("/")?.trigger == "/")
        #expect(ChatComposerQuery.parse("hello @read")?.term == "read")
        #expect(ChatComposerQuery.parse("check #task")?.trigger == "#")
        #expect(ChatComposerQuery.parse("email@example.com") == nil)
    }

    @Test("selection replaces only the active token")
    func appliesSuggestion() throws {
        let text = "Please inspect @rea"
        let query = try #require(ChatComposerQuery.parse(text))
        let suggestion = ChatComposerSuggestion(
            id: "file:README.md",
            kind: .file,
            title: "README.md",
            subtitle: "Project file",
            insertion: "@README.md"
        )

        #expect(query.applying(suggestion, to: text) == "Please inspect @README.md ")
    }
}
