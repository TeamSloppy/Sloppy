import Foundation

/// Interpret only Markdown checkbox syntax; code fences are kept literal.
struct BrowserNoteChecklist: Identifiable {
    var line: Int
    var title: String
    var isComplete: Bool
    var marker: Range<String.Index>
    var id: Int { line }

    static func items(in markdown: String) -> [Self] {
        guard let pattern = try? NSRegularExpression(pattern: #"^[ \t]*(?:[-+*]|\d+[.)])[ \t]+\[([ xX])\][ \t]+(.+)$"#) else { return [] }
        var fence: Character?
        var fenceLength = 0
        return markdown.components(separatedBy: "\n").enumerated().compactMap { index, line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let first = trimmed.first, first == "`" || first == "~" {
                let count = trimmed.prefix(while: { $0 == first }).count
                if count >= 3 {
                    if fence == nil { fence = first; fenceLength = count }
                    else if fence == first && count >= fenceLength && trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
                    return nil
                }
            }
            guard fence == nil,
                  let match = pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let marker = Range(match.range(at: 1), in: line), let title = Range(match.range(at: 2), in: line) else { return nil }
            return Self(line: index, title: String(line[title]), isComplete: line[marker] != " ", marker: marker)
        }
    }

    static func toggling(line index: Int, in markdown: String) -> String {
        guard let item = items(in: markdown).first(where: { $0.line == index }) else { return markdown }
        var lines = markdown.components(separatedBy: "\n")
        lines[index].replaceSubrange(item.marker, with: item.isComplete ? " " : "x")
        return lines.joined(separator: "\n")
    }
}
