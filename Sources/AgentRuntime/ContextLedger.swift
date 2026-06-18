import Foundation
import Protocols

public enum ContextLedgerCategory: String, Codable, Sendable, Equatable, CaseIterable {
    case systemInstructions = "system_instructions"
    case bootstrapStatic = "bootstrap_static"
    case toolsSchema = "tools_schema"
    case sessionTranscript = "session_transcript"
    case currentTurn = "current_turn"
    case attachments
    case memory
    case planner
    case toolResults = "tool_results"
    case reservedOutput = "reserved_output"
}

public enum ContextLedgerCachePolicy: String, Codable, Sendable, Equatable {
    case unknown
    case uncacheable
    case cacheable
    case cached
}

public struct ContextLedgerEntry: Codable, Sendable, Equatable {
    public var category: ContextLedgerCategory
    public var label: String
    public var estimatedTokens: Int
    public var cachePolicy: ContextLedgerCachePolicy

    public init(
        category: ContextLedgerCategory,
        label: String,
        estimatedTokens: Int,
        cachePolicy: ContextLedgerCachePolicy = .unknown
    ) {
        self.category = category
        self.label = label
        self.estimatedTokens = max(0, estimatedTokens)
        self.cachePolicy = cachePolicy
    }
}

public struct ContextLedgerSnapshot: Codable, Sendable, Equatable {
    public var channelId: String
    public var contextWindowTokens: Int
    public var reservedOutputTokens: Int
    public var entries: [ContextLedgerEntry]
    public var lastTurnUsage: TokenUsage?

    public init(
        channelId: String,
        contextWindowTokens: Int,
        reservedOutputTokens: Int,
        entries: [ContextLedgerEntry],
        lastTurnUsage: TokenUsage? = nil
    ) {
        self.channelId = channelId
        self.contextWindowTokens = max(1, contextWindowTokens)
        self.reservedOutputTokens = max(0, reservedOutputTokens)
        self.entries = entries
        self.lastTurnUsage = lastTurnUsage
    }

    public var contextWindowUsedTokens: Int {
        entries.reduce(0) { $0 + $1.estimatedTokens }
    }

    public var contextWindowFreeTokens: Int {
        max(0, contextWindowTokens - reservedOutputTokens - contextWindowUsedTokens)
    }

    public var utilization: Double {
        min(1.0, Double(contextWindowUsedTokens + reservedOutputTokens) / Double(contextWindowTokens))
    }

    public var lastTurnInputTokens: Int {
        lastTurnUsage?.prompt ?? 0
    }

    public var lastTurnCachedInputTokens: Int {
        lastTurnUsage?.cachedInput ?? 0
    }

    public var lastTurnUncachedInputTokens: Int {
        lastTurnUsage?.uncachedInput ?? 0
    }

    public var lastTurnCacheCreationInputTokens: Int {
        lastTurnUsage?.cacheCreationInput ?? 0
    }

    public var lastTurnCompletionTokens: Int {
        lastTurnUsage?.completion ?? 0
    }

    public var lastTurnReasoningTokens: Int {
        lastTurnUsage?.reasoning ?? 0
    }

    public func withProviderUsage(_ usage: TokenUsage) -> ContextLedgerSnapshot {
        var copy = self
        copy.lastTurnUsage = usage
        return copy
    }
}

public struct ContextLedgerBuilder: Sendable {
    private let estimator: TokenPressureEstimator

    public init(estimator: TokenPressureEstimator = TokenPressureEstimator()) {
        self.estimator = estimator
    }

    public func estimateTextTokens(_ text: String) -> Int {
        estimator.estimateTextTokens(text)
    }

    public func entry(
        category: ContextLedgerCategory,
        label: String,
        text: String,
        cachePolicy: ContextLedgerCachePolicy = .unknown
    ) -> ContextLedgerEntry {
        ContextLedgerEntry(
            category: category,
            label: label,
            estimatedTokens: estimateTextTokens(text),
            cachePolicy: cachePolicy
        )
    }

    public func snapshot(
        channelId: String,
        contextWindowTokens: Int,
        reservedOutputTokens: Int,
        entries: [ContextLedgerEntry],
        lastTurnUsage: TokenUsage? = nil
    ) -> ContextLedgerSnapshot {
        ContextLedgerSnapshot(
            channelId: channelId,
            contextWindowTokens: contextWindowTokens,
            reservedOutputTokens: reservedOutputTokens,
            entries: entries,
            lastTurnUsage: lastTurnUsage
        )
    }
}
