import Foundation

/// Compares two versions of a memory note by their identifier-like tokens (ports, ids, versions, codes).
///
/// Updating a record may legitimately replace a value (`port 6543` -> `port 7654`), but rewriting a note into a
/// shorter paraphrase silently loses details that cannot be reconstructed. An update that drops identifiers without
/// adding any replacement is that second case. The test looks only at the token shapes, never at the wording.
enum MemoryNoteDiff {
    struct Result: Equatable {
        var dropped: [String]
        var added: [String]

        /// More identifiers disappeared than were introduced: a lossy rewrite rather than a substitution.
        var losesDetail: Bool { added.count < dropped.count }
    }

    static func compare(old: String, new: String) -> Result {
        let before = identifiers(in: old)
        let after = identifiers(in: new)
        return Result(
            dropped: before.subtracting(after).sorted(),
            added: after.subtracting(before).sorted()
        )
    }

    /// Tokens that carry a value: contain a digit, or are an upper-case code of four or more letters.
    static func identifiers(in text: String) -> Set<String> {
        var result = Set<String>()
        for raw in text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && !"-_.:/".contains($0) }) {
            let token = raw.trimmingCharacters(in: CharacterSet(charactersIn: "-_.:/"))
            guard token.count >= 3 else { continue }
            let hasDigit = token.contains(where: \.isNumber)
            let isCode = token.count >= 4 && token.allSatisfy { !$0.isLetter || $0.isUppercase } && token.contains(where: \.isLetter)
            if hasDigit || isCode { result.insert(token.uppercased()) }
        }
        return result
    }
}
