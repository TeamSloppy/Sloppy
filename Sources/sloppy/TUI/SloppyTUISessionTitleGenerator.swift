import Foundation

enum SloppyTUISessionTitleGenerator {
    static let fallbackTitle = "New chat"
    static let maxCharacters = 64
    static let maxWords = 9

    static func title(for raw: String, fallback: String = fallbackTitle) -> String {
        let normalized = normalize(raw)
        guard !normalized.isEmpty else { return fallback }

        let candidate = firstMeaningfulTitleCandidate(in: normalized)
        let withoutCommandPrefix = stripLeadingInvocation(from: candidate)
        let cleaned = clean(withoutCommandPrefix)
        guard !cleaned.isEmpty else { return fallback }

        return truncate(cleaned, maxCharacters: maxCharacters, maxWords: maxWords)
    }

    private static func normalize(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func firstMeaningfulTitleCandidate(in text: String) -> String {
        var insideFence = false
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                insideFence.toggle()
                continue
            }
            guard !insideFence else { continue }
            if line.hasPrefix("[Attached ") || line.hasPrefix("[Attachment failed:") {
                continue
            }
            if line.hasPrefix("- "), line.contains(" bytes") {
                continue
            }
            return line
        }
        return text.components(separatedBy: "\n").first ?? text
    }

    private static func stripLeadingInvocation(from text: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = value.first, first == "@" || first == "/" else { return value }
        let parts = value.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return value }
        let tail = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.isEmpty ? value : tail
    }

    private static func clean(_ text: String) -> String {
        var value = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while value.hasPrefix("#") || value.hasPrefix(">") || value.hasPrefix("-") || value.hasPrefix("*") {
            value.removeFirst()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        value = value.trimmingCharacters(in: CharacterSet(charactersIn: " .,:;!?-—–_`'\"“”‘’()[]{}<>"))
        return value
    }

    private static func truncate(_ text: String, maxCharacters: Int, maxWords: Int) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        var candidate = words.prefix(maxWords).joined(separator: " ")
        if candidate.isEmpty { candidate = text }

        if candidate.count <= maxCharacters {
            return candidate
        }

        let end = candidate.index(candidate.startIndex, offsetBy: maxCharacters)
        var truncated = String(candidate[..<end])
        if let lastSpace = truncated.lastIndex(of: " "), truncated.distance(from: truncated.startIndex, to: lastSpace) >= 24 {
            truncated = String(truncated[..<lastSpace])
        }
        return truncated.trimmingCharacters(in: CharacterSet(charactersIn: " .,:;!?-—–_`'\"“”‘’()[]{}<>"))
    }
}
