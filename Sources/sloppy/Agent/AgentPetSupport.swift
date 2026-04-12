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

    mutating func nextDouble() -> Double {
        return Double(next()) / Double(UInt64.max)
    }

    mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        guard range.upperBound >= range.lowerBound else {
            return range.lowerBound
        }
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        let value = next() % span
        return range.lowerBound + Int(value)
    }
}

enum AgentPetFactory {
    private static let heads: [AgentPetPartCatalogEntry] = [
        .init(id: "head_vladimir", rarity: .common, weight: 28),
        .init(id: "head_kisya", rarity: .common, weight: 26),
        .init(id: "head_ada", rarity: .common, weight: 24),
        .init(id: "head_bipbop", rarity: .uncommon, weight: 18),
        .init(id: "head_george", rarity: .uncommon, weight: 14),
        .init(id: "head_hollow", rarity: .rare, weight: 9),
        .init(id: "head_pooh", rarity: .rare, weight: 6),
        .init(id: "head_proj1018_secret", rarity: .legendary, weight: 2)
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

    private static let faces: [AgentPetPartCatalogEntry] = [
        .init(id: "face-default", rarity: .common, weight: 30),
        .init(id: "face-mono", rarity: .common, weight: 20),
        .init(id: "face-scan", rarity: .common, weight: 18),
        .init(id: "face-grin", rarity: .uncommon, weight: 14),
        .init(id: "face-frown", rarity: .uncommon, weight: 10),
        .init(id: "face-x", rarity: .rare, weight: 6),
        .init(id: "face-star", rarity: .rare, weight: 4),
        .init(id: "face-halo", rarity: .legendary, weight: 2)
    ]

    private static let accessories: [AgentPetPartCatalogEntry] = [
        .init(id: "acc-none", rarity: .common, weight: 30),
        .init(id: "acc-scarf", rarity: .common, weight: 22),
        .init(id: "acc-badge", rarity: .common, weight: 18),
        .init(id: "acc-cape", rarity: .uncommon, weight: 14),
        .init(id: "acc-chain", rarity: .uncommon, weight: 10),
        .init(id: "acc-stripe", rarity: .rare, weight: 6),
        .init(id: "acc-wings", rarity: .rare, weight: 4),
        .init(id: "acc-bolt", rarity: .legendary, weight: 2)
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
        let face = weightedPick(from: faces, using: &rng)
        let accessory = weightedPick(from: accessories, using: &rng)
        let baseStats = makeBaseStats(head: head, body: body, legs: legs, face: face, accessory: accessory, rng: &rng)
        let partRarities = AgentPetPartRarities(
            head: head.rarity,
            body: body.rarity,
            legs: legs.rarity,
            face: face.rarity,
            accessory: accessory.rarity
        )
        let summary = AgentPetSummary(
            petId: "pet_" + String(UUID().uuidString.lowercased().prefix(12)),
            genomeHex: String(format: "%016llx", genome),
            parts: AgentPetParts(headId: head.id, bodyId: body.id, legsId: legs.id, faceId: face.id, accessoryId: accessory.id),
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
        face: AgentPetPartCatalogEntry,
        accessory: AgentPetPartCatalogEntry,
        rng: inout SplitMix64
    ) -> AgentPetStats {
        let rarityBoost = rarityScore(head.rarity) + rarityScore(body.rarity) + rarityScore(legs.rarity) + rarityScore(face.rarity) + rarityScore(accessory.rarity)
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
        if face.id.contains("grin") || face.id.contains("halo") {
            stats.patience += 4
        }
        if face.id.contains("x") || face.id.contains("frown") {
            stats.snark += 3
        }
        if face.id.contains("scan") || face.id.contains("star") {
            stats.wisdom += 3
        }
        if accessory.id.contains("bolt") || accessory.id.contains("wings") {
            stats.chaos += 4
        }
        if accessory.id.contains("cape") || accessory.id.contains("chain") {
            stats.snark += 3
        }
        if accessory.id.contains("stripe") || accessory.id.contains("badge") {
            stats.debugging += 3
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
        let values = [rarities.head, rarities.body, rarities.legs, rarities.face, rarities.accessory]
        let rareCount = values.filter { $0 == .rare }.count
        let legendaryCount = values.filter { $0 == .legendary }.count
        let uncommonCount = values.filter { $0 == .uncommon }.count

        if legendaryCount > 0 || rareCount >= 2 {
            return .legendary
        }
        if rareCount == 1 || uncommonCount >= 3 {
            return .rare
        }
        if uncommonCount >= 1 {
            return .uncommon
        }
        return .common
    }
}

struct AgentPetProgressionTuning {
    var perChannelDailyCap: AgentPetStats
    var globalDailyCap: AgentPetStats
    var growthMultiplier: Double
    var sourceWeights: [AgentPetSourceKind: Double]
    var decayProbability: Double
    var decayMagnitudeRange: ClosedRange<Int>
    var maxDecayAxes: Int

    static let `default` = AgentPetProgressionTuning(
        perChannelDailyCap: AgentPetStats(
            wisdom: 8,
            debugging: 10,
            patience: 7,
            snark: 6,
            chaos: 7
        ),
        globalDailyCap: AgentPetStats(
            wisdom: 18,
            debugging: 22,
            patience: 16,
            snark: 14,
            chaos: 16
        ),
        growthMultiplier: 0.35,
        sourceWeights: [
            .agentSession: 0.8,
            .externalChannel: 0.8,
            .heartbeat: 0.25,
            .cron: 0.25
        ],
        decayProbability: 0.35,
        decayMagnitudeRange: 1...3,
        maxDecayAxes: 3
    )
}

enum AgentPetProgressionEngine {
    private static let tuning = AgentPetProgressionTuning.default

    static func apply(
        state: inout AgentPetProgressState,
        input: AgentPetProgressionInput,
        baseStats: AgentPetStats
    ) {
        pruneOldBuckets(state: &state, referenceDate: input.timestamp)

        let rawDelta = delta(for: input, counters: state.counters)
        let adjustedDelta = applyVariance(to: rawDelta, seed: varianceSeed(for: input))
        let positiveDelta = adjustedDelta.positiveComponents()
        let negativeDelta = adjustedDelta.negativeComponents()
        let dayKey = dayBucket(for: input.timestamp)
        let channelBucketKey = dayKey + "|" + input.channelId
        let existingChannelGain = state.dailyChannelGainBuckets[channelBucketKey] ?? .init()
        let existingGlobalGain = state.dailyGlobalGainBuckets[dayKey] ?? .init()
        let cappedDelta = cap(
            delta: positiveDelta,
            channelGain: existingChannelGain,
            globalGain: existingGlobalGain
        )

        guard !cappedDelta.isZero || !negativeDelta.isZero else {
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
        if !negativeDelta.isZero {
            state.currentStats = (state.currentStats + negativeDelta).clamped()
        }
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

        // scaling logic remains unchanged to preserve per-event weight;
        // only downstream tuning adjusts effective growth.
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

    private static func applyVariance(to delta: AgentPetStats, seed: UInt64) -> AgentPetStats {
        var rng = SplitMix64(seed: seed)
        let dampened = delta.scaledDown(by: tuning.growthMultiplier)
        guard rng.nextDouble() < tuning.decayProbability else {
            return dampened
        }
        return dampened + randomDecayDelta(using: &rng)
    }

    private static func randomDecayDelta(using rng: inout SplitMix64) -> AgentPetStats {
        var penalties = AgentPetStats()
        let axes = AgentPetStatAxis.allCases
        guard !axes.isEmpty else {
            return penalties
        }
        let selectionCount = min(axes.count, max(1, rng.nextInt(in: 1...tuning.maxDecayAxes)))
        var usedIndexes: Set<Int> = []
        while usedIndexes.count < selectionCount {
            let index = rng.nextInt(in: 0...(axes.count - 1))
            if usedIndexes.insert(index).inserted {
                let amount = -rng.nextInt(in: tuning.decayMagnitudeRange)
                switch axes[index] {
                case .wisdom:
                    penalties.wisdom += amount
                case .debugging:
                    penalties.debugging += amount
                case .patience:
                    penalties.patience += amount
                case .snark:
                    penalties.snark += amount
                case .chaos:
                    penalties.chaos += amount
                }
            }
        }
        return penalties
    }

    private static func varianceSeed(for input: AgentPetProgressionInput) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(input.channelId)
        hasher.combine(input.sessionId)
        hasher.combine(input.timestamp.timeIntervalSince1970)
        hasher.combine(input.userId)
        hasher.combine(input.eventKind.rawValue)
        hasher.combine(input.sourceKind.rawValue)
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }

    private enum AgentPetStatAxis: CaseIterable {
        case wisdom
        case debugging
        case patience
        case snark
        case chaos
    }

    private static func cap(
        delta: AgentPetStats,
        channelGain: AgentPetStats,
        globalGain: AgentPetStats
    ) -> AgentPetStats {
        AgentPetStats(
            wisdom: maxCapped(delta.wisdom, channelGain.wisdom, tuning.perChannelDailyCap.wisdom, globalGain.wisdom, tuning.globalDailyCap.wisdom),
            debugging: maxCapped(delta.debugging, channelGain.debugging, tuning.perChannelDailyCap.debugging, globalGain.debugging, tuning.globalDailyCap.debugging),
            patience: maxCapped(delta.patience, channelGain.patience, tuning.perChannelDailyCap.patience, globalGain.patience, tuning.globalDailyCap.patience),
            snark: maxCapped(delta.snark, channelGain.snark, tuning.perChannelDailyCap.snark, globalGain.snark, tuning.globalDailyCap.snark),
            chaos: maxCapped(delta.chaos, channelGain.chaos, tuning.perChannelDailyCap.chaos, globalGain.chaos, tuning.globalDailyCap.chaos)
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
        max(tuning.sourceWeights[sourceKind] ?? 1.0, 0)
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

    func scaledDown(by factor: Double) -> AgentPetStats {
        guard factor > 0 else {
            return .init()
        }

        func scale(_ value: Int) -> Int {
            guard value > 0 else {
                return 0
            }
            let scaled = Int((Double(value) * factor).rounded(.down))
            return max(scaled, 0)
        }

        return AgentPetStats(
            wisdom: scale(wisdom),
            debugging: scale(debugging),
            patience: scale(patience),
            snark: scale(snark),
            chaos: scale(chaos)
        )
    }

    func positiveComponents() -> AgentPetStats {
        AgentPetStats(
            wisdom: max(wisdom, 0),
            debugging: max(debugging, 0),
            patience: max(patience, 0),
            snark: max(snark, 0),
            chaos: max(chaos, 0)
        )
    }

    func negativeComponents() -> AgentPetStats {
        AgentPetStats(
            wisdom: wisdom < 0 ? wisdom : 0,
            debugging: debugging < 0 ? debugging : 0,
            patience: patience < 0 ? patience : 0,
            snark: snark < 0 ? snark : 0,
            chaos: chaos < 0 ? chaos : 0
        )
    }
}
