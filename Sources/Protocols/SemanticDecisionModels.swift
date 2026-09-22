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

