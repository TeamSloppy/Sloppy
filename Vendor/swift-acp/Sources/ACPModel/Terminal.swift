//
//  Terminal.swift
//  ACPModel
//
//  Agent Client Protocol - Terminal Types
//

import Foundation

// MARK: - Terminal Types

public struct TerminalId: Codable, Hashable, Sendable {
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

// MARK: - Environment Variable

public struct EnvVariable: Codable, Sendable {
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

// MARK: - Terminal Exit Status

public struct TerminalExitStatus: Codable, Sendable {
    public let exitCode: Int?
    public let signal: String?
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case exitCode
        case signal
        case _meta
    }

    public init(exitCode: Int? = nil, signal: String? = nil, _meta: [String: AnyCodable]? = nil) {
        self.exitCode = exitCode
        self.signal = signal
        self._meta = _meta
    }
}

// MARK: - Create Terminal

public struct CreateTerminalRequest: Codable, Sendable {
    public let command: String
    public let args: [String]?
    public let cwd: String?
    public let env: [EnvVariable]?
    public let outputByteLimit: Int?
    public let sessionId: String
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case command, args, cwd, env, sessionId
        case outputByteLimit = "outputByteLimit"
        case _meta
    }

    public init(command: String, sessionId: String, args: [String]? = nil, cwd: String? = nil, env: [EnvVariable]? = nil, outputByteLimit: Int? = nil, _meta: [String: AnyCodable]? = nil) {
        self.command = command
        self.sessionId = sessionId
        self.args = args
        self.cwd = cwd
        self.env = env
        self.outputByteLimit = outputByteLimit
        self._meta = _meta
    }
}

public struct CreateTerminalResponse: Codable, Sendable {
    public let terminalId: TerminalId
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case terminalId
        case _meta
    }

    public init(terminalId: TerminalId, _meta: [String: AnyCodable]? = nil) {
        self.terminalId = terminalId
        self._meta = _meta
    }
}

// MARK: - Terminal Output

public struct TerminalOutputRequest: Codable, Sendable {
    public let terminalId: TerminalId
    public let sessionId: String
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case terminalId
        case sessionId
        case _meta
    }

    public init(terminalId: TerminalId, sessionId: String, _meta: [String: AnyCodable]? = nil) {
        self.terminalId = terminalId
        self.sessionId = sessionId
        self._meta = _meta
    }
}

public struct TerminalOutputResponse: Codable, Sendable {
    public let output: String
    public let exitStatus: TerminalExitStatus?
    public let truncated: Bool
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case output, truncated, exitStatus
        case _meta
    }

    public init(output: String, exitStatus: TerminalExitStatus? = nil, truncated: Bool, _meta: [String: AnyCodable]? = nil) {
        self.output = output
        self.exitStatus = exitStatus
        self.truncated = truncated
        self._meta = _meta
    }
}

// MARK: - Wait for Exit

public struct WaitForExitRequest: Codable, Sendable {
    public let terminalId: TerminalId
    public let sessionId: String
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case terminalId
        case sessionId
        case _meta
    }

    public init(terminalId: TerminalId, sessionId: String, _meta: [String: AnyCodable]? = nil) {
        self.terminalId = terminalId
        self.sessionId = sessionId
        self._meta = _meta
    }
}

public struct WaitForExitResponse: Codable, Sendable {
    public let exitCode: Int?
    public let signal: String?
    public let _meta: [String: AnyCodable]?

    public init(exitCode: Int? = nil, signal: String? = nil, _meta: [String: AnyCodable]? = nil) {
        self.exitCode = exitCode
        self.signal = signal
        self._meta = _meta
    }
}

// MARK: - Kill Terminal

public struct KillTerminalRequest: Codable, Sendable {
    public let terminalId: TerminalId
    public let sessionId: String
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case terminalId
        case sessionId
        case _meta
    }

    public init(terminalId: TerminalId, sessionId: String, _meta: [String: AnyCodable]? = nil) {
        self.terminalId = terminalId
        self.sessionId = sessionId
        self._meta = _meta
    }
}

public struct KillTerminalResponse: Codable, Sendable {
    public let success: Bool
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case success, _meta
    }

    public init(success: Bool, _meta: [String: AnyCodable]? = nil) {
        self.success = success
        self._meta = _meta
    }
}

// MARK: - Release Terminal

public struct ReleaseTerminalRequest: Codable, Sendable {
    public let terminalId: TerminalId
    public let sessionId: String
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case terminalId
        case sessionId
        case _meta
    }

    public init(terminalId: TerminalId, sessionId: String, _meta: [String: AnyCodable]? = nil) {
        self.terminalId = terminalId
        self.sessionId = sessionId
        self._meta = _meta
    }
}

public struct ReleaseTerminalResponse: Codable, Sendable {
    public let success: Bool
    public let _meta: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case success, _meta
    }

    public init(success: Bool, _meta: [String: AnyCodable]? = nil) {
        self.success = success
        self._meta = _meta
    }
}
