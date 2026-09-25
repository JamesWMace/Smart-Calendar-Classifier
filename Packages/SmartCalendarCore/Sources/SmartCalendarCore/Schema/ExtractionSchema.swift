import FoundationModels

// The shape the on-device model fills in via guided generation.
//
// The ~3B on-device model is reliable at *finding* the words that give a date ("next
// Tuesday", "October 20–22") but unreliable at filling optional numeric fields, so dates are
// captured as verbatim phrases and parsed deterministically by `DatePhraseParser`. Times are
// captured both ways: the phrase is parsed first, the model's own reading resolves
// ambiguities like "at 7". Properties are generated in declaration order, so phrases come
// before the fields derived from them.

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

    @Guide(description: "The exact words that say which day the event ends, only when it ends on a different day than it starts. Examples: 'Sunday', 'Oct 22'. Empty otherwise.")
    public var endDatePhrase: String

    @Guide(description: "The exact words that give the time of day, including any range. Examples: '3-5pm', '9:30am–12pm', 'at noon', '11:59pm'. Empty if no time is stated.")
    public var timePhrase: String

    @Guide(description: "allDay for holidays, birthdays, deadlines with no time of day, and multi-day trips or conferences. timed when a time of day is stated. unknown when the event normally has a time but none is stated.")
    public var timing: Timing

    @Guide(description: "The time of day the event starts. Omit if no time is stated.")
    public var startTime: TimeSpec?

    @Guide(description: "The time of day the event ends, from phrases like '3-5pm' or 'until 6'. Omit if not stated.")
    public var endTime: TimeSpec?

    @Guide(description: "Length in minutes when stated as a duration instead of an end time, e.g. '2 hour workshop' is 120. Omit otherwise.")
    public var durationMinutes: Int?

    @Guide(description: "The time zone exactly as written next to the time, e.g. 'ET', 'PST', 'CEST', 'UTC+2'. Omit if the text does not state one.")
    public var timeZone: String?

    @Guide(description: "The place, copied exactly from the text: a room, building, venue, city, street address or 'Zoom'. Omit if the text names no place.")
    public var location: String?

    @Guide(description: "A meeting link or event web address copied exactly from the text. Omit if none.")
    public var url: String?

    @Guide(description: "How the event repeats, only if the text says it repeats. A class meeting 'every Tuesday and Thursday' is ONE event with a weekly recurrence on both days. Omit otherwise.")
    public var recurrence: RecurrenceSpec?

    @Guide(description: "Reminder times in minutes before the start, only if the text explicitly asks for a reminder. Usually empty.")
    public var alertMinutesBefore: [Int]

    @Guide(description: "One or two plain sentences describing what the event is and anything the attendee needs to know or bring. Do not repeat the date and time.")
    public var summary: String

    @Guide(description: "The best matching calendar name, copied exactly from the list of the user's calendars. Omit if no list was given or nothing fits.")
    public var suggestedCalendar: String?

    public init(
        title: String,
        startDatePhrase: String = "",
        endDatePhrase: String = "",
        timePhrase: String = "",
        timing: Timing,
        startTime: TimeSpec? = nil,
        endTime: TimeSpec? = nil,
        durationMinutes: Int? = nil,
        timeZone: String? = nil,
        location: String? = nil,
        url: String? = nil,
        recurrence: RecurrenceSpec? = nil,
        alertMinutesBefore: [Int] = [],
        summary: String = "",
        suggestedCalendar: String? = nil
    ) {
        self.title = title
        self.startDatePhrase = startDatePhrase
        self.endDatePhrase = endDatePhrase
        self.timePhrase = timePhrase
        self.timing = timing
        self.startTime = startTime
        self.endTime = endTime
        self.durationMinutes = durationMinutes
        self.timeZone = timeZone
        self.location = location
        self.url = url
        self.recurrence = recurrence
        self.alertMinutesBefore = alertMinutesBefore
        self.summary = summary
        self.suggestedCalendar = suggestedCalendar
    }
}

@Generable
public enum Timing: Sendable {
    case timed
    case allDay
    case unknown
}

@Generable
public enum Weekday: Sendable, CaseIterable {
    case sunday, monday, tuesday, wednesday, thursday, friday, saturday

    /// Matches `Calendar`'s weekday numbering (Sunday = 1).
    public var calendarValue: Int {
        Weekday.allCases.firstIndex(of: self)! + 1
    }
}

@Generable
public struct TimeSpec: Sendable, Equatable {
    @Guide(description: "Hour on a 24-hour clock. 3pm is 15, noon is 12, midnight is 0, 9am is 9.", .range(0...23))
    public var hour: Int

    @Guide(description: "Minute past the hour.", .range(0...59))
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
