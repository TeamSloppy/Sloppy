import Foundation

public struct WorkspaceBrowserBinding: Codable, Sendable {
    public var bridgeId: String
    public var agentId: String
    public var sessionId: String

    public init(bridgeId: String, agentId: String, sessionId: String) {
        self.bridgeId = bridgeId
        self.agentId = agentId
        self.sessionId = sessionId
    }
}

public struct WorkspaceBrowserCommand: Codable, Sendable {
    public var id: String
    public var name: String
    public var input: Input

    public struct Input: Codable, Sendable {
        public var url: String?
        public var pageId: String?
        public var selector: String?
        public var text: String?
        public var x: Double?
        public var y: Double?
    }
}

public struct WorkspaceBrowserCommands: Codable, Sendable {
    public var commands: [WorkspaceBrowserCommand]
}

public struct WorkspaceBrowserElement: Codable, Sendable {
    public var selector: String
    public var role: String
    public var name: String
    public var disabled: Bool
}

public struct WorkspaceBrowserPage: Codable, Sendable {
    public var pageId: String
    public var url: String
    public var title: String
    public var visibleText: String
    public var elements: [WorkspaceBrowserElement]
    public var running: Bool

    public init(pageId: String, url: String, title: String, visibleText: String,
                elements: [WorkspaceBrowserElement] = [], running: Bool = true) {
        self.pageId = pageId
        self.url = url
        self.title = title
        self.visibleText = visibleText
        self.elements = elements
        self.running = running
    }
}

public struct WorkspaceBrowserCompletion: Codable, Sendable {
    public var binding: WorkspaceBrowserBinding
    public var commandId: String
    public var data: WorkspaceBrowserPage?
    public var imageBase64: String?
    public var error: String?

    public init(binding: WorkspaceBrowserBinding, commandId: String,
                data: WorkspaceBrowserPage? = nil, imageBase64: String? = nil, error: String? = nil) {
        self.binding = binding
        self.commandId = commandId
        self.data = data
        self.imageBase64 = imageBase64
        self.error = error
    }
}
