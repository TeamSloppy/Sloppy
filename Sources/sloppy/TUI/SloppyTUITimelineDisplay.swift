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

    static func toolCallDisplay(
        tool: String,
        arguments: [String: JSONValue]
    ) -> (summary: String?, details: String?) {
        switch tool {
        case "runtime.exec":
            let command = arguments["command"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let argv = arguments["arguments"]?.asArray?.compactMap(\.asString) ?? []
            let fullCommand = ([command] + argv).filter { !$0.isEmpty }.map(shellQuote).joined(separator: " ")
            let cwd = arguments["cwd"]?.asString?.trimmingCharacters(in: .whitespacesAndNewlines)
            var details = fullCommand.isEmpty ? nil : fencedBlock("shell", fullCommand, maxCharacters: 4_000)
            if let cwd, !cwd.isEmpty {
                details = ([details, "cwd: `\(cwd)`"].compactMap { $0 }).joined(separator: "\n\n")
            }
            return (clipInline(singleLineDisplay(fullCommand), maxCharacters: 160), details)
        case "files.read":
            let path = displayPath(arguments["path"]?.asString)
            let options = bracketedOptions([
                ("offset", arguments["offset"]?.asInt),
                ("limit", arguments["maxBytes"]?.asInt),
            ])
            return ("Read \(path)\(options)", nil)
        case "files.grep":
            let query = arguments["query"]?.asString ?? ""
            let path = displayPath(arguments["path"]?.asString, fallback: ".")
            let mode = arguments["regex"]?.asBool == true ? "Grep" : "Search"
            let options = bracketedOptions([
                ("max", arguments["maxMatches"]?.asInt),
            ])
            return ("\(mode) \(quoted(query)) in \(path)\(options)", nil)
        case "files.list":
            let path = displayPath(arguments["path"]?.asString)
            let options = bracketedOptions([
                ("depth", arguments["depth"]?.asInt),
            ])
            return ("List \(path)\(options)", nil)
        case "files.edit":
            let path = displayPath(arguments["path"]?.asString)
            let details = editPreview(search: arguments["search"]?.asString, replace: arguments["replace"]?.asString)
            let suffix = arguments["all"]?.asBool == true ? " [all]" : ""
            return ("Edit \(path)\(suffix)", details)
        case "files.write":
            let path = displayPath(arguments["path"]?.asString)
            let content = arguments["content"]?.asString
            let byteCount = content?.lengthOfBytes(using: .utf8)
            let details = content.map { fencedBlock("text", $0, maxCharacters: 4_000) }
            return ("Write \(path)\(bracketedOptions([("bytes", byteCount)]))", details)
        default:
            let keys = arguments.keys.sorted()
            let details = arguments.isEmpty ? nil : fencedBlock("json", prettyJSON(.object(arguments)), maxCharacters: 4_000)
            return (keys.isEmpty ? nil : "\(tool) [\(keys.joined(separator: ", "))]", details)
        }
    }

    static func toolResultTitle(_ result: AgentToolResultEvent) -> String {
        switch result.tool {
        case "files.read":
            return "Read"
        case "files.grep":
            guard let count = result.data?.asObject?["matchesCount"]?.asInt else {
                return "Grep"
            }
            let suffix = count == 1 ? "1 match" : "\(count) matches"
            return "Grep (\(suffix))"
        case "files.list":
            return "List"
        case "files.edit":
            return "Edit"
        case "files.write":
            return "Write"
        case "runtime.exec":
            return "Run"
        default:
            return result.tool
        }
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

    private static func displayPath(_ raw: String?, fallback: String = "<path>") -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return fallback
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if trimmed == home {
            return "~"
        }
        if trimmed.hasPrefix(home + "/") {
            return "~/" + trimmed.dropFirst(home.count + 1)
        }
        return trimmed
    }

    private static func bracketedOptions(_ options: [(String, Int?)]) -> String {
        let parts = options.compactMap { key, value -> String? in
            guard let value else { return nil }
            return "\(key)=\(value)"
        }
        guard !parts.isEmpty else {
            return ""
        }
        return " [" + parts.joined(separator: ", ") + "]"
    }

    private static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func editPreview(search: String?, replace: String?) -> String? {
        guard let search, let replace else {
            return nil
        }
        let removed = search.split(separator: "\n", omittingEmptySubsequences: false).map { "-\(String($0))" }
        let added = replace.split(separator: "\n", omittingEmptySubsequences: false).map { "+\(String($0))" }
        return fencedBlock("diff", (removed + added).joined(separator: "\n"), maxCharacters: 6_000)
    }

    private static func fencedBlock(_ language: String, _ text: String, maxCharacters: Int) -> String {
        let safeText = clip(text.replacingOccurrences(of: "```", with: "` ` `"), maxCharacters: maxCharacters)
        return "```\(language)\n\(safeText)\n```"
    }

    private static func prettyJSON(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return string
    }

    private static func clip(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else {
            return text
        }
        return String(text.prefix(max(0, maxCharacters - 14))) + "\n... truncated"
    }

    private static func clipInline(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else {
            return text
        }
        return String(text.prefix(max(0, maxCharacters - 14))) + " ... truncated"
    }

    private static func singleLineDisplay(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func shellQuote(_ value: String) -> String {
        guard !value.isEmpty else {
            return "''"
        }
        let safeCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-")
        if value.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
