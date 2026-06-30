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
    case toolCall = "tool_call"
    case toolResult = "tool_result"
    case status
}

public struct ChatMessageSegment: Codable, Sendable, Equatable {
    public var kind: ChatMessageSegmentKind
    public var text: String?
    public var title: String?
    public var status: String?
    public var startedAt: Date?
    public var finishedAt: Date?
    public var metadata: [String: String]?

    public init(
        kind: ChatMessageSegmentKind,
        text: String? = nil,
        title: String? = nil,
        status: String? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        metadata: [String: String]? = nil
    ) {
        self.kind = kind
        self.text = text
        self.title = title
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.metadata = metadata
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
    public var projectId: String?

    public init(
        id: String,
        agentId: String,
        title: String,
        messageCount: Int = 0,
        updatedAt: Date = Date(),
        kind: String = "chat",
        projectId: String? = nil
    ) {
        self.id = id
        self.agentId = agentId
        self.title = title
        self.messageCount = messageCount
        self.updatedAt = updatedAt
        self.kind = kind
        self.projectId = projectId
    }
}

public struct ChatSessionDetail: Decodable, Sendable {
    public var summary: ChatSessionSummary
    public var events: [ChatEventEnvelope]
    private var directMessages: [ChatMessage]

    public var messages: [ChatMessage] {
        directMessages.isEmpty ? events.compactMap { $0.message } : directMessages
    }

    public init(summary: ChatSessionSummary, events: [ChatEventEnvelope] = [], messages: [ChatMessage] = []) {
        self.summary = summary
        self.events = events
        self.directMessages = messages
    }

    private enum CodingKeys: String, CodingKey {
        case summary, events, messages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(ChatSessionSummary.self, forKey: .summary)
        events = try container.decodeIfPresent([ChatEventEnvelope].self, forKey: .events) ?? []
        directMessages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
    }
}

public struct ChatEventEnvelope: Decodable, Sendable {
    public var id: String
    public var type: String
    public var message: ChatMessage?

    private enum CodingKeys: String, CodingKey {
        case id, type, message, event
    }

    private struct EmbeddedEvent: Decodable {
        var message: ChatMessage?
    }

    public init(id: String, type: String, message: ChatMessage? = nil) {
        self.id = id
        self.type = type
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)

        // REST session history stores chat messages on the event itself:
        // { "type": "message", "message": { ... } }
        // Some streamed/debug payloads wrap the same value under `event.message`.
        // Support both so opening an existing session can hydrate the transcript.
        message = try container.decodeIfPresent(ChatMessage.self, forKey: .message)
            ?? container.decodeIfPresent(EmbeddedEvent.self, forKey: .event)?.message
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
