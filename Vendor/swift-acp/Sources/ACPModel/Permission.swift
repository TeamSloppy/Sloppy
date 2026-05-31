//
//  Permission.swift
//  ACPModel
//
//  Agent Client Protocol - Permission Types
//

import Foundation

// MARK: - Permission Request

public struct RequestPermissionRequest: Codable, Sendable {
    public let message: String?
    public let options: [PermissionOption]?
    public let sessionId: SessionId?
    public let toolCall: PermissionToolCall?

    enum CodingKeys: String, CodingKey {
        case message
        case options
        case sessionId
        case toolCall
    }

    public init(message: String? = nil, options: [PermissionOption]? = nil, sessionId: SessionId? = nil, toolCall: PermissionToolCall? = nil) {
        self.message = message
        self.options = options
        self.sessionId = sessionId
        self.toolCall = toolCall
    }
}

public struct PermissionOption: Codable, Sendable {
    public let kind: String
    public let name: String
    public let optionId: String

    enum CodingKeys: String, CodingKey {
        case kind
        case name
        case optionId
    }

    public init(kind: String, name: String, optionId: String) {
        self.kind = kind
        self.name = name
        self.optionId = optionId
    }
}

public struct PermissionToolCall: Codable, Sendable {
    public let toolCallId: String
    public let rawInput: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case toolCallId
        case rawInput
    }

    public init(toolCallId: String, rawInput: AnyCodable? = nil) {
        self.toolCallId = toolCallId
        self.rawInput = rawInput
    }
}

// MARK: - Permission Decision

public enum PermissionDecision: String, Codable, Sendable {
    case allowOnce = "allow_once"
    case allowAlways = "allow_always"
    case rejectOnce = "reject_once"
    case rejectAlways = "reject_always"
}

// MARK: - Permission Response

public struct RequestPermissionResponse: Codable, Sendable {
    public let outcome: PermissionOutcome

    enum CodingKeys: String, CodingKey {
        case outcome
    }

    public init(outcome: PermissionOutcome) {
        self.outcome = outcome
    }
}

public struct PermissionOutcome: Codable, Sendable {
    public let outcome: String
    public let optionId: String?

    enum CodingKeys: String, CodingKey {
        case outcome
        case optionId
    }

    public init(optionId: String) {
        self.outcome = "selected"
        self.optionId = optionId
    }

    public init(cancelled: Bool) {
        self.outcome = "cancelled"
        self.optionId = nil
    }
}
