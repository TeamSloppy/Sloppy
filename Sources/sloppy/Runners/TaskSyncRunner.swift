import Foundation
import Logging

struct ProjectTaskSyncScheduleEntry: Sendable, Equatable {
    var projectId: String
    var intervalMinutes: Int
    var lastRunAt: Date?
}

actor TaskSyncRunner {
    private let logger: Logger
    private let scheduleProvider: @Sendable () async -> [ProjectTaskSyncScheduleEntry]
    private let executor: @Sendable (String) async -> Void
    private var task: Task<Void, Never>?
    private var isRunning = false
    private var lastRunMinuteKey: String?
    private var activeProjectIDs: Set<String> = []

    init(
        logger: Logger,
        scheduleProvider: @escaping @Sendable () async -> [ProjectTaskSyncScheduleEntry],
        executor: @escaping @Sendable (String) async -> Void
    ) {
        self.logger = logger
        self.scheduleProvider = scheduleProvider
        self.executor = executor
    }

    deinit {
        task?.cancel()
    }

    func start() {
        guard task == nil else {
            logger.warning("TaskSyncRunner.start() called but already running")
            return
        }
        logger.info("Starting TaskSyncRunner")
        isRunning = true
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                let now = Date()
                let currentSecond = Calendar.current.component(.second, from: now)
                let sleepDuration = max(1, 60 - currentSecond + 1)
                do {
                    try await Task.sleep(nanoseconds: UInt64(sleepDuration) * 1_000_000_000)
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                await self.tick(date: Date(), ignoreMinuteGuard: false)
            }
            await self?.markStopped()
        }
    }

    func stop() {
        logger.info("Stopping TaskSyncRunner")
        task?.cancel()
        task = nil
        isRunning = false
        lastRunMinuteKey = nil
        activeProjectIDs.removeAll()
    }

    func running() -> Bool {
        isRunning
    }

    func triggerImmediately() async {
        await tick(date: Date(), ignoreMinuteGuard: true)
    }

    private func tick(date: Date, ignoreMinuteGuard: Bool) async {
        let minuteKey = Self.minuteKey(for: date)
        if !ignoreMinuteGuard && minuteKey == lastRunMinuteKey {
            return
        }
        lastRunMinuteKey = minuteKey

        let schedules = await scheduleProvider()
        for schedule in schedules where isDue(schedule: schedule, at: date) {
            guard activeProjectIDs.insert(schedule.projectId).inserted else {
                logger.debug("Skipping task sync for \(schedule.projectId): already running")
                continue
            }
            await executor(schedule.projectId)
            finish(projectId: schedule.projectId)
        }
    }

    private func finish(projectId: String) {
        activeProjectIDs.remove(projectId)
    }

    private func markStopped() {
        isRunning = false
    }

    private func isDue(schedule: ProjectTaskSyncScheduleEntry, at date: Date) -> Bool {
        guard schedule.intervalMinutes >= 1 else { return false }
        guard let lastRunAt = schedule.lastRunAt else { return true }
        return date.timeIntervalSince(lastRunAt) >= Double(schedule.intervalMinutes * 60)
    }

    private static func minuteKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
