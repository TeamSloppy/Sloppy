import Foundation
import Logging

struct SelfImprovementCuratorRunnerConfig: Sendable {
    var interval: Duration
    var jitter: Duration

    init(
        interval: Duration = .seconds(604_800),
        jitter: Duration = .seconds(3_600)
    ) {
        self.interval = interval
        self.jitter = jitter
    }

    static let weekly = SelfImprovementCuratorRunnerConfig()
}

actor SelfImprovementCuratorRunner {
    private let config: SelfImprovementCuratorRunnerConfig
    private let logger: Logger
    private let curator: @Sendable () async -> Void
    private var task: Task<Void, Never>?
    private var isRunning = false
    private var isCuratorInProgress = false

    init(
        config: SelfImprovementCuratorRunnerConfig = .weekly,
        logger: Logger,
        curator: @escaping @Sendable () async -> Void
    ) {
        self.config = config
        self.logger = logger
        self.curator = curator
    }

    deinit {
        task?.cancel()
    }

    func start() {
        guard task == nil else {
            logger.warning("SelfImprovementCuratorRunner.start() called but already running")
            return
        }

        isRunning = true
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                let sleepDuration = await self.nextSleepDuration()
                do {
                    try await Task.sleep(for: sleepDuration)
                } catch {
                    break
                }

                guard !Task.isCancelled else { break }
                await self.runIfNotOverlapping()
            }
            await self?.markStopped()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func running() -> Bool {
        isRunning
    }

    @discardableResult
    func triggerImmediately() async -> Bool {
        await runIfNotOverlapping()
    }

    private func nextSleepDuration() -> Duration {
        let jitterSeconds = Double(config.jitter.components.seconds)
        guard jitterSeconds > 0 else {
            return config.interval
        }
        return config.interval + .seconds(Double.random(in: 0..<jitterSeconds))
    }

    @discardableResult
    private func runIfNotOverlapping() async -> Bool {
        guard !isCuratorInProgress else {
            logger.warning("Skipping self-improvement curator: previous run still in progress")
            return false
        }

        isCuratorInProgress = true
        defer { isCuratorInProgress = false }

        logger.info("Running self-improvement curator")
        await curator()
        logger.info("Self-improvement curator completed")
        return true
    }

    private func markStopped() {
        isRunning = false
    }
}
