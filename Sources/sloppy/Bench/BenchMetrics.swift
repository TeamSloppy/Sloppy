import Foundation
import Protocols

/// Quantitative profile of one agent run, derived only from typed session events (never from assistant prose).
struct BenchMetrics: Codable, Sendable, Equatable {
    var toolCalls: Int = 0
    var toolErrors: Int = 0
    /// Count of failed tool results per typed error code, e.g. `ambiguous_match`, `file_changed`.
    var errorCodes: [String: Int] = [:]
    var mutationConflicts: Int = 0
    var promptTokens: Int = 0
    var completionTokens: Int = 0
    var reasoningTokens: Int = 0
    var cachedInputTokens: Int = 0
    var turnOutcome: String?
    /// Typed failure code of the final turn outcome (e.g. `protectedContextExceedsBudget`), when the turn failed.
    var turnFailureCode: String?
    var models: [String] = []

    var totalTokens: Int { promptTokens + completionTokens }

    /// Model requests are not recorded as events; every tool call is followed by one, plus the initial request.
    var steps: Int { toolCalls + 1 }

    /// Input tokens per model request. Unlike the per-task total it does not move with how many rounds a run took,
    /// so it is the right number for comparing prompt-size changes.
    var promptTokensPerStep: Int { promptTokens / steps }

    init() {}

    /// Tolerates reports written before a metric existed, so `--baseline` keeps working across versions.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolCalls = try container.decodeIfPresent(Int.self, forKey: .toolCalls) ?? 0
        toolErrors = try container.decodeIfPresent(Int.self, forKey: .toolErrors) ?? 0
        errorCodes = try container.decodeIfPresent([String: Int].self, forKey: .errorCodes) ?? [:]
        mutationConflicts = try container.decodeIfPresent(Int.self, forKey: .mutationConflicts) ?? 0
        promptTokens = try container.decodeIfPresent(Int.self, forKey: .promptTokens) ?? 0
        completionTokens = try container.decodeIfPresent(Int.self, forKey: .completionTokens) ?? 0
        reasoningTokens = try container.decodeIfPresent(Int.self, forKey: .reasoningTokens) ?? 0
        cachedInputTokens = try container.decodeIfPresent(Int.self, forKey: .cachedInputTokens) ?? 0
        turnOutcome = try container.decodeIfPresent(String.self, forKey: .turnOutcome)
        turnFailureCode = try container.decodeIfPresent(String.self, forKey: .turnFailureCode)
        models = try container.decodeIfPresent([String].self, forKey: .models) ?? []
    }

    static let mutationConflictCodes: Set<String> = ["ambiguous_match", "file_changed"]

    static func derive(from events: [AgentSessionEvent]) -> BenchMetrics {
        var metrics = BenchMetrics()
        var models: [String] = []
        var lastUsage: TokenUsage?
        for event in events {
            if event.toolCall != nil { metrics.toolCalls += 1 }
            if let result = event.toolResult, !result.ok {
                metrics.toolErrors += 1
                let code = result.error?.code ?? "unknown"
                metrics.errorCodes[code, default: 0] += 1
                if mutationConflictCodes.contains(code) { metrics.mutationConflicts += 1 }
            }
            if let status = event.runStatus {
                // The runtime re-emits the previous usage on the closing status event; count each distinct report once.
                if let usage = status.tokenUsage, usage != lastUsage {
                    lastUsage = usage
                    metrics.promptTokens += usage.prompt
                    metrics.completionTokens += usage.completion
                    metrics.reasoningTokens += usage.reasoning
                    metrics.cachedInputTokens += usage.cachedInput
                }
                if let model = status.selectedModel, !models.contains(model) { models.append(model) }
                if let outcome = status.executionOutcome {
                    metrics.turnOutcome = outcome.state.rawValue
                    metrics.turnFailureCode = outcome.state == .failed ? (outcome.code ?? outcome.category?.rawValue) : nil
                }
            }
        }
        metrics.models = models
        return metrics
    }
}
