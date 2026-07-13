import Foundation
import SloppyClientCore

enum ChatComposerSuggestionKind: Equatable, Sendable {
    case command
    case skill
    case file
    case task
}

struct ChatComposerSuggestion: Identifiable, Equatable, Sendable {
    var id: String
    var kind: ChatComposerSuggestionKind
    var title: String
    var subtitle: String
    var insertion: String
}

struct ChatComposerQuery: Equatable, Sendable {
    var trigger: Character
    var term: String
    var range: Range<String.Index>

    static func parse(_ text: String) -> ChatComposerQuery? {
        let tokenStart = text.lastIndex(where: { $0.isWhitespace })
            .map { text.index(after: $0) } ?? text.startIndex
        guard tokenStart < text.endIndex else { return nil }
        let trigger = text[tokenStart]
        guard trigger == "/" || trigger == "@" || trigger == "#" else { return nil }
        let termStart = text.index(after: tokenStart)
        let term = String(text[termStart...])
        guard !term.contains(where: { $0.isWhitespace }) else { return nil }
        return ChatComposerQuery(trigger: trigger, term: term, range: tokenStart..<text.endIndex)
    }

    func applying(_ suggestion: ChatComposerSuggestion, to text: String) -> String {
        var result = text
        result.replaceSubrange(range, with: suggestion.insertion + " ")
        return result
    }
}
