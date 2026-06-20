import Foundation
import Logging

struct AutodreamRunnerConfig: Sendable {
    var interval: Duration
    var jitter: Duration

    init(interval: Duration, jitter: Duration) {
        self.interval = interval
        self.jitter = jitter
    }
}

actor AutodreamRunner {
    private let config: AutodreamRunnerConfig
    private let logger: Logger
    private let run: @Sendable () async -> Void
    private var task: Task<Void, Never>?
    private var isRunning = false
    private var isPassInProgress = false

    init(
        config: AutodreamRunnerConfig,
        logger: Logger,
        run: @escaping @Sendable () async -> Void
    ) {
        self.config = config
        self.logger = logger
        self.run = run
    }

    deinit {
        task?.cancel()
    }

    func start() {
        guard task == nil else {
            logger.warning("AutodreamRunner.start() called but already running")
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
        guard !isPassInProgress else {
            logger.warning("Skipping autodream pass: previous run still in progress")
            return false
        }

        isPassInProgress = true
        defer { isPassInProgress = false }

        logger.info("Running autodream pass")
        await run()
        logger.info("Autodream pass completed")
        return true
    }

    private func markStopped() {
        isRunning = false
    }
}
