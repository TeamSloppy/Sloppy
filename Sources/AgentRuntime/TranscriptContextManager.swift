import AnyLanguageModel
import Foundation
import PluginSDK
import Protocols

public struct TranscriptContextReport: Sendable, Equatable {
    public var beforeTokens: Int
    public var afterTokens: Int
    public var prunedToolOutputs: Int
    public var summarized: Bool
    public var usedFallback: Bool = false
    public var checkpoint: TranscriptContextCheckpoint? = nil
}

/// A persisted model projection. Validate its prefix against the journal before replaying it.
public struct TranscriptContextCheckpoint: Codable, Sendable, Equatable {
    public var sourcePrefixIDs: [String]
    public var retainedPromptIDs: [String]
    public var summary: String

    public func restore(_ transcript: Transcript) -> Transcript? {
        let prefix = transcript.prefix(sourcePrefixIDs.count)
        guard prefix.map(\.id) == sourcePrefixIDs else { return nil }
        let kept = Set(retainedPromptIDs)
        return Transcript(entries: [summaryEntry] + prefix.filter { kept.contains($0.id) }
            + transcript.dropFirst(sourcePrefixIDs.count))
    }

    /// Translate a checkpoint on top of an earlier projection back to journal IDs.
    public func extending(_ previous: Self?) -> Self {
        guard sourcePrefixIDs.first == Self.summaryID, let previous else { return self }
        let oldPrefix = Set(previous.sourcePrefixIDs)
        return .init(
            sourcePrefixIDs: previous.sourcePrefixIDs + sourcePrefixIDs.dropFirst().filter { !oldPrefix.contains($0) },
            retainedPromptIDs: retainedPromptIDs,
            summary: summary
        )
    }

    static let summaryID = "sloppy-context-checkpoint"

    var summaryEntry: Transcript.Entry {
        .response(.init(id: Self.summaryID, assetIDs: [], segments: [
            .text(.init(content: summary))
        ]))
    }
}

public enum TranscriptContextError: Error, Sendable {
    case protectedContextExceedsBudget
    case summaryFailed
}

/// Transforms a model-visible copy, leaving persisted events and their evidence intact.
public enum TranscriptContextManager {
    public typealias Archive = @Sendable (String, String) async -> Protocols.JSONValue?
    public typealias Summarize = @Sendable (String, Int) async throws -> String

    public static func estimate(_ transcript: Transcript) -> Int {
        transcript.reduce(0) { $0 + estimate(entry: $1) }
    }

    public static func estimate(entry: Transcript.Entry) -> Int {
        TokenPressureEstimator().estimateTextTokens(render(entry)) + 16
    }

    public static func render(_ entry: Transcript.Entry) -> String {
        func segments(_ segments: [Transcript.Segment]) -> String {
            segments.map {
                switch $0 {
                case .text(let value): return value.content
                case .structure(let value): return value.content.jsonString
                case .image: return String(repeating: " ", count: 3_072)
                }
            }.joined(separator: "\n")
        }
        switch entry {
        case .instructions(let value):
            let definitions = (try? JSONEncoder().encode(value.toolDefinitions)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            return "[Instructions]\n" + segments(value.segments) + definitions
        case .prompt(let value): return "[User]\n" + segments(value.segments)
        case .response(let value): return "[Assistant]\n" + segments(value.segments)
        case .toolOutput(let value): return "[Tool \(value.toolName) id=\(value.id)]\n" + segments(value.segments)
        case .toolCalls(let value): return value.map { "[Call \($0.toolName) id=\($0.id)] \($0.arguments.jsonString)" }.joined(separator: "\n")
        }
    }

    public static func prepare(
        _ original: Transcript,
        inputBudget: Int,
        protectRecentEntries: Int = 8,
        forceSummary: Bool = false,
        summaryInputBudget: Int? = nil,
        targetInputTokens: Int? = nil,
        protectRecentTokens: Int? = nil,
        allowDeterministicFallback: Bool = false,
        archive: Archive? = nil,
        ledger: String? = nil,
        summarize: Summarize
    ) async throws -> (Transcript, TranscriptContextReport) {
        var entries = Array(original)
        let before = estimate(original)
        var pruned = 0
        let prompts = entries.indices.filter { if case .prompt = entries[$0] { return true }; return false }
        var recentStart = max(0, entries.count - max(1, protectRecentEntries))
        if let protectRecentTokens {
            var tokens = 0
            // Keep the newest contiguous entries that fit the token target.
            recentStart = entries.count
            while recentStart > 0, entries.count - recentStart < max(1, protectRecentEntries) {
                let cost = estimate(entry: entries[recentStart - 1])
                if recentStart < entries.count, tokens + cost > protectRecentTokens { break }
                tokens += cost
                recentStart -= 1
            }
        }
        let protectedPrompts = Set(prompts.suffix(2))
        for index in entries.indices {
            // A token-bounded runtime tail may use complete artifact references under pressure.
            guard index < recentStart || (protectRecentTokens != nil && before > inputBudget),
                  case .toolOutput(let output) = entries[index],
                  output.segments.allSatisfy({ if case .text = $0 { return true }; return false }),
                  estimate(entry: entries[index]) > 512 else { continue }
            let text = output.segments.map { if case .text(let value) = $0 { return value.content }; return "" }.joined(separator: "\n")
            guard var payload = (try? JSONDecoder().decode(Protocols.JSONValue.self, from: Data(text.utf8)))?.asObject else { continue }
            let data = payload["data"]?.asObject ?? [:]
            let state = payload["executionOutcome"]?.asObject?["state"]?.asString
            if state == ExecutionState.interrupted.rawValue || payload["error"]?.asObject?["code"] == .string("tool_execution_interrupted") { continue }
            var refs = ["outputArtifact", "stdoutArtifact", "stderrArtifact"].compactMap { key -> Protocols.JSONValue? in
                guard let ref = data[key], ref.asObject?["complete"] == .bool(true) else { return nil }
                return ref
            }
            if refs.isEmpty, let ref = await archive?(output.id, text), ref.asObject?["complete"] == .bool(true) { refs = [ref] }
            guard !refs.isEmpty else { continue }
            var replacement: [String: Protocols.JSONValue] = ["compacted": .bool(true), "artifacts": .array(refs)]
            for key in ["verificationEvidence", "exitCode", "timedOut", "contentHash", "executionOutcome", "requiresReconciliation"] {
                if let value = data[key] { replacement[key] = value }
            }
            payload["data"] = .object(replacement)
            let encoded = try JSONEncoder().encode(Protocols.JSONValue.object(payload))
            let next = Transcript.Entry.toolOutput(.init(id: output.id, toolName: output.toolName, segments: [.text(.init(content: String(decoding: encoded, as: UTF8.self)))]))
            guard estimate(entry: next) < estimate(entry: entries[index]) else { continue }
            entries[index] = next
            pruned += 1
        }
        var transcript = Transcript(entries: entries)
        let prunedTokens = estimate(transcript)
        if prunedTokens <= (targetInputTokens ?? inputBudget) && !forceSummary {
            return (transcript, .init(beforeTokens: before, afterTokens: prunedTokens, prunedToolOutputs: pruned, summarized: false))
        }
        let outputs = Set(entries.compactMap { if case .toolOutput(let value) = $0 { return value.id }; return nil })
        var tailStart = recentStart
        var callsByID: [String: Int] = [:]
        for index in entries.indices {
            if case .toolCalls(let calls) = entries[index] {
                for call in calls {
                    callsByID[call.id] = index
                    if !outputs.contains(call.id) { tailStart = min(tailStart, index) }
                }
            }
        }
        // Walk back to a fixed point when parallel call/result spans overlap.
        var index = entries.count
        while index > tailStart {
            index -= 1
            if case .toolOutput(let output) = entries[index], let callIndex = callsByID[output.id] {
                tailStart = min(tailStart, callIndex)
            }
        }
        let head = entries.prefix(tailStart).enumerated().filter { index, entry in
            if case .instructions = entry { return false }
            return !protectedPrompts.contains(index)
        }.map(\.element)
        let instructions = entries.filter { if case .instructions = $0 { return true }; return false }
        let retainedPrompts = entries.prefix(tailStart).enumerated().filter { protectedPrompts.contains($0.offset) }.map(\.element)
        let tail = entries.suffix(from: tailStart).filter { if case .instructions = $0 { return false }; return true }
        let protectedTokens = estimate(Transcript(entries: instructions + retainedPrompts + tail))
        let ledgerBudget = max(0, min(inputBudget / 8, inputBudget - protectedTokens - 128))
        let ledgerText = ledger.map { String($0.prefix(ledgerBudget * 4)) }.flatMap { $0.isEmpty ? nil : $0 }
        let ledgerTokens = ledgerText.map { TokenPressureEstimator().estimateTextTokens($0) } ?? 0
        guard head.contains(where: { $0.id != TranscriptContextCheckpoint.summaryID }) else {
            if estimate(transcript) <= inputBudget {
                return (transcript, .init(beforeTokens: before, afterTokens: estimate(transcript), prunedToolOutputs: pruned, summarized: false))
            }
            throw TranscriptContextError.protectedContextExceedsBudget
        }

        let remaining = inputBudget - protectedTokens - ledgerTokens - 64
        guard remaining > 0 else {
            if !forceSummary || before > inputBudget || estimate(transcript) > inputBudget {
                throw TranscriptContextError.protectedContextExceedsBudget
            }
            return (transcript, .init(beforeTokens: before, afterTokens: estimate(transcript), prunedToolOutputs: pruned, summarized: false))
        }
        let summarizerBudget = summaryInputBudget ?? inputBudget
        let outputTokens = min(remaining, max(1, summarizerBudget / 4), 2_000)
        let historyBudget = summarizerBudget - outputTokens - min(256, summarizerBudget / 4)
        guard historyBudget > 0 else { throw TranscriptContextError.protectedContextExceedsBudget }
        let history = boundedSummaryInput(head, budget: historyBudget)
        let summary: String
        let usedFallback: Bool
        do {
            let generated = try await summarize(history, outputTokens)
            guard !generated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  TokenPressureEstimator().estimateTextTokens(generated) <= remaining else {
                throw TranscriptContextError.summaryFailed
            }
            summary = generated
            usedFallback = false
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard allowDeterministicFallback else { throw TranscriptContextError.summaryFailed }
            try Task.checkCancellation()
            summary = "The summary model was unavailable. Earlier events are recoverable from session history."
            usedFallback = true
        }

        let checkpoint = TranscriptContextCheckpoint(
            sourcePrefixIDs: entries.prefix(tailStart).filter { if case .instructions = $0 { return false }; return true }.map(\.id),
            retainedPromptIDs: retainedPrompts.map(\.id),
            summary: "[Compacted conversation context]\n" + summary
                + (ledgerText.map { "\n\n" + $0 } ?? "")
                + recoveryHint(entries: entries, tailStart: tailStart)
        )
        transcript = Transcript(entries: instructions + [checkpoint.summaryEntry] + retainedPrompts + tail)
        guard estimate(transcript) <= inputBudget else { throw TranscriptContextError.protectedContextExceedsBudget }
        return (transcript, .init(beforeTokens: before, afterTokens: estimate(transcript), prunedToolOutputs: pruned, summarized: true, usedFallback: usedFallback, checkpoint: checkpoint))
    }

    private static func recoveryHint(entries: [Transcript.Entry], tailStart: Int) -> String {
        if tailStart < entries.count,
           let entry = entries.suffix(from: tailStart).first(where: {
               switch $0 {
               case .prompt, .response, .toolCalls: true
               case .instructions, .toolOutput: false
               }
           }) {
            return "\n\nRetrieve exact earlier events with sessions.history beforeEventId=\(entry.id)."
        }
        return "\n\nRetrieve exact earlier events with sessions.history."
    }

    static func boundedSummaryInput(_ entries: [Transcript.Entry], budget: Int) -> String {
        // Use the runtime estimator's four characters per token, with space for separators.
        let limit = budget * 4
        let previous = entries.first(where: { $0.id == TranscriptContextCheckpoint.summaryID })
        let history = entries.filter { $0.id != TranscriptContextCheckpoint.summaryID }
        let previousText = previous.map { String(render($0).prefix(limit / 3)) + "\n\n" } ?? ""
        let available = limit - previousText.count
        let records = history.map { entry in
            let text = render(entry)
            let marker = "\n[Earlier event \(entry.id) continues in session history]"
            let cap = min(6_000, max(1, available / 8))
            return text.count <= cap ? text : String(text.prefix(max(0, cap - marker.count))) + marker
        }
        let full = records.joined(separator: "\n\n")
        if full.count <= available { return previousText + full }

        let count = min(8, records.count)
        let marker = "\n\n[Older records omitted. Retrieve them with sessions.history.]\n\n"
        let perSlice = max(0, (available - (count - 1) * marker.count) / count)
        var slices: [String] = []
        for slice in 0..<count {
            let start = slice * records.count / count
            let end = (slice + 1) * records.count / count
            var selected: [String] = []
            var used = 0
            for record in slice == count - 1 ? Array(records[start..<end].reversed()) : Array(records[start..<end]) {
                let separator = selected.isEmpty ? 0 : 2
                let room = perSlice - used - separator
                guard room > 0 else { break }
                if record.count > room, !selected.isEmpty { break }
                selected.append(String(record.prefix(room)))
                used += min(room, record.count) + separator
            }
            if slice == count - 1 { selected.reverse() }
            slices.append(selected.joined(separator: "\n\n"))
        }
        return previousText + String(slices.joined(separator: marker).prefix(available))
    }
}
