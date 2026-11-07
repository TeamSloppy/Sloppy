import Foundation
import SloppyClientCore

enum ChatTranscriptEntry: Identifiable, Equatable {
    case message(ChatMessage)
    case systemGroup([ChatMessage])
    case fragment(ChatMessage, Range<Int>)

    enum Presentation: Equatable {
        case message(ChatMessage)
        case systemGroup([ChatMessage])
    }

    var presentation: Presentation {
        switch self {
        case .message(let message): return .message(message)
        case .systemGroup(let messages): return .systemGroup(messages)
        case .fragment(let message, let range):
            var part = message
            part.segments = Array(message.segments[range])
            return part.segments.first?.isAssistantActivity == true ? .systemGroup([part]) : .message(part)
        }
    }

    var segmentOffset: Int {
        if case .fragment(_, let range) = self { return range.lowerBound }
        return 0
    }

    var sourceMessage: ChatMessage? {
        if case .fragment(let message, _) = self { return message }
        return nil
    }

    var messageIDs: Set<ChatMessage.ID> {
        switch presentation {
        case .message(let message): return [message.id]
        case .systemGroup(let messages): return Set(messages.map(\.id))
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        // A growing response must not invalidate earlier fragments of the same
        // canonical message when their displayed segments have not changed.
        lhs.id == rhs.id && lhs.segmentOffset == rhs.segmentOffset && lhs.presentation == rhs.presentation
    }

    var id: String {
        switch self {
        case .message(let message):
            return "message:\(message.id)"
        case .systemGroup(let messages):
            return "system-group:\(messages.first?.id ?? "empty")"
        case .fragment(let message, let range):
            return "fragment:\(message.id):\(range.lowerBound)"
        }
    }

    var createdAt: Date {
        switch self {
        case .message(let message):
            return message.createdAt
        case .systemGroup(let messages):
            return messages.first?.createdAt ?? .distantPast
        case .fragment(let message, _): return message.createdAt
        }
    }
}

enum ChatTranscriptDateSeparators {
    static let minimumInterval: TimeInterval = 45 * 60

    static func shouldInsert(
        between previous: Date,
        and current: Date,
        calendar: Calendar = .current
    ) -> Bool {
        !calendar.isDate(previous, inSameDayAs: current)
            || current.timeIntervalSince(previous) >= minimumInterval
    }

    static func title(for date: Date, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) {
            return "Today \(time)"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday \(time)"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

enum ChatTranscriptGrouping {
    static func entries(from messages: [ChatMessage]) -> [ChatTranscriptEntry] {
        var entries: [ChatTranscriptEntry] = []
        var pendingSystemMessages: [ChatMessage] = []

        func flushSystemMessages(reorderLateReasoning: Bool = false) {
            guard !pendingSystemMessages.isEmpty else { return }
            // Providers can persist their accumulated reasoning after the final
            // text. Keep that typed thinking-only block with the preceding work,
            // so the reply remains the last visible part of the turn.
            if reorderLateReasoning, pendingSystemMessages.allSatisfy({ message in
                !message.segments.isEmpty && message.longChatTask == nil && message.workerSession == nil
                    && message.segments.allSatisfy { $0.kind == .thinking }
            }), let last = entries.last, case .message(let response) = last,
               response.role == .assistant, response.segments.contains(where: { $0.kind == .text }) {
                entries.removeLast()
                if let previous = entries.last, case .systemGroup(let activity) = previous {
                    entries.removeLast()
                    entries.append(.systemGroup(activity + pendingSystemMessages))
                } else {
                    entries.append(.systemGroup(pendingSystemMessages))
                }
                entries.append(last)
            } else {
                entries.append(.systemGroup(pendingSystemMessages))
            }
            pendingSystemMessages.removeAll(keepingCapacity: true)
        }

        for message in messages {
            if isGroupableSystemMessage(message) {
                pendingSystemMessages.append(message)
            } else if message.role == .assistant {
                let ranges = segmentRanges(in: message)
                // Interleaved text and activity must stay in segment order. Keep
                // canonical message IDs and segment indices for actions/annotations.
                if ranges.count > 2 || (ranges.count == 2 && !message.segments[0].isAssistantActivity) {
                    flushSystemMessages()
                    entries.append(contentsOf: ranges.map { .fragment(message, $0) })
                    continue
                }
                let activitySegments = message.segments.filter(\.isAssistantActivity)
                guard !activitySegments.isEmpty else {
                    flushSystemMessages()
                    entries.append(.message(message))
                    continue
                }
                var activity = message
                activity.segments = activitySegments
                pendingSystemMessages.append(activity)

                var response = message
                response.segments.removeAll(where: \.isAssistantActivity)
                if !response.segments.isEmpty {
                    flushSystemMessages()
                    entries.append(.message(response))
                }
            } else {
                flushSystemMessages(reorderLateReasoning: message.role == .user)
                entries.append(.message(message))
            }
        }

        flushSystemMessages(reorderLateReasoning: true)
        return entries
    }

    private static func isGroupableSystemMessage(_ message: ChatMessage) -> Bool {
        message.role == .system
            && message.segments.allSatisfy { $0.buildProgress == nil }
    }

    private static func segmentRanges(in message: ChatMessage) -> [Range<Int>] {
        guard !message.segments.isEmpty else { return [] }
        var ranges: [Range<Int>] = []
        var start = 0
        for index in message.segments.indices.dropFirst() {
            if message.segments[index].isAssistantActivity != message.segments[start].isAssistantActivity {
                ranges.append(start..<index)
                start = index
            }
        }
        ranges.append(start..<message.segments.count)
        return ranges
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
    var isAssistantActivity: Bool {
        switch kind {
        case .thinking, .toolCall, .toolResult:
            return true
        case .text, .attachment, .status, .buildProgress:
            return false
        }
    }

    var isExecutionRunning: Bool {
        if let status = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            return status == "started" || status == "running" || status == "in_progress"
        }
        return startedAt != nil && finishedAt == nil
    }
}

private extension ChatTranscriptEntry {
    var isSystemActivity: Bool {
        switch presentation {
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
