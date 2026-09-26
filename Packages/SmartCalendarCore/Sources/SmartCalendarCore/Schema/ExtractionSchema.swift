import FoundationModels

// The shape the on-device model fills in via guided generation.
//
// Generation time is dominated by output tokens, so the model only produces what needs
// understanding: a title, *which words* give the dates and times, the place, repetition and
// a calendar. Everything that can be read deterministically — the dates and times
// themselves, time zones, links, durations, reminders — is parsed in Swift from those
// phrases and the event's line (`EventResolver`). Keeping the schema this small made
// extraction about 2.4x faster than a 15-field version. Properties are generated in
// declaration order.

@Generable
public struct ExtractionResult: Sendable {
    @Guide(description: "Every distinct calendar event the SELECTED TEXT describes or refers to, in the order they appear. Empty if it describes no event, such as a thank-you note.", .maximumCount(20))
    public var events: [ExtractedEvent]

    public init(events: [ExtractedEvent]) {
        self.events = events
    }
}

@Generable
public struct ExtractedEvent: Sendable {
    @Guide(description: "Concise calendar title of 2 to 8 words. Include specific names when known: course codes, company, person, flight number. Examples: 'CS 153 Midterm', 'Dinner with Priya', 'Flight UA 1234 SFO to JFK'. Never include the date or time in the title.")
    public var title: String

    @Guide(description: "The exact words from the text that say which day the event starts, without the time. Examples: 'next Tuesday', 'tomorrow', 'Oct 15', '10/05/2026', 'the 14th', 'October 20–22'. Empty if the text names no day.")
    public var startDatePhrase: String

    @Guide(description: "The exact words that say which DAY the event ends, only when it ends on a different day than it starts. Day words only, never a time: for '3-5pm' this is empty. Examples: 'Sunday', 'Oct 22'. Empty otherwise.")
    public var endDatePhrase: String

    @Guide(description: "The exact words that give the time of day, including any range and time zone. Examples: '3-5pm', '9:30am–12pm', 'at noon', '3pm ET'. Empty if no time is stated.")
    public var timePhrase: String

    @Guide(description: "The place, copied exactly from the text: a room, building, venue, city, street address or 'Zoom'. Omit if the text names no place.")
    public var location: String?

    @Guide(description: "How the event repeats, only if the text says it repeats. A class meeting 'every Tuesday and Thursday' is ONE event with a weekly recurrence on both days. Omit otherwise.")
    public var recurrence: RecurrenceSpec?

    @Guide(description: "The best matching calendar name, copied exactly from the list of the user's calendars. Omit if no list was given or nothing fits.")
    public var suggestedCalendar: String?

    public init(
        title: String,
        startDatePhrase: String = "",
        endDatePhrase: String = "",
        timePhrase: String = "",
        location: String? = nil,
        recurrence: RecurrenceSpec? = nil,
        suggestedCalendar: String? = nil
    ) {
        self.title = title
        self.startDatePhrase = startDatePhrase
        self.endDatePhrase = endDatePhrase
        self.timePhrase = timePhrase
        self.location = location
        self.recurrence = recurrence
        self.suggestedCalendar = suggestedCalendar
    }
}

@Generable
public enum Weekday: Sendable, CaseIterable {
    case sunday, monday, tuesday, wednesday, thursday, friday, saturday

    /// Matches `Calendar`'s weekday numbering (Sunday = 1).
    public var calendarValue: Int {
        Weekday.allCases.firstIndex(of: self)! + 1
    }
}

/// A time of day on a 24-hour clock, as parsed from a time phrase.
public struct TimeSpec: Sendable, Equatable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }
}

@Generable
public struct RecurrenceSpec: Sendable {
    public var frequency: Frequency

    @Guide(description: "Repeat every N units: 1 for every week, 2 for every other week.", .range(1...52))
    public var interval: Int

    @Guide(description: "For weekly repeats on specific days, e.g. 'every Tuesday and Thursday'. Empty otherwise.")
    public var weekdays: [Weekday]

    @Guide(description: "The exact words giving the last day it repeats, e.g. 'Dec 4'. Empty if not stated.")
    public var untilPhrase: String

    @Guide(description: "Total number of occurrences, if stated, e.g. '6 sessions' is 6.")
    public var occurrenceCount: Int?

    public init(
        frequency: Frequency,
        interval: Int = 1,
        weekdays: [Weekday] = [],
        untilPhrase: String = "",
        occurrenceCount: Int? = nil
    ) {
        self.frequency = frequency
        self.interval = interval
        self.weekdays = weekdays
        self.untilPhrase = untilPhrase
        self.occurrenceCount = occurrenceCount
    }
}

@Generable
public enum Frequency: Sendable {
    case daily, weekly, monthly, yearly
}
