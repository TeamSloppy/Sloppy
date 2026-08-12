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

    static func usesCompactSpacing(
        between current: ChatTranscriptEntry,
        and next: ChatTranscriptEntry
    ) -> Bool {
        current.isSystemActivity && next.isSystemActivity
    }
}

enum ChatActiveRunMessages {
    static func messageIDs(
        in messages: [ChatMessage],
        isRunActive: Bool
    ) -> Set<ChatMessage.ID> {
        guard isRunActive,
              let lastUserIndex = messages.lastIndex(where: { $0.role == .user }) else {
            return []
        }

        let firstActiveIndex = messages.index(after: lastUserIndex)
        guard firstActiveIndex < messages.endIndex else { return [] }

        let activeMessages = messages[firstActiveIndex...]
        var messageIDs = Set(activeMessages.compactMap { message -> ChatMessage.ID? in
            message.segments.contains(where: \.isExecutionRunning) ? message.id : nil
        })

        if let thinkingMessage = activeMessages.reversed().first(where: { message in
            message.role == .assistant
                && message.segments.contains(where: { $0.kind == .thinking })
        }) {
            messageIDs.insert(thinkingMessage.id)
        }

        return messageIDs
    }
}

extension ChatMessageSegment {
    var isExecutionRunning: Bool {
        if let status = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            return status == "started" || status == "running" || status == "in_progress"
        }
        return startedAt != nil && finishedAt == nil
    }
}

private extension ChatTranscriptEntry {
    var isSystemActivity: Bool {
        switch self {
        case .message(let message):
            return message.role == .system
        case .systemGroup:
            return true
        }
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
