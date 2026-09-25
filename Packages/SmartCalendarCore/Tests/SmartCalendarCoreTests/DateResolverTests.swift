import Foundation
import Testing
@testable import SmartCalendarCore

@Suite("DateResolver — reference Friday Sep 25 2026")
struct DateResolverTests {
    let resolver = DateResolver(referenceDate: TestClock.friday, timeZone: TestClock.pacific)

    private func day(_ spec: DateSpec, _ resolver: DateResolver? = nil) -> String {
        TestClock.format((resolver ?? self.resolver).day(for: spec), allDay: true)
    }

    @Test func relativeDays() {
        #expect(day(DateSpec(kind: .relative, daysFromToday: 0)) == "2026-09-25")
        #expect(day(DateSpec(kind: .relative, daysFromToday: 1)) == "2026-09-26")
        #expect(day(DateSpec(kind: .relative, daysFromToday: 10)) == "2026-10-05")
    }

    @Test func weekdays() {
        #expect(day(DateSpec(kind: .weekday, weekday: .tuesday, weeksAhead: 0)) == "2026-09-29")
        // The coming Tuesday is already in next week, so "next Tuesday" is the same day.
        #expect(day(DateSpec(kind: .weekday, weekday: .tuesday, weeksAhead: 1)) == "2026-09-29")
        #expect(day(DateSpec(kind: .weekday, weekday: .tuesday, weeksAhead: 2)) == "2026-10-06")
        #expect(day(DateSpec(kind: .weekday, weekday: .friday, weeksAhead: 0)) == "2026-09-25")
        #expect(day(DateSpec(kind: .weekday, weekday: .friday, weeksAhead: 1)) == "2026-10-02")
        #expect(day(DateSpec(kind: .weekday, weekday: .saturday, weeksAhead: 0)) == "2026-09-26")
    }

    @Test func weekdaysFromMonday() {
        let monday = DateResolver(referenceDate: TestClock.monday, timeZone: TestClock.pacific)
        #expect(day(DateSpec(kind: .weekday, weekday: .friday, weeksAhead: 0), monday) == "2026-09-25")
        #expect(day(DateSpec(kind: .weekday, weekday: .friday, weeksAhead: 1), monday) == "2026-10-02")
        #expect(day(DateSpec(kind: .weekday, weekday: .monday, weeksAhead: 1), monday) == "2026-09-28")
    }

    @Test func absoluteDatesInferYear() {
        #expect(day(DateSpec(kind: .absolute, month: 10, day: 3)) == "2026-10-03")
        #expect(day(DateSpec(kind: .absolute, month: 1, day: 5)) == "2027-01-05")
        // Recently past dates stay in this year (e.g. an event recap).
        #expect(day(DateSpec(kind: .absolute, month: 9, day: 20)) == "2026-09-20")
        #expect(day(DateSpec(kind: .absolute, month: 8, day: 1)) == "2027-08-01")
        #expect(day(DateSpec(kind: .absolute, year: 2025, month: 8, day: 1)) == "2025-08-01")
        #expect(day(DateSpec(kind: .absolute, month: 2, day: 29)) == "2028-02-29")
    }

    @Test func invalidAbsoluteDates() {
        #expect(resolver.day(for: DateSpec(kind: .absolute, month: 2, day: 30)) == nil)
        #expect(resolver.day(for: DateSpec(kind: .absolute, month: 13, day: 1)) == nil)
        #expect(resolver.day(for: DateSpec(kind: .absolute, month: 10)) == nil)
    }

    @Test func dayOfMonthOnly() {
        #expect(day(DateSpec(kind: .absolute, day: 30)) == "2026-09-30")
        #expect(day(DateSpec(kind: .absolute, day: 25)) == "2026-09-25")
        #expect(day(DateSpec(kind: .absolute, day: 14)) == "2026-10-14")
        #expect(day(DateSpec(kind: .absolute, day: 31)) == "2026-10-31")
    }

    @Test func missing() {
        #expect(resolver.day(for: DateSpec(kind: .missing)) == nil)
        #expect(resolver.day(for: DateSpec(kind: .weekday)) == nil)
    }
}
