import Foundation

/// Deterministic calendar arithmetic: pins a parsed `DateSpec` to a concrete day.
public struct DateResolver: Sendable {
    public let referenceDate: Date
    public let calendar: Calendar

    /// Month/day dates without a year that fall more than this many days in the past are
    /// assumed to mean next year ("Jan 5" read in December).
    public static let pastToleranceDays = 30

    public init(referenceDate: Date, timeZone: TimeZone) {
        self.referenceDate = referenceDate
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2 // Monday: "next Tuesday" said on a weekend means the coming one.
        self.calendar = calendar
    }

    public var today: Date { calendar.startOfDay(for: referenceDate) }

    /// Returns local midnight of the day `spec` refers to, or `nil` if it names no valid day.
    public func day(for spec: DateSpec) -> Date? {
        switch spec.kind {
        case .missing:
            return nil
        case .relative:
            return calendar.date(byAdding: .day, value: spec.daysFromToday ?? 0, to: today)
        case .weekday:
            guard let weekday = spec.weekday else { return nil }
            return day(for: weekday, weeksAhead: spec.weeksAhead ?? 0)
        case .absolute:
            guard let day = spec.day else { return nil }
            guard let month = spec.month else { return dayOfMonth(day) }
            return absoluteDay(year: spec.year, month: month, day: day)
        }
    }

    /// The first `weekday` on or after today; with `weeksAhead >= 1` ("next Tuesday") it is
    /// pushed out of the current week and then further by whole weeks.
    public func day(for weekday: Weekday, weeksAhead: Int) -> Date? {
        let match = DateComponents(weekday: weekday.calendarValue)
        let upcoming = calendar.component(.weekday, from: today) == weekday.calendarValue
            ? today
            : calendar.nextDate(after: today, matching: match, matchingPolicy: .nextTime)
        guard var result = upcoming else { return nil }
        if weeksAhead >= 1 {
            if calendar.isDate(result, equalTo: today, toGranularity: .weekOfYear) {
                result = calendar.date(byAdding: .day, value: 7, to: result)!
            }
            result = calendar.date(byAdding: .day, value: 7 * (weeksAhead - 1), to: result)!
        }
        return result
    }

    public func absoluteDay(year: Int?, month: Int, day: Int) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        if let year {
            return validDate(year: year, month: month, day: day)
        }
        let thisYear = calendar.component(.year, from: today)
        let cutoff = calendar.date(byAdding: .day, value: -Self.pastToleranceDays, to: today)!
        // Up to four years out so a yearless Feb 29 finds the next leap year.
        for year in thisYear...(thisYear + 4) {
            if let date = validDate(year: year, month: month, day: day), date >= cutoff { return date }
        }
        return nil
    }

    /// "the 14th": this month if it hasn't passed yet, otherwise the next month that has that day.
    public func dayOfMonth(_ day: Int) -> Date? {
        guard (1...31).contains(day) else { return nil }
        var components = calendar.dateComponents([.year, .month], from: today)
        for _ in 0..<12 {
            if let date = validDate(year: components.year!, month: components.month!, day: day), date >= today {
                return date
            }
            components.month! += 1
            if components.month! > 12 { components.month = 1; components.year! += 1 }
        }
        return nil
    }

    /// Rejects dates like Feb 30 instead of letting `Calendar` roll them into March.
    private func validDate(year: Int, month: Int, day: Int) -> Date? {
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day
        else { return nil }
        return date
    }
}
