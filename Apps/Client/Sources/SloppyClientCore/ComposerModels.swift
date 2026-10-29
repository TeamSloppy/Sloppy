public struct AgentChatSlashCommandItem: Codable, Sendable, Equatable {
    public var source: String
    public var name: String
    public var description: String
    public var argument: String?
    public var skillId: String?
    public var displayName: String?

    public init(
        source: String,
        name: String,
        description: String,
        argument: String? = nil,
        skillId: String? = nil,
        displayName: String? = nil
    ) {
        self.source = source
        self.name = name
        self.description = description
        self.argument = argument
        self.skillId = skillId
        self.displayName = displayName
    }
}

public struct AgentChatSlashCommandsResponse: Codable, Sendable, Equatable {
    public var commands: [AgentChatSlashCommandItem]

    public init(commands: [AgentChatSlashCommandItem]) {
        self.commands = commands
    }
}
