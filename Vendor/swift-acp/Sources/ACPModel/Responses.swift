//
//  Responses.swift
//  ACPModel
//
//  Agent Client Protocol - Response Types
//

import Foundation

// MARK: - Initialize

public struct InitializeResponse: Codable, Sendable {
    public let protocolVersion: Int
    public let agentInfo: AgentInfo?
    public let agentCapabilities: AgentCapabilities
    public let authMethods: [AuthMethod]?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case agentInfo
        case agentCapabilities
        case authMethods
        case _meta
    }

    public init(
        protocolVersion: Int,
        agentCapabilities: AgentCapabilities,
        agentInfo: AgentInfo? = nil,
        authMethods: [AuthMethod]? = nil,
        _meta: [String: AnyCodable]? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.agentCapabilities = agentCapabilities
        self.agentInfo = agentInfo
        self.authMethods = authMethods
        self._meta = _meta
    }
}

// MARK: - Session Management

public struct NewSessionResponse: Codable, Sendable {
    public let sessionId: SessionId
    public let modes: ModesInfo?
    public let models: ModelsInfo?
    public let configOptions: [SessionConfigOption]?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case sessionId
        case modes
        case models
        case configOptions
        case _meta
    }

    public init(
        sessionId: SessionId,
        modes: ModesInfo? = nil,
        models: ModelsInfo? = nil,
        configOptions: [SessionConfigOption]? = nil,
        _meta: [String: AnyCodable]? = nil
    ) {
        self.sessionId = sessionId
        self.modes = modes
        self.models = models
        self.configOptions = configOptions
        self._meta = _meta
    }
}

public struct LoadSessionResponse: Codable, Sendable {
    public let sessionId: SessionId
    public let modes: ModesInfo?
    public let models: ModelsInfo?
    public let configOptions: [SessionConfigOption]?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case sessionId
        case modes
        case models
        case configOptions
        case _meta
    }

    public init(
        sessionId: SessionId,
        modes: ModesInfo? = nil,
        models: ModelsInfo? = nil,
        configOptions: [SessionConfigOption]? = nil,
        _meta: [String: AnyCodable]? = nil
    ) {
        self.sessionId = sessionId
        self.modes = modes
        self.models = models
        self.configOptions = configOptions
        self._meta = _meta
    }
}

public struct ListSessionsResponse: Codable, Sendable {
    public let sessions: [SessionInfo]
    public let nextCursor: String?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case sessions
        case nextCursor
        case _meta
    }

    public init(sessions: [SessionInfo], nextCursor: String? = nil, _meta: [String: AnyCodable]? = nil) {
        self.sessions = sessions
        self.nextCursor = nextCursor
        self._meta = _meta
    }
}

// MARK: - Prompt

public struct SessionPromptResponse: Codable, Sendable {
    public let stopReason: StopReason
    public let usage: Usage?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case stopReason
        case usage
        case _meta
    }

    public init(stopReason: StopReason, usage: Usage? = nil, _meta: [String: AnyCodable]? = nil) {
        self.stopReason = stopReason
        self.usage = usage
        self._meta = _meta
    }
}

// MARK: - Mode & Model Selection

public struct SetModeResponse: Codable, Sendable {
    public let success: Bool
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case success
        case _meta
    }

    public init(success: Bool, _meta: [String: AnyCodable]? = nil) {
        self.success = success
        self._meta = _meta
    }
}

public struct SetModelResponse: Codable, Sendable {
    public let success: Bool
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case success
        case _meta
    }

    public init(success: Bool, _meta: [String: AnyCodable]? = nil) {
        self.success = success
        self._meta = _meta
    }
}

public struct SetSessionConfigOptionResponse: Codable, Sendable {
    public let configOptions: [SessionConfigOption]
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case configOptions
        case _meta
    }

    public init(configOptions: [SessionConfigOption], _meta: [String: AnyCodable]? = nil) {
        self.configOptions = configOptions
        self._meta = _meta
    }
}

// MARK: - Authentication

public struct AuthenticateResponse: Codable, Sendable {
    public let success: Bool
    public let error: String?
    public let _meta: [String: AnyCodable]?

    public init(success: Bool, error: String? = nil, _meta: [String: AnyCodable]? = nil) {
        self.success = success
        self.error = error
        self._meta = _meta
    }
}

// MARK: - File System

public struct ReadTextFileResponse: Codable, Sendable {
    public let content: String
    public let totalLines: Int?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case content
        case totalLines = "total_lines"
        case _meta
    }

    public init(content: String, totalLines: Int? = nil, _meta: [String: AnyCodable]? = nil) {
        self.content = content
        self.totalLines = totalLines
        self._meta = _meta
    }
}

public struct WriteTextFileResponse: Codable, Sendable {
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case _meta
    }

    public init(_meta: [String: AnyCodable]? = nil) {
        self._meta = _meta
    }
}
