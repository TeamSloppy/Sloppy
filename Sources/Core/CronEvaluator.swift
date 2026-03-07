import Foundation

/// A very basic, simplified Cron expression evaluator.
/// Supports `*`, `*/X`, `X`, and `X,Y,Z`.
public struct CronEvaluator {
    public static func isDue(cronExpression: String, date: Date = Date()) -> Bool {
        let parts = cronExpression.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard parts.count == 5 else { return false }
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: date)
        
        let minute = components.minute ?? 0
        let hour = components.hour ?? 0
        let day = components.day ?? 0
        let month = components.month ?? 0
        let weekday = (components.weekday ?? 1) - 1 // 1 is Sunday in Foundation Calendar
        
        return match(part: parts[0], value: minute) &&
               match(part: parts[1], value: hour) &&
               match(part: parts[2], value: day) &&
               match(part: parts[3], value: month) &&
               matchWeekday(part: parts[4], value: weekday)
    }
    
    private static func match(part: String, value: Int) -> Bool {
        if part == "*" { return true }
        if part.hasPrefix("*/"), let divisor = Int(part.dropFirst(2)), divisor > 0 {
            return value % divisor == 0
        }
        let values = part.split(separator: ",").compactMap { Int($0) }
        if !values.isEmpty { return values.contains(value) }
        return Int(part) == value
    }
    
    private static func matchWeekday(part: String, value: Int) -> Bool {
        if part == "*" { return true }
        if part.hasPrefix("*/"), let divisor = Int(part.dropFirst(2)), divisor > 0 {
            return value % divisor == 0
        }
        let values = part.split(separator: ",").compactMap { Int($0) }
        if !values.isEmpty {
            return values.contains(value) || (values.contains(7) && value == 0) // Treat 7 as Sunday
        }
        if let exact = Int(part) {
            return exact == value || (exact == 7 && value == 0)
        }
        return false
    }
}
