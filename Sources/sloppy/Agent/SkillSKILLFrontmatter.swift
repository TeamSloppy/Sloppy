import Foundation

/// Reads optional `model` from YAML frontmatter of a SKILL.md file (first `---` … `---` block).
enum SkillSKILLFrontmatter {
    static func preferredModel(fromMarkdown markdown: String) -> String? {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else {
            return nil
        }

        let withoutOpening = trimmed.dropFirst(3)
        guard let endRange = withoutOpening.range(of: "\n---", options: .literal) else {
            return nil
        }
        let frontmatter = String(withoutOpening[..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for line in frontmatter.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line).trimmingCharacters(in: .whitespaces)
            guard let colon = s.firstIndex(of: ":") else {
                continue
            }
            let key = String(s[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            guard key == "model" else {
                continue
            }
            var value = String(s[s.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            let resolved = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return resolved.isEmpty ? nil : resolved
        }
        return nil
    }
}
