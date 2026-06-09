//
//  Requests.swift
//  ACPModel
//
//  Agent Client Protocol - Request Types
//

import Foundation

// MARK: - Initialize

public struct InitializeRequest: Codable, Sendable {
    public let protocolVersion: Int
    public let clientCapabilities: ClientCapabilities
    public let clientInfo: ClientInfo?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case clientCapabilities
        case clientInfo
        case _meta
    }

    public init(
        protocolVersion: Int,
        clientCapabilities: ClientCapabilities,
        clientInfo: ClientInfo? = nil,
        _meta: [String: AnyCodable]? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.clientCapabilities = clientCapabilities
        self.clientInfo = clientInfo
        self._meta = _meta
    }
}

// MARK: - Session Management

public struct NewSessionRequest: Codable, Sendable {
    public let cwd: String
    public let mcpServers: [MCPServerConfig]
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case cwd
        case mcpServers
        case _meta
    }

    public init(cwd: String, mcpServers: [MCPServerConfig] = [], _meta: [String: AnyCodable]? = nil)
    {
        self.cwd = cwd
        self.mcpServers = mcpServers
        self._meta = _meta
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cwd = try container.decode(String.self, forKey: .cwd)
        mcpServers = try container.decodeIfPresent([MCPServerConfig].self, forKey: .mcpServers) ?? []
        _meta = try container.decodeIfPresent([String: AnyCodable].self, forKey: ._meta)
    }
}

public struct AuthorizationRequest: Codable, Sendable {

}

public struct LoadSessionRequest: Codable, Sendable {
    public let sessionId: SessionId
    public let cwd: String?
    public let mcpServers: [MCPServerConfig]?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case sessionId
        case cwd
        case mcpServers
        case _meta
    }

    public init(
        sessionId: SessionId,
        cwd: String? = nil,
        mcpServers: [MCPServerConfig]? = nil,
        _meta: [String: AnyCodable]? = nil
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.mcpServers = mcpServers
        self._meta = _meta
    }
}

public struct ListSessionsRequest: Codable, Sendable {
    public let cwd: String?
    public let cursor: String?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case cwd
        case cursor
        case _meta
    }

    public init(cwd: String? = nil, cursor: String? = nil, _meta: [String: AnyCodable]? = nil) {
        self.cwd = cwd
        self.cursor = cursor
        self._meta = _meta
    }
}

public struct CancelSessionRequest: Codable, Sendable {
    public let sessionId: SessionId
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case sessionId
        case _meta
    }

    public init(sessionId: SessionId, _meta: [String: AnyCodable]? = nil) {
        self.sessionId = sessionId
        self._meta = _meta
    }
}

// MARK: - Prompt

public struct SessionPromptRequest: Codable, Sendable {
    public let sessionId: SessionId
    public let prompt: [ContentBlock]
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case sessionId
        case prompt
        case _meta
    }

    public init(sessionId: SessionId, prompt: [ContentBlock], _meta: [String: AnyCodable]? = nil) {
        self.sessionId = sessionId
        self.prompt = prompt
        self._meta = _meta
    }
}

// MARK: - Mode & Model Selection

public struct SetModeRequest: Codable, Sendable {
    public let sessionId: SessionId
    public let modeId: String
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case sessionId
        case modeId
        case _meta
    }

    public init(sessionId: SessionId, modeId: String, _meta: [String: AnyCodable]? = nil) {
        self.sessionId = sessionId
        self.modeId = modeId
        self._meta = _meta
    }
}

public struct SetModelRequest: Codable, Sendable {
    public let sessionId: SessionId
    public let modelId: String
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case sessionId
        case modelId
        case _meta
    }

    public init(sessionId: SessionId, modelId: String, _meta: [String: AnyCodable]? = nil) {
        self.sessionId = sessionId
        self.modelId = modelId
        self._meta = _meta
    }
}

public struct SetSessionConfigOptionRequest: Codable, Sendable {
    public let sessionId: SessionId
    public let configId: SessionConfigId
    public let value: SessionConfigOptionValue
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case sessionId
        case configId
        case type
        case value
        case _meta
    }

    public init(
        sessionId: SessionId,
        configId: SessionConfigId,
        value: SessionConfigOptionValue,
        _meta: [String: AnyCodable]? = nil
    ) {
        self.sessionId = sessionId
        self.configId = configId
        self.value = value
        self._meta = _meta
    }

    public init(
        sessionId: SessionId, configId: SessionConfigId, value: SessionConfigValueId,
        _meta: [String: AnyCodable]? = nil
    ) {
        self.init(sessionId: sessionId, configId: configId, value: .select(value), _meta: _meta)
    }

    public init(
        sessionId: SessionId, configId: SessionConfigId, value: Bool,
        _meta: [String: AnyCodable]? = nil
    ) {
        self.init(sessionId: sessionId, configId: configId, value: .boolean(value), _meta: _meta)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(SessionId.self, forKey: .sessionId)
        configId = try container.decode(SessionConfigId.self, forKey: .configId)
        _meta = try container.decodeIfPresent([String: AnyCodable].self, forKey: ._meta)

        if try container.decodeIfPresent(String.self, forKey: .type) == "boolean" {
            value = .boolean(try container.decode(Bool.self, forKey: .value))
        } else {
            value = .select(try container.decode(SessionConfigValueId.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(configId, forKey: .configId)
        try container.encodeIfPresent(_meta, forKey: ._meta)

        switch value {
        case .select(let valueId):
            try container.encode(valueId, forKey: .value)
        case .boolean(let booleanValue):
            try container.encode("boolean", forKey: .type)
            try container.encode(booleanValue, forKey: .value)
        }
    }
}

// MARK: - Authentication

public struct AuthenticateRequest: Codable, Sendable {
    public let methodId: String
    public let credentials: [String: String]?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case methodId
        case credentials
        case _meta
    }

    public init(
        methodId: String, credentials: [String: String]? = nil, _meta: [String: AnyCodable]? = nil
    ) {
        self.methodId = methodId
        self.credentials = credentials
        self._meta = _meta
    }
}

// MARK: - File System

public struct ReadTextFileRequest: Codable, Sendable {
    public let path: String
    public let line: Int?
    public let limit: Int?
    public let sessionId: String
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case path, line, limit, sessionId, _meta
    }

    public init(
        path: String, sessionId: String, line: Int? = nil, limit: Int? = nil,
        _meta: [String: AnyCodable]? = nil
    ) {
        self.path = path
        self.sessionId = sessionId
        self.line = line
        self.limit = limit
        self._meta = _meta
    }
}

public struct WriteTextFileRequest: Codable, Sendable {
    public let path: String
    public let content: String
    public let sessionId: String
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case path, content, sessionId, _meta
    }

    public init(
        path: String, content: String, sessionId: String, _meta: [String: AnyCodable]? = nil
    ) {
        self.path = path
        self.content = content
        self.sessionId = sessionId
        self._meta = _meta
    }
}
