import Foundation

public enum ChatStreamUpdateKind: String, Codable, Sendable {
    case sessionReady = "session_ready"
    case sessionEvent = "session_event"
    case sessionDelta = "session_delta"
    case heartbeat
    case sessionClosed = "session_closed"
    case sessionError = "session_error"
}

public enum ChatMessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

public enum ChatMessageSegmentKind: String, Codable, Sendable {
    case text
    case thinking
    case attachment
}

public struct ChatMessageSegment: Codable, Sendable, Equatable {
    public var kind: ChatMessageSegmentKind
    public var text: String?

    public init(kind: ChatMessageSegmentKind, text: String? = nil) {
        self.kind = kind
        self.text = text
    }
}

public struct ChatMessage: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var role: ChatMessageRole
    public var segments: [ChatMessageSegment]
    public var createdAt: Date

    public var textContent: String {
        segments.filter { $0.kind == .text }.compactMap { $0.text }.joined()
    }

    public init(
        id: String = UUID().uuidString,
        role: ChatMessageRole,
        segments: [ChatMessageSegment],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.segments = segments
        self.createdAt = createdAt
    }
}

public struct ChatSessionSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var agentId: String
    public var title: String
    public var messageCount: Int
    public var updatedAt: Date
    public var kind: String

    public init(
        id: String,
        agentId: String,
        title: String,
        messageCount: Int = 0,
        updatedAt: Date = Date(),
        kind: String = "chat"
    ) {
        self.id = id
        self.agentId = agentId
        self.title = title
        self.messageCount = messageCount
        self.updatedAt = updatedAt
        self.kind = kind
    }
}

public struct ChatSessionDetail: Decodable, Sendable {
    public var summary: ChatSessionSummary
    public var events: [ChatEventEnvelope]

    public var messages: [ChatMessage] {
        events.compactMap { $0.message }
    }

    public init(summary: ChatSessionSummary, events: [ChatEventEnvelope] = []) {
        self.summary = summary
        self.events = events
    }
}

public struct ChatEventEnvelope: Decodable, Sendable {
    public var id: String
    public var type: String
    public var message: ChatMessage?

    private enum CodingKeys: String, CodingKey {
        case id, type, message
    }
}

// Mirrors the server's AgentSessionStreamUpdate wire format.
// The server puts the full event object under "event", which itself may contain a "message".
public struct ChatStreamUpdate: Sendable {
    public var kind: ChatStreamUpdateKind
    public var cursor: Int
    public var summary: ChatSessionSummary?
    public var message: ChatMessage?
    public var messageText: String?
    public var errorText: String?
    public var createdAt: Date

    public init(
        kind: ChatStreamUpdateKind,
        cursor: Int,
        summary: ChatSessionSummary? = nil,
        message: ChatMessage? = nil,
        messageText: String? = nil,
        errorText: String? = nil,
        createdAt: Date = Date()
    ) {
        self.kind = kind
        self.cursor = cursor
        self.summary = summary
        self.message = message
        self.messageText = messageText
        self.errorText = errorText
        self.createdAt = createdAt
    }
}

extension ChatStreamUpdate: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind, cursor, summary, event, message, createdAt
    }

    private struct EmbeddedEvent: Decodable {
        var message: ChatMessage?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(ChatStreamUpdateKind.self, forKey: .kind)
        cursor = try container.decodeIfPresent(Int.self, forKey: .cursor) ?? 0
        summary = try container.decodeIfPresent(ChatSessionSummary.self, forKey: .summary)
        createdAt = (try? container.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        let text = try container.decodeIfPresent(String.self, forKey: .message)
        messageText = kind == .sessionDelta ? text : nil
        errorText = kind == .sessionError || kind == .sessionClosed ? text : nil
        let embedded = try container.decodeIfPresent(EmbeddedEvent.self, forKey: .event)
        message = embedded?.message
    }
}
