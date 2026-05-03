import Foundation
import TauTUI

struct SloppyTUISlashCommand: SlashCommand {
    let name: String
    let description: String?
    var requiresArgument: Bool {
        switch name {
        case "context", "anthropic-callback":
            return true
        default:
            return false
        }
    }

    init(_ name: String, _ description: String?) {
        self.name = name
        self.description = description
    }

    func argumentCompletions(prefix: String) -> [AutocompleteItem] {
        []
    }
}

final class SloppyTUIAutocompleteProvider: AutocompleteProvider {
    private let base: CombinedAutocompleteProvider

    init(basePath: String) {
        self.base = CombinedAutocompleteProvider(basePath: basePath)
    }

    func getSuggestions(lines: [String], cursorLine: Int, cursorCol: Int) -> AutocompleteSuggestion? {
        base.getSuggestions(lines: lines, cursorLine: cursorLine, cursorCol: cursorCol)
    }

    func applyCompletion(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int,
        item: AutocompleteItem,
        prefix: String
    ) -> (lines: [String], cursorLine: Int, cursorCol: Int) {
        guard prefix.hasPrefix("@") else {
            return base.applyCompletion(
                lines: lines,
                cursorLine: cursorLine,
                cursorCol: cursorCol,
                item: item,
                prefix: prefix
            )
        }
        guard lines.indices.contains(cursorLine) else {
            return (lines, cursorLine, cursorCol)
        }

        var mutableLines = lines
        var currentLine = lines[cursorLine]
        let safePrefixCount = min(prefix.count, cursorCol)
        let start = currentLine.index(currentLine.startIndex, offsetBy: cursorCol - safePrefixCount)
        let end = currentLine.index(start, offsetBy: safePrefixCount)
        let replacement = item.value.hasPrefix("@") ? item.value + " " : "@" + item.value + " "
        currentLine.replaceSubrange(start..<end, with: replacement)
        mutableLines[cursorLine] = currentLine
        let newCursor = cursorCol - safePrefixCount + replacement.count
        return (mutableLines, cursorLine, max(0, newCursor))
    }

    func forceFileSuggestions(lines: [String], cursorLine: Int, cursorCol: Int) -> AutocompleteSuggestion? {
        nil
    }

    func shouldTriggerFileCompletion(lines: [String], cursorLine: Int, cursorCol: Int) -> Bool {
        guard lines.indices.contains(cursorLine) else {
            return false
        }
        let currentLine = lines[cursorLine]
        let prefixIndex = currentLine.index(currentLine.startIndex, offsetBy: min(cursorCol, currentLine.count))
        let textBeforeCursor = String(currentLine[..<prefixIndex])
        return textBeforeCursor.trimmingCharacters(in: .whitespaces).hasPrefix("/")
    }
}

