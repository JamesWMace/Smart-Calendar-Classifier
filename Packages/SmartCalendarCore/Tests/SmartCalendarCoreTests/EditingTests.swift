import Foundation
import Testing
@testable import SmartCalendarCore

@Suite("EventCandidate editing")
struct EditingTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TestClock.pacific
        return calendar
    }
    private let hour: TimeInterval = 3_600

    private func timed(_ start: String, _ end: String) -> EventCandidate {
        EventCandidate(title: "x", isAllDay: false, start: TestClock.local(start), end: TestClock.local(end))
    }

    @Test func movingTheDayKeepsTimesAndLength() {
        var c = timed("2026-09-29T15:00", "2026-09-29T17:00")
        c.setDay(TestClock.local("2026-10-06"), calendar: calendar, defaultDuration: hour)
        #expect(TestClock.format(c.start) == "2026-10-06T15:00")
        #expect(TestClock.format(c.end) == "2026-10-06T17:00")
    }

    @Test func pickingADayAppliesTheTimeTheTextGave() {
        var c = EventCandidate(title: "Call Sam", isAllDay: false, start: nil, end: nil,
                               startTimeHint: DateComponents(timeZone: TestClock.pacific, hour: 16, minute: 30))
        #expect(c.missingFields == [.date])
        c.setDay(TestClock.local("2026-09-30"), calendar: calendar, defaultDuration: hour)
        #expect(TestClock.format(c.start) == "2026-09-30T16:30")
        #expect(TestClock.format(c.end) == "2026-09-30T17:30")
        #expect(c.endIsAssumed)
        #expect(c.isComplete)
    }

    @Test func pickingADayWithoutATimeStillNeedsTheTime() {
        var c = EventCandidate(title: "Dentist", isAllDay: false, start: nil, end: nil, startTimeMissing: true)
        c.setDay(TestClock.local("2026-10-14"), calendar: calendar, defaultDuration: hour)
        #expect(c.missingFields == [.startTime])
        c.setStartTime(TestClock.local("2000-01-01T09:30"), calendar: calendar, defaultDuration: hour)
        #expect(TestClock.format(c.start) == "2026-10-14T09:30")
        #expect(TestClock.format(c.end) == "2026-10-14T10:30")
        #expect(c.isComplete)
    }

    @Test func movingTheStartKeepsTheLength() {
        var c = timed("2026-09-29T15:00", "2026-09-29T17:00")
        c.setStartTime(TestClock.local("2000-01-01T10:00"), calendar: calendar, defaultDuration: hour)
        #expect(TestClock.format(c.start) == "2026-09-29T10:00")
        #expect(TestClock.format(c.end) == "2026-09-29T12:00")
    }

    @Test func endTimes() {
        var c = timed("2026-09-29T22:00", "2026-09-29T23:00")
        c.setEndTime(TestClock.local("2000-01-01T23:30"), calendar: calendar)
        #expect(TestClock.format(c.end) == "2026-09-29T23:30")
        c.setEndTime(TestClock.local("2000-01-01T02:00"), calendar: calendar)
        #expect(TestClock.format(c.end) == "2026-09-30T02:00") // past midnight
        #expect(!c.endIsAssumed)
    }

    @Test func toggleAllDay() {
        var c = timed("2026-09-29T15:00", "2026-09-29T17:00")
        c.setAllDay(true, calendar: calendar)
        #expect(TestClock.format(c.start) == "2026-09-29T00:00")
        #expect(c.isComplete)
        c.setLastDay(TestClock.local("2026-10-01"), calendar: calendar)
        #expect(TestClock.format(c.end, allDay: true) == "2026-10-01")
        c.setAllDay(false, calendar: calendar)
        #expect(c.missingFields == [.startTime])
        #expect(TestClock.format(c.start, allDay: true) == "2026-09-29")
    }
}
