import Foundation

struct BrowserNoteDaySection: Identifiable {
    let day: Date
    let notes: [BrowserNote]
    var id: Date { day }

    static func sections(from notes: [BrowserNote], calendar: Calendar = .current) -> [Self] {
        Dictionary(grouping: notes) { calendar.startOfDay(for: $0.updatedAt) }
            .map { Self(day: $0.key, notes: $0.value) }
            .sorted { $0.day > $1.day }
    }

    func title(relativeTo now: Date, calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now)
        if day == today { return String(localized: "Today") }
        if day == calendar.date(byAdding: .day, value: -1, to: today) { return String(localized: "Yesterday") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "dd-MM-yyyy"
        return formatter.string(from: day)
    }
}
