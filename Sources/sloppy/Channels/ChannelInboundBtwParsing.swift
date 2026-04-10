import Foundation

enum ChannelInboundBtwParsing {
    /// `nil` if the message is not a `/btw` command; otherwise the model-facing tail (may be empty).
    static func btwModelTailIfCommand(_ content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased() == "/btw" || trimmed.lowercased().hasPrefix("/btw ") else {
            return nil
        }
        guard let range = trimmed.range(of: "/btw", options: [.anchored, .caseInsensitive]) else {
            return ""
        }
        var after = String(trimmed[range.upperBound...])
        if after.hasPrefix(" ") {
            after = String(after.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            after = after.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return after
    }
}
