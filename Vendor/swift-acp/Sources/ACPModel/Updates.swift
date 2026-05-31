//
//  Updates.swift
//  ACPModel
//
//  Agent Client Protocol - Session Update Types
//

import Foundation

// MARK: - Session Update Notification

public struct SessionUpdateNotification: Codable, Sendable {
    public let sessionId: SessionId
    public let update: SessionUpdate
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case sessionId, update, _meta
    }

    public init(sessionId: SessionId, update: SessionUpdate, _meta: [String: AnyCodable]? = nil) {
        self.sessionId = sessionId
        self.update = update
        self._meta = _meta
    }
}

// MARK: - Usage

public struct Cost: Codable, Sendable {
    public let amount: Double
    public let currency: String

    public init(amount: Double, currency: String) {
        self.amount = amount
        self.currency = currency
    }
}

public struct Usage: Codable, Sendable {
    public let cachedReadTokens: Int?
    public let cachedWriteTokens: Int?
    public let inputTokens: Int
    public let outputTokens: Int
    public let thoughtTokens: Int?
    public let totalTokens: Int

    public init(
        cachedReadTokens: Int? = nil,
        cachedWriteTokens: Int? = nil,
        inputTokens: Int,
        outputTokens: Int,
        thoughtTokens: Int? = nil,
        totalTokens: Int
    ) {
        self.cachedReadTokens = cachedReadTokens
        self.cachedWriteTokens = cachedWriteTokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.thoughtTokens = thoughtTokens
        self.totalTokens = totalTokens
    }
}

public struct UsageUpdate: Codable, Sendable {
    public let used: Int
    public let size: Int
    public let cost: Cost?
    public let _meta: [String: AnyCodable]?

    public init(used: Int, size: Int, cost: Cost? = nil, _meta: [String: AnyCodable]? = nil) {
        self.used = used
        self.size = size
        self.cost = cost
        self._meta = _meta
    }
}

public enum SessionInfoFieldUpdate<Value: Sendable>: Sendable {
    case omitted
    case clear
    case set(Value)

    public var value: Value? {
        switch self {
        case .set(let value): return value
        case .omitted, .clear: return nil
        }
    }

    public var isOmitted: Bool {
        if case .omitted = self {
            return true
        }
        return false
    }

    public var isClear: Bool {
        if case .clear = self {
            return true
        }
        return false
    }
}

public struct SessionInfoUpdate: Codable, Sendable {
    public let titleUpdate: SessionInfoFieldUpdate<String>
    public let updatedAtUpdate: SessionInfoFieldUpdate<String>
    public let _meta: [String: AnyCodable]?

    public var title: String? { titleUpdate.value }
    public var updatedAt: String? { updatedAtUpdate.value }

    enum CodingKeys: String, CodingKey {
        case title
        case updatedAt
        case _meta
    }

    public init(title: String? = nil, updatedAt: String? = nil, _meta: [String: AnyCodable]? = nil) {
        self.titleUpdate = title.map(SessionInfoFieldUpdate.set) ?? .omitted
        self.updatedAtUpdate = updatedAt.map(SessionInfoFieldUpdate.set) ?? .omitted
        self._meta = _meta
    }

    public init(
        titleUpdate: SessionInfoFieldUpdate<String> = .omitted,
        updatedAtUpdate: SessionInfoFieldUpdate<String> = .omitted,
        _meta: [String: AnyCodable]? = nil
    ) {
        self.titleUpdate = titleUpdate
        self.updatedAtUpdate = updatedAtUpdate
        self._meta = _meta
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        titleUpdate = try Self.decodeField(String.self, forKey: .title, from: container)
        updatedAtUpdate = try Self.decodeField(String.self, forKey: .updatedAt, from: container)
        _meta = try container.decodeIfPresent([String: AnyCodable].self, forKey: ._meta)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try Self.encodeField(titleUpdate, forKey: .title, to: &container)
        try Self.encodeField(updatedAtUpdate, forKey: .updatedAt, to: &container)
        try container.encodeIfPresent(_meta, forKey: ._meta)
    }

    private static func decodeField(
        _ type: String.Type,
        forKey key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> SessionInfoFieldUpdate<String> {
        guard container.contains(key) else {
            return .omitted
        }

        if try container.decodeNil(forKey: key) {
            return .clear
        }

        return .set(try container.decode(type, forKey: key))
    }

    private static func encodeField(
        _ field: SessionInfoFieldUpdate<String>,
        forKey key: CodingKeys,
        to container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        switch field {
        case .omitted:
            break
        case .clear:
            try container.encodeNil(forKey: key)
        case .set(let value):
            try container.encode(value, forKey: key)
        }
    }
}

// MARK: - Session Update

public enum SessionUpdate: Codable, Sendable {
    case userMessageChunk(ContentBlock)
    case agentMessageChunk(ContentBlock)
    case agentThoughtChunk(ContentBlock)
    case toolCall(ToolCallUpdate)
    case toolCallUpdate(ToolCallUpdateDetails)
    case plan(Plan)
    case availableCommandsUpdate([AvailableCommand])
    case currentModeUpdate(String)
    case configOptionUpdate([SessionConfigOption])
    case sessionInfoUpdate(SessionInfoUpdate)
    case usageUpdate(UsageUpdate)

    enum CodingKeys: String, CodingKey {
        case sessionUpdate
        case content
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let updateType = try container.decode(String.self, forKey: .sessionUpdate)

        switch updateType {
        case "user_message_chunk":
            let content = try container.decode(ContentBlock.self, forKey: .content)
            self = .userMessageChunk(content)
        case "agent_message_chunk":
            let content = try container.decode(ContentBlock.self, forKey: .content)
            self = .agentMessageChunk(content)
        case "agent_thought_chunk":
            let content = try container.decode(ContentBlock.self, forKey: .content)
            self = .agentThoughtChunk(content)
        case "tool_call":
            let toolCall = try ToolCallUpdate(from: decoder)
            self = .toolCall(toolCall)
        case "tool_call_update":
            let details = try ToolCallUpdateDetails(from: decoder)
            self = .toolCallUpdate(details)
        case "plan":
            let plan = try Plan(from: decoder)
            self = .plan(plan)
        case "available_commands_update":
            let commands = try decoder.container(keyedBy: AnyCodingKey.self).decode([AvailableCommand].self, forKey: AnyCodingKey(stringValue: "availableCommands")!)
            self = .availableCommandsUpdate(commands)
        case "current_mode_update":
            let modeId = try decoder.container(keyedBy: AnyCodingKey.self).decode(String.self, forKey: AnyCodingKey(stringValue: "currentModeId")!)
            self = .currentModeUpdate(modeId)
        case "config_option_update":
            let configOptions = try decoder.container(keyedBy: AnyCodingKey.self).decode([SessionConfigOption].self, forKey: AnyCodingKey(stringValue: "configOptions")!)
            self = .configOptionUpdate(configOptions)
        case "session_info_update":
            let info = try SessionInfoUpdate(from: decoder)
            self = .sessionInfoUpdate(info)
        case "usage_update":
            let usage = try UsageUpdate(from: decoder)
            self = .usageUpdate(usage)
        default:
            throw DecodingError.dataCorruptedError(forKey: .sessionUpdate, in: container, debugDescription: "Unknown session update type: \(updateType)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .userMessageChunk(let content):
            try container.encode("user_message_chunk", forKey: .sessionUpdate)
            try container.encode(content, forKey: .content)
        case .agentMessageChunk(let content):
            try container.encode("agent_message_chunk", forKey: .sessionUpdate)
            try container.encode(content, forKey: .content)
        case .agentThoughtChunk(let content):
            try container.encode("agent_thought_chunk", forKey: .sessionUpdate)
            try container.encode(content, forKey: .content)
        case .toolCall(let toolCall):
            try container.encode("tool_call", forKey: .sessionUpdate)
            try toolCall.encode(to: encoder)
        case .toolCallUpdate(let details):
            try container.encode("tool_call_update", forKey: .sessionUpdate)
            try details.encode(to: encoder)
        case .plan(let plan):
            try container.encode("plan", forKey: .sessionUpdate)
            try plan.encode(to: encoder)
        case .availableCommandsUpdate(let commands):
            try container.encode("available_commands_update", forKey: .sessionUpdate)
            var innerContainer = encoder.container(keyedBy: AnyCodingKey.self)
            try innerContainer.encode(commands, forKey: AnyCodingKey(stringValue: "availableCommands")!)
        case .currentModeUpdate(let modeId):
            try container.encode("current_mode_update", forKey: .sessionUpdate)
            var innerContainer = encoder.container(keyedBy: AnyCodingKey.self)
            try innerContainer.encode(modeId, forKey: AnyCodingKey(stringValue: "currentModeId")!)
        case .configOptionUpdate(let configOptions):
            try container.encode("config_option_update", forKey: .sessionUpdate)
            var innerContainer = encoder.container(keyedBy: AnyCodingKey.self)
            try innerContainer.encode(configOptions, forKey: AnyCodingKey(stringValue: "configOptions")!)
        case .sessionInfoUpdate(let info):
            try container.encode("session_info_update", forKey: .sessionUpdate)
            try info.encode(to: encoder)
        case .usageUpdate(let usage):
            try container.encode("usage_update", forKey: .sessionUpdate)
            try usage.encode(to: encoder)
        }
    }
}

// MARK: - Tool Call Types

public struct ToolCallUpdate: Codable, Sendable {
    public let toolCallId: String
    public let title: String?
    public let kind: ToolKind?
    public let status: ToolStatus
    public let content: [ToolCallContent]
    public let locations: [ToolLocation]?
    public let rawInput: AnyCodable?
    public let rawOutput: AnyCodable?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case toolCallId
        case title, kind, status, content, locations
        case rawInput
        case rawOutput
        case _meta
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolCallId = try container.decode(String.self, forKey: .toolCallId)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        status = try container.decode(ToolStatus.self, forKey: .status)
        content = try container.decodeIfPresent([ToolCallContent].self, forKey: .content) ?? []
        locations = try container.decodeIfPresent([ToolLocation].self, forKey: .locations)
        rawInput = try container.decodeIfPresent(AnyCodable.self, forKey: .rawInput)
        rawOutput = try container.decodeIfPresent(AnyCodable.self, forKey: .rawOutput)
        _meta = try container.decodeIfPresent([String: AnyCodable].self, forKey: ._meta)

        if let kindString = try? container.decode(String.self, forKey: .kind) {
            kind = ToolKind(rawValue: kindString)
        } else {
            kind = try container.decodeIfPresent(ToolKind.self, forKey: .kind)
        }
    }

    public init(
        toolCallId: String,
        status: ToolStatus,
        title: String? = nil,
        kind: ToolKind? = nil,
        content: [ToolCallContent] = [],
        locations: [ToolLocation]? = nil,
        rawInput: AnyCodable? = nil,
        rawOutput: AnyCodable? = nil,
        _meta: [String: AnyCodable]? = nil
    ) {
        self.toolCallId = toolCallId
        self.status = status
        self.title = title
        self.kind = kind
        self.content = content
        self.locations = locations
        self.rawInput = rawInput
        self.rawOutput = rawOutput
        self._meta = _meta
    }
}

public struct ToolCallUpdateDetails: Codable, Sendable {
    public let toolCallId: String
    public let status: ToolStatus?
    public let locations: [ToolLocation]?
    public let kind: ToolKind?
    public let title: String?
    public let content: [ToolCallContent]?
    public let rawInput: AnyCodable?
    public let rawOutput: AnyCodable?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case toolCallId
        case status, locations, kind, title, content
        case rawInput
        case rawOutput
        case _meta
    }

    public init(
        toolCallId: String,
        status: ToolStatus? = nil,
        locations: [ToolLocation]? = nil,
        kind: ToolKind? = nil,
        title: String? = nil,
        content: [ToolCallContent]? = nil,
        rawInput: AnyCodable? = nil,
        rawOutput: AnyCodable? = nil,
        _meta: [String: AnyCodable]? = nil
    ) {
        self.toolCallId = toolCallId
        self.status = status
        self.locations = locations
        self.kind = kind
        self.title = title
        self.content = content
        self.rawInput = rawInput
        self.rawOutput = rawOutput
        self._meta = _meta
    }
}

// MARK: - SessionUpdate Convenience Accessors

extension SessionUpdate {
    public var sessionUpdateType: String {
        switch self {
        case .userMessageChunk: return "user_message_chunk"
        case .agentMessageChunk: return "agent_message_chunk"
        case .agentThoughtChunk: return "agent_thought_chunk"
        case .toolCall: return "tool_call"
        case .toolCallUpdate: return "tool_call_update"
        case .plan: return "plan"
        case .availableCommandsUpdate: return "available_commands_update"
        case .currentModeUpdate: return "current_mode_update"
        case .configOptionUpdate: return "config_option_update"
        case .sessionInfoUpdate: return "session_info_update"
        case .usageUpdate: return "usage_update"
        }
    }

    public var content: AnyCodable? {
        switch self {
        case .userMessageChunk(let block),
             .agentMessageChunk(let block),
             .agentThoughtChunk(let block):
            return AnyCodable(block.toDictionary())
        case .toolCall(let call):
            let blocks = call.content.map { $0.toDictionary() }
            return AnyCodable(blocks)
        case .toolCallUpdate(let details):
            if let raw = details.rawOutput {
                return raw
            }
            return nil
        default:
            return nil
        }
    }

    public var toolCalls: [ToolCall]? {
        switch self {
        case .toolCall(let update):
            return [
                ToolCall(
                    toolCallId: update.toolCallId,
                    title: update.title ?? (update.kind?.rawValue.capitalized ?? "Tool"),
                    kind: update.kind,
                    status: update.status,
                    content: update.content,
                    locations: update.locations,
                    rawInput: update.rawInput,
                    rawOutput: update.rawOutput,
                    timestamp: Date()
                )
            ]
        default:
            return nil
        }
    }

    public var toolCallId: String? {
        switch self {
        case .toolCall(let update): return update.toolCallId
        case .toolCallUpdate(let details): return details.toolCallId
        default: return nil
        }
    }

    public var title: String? {
        switch self {
        case .toolCall(let update): return update.title
        case .toolCallUpdate: return nil
        default: return nil
        }
    }

    public var kind: ToolKind? {
        switch self {
        case .toolCall(let update): return update.kind
        default: return nil
        }
    }

    public var status: ToolStatus? {
        switch self {
        case .toolCall(let update): return update.status
        case .toolCallUpdate(let details): return details.status
        default: return nil
        }
    }

    public var locations: [ToolLocation]? {
        switch self {
        case .toolCall(let update): return update.locations
        case .toolCallUpdate(let details): return details.locations
        default: return nil
        }
    }

    public var rawInput: AnyCodable? {
        switch self {
        case .toolCall(let update): return update.rawInput
        default: return nil
        }
    }

    public var rawOutput: AnyCodable? {
        switch self {
        case .toolCall(let update): return update.rawOutput
        case .toolCallUpdate(let details): return details.rawOutput
        default: return nil
        }
    }

    public var plan: Plan? {
        switch self {
        case .plan(let plan): return plan
        default: return nil
        }
    }

    public var availableCommands: [AvailableCommand]? {
        switch self {
        case .availableCommandsUpdate(let commands): return commands
        default: return nil
        }
    }

    public var currentMode: String? {
        switch self {
        case .currentModeUpdate(let mode): return mode
        default: return nil
        }
    }

    public var configOptions: [SessionConfigOption]? {
        switch self {
        case .configOptionUpdate(let options): return options
        default: return nil
        }
    }

    public var sessionInfo: SessionInfoUpdate? {
        switch self {
        case .sessionInfoUpdate(let info): return info
        default: return nil
        }
    }

    public var usage: UsageUpdate? {
        switch self {
        case .usageUpdate(let usage): return usage
        default: return nil
        }
    }
}
