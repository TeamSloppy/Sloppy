import Foundation

struct BenchSummary: Codable, Sendable, Equatable {
    var model: String
    var runs: Int
    var passed: Int
    var failed: Int
    var timeouts: Int
    var errors: Int
    var passRate: Double
    var meanAgentSeconds: Double
    var meanToolCalls: Double
    var meanToolErrors: Double
    var meanTotalTokens: Double
    var mutationConflicts: Int
}

struct BenchReport: Codable, Sendable, Equatable {
    var generatedAt: Date
    var suite: String
    var results: [BenchRunResult]

    var summaries: [BenchSummary] {
        Dictionary(grouping: results, by: \.model).map { model, runs in
            let count = Double(runs.count)
            func mean(_ value: (BenchRunResult) -> Double) -> Double { runs.map(value).reduce(0, +) / count }
            let passed = runs.filter { $0.status == .passed }.count
            return BenchSummary(
                model: model,
                runs: runs.count,
                passed: passed,
                failed: runs.filter { $0.status == .failed }.count,
                timeouts: runs.filter { $0.status == .timeout }.count,
                errors: runs.filter { $0.status == .error }.count,
                passRate: Double(passed) / count,
                meanAgentSeconds: mean(\.agentSeconds),
                meanToolCalls: mean { Double($0.metrics.toolCalls) },
                meanToolErrors: mean { Double($0.metrics.toolErrors) },
                meanTotalTokens: mean { Double($0.metrics.totalTokens) },
                mutationConflicts: runs.reduce(0) { $0 + $1.metrics.mutationConflicts }
            )
        }.sorted { $0.model < $1.model }
    }

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func load(from url: URL) throws -> BenchReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BenchReport.self, from: Data(contentsOf: url))
    }

    /// Plain-text table: one row per task attempt, then one summary row per model.
    func renderTable() -> String {
        var lines: [String] = []
        let header = ["task", "model", "#", "status", "sec", "tools", "errs", "tokens"]
        var rows: [[String]] = [header]
        for result in results {
            rows.append([
                result.taskId, result.model, String(result.attempt), result.status.rawValue,
                String(format: "%.1f", result.agentSeconds), String(result.metrics.toolCalls),
                String(result.metrics.toolErrors), String(result.metrics.totalTokens),
            ])
        }
        let widths = header.indices.map { column in rows.map { $0[column].count }.max() ?? 0 }
        for row in rows {
            lines.append(row.enumerated().map { $1.padding(toLength: widths[$0], withPad: " ", startingAt: 0) }
                .joined(separator: "  "))
        }
        lines.append("")
        for summary in summaries {
            lines.append(
                "\(summary.model): \(summary.passed)/\(summary.runs) passed "
                    + "(\(Int((summary.passRate * 100).rounded()))%), "
                    + "\(summary.failed) failed, \(summary.timeouts) timeout, \(summary.errors) error; "
                    + String(format: "avg %.1fs, %.1f tool calls, %.1f tool errors, %.0f tokens",
                             summary.meanAgentSeconds, summary.meanToolCalls, summary.meanToolErrors, summary.meanTotalTokens)
                    + "; edit conflicts: \(summary.mutationConflicts)"
            )
        }
        return lines.joined(separator: "\n")
    }

    /// Per-task pass/fail delta against a baseline report, matched by task id and model.
    func renderComparison(against baseline: BenchReport) -> String {
        func rates(_ report: BenchReport) -> [String: Double] {
            Dictionary(grouping: report.results, by: { "\($0.model)/\($0.taskId)" }).mapValues { runs in
                Double(runs.filter(\.passed).count) / Double(runs.count)
            }
        }
        let old = rates(baseline)
        let new = rates(self)
        var lines: [String] = []
        for key in Set(old.keys).union(new.keys).sorted() {
            let before = old[key].map { "\(Int(($0 * 100).rounded()))%" } ?? "-"
            let after = new[key].map { "\(Int(($0 * 100).rounded()))%" } ?? "-"
            let marker = (old[key] ?? 0) == (new[key] ?? 0) ? " " : ((new[key] ?? 0) > (old[key] ?? 0) ? "+" : "-")
            lines.append("\(marker) \(key): \(before) -> \(after)")
        }
        return lines.joined(separator: "\n")
    }
}
