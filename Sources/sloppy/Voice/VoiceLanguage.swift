import Foundation

enum VoiceLanguage {
    /// Reduces a locale identifier ("ru_RU", "ru-RU", "RU") to the ISO 639 code that Whisper-style
    /// APIs accept ("ru"). Empty, "auto" and unrecognizable values mean "detect automatically".
    static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed != "auto" else { return nil }
        let code = trimmed.split(whereSeparator: { $0 == "_" || $0 == "-" }).first.map(String.init) ?? trimmed
        guard (2...3).contains(code.count), code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return code
    }
}
