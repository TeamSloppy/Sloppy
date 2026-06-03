import Foundation
import Logging

public struct KanbanMaintenanceSchedulerConfig: Sendable {
    public var interval: Duration
    public var jitter: Duration

    public init(
        interval: Duration = .seconds(60),
        jitter: Duration = .seconds(5)
    ) {
        self.interval = interval
        self.jitter = jitter
    }
}

public actor KanbanMaintenanceScheduler {
    private let config: KanbanMaintenanceSchedulerConfig
    private let logger: Logger
    private let maintenance: @Sendable () async -> Void
    private var task: Task<Void, Never>?
    private var isRunning = false
    private var isMaintenanceInProgress = false

    public init(
        config: KanbanMaintenanceSchedulerConfig = KanbanMaintenanceSchedulerConfig(),
        logger: Logger,
        maintenance: @escaping @Sendable () async -> Void
    ) {
        self.config = config
        self.logger = logger
        self.maintenance = maintenance
    }

    deinit {
        task?.cancel()
    }

    public func start() {
        guard task == nil else {
            logger.warning("KanbanMaintenanceScheduler.start() called but already running")
            return
        }

        isRunning = true
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                let sleepDuration = await self.sleepDuration()
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

    public func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    public func running() -> Bool {
        isRunning
    }

    @discardableResult
    public func triggerImmediately() async -> Bool {
        await runIfNotOverlapping()
    }

    private func sleepDuration() -> Duration {
        let jitterSeconds = Double(config.jitter.components.seconds)
        guard jitterSeconds > 0 else { return config.interval }
        return config.interval + .seconds(Double.random(in: 0..<jitterSeconds))
    }

    @discardableResult
    private func runIfNotOverlapping() async -> Bool {
        guard !isMaintenanceInProgress else {
            logger.warning("Skipping kanban maintenance: previous run still in progress")
            return false
        }
        isMaintenanceInProgress = true
        defer { isMaintenanceInProgress = false }

        await maintenance()
        return true
    }

    private func markStopped() {
        isRunning = false
    }
}
