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
    private let store: (any PersistenceStore)?

    init(store: (any PersistenceStore)? = nil) {
        self.store = store
    }

    func record(channelID: String, usage call: SemanticDecisionCallUsage, at createdAt: Date = Date()) async {
        let costUSD = call.costUSD.isFinite ? max(0, call.costUSD) : 0
        var usage = usageByChannel[channelID] ?? SemanticDecisionUsage()
        usage.requestCount += 1
        usage.inputTokens += max(0, call.inputTokens)
        usage.outputTokens += max(0, call.outputTokens)
        usage.totalCostUSD += costUSD
        if call.costIsEstimated {
            usage.estimatedCostUSD += costUSD
        }
        usageByChannel[channelID] = usage
        if let store {
            await store.persistSemanticDecisionUsage(record: SemanticDecisionUsageRecord(
                id: UUID().uuidString,
                channelId: channelID,
                inputTokens: call.inputTokens,
                outputTokens: call.outputTokens,
                costUSD: costUSD,
                costIsEstimated: call.costIsEstimated,
                createdAt: createdAt
            ))
        }
    }

    func snapshot(channelID: String?) async -> SemanticDecisionUsage? {
        if let store {
            let records = await store.listSemanticDecisionUsage(channelId: channelID, from: nil, to: nil)
            if !records.isEmpty {
                return records.reduce(into: SemanticDecisionUsage()) { total, record in
                    total.requestCount += 1
                    total.inputTokens += record.inputTokens
                    total.outputTokens += record.outputTokens
                    total.totalCostUSD += record.costUSD
                    if record.costIsEstimated {
                        total.estimatedCostUSD += record.costUSD
                    }
                }
            }
        }
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
