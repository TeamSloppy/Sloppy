import Foundation
import Protocols

public actor Visor {
    private let eventBus: EventBus
    private let memoryStore: MemoryStore
    private let completionProvider: (@Sendable (String, Int) async -> String?)?
    private let bulletinMaxWords: Int
    private var bulletins: [MemoryBulletin] = []
    private var lastRetrievalHash: String?
    private var lastBulletin: MemoryBulletin?

    public init(
        eventBus: EventBus,
        memoryStore: MemoryStore,
        completionProvider: (@Sendable (String, Int) async -> String?)? = nil,
        bulletinMaxWords: Int = 300
    ) {
        self.eventBus = eventBus
        self.memoryStore = memoryStore
        self.completionProvider = completionProvider
        self.bulletinMaxWords = bulletinMaxWords
    }

    /// Builds periodic runtime bulletin via two-phase retrieval + LLM synthesis.
    /// Phase 1: programmatic retrieval of channels, workers, and memory sections.
    /// Phase 2: LLM synthesis into a concise briefing (skipped if state is unchanged).
    public func generateBulletin(
        channels: [ChannelSnapshot],
        workers: [WorkerSnapshot],
        taskSummary: String? = nil
    ) async -> MemoryBulletin {
        let scope: MemoryScope = channels.count == 1 ? .channel(channels[0].channelId) : .default

        // Phase 1: retrieve
        let sections = await retrieveSections(channels: channels, workers: workers, taskSummary: taskSummary, scope: scope)
        let retrievalHash = hash(sections)

        // Dedup: if retrieval output is identical, return cached bulletin
        if let cached = lastBulletin, retrievalHash == lastRetrievalHash {
            return cached
        }

        // Phase 2: synthesize
        let (headline, digest) = await synthesize(sections: sections, scope: scope)

        let recalled = await memoryStore.recall(
            request: MemoryRecallRequest(query: digest, limit: 12, scope: scope)
        )
        let memoryRefs = recalled.map(\.ref)
        let bulletin = MemoryBulletin(
            headline: headline,
            digest: digest,
            items: sections.items,
            memoryRefs: memoryRefs,
            scope: scope
        )

        let saved = await memoryStore.save(
            entry: MemoryWriteRequest(
                note: "[bulletin] \(digest)",
                summary: headline,
                kind: .event,
                memoryClass: .bulletin,
                scope: scope,
                source: MemorySource(type: "visor.bulletin.generated", id: bulletin.id),
                importance: 0.7,
                confidence: 0.9
            )
        )
        for ref in memoryRefs {
            _ = await memoryStore.link(
                MemoryEdgeWriteRequest(
                    fromMemoryId: saved.id,
                    toMemoryId: ref.id,
                    relation: .about,
                    provenance: "visor.bulletin"
                )
            )
        }

        lastRetrievalHash = retrievalHash
        lastBulletin = bulletin
        bulletins.append(bulletin)

        if let payload = try? JSONValueCoder.encode(bulletin) {
            await eventBus.publish(
                EventEnvelope(
                    messageType: .visorBulletinGenerated,
                    channelId: "broadcast",
                    payload: payload
                )
            )
        }

        return bulletin
    }

    /// Lists bulletins generated since runtime startup.
    public func listBulletins() -> [MemoryBulletin] {
        bulletins
    }

    // MARK: - Private

    private struct RetrievedSections {
        var channelSummary: String
        var workerSummary: String
        var recentMemories: [MemoryHit]
        var decisions: [MemoryHit]
        var goals: [MemoryHit]
        var events: [MemoryHit]
        var taskSummary: String?

        var items: [String] {
            var result: [String] = []
            if !channelSummary.isEmpty { result.append(channelSummary) }
            if !workerSummary.isEmpty { result.append(workerSummary) }
            if let taskSummary, !taskSummary.isEmpty { result.append(taskSummary) }
            return result
        }
    }

    private func retrieveSections(
        channels: [ChannelSnapshot],
        workers: [WorkerSnapshot],
        taskSummary: String?,
        scope: MemoryScope
    ) async -> RetrievedSections {
        let activeWorkers = workers.filter { $0.status == .running || $0.status == .waitingInput }
        let channelSummary = "Active channels: \(channels.count)"
        let workerSummary = "Workers in progress: \(activeWorkers.count) / \(workers.count) total"

        async let recentHits = memoryStore.recall(
            request: MemoryRecallRequest(query: "recent activity", limit: 8, scope: scope)
        )
        async let decisionHits = memoryStore.recall(
            request: MemoryRecallRequest(query: "decision", limit: 5, scope: scope, kinds: [.decision])
        )
        async let goalHits = memoryStore.recall(
            request: MemoryRecallRequest(query: "goal objective", limit: 5, scope: scope, kinds: [.goal])
        )
        async let eventHits = memoryStore.recall(
            request: MemoryRecallRequest(query: "event", limit: 5, scope: scope, kinds: [.event])
        )

        let (recent, decisions, goals, events) = await (recentHits, decisionHits, goalHits, eventHits)

        return RetrievedSections(
            channelSummary: channelSummary,
            workerSummary: workerSummary,
            recentMemories: recent,
            decisions: decisions,
            goals: goals,
            events: events,
            taskSummary: taskSummary
        )
    }

    private func synthesize(sections: RetrievedSections, scope: MemoryScope) async -> (headline: String, digest: String) {
        let programmaticDigest = buildProgrammaticDigest(sections: sections)
        let headline = buildHeadline(sections: sections)

        guard let completionProvider else {
            return (headline, programmaticDigest)
        }

        let prompt = buildSynthesisPrompt(sections: sections)
        let maxTokens = bulletinMaxWords * 2

        guard let synthesized = await completionProvider(prompt, maxTokens),
              !synthesized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return (headline, programmaticDigest)
        }

        return (headline, synthesized.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func buildSynthesisPrompt(sections: RetrievedSections) -> String {
        var lines: [String] = [
            "You are Visor, the system's self-awareness layer.",
            "Synthesize a concise briefing (~\(bulletinMaxWords) words) from the runtime data below.",
            "Focus on what any conversation would benefit from knowing right now.",
            "Be factual and brief. Do not invent information.",
            ""
        ]

        lines.append("## Channel Activity")
        lines.append(sections.channelSummary)
        lines.append("")

        lines.append("## Active Workers")
        lines.append(sections.workerSummary)
        lines.append("")

        if let taskSummary = sections.taskSummary, !taskSummary.isEmpty {
            lines.append("## Task Status")
            lines.append(taskSummary)
            lines.append("")
        }

        if !sections.decisions.isEmpty {
            lines.append("## Recent Decisions")
            for hit in sections.decisions {
                lines.append("- \(hit.summary ?? hit.note)")
            }
            lines.append("")
        }

        if !sections.goals.isEmpty {
            lines.append("## Active Goals")
            for hit in sections.goals {
                lines.append("- \(hit.summary ?? hit.note)")
            }
            lines.append("")
        }

        if !sections.recentMemories.isEmpty {
            lines.append("## Recent Memories")
            for hit in sections.recentMemories.prefix(5) {
                lines.append("- \(hit.summary ?? hit.note)")
            }
            lines.append("")
        }

        if !sections.events.isEmpty {
            lines.append("## Recent Events")
            for hit in sections.events.prefix(4) {
                lines.append("- \(hit.summary ?? hit.note)")
            }
            lines.append("")
        }

        lines.append("Respond with the briefing only. No preamble, no markdown headers.")

        return lines.joined(separator: "\n")
    }

    private func buildProgrammaticDigest(sections: RetrievedSections) -> String {
        var parts = [sections.channelSummary, sections.workerSummary]
        if let taskSummary = sections.taskSummary, !taskSummary.isEmpty {
            parts.append(taskSummary)
        }
        return parts.joined(separator: " | ")
    }

    private func buildHeadline(sections: RetrievedSections) -> String {
        "Runtime bulletin: \(sections.channelSummary.lowercased()), \(sections.workerSummary.lowercased())"
    }

    /// Hashes operational state only (channels, workers, tasks).
    /// Memory hits are intentionally excluded: saving a bulletin memory between runs
    /// would otherwise invalidate the dedup key on every cycle.
    private func hash(_ sections: RetrievedSections) -> String {
        var content = "\(sections.channelSummary)|\(sections.workerSummary)"
        if let taskSummary = sections.taskSummary {
            content += "|\(taskSummary)"
        }
        return fnv1a(content)
    }

    /// FNV-1a 64-bit hash — stable within a process run, no external dependencies.
    private func fnv1a(_ string: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
