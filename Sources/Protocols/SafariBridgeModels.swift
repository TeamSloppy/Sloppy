import Foundation

public struct SafariBridgeTab: Codable, Sendable, Equatable {
    public var id: Int?
    public var url: String
    public var title: String?
    public var active: Bool
    public var currentWindow: Bool

    public init(id: Int? = nil, url: String, title: String? = nil, active: Bool = false, currentWindow: Bool = false) {
        self.id = id
        self.url = url
        self.title = title
        self.active = active
        self.currentWindow = currentWindow
    }
}

public struct SafariBridgeRegisterRequest: Codable, Sendable, Equatable {
    public var bridgeId: String?
    public var tabs: [SafariBridgeTab]
    public var capabilities: [String]

    public init(bridgeId: String? = nil, tabs: [SafariBridgeTab] = [], capabilities: [String] = []) {
        self.bridgeId = bridgeId
        self.tabs = tabs
        self.capabilities = capabilities
    }
}

public struct SafariBridgeRegisterResponse: Codable, Sendable, Equatable {
    public var bridgeId: String
    public var status: String
    public var commandPollIntervalMs: Int

    public init(bridgeId: String, status: String = "registered", commandPollIntervalMs: Int = 1_000) {
        self.bridgeId = bridgeId
        self.status = status
        self.commandPollIntervalMs = commandPollIntervalMs
    }
}

public struct SafariBridgeCommand: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var input: JSONValue

    public init(id: String, name: String, input: JSONValue = .object([:])) {
        self.id = id
        self.name = name
        self.input = input
    }
}

public struct SafariBridgeCommandListResponse: Codable, Sendable, Equatable {
    public var commands: [SafariBridgeCommand]

    public init(commands: [SafariBridgeCommand] = []) {
        self.commands = commands
    }
}

public struct SafariBridgeCommandResultRequest: Codable, Sendable, Equatable {
    public var commandId: String
    public var ok: Bool
    public var data: JSONValue?
    public var error: String?

    public init(commandId: String, ok: Bool, data: JSONValue? = nil, error: String? = nil) {
        self.commandId = commandId
        self.ok = ok
        self.data = data
        self.error = error
    }
}
