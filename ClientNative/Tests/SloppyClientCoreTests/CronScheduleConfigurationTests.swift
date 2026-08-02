import Testing
@testable import SloppyClientCore

@Suite("Cron schedule configuration")
struct CronScheduleConfigurationTests {
    @Test("parses a daily schedule")
    func parsesDailySchedule() {
        let schedule = CronScheduleConfiguration(expression: "15 9 * * *")

        #expect(schedule.mode == .daily)
        #expect(schedule.hour == 9)
        #expect(schedule.minute == 15)
        #expect(schedule.summary == "Every day at 09:15")
    }

    @Test("parses weekdays generated for the runtime evaluator")
    func parsesWeekdaySchedule() {
        let schedule = CronScheduleConfiguration(expression: "0 10 * * 1,2,3,4,5")

        #expect(schedule.mode == .weekdays)
        #expect(schedule.expression == "0 10 * * 1,2,3,4,5")
        #expect(schedule.summary == "Every weekday at 10:00")
    }

    @Test("generates a selected weekday schedule")
    func generatesWeeklySchedule() {
        let schedule = CronScheduleConfiguration(
            mode: .weekly,
            hour: 18,
            minute: 30,
            weekdays: [.monday, .wednesday, .friday]
        )

        #expect(schedule.expression == "30 18 * * 1,3,5")
        #expect(schedule.summary == "Every Monday, Wednesday, and Friday at 18:30")
    }

    @Test("parses minute and hour intervals")
    func parsesIntervals() {
        let minutes = CronScheduleConfiguration(expression: "*/15 * * * *")
        let hourly = CronScheduleConfiguration(expression: "0 * * * *")
        let hours = CronScheduleConfiguration(expression: "0 */3 * * *")

        #expect(minutes.mode == .interval)
        #expect(minutes.intervalMinutes == 15)
        #expect(minutes.summary == "Every 15 minutes")
        #expect(hourly.mode == .interval)
        #expect(hourly.intervalMinutes == 60)
        #expect(hourly.summary == "Every hour")
        #expect(hours.mode == .interval)
        #expect(hours.intervalMinutes == 180)
        #expect(hours.summary == "Every 3 hours")
    }

    @Test("keeps unsupported and invalid schedules editable as custom cron")
    func preservesCustomSchedules() {
        let unsupported = CronScheduleConfiguration(expression: "0 9 1 * *")
        let invalid = CronScheduleConfiguration(expression: "not a cron expression")
        let unsupportedInterval = CronScheduleConfiguration(mode: .interval, intervalMinutes: 90)

        #expect(unsupported.mode == .custom)
        #expect(unsupported.customExpression == "0 9 1 * *")
        #expect(unsupported.isValid)
        #expect(invalid.mode == .custom)
        #expect(!invalid.isValid)
        #expect(!unsupportedInterval.isValid)
    }
}
