import Foundation
import Protocols

enum SloppyTUITimelineDisplay {
    private static let maxUserMessageCharacters = 6_000

    static func messageText(role: AgentMessageRole, text: String) -> String {
        switch role {
        case .user:
            return userMessageText(text)
        default:
            return text
        }
    }

    static func userMessageText(_ text: String) -> String {
        let collapsed = collapseInlineAttachedFiles(text)
        guard collapsed.count > maxUserMessageCharacters else {
            return collapsed
        }
        let limit = max(0, maxUserMessageCharacters - 64)
        return String(collapsed.prefix(limit))
            + "\n\n[Message clipped in TUI; full content was sent to the agent.]"
    }

    private static func collapseInlineAttachedFiles(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var output: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard isAttachedFileHeader(line),
                  lines.indices.contains(index + 1),
                  lines[index + 1].trimmingCharacters(in: .whitespaces) == "```"
            else {
                output.append(line)
                index += 1
                continue
            }

            index += 2
            var hiddenLines = 0
            var hiddenCharacters = 0
            while index < lines.count {
                if lines[index].trimmingCharacters(in: .whitespaces) == "```" {
                    index += 1
                    break
                }
                hiddenLines += 1
                hiddenCharacters += lines[index].count + 1
                index += 1
            }

            let size = formatHiddenSize(lines: hiddenLines, characters: hiddenCharacters)
            output.append("\(line) \(size) hidden in TUI; full content was sent to the agent.")
        }

        return output.joined(separator: "\n")
    }

    private static func isAttachedFileHeader(_ line: String) -> Bool {
        line.hasPrefix("[Attached file: ") && line.hasSuffix("]")
    }

    private static func formatHiddenSize(lines: Int, characters: Int) -> String {
        let lineText = lines == 1 ? "1 line" : "\(lines) lines"
        let characterText = characters == 1 ? "1 char" : "\(characters) chars"
        return "(\(lineText), \(characterText))"
    }
}
