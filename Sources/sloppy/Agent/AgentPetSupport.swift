import Foundation
import Protocols

enum AgentPetSourceKind: String, Codable, Sendable {
    case agentSession = "agent_session"
    case externalChannel = "external_channel"
    case heartbeat
    case cron
}

enum AgentPetEventKind: String, Codable, Sendable {
    case userMessage = "user_message"
    case toolCall = "tool_call"
    case toolSuccess = "tool_success"
    case toolFailure = "tool_failure"
    case runCompleted = "run_completed"
    case runFailed = "run_failed"
    case runInterrupted = "run_interrupted"
}

struct AgentPetProgressionInput: Sendable {
    let sourceKind: AgentPetSourceKind
    let eventKind: AgentPetEventKind
    let channelId: String
    let sessionId: String?
    let timestamp: Date
    let userId: String?
    let content: String?

    init(
        sourceKind: AgentPetSourceKind,
        eventKind: AgentPetEventKind,
        channelId: String,
        sessionId: String? = nil,
        timestamp: Date = Date(),
        userId: String? = nil,
        content: String? = nil
    ) {
        self.sourceKind = sourceKind
        self.eventKind = eventKind
        self.channelId = channelId
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.userId = userId
        self.content = content
    }
}

struct AgentPetGeneratedRecord {
    let summary: AgentPetSummary
    let state: AgentPetProgressState
}

private struct AgentPetPartCatalogEntry {
    let id: String
    let rarity: AgentPetRarityTier
    let weight: Int
}

private struct SplitMix64 {
    private(set) var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum AgentPetFactory {
    private static let heads: [AgentPetPartCatalogEntry] = [
        .init(id: "head-bubble", rarity: .common, weight: 28),
        .init(id: "head-cube", rarity: .common, weight: 26),
        .init(id: "head-shell", rarity: .common, weight: 24),
        .init(id: "head-fork", rarity: .uncommon, weight: 18),
        .init(id: "head-visor", rarity: .uncommon, weight: 14),
        .init(id: "head-probe", rarity: .rare, weight: 9),
        .init(id: "head-oracle", rarity: .rare, weight: 6),
        .init(id: "head-crown", rarity: .legendary, weight: 2)
    ]

    private static let bodies: [AgentPetPartCatalogEntry] = [
        .init(id: "body-core", rarity: .common, weight: 28),
        .init(id: "body-puff", rarity: .common, weight: 26),
        .init(id: "body-brick", rarity: .common, weight: 24),
        .init(id: "body-terminal", rarity: .uncommon, weight: 18),
        .init(id: "body-satchel", rarity: .uncommon, weight: 14),
        .init(id: "body-relay", rarity: .rare, weight: 9),
        .init(id: "body-reactor", rarity: .rare, weight: 6),
        .init(id: "body-throne", rarity: .legendary, weight: 2)
    ]

    private static let legs: [AgentPetPartCatalogEntry] = [
        .init(id: "legs-stub", rarity: .common, weight: 28),
        .init(id: "legs-bouncer", rarity: .common, weight: 26),
        .init(id: "legs-track", rarity: .common, weight: 24),
        .init(id: "legs-sprinter", rarity: .uncommon, weight: 18),
        .init(id: "legs-spider", rarity: .uncommon, weight: 14),
        .init(id: "legs-piston", rarity: .rare, weight: 9),
        .init(id: "legs-hover", rarity: .rare, weight: 6),
        .init(id: "legs-singularity", rarity: .legendary, weight: 2)
    ]

    static func makePet(createdAt: Date = Date()) -> AgentPetGeneratedRecord {
        let genome = UInt64.random(in: UInt64.min ... UInt64.max)
        return makePet(genome: genome, createdAt: createdAt)
    }

    static func makePet(genome: UInt64, createdAt: Date = Date()) -> AgentPetGeneratedRecord {
        var rng = SplitMix64(seed: genome)
        let head = weightedPick(from: heads, using: &rng)
        let body = weightedPick(from: bodies, using: &rng)
        let legs = weightedPick(from: legs, using: &rng)
        let baseStats = makeBaseStats(head: head, body: body, legs: legs, rng: &rng)
        let partRarities = AgentPetPartRarities(
            head: head.rarity,
            body: body.rarity,
            legs: legs.rarity
        )
        let summary = AgentPetSummary(
            petId: "pet_" + String(UUID().uuidString.lowercased().prefix(12)),
            genomeHex: String(format: "%016llx", genome),
            parts: AgentPetParts(headId: head.id, bodyId: body.id, legsId: legs.id),
            partRarities: partRarities,
            rarity: overallRarity(from: partRarities),
            baseStats: baseStats,
            currentStats: baseStats,
            transferable: true
        )
        let state = AgentPetProgressState(
            currentStats: baseStats,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        return AgentPetGeneratedRecord(summary: summary, state: state)
    }

    private static func weightedPick(from entries: [AgentPetPartCatalogEntry], using rng: inout SplitMix64) -> AgentPetPartCatalogEntry {
        let totalWeight = max(entries.reduce(0) { $0 + max($1.weight, 1) }, 1)
        var ticket = Int(rng.next() % UInt64(totalWeight))
        for entry in entries {
            ticket -= max(entry.weight, 1)
            if ticket < 0 {
                return entry
            }
        }
        return entries[0]
    }

    private static func makeBaseStats(
        head: AgentPetPartCatalogEntry,
        body: AgentPetPartCatalogEntry,
        legs: AgentPetPartCatalogEntry,
        rng: inout SplitMix64
    ) -> AgentPetStats {
        let rarityBoost = rarityScore(head.rarity) + rarityScore(body.rarity) + rarityScore(legs.rarity)
        var stats = AgentPetStats(
            wisdom: 18 + Int(rng.next() % 19),
            debugging: 18 + Int(rng.next() % 19),
            patience: 18 + Int(rng.next() % 19),
            snark: 18 + Int(rng.next() % 19),
            chaos: 18 + Int(rng.next() % 19)
        )

        if head.id.contains("oracle") || head.id.contains("crown") {
            stats.wisdom += 6
        }
        if body.id.contains("terminal") || body.id.contains("reactor") {
            stats.debugging += 6
        }
        if body.id.contains("puff") || body.id.contains("throne") {
            stats.patience += 5
        }
        if head.id.contains("visor") || legs.id.contains("spider") {
            stats.snark += 4
        }
        if legs.id.contains("hover") || legs.id.contains("singularity") {
            stats.chaos += 5
        }

        stats.wisdom += rarityBoost
        stats.debugging += rarityBoost
        stats.patience += max(rarityBoost - 1, 0)
        stats.snark += max(rarityBoost - 2, 0)
        stats.chaos += max(rarityBoost - 2, 0)
        return stats.clamped()
    }

    private static func rarityScore(_ rarity: AgentPetRarityTier) -> Int {
        switch rarity {
        case .common:
            return 0
        case .uncommon:
            return 2
        case .rare:
            return 5
        case .legendary:
            return 9
        }
    }

    private static func overallRarity(from rarities: AgentPetPartRarities) -> AgentPetRarityTier {
        let values = [rarities.head, rarities.body, rarities.legs]
        let rareCount = values.filter { $0 == .rare }.count
        let legendaryCount = values.filter { $0 == .legendary }.count
        let uncommonCount = values.filter { $0 == .uncommon }.count

        if legendaryCount > 0 || rareCount >= 2 {
            return .legendary
        }
        if rareCount == 1 || uncommonCount >= 2 {
            return .rare
        }
        if uncommonCount == 1 {
            return .uncommon
        }
        return .common
    }
}

enum AgentPetProgressionEngine {
    private static let perChannelDailyCap = AgentPetStats(
        wisdom: 14,
        debugging: 16,
        patience: 12,
        snark: 10,
        chaos: 12
    )
    private static let globalDailyCap = AgentPetStats(
        wisdom: 32,
        debugging: 36,
        patience: 28,
        snark: 24,
        chaos: 28
    )

    static func apply(
        state: inout AgentPetProgressState,
        input: AgentPetProgressionInput,
        baseStats: AgentPetStats
    ) {
        pruneOldBuckets(state: &state, referenceDate: input.timestamp)

        let rawDelta = delta(for: input, counters: state.counters)
        let dayKey = dayBucket(for: input.timestamp)
        let channelBucketKey = dayKey + "|" + input.channelId
        let existingChannelGain = state.dailyChannelGainBuckets[channelBucketKey] ?? .init()
        let existingGlobalGain = state.dailyGlobalGainBuckets[dayKey] ?? .init()
        let cappedDelta = cap(
            delta: rawDelta,
            channelGain: existingChannelGain,
            globalGain: existingGlobalGain
        )

        guard !cappedDelta.isZero else {
            state.processedWatermark = AgentPetProgressWatermark(
                sourceKind: input.sourceKind.rawValue,
                channelId: input.channelId,
                sessionId: input.sessionId,
                eventKind: input.eventKind.rawValue,
                processedAt: input.timestamp
            )
            state.updatedAt = input.timestamp
            return
        }

        state.currentStats = (state.currentStats + cappedDelta).clamped()
        state.dailyChannelGainBuckets[channelBucketKey] = existingChannelGain + cappedDelta
        state.dailyGlobalGainBuckets[dayKey] = existingGlobalGain + cappedDelta
        state.processedWatermark = AgentPetProgressWatermark(
            sourceKind: input.sourceKind.rawValue,
            channelId: input.channelId,
            sessionId: input.sessionId,
            eventKind: input.eventKind.rawValue,
            processedAt: input.timestamp
        )
        state.updatedAt = input.timestamp
        updateCounters(state: &state, input: input)
        state.currentStats = mergeMinimum(base: baseStats, current: state.currentStats).clamped()
    }

    private static func delta(for input: AgentPetProgressionInput, counters: AgentPetProgressCounters) -> AgentPetStats {
        var delta = AgentPetStats()
        let normalizedText = input.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let length = normalizedText.count
        let lower = normalizedText.lowercased()

        switch input.eventKind {
        case .userMessage:
            if length >= 120 {
                delta.wisdom += 3
                delta.patience += 2
            } else if length >= 48 {
                delta.wisdom += 2
                delta.patience += 1
            } else if length >= 16 {
                delta.wisdom += 1
            }

            if isTechnical(lower) {
                delta.debugging += length >= 24 ? 2 : 1
            }

            if isSnarky(lower) {
                delta.snark += 2
            }

            if isChaotic(lower) {
                delta.chaos += 1
            }

            if length > 0 && length < 12 {
                delta = delta.scaled(by: 0.35)
            }
        case .toolCall:
            delta.debugging += 2
        case .toolSuccess:
            delta.debugging += 2
            delta.wisdom += 1
        case .toolFailure:
            delta.debugging += 1
            delta.chaos += counters.toolFailureCount >= 3 ? 1 : 2
        case .runCompleted:
            delta.wisdom += 2
            delta.patience += 2
        case .runFailed:
            delta.debugging += 1
            delta.chaos += counters.failedRunCount >= 3 ? 1 : 2
        case .runInterrupted:
            delta.snark += 1
            delta.chaos += counters.interruptedRunCount >= 2 ? 1 : 2
        }

        let weighted = delta.scaled(by: weight(for: input.sourceKind))
        return weighted.clamped()
    }

    private static func cap(
        delta: AgentPetStats,
        channelGain: AgentPetStats,
        globalGain: AgentPetStats
    ) -> AgentPetStats {
        AgentPetStats(
            wisdom: maxCapped(delta.wisdom, channelGain.wisdom, perChannelDailyCap.wisdom, globalGain.wisdom, globalDailyCap.wisdom),
            debugging: maxCapped(delta.debugging, channelGain.debugging, perChannelDailyCap.debugging, globalGain.debugging, globalDailyCap.debugging),
            patience: maxCapped(delta.patience, channelGain.patience, perChannelDailyCap.patience, globalGain.patience, globalDailyCap.patience),
            snark: maxCapped(delta.snark, channelGain.snark, perChannelDailyCap.snark, globalGain.snark, globalDailyCap.snark),
            chaos: maxCapped(delta.chaos, channelGain.chaos, perChannelDailyCap.chaos, globalGain.chaos, globalDailyCap.chaos)
        )
    }

    private static func maxCapped(
        _ delta: Int,
        _ channelCurrent: Int,
        _ channelCap: Int,
        _ globalCurrent: Int,
        _ globalCap: Int
    ) -> Int {
        guard delta > 0 else {
            return 0
        }
        let remainingChannel = max(channelCap - channelCurrent, 0)
        let remainingGlobal = max(globalCap - globalCurrent, 0)
        return min(delta, remainingChannel, remainingGlobal)
    }

    private static func updateCounters(state: inout AgentPetProgressState, input: AgentPetProgressionInput) {
        switch input.eventKind {
        case .userMessage:
            switch input.sourceKind {
            case .agentSession:
                state.counters.directMessageCount += 1
            case .externalChannel:
                state.counters.externalMessageCount += 1
            case .heartbeat, .cron:
                state.counters.automatedMessageCount += 1
            }
        case .toolCall:
            state.counters.toolCallCount += 1
        case .toolSuccess:
            break
        case .toolFailure:
            state.counters.toolFailureCount += 1
        case .runCompleted:
            state.counters.successfulRunCount += 1
        case .runFailed:
            state.counters.failedRunCount += 1
        case .runInterrupted:
            state.counters.interruptedRunCount += 1
        }
    }

    private static func weight(for sourceKind: AgentPetSourceKind) -> Double {
        switch sourceKind {
        case .agentSession, .externalChannel:
            return 1.0
        case .heartbeat, .cron:
            return 0.35
        }
    }

    private static func pruneOldBuckets(state: inout AgentPetProgressState, referenceDate: Date) {
        let calendar = Calendar(identifier: .gregorian)
        let earliestDate = calendar.date(byAdding: .day, value: -2, to: referenceDate) ?? referenceDate
        let earliestKey = dayBucket(for: earliestDate)
        state.dailyChannelGainBuckets = state.dailyChannelGainBuckets.filter { key, _ in
            String(key.prefix(10)) >= earliestKey
        }
        state.dailyGlobalGainBuckets = state.dailyGlobalGainBuckets.filter { key, _ in
            key >= earliestKey
        }
    }

    private static func dayBucket(for date: Date) -> String {
        AgentPetDateFormatter.day.string(from: date)
    }

    private static func isTechnical(_ text: String) -> Bool {
        let keywords = [
            "bug", "debug", "stack", "trace", "test", "build", "compile", "error",
            "swift", "react", "typescript", "sql", "crash", "fix", "refactor"
        ]
        return keywords.contains(where: text.contains)
    }

    private static func isSnarky(_ text: String) -> Bool {
        text.contains("???") ||
        text.contains("wtf") ||
        text.contains("seriously") ||
        text.contains("sure.") ||
        text.contains("obviously") ||
        text.contains("ага")
    }

    private static func isChaotic(_ text: String) -> Bool {
        text.contains("!!!") ||
        text.contains("panic") ||
        text.contains("urgent") ||
        text.contains("asap") ||
        text.contains("сломалось") ||
        text.contains("пожар")
    }

    private static func mergeMinimum(base: AgentPetStats, current: AgentPetStats) -> AgentPetStats {
        AgentPetStats(
            wisdom: max(base.wisdom, current.wisdom),
            debugging: max(base.debugging, current.debugging),
            patience: max(base.patience, current.patience),
            snark: max(base.snark, current.snark),
            chaos: max(base.chaos, current.chaos)
        )
    }
}

private enum AgentPetDateFormatter {
    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

extension AgentPetStats {
    var isZero: Bool {
        wisdom == 0 && debugging == 0 && patience == 0 && snark == 0 && chaos == 0
    }

    func clamped() -> AgentPetStats {
        AgentPetStats(
            wisdom: min(max(wisdom, 0), 100),
            debugging: min(max(debugging, 0), 100),
            patience: min(max(patience, 0), 100),
            snark: min(max(snark, 0), 100),
            chaos: min(max(chaos, 0), 100)
        )
    }

    func scaled(by factor: Double) -> AgentPetStats {
        guard factor > 0 else {
            return .init()
        }

        func scale(_ value: Int) -> Int {
            guard value > 0 else {
                return 0
            }
            let scaled = Int((Double(value) * factor).rounded(.toNearestOrAwayFromZero))
            return max(scaled, 1)
        }

        return AgentPetStats(
            wisdom: scale(wisdom),
            debugging: scale(debugging),
            patience: scale(patience),
            snark: scale(snark),
            chaos: scale(chaos)
        )
    }

    static func + (lhs: AgentPetStats, rhs: AgentPetStats) -> AgentPetStats {
        AgentPetStats(
            wisdom: lhs.wisdom + rhs.wisdom,
            debugging: lhs.debugging + rhs.debugging,
            patience: lhs.patience + rhs.patience,
            snark: lhs.snark + rhs.snark,
            chaos: lhs.chaos + rhs.chaos
        )
    }
}
