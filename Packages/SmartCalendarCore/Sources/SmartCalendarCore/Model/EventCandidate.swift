import Foundation

/// A fully resolved event, ready for the preview panel and, once complete, for EventKit.
/// Dates are absolute instants; for all-day events they are local midnights and `end` is
/// the *last* day (inclusive).
public struct EventCandidate: Identifiable, Sendable, Equatable {
    public enum Field: Sendable, Hashable, CaseIterable {
        case title, date, startTime
    }

    public var id = UUID()
    public var title: String
    public var isAllDay: Bool
    /// `nil` means no date was found; the user must pick one.
    public var start: Date?
    public var end: Date?
    /// True when `end` was filled from the default duration rather than the text.
    public var endIsAssumed: Bool
    /// True when `start` has a day but the time of day still has to be entered.
    public var startTimeMissing: Bool
    /// A time of day the text did state when it stated no day ("call at 3pm"), expressed in
    /// `sourceTimeZone ?? local`. Applied once the user picks the day.
    public var startTimeHint: DateComponents?
    public var location: String?
    public var url: URL?
    public var notes: String
    public var recurrence: Recurrence?
    public var alertMinutesBefore: [Int]
    public var suggestedCalendarName: String?
    /// The zone the text was written in, when it differs from the user's.
    public var sourceTimeZone: TimeZone?

    public init(
        title: String,
        isAllDay: Bool,
        start: Date?,
        end: Date?,
        endIsAssumed: Bool = false,
        startTimeMissing: Bool = false,
        startTimeHint: DateComponents? = nil,
        location: String? = nil,
        url: URL? = nil,
        notes: String = "",
        recurrence: Recurrence? = nil,
        alertMinutesBefore: [Int] = [],
        suggestedCalendarName: String? = nil,
        sourceTimeZone: TimeZone? = nil
    ) {
        self.title = title
        self.isAllDay = isAllDay
        self.start = start
        self.end = end
        self.endIsAssumed = endIsAssumed
        self.startTimeMissing = startTimeMissing
        self.startTimeHint = startTimeHint
        self.location = location
        self.url = url
        self.notes = notes
        self.recurrence = recurrence
        self.alertMinutesBefore = alertMinutesBefore
        self.suggestedCalendarName = suggestedCalendarName
        self.sourceTimeZone = sourceTimeZone
    }

    /// Fields the user must fill in before the event can be saved.
    public var missingFields: Set<Field> {
        var missing: Set<Field> = []
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missing.insert(.title) }
        if start == nil { missing.insert(.date) }
        if !isAllDay && startTimeMissing { missing.insert(.startTime) }
        return missing
    }

    public var isComplete: Bool { missingFields.isEmpty }
}

/// EventKit-independent recurrence; the app maps it to `EKRecurrenceRule`.
public struct Recurrence: Sendable, Equatable {
    public enum Frequency: Sendable, Equatable { case daily, weekly, monthly, yearly }

    public var frequency: Frequency
    public var interval: Int
    /// Calendar weekday numbers (Sunday = 1).
    public var weekdays: [Int]
    public var until: Date?
    public var occurrenceCount: Int?

    public init(frequency: Frequency, interval: Int = 1, weekdays: [Int] = [], until: Date? = nil, occurrenceCount: Int? = nil) {
        self.frequency = frequency
        self.interval = interval
        self.weekdays = weekdays
        self.until = until
        self.occurrenceCount = occurrenceCount
    }
}
