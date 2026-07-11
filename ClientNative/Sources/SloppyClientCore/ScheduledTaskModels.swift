import Foundation

public struct ScheduledTask: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var agentId: String
    public var channelId: String
    public var schedule: String
    public var command: String
    public var enabled: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        agentId: String,
        channelId: String,
        schedule: String,
        command: String,
        enabled: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.agentId = agentId
        self.channelId = channelId
        self.schedule = schedule
        self.command = command
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ScheduledTaskCreateRequest: Codable, Sendable {
    public var channelId: String
    public var schedule: String
    public var command: String
    public var enabled: Bool?

    public init(channelId: String, schedule: String, command: String, enabled: Bool? = true) {
        self.channelId = channelId
        self.schedule = schedule
        self.command = command
        self.enabled = enabled
    }
}

public struct ScheduledTaskUpdateRequest: Codable, Sendable {
    public var channelId: String?
    public var schedule: String?
    public var command: String?
    public var enabled: Bool?

    public init(channelId: String? = nil, schedule: String? = nil, command: String? = nil, enabled: Bool? = nil) {
        self.channelId = channelId
        self.schedule = schedule
        self.command = command
        self.enabled = enabled
    }
}
