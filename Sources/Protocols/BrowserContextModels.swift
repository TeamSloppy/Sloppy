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

public struct BrowserContextBrowser: Codable, Sendable, Equatable {
    public var tabs: [JSONValue]
    public var pageSnapshot: JSONValue?

    public init(tabs: [JSONValue] = [], pageSnapshot: JSONValue? = nil) {
        self.tabs = tabs
        self.pageSnapshot = pageSnapshot
    }
}

public struct BrowserWidgetSessionWidget: Codable, Sendable, Equatable {
    public var kind: String?
    public var title: String?
    public var size: String?
    public var colSpan: Int?
    public var rowSpan: Int?
    public var artifactId: String?
    public var sourceItemId: String?

    public init(
        kind: String? = nil,
        title: String? = nil,
        size: String? = nil,
        colSpan: Int? = nil,
        rowSpan: Int? = nil,
        artifactId: String? = nil,
        sourceItemId: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.size = size
        self.colSpan = colSpan
        self.rowSpan = rowSpan
        self.artifactId = artifactId
        self.sourceItemId = sourceItemId
    }
}

public struct BrowserWidgetSession: Codable, Sendable, Equatable {
    public var mode: String?
    public var isolated: Bool?
    public var sessionId: String?
    public var sourceItemId: String?
    public var widget: BrowserWidgetSessionWidget?

    public init(
        mode: String? = nil,
        isolated: Bool? = nil,
        sessionId: String? = nil,
        sourceItemId: String? = nil,
        widget: BrowserWidgetSessionWidget? = nil
    ) {
        self.mode = mode
        self.isolated = isolated
        self.sessionId = sessionId
        self.sourceItemId = sourceItemId
        self.widget = widget
    }
}

public struct BrowserContextMessageRequest: Codable, Sendable, Equatable {
    public var source: String
    public var page: BrowserContextPage
    public var selection: BrowserContextSelection
    public var browser: BrowserContextBrowser?
    public var widgetSession: BrowserWidgetSession?
    public var prompt: String
    public var target: BrowserContextTarget
    public var attachments: [AgentAttachmentUpload]
    public var userId: String

    private enum CodingKeys: String, CodingKey {
        case source
        case page
        case selection
        case browser
        case widgetSession
        case prompt
        case target
        case attachments
        case userId
    }

    public init(
        source: String = "safari_extension",
        page: BrowserContextPage,
        selection: BrowserContextSelection,
        prompt: String,
        browser: BrowserContextBrowser? = nil,
        widgetSession: BrowserWidgetSession? = nil,
        target: BrowserContextTarget = BrowserContextTarget(),
        attachments: [AgentAttachmentUpload] = [],
        userId: String = "safari_extension"
    ) {
        self.source = source
        self.page = page
        self.selection = selection
        self.browser = browser
        self.widgetSession = widgetSession
        self.prompt = prompt
        self.target = target
        self.attachments = attachments
        self.userId = userId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.source = try container.decodeIfPresent(String.self, forKey: .source) ?? "safari_extension"
        self.page = try container.decode(BrowserContextPage.self, forKey: .page)
        self.selection = try container.decode(BrowserContextSelection.self, forKey: .selection)
        self.browser = try container.decodeIfPresent(BrowserContextBrowser.self, forKey: .browser)
        self.widgetSession = try container.decodeIfPresent(BrowserWidgetSession.self, forKey: .widgetSession)
        self.prompt = try container.decode(String.self, forKey: .prompt)
        self.target = try container.decodeIfPresent(BrowserContextTarget.self, forKey: .target) ?? BrowserContextTarget()
        self.attachments = try container.decodeIfPresent([AgentAttachmentUpload].self, forKey: .attachments) ?? []
        self.userId = try container.decodeIfPresent(String.self, forKey: .userId) ?? "safari_extension"
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
