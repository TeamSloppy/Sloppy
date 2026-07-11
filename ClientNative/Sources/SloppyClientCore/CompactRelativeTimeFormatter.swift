import Foundation

public enum CompactRelativeTimeFormatter {
    public static func string(
        since date: Date,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        if date > referenceDate {
            return "now"
        }

        let components = calendar.dateComponents([.year, .month, .weekOfYear, .day, .hour, .minute], from: date, to: referenceDate)

        if let years = components.year, years > 0 {
            return "\(years)y"
        }
        if let months = components.month, months > 0 {
            return "\(months)mo"
        }
        if let weeks = components.weekOfYear, weeks > 0 {
            return "\(weeks)w"
        }
        if let days = components.day, days > 0 {
            return "\(days)d"
        }
        if let hours = components.hour, hours > 0 {
            return "\(hours)h"
        }
        if let minutes = components.minute, minutes > 0 {
            return "\(minutes)m"
        }

        return "now"
    }
}
