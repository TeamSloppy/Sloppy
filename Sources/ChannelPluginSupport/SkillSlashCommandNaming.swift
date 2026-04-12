import Foundation

/// Maps installed skill ids (e.g. `owner/repo`) to slash tokens safe for Telegram bot menus (`[a-z0-9_]{1,32}`).
public enum SkillSlashCommandNaming: Sendable {
    /// Lowercased token for slash menus and `/token` matching.
    public static func slashToken(fromSkillId skillId: String) -> String {
        let trimmed = skillId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out = ""
        out.reserveCapacity(min(32, trimmed.count))
        for ch in trimmed.unicodeScalars {
            if ch.value < 128, CharacterSet.alphanumerics.contains(ch) {
                out.unicodeScalars.append(ch)
            } else if ch == "/" || ch == "-" || ch == "." || ch == ":" {
                out.append("_")
            }
        }
        while out.contains("__") {
            out = out.replacingOccurrences(of: "__", with: "_")
        }
        var trimmedUnderscores = out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if trimmedUnderscores.count > 32 {
            trimmedUnderscores = String(trimmedUnderscores.prefix(32)).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        }
        if trimmedUnderscores.isEmpty {
            return "skill"
        }
        return trimmedUnderscores
    }
}

/// Extracts the first `/command` segment from a user line (after optional `@botsuffix` on the command).
public enum ChannelSlashLineParsing: Sendable {
    public static func firstCommandTokenLowercased(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else {
            return nil
        }
        let withoutSlash = trimmed.dropFirst()
        let firstSegment = withoutSlash.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        guard !firstSegment.isEmpty else {
            return nil
        }
        let cmdPart: String
        if let at = firstSegment.firstIndex(of: "@") {
            cmdPart = String(firstSegment[..<at])
        } else {
            cmdPart = firstSegment
        }
        let token = cmdPart.lowercased()
        return token.isEmpty ? nil : token
    }
}
