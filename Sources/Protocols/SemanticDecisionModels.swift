import Foundation

/// Aggregated usage for optional semantic-decision providers such as Jev.
public struct SemanticDecisionUsage: Codable, Sendable, Equatable {
    public var requestCount: Int
    public var inputTokens: Int
    public var outputTokens: Int
    public var totalCostUSD: Double
    public var estimatedCostUSD: Double

    public init(
        requestCount: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        totalCostUSD: Double = 0,
        estimatedCostUSD: Double = 0
    ) {
        self.requestCount = max(0, requestCount)
        self.inputTokens = max(0, inputTokens)
        self.outputTokens = max(0, outputTokens)
        self.totalCostUSD = max(0, totalCostUSD)
        self.estimatedCostUSD = max(0, estimatedCostUSD)
    }

    public var includesEstimatedCost: Bool {
        estimatedCostUSD > 0
    }
}

/// One billed semantic-decision call, retained for period-based spending reports.
public struct SemanticDecisionUsageRecord: Codable, Sendable, Equatable {
    public var id: String
    public var channelId: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var costUSD: Double
    public var costIsEstimated: Bool
    public var createdAt: Date

    public init(
        id: String,
        channelId: String,
        inputTokens: Int,
        outputTokens: Int,
        costUSD: Double,
        costIsEstimated: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.channelId = channelId
        self.inputTokens = max(0, inputTokens)
        self.outputTokens = max(0, outputTokens)
        self.costUSD = costUSD.isFinite ? max(0, costUSD) : 0
        self.costIsEstimated = costIsEstimated
        self.createdAt = createdAt
    }
}

public struct SemanticDecisionSpendingDay: Codable, Sendable, Equatable {
    public var day: String
    public var usage: SemanticDecisionUsage

    public init(day: String, usage: SemanticDecisionUsage) {
        self.day = day
        self.usage = usage
    }
}

public struct SemanticDecisionSpendingResponse: Codable, Sendable, Equatable {
    public var total: SemanticDecisionUsage
    public var days: [SemanticDecisionSpendingDay]

    public init(total: SemanticDecisionUsage, days: [SemanticDecisionSpendingDay]) {
        self.total = total
        self.days = days
    }
}
