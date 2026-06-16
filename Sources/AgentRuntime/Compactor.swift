import Foundation
import Protocols

public struct CompactorRetryPolicy: Sendable, Equatable {
    public var maxAttempts: Int
    public var initialBackoffNanoseconds: UInt64
    public var multiplier: Double
    public var maxBackoffNanoseconds: UInt64

    public init(
        maxAttempts: Int = 3,
        initialBackoffNanoseconds: UInt64 = 250_000_000,
        multiplier: Double = 2.0,
        maxBackoffNanoseconds: UInt64 = 2_000_000_000
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.initialBackoffNanoseconds = initialBackoffNanoseconds
        self.multiplier = max(1.0, multiplier)
        self.maxBackoffNanoseconds = max(maxBackoffNanoseconds, initialBackoffNanoseconds)
    }

    public static let `default` = CompactorRetryPolicy()
}


public struct CompactionLevelConfiguration: Sendable, Equatable {
    public var level: CompactionLevel
    public var utilizationThreshold: Double
    public var targetReductionPercent: Int
    public var preserveRecentMessages: Int
    public var preserveRecentTokens: Int

    public init(
        level: CompactionLevel,
        utilizationThreshold: Double,
        targetReductionPercent: Int,
        preserveRecentMessages: Int = 8,
        preserveRecentTokens: Int = 2_000
    ) {
        self.level = level
        self.utilizationThreshold = min(max(utilizationThreshold, 0.0), 1.0)
        self.targetReductionPercent = min(max(targetReductionPercent, 1), 100)
        self.preserveRecentMessages = max(0, preserveRecentMessages)
        self.preserveRecentTokens = max(0, preserveRecentTokens)
    }
}

public struct CompactorConfiguration: Sendable, Equatable {
    public var enabled: Bool
    public var contextWindowTokens: Int
    public var summaryTargetRatio: Double
    public var protectHeadMessages: Int
    public var protectTailTokens: Int
    public var protectTailMessages: Int
    public var antiThrashMinSavingsPercent: Int
    public var antiThrashMaxIneffectiveRuns: Int
    public var abortOnSummaryFailure: Bool
    public var maxContextInjectionPercent: Int
    public var warnContextInjectionPercent: Int
    public var levels: [CompactionLevelConfiguration]

    public init(
        enabled: Bool = true,
        contextWindowTokens: Int = 32_000,
        summaryTargetRatio: Double = 0.35,
        protectHeadMessages: Int = 2,
        protectTailTokens: Int = 2_000,
        protectTailMessages: Int = 8,
        antiThrashMinSavingsPercent: Int = 10,
        antiThrashMaxIneffectiveRuns: Int = 2,
        abortOnSummaryFailure: Bool = true,
        maxContextInjectionPercent: Int = 20,
        warnContextInjectionPercent: Int = 12,
        levels: [CompactionLevelConfiguration] = Self.defaultLevels
    ) {
        self.enabled = enabled
        self.contextWindowTokens = max(1, contextWindowTokens)
        self.summaryTargetRatio = min(max(summaryTargetRatio, 0.05), 0.95)
        self.protectHeadMessages = max(0, protectHeadMessages)
        self.protectTailTokens = max(0, protectTailTokens)
        self.protectTailMessages = max(0, protectTailMessages)
        self.antiThrashMinSavingsPercent = min(max(antiThrashMinSavingsPercent, 0), 100)
        self.antiThrashMaxIneffectiveRuns = max(1, antiThrashMaxIneffectiveRuns)
        self.abortOnSummaryFailure = abortOnSummaryFailure
        self.maxContextInjectionPercent = min(max(maxContextInjectionPercent, 1), 100)
        self.warnContextInjectionPercent = min(max(warnContextInjectionPercent, 0), self.maxContextInjectionPercent)
        self.levels = levels.isEmpty ? Self.defaultLevels : levels
    }

    public static let defaultLevels: [CompactionLevelConfiguration] = [
        CompactionLevelConfiguration(level: .soft, utilizationThreshold: 0.80, targetReductionPercent: 30),
        CompactionLevelConfiguration(level: .aggressive, utilizationThreshold: 0.85, targetReductionPercent: 50),
        CompactionLevelConfiguration(level: .emergency, utilizationThreshold: 0.95, targetReductionPercent: 70),
    ]

    public static let `default` = CompactorConfiguration()

    public func matchingLevel(for utilization: Double) -> CompactionLevelConfiguration? {
        guard enabled else { return nil }
        return levels
            .sorted { lhs, rhs in lhs.utilizationThreshold > rhs.utilizationThreshold }
            .first { utilization > $0.utilizationThreshold }
    }
}

public struct CompactionJobExecutionResult: Sendable, Equatable {
    public var success: Bool
    public var workerId: String?

    public init(success: Bool, workerId: String?) {
        self.success = success
        self.workerId = workerId
    }
}

private struct QueuedCompactionJob: Sendable {
    var job: CompactionJob
    var dedupKey: String
}

public actor Compactor {
    public typealias CompactionApplier = @Sendable (CompactionJob, WorkerRuntime) async -> CompactionJobExecutionResult
    public typealias SleepOperation = @Sendable (UInt64) async -> Void

    private let eventBus: EventBus
    private let configuration: CompactorConfiguration
    private let retryPolicy: CompactorRetryPolicy
    private let applier: CompactionApplier
    private let sleepOperation: SleepOperation

    private var lastLevelByChannel: [String: CompactionLevel] = [:]
    private var queuedJobsByChannel: [String: [QueuedCompactionJob]] = [:]
    private var queuedJobKeysByChannel: [String: Set<String>] = [:]
    private var activeJobKeyByChannel: [String: String] = [:]
    private var drainingChannels: Set<String> = []

    public init(eventBus: EventBus) {
        self.eventBus = eventBus
        self.configuration = .default
        self.retryPolicy = .default
        self.applier = Compactor.defaultApplier
        self.sleepOperation = Compactor.defaultSleepOperation
    }

    public init(
        eventBus: EventBus,
        configuration: CompactorConfiguration = .default,
        retryPolicy: CompactorRetryPolicy = .default
    ) {
        self.eventBus = eventBus
        self.configuration = configuration
        self.retryPolicy = retryPolicy
        self.applier = Compactor.defaultApplier
        self.sleepOperation = Compactor.defaultSleepOperation
    }

    public init(
        eventBus: EventBus,
        configuration: CompactorConfiguration = .default,
        retryPolicy: CompactorRetryPolicy = .default,
        applier: @escaping CompactionApplier,
        sleepOperation: @escaping SleepOperation
    ) {
        self.eventBus = eventBus
        self.configuration = configuration
        self.retryPolicy = retryPolicy
        self.applier = applier
        self.sleepOperation = sleepOperation
    }

    /// Evaluates channel context utilization and schedules compaction job when needed.
    public func evaluate(channelId: String, utilization: Double) async -> CompactionJob? {
        guard let levelConfig = configuration.matchingLevel(for: utilization) else {
            lastLevelByChannel[channelId] = nil
            return nil
        }

        let level = levelConfig.level
        if lastLevelByChannel[channelId] == level {
            return nil
        }

        lastLevelByChannel[channelId] = level
        let job = CompactionJob(
            channelId: channelId,
            level: level,
            threshold: levelConfig.utilizationThreshold,
            targetReductionPercent: levelConfig.targetReductionPercent,
            preserveRecentMessages: levelConfig.preserveRecentMessages,
            preserveRecentTokens: levelConfig.preserveRecentTokens,
            contextWindowTokens: configuration.contextWindowTokens
        )

        if let payload = try? JSONValueCoder.encode(job) {
            await eventBus.publish(
                EventEnvelope(
                    messageType: .compactorThresholdHit,
                    channelId: channelId,
                    payload: payload
                )
            )
        }

        return job
    }

    /// Enqueues compaction job and processes channel queue in background.
    public func apply(job: CompactionJob, workers: WorkerRuntime) async {
        let dedupKey = compactionDedupKey(for: job)

        if activeJobKeyByChannel[job.channelId] == dedupKey {
            return
        }

        var queuedKeys = queuedJobKeysByChannel[job.channelId, default: []]
        if queuedKeys.contains(dedupKey) {
            return
        }
        queuedKeys.insert(dedupKey)
        queuedJobKeysByChannel[job.channelId] = queuedKeys

        queuedJobsByChannel[job.channelId, default: []].append(
            QueuedCompactionJob(job: job, dedupKey: dedupKey)
        )
        scheduleQueueDrainIfNeeded(channelId: job.channelId, workers: workers)
    }

    private func scheduleQueueDrainIfNeeded(channelId: String, workers: WorkerRuntime) {
        let inserted = drainingChannels.insert(channelId).inserted
        guard inserted else {
            return
        }

        Task {
            await self.drainQueue(channelId: channelId, workers: workers)
        }
    }

    private func drainQueue(channelId: String, workers: WorkerRuntime) async {
        defer {
            drainingChannels.remove(channelId)
            cleanupQueueState(channelId: channelId)
            if hasPendingQueueWork(channelId: channelId) {
                scheduleQueueDrainIfNeeded(channelId: channelId, workers: workers)
            }
        }

        while let queuedJob = dequeueNext(channelId: channelId) {
            activeJobKeyByChannel[channelId] = queuedJob.dedupKey
            let result = await applyWithRetry(job: queuedJob.job, workers: workers)
            activeJobKeyByChannel[channelId] = nil

            if result.success {
                await publishSummaryApplied(job: queuedJob.job, workerId: result.workerId)
            }
        }
    }

    private func dequeueNext(channelId: String) -> QueuedCompactionJob? {
        guard var queue = queuedJobsByChannel[channelId], !queue.isEmpty else {
            return nil
        }

        let next = queue.removeFirst()
        if queue.isEmpty {
            queuedJobsByChannel[channelId] = nil
        } else {
            queuedJobsByChannel[channelId] = queue
        }

        var queuedKeys = queuedJobKeysByChannel[channelId] ?? []
        queuedKeys.remove(next.dedupKey)
        if queuedKeys.isEmpty {
            queuedJobKeysByChannel[channelId] = nil
        } else {
            queuedJobKeysByChannel[channelId] = queuedKeys
        }

        return next
    }

    private func applyWithRetry(job: CompactionJob, workers: WorkerRuntime) async -> CompactionJobExecutionResult {
        var attempt = 1
        var backoff = retryPolicy.initialBackoffNanoseconds

        while true {
            let result = await applier(job, workers)
            if result.success {
                return result
            }
            if attempt >= retryPolicy.maxAttempts {
                return result
            }

            await sleepOperation(backoff)
            backoff = nextBackoff(after: backoff)
            attempt += 1
        }
    }

    private func nextBackoff(after currentBackoff: UInt64) -> UInt64 {
        let next = Double(currentBackoff) * retryPolicy.multiplier
        let bounded = min(next, Double(retryPolicy.maxBackoffNanoseconds))
        return UInt64(bounded.rounded(.up))
    }

    private func publishSummaryApplied(job: CompactionJob, workerId: String?) async {
        await eventBus.publish(
            EventEnvelope(
                messageType: .compactorSummaryApplied,
                channelId: job.channelId,
                workerId: workerId,
                payload: .object([
                    "jobId": .string(job.id),
                    "level": .string(job.level.rawValue),
                    "targetReductionPercent": .number(Double(job.targetReductionPercent)),
                    "preserveRecentMessages": .number(Double(job.preserveRecentMessages)),
                    "preserveRecentTokens": .number(Double(job.preserveRecentTokens)),
                    "contextWindowTokens": .number(Double(job.contextWindowTokens))
                ])
            )
        )
    }

    private func compactionDedupKey(for job: CompactionJob) -> String {
        "\(job.channelId):\(job.level.rawValue)"
    }

    private func hasPendingQueueWork(channelId: String) -> Bool {
        let queueHasEntries = !(queuedJobsByChannel[channelId] ?? []).isEmpty
        let hasActive = activeJobKeyByChannel[channelId] != nil
        return queueHasEntries || hasActive
    }

    private func cleanupQueueState(channelId: String) {
        if queuedJobsByChannel[channelId]?.isEmpty == true {
            queuedJobsByChannel[channelId] = nil
        }
        if queuedJobKeysByChannel[channelId]?.isEmpty == true {
            queuedJobKeysByChannel[channelId] = nil
        }
        if activeJobKeyByChannel[channelId] == nil {
            activeJobKeyByChannel.removeValue(forKey: channelId)
        }
    }

    private static func defaultApplier(job: CompactionJob, workers: WorkerRuntime) async -> CompactionJobExecutionResult {
        let spec = WorkerTaskSpec(
            taskId: "compaction-\(job.id)",
            channelId: job.channelId,
            title: "Compaction \(job.level.rawValue)",
            objective: "Summarize channel context at \(Int(job.threshold * 100))% threshold; target \(job.targetReductionPercent)% reduction while preserving the latest \(job.preserveRecentMessages) messages / \(job.preserveRecentTokens) tokens.",
            tools: ["file"],
            mode: .fireAndForget
        )

        let workerId = await workers.spawn(spec: spec, autoStart: false)
        let artifact = await workers.completeNow(
            workerId: workerId,
            summary: "Compaction \(job.level.rawValue) summary applied"
        )
        return CompactionJobExecutionResult(success: artifact != nil, workerId: workerId)
    }

    private static func defaultSleepOperation(nanoseconds: UInt64) async {
        guard nanoseconds > 0 else {
            return
        }
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}
