import Foundation
import Observation

struct BrowserTimeBucket: Codable {
    var hour: Date
    var host: String
    var seconds: TimeInterval
}

struct BrowserSiteTime: Identifiable {
    let host: String
    var seconds: TimeInterval
    var id: String { host }
}

enum BrowserTimeBlock: String {
    case focus, siteLimit, browserLimit
    var message: String {
        switch self {
        case .focus: "This site is paused during your focus session."
        case .siteLimit: "You have reached this site’s daily time limit."
        case .browserLimit: "You have reached your daily browsing limit."
        }
    }
}

/// Local foreground usage only. Never uploads URLs or imports time from history.
@Observable @MainActor
final class BrowserTimeStore {
    static let shared = BrowserTimeStore()
    enum Phase: String, Codable { case ready, focus, rest }
    private struct Snapshot: Codable {
        var buckets: [BrowserTimeBucket] = []
        var dailyLimitMinutes = 0
        var siteLimits: [String: Int] = [:]
        var focusSites: Set<String> = []
        var focusMinutes = 25
        var breakMinutes = 5
        var phase = Phase.ready
        var deadline: Date?
        var pausedSeconds: TimeInterval?
        var completedSessions = 0
    }
    private static let key = "sloppy.browser.time.v1"
    private let defaults: UserDefaults
    private var snapshot: Snapshot
    private(set) var clock: Date
    @ObservationIgnored private var activeHost: String?
    @ObservationIgnored private var lastSample: Date?
    @ObservationIgnored private var activeOwner: UUID?
    let calendar: Calendar

    init(defaults: UserDefaults = .standard, now: Date = .now, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        clock = now
        snapshot = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } ?? Snapshot()
        updateClock(now)
    }

    var dailyLimitMinutes: Int { snapshot.dailyLimitMinutes }
    var siteLimits: [String: Int] { snapshot.siteLimits }
    var focusSites: Set<String> { snapshot.focusSites }
    var focusMinutes: Int { snapshot.focusMinutes }
    var breakMinutes: Int { snapshot.breakMinutes }
    var phase: Phase { snapshot.phase }
    var isPaused: Bool { snapshot.pausedSeconds != nil }
    var completedSessions: Int { snapshot.completedSessions }
    var remaining: TimeInterval {
        snapshot.pausedSeconds ?? max(0, snapshot.deadline?.timeIntervalSince(clock) ?? Double(focusMinutes * 60))
    }
    var progress: Double {
        let duration = Double((phase == .rest ? breakMinutes : focusMinutes) * 60)
        return min(1, max(0, 1 - remaining / duration))
    }

    static func host(for url: URL?) -> String? {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased() else { return nil }
        let trimmed = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return trimmed.hasPrefix("www.") ? String(trimmed.dropFirst(4)) : trimmed
    }

    static func normalizedHost(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return host(for: URL(string: text.contains("://") ? text : "https://" + text))
    }

    func setDailyLimit(_ minutes: Int) {
        snapshot.dailyLimitMinutes = max(0, min(1440, minutes)); persist()
    }

    func setSiteLimit(host: String, minutes: Int) {
        guard let host = Self.normalizedHost(host) else { return }
        snapshot.siteLimits[host] = minutes > 0 ? min(1440, minutes) : nil
        persist()
    }

    func setFocusSite(_ host: String, enabled: Bool) {
        guard let host = Self.normalizedHost(host) else { return }
        if enabled { snapshot.focusSites.insert(host) }
        else { snapshot.focusSites.remove(host) }
        persist()
    }

    func configureFocus(minutes: Int, breakMinutes: Int) {
        guard phase == .ready else { return }
        snapshot.focusMinutes = max(1, min(120, minutes))
        snapshot.breakMinutes = max(1, min(30, breakMinutes))
        persist()
    }

    func startFocus(at now: Date = .now) {
        clock = now
        snapshot.phase = .focus
        snapshot.pausedSeconds = nil
        snapshot.deadline = now.addingTimeInterval(Double(focusMinutes * 60))
        persist()
    }

    func togglePause(at now: Date = .now) {
        updateClock(now)
        guard phase != .ready else { return }
        if let seconds = snapshot.pausedSeconds {
            snapshot.deadline = now.addingTimeInterval(seconds)
            snapshot.pausedSeconds = nil
        } else {
            snapshot.pausedSeconds = remaining
            snapshot.deadline = nil
        }
        persist()
    }

    func stopFocus() {
        snapshot.phase = .ready; snapshot.deadline = nil; snapshot.pausedSeconds = nil
        persist()
    }

    func updateClock(_ now: Date = .now) {
        clock = now
        if let deadline = snapshot.deadline, deadline <= now {
            if phase == .focus {
                snapshot.completedSessions += 1
                snapshot.phase = .rest
                snapshot.deadline = deadline.addingTimeInterval(Double(breakMinutes * 60))
            }
            if let end = snapshot.deadline, end <= now {
                snapshot.phase = .ready; snapshot.deadline = nil
            }
            persist()
        }
    }

    /// Short samples avoid charging time spent asleep or suspended between ticks.
    func sample(url: URL?, at now: Date = .now) {
        updateClock(now)
        if let previous = lastSample, let host = activeHost {
            let elapsed = now.timeIntervalSince(previous)
            if elapsed > 0, elapsed <= 5 {
                record(host: host, from: previous, to: now)
            }
        }
        activeHost = Self.host(for: url)
        lastSample = now
    }

    func sample(url: URL?, owner: UUID, at now: Date = .now) {
        sample(url: url, at: now)
        activeOwner = owner
    }

    func stopSampling(owner: UUID, at now: Date = .now) {
        updateClock(now)
        guard activeOwner == owner else { return }
        sample(url: nil, at: now)
        activeOwner = nil
    }

    private func record(host: String, from start: Date, to end: Date) {
        var cursor = start
        while cursor < end, let hour = calendar.dateInterval(of: .hour, for: cursor) {
            let stop = min(hour.end, end)
            let day = calendar.dateInterval(of: .day, for: cursor) ?? hour
            let total = total(in: day)
            let browserRemaining = dailyLimitMinutes > 0 ? max(0, Double(dailyLimitMinutes * 60) - total) : .infinity
            let siteRemaining = remainingSiteAllowance(for: host, in: day)
            let seconds = min(stop.timeIntervalSince(cursor), browserRemaining, siteRemaining)
            if seconds > 0 {
                if let index = snapshot.buckets.firstIndex(where: { $0.hour == hour.start && $0.host == host }) {
                    snapshot.buckets[index].seconds += seconds
                } else { snapshot.buckets.append(.init(hour: hour.start, host: host, seconds: seconds)) }
            }
            cursor = stop
        }
        let cutoff = calendar.date(byAdding: .day, value: -35, to: end) ?? end
        snapshot.buckets.removeAll { $0.hour < cutoff }
        persist()
    }

    func interval(week: Bool) -> DateInterval {
        calendar.dateInterval(of: week ? .weekOfYear : .day, for: clock)
            ?? DateInterval(start: clock, duration: 1)
    }

    func sites(in interval: DateInterval) -> [BrowserSiteTime] {
        var totals: [String: TimeInterval] = [:]
        for bucket in snapshot.buckets where interval.contains(bucket.hour) && bucket.hour < interval.end {
            totals[bucket.host, default: 0] += bucket.seconds
        }
        return totals.map { BrowserSiteTime(host: $0.key, seconds: $0.value) }
            .sorted { $0.seconds == $1.seconds ? $0.host < $1.host : $0.seconds > $1.seconds }
    }

    func total(in interval: DateInterval) -> TimeInterval { sites(in: interval).reduce(0) { $0 + $1.seconds } }

    func seconds(for host: String, in interval: DateInterval) -> TimeInterval {
        sites(in: interval).filter { Self.matches($0.host, rule: host) }.reduce(0) { $0 + $1.seconds }
    }

    func chart(week: Bool) -> [TimeInterval] {
        let range = interval(week: week)
        let component: Calendar.Component = week ? .day : .hour
        var cursor = range.start
        var result: [TimeInterval] = []
        while cursor < range.end, let end = calendar.date(byAdding: component, value: 1, to: cursor), end > cursor {
            result.append(total(in: DateInterval(start: cursor, end: min(end, range.end))))
            cursor = end
        }
        return result
    }

    func block(for url: URL?, at now: Date? = nil) -> BrowserTimeBlock? {
        guard let host = Self.host(for: url) else { return nil }
        let date = now ?? clock
        if phase == .focus, let deadline = snapshot.deadline, date < deadline,
           focusSites.contains(where: { Self.matches(host, rule: $0) }) { return .focus }
        let day = calendar.dateInterval(of: .day, for: date) ?? interval(week: false)
        if dailyLimitMinutes > 0, total(in: day) >= Double(dailyLimitMinutes * 60) { return .browserLimit }
        if remainingSiteAllowance(for: host, in: day) <= 0 { return .siteLimit }
        return nil
    }

    private func remainingSiteAllowance(for host: String, in day: DateInterval) -> TimeInterval {
        siteLimits.filter { Self.matches(host, rule: $0.key) }.map {
            max(0, Double($0.value * 60) - seconds(for: $0.key, in: day))
        }.min() ?? .infinity
    }

    private static func matches(_ host: String, rule: String) -> Bool {
        host == rule || host.hasSuffix("." + rule)
    }

    func clearUsage() {
        snapshot.buckets = []; lastSample = nil; activeHost = nil; persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: Self.key) }
    }
}
