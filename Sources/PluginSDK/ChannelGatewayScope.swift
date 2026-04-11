import Foundation

/// Scopes gateway traffic (e.g. Telegram forum topics) onto distinct Sloppy channel/session keys while preserving a stable binding id.
public enum ChannelGatewayScope {
    private static let unitSeparator = "\u{001E}" // RECORD SEPARATOR — unlikely in user channel ids
    private static let topicMarker = "tgthread:"

    /// Returns a distinct channel id per topic when `topicKey` is non-empty; otherwise `baseChannelId`.
    public static func scopedChannelId(baseChannelId: String, topicKey: String?) -> String {
        let base = baseChannelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let topic = topicKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !base.isEmpty, !topic.isEmpty else {
            return base
        }
        return "\(base)\(unitSeparator)\(topicMarker)\(topic)"
    }

    /// Splits a scoped id into binding base + optional topic key (Telegram `message_thread_id` string).
    public static func parse(_ scopedOrBaseChannelId: String) -> (baseChannelId: String, topicKey: String?) {
        let raw = scopedOrBaseChannelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = "\(unitSeparator)\(topicMarker)"
        guard let range = raw.range(of: needle) else {
            return (raw, nil)
        }
        let base = String(raw[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let topic = String(raw[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            return (raw, nil)
        }
        return (base, topic.isEmpty ? nil : topic)
    }

    /// Whether an open session was opened for this gateway binding (exact base or topic under that base).
    public static func sessionMatchesBinding(sessionChannelId: String, bindingChannelId: String) -> Bool {
        let binding = bindingChannelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = sessionChannelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !binding.isEmpty else { return false }
        if session == binding { return true }
        return session.hasPrefix("\(binding)\(unitSeparator)\(topicMarker)")
    }
}
