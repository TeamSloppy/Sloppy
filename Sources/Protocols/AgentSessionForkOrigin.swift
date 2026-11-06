import Foundation

/// Immediate source of copied conversation history. It carries no runtime authority.
public struct AgentSessionForkOrigin: Codable, Sendable, Equatable {
    public var sourceAgentId: String
    public var sourceSessionId: String
    public var sourceEventId: String

    public init(sourceAgentId: String, sourceSessionId: String, sourceEventId: String) {
        self.sourceAgentId = sourceAgentId
        self.sourceSessionId = sourceSessionId
        self.sourceEventId = sourceEventId
    }
}
