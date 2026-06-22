import Foundation

public struct BrowserContextPage: Codable, Sendable, Equatable {
    public var url: String
    public var title: String?

    public init(url: String, title: String? = nil) {
        self.url = url
        self.title = title
    }
}

public struct BrowserContextSelection: Codable, Sendable, Equatable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

public struct BrowserContextTarget: Codable, Sendable, Equatable {
    public var agentId: String
    public var sessionId: String?

    public init(agentId: String = "sloppy", sessionId: String? = nil) {
        self.agentId = agentId
        self.sessionId = sessionId
    }
}

public struct BrowserContextMessageRequest: Codable, Sendable, Equatable {
    public var source: String
    public var page: BrowserContextPage
    public var selection: BrowserContextSelection
    public var prompt: String
    public var target: BrowserContextTarget
    public var userId: String

    public init(
        source: String = "safari_extension",
        page: BrowserContextPage,
        selection: BrowserContextSelection,
        prompt: String,
        target: BrowserContextTarget = BrowserContextTarget(),
        userId: String = "safari_extension"
    ) {
        self.source = source
        self.page = page
        self.selection = selection
        self.prompt = prompt
        self.target = target
        self.userId = userId
    }
}

public struct BrowserContextMessageResponse: Codable, Sendable, Equatable {
    public var sessionId: String
    public var messageId: String?
    public var status: String
    public var text: String

    public init(sessionId: String, messageId: String? = nil, status: String, text: String) {
        self.sessionId = sessionId
        self.messageId = messageId
        self.status = status
        self.text = text
    }
}
