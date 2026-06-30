import Foundation

enum ChatMarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(language: String?, code: String)
}

enum ChatMarkdownBlockParser {
    static func parse(_ source: String) -> [ChatMarkdownBlock] {
        let lines = source.components(separatedBy: .newlines)
        var index = 0
        var blocks: [ChatMarkdownBlock] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            let joined = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !joined.isEmpty else {
                paragraphLines.removeAll(keepingCapacity: true)
                return
            }
            blocks.append(.paragraph(joined))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let fence = codeFencePrefix(for: trimmed) {
                flushParagraph()
                let languageToken = String(trimmed.dropFirst(fence.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                let language = languageToken.isEmpty ? nil : languageToken
                index += 1
                var codeLines: [String] = []
                while index < lines.count {
                    let codeLine = lines[index]
                    if codeLine.trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                        break
                    }
                    codeLines.append(codeLine)
                    index += 1
                }
                blocks.append(.code(language: language, code: codeLines.joined(separator: "\n")))
            } else if let heading = headingBlock(from: trimmed) {
                flushParagraph()
                blocks.append(heading)
            } else if trimmed.isEmpty {
                flushParagraph()
            } else {
                paragraphLines.append(line)
            }

            index += 1
        }

        flushParagraph()
        return blocks
    }

    private static func headingBlock(from line: String) -> ChatMarkdownBlock? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }
        let level = hashes.count
        guard (1...6).contains(level) else { return nil }
        let title = line.dropFirst(level).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return .heading(level: level, text: title)
    }

    private static func codeFencePrefix(for line: String) -> String? {
        if line.hasPrefix("```") {
            return "```"
        }
        if line.hasPrefix("~~~") {
            return "~~~"
        }
        return nil
    }
}

enum ChatCompactDurationFormatter {
    static func string(for seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }
}
