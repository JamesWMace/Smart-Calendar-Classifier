import EventKit
import Foundation
import Testing
@testable import SmartCalendarCore

/// Creating `EKEvent`s needs no calendar permission, so the mapping is tested without access.
@Suite("EventMapper")
struct EventMapperTests {
    let store = EKEventStore()
    let zone = TestClock.pacific

    private func map(_ candidate: EventCandidate, alerts: [Int] = []) throws -> EKEvent {
        try EventMapper.makeEvent(from: candidate, in: store, calendar: nil, defaultAlertMinutes: alerts, timeZone: zone)
    }

    @Test func timedEvent() throws {
        let start = TestClock.local("2026-09-29T15:00"), end = TestClock.local("2026-09-29T17:00")
        let event = try map(EventCandidate(
            title: " Design Review ", isAllDay: false, start: start, end: end,
            location: "Orion Room", url: URL(string: "https://zoom.us/j/1"), notes: "Bring mocks."
        ))
        #expect(event.title == "Design Review")
        #expect(!event.isAllDay)
        #expect(event.startDate == start)
        #expect(event.endDate == end)
        #expect(event.timeZone?.identifier == "America/Los_Angeles")
        #expect(event.location == "Orion Room")
        #expect(event.url?.absoluteString == "https://zoom.us/j/1")
        #expect(event.notes == "Bring mocks.")
        #expect(event.alarms == nil || event.alarms!.isEmpty)
    }

    @Test func allDayRangeCoversLastDay() throws {
        let event = try map(EventCandidate(
            title: "SwiftConf", isAllDay: true, start: TestClock.local("2026-10-20"), end: TestClock.local("2026-10-22")
        ))
        #expect(event.isAllDay)
        #expect(event.timeZone == nil)
        #expect(TestClock.format(event.startDate) == "2026-10-20T00:00")
        #expect(TestClock.format(event.endDate) == "2026-10-22T23:59")
    }

    @Test func singleAllDay() throws {
        let day = TestClock.local("2026-11-03")
        let event = try map(EventCandidate(title: "Birthday", isAllDay: true, start: day, end: day))
        #expect(TestClock.format(event.endDate) == "2026-11-03T23:59")
    }

    @Test func alertsPreferTextOverDefaults() throws {
        let start = TestClock.local("2026-09-29T15:00")
        let base = EventCandidate(title: "x", isAllDay: false, start: start, end: start.addingTimeInterval(3_600))

        let defaults = try map(base, alerts: [10])
        #expect(defaults.alarms?.map(\.relativeOffset) == [-600])

        var explicit = base
        explicit.alertMinutesBefore = [60, 1_440, 60]
        let offsets = try map(explicit, alerts: [10]).alarms?.map(\.relativeOffset)
        #expect(offsets.map(Set.init) == [-3_600, -86_400]) // EventKit orders alarms itself; duplicates are dropped
    }

    @Test func weeklyRecurrenceUntilIncludesLastDay() throws {
        let start = TestClock.local("2026-09-29T14:00")
        let event = try map(EventCandidate(
            title: "Office Hours", isAllDay: false, start: start, end: start.addingTimeInterval(3_600),
            recurrence: Recurrence(frequency: .weekly, weekdays: [3, 5], until: TestClock.local("2026-12-04"))
        ))
        let rule = try #require(event.recurrenceRules?.first)
        #expect(rule.frequency == .weekly)
        #expect(rule.interval == 1)
        #expect(rule.daysOfTheWeek?.map(\.dayOfTheWeek) == [.tuesday, .thursday])
        #expect(TestClock.format(rule.recurrenceEnd?.endDate) == "2026-12-04T23:59")
    }

    @Test func recurrenceByCount() throws {
        let start = TestClock.local("2026-10-01T18:00")
        let event = try map(EventCandidate(
            title: "Workshop", isAllDay: false, start: start, end: start.addingTimeInterval(3_600),
            recurrence: Recurrence(frequency: .weekly, interval: 2, occurrenceCount: 6)
        ))
        let rule = try #require(event.recurrenceRules?.first)
        #expect(rule.interval == 2)
        #expect(rule.recurrenceEnd?.occurrenceCount == 6)
        #expect(rule.daysOfTheWeek == nil)
    }

    @Test func incompleteCandidateIsRejected() {
        let candidate = EventCandidate(title: "Dentist", isAllDay: false, start: TestClock.local("2026-10-14"), end: nil, startTimeMissing: true)
        #expect(throws: EventMappingError.incomplete([.startTime])) { try map(candidate) }
    }
}

@Suite("ConflictDetector")
struct ConflictDetectorTests {
    private let meeting = EventCandidate(
        title: "Design Review", isAllDay: false,
        start: TestClock.local("2026-09-29T15:00"), end: TestClock.local("2026-09-29T17:00")
    )

    private func existing(_ id: String, _ start: String, _ end: String, allDay: Bool = false, blocks: Bool = true) -> ExistingEvent {
        ExistingEvent(id: id, title: id, start: TestClock.local(start), end: TestClock.local(end), isAllDay: allDay, blocksTime: blocks)
    }

    @Test func overlapsOnly() {
        let events = [
            existing("overlaps end", "2026-09-29T16:30", "2026-09-29T18:00"),
            existing("inside", "2026-09-29T15:30", "2026-09-29T16:00"),
            existing("touches start", "2026-09-29T14:00", "2026-09-29T15:00"),
            existing("touches end", "2026-09-29T17:00", "2026-09-29T18:00"),
            existing("all day", "2026-09-29T00:00", "2026-09-29T23:59", allDay: true),
            existing("free", "2026-09-29T15:00", "2026-09-29T16:00", blocks: false),
        ]
        #expect(ConflictDetector.conflicts(for: meeting, among: events).map(\.id) == ["inside", "overlaps end"])
    }

    @Test func allDayAndIncompleteCandidatesNeverConflict() {
        let events = [existing("busy", "2026-09-29T00:00", "2026-09-29T23:00")]
        var allDay = meeting
        allDay.isAllDay = true
        #expect(ConflictDetector.conflicts(for: allDay, among: events).isEmpty)
        var noTime = meeting
        noTime.startTimeMissing = true
        #expect(ConflictDetector.conflicts(for: noTime, among: events).isEmpty)
    }
}
