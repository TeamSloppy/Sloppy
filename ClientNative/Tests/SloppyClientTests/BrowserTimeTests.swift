import Foundation
import Testing
@testable import SloppyClient

@Suite("Browser time and focus")
@MainActor
struct BrowserTimeTests {
    private func fixture(_ run: (BrowserTimeStore, UserDefaults, Date) throws -> Void) throws {
        let name = "BrowserTimeTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12)))
        try run(BrowserTimeStore(defaults: defaults, now: now, calendar: calendar), defaults, now)
    }

    @Test func countsForegroundSwitchesButExcludesSuspensionAndPersists() throws {
        try fixture { time, defaults, now in
            let first = try #require(URL(string: "https://www.example.com/a"))
            let second = try #require(URL(string: "https://other.test/"))
            time.sample(url: first, at: now)
            time.sample(url: second, at: now.addingTimeInterval(2))
            time.sample(url: nil, at: now.addingTimeInterval(5))
            time.sample(url: first, at: now.addingTimeInterval(500))
            time.sample(url: first, at: now.addingTimeInterval(1000))
            #expect(time.total(in: time.interval(week: false)) == 5)
            #expect(time.seconds(for: "example.com", in: time.interval(week: false)) == 2)
            let restored = BrowserTimeStore(defaults: defaults, now: now, calendar: time.calendar)
            #expect(restored.total(in: restored.interval(week: false)) == 5)
            restored.sample(url: nil, at: now.addingTimeInterval(3))
            #expect(restored.total(in: restored.interval(week: false)) == 5)
        }
    }

    @Test func usageSplitsAcrossMidnightAndLimitsReset() throws {
        try fixture { time, _, now in
            let url = try #require(URL(string: "https://example.com"))
            let midnight = time.calendar.startOfDay(for: now)
            time.sample(url: url, at: midnight.addingTimeInterval(-2))
            time.sample(url: nil, at: midnight.addingTimeInterval(2))
            #expect(time.total(in: time.interval(week: false)) == 2)
            let yesterday = DateInterval(start: midnight.addingTimeInterval(-86400), end: midnight)
            #expect(time.total(in: yesterday) == 2)
            time.setDailyLimit(1)
            for second in 0...65 { time.sample(url: url, at: midnight.addingTimeInterval(10 + Double(second))) }
            #expect(time.total(in: time.interval(week: false)) == 60)
            #expect(time.block(for: url) == .browserLimit)
            time.updateClock(midnight.addingTimeInterval(86400))
            #expect(time.block(for: url) == nil)
        }
    }

    @Test func siteLimitsIncludeSubdomainsWithoutMatchingOtherDomains() throws {
        try fixture { time, _, now in
            let url = try #require(URL(string: "https://news.example.com/a"))
            time.setSiteLimit(host: "https://www.example.com/settings", minutes: 1)
            for second in 0...65 { time.sample(url: url, at: now.addingTimeInterval(Double(second))) }
            #expect(time.seconds(for: "example.com", in: time.interval(week: false)) == 60)
            #expect(time.block(for: url) == .siteLimit)
            #expect(time.block(for: URL(string: "https://example.com/another")) == .siteLimit)
            #expect(time.block(for: URL(string: "https://notexample.com")) == nil)
            #expect(time.block(for: URL(string: "https://example.com.other.test")) == nil)
            time.setSiteLimit(host: "example.com", minutes: 0)
            #expect(time.block(for: url) == nil)
        }
    }

    @Test func focusPausesResumesRestoresAndTransitionsToBreakOnce() throws {
        try fixture { time, defaults, now in
            let url = try #require(URL(string: "https://www.example.com"))
            time.configureFocus(minutes: 1, breakMinutes: 1)
            time.setFocusSite("example.com", enabled: true)
            time.startFocus(at: now)
            #expect(time.block(for: url) == .focus)
            time.togglePause(at: now.addingTimeInterval(20))
            #expect(time.remaining == 40)
            #expect(time.block(for: url) == nil)
            let restored = BrowserTimeStore(defaults: defaults, now: now.addingTimeInterval(200), calendar: time.calendar)
            #expect(restored.isPaused)
            #expect(restored.remaining == 40)
            restored.togglePause(at: now.addingTimeInterval(200))
            restored.updateClock(now.addingTimeInterval(240))
            #expect(restored.phase == .rest)
            #expect(restored.remaining == 60)
            #expect(restored.completedSessions == 1)
            #expect(restored.block(for: url) == nil)
            restored.updateClock(now.addingTimeInterval(300))
            #expect(restored.phase == .ready)
            #expect(restored.completedSessions == 1)
        }
    }

    @Test func relaunchAfterBothDeadlinesCompletesOnlyOneSession() throws {
        try fixture { time, defaults, now in
            time.startFocus(at: now)
            let restored = BrowserTimeStore(defaults: defaults, now: now.addingTimeInterval(7200), calendar: time.calendar)
            #expect(restored.phase == .ready)
            #expect(restored.completedSessions == 1)
            restored.updateClock(now.addingTimeInterval(7300))
            #expect(restored.completedSessions == 1)
        }
    }

    @Test func chartsAggregateHoursAndClearingKeepsRules() throws {
        try fixture { time, _, now in
            let url = try #require(URL(string: "https://example.com"))
            time.setDailyLimit(90)
            time.setFocusSite("example.com", enabled: true)
            time.sample(url: url, at: now)
            time.sample(url: nil, at: now.addingTimeInterval(4))
            #expect(time.chart(week: false).count == 24)
            #expect(time.chart(week: false)[12] == 4)
            #expect(time.chart(week: true).reduce(0, +) == 4)
            time.clearUsage()
            #expect(time.total(in: time.interval(week: false)) == 0)
            #expect(time.dailyLimitMinutes == 90)
            #expect(time.focusSites == ["example.com"])
        }
    }

    @Test func workspaceBlocksLinkNavigationAndReleasesAfterFocusEnds() throws {
        try fixture { _, defaults, _ in
            let state = BrowserWorkspaceState(defaults: defaults)
            state.createBlankTab()
            let page = try #require(state.selectedPage)
            let url = try #require(URL(string: "https://news.example.com"))
            state.time.setFocusSite("example.com", enabled: true)
            state.time.startFocus()
            #expect(page.navigationBlock?(url) != nil)
            #expect(page.timeBlock == .focus)
            #expect(page.blockedNavigationURL == url)
            state.time.stopFocus()
            state.updateTimeUsage()
            #expect(page.timeBlock == nil)
            #expect(page.blockedNavigationURL == nil)
        }
    }

    @Test func inactiveWindowCannotStopTheActiveWindowSample() throws {
        try fixture { time, _, now in
            let url = try #require(URL(string: "https://example.com"))
            let first = UUID(), second = UUID()
            time.sample(url: url, owner: first, at: now)
            time.stopSampling(owner: second, at: now.addingTimeInterval(1))
            time.sample(url: url, owner: first, at: now.addingTimeInterval(2))
            time.sample(url: url, owner: second, at: now.addingTimeInterval(3))
            time.stopSampling(owner: first, at: now.addingTimeInterval(4))
            time.stopSampling(owner: second, at: now.addingTimeInterval(5))
            #expect(time.total(in: time.interval(week: false)) == 5)
        }
    }

    @Test func repeatedDaylightSavingHourHasItsOwnChartBucket() throws {
        try fixture { _, defaults, _ in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
            let noon = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12)))
            let time = BrowserTimeStore(defaults: defaults, now: noon, calendar: calendar)
            #expect(time.chart(week: false).count == 25)
            let dayStart = calendar.startOfDay(for: noon)
            let repeatedHour = dayStart.addingTimeInterval(7200)
            let url = try #require(URL(string: "https://example.com"))
            time.sample(url: url, at: repeatedHour.addingTimeInterval(-2))
            time.sample(url: nil, at: repeatedHour.addingTimeInterval(2))
            #expect(time.chart(week: false)[1] == 2)
            #expect(time.chart(week: false)[2] == 2)
        }
    }
}
