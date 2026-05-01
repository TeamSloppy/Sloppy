import Foundation
import SloppyComputerControl

public enum NodeAction: String, Codable, Sendable {
    case exec
    case computerClick = "computer.click"
    case computerTypeText = "computer.typeText"
    case computerKey = "computer.key"
    case computerScreenshot = "computer.screenshot"
    case status
}

public struct NodeActionRequest: Codable, Sendable, Equatable {
    public var action: NodeAction
    public var payload: JSONValue

    public init(action: NodeAction, payload: JSONValue = .object([:])) {
        self.action = action
        self.payload = payload
    }
}

public struct NodeActionResponse: Codable, Sendable, Equatable {
    public var action: NodeAction
    public var ok: Bool
    public var data: JSONValue?
    public var error: NodeActionError?

    public init(action: NodeAction, ok: Bool, data: JSONValue? = nil, error: NodeActionError? = nil) {
        self.action = action
        self.ok = ok
        self.data = data
        self.error = error
    }

    public static func success(action: NodeAction, data: JSONValue = .object([:])) -> NodeActionResponse {
        NodeActionResponse(action: action, ok: true, data: data)
    }

    public static func failure(action: NodeAction, code: String, message: String, retryable: Bool = false) -> NodeActionResponse {
        NodeActionResponse(
            action: action,
            ok: false,
            error: NodeActionError(code: code, message: message, retryable: retryable)
        )
    }
}

public struct NodeActionError: Codable, Sendable, Equatable {
    public var code: String
    public var message: String
    public var retryable: Bool

    public init(code: String, message: String, retryable: Bool = false) {
        self.code = code
        self.message = message
        self.retryable = retryable
    }
}

public struct NodeExecPayload: Codable, Sendable, Equatable {
    public var command: String
    public var arguments: [String]

    public init(command: String, arguments: [String] = []) {
        self.command = command
        self.arguments = arguments
    }
}

public typealias ComputerClickPayload = SloppyComputerControl.ComputerClickPayload
public typealias ComputerTypeTextPayload = SloppyComputerControl.ComputerTypeTextPayload
public typealias ComputerKeyPayload = SloppyComputerControl.ComputerKeyPayload
public typealias ComputerScreenshotPayload = SloppyComputerControl.ComputerScreenshotPayload
public typealias ComputerScreenshotResult = SloppyComputerControl.ComputerScreenshotResult
