//
//  Tool.swift
//  ACPModel
//
//  Agent Client Protocol - Tool Call Types
//

import Foundation

// MARK: - Tool Call Content

public enum ToolCallContent: Codable, Sendable {
    case content(ContentBlock)
    case diff(ToolCallDiff)
    case terminal(ToolCallTerminal)

    enum CodingKeys: String, CodingKey {
        case type
        case content
        case path, oldText, newText
        case terminalId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "content":
            let block = try container.decode(ContentBlock.self, forKey: .content)
            self = .content(block)
        case "diff":
            let diff = try ToolCallDiff(from: decoder)
            self = .diff(diff)
        case "terminal":
            let terminal = try ToolCallTerminal(from: decoder)
            self = .terminal(terminal)
        default:
            if let text = try? container.decodeIfPresent(String.self, forKey: .content) {
                self = .content(.text(TextContent(text: text)))
            } else {
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown tool call content type: \(type)")
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .content(let block):
            try container.encode("content", forKey: .type)
            try container.encode(block, forKey: .content)
        case .diff(let diff):
            try container.encode("diff", forKey: .type)
            try diff.encode(to: encoder)
        case .terminal(let terminal):
            try container.encode("terminal", forKey: .type)
            try terminal.encode(to: encoder)
        }
    }

    public var displayText: String? {
        switch self {
        case .content(let block):
            if case .text(let text) = block {
                return text.text
            }
            return nil
        case .diff(let diff):
            return "Modified: \(diff.path)"
        case .terminal(let terminal):
            return "Terminal: \(terminal.terminalId)"
        }
    }

    public var asContentBlock: ContentBlock? {
        switch self {
        case .content(let block):
            return block
        case .diff(let diff):
            var text = "File: \(diff.path)\n"
            if let old = diff.oldText {
                text += "--- old\n\(old)\n"
            }
            text += "+++ new\n\(diff.newText)"
            return .text(TextContent(text: text))
        case .terminal:
            return nil
        }
    }

    public func toDictionary() -> [String: any Sendable] {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: any Sendable] else {
            return [:]
        }
        return dict
    }
}

public struct ToolCallDiff: Codable, Sendable {
    public let path: String
    public let oldText: String?
    public let newText: String

    enum CodingKeys: String, CodingKey {
        case path, oldText, newText
    }

    public init(path: String, oldText: String? = nil, newText: String) {
        self.path = path
        self.oldText = oldText
        self.newText = newText
    }
}

public struct ToolCallTerminal: Codable, Sendable {
    public let terminalId: String

    enum CodingKeys: String, CodingKey {
        case terminalId
    }

    public init(terminalId: String) {
        self.terminalId = terminalId
    }
}

// MARK: - Tool Calls

public struct ToolCall: Codable, Identifiable, Sendable {
    public let toolCallId: String
    public var title: String
    public var kind: ToolKind?
    public var status: ToolStatus
    public var content: [ToolCallContent]
    public var locations: [ToolLocation]?
    public var rawInput: AnyCodable?
    public var rawOutput: AnyCodable?
    public var timestamp: Date = Date()
    public var iterationId: String?
    public var parentToolCallId: String?

    public var id: String { toolCallId }

    enum CodingKeys: String, CodingKey {
        case toolCallId
        case title, kind, status, content, locations
        case rawInput
        case rawOutput
    }

    public var resolvedKind: ToolKind {
        kind ?? .other
    }

    public var contentBlocks: [ContentBlock] {
        content.compactMap { $0.asContentBlock }
    }

    public var copyableOutputText: String? {
        let outputs = content.compactMap { $0.copyableText }
        let result = outputs.joined(separator: "\n\n")
        return result.isEmpty ? nil : result
    }

    public init(
        toolCallId: String,
        title: String,
        kind: ToolKind? = nil,
        status: ToolStatus,
        content: [ToolCallContent],
        locations: [ToolLocation]? = nil,
        rawInput: AnyCodable? = nil,
        rawOutput: AnyCodable? = nil,
        timestamp: Date = Date(),
        iterationId: String? = nil,
        parentToolCallId: String? = nil
    ) {
        self.toolCallId = toolCallId
        self.title = title
        self.kind = kind
        self.status = status
        self.content = content
        self.locations = locations
        self.rawInput = rawInput
        self.rawOutput = rawOutput
        self.timestamp = timestamp
        self.iterationId = iterationId
        self.parentToolCallId = parentToolCallId
    }
}

extension ToolCallContent {
    fileprivate var copyableText: String? {
        switch self {
        case .content(let block):
            if case .text(let textContent) = block {
                return textContent.text
            }
            return nil
        case .diff(let diff):
            return diff.newText
        case .terminal:
            return nil
        }
    }
}

public enum ToolKind: String, Codable, Sendable {
    case read
    case edit
    case delete
    case move
    case search
    case execute
    case think
    case fetch
    case switchMode = "switch_mode"
    case plan
    case exitPlanMode = "exit_plan_mode"
    case other

    public var symbolName: String {
        switch self {
        case .read: return "doc.text"
        case .edit: return "pencil"
        case .delete: return "trash"
        case .move: return "arrow.right.doc.on.clipboard"
        case .search: return "magnifyingglass"
        case .execute: return "terminal"
        case .think: return "brain"
        case .fetch: return "arrow.down.circle"
        case .switchMode: return "arrow.left.arrow.right"
        case .plan: return "list.bullet.clipboard"
        case .exitPlanMode: return "checkmark.circle"
        case .other: return "wrench.and.screwdriver"
        }
    }
}

public enum ToolStatus: String, Codable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed
    case failed
}

public struct ToolLocation: Codable, Sendable {
    public let path: String?
    public let line: Int?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case path, line, _meta
    }

    public init(path: String? = nil, line: Int? = nil, _meta: [String: AnyCodable]? = nil) {
        self.path = path
        self.line = line
        self._meta = _meta
    }
}

// MARK: - Available Commands

public struct AvailableCommand: Codable, Sendable {
    public let name: String
    public let description: String
    public let input: CommandInputSpec?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case name, description, input, _meta
    }

    public init(name: String, description: String, input: CommandInputSpec? = nil, _meta: [String: AnyCodable]? = nil) {
        self.name = name
        self.description = description
        self.input = input
        self._meta = _meta
    }
}

public struct CommandInputSpec: Codable, Sendable {
    public let type: String?
    public let hint: String?
    public let properties: [String: AnyCodable]?
    public let required: [String]?

    public init(type: String? = nil, hint: String? = nil, properties: [String: AnyCodable]? = nil, required: [String]? = nil) {
        self.type = type
        self.hint = hint
        self.properties = properties
        self.required = required
    }
}

// MARK: - Agent Plan

public enum PlanPriority: String, Codable, Sendable {
    case low
    case medium
    case high
}

public enum PlanEntryStatus: String, Codable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed
    case cancelled
}

public struct PlanEntry: Codable, Equatable, Sendable {
    public let content: String
    public let priority: PlanPriority
    public let status: PlanEntryStatus
    public let activeForm: String?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case content, priority, status, activeForm, _meta
    }

    public static func == (lhs: PlanEntry, rhs: PlanEntry) -> Bool {
        lhs.content == rhs.content &&
        lhs.priority == rhs.priority &&
        lhs.status == rhs.status &&
        lhs.activeForm == rhs.activeForm
    }

    public init(content: String, priority: PlanPriority, status: PlanEntryStatus, activeForm: String? = nil, _meta: [String: AnyCodable]? = nil) {
        self.content = content
        self.priority = priority
        self.status = status
        self.activeForm = activeForm
        self._meta = _meta
    }
}

public struct Plan: Codable, Equatable, Sendable {
    public let entries: [PlanEntry]

    public init(entries: [PlanEntry]) {
        self.entries = entries
    }
}
