import Foundation
import Testing
@testable import SmartCalendarCore

@Suite("EventResolver")
struct EventResolverTests {
    /// Without an explicit context, the "selection" is the event's own words, as it would be
    /// for a real capture (phrases not in the text are dropped by grounding).
    private func resolve(_ event: ExtractedEvent, context: CaptureContext? = nil) -> EventCandidate {
        let text = [event.title, event.startDatePhrase, event.endDatePhrase, event.timePhrase, event.location ?? ""]
            .joined(separator: " ")
        return EventResolver(context: context ?? TestClock.context(text)).resolve(event)
    }

    @Test func timedWithEndTime() {
        let c = resolve(ExtractedEvent(
            title: " Design Review ", startDatePhrase: "next Tuesday", timePhrase: "from 3-5pm", location: "in the Orion Room"
        ), context: TestClock.context("design review next Tuesday from 3-5pm in the Orion Room"))
        #expect(c.title == "Design Review")
        #expect(!c.isAllDay)
        #expect(TestClock.format(c.start) == "2026-09-29T15:00")
        #expect(TestClock.format(c.end) == "2026-09-29T17:00")
        #expect(!c.endIsAssumed)
        #expect(c.location == "Orion Room")
        #expect(c.isComplete)
        #expect(c.sourceTimeZone == nil)
    }

    @Test func convertsStatedTimeZoneToLocal() {
        let c = resolve(ExtractedEvent(title: "Webinar", startDatePhrase: "Thursday Oct 1", timePhrase: "3pm ET"))
        #expect(TestClock.format(c.start) == "2026-10-01T12:00")
        #expect(TestClock.format(c.end) == "2026-10-01T13:00")
        #expect(c.endIsAssumed)
        #expect(c.sourceTimeZone?.identifier == "America/New_York")
        #expect(c.notes.contains("Originally 3:00 PM EDT."))
    }

    @Test func statedZoneMatchingLocalIsNotFlagged() {
        let c = resolve(ExtractedEvent(title: "Call", startDatePhrase: "tomorrow", timePhrase: "9am PST"))
        #expect(TestClock.format(c.start) == "2026-09-26T09:00")
        #expect(c.sourceTimeZone == nil)
    }

    @Test func defaultDurationIsMarkedAssumed() {
        let c = resolve(ExtractedEvent(title: "Lunch", startDatePhrase: "tomorrow", timePhrase: "at noon"))
        #expect(TestClock.format(c.end) == "2026-09-26T13:00")
        #expect(c.endIsAssumed)
    }

    @Test func durationFromTheEventsLine() {
        let c = resolve(
            ExtractedEvent(title: "Workshop", startDatePhrase: "tomorrow", timePhrase: "10:30am"),
            context: TestClock.context("Join our 2-hour SwiftUI workshop tomorrow at 10:30am")
        )
        #expect(TestClock.format(c.end) == "2026-09-26T12:30")
        #expect(!c.endIsAssumed)
    }

    @Test func overnightEndRollsToNextDay() {
        let c = resolve(ExtractedEvent(title: "Party", startDatePhrase: "tomorrow", timePhrase: "10pm-2am"))
        #expect(TestClock.format(c.end) == "2026-09-27T02:00")
    }

    @Test func timedAcrossDays() {
        let c = resolve(ExtractedEvent(title: "Hackathon", startDatePhrase: "Saturday", endDatePhrase: "Sunday at 4pm", timePhrase: "10am"))
        #expect(TestClock.format(c.start) == "2026-09-26T10:00")
        #expect(TestClock.format(c.end) == "2026-09-27T16:00")
        let both = resolve(ExtractedEvent(title: "Hackathon", startDatePhrase: "Saturday", endDatePhrase: "Sunday", timePhrase: "10am … 4pm"))
        #expect(TestClock.format(both.end) == "2026-09-27T16:00")
    }

    @Test func allDayRange() {
        let c = resolve(ExtractedEvent(title: "SwiftConf", startDatePhrase: "October 20–22"))
        #expect(c.isAllDay)
        #expect(TestClock.format(c.start, allDay: true) == "2026-10-20")
        #expect(TestClock.format(c.end, allDay: true) == "2026-10-22")
        #expect(c.isComplete)
    }

    @Test func allDayRangeAcrossNewYear() {
        let c = resolve(ExtractedEvent(title: "Ski trip", startDatePhrase: "Dec 28", endDatePhrase: "Jan 3"))
        #expect(TestClock.format(c.start, allDay: true) == "2026-12-28")
        #expect(TestClock.format(c.end, allDay: true) == "2027-01-03")
    }

    /// Regression: a time in the end-date field produced Sep 29 2026 3pm – Sep 3 2027 5pm.
    @Test func timeInEndDateFieldIsIgnored() {
        let c = resolve(ExtractedEvent(title: "Design Review", startDatePhrase: "next Tuesday", endDatePhrase: "3-5pm", timePhrase: "3-5pm"))
        #expect(TestClock.format(c.start) == "2026-09-29T15:00")
        #expect(TestClock.format(c.end) == "2026-09-29T17:00")
    }

    @Test func implausibleSpansAreDropped() {
        let rolled = resolve(ExtractedEvent(title: "x", startDatePhrase: "Oct 20", endDatePhrase: "Oct 3"))
        #expect(TestClock.format(rolled.end, allDay: true) == "2026-10-20")
        let timed = resolve(ExtractedEvent(title: "x", startDatePhrase: "Oct 1", endDatePhrase: "Oct 20", timePhrase: "9am-5pm"))
        #expect(TestClock.format(timed.end) == "2026-10-01T17:00")
        let term = resolve(ExtractedEvent(title: "Fall Quarter", startDatePhrase: "Sep 24", endDatePhrase: "Dec 12"))
        #expect(TestClock.format(term.end, allDay: true) == "2026-12-12")
    }

    @Test func dayWithoutTimeIsAllDay() {
        let c = resolve(ExtractedEvent(title: "Dentist", startDatePhrase: "the 14th"))
        #expect(c.isAllDay)
        #expect(TestClock.format(c.start, allDay: true) == "2026-10-14")
        #expect(TestClock.format(c.end, allDay: true) == "2026-10-14")
        #expect(c.isComplete)
    }

    @Test func vagueOrFillerTimesAreAllDay() {
        for phrase in ["unknown", "in the evening", "TBD"] {
            #expect(resolve(ExtractedEvent(title: "x", startDatePhrase: "Nov 3", timePhrase: phrase)).isAllDay)
        }
    }

    @Test func timeWithoutDayRequiresDateAndKeepsHint() {
        let c = resolve(ExtractedEvent(title: "Call Sam", timePhrase: "at 4:30pm"))
        #expect(c.start == nil)
        #expect(c.startTimeHint?.hour == 16)
        #expect(c.startTimeHint?.minute == 30)
        #expect(!c.isAllDay)
        #expect(c.missingFields == [.date])
    }

    @Test func nothingKnownRequiresTitleAndDate() {
        let c = resolve(ExtractedEvent(title: ""))
        #expect(c.missingFields == [.title, .date])
        #expect(c.isAllDay)
    }

    @Test func ambiguousTimesUseTheirWords() {
        let dinner = resolve(ExtractedEvent(title: "Dinner with Priya", startDatePhrase: "tomorrow", timePhrase: "at 7"))
        #expect(TestClock.format(dinner.start) == "2026-09-26T19:00")
        let breakfast = resolve(ExtractedEvent(title: "Breakfast", startDatePhrase: "tomorrow", timePhrase: "at 7"))
        #expect(TestClock.format(breakfast.start) == "2026-09-26T07:00")
        let meeting = resolve(ExtractedEvent(title: "Sync", startDatePhrase: "tomorrow", timePhrase: "at 3"))
        #expect(TestClock.format(meeting.start) == "2026-09-26T15:00")
        let standup = resolve(ExtractedEvent(title: "Standup", startDatePhrase: "tomorrow", timePhrase: "9:30"))
        #expect(TestClock.format(standup.start) == "2026-09-26T09:30")
        let explicit = resolve(ExtractedEvent(title: "Dinner", startDatePhrase: "tomorrow", timePhrase: "9:30am"))
        #expect(TestClock.format(explicit.start) == "2026-09-26T09:30")
    }

    /// Regression: the model quoted "3-5pm" from the schema's own examples for a conference
    /// with no time, making it a 3–5 PM event.
    @Test func phrasesMustComeFromTheText() {
        let resolver = EventResolver(context: TestClock.context("SwiftConf 2026 runs October 20–22 in Seattle, WA."))
        #expect(resolver.grounded("3-5pm") == "")
        #expect(resolver.grounded("next Tuesday") == "")
        #expect(resolver.grounded("October 20–22") == "October 20–22")
        #expect(resolver.grounded("Oct 22") == "Oct 22")
        #expect(resolver.grounded("on the 22nd") == "")
        let c = resolver.resolve(ExtractedEvent(title: "SwiftConf", startDatePhrase: "October 20–22", endDatePhrase: "Oct 22", timePhrase: "3-5pm"))
        #expect(c.isAllDay)
        #expect(TestClock.format(c.end, allDay: true) == "2026-10-22")

        let later = EventResolver(context: TestClock.context("see you tues at 3 PM"))
        #expect(later.grounded("Tuesday") == "Tuesday")
        #expect(later.grounded("3pm") == "3pm")
    }

    @Test func timeInsideDatePhrase() {
        let c = resolve(ExtractedEvent(title: "HW 3 Due", startDatePhrase: "Friday at 11:59pm"))
        #expect(TestClock.format(c.start) == "2026-09-25T23:59")
    }

    @Test func ungroundedLocationIsDropped() {
        let context = TestClock.context("lunch tomorrow at noon at Blue Bottle")
        let event = { (location: String) in ExtractedEvent(title: "Lunch", startDatePhrase: "tomorrow", location: location) }
        #expect(resolve(event("Lunch spot"), context: context).location == nil)
        #expect(resolve(event("at Blue Bottle"), context: context).location == "Blue Bottle")
    }

    @Test func linksComeFromTheText() {
        let context = TestClock.context("Register at https://example.com/swiftui")
        let offered = resolve(ExtractedEvent(title: "x", location: "https://example.com/swiftui"), context: context)
        #expect(offered.location == nil)
        #expect(offered.url?.absoluteString == "https://example.com/swiftui")
        #expect(resolve(ExtractedEvent(title: "x"), context: context).url?.absoluteString == "https://example.com/swiftui")

        let list = TestClock.context("Standup Monday zoom.us/j/111\nRetro Friday zoom.us/j/222")
        #expect(resolve(ExtractedEvent(title: "Retro", startDatePhrase: "Friday"), context: list).url?.absoluteString.hasSuffix("222") == true)
    }

    @Test func remindersFromTheText() {
        let c = resolve(
            ExtractedEvent(title: "Dentist", startDatePhrase: "Oct 14", timePhrase: "9am"),
            context: TestClock.context("Dentist Oct 14 at 9am, remind me 1 day before and 30 min before")
        )
        #expect(c.alertMinutesBefore == [1_440, 30])
    }

    @Test func duplicatesAreDropped() {
        let event = ExtractedEvent(title: "SwiftConf", startDatePhrase: "October 20–22")
        let copy = ExtractedEvent(title: "swiftconf", startDatePhrase: "Oct 20-22")
        #expect(EventResolver(context: TestClock.context("x")).resolveAll([event, copy]).count == 1)
    }

    /// Regression: "Office Hours" went to the "Class" calendar the model suggested.
    @Test func calendarNamedInTextBeatsModelSuggestion() {
        let context = TestClock.context(
            "Office hours every Tuesday and Thursday 2-3pm", calendars: ["Class", "Office Hours", "Work", "Home"]
        )
        let event = { (title: String, suggestion: String?) in
            ExtractedEvent(title: title, startDatePhrase: "Tuesday", suggestedCalendar: suggestion)
        }
        #expect(resolve(event("Office Hours", "Class"), context: context).namedCalendar == "Office Hours")
        #expect(resolve(event("TA Session", "Class"), context: context).namedCalendar == "Office Hours")
        let chat = TestClock.context("let's work on it at home", calendars: ["Class", "Work", "Home"])
        let sync = resolve(event("Project sync", "class"), context: chat)
        #expect(sync.namedCalendar == nil)
        #expect(sync.suggestedCalendarName == "Class")
        #expect(resolve(event("Homework 3 Due", nil), context: chat).namedCalendar == nil)
        #expect(resolve(event("Work Offsite", "Class"), context: chat).namedCalendar == "Work")
        #expect(resolve(event("x", "Gym"), context: chat).suggestedCalendarName == nil)
    }

    @Test func urls() {
        #expect(EventResolver.url(from: "zoom.us/j/123")?.absoluteString == "https://zoom.us/j/123")
        #expect(EventResolver.url(from: "https://meet.google.com/abc")?.absoluteString == "https://meet.google.com/abc")
        #expect(EventResolver.url(from: "not a link") == nil)
        #expect(EventResolver.url(from: "  ") == nil)
    }

    /// Regression: a list of dates came back as "every day", first with no repeat words at
    /// all, then because another line said "for each academic year".
    @Test func recurrenceMustBeStatedOnTheEventsLine() {
        let list = TestClock.context("""
            August 17th 2026 - Module is now available.
            June 4th 2027 - Deadline (typically the first Friday of June for each academic year.)
            Standup every Monday at 9am
            """)
        let event = { (phrase: String, frequency: Frequency) in
            ExtractedEvent(title: "x", startDatePhrase: phrase, recurrence: RecurrenceSpec(frequency: frequency))
        }
        #expect(resolve(event("August 17th 2026", .daily), context: list).recurrence == nil)
        #expect(resolve(event("June 4th 2027", .daily), context: list).recurrence == nil)
        #expect(resolve(event("every Monday", .weekly), context: list).recurrence?.frequency == .weekly)
        #expect(resolve(event("every Monday", .daily), context: list).recurrence == nil)
    }

    @Test(arguments: [
        ("Office hours every Tuesday and Thursday", Frequency.weekly, true),
        ("Standup on Mondays and Thursdays", .weekly, true),
        ("biweekly sync", .weekly, true),
        ("Everyone meets Tuesday", .weekly, false),
        ("Take meds daily at 8", .daily, true),
        ("Rent due on the 1st of every month", .monthly, true),
        ("Annual review in March", .yearly, true),
        ("for each academic year", .daily, false),
    ])
    func repetitionWording(_ text: String, _ frequency: Frequency, _ supported: Bool) {
        #expect(EventResolver.textSupports(RecurrenceSpec(frequency: frequency), for: ExtractedEvent(title: "x"), in: text) == supported)
    }

    @Test func recurrence() {
        let c = resolve(ExtractedEvent(
            title: "Office Hours", startDatePhrase: "every Tuesday", timePhrase: "2-3pm",
            recurrence: RecurrenceSpec(frequency: .weekly, weekdays: [.tuesday, .thursday], untilPhrase: "Dec 4")
        ), context: TestClock.context("Office hours every Tuesday and Thursday 2-3pm until Dec 4"))
        #expect(c.recurrence?.frequency == .weekly)
        #expect(c.recurrence?.weekdays == [3, 5])
        #expect(TestClock.format(c.recurrence?.until, allDay: true) == "2026-12-04")
    }
}
