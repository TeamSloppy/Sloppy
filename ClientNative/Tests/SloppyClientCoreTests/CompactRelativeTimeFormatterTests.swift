import Foundation
import Testing
@testable import SloppyClientCore

struct CompactRelativeTimeFormatterTests {
    @Test
    func formatsCompactRelativeUnits() {
        let calendar = Calendar(identifier: .gregorian)
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(
            CompactRelativeTimeFormatter.string(
                since: referenceDate.addingTimeInterval(-60),
                referenceDate: referenceDate,
                calendar: calendar
            ) == "1m"
        )
        #expect(
            CompactRelativeTimeFormatter.string(
                since: referenceDate.addingTimeInterval(-3_600),
                referenceDate: referenceDate,
                calendar: calendar
            ) == "1h"
        )
        #expect(
            CompactRelativeTimeFormatter.string(
                since: referenceDate.addingTimeInterval(-86_400),
                referenceDate: referenceDate,
                calendar: calendar
            ) == "1d"
        )
        #expect(
            CompactRelativeTimeFormatter.string(
                since: referenceDate.addingTimeInterval(-604_800),
                referenceDate: referenceDate,
                calendar: calendar
            ) == "1w"
        )
        #expect(
            CompactRelativeTimeFormatter.string(
                since: calendar.date(byAdding: .month, value: -1, to: referenceDate) ?? referenceDate,
                referenceDate: referenceDate,
                calendar: calendar
            ) == "1mo"
        )
        #expect(
            CompactRelativeTimeFormatter.string(
                since: calendar.date(byAdding: .year, value: -1, to: referenceDate) ?? referenceDate,
                referenceDate: referenceDate,
                calendar: calendar
            ) == "1y"
        )
    }

    @Test
    func formatsVeryRecentDatesAsNow() {
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(
            CompactRelativeTimeFormatter.string(
                since: referenceDate.addingTimeInterval(-20),
                referenceDate: referenceDate
            ) == "now"
        )
    }
}
