import Foundation
import Testing
@testable import SloppyClient

@Suite("Browser note day sections")
struct BrowserNoteDaySectionTests {
    @Test func groupsByLocalDayAndOrdersDaysNewestFirst() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 10800))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 0, minute: 15)))
        let today = BrowserNote(title: "Today", updatedAt: now)
        let pinned = BrowserNote(title: "Pinned", isPinned: true, updatedAt: now.addingTimeInterval(-60))
        let yesterday = BrowserNote(title: "Yesterday", updatedAt: now.addingTimeInterval(-1200))
        let older = BrowserNote(title: "Earlier", updatedAt: try #require(calendar.date(from:
            DateComponents(year: 2026, month: 10, day: 30, hour: 12))))
        let sections = BrowserNoteDaySection.sections(from: [older, pinned, today, yesterday], calendar: calendar)
        #expect(sections.map { $0.title(relativeTo: now, calendar: calendar) } == ["Today", "Yesterday", "30-10-2026"])
        #expect(sections.first?.notes.map(\.id) == [pinned.id, today.id])
        #expect(sections.flatMap(\.notes).count == 4)
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: now))
        #expect(sections.first?.title(relativeTo: tomorrow, calendar: calendar) == "Yesterday")
    }

    @Test func yesterdayHandlesA25HourDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 0, minute: 15)))
        let note = BrowserNote(updatedAt: try #require(calendar.date(from:
            DateComponents(year: 2026, month: 10, day: 25, hour: 0, minute: 30))))
        let section = try #require(BrowserNoteDaySection.sections(from: [note], calendar: calendar).first)
        #expect(section.title(relativeTo: now, calendar: calendar) == "Yesterday")
    }

    @Test func dateHeaderUsesCalendarYearAndEmptySearchHasNoSections() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let date = try #require(calendar.date(from: DateComponents(year: 2018, month: 12, day: 31)))
        let now = try #require(calendar.date(from: DateComponents(year: 2019, month: 1, day: 3)))
        let section = try #require(BrowserNoteDaySection.sections(from: [BrowserNote(updatedAt: date)], calendar: calendar).first)
        #expect(section.title(relativeTo: now, calendar: calendar) == "31-12-2018")
        #expect(BrowserNoteDaySection.sections(from: [], calendar: calendar).isEmpty)
    }
}
