//
//  Session.swift
//  ACPModel
//
//  Agent Client Protocol - Core Session Types
//

import Foundation

// MARK: - Session ID

public struct SessionId: Codable, Hashable, Sendable {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - Client & Agent Info

public struct ClientInfo: Codable, Sendable {
    public let name: String
    public let title: String?
    public let version: String?
    public let _meta: [String: AnyCodable]?

    public init(name: String, title: String? = nil, version: String? = nil, _meta: [String: AnyCodable]? = nil) {
        self.name = name
        self.title = title
        self.version = version
        self._meta = _meta
    }
}

public struct AgentInfo: Codable, Sendable {
    public let name: String
    public let version: String
    public let title: String?
    public let _meta: [String: AnyCodable]?

    public init(name: String, version: String, title: String? = nil, _meta: [String: AnyCodable]? = nil) {
        self.name = name
        self.version = version
        self.title = title
        self._meta = _meta
    }
}

// MARK: - Stop Reason

public enum StopReason: String, Codable, Sendable {
    case endTurn = "end_turn"
    case maxTokens = "max_tokens"
    case maxTurnRequests = "max_turn_requests"
    case refusal = "refusal"
    case cancelled = "cancelled"
}

// MARK: - Session Mode Types

public enum SessionMode: String, Codable, Sendable {
    case code
    case chat
    case ask
}

public struct ModeInfo: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let description: String?

    public init(id: String, name: String, description: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
    }
}

public struct ModesInfo: Codable, Sendable {
    public let currentModeId: String
    public let availableModes: [ModeInfo]

    enum CodingKeys: String, CodingKey {
        case currentModeId = "currentModeId"
        case availableModes = "availableModes"
    }

    public init(currentModeId: String, availableModes: [ModeInfo]) {
        self.currentModeId = currentModeId
        self.availableModes = availableModes
    }
}

// MARK: - Model Selection Types

public struct ModelInfo: Codable, Hashable, Sendable {
    public let modelId: String
    public let name: String
    public let description: String?

    enum CodingKeys: String, CodingKey {
        case modelId = "modelId"
        case name
        case description
    }

    public init(modelId: String, name: String, description: String? = nil) {
        self.modelId = modelId
        self.name = name
        self.description = description
    }
}

public struct ModelsInfo: Codable, Sendable {
    public let currentModelId: String
    public let availableModels: [ModelInfo]

    enum CodingKeys: String, CodingKey {
        case currentModelId = "currentModelId"
        case availableModels = "availableModels"
    }

    public init(currentModelId: String, availableModels: [ModelInfo]) {
        self.currentModelId = currentModelId
        self.availableModels = availableModels
    }
}

// MARK: - Authentication Types

public struct AuthMethod: Codable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let _meta: [String: AnyCodable]?

    public init(id: String, name: String, description: String? = nil, _meta: [String: AnyCodable]? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self._meta = _meta
    }
}

// MARK: - Session Listing

public struct SessionInfo: Codable, Sendable {
    public let sessionId: SessionId
    public let cwd: String
    public let title: String?
    public let updatedAt: String?
    public let _meta: [String: AnyCodable]?

    public init(
        sessionId: SessionId,
        cwd: String,
        title: String? = nil,
        updatedAt: String? = nil,
        _meta: [String: AnyCodable]? = nil
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.title = title
        self.updatedAt = updatedAt
        self._meta = _meta
    }
}

// MARK: - MCP Server Configuration

public enum MCPServerConfig: Codable, Sendable {
    case stdio(StdioServerConfig)
    case http(HTTPServerConfig)
    case sse(SSEServerConfig)

    enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "stdio":
            self = .stdio(try StdioServerConfig(from: decoder))
        case "http":
            self = .http(try HTTPServerConfig(from: decoder))
        case "sse":
            self = .sse(try SSEServerConfig(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown MCP server type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .stdio(let config):
            try container.encode("stdio", forKey: .type)
            try config.encode(to: encoder)
        case .http(let config):
            try container.encode("http", forKey: .type)
            try config.encode(to: encoder)
        case .sse(let config):
            try container.encode("sse", forKey: .type)
            try config.encode(to: encoder)
        }
    }
}

public struct StdioServerConfig: Codable, Sendable {
    public let name: String
    public let command: String
    public let args: [String]
    public let env: [EnvVariable]
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case name, command, args, env, _meta
    }

    public init(name: String, command: String, args: [String], env: [EnvVariable], _meta: [String: AnyCodable]? = nil) {
        self.name = name
        self.command = command
        self.args = args
        self.env = env
        self._meta = _meta
    }
}

public struct HTTPServerConfig: Codable, Sendable {
    public let name: String
    public let url: String
    public let headers: [HTTPHeader]?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case name, url, headers, _meta
    }

    public init(name: String, url: String, headers: [HTTPHeader]? = nil, _meta: [String: AnyCodable]? = nil) {
        self.name = name
        self.url = url
        self.headers = headers
        self._meta = _meta
    }
}

public struct SSEServerConfig: Codable, Sendable {
    public let name: String
    public let url: String
    public let headers: [HTTPHeader]?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case name, url, headers, _meta
    }

    public init(name: String, url: String, headers: [HTTPHeader]? = nil, _meta: [String: AnyCodable]? = nil) {
        self.name = name
        self.url = url
        self.headers = headers
        self._meta = _meta
    }
}

public struct HTTPHeader: Codable, Sendable {
    public let name: String
    public let value: String
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case name, value, _meta
    }

    public init(name: String, value: String, _meta: [String: AnyCodable]? = nil) {
        self.name = name
        self.value = value
        self._meta = _meta
    }
}
