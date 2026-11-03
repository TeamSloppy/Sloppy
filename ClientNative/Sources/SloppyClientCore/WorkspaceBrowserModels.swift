import Foundation
import SloppyA2UI

public typealias WorkspaceBrowserJSONValue = A2UIValue

public struct WorkspaceBrowserEvaluation: Codable, Sendable {
    public var value: WorkspaceBrowserJSONValue

    public init(value: WorkspaceBrowserJSONValue) { self.value = value }
}

public struct WorkspaceBrowserBinding: Codable, Sendable {
    public var bridgeId: String
    public var agentId: String
    public var sessionId: String
    public var capabilities: [String]?

    public init(bridgeId: String, agentId: String, sessionId: String, capabilities: [String]? = nil) {
        self.bridgeId = bridgeId
        self.agentId = agentId
        self.sessionId = sessionId
        self.capabilities = capabilities
    }
}

public struct WorkspaceBrowserCommand: Codable, Sendable {
    public var id: String
    public var name: String
    public var input: Input

    public struct Input: Codable, Sendable {
        public var operation: String?
        public var platform: String?
        public var deviceId: String?
        public var androidAddress: String?
        public var dueAt: String?
        public var priority: String?
        public var groupId: String?
        public var tabIds: [String]?
        public var title: String?
        public var tabId: String?
        public var url: String?
        public var pageId: String?
        public var selector: String?
        public var text: String?
        public var expression: String?
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
    public var evaluation: WorkspaceBrowserEvaluation?
    public var workspace: WorkspaceBrowserWorkspace?
    public var createdEntry: WorkspaceBrowserCreatedEntry?
    public var devicePreview: WorkspaceDevicePreview?

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

public struct WorkspaceDevicePreview: Codable, Sendable {
    public enum State: String, Codable, Sendable { case stopped, starting, ready, failed }
    public struct Device: Codable, Sendable {
        public var id: String
        public var name: String
        public init(id: String, name: String) { self.id = id; self.name = name }
    }
    public var state: State
    public var platform: String
    public var devices: [Device]
    public var error: String?
    public init(state: State, platform: String, devices: [Device], error: String? = nil) {
        self.state = state; self.platform = platform; self.devices = devices; self.error = error
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

public struct WorkspaceBrowserWorkspace: Codable, Sendable {
    public struct Tab: Codable, Sendable {
        public var id: String
        public var title: String
        public var url: String?
        public var groupId: String?
        public var selected: Bool

        public init(id: String, title: String, url: String?, selected: Bool, groupId: String? = nil) {
            self.id = id; self.title = title; self.url = url; self.selected = selected; self.groupId = groupId
        }
    }
    public struct Group: Codable, Sendable {
        public var id: String
        public var title: String
        public init(id: String, title: String) { self.id = id; self.title = title }
    }
    public var groups: [Group]?
    public var tabs: [Tab]
    public init(tabs: [Tab]) { self.tabs = tabs }
}

public struct WorkspaceBrowserCreatedEntry: Codable, Sendable {
    public var kind: String
    public var id: String
    public var title: String
    public init(kind: String, id: String, title: String) { self.kind = kind; self.id = id; self.title = title }
}
