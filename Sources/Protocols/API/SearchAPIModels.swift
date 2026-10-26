import Foundation

/// Literal text is the default; words also supports a prefix for the last word.
public enum TextSearchMode: String, Codable, Sendable {
    case text
    case words
}

public struct TextSearchHit: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var source: String
    public var agentId: String?
    public var sessionId: String
    public var projectId: String?
    public var title: String
    public var eventId: String
    public var messageId: String?
    /// Exclusive byte boundary of the journal event, usable by the session history API.
    public var before: String
    public var kind: String
    public var role: String?
    public var createdAt: String
    public var snippet: String

    public init(id: String, source: String, agentId: String?, sessionId: String, projectId: String?, title: String,
                eventId: String, messageId: String?, before: String, kind: String, role: String?, createdAt: String, snippet: String) {
        self.id = id; self.source = source; self.agentId = agentId; self.sessionId = sessionId
        self.projectId = projectId; self.title = title; self.eventId = eventId; self.messageId = messageId
        self.before = before; self.kind = kind; self.role = role; self.createdAt = createdAt; self.snippet = snippet
    }
}

public struct TextSearchResponse: Codable, Sendable {
    public var items: [TextSearchHit]
    public var hasMore: Bool
    public var indexing: Bool
    public var indexedSources: Int
    public var failedSources: Int
    public var durationMs: Double

    public init(items: [TextSearchHit], hasMore: Bool, indexing: Bool, indexedSources: Int, failedSources: Int, durationMs: Double) {
        self.items = items; self.hasMore = hasMore; self.indexing = indexing
        self.indexedSources = indexedSources; self.failedSources = failedSources; self.durationMs = durationMs
    }
}

public struct TextSearchDocumentResponse: Codable, Sendable {
    public var hit: TextSearchHit
    public var text: String

    public init(hit: TextSearchHit, text: String) {
        self.hit = hit; self.text = text
    }
}
