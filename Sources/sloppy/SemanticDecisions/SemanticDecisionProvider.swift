import Foundation
import Protocols

struct SemanticChoiceRequest: Sendable, Equatable {
    var state: String
    var questionID: String
    var instructions: String
    var choices: [String: String]
}

struct SemanticChoiceResponse: Sendable, Equatable {
    var choice: String
    var confidence: Double
    var probabilities: [String: Double]
    var usage: SemanticDecisionCallUsage
}

struct SemanticDecisionCallUsage: Sendable, Equatable {
    var inputTokens: Int
    var outputTokens: Int
    var costUSD: Double
    var costIsEstimated: Bool
}

protocol SemanticDecisionProvider: Sendable {
    func choose(_ request: SemanticChoiceRequest) async throws -> SemanticChoiceResponse
}

actor SemanticDecisionUsageMeter {
    private var usageByChannel: [String: SemanticDecisionUsage] = [:]

    func record(channelID: String, usage call: SemanticDecisionCallUsage) {
        var usage = usageByChannel[channelID] ?? SemanticDecisionUsage()
        usage.requestCount += 1
        usage.inputTokens += max(0, call.inputTokens)
        usage.outputTokens += max(0, call.outputTokens)
        usage.totalCostUSD += max(0, call.costUSD)
        if call.costIsEstimated {
            usage.estimatedCostUSD += max(0, call.costUSD)
        }
        usageByChannel[channelID] = usage
    }

    func snapshot(channelID: String?) -> SemanticDecisionUsage? {
        if let channelID {
            return usageByChannel[channelID]
        }
        guard !usageByChannel.isEmpty else { return nil }
        return usageByChannel.values.reduce(into: SemanticDecisionUsage()) { total, item in
            total.requestCount += item.requestCount
            total.inputTokens += item.inputTokens
            total.outputTokens += item.outputTokens
            total.totalCostUSD += item.totalCostUSD
            total.estimatedCostUSD += item.estimatedCostUSD
        }
    }
}

