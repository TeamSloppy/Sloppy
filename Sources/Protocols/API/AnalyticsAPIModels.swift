import Foundation

public enum ProjectAnalyticsWindow: String, Codable, Sendable, Equatable, CaseIterable {
    case last24h = "24h"
    case last7d = "7d"
    case all = "all"
}

public struct ProjectAnalyticsQuery: Codable, Sendable, Equatable {
    public var window: ProjectAnalyticsWindow
    public var from: Date?
    public var to: Date?

    public init(window: ProjectAnalyticsWindow = .last24h, from: Date? = nil, to: Date? = nil) {
        self.window = window
        self.from = from
        self.to = to
    }
}

public struct ProjectTaskOutcomeCounts: Codable, Sendable, Equatable {
    public var total: Int
    public var success: Int
    public var failed: Int
    public var interrupted: Int

    public init(total: Int = 0, success: Int = 0, failed: Int = 0, interrupted: Int = 0) {
        self.total = total
        self.success = success
        self.failed = failed
        self.interrupted = interrupted
    }
}

public struct ProjectToolStats: Codable, Sendable, Equatable {
    public struct ToolAggregate: Codable, Sendable, Equatable {
        public var tool: String
        public var calls: Int
        public var failures: Int
        public var avgDurationMs: Int?

        public init(tool: String, calls: Int = 0, failures: Int = 0, avgDurationMs: Int? = nil) {
            self.tool = tool
            self.calls = calls
            self.failures = failures
            self.avgDurationMs = avgDurationMs
        }
    }

    public var totalCalls: Int
    public var totalFailures: Int
    public var failureRate: Double
    public var avgDurationMs: Int?
    public var p50DurationMs: Int?
    public var p95DurationMs: Int?
    public var topToolsByTime: [ToolAggregate]
    public var topFailingTools: [ToolAggregate]

    public init(
        totalCalls: Int = 0,
        totalFailures: Int = 0,
        failureRate: Double = 0,
        avgDurationMs: Int? = nil,
        p50DurationMs: Int? = nil,
        p95DurationMs: Int? = nil,
        topToolsByTime: [ToolAggregate] = [],
        topFailingTools: [ToolAggregate] = []
    ) {
        self.totalCalls = totalCalls
        self.totalFailures = totalFailures
        self.failureRate = failureRate
        self.avgDurationMs = avgDurationMs
        self.p50DurationMs = p50DurationMs
        self.p95DurationMs = p95DurationMs
        self.topToolsByTime = topToolsByTime
        self.topFailingTools = topFailingTools
    }
}

public struct ProjectTokenUsageTotals: Codable, Sendable, Equatable {
    public var totalPromptTokens: Int
    public var totalCompletionTokens: Int
    public var totalTokens: Int
    public var totalCachedInputTokens: Int
    public var totalCacheCreationInputTokens: Int
    public var totalReasoningTokens: Int

    public init(
        totalPromptTokens: Int = 0,
        totalCompletionTokens: Int = 0,
        totalTokens: Int = 0,
        totalCachedInputTokens: Int = 0,
        totalCacheCreationInputTokens: Int = 0,
        totalReasoningTokens: Int = 0
    ) {
        self.totalPromptTokens = totalPromptTokens
        self.totalCompletionTokens = totalCompletionTokens
        self.totalTokens = totalTokens
        self.totalCachedInputTokens = totalCachedInputTokens
        self.totalCacheCreationInputTokens = totalCacheCreationInputTokens
        self.totalReasoningTokens = totalReasoningTokens
    }
}

public struct ProjectAnalyticsResponse: Codable, Sendable, Equatable {
    public var projectId: String
    public var window: ProjectAnalyticsWindow
    public var from: Date?
    public var to: Date?

    /// Keys are `EventEnvelope.messageType` raw values (e.g. "channel.route.decided").
    public var runtimeEventCounts: [String: Int]

    public var taskOutcomes: ProjectTaskOutcomeCounts
    public var tools: ProjectToolStats
    public var tokenUsage: ProjectTokenUsageTotals

    public var isPartial: Bool
    public var notes: [String]

    public init(
        projectId: String,
        window: ProjectAnalyticsWindow,
        from: Date? = nil,
        to: Date? = nil,
        runtimeEventCounts: [String: Int] = [:],
        taskOutcomes: ProjectTaskOutcomeCounts = .init(),
        tools: ProjectToolStats = .init(),
        tokenUsage: ProjectTokenUsageTotals = .init(),
        isPartial: Bool = false,
        notes: [String] = []
    ) {
        self.projectId = projectId
        self.window = window
        self.from = from
        self.to = to
        self.runtimeEventCounts = runtimeEventCounts
        self.taskOutcomes = taskOutcomes
        self.tools = tools
        self.tokenUsage = tokenUsage
        self.isPartial = isPartial
        self.notes = notes
    }
}

/// Represents a persisted token usage record.
public struct TokenUsageRecord: Codable, Sendable, Equatable {
    public var id: String
    public var channelId: String
    public var taskId: String?
    public var promptTokens: Int
    public var completionTokens: Int
    public var totalTokens: Int
    public var cachedInputTokens: Int
    public var cacheCreationInputTokens: Int
    public var reasoningTokens: Int
    public var createdAt: Date

    public init(
        id: String,
        channelId: String,
        taskId: String? = nil,
        promptTokens: Int,
        completionTokens: Int,
        totalTokens: Int,
        cachedInputTokens: Int = 0,
        cacheCreationInputTokens: Int = 0,
        reasoningTokens: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.channelId = channelId
        self.taskId = taskId
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.reasoningTokens = reasoningTokens
        self.createdAt = createdAt
    }
}

/// Response for token usage list endpoint with aggregates.
public struct TokenUsageResponse: Codable, Sendable {
    public var items: [TokenUsageRecord]
    public var totalPromptTokens: Int
    public var totalCompletionTokens: Int
    public var totalTokens: Int
    public var totalCachedInputTokens: Int
    public var totalCacheCreationInputTokens: Int
    public var totalReasoningTokens: Int
    /// Optional spend from semantic-decision calls associated with this channel.
    public var semanticDecisionUsage: SemanticDecisionUsage?

    public init(
        items: [TokenUsageRecord],
        totalPromptTokens: Int = 0,
        totalCompletionTokens: Int = 0,
        totalTokens: Int = 0,
        totalCachedInputTokens: Int = 0,
        totalCacheCreationInputTokens: Int = 0,
        totalReasoningTokens: Int = 0,
        semanticDecisionUsage: SemanticDecisionUsage? = nil
    ) {
        self.items = items
        self.totalPromptTokens = totalPromptTokens
        self.totalCompletionTokens = totalCompletionTokens
        self.totalTokens = totalTokens
        self.totalCachedInputTokens = totalCachedInputTokens
        self.totalCacheCreationInputTokens = totalCacheCreationInputTokens
        self.totalReasoningTokens = totalReasoningTokens
        self.semanticDecisionUsage = semanticDecisionUsage
    }
}
