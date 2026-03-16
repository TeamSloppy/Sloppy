import Foundation
import Protocols

public actor Visor {
    private let eventBus: EventBus
    private let memoryStore: MemoryStore
    private let completionProvider: (@Sendable (String, Int) async -> String?)?
    private let streamingProvider: (@Sendable (String, Int) -> AsyncStream<String>)?
    private let bulletinMaxWords: Int
    private var bulletins: [MemoryBulletin] = []
    private var lastRetrievalHash: String?
    private var lastBulletin: MemoryBulletin?
    private var supervisionTask: Task<Void, Never>?
    private var signalSubscriptionTask: Task<Void, Never>?
    private var lastMaintenanceRun: Date?
    private var failureWindows: [String: [Date]] = [:]
    private var lastActivityAt: Date = Date()
    public private(set) var isReady: Bool = false

    public init(
        eventBus: EventBus,
        memoryStore: MemoryStore,
        completionProvider: (@Sendable (String, Int) async -> String?)? = nil,
        streamingProvider: (@Sendable (String, Int) -> AsyncStream<String>)? = nil,
        bulletinMaxWords: Int = 300
    ) {
        self.eventBus = eventBus
        self.memoryStore = memoryStore
        self.completionProvider = completionProvider
        self.streamingProvider = streamingProvider
        self.bulletinMaxWords = bulletinMaxWords
    }

    // MARK: - Supervision tick loop

    /// Starts the internal supervision tick loop. Each tick: health checks + periodic maintenance.
    public func startSupervision(
        tickInterval: Duration,
        workerTimeoutSeconds: Int,
        branchTimeoutSeconds: Int,
        maintenanceIntervalSeconds: Int,
        decayRatePerDay: Double,
        pruneImportanceThreshold: Double,
        pruneMinAgeDays: Int,
        channelDegradedFailureCount: Int = 3,
        channelDegradedWindowSeconds: Int = 600,
        idleThresholdSeconds: Int = 1800,
        snapshotProvider: @escaping @Sendable () async -> ([ChannelSnapshot], [WorkerSnapshot]),
        branchProvider: @escaping @Sendable () async -> [BranchSnapshot],
        branchForceTimeout: @escaping @Sendable (String) async -> Void
    ) {
        guard supervisionTask == nil else { return }

        signalSubscriptionTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.eventBus.subscribe()
            for await event in stream {
                guard !Task.isCancelled else { break }
                await self.recordEvent(event)
            }
        }

        supervisionTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.runTick(
                    workerTimeoutSeconds: workerTimeoutSeconds,
                    branchTimeoutSeconds: branchTimeoutSeconds,
                    maintenanceIntervalSeconds: maintenanceIntervalSeconds,
                    decayRatePerDay: decayRatePerDay,
                    pruneImportanceThreshold: pruneImportanceThreshold,
                    pruneMinAgeDays: pruneMinAgeDays,
                    channelDegradedFailureCount: channelDegradedFailureCount,
                    channelDegradedWindowSeconds: channelDegradedWindowSeconds,
                    idleThresholdSeconds: idleThresholdSeconds,
                    snapshotProvider: snapshotProvider,
                    branchProvider: branchProvider,
                    branchForceTimeout: branchForceTimeout
                )
                try? await Task.sleep(for: tickInterval)
            }
        }
    }

    private func runTick(
        workerTimeoutSeconds: Int,
        branchTimeoutSeconds: Int,
        maintenanceIntervalSeconds: Int,
        decayRatePerDay: Double,
        pruneImportanceThreshold: Double,
        pruneMinAgeDays: Int,
        channelDegradedFailureCount: Int,
        channelDegradedWindowSeconds: Int,
        idleThresholdSeconds: Int,
        snapshotProvider: @escaping @Sendable () async -> ([ChannelSnapshot], [WorkerSnapshot]),
        branchProvider: @escaping @Sendable () async -> [BranchSnapshot],
        branchForceTimeout: @escaping @Sendable (String) async -> Void
    ) async {
        let (_, workers) = await snapshotProvider()
        await checkWorkerHealth(workers: workers, workerTimeoutSeconds: workerTimeoutSeconds)

        let branches = await branchProvider()
        await checkBranchHealth(
            branches: branches,
            branchTimeoutSeconds: branchTimeoutSeconds,
            forceTimeout: branchForceTimeout
        )

        await checkSignals(
            channelDegradedFailureCount: channelDegradedFailureCount,
            channelDegradedWindowSeconds: channelDegradedWindowSeconds,
            idleThresholdSeconds: idleThresholdSeconds
        )

        let now = Date()
        let needsMaintenance = lastMaintenanceRun.map {
            now.timeIntervalSince($0) >= Double(maintenanceIntervalSeconds)
        } ?? true
        if needsMaintenance {
            await runMemoryMaintenance(
                decayRatePerDay: decayRatePerDay,
                pruneImportanceThreshold: pruneImportanceThreshold,
                pruneMinAgeDays: pruneMinAgeDays
            )
            lastMaintenanceRun = now
        }

        if !isReady {
            isReady = true
        }
    }

    /// Stops the supervision tick loop.
    public func stopSupervision() {
        supervisionTask?.cancel()
        supervisionTask = nil
        signalSubscriptionTask?.cancel()
        signalSubscriptionTask = nil
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

    /// Returns the digest from the most recent bulletin, for injection into LLM prompts.
    public func latestBulletinDigest() -> String? {
        lastBulletin?.digest
    }

    // MARK: - Signal detection

    func recordEvent(_ event: EventEnvelope) {
        switch event.messageType {
        case .workerFailed:
            let channelId = event.channelId
            var timestamps = failureWindows[channelId] ?? []
            timestamps.append(Date())
            failureWindows[channelId] = timestamps
        case .channelMessageReceived:
            lastActivityAt = Date()
        default:
            break
        }
    }

    func checkSignals(
        channelDegradedFailureCount: Int,
        channelDegradedWindowSeconds: Int,
        idleThresholdSeconds: Int
    ) async {
        let now = Date()
        let windowCutoff = now.addingTimeInterval(-Double(channelDegradedWindowSeconds))

        for (channelId, timestamps) in failureWindows {
            let recent = timestamps.filter { $0 >= windowCutoff }
            failureWindows[channelId] = recent
            guard recent.count >= channelDegradedFailureCount else { continue }
            await eventBus.publish(
                EventEnvelope(
                    messageType: .visorSignalChannelDegraded,
                    channelId: channelId,
                    payload: .object([
                        "failure_count": .number(Double(recent.count)),
                        "window_seconds": .number(Double(channelDegradedWindowSeconds))
                    ])
                )
            )
            failureWindows[channelId] = []
        }

        let idleSince = now.timeIntervalSince(lastActivityAt)
        if idleSince >= Double(idleThresholdSeconds) {
            await eventBus.publish(
                EventEnvelope(
                    messageType: .visorSignalIdle,
                    channelId: "broadcast",
                    payload: .object([
                        "idle_seconds": .number(idleSince)
                    ])
                )
            )
        }
    }

    // MARK: - Health monitoring

    func checkWorkerHealth(workers: [WorkerSnapshot], workerTimeoutSeconds: Int) async {
        let now = Date()
        let timeout = TimeInterval(workerTimeoutSeconds)
        for worker in workers {
            guard worker.status == .running || worker.status == .waitingInput else { continue }
            guard let startedAt = worker.startedAt else { continue }
            let elapsed = now.timeIntervalSince(startedAt)
            guard elapsed >= timeout else { continue }
            await eventBus.publish(
                EventEnvelope(
                    messageType: .visorWorkerTimeout,
                    channelId: worker.channelId,
                    taskId: worker.taskId,
                    workerId: worker.workerId,
                    payload: .object([
                        "elapsed_seconds": .number(elapsed),
                        "timeout_seconds": .number(Double(workerTimeoutSeconds)),
                        "status": .string(worker.status.rawValue)
                    ])
                )
            )
        }
    }

    func checkBranchHealth(
        branches: [BranchSnapshot],
        branchTimeoutSeconds: Int,
        forceTimeout: @Sendable (String) async -> Void
    ) async {
        let now = Date()
        let timeout = TimeInterval(branchTimeoutSeconds)
        for branch in branches {
            let elapsed = now.timeIntervalSince(branch.createdAt)
            guard elapsed >= timeout else { continue }
            await forceTimeout(branch.branchId)
        }
    }

    // MARK: - Memory maintenance

    func runMemoryMaintenance(
        decayRatePerDay: Double,
        pruneImportanceThreshold: Double,
        pruneMinAgeDays: Int
    ) async {
        let all = await memoryStore.entries(filter: .default)
        let now = Date()
        let minAgeSeconds = TimeInterval(pruneMinAgeDays) * 86_400
        var decayCount = 0
        var pruneCount = 0

        for entry in all {
            guard entry.memoryClass != .bulletin else { continue }
            guard entry.kind != .identity else { continue }

            let ageSeconds = now.timeIntervalSince(entry.updatedAt)
            let ageDays = ageSeconds / 86_400

            if ageDays >= 1 {
                let decayed = entry.importance * (1 - decayRatePerDay * ageDays)
                let clamped = max(decayed, 0)
                if clamped < entry.importance {
                    _ = await memoryStore.updateImportance(id: entry.id, importance: clamped)
                    decayCount += 1
                    if clamped < pruneImportanceThreshold && ageSeconds >= minAgeSeconds {
                        _ = await memoryStore.softDelete(id: entry.id)
                        pruneCount += 1
                    }
                }
            }
        }

        await eventBus.publish(
            EventEnvelope(
                messageType: .visorMemoryMaintained,
                channelId: "broadcast",
                payload: .object([
                    "decayed": .number(Double(decayCount)),
                    "pruned": .number(Double(pruneCount))
                ])
            )
        )
    }

    // MARK: - Interactive chat

    /// Answers a question using the current bulletin, memory recall, and system state.
    public func answer(
        question: String,
        channels: [ChannelSnapshot],
        workers: [WorkerSnapshot]
    ) async -> String {
        let bulletinContext = lastBulletin?.digest ?? "No bulletin yet."
        let activeWorkers = workers.filter { $0.status == .running || $0.status == .waitingInput }
        let stateSummary = "Active channels: \(channels.count). Workers in progress: \(activeWorkers.count) / \(workers.count) total."
        let prompt = """
            You are Visor, the Sloppy system's self-awareness layer.
            Answer the following question using only the context provided.

            ## Current Bulletin
            \(bulletinContext)

            ## System State
            \(stateSummary)

            ## Question
            \(question)
            """

        guard let completionProvider else {
            return bulletinContext
        }

        let response = await completionProvider(prompt, 512)
        return response?.trimmingCharacters(in: .whitespacesAndNewlines) ?? bulletinContext
    }

    /// Streams an answer to a question using current bulletin and system state, yielding text deltas.
    public func streamAnswer(
        question: String,
        channels: [ChannelSnapshot],
        workers: [WorkerSnapshot]
    ) -> AsyncStream<String> {
        let bulletinContext = lastBulletin?.digest ?? "No bulletin yet."
        let activeWorkers = workers.filter { $0.status == .running || $0.status == .waitingInput }
        let stateSummary = "Active channels: \(channels.count). Workers in progress: \(activeWorkers.count) / \(workers.count) total."
        let prompt = """
            You are Visor, the Sloppy system's self-awareness layer.
            Answer the following question using only the context provided.

            ## Current Bulletin
            \(bulletinContext)

            ## System State
            \(stateSummary)

            ## Question
            \(question)
            """

        if let streamingProvider {
            return streamingProvider(prompt, 512)
        }

        let completionProvider = self.completionProvider
        return AsyncStream<String> { continuation in
            Task {
                if let text = await completionProvider?(prompt, 512) {
                    continuation.yield(text.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    continuation.yield(bulletinContext)
                }
                continuation.finish()
            }
        }
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
