import Foundation

/// A day as written, before it is pinned to the calendar by `DateResolver`.
public struct DateSpec: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// A day of the month, with or without month and year: "Oct 3", "10/3/2026", "the 14th".
        case absolute
        /// A day of the week: "Tuesday", "next Friday".
        case weekday
        /// Relative to today: "today", "tomorrow", "in 3 days".
        case relative
        case missing
    }

    public var kind: Kind
    public var year: Int?
    public var month: Int?
    public var day: Int?
    public var weekday: Weekday?
    /// 0 for "Tuesday"/"this Tuesday", 1 for "next Tuesday", 2 for "Tuesday after next".
    public var weeksAhead: Int?
    public var daysFromToday: Int?

    public init(
        kind: Kind,
        year: Int? = nil,
        month: Int? = nil,
        day: Int? = nil,
        weekday: Weekday? = nil,
        weeksAhead: Int? = nil,
        daysFromToday: Int? = nil
    ) {
        self.kind = kind
        self.year = year
        self.month = month
        self.day = day
        self.weekday = weekday
        self.weeksAhead = weeksAhead
        self.daysFromToday = daysFromToday
    }
}
