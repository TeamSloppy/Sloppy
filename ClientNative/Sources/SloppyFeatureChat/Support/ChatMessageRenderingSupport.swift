import Foundation
import SloppyClientCore

enum ChatTranscriptEntry: Identifiable, Equatable {
    case message(ChatMessage)
    case systemGroup([ChatMessage])

    var id: String {
        switch self {
        case .message(let message):
            return "message:\(message.id)"
        case .systemGroup(let messages):
            return "system-group:\(messages.first?.id ?? "empty")"
        }
    }
}

enum ChatTranscriptGrouping {
    static func entries(from messages: [ChatMessage]) -> [ChatTranscriptEntry] {
        var entries: [ChatTranscriptEntry] = []
        var pendingSystemMessages: [ChatMessage] = []

        func flushSystemMessages() {
            guard !pendingSystemMessages.isEmpty else { return }
            entries.append(.systemGroup(pendingSystemMessages))
            pendingSystemMessages.removeAll(keepingCapacity: true)
        }

        for message in messages {
            if isGroupableSystemMessage(message) {
                pendingSystemMessages.append(message)
            } else {
                flushSystemMessages()
                entries.append(.message(message))
            }
        }

        flushSystemMessages()
        return entries
    }

    private static func isGroupableSystemMessage(_ message: ChatMessage) -> Bool {
        message.role == .system
            && message.segments.allSatisfy { $0.buildProgress == nil }
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
