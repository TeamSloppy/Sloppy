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

    @Test("selection moves with arrow directions and stays within bounds")
    func movesSelection() throws {
        let suggestions = [
            ChatComposerSuggestion(id: "one", kind: .command, title: "/one", subtitle: "", insertion: "/one"),
            ChatComposerSuggestion(id: "two", kind: .command, title: "/two", subtitle: "", insertion: "/two"),
            ChatComposerSuggestion(id: "three", kind: .command, title: "/three", subtitle: "", insertion: "/three"),
        ]
        var selection = ChatComposerSuggestionSelection()

        selection.reconcile(with: suggestions)
        #expect(selection.selectedID == "one")
        #expect(selection.move(.next, in: suggestions))
        #expect(selection.selectedID == "two")
        #expect(selection.move(.previous, in: suggestions))
        #expect(selection.selectedID == "one")
        #expect(selection.move(.previous, in: suggestions))
        #expect(selection.selectedID == "one")
        #expect(selection.selectedSuggestion(in: suggestions)?.id == "one")
    }

    @Test("selection resets when suggestions disappear")
    func resetsSelection() {
        let suggestion = ChatComposerSuggestion(
            id: "one",
            kind: .command,
            title: "/one",
            subtitle: "",
            insertion: "/one"
        )
        var selection = ChatComposerSuggestionSelection()

        selection.reconcile(with: [suggestion])
        selection.reconcile(with: [])

        #expect(selection.selectedID == nil)
        #expect(!selection.move(.next, in: []))
    }
}
