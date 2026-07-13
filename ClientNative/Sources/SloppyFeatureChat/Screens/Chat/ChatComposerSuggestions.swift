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

enum ChatComposerSuggestionSelectionDirection: Equatable, Sendable {
    case previous
    case next
}

struct ChatComposerSuggestionSelection: Equatable, Sendable {
    private(set) var selectedID: ChatComposerSuggestion.ID?

    mutating func reconcile(with suggestions: [ChatComposerSuggestion]) {
        guard !suggestions.isEmpty else {
            selectedID = nil
            return
        }
        if !suggestions.contains(where: { $0.id == selectedID }) {
            selectedID = suggestions.first?.id
        }
    }

    mutating func move(
        _ direction: ChatComposerSuggestionSelectionDirection,
        in suggestions: [ChatComposerSuggestion]
    ) -> Bool {
        guard !suggestions.isEmpty else {
            selectedID = nil
            return false
        }
        guard let selectedID,
              let selectedIndex = suggestions.firstIndex(where: { $0.id == selectedID }) else {
            self.selectedID = direction == .previous ? suggestions.last?.id : suggestions.first?.id
            return true
        }

        let nextIndex: Int
        switch direction {
        case .previous:
            nextIndex = max(suggestions.startIndex, selectedIndex - 1)
        case .next:
            nextIndex = min(suggestions.index(before: suggestions.endIndex), selectedIndex + 1)
        }
        self.selectedID = suggestions[nextIndex].id
        return true
    }

    func selectedSuggestion(in suggestions: [ChatComposerSuggestion]) -> ChatComposerSuggestion? {
        suggestions.first(where: { $0.id == selectedID })
    }
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
