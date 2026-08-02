import Foundation

public struct CronScheduleConfiguration: Sendable, Hashable {
    public enum Mode: String, CaseIterable, Sendable, Hashable {
        case daily
        case weekdays
        case weekly
        case interval
        case custom
    }

    public enum Weekday: Int, CaseIterable, Identifiable, Sendable, Hashable {
        case monday = 1
        case tuesday = 2
        case wednesday = 3
        case thursday = 4
        case friday = 5
        case saturday = 6
        case sunday = 0

        public var id: Int { rawValue }

        public var name: String {
            switch self {
            case .sunday: "Sunday"
            case .monday: "Monday"
            case .tuesday: "Tuesday"
            case .wednesday: "Wednesday"
            case .thursday: "Thursday"
            case .friday: "Friday"
            case .saturday: "Saturday"
            }
        }

        public var shortName: String {
            switch self {
            case .sunday: "S"
            case .monday: "M"
            case .tuesday: "T"
            case .wednesday: "W"
            case .thursday: "T"
            case .friday: "F"
            case .saturday: "S"
            }
        }
    }

    public var mode: Mode
    public var hour: Int
    public var minute: Int
    public var weekdays: Set<Weekday>
    public var intervalMinutes: Int
    public var customExpression: String

    public init(
        mode: Mode = .daily,
        hour: Int = 9,
        minute: Int = 0,
        weekdays: Set<Weekday> = [.monday],
        intervalMinutes: Int = 30,
        customExpression: String = "0 9 * * *"
    ) {
        self.mode = mode
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.intervalMinutes = intervalMinutes
        self.customExpression = customExpression
    }

    public init(expression: String) {
        self.init(customExpression: Self.normalized(expression))

        let parts = customExpression.split(separator: " ").map(String.init)
        guard parts.count == 5, Self.isValid(expression: customExpression) else {
            mode = .custom
            return
        }

        if let interval = Self.stepValue(parts[0]), parts.dropFirst().allSatisfy({ $0 == "*" }) {
            mode = .interval
            intervalMinutes = interval
            return
        }

        if parts[0] == "0", parts[1] == "*", parts.dropFirst(2).allSatisfy({ $0 == "*" }) {
            mode = .interval
            intervalMinutes = 60
            return
        }

        if parts[0] == "0", let hours = Self.stepValue(parts[1]), parts.dropFirst(2).allSatisfy({ $0 == "*" }) {
            mode = .interval
            intervalMinutes = hours * 60
            return
        }

        guard
            let parsedMinute = Int(parts[0]), (0...59).contains(parsedMinute),
            let parsedHour = Int(parts[1]), (0...23).contains(parsedHour),
            parts[2] == "*", parts[3] == "*"
        else {
            mode = .custom
            return
        }

        hour = parsedHour
        minute = parsedMinute

        if parts[4] == "*" {
            mode = .daily
            return
        }

        guard let parsedWeekdays = Self.parseWeekdays(parts[4]), !parsedWeekdays.isEmpty else {
            mode = .custom
            return
        }

        weekdays = parsedWeekdays
        if parsedWeekdays == Set([.monday, .tuesday, .wednesday, .thursday, .friday]) {
            mode = .weekdays
        } else {
            mode = .weekly
        }
    }

    public var expression: String {
        switch mode {
        case .daily:
            "\(minute) \(hour) * * *"
        case .weekdays:
            "\(minute) \(hour) * * 1,2,3,4,5"
        case .weekly:
            "\(minute) \(hour) * * \(weekdayExpression)"
        case .interval:
            if intervalMinutes < 60 {
                "*/\(intervalMinutes) * * * *"
            } else if intervalMinutes == 60 {
                "0 * * * *"
            } else {
                "0 */\(intervalMinutes / 60) * * *"
            }
        case .custom:
            customExpression
        }
    }

    public var summary: String {
        let time = String(format: "%02d:%02d", hour, minute)
        switch mode {
        case .daily:
            return "Every day at \(time)"
        case .weekdays:
            return "Every weekday at \(time)"
        case .weekly:
            guard !weekdays.isEmpty else { return "Choose at least one day" }
            let names = Weekday.allCases.filter(weekdays.contains).map(\.name)
            return "Every \(Self.joinedList(names)) at \(time)"
        case .interval:
            if intervalMinutes == 60 { return "Every hour" }
            if intervalMinutes.isMultiple(of: 60) {
                return "Every \(intervalMinutes / 60) hours"
            }
            return "Every \(intervalMinutes) minutes"
        case .custom:
            return Self.isValid(expression: customExpression) ? "Custom schedule" : "Invalid cron expression"
        }
    }

    public var isValid: Bool {
        switch mode {
        case .weekly:
            isTimeValid && !weekdays.isEmpty
        case .interval:
            (1...59).contains(intervalMinutes)
                || (intervalMinutes.isMultiple(of: 60) && (60...(23 * 60)).contains(intervalMinutes))
        case .custom:
            Self.isValid(expression: customExpression)
        case .daily, .weekdays:
            isTimeValid
        }
    }

    public static func describe(_ expression: String) -> String {
        CronScheduleConfiguration(expression: expression).summary
    }

    public static func isValid(expression: String) -> Bool {
        let parts = normalized(expression).split(separator: " ").map(String.init)
        guard parts.count == 5 else { return false }
        let bounds = [(0, 59), (0, 23), (1, 31), (1, 12), (0, 7)]
        return zip(parts, bounds).allSatisfy { part, bound in
            isValid(part: part, lowerBound: bound.0, upperBound: bound.1)
        }
    }

    private var weekdayExpression: String {
        weekdays
            .sorted { $0.rawValue < $1.rawValue }
            .map { String($0.rawValue) }
            .joined(separator: ",")
    }

    private var isTimeValid: Bool {
        (0...23).contains(hour) && (0...59).contains(minute)
    }

    private static func normalized(_ expression: String) -> String {
        expression
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }

    private static func stepValue(_ part: String) -> Int? {
        guard part.hasPrefix("*/"), let value = Int(part.dropFirst(2)), value > 0 else { return nil }
        return value
    }

    private static func parseWeekdays(_ part: String) -> Set<Weekday>? {
        let values = part.split(separator: ",")
        guard !values.isEmpty else { return nil }

        var result: Set<Weekday> = []
        for value in values {
            guard let rawValue = Int(value), (0...7).contains(rawValue) else { return nil }
            let normalizedValue = rawValue == 7 ? 0 : rawValue
            guard let weekday = Weekday(rawValue: normalizedValue) else { return nil }
            result.insert(weekday)
        }
        return result
    }

    private static func isValid(part: String, lowerBound: Int, upperBound: Int) -> Bool {
        if part == "*" { return true }
        if let step = stepValue(part) {
            return step <= upperBound
        }

        let values = part.split(separator: ",", omittingEmptySubsequences: false)
        guard !values.isEmpty else { return false }
        return values.allSatisfy { value in
            guard let number = Int(value) else { return false }
            return (lowerBound...upperBound).contains(number)
        }
    }

    private static func joinedList(_ values: [String]) -> String {
        switch values.count {
        case 0:
            return ""
        case 1:
            return values[0]
        case 2:
            return values.joined(separator: " and ")
        default:
            guard let last = values.last else { return "" }
            return values.dropLast().joined(separator: ", ") + ", and " + last
        }
    }
}
