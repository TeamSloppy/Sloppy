import Foundation

/// Maps installed skill ids (e.g. `owner/repo`) to slash tokens safe for Telegram bot menus (`[a-z0-9_]{1,32}`).
public enum SkillSlashCommandNaming: Sendable {
    /// Lowercased token for slash menus and `/token` matching.
    public static func slashToken(fromSkillId skillId: String) -> String {
        sanitizedToken(skillId)
    }

    /// Resolves per-skill slash tokens. The default token is the sanitized repo name; owner is added only
    /// when needed to avoid a builtin command or another installed skill.
    public static func resolvedSlashTokens(
        forSkillIds skillIds: [String],
        reservedTokens: Set<String> = []
    ) -> [String: String] {
        let normalizedReserved = Set(reservedTokens.map { sanitizedToken($0) })
        let repoTokens = skillIds.map { repoToken(fromSkillId: $0) }
        let repoCounts = Dictionary(repoTokens.map { ($0, 1) }, uniquingKeysWith: +)
        var used = normalizedReserved
        var resolved: [String: String] = [:]

        for skillId in skillIds {
            let repo = repoToken(fromSkillId: skillId)
            let needsOwner = normalizedReserved.contains(repo) || (repoCounts[repo] ?? 0) > 1
            let base = needsOwner ? ownerRepoToken(fromSkillId: skillId) : repo
            let token = uniqueToken(base: base, stableInput: skillId, used: &used)
            resolved[skillId] = token
        }

        return resolved
    }

    private static func repoToken(fromSkillId skillId: String) -> String {
        let parts = skillId.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        return sanitizedToken(parts.last ?? skillId)
    }

    private static func ownerRepoToken(fromSkillId skillId: String) -> String {
        let parts = skillId.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else {
            return sanitizedToken(skillId)
        }
        return sanitizedToken(parts.suffix(2).joined(separator: "_"))
    }

    private static func uniqueToken(base: String, stableInput: String, used: inout Set<String>) -> String {
        var token = base.isEmpty ? "skill" : base
        if token.count > 32 {
            token = String(token.prefix(32)).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        }
        if !used.contains(token) {
            used.insert(token)
            return token
        }

        let suffix = "_" + shortStableHash(stableInput)
        let prefixCount = max(1, 32 - suffix.count)
        var prefixed = String(token.prefix(prefixCount)).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if prefixed.isEmpty {
            prefixed = "skill"
        }
        var candidate = String((prefixed + suffix).prefix(32)).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        var salt = 1
        while used.contains(candidate) {
            let numberedSuffix = "_" + shortStableHash("\(stableInput)#\(salt)")
            let numberedPrefixCount = max(1, 32 - numberedSuffix.count)
            let numberedPrefix = String(token.prefix(numberedPrefixCount)).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            candidate = String(((numberedPrefix.isEmpty ? "skill" : numberedPrefix) + numberedSuffix).prefix(32))
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            salt += 1
        }
        used.insert(candidate)
        return candidate
    }

    private static func sanitizedToken(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out = ""
        out.reserveCapacity(min(32, trimmed.count))
        for ch in trimmed.unicodeScalars {
            if ch.value < 128, CharacterSet.alphanumerics.contains(ch) {
                out.unicodeScalars.append(ch)
            } else if ch == "/" || ch == "-" || ch == "." || ch == ":" || ch == "_" {
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

    private static func shortStableHash(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(String(hash, radix: 36).prefix(6))
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
