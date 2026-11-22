import Foundation

public struct ChatTurnDiff: Codable, Sendable, Equatable {
    public struct File: Codable, Sendable, Equatable, Identifiable {
        public enum Attribution: String, Codable, Sendable {
            case verified
            case interleaved
            case limited
        }

        public let path: String
        public let attribution: Attribution
        public let patch: String?
        public let additions: Int
        public let deletions: Int

        public var id: String { path }
    }

    public let files: [File]
    public let truncated: Bool
}

extension ChatRunStatusEvent {
    func diffTimelineMessage(eventID: String, createdAt: Date) -> ChatMessage? {
        guard let turnDiff else { return nil }
        var message = ChatMessage(id: "turn-diff:\(id ?? eventID)", role: .system, segments: [], createdAt: createdAt)
        message.turnDiff = turnDiff
        return message
    }
}
