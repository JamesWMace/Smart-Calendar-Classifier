import Foundation
@testable import SmartCalendarCore

enum TestClock {
    static let pacific = TimeZone(identifier: "America/Los_Angeles")!

    /// Friday, September 25, 2026, 10:00 AM Pacific.
    static let friday = local("2026-09-25T10:00")
    /// Monday, September 21, 2026, 10:00 AM Pacific.
    static let monday = local("2026-09-21T10:00")

    /// Parses "yyyy-MM-dd'T'HH:mm" or "yyyy-MM-dd" in `zone` (Pacific by default).
    static func local(_ string: String, zone: TimeZone = pacific) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = string.contains("T") ? "yyyy-MM-dd'T'HH:mm" : "yyyy-MM-dd"
        guard let date = formatter.date(from: string) else { fatalError("Bad test date \(string)") }
        return date
    }

    static func format(_ date: Date?, allDay: Bool = false) -> String {
        guard let date else { return "nil" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = pacific
        formatter.dateFormat = allDay ? "yyyy-MM-dd" : "yyyy-MM-dd'T'HH:mm"
        return formatter.string(from: date)
    }

    static func context(
        _ selection: String = "",
        at referenceDate: Date = friday,
        calendars: [String] = []
    ) -> CaptureContext {
        CaptureContext(selection: selection, referenceDate: referenceDate, timeZone: pacific, calendarNames: calendars)
    }
}
