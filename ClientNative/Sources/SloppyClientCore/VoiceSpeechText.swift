import Foundation

/// Pure text preparation for speaking assistant replies. Formatting only; no intent detection.
public enum VoiceSpeechText {
    public static let maxChunkCharacters = 3_000

    /// Removes Markdown markup so it is not read aloud.
    public static func plainText(fromMarkdown markdown: String) -> String {
        var text = markdown
        let rules: [(String, String)] = [
            ("(?s)```.*?```", " "),
            ("!\\[[^\\]]*\\]\\([^)]*\\)", " "),
            ("\\[([^\\]]+)\\]\\([^)]*\\)", "$1"),
            ("`([^`]*)`", "$1"),
            ("(?m)^\\s{0,3}#{1,6}\\s+", ""),
            ("(?m)^\\s*[-*+]\\s+", ""),
            ("(\\*\\*|__|\\*|_|~~)", ""),
            ("(?m)^\\s*\\|?[-:| ]+\\|?\\s*$", " "),
            ("\\s*\\n\\s*\\n\\s*", "\n\n")
        ]
        for (pattern, template) in rules {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Splits text into sentence groups so the first audio can start early while the rest is
    /// synthesized in the background. Short sentences are merged to keep the request count low.
    public static func speechChunks(from text: String, minCharacters: Int = 40, maxCharacters: Int = maxChunkCharacters) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.bySentences, .substringNotRequired]) { _, range, _, _ in
            sentences.append(String(text[range]))
        }

        var chunks: [String] = []
        var current = ""
        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { chunks.append(trimmed) }
            current = ""
        }
        for sentence in sentences {
            for piece in split(sentence, limit: maxCharacters) {
                if current.count + piece.count > maxCharacters { flush() }
                current += piece
                if current.trimmingCharacters(in: .whitespacesAndNewlines).count >= minCharacters { flush() }
            }
        }
        flush()
        return chunks
    }

    private static func split(_ text: String, limit: Int) -> [String] {
        guard text.count > limit else { return [text] }
        var pieces: [String] = []
        var rest = Substring(text)
        while !rest.isEmpty {
            let head = rest.prefix(limit)
            pieces.append(String(head))
            rest = rest.dropFirst(head.count)
        }
        return pieces
    }
}
