import Foundation

enum TaskMarkdown {
    /// Translate Tracker presentation markup, preserving literal fenced code.
    static func normalized(_ source: String) -> String {
        var fence: Character?
        var fenceLength = 0
        return source.components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let first = trimmed.first, first == "`" || first == "~" {
                let count = trimmed.prefix(while: { $0 == first }).count
                if count >= 3 {
                    if fence == nil { fence = first; fenceLength = count }
                    else if fence == first && count >= fenceLength { fence = nil }
                    return line
                }
            }
            guard fence == nil else { return line }
            if trimmed == "{% endcut %}" { return "" }
            if trimmed.hasPrefix("{% cut \""), trimmed.hasSuffix("\" %}") {
                return "### " + trimmed.dropFirst(8).dropLast(4)
            }
            // Avoid transforming inline code samples as well.
            return normalizeInline(line)
        }.joined(separator: "\n")
    }

    private static func normalizeInline(_ line: String) -> String {
        var result = ""
        var cursor = line.startIndex
        while let tick = line[cursor...].firstIndex(of: "`") {
            result += normalizePlain(String(line[cursor..<tick]))
            var end = tick
            while end < line.endIndex && line[end] == "`" { end = line.index(after: end) }
            let delimiter = String(line[tick..<end])
            guard let closing = line.range(of: delimiter, range: end..<line.endIndex) else {
                return result + normalizePlain(String(line[tick...]))
            }
            result += line[tick..<closing.upperBound]
            cursor = closing.upperBound
        }
        return result + normalizePlain(String(line[cursor...]))
    }

    private static func normalizePlain(_ text: String) -> String {
        text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: ###"##""(.*?)""##"###, with: "`$1`", options: .regularExpression)
            .replacingOccurrences(of: #"!!\((?:blue|red|green|orange|gray|grey|yellow)\)(.*?)!!"#,
                                  with: "**$1**", options: .regularExpression)
            .replacingOccurrences(of: #"\{(?:red|green|blue|orange|gray|grey|yellow)\}\(([^)\n]*)\)"#,
                                  with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\(\((https?://[^\s)]+)\s+([^)]+)\)\)"#,
                                  with: "[$2]($1)", options: .regularExpression)
    }
}
