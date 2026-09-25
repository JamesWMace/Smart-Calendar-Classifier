import Foundation
import Testing
@testable import SmartCalendarCore

@Suite("EventResolver")
struct EventResolverTests {
    private func resolve(_ event: ExtractedEvent, context: CaptureContext = TestClock.context("text")) -> EventCandidate {
        EventResolver(context: context).resolve(event)
    }

    @Test func timedWithEndTime() {
        let c = resolve(ExtractedEvent(
            title: " Design Review ", startDatePhrase: "next Tuesday", timePhrase: "from 3-5pm", timing: .timed,
            location: "in the Orion Room"
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
        let c = resolve(ExtractedEvent(
            title: "Webinar", startDatePhrase: "Thursday Oct 1", timePhrase: "3pm", timing: .timed, timeZone: "ET"
        ))
        #expect(TestClock.format(c.start) == "2026-10-01T12:00")
        #expect(c.sourceTimeZone?.identifier == "America/New_York")
        #expect(c.notes.contains("Originally 3:00 PM EDT."))
    }

    @Test func statedZoneMatchingLocalIsNotFlagged() {
        let c = resolve(ExtractedEvent(
            title: "Call", startDatePhrase: "tomorrow", timePhrase: "9am", timing: .timed, timeZone: "PST"
        ))
        #expect(TestClock.format(c.start) == "2026-09-26T09:00")
        #expect(c.sourceTimeZone == nil)
    }

    @Test func defaultDurationIsMarkedAssumed() {
        let c = resolve(ExtractedEvent(
            title: "Lunch", startDatePhrase: "tomorrow", timePhrase: "at noon", timing: .timed
        ))
        #expect(TestClock.format(c.end) == "2026-09-26T13:00")
        #expect(c.endIsAssumed)
    }

    @Test func statedDuration() {
        let c = resolve(ExtractedEvent(
            title: "Workshop", startDatePhrase: "tomorrow", timePhrase: "10:30am", timing: .timed, durationMinutes: 120
        ))
        #expect(TestClock.format(c.end) == "2026-09-26T12:30")
        #expect(!c.endIsAssumed)
    }

    @Test func overnightEndRollsToNextDay() {
        let c = resolve(ExtractedEvent(
            title: "Party", startDatePhrase: "tomorrow", timePhrase: "10pm-2am", timing: .timed
        ))
        #expect(TestClock.format(c.end) == "2026-09-27T02:00")
    }

    @Test func timedAcrossDays() {
        let c = resolve(ExtractedEvent(
            title: "Hackathon", startDatePhrase: "Saturday", endDatePhrase: "Sunday", timePhrase: "10am",
            timing: .timed, endTime: TimeSpec(hour: 16)
        ))
        #expect(TestClock.format(c.start) == "2026-09-26T10:00")
        #expect(TestClock.format(c.end) == "2026-09-27T16:00")
    }

    @Test func allDayRange() {
        let c = resolve(ExtractedEvent(
            title: "SwiftConf", startDatePhrase: "October 20–22", timing: .allDay
        ))
        #expect(c.isAllDay)
        #expect(TestClock.format(c.start, allDay: true) == "2026-10-20")
        #expect(TestClock.format(c.end, allDay: true) == "2026-10-22")
        #expect(c.isComplete)
    }

    @Test func allDayRangeAcrossNewYear() {
        let c = resolve(ExtractedEvent(
            title: "Ski trip", startDatePhrase: "Dec 28", endDatePhrase: "Jan 3", timing: .allDay
        ))
        #expect(TestClock.format(c.start, allDay: true) == "2026-12-28")
        #expect(TestClock.format(c.end, allDay: true) == "2027-01-03")
    }

    @Test func dayWithoutTimeRequiresTime() {
        let c = resolve(ExtractedEvent(title: "Dentist", startDatePhrase: "the 14th", timing: .unknown))
        #expect(!c.isAllDay)
        #expect(TestClock.format(c.start, allDay: true) == "2026-10-14")
        #expect(c.startTimeMissing)
        #expect(c.missingFields == [.startTime])
    }

    @Test func timeWithoutDayRequiresDateAndKeepsHint() {
        let c = resolve(ExtractedEvent(title: "Call Sam", timePhrase: "at 4:30", timing: .timed, startTime: TimeSpec(hour: 16, minute: 30)))
        #expect(c.start == nil)
        #expect(c.startTimeHint?.hour == 16)
        #expect(c.startTimeHint?.minute == 30)
        #expect(c.missingFields == [.date])
    }

    @Test func nothingKnownRequiresEverything() {
        let c = resolve(ExtractedEvent(title: "", timing: .unknown))
        #expect(c.missingFields == [.title, .date, .startTime])
    }

    @Test func calendarSuggestionMustMatchARealCalendar() {
        let context = TestClock.context("x", calendars: ["Work", "School"])
        let event = { (name: String) in
            ExtractedEvent(title: "x", startDatePhrase: "today", timing: .allDay, suggestedCalendar: name)
        }
        #expect(resolve(event("school"), context: context).suggestedCalendarName == "School")
        #expect(resolve(event("Gym"), context: context).suggestedCalendarName == nil)
    }

    @Test func urls() {
        #expect(EventResolver.url(from: "zoom.us/j/123")?.absoluteString == "https://zoom.us/j/123")
        #expect(EventResolver.url(from: "https://meet.google.com/abc")?.absoluteString == "https://meet.google.com/abc")
        #expect(EventResolver.url(from: "not a link") == nil)
        #expect(EventResolver.url(from: "  ") == nil)
    }

    @Test func ambiguousPhraseDefersToModel() {
        let c = resolve(ExtractedEvent(
            title: "Dinner", startDatePhrase: "tomorrow", timePhrase: "at 7", timing: .timed, startTime: TimeSpec(hour: 19)
        ))
        #expect(TestClock.format(c.start) == "2026-09-26T19:00")
    }

    @Test func unambiguousPhraseBeatsModel() {
        let c = resolve(ExtractedEvent(
            title: "Standup", startDatePhrase: "tomorrow", timePhrase: "9:30am", timing: .timed, startTime: TimeSpec(hour: 21, minute: 30)
        ))
        #expect(TestClock.format(c.start) == "2026-09-26T09:30")
    }

    @Test func modelTimeWithoutTimeWordsIsIgnored() {
        let c = resolve(ExtractedEvent(title: "Birthday", startDatePhrase: "Nov 3", timing: .unknown, startTime: TimeSpec(hour: 0)))
        #expect(c.startTimeMissing)
    }

    @Test func duplicatesAreDropped() {
        let event = ExtractedEvent(title: "SwiftConf", startDatePhrase: "October 20–22", timing: .allDay)
        let copy = ExtractedEvent(title: "swiftconf", startDatePhrase: "Oct 20-22", timing: .allDay)
        #expect(EventResolver(context: TestClock.context("x")).resolveAll([event, copy]).count == 1)
    }

    @Test func timeInsideDatePhrase() {
        let c = resolve(ExtractedEvent(title: "HW 3 Due", startDatePhrase: "Friday at 11:59pm", timing: .timed))
        #expect(TestClock.format(c.start) == "2026-09-25T23:59")
    }

    @Test func ungroundedLocationIsDropped() {
        let context = TestClock.context("lunch tomorrow at noon at Blue Bottle")
        let event = { (location: String) in
            ExtractedEvent(title: "Lunch", startDatePhrase: "tomorrow", timing: .timed, location: location)
        }
        #expect(resolve(event("Lunch spot"), context: context).location == nil)
        #expect(resolve(event("at Blue Bottle"), context: context).location == "Blue Bottle")
    }

    @Test func linkOfferedAsLocationBecomesURL() {
        let context = TestClock.context("Register at https://example.com/swiftui")
        let c = resolve(ExtractedEvent(title: "x", timing: .unknown, location: "https://example.com/swiftui"), context: context)
        #expect(c.location == nil)
        #expect(c.url?.absoluteString == "https://example.com/swiftui")
        let made = resolve(ExtractedEvent(title: "x", timing: .unknown, url: "https://zoom.us/j/1"), context: context)
        #expect(made.url == nil)
    }

    @Test func recurrence() {
        let c = resolve(ExtractedEvent(
            title: "Office Hours", startDatePhrase: "every Tuesday", timePhrase: "2-3pm", timing: .timed,
            recurrence: RecurrenceSpec(frequency: .weekly, weekdays: [.tuesday, .thursday], untilPhrase: "Dec 4")
        ))
        #expect(c.recurrence?.frequency == .weekly)
        #expect(c.recurrence?.weekdays == [3, 5])
        #expect(TestClock.format(c.recurrence?.until, allDay: true) == "2026-12-04")
    }
}
