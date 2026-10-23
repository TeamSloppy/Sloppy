import Foundation

public enum SystemLogLevel: String, Codable, Sendable, Equatable, CaseIterable {
    case trace
    case debug
    case info
    case warning
    case error
    case fatal
}

public struct SystemLogEntry: Codable, Sendable, Equatable {
    public var timestamp: Date
    public var level: SystemLogLevel
    public var label: String
    public var message: String
    public var source: String
    public var metadata: [String: String]

    public init(
        timestamp: Date,
        level: SystemLogLevel,
        label: String,
        message: String,
        source: String = "",
        metadata: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.level = level
        self.label = label
        self.message = message
        self.source = source
        self.metadata = metadata
    }
}

public struct SystemLogsResponse: Codable, Sendable, Equatable {
    public var filePath: String
    public var entries: [SystemLogEntry]

    public init(filePath: String, entries: [SystemLogEntry]) {
        self.filePath = filePath
        self.entries = entries
    }
}

public struct IssueReportRequest: Codable, Sendable, Equatable {
    public var logLimit: Int?

    public init(logLimit: Int? = nil) {
        self.logLimit = logLimit
    }
}

public struct IssueReportResponse: Codable, Sendable, Equatable {
    public var issueUrl: String
    public var logs: String
    public var logsUrl: String?
    public var logEntryCount: Int
    public var redactionCount: Int
    public var truncated: Bool

    private enum CodingKeys: String, CodingKey {
        case issueUrl
        case logs
        case logsUrl
        case logEntryCount
        case redactionCount
        case truncated
    }

    public init(
        issueUrl: String,
        logs: String,
        logsUrl: String? = nil,
        logEntryCount: Int,
        redactionCount: Int,
        truncated: Bool
    ) {
        self.issueUrl = issueUrl
        self.logs = logs
        self.logsUrl = logsUrl
        self.logEntryCount = logEntryCount
        self.redactionCount = redactionCount
        self.truncated = truncated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        issueUrl = try container.decode(String.self, forKey: .issueUrl)
        logs = try container.decodeIfPresent(String.self, forKey: .logs) ?? ""
        logsUrl = try container.decodeIfPresent(String.self, forKey: .logsUrl)
        logEntryCount = try container.decode(Int.self, forKey: .logEntryCount)
        redactionCount = try container.decode(Int.self, forKey: .redactionCount)
        truncated = try container.decode(Bool.self, forKey: .truncated)
    }
}

public struct VisorReadyResponse: Codable, Sendable {
    public var ready: Bool

    public init(ready: Bool) {
        self.ready = ready
    }
}

public struct VisorChatRequest: Codable, Sendable {
    public var question: String

    public init(question: String) {
        self.question = question
    }
}

public struct VisorChatResponse: Codable, Sendable {
    public var answer: String

    public init(answer: String) {
        self.answer = answer
    }
}
