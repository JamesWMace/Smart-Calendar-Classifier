import Foundation
import Testing
@testable import SmartCalendarCore

@Suite("DatePhraseParser")
struct DatePhraseParserTests {
    private func start(_ phrase: String) -> DateSpec? { DatePhraseParser.parse(phrase)?.start }

    @Test func absolute() {
        #expect(start("Oct 15") == DateSpec(kind: .absolute, month: 10, day: 15))
        #expect(start("Thursday, October 15th, 2026") == DateSpec(kind: .absolute, year: 2026, month: 10, day: 15))
        #expect(start("Sept. 3") == DateSpec(kind: .absolute, month: 9, day: 3))
        #expect(start("the 3rd of December") == DateSpec(kind: .absolute, month: 12, day: 3))
        #expect(start("10/05/2026") == DateSpec(kind: .absolute, year: 2026, month: 10, day: 5))
        #expect(start("10/5/26") == DateSpec(kind: .absolute, year: 2026, month: 10, day: 5))
        #expect(start("on 12/1") == DateSpec(kind: .absolute, month: 12, day: 1))
        #expect(start("2026-10-05") == DateSpec(kind: .absolute, year: 2026, month: 10, day: 5))
        #expect(start("the 14th") == DateSpec(kind: .absolute, day: 14))
    }

    @Test func relative() {
        #expect(start("tomorrow") == DateSpec(kind: .relative, daysFromToday: 1))
        #expect(start("Tonight") == DateSpec(kind: .relative, daysFromToday: 0))
        #expect(start("the day after tomorrow") == DateSpec(kind: .relative, daysFromToday: 2))
        #expect(start("in 3 days") == DateSpec(kind: .relative, daysFromToday: 3))
        #expect(start("in two weeks") == DateSpec(kind: .relative, daysFromToday: 14))
    }

    @Test func weekdays() {
        #expect(start("Tuesday") == DateSpec(kind: .weekday, weekday: .tuesday, weeksAhead: 0))
        #expect(start("this Thurs") == DateSpec(kind: .weekday, weekday: .thursday, weeksAhead: 0))
        #expect(start("next Friday") == DateSpec(kind: .weekday, weekday: .friday, weeksAhead: 1))
        #expect(start("Friday after next") == DateSpec(kind: .weekday, weekday: .friday, weeksAhead: 2))
        #expect(start("every Tuesday") == DateSpec(kind: .weekday, weekday: .tuesday, weeksAhead: 0))
        #expect(start("Mondays") == DateSpec(kind: .weekday, weekday: .monday, weeksAhead: 0))
        #expect(start("this month") == nil)
    }

    @Test func ranges() {
        let conf = DatePhraseParser.parse("October 20–22")
        #expect(conf?.start == DateSpec(kind: .absolute, month: 10, day: 20))
        #expect(conf?.end == DateSpec(kind: .absolute, month: 10, day: 22))

        let trip = DatePhraseParser.parse("Dec 28 - Jan 3")
        #expect(trip?.end == DateSpec(kind: .absolute, month: 1, day: 3))

        let weekend = DatePhraseParser.parse("Saturday to Sunday")
        #expect(weekend?.end == DateSpec(kind: .weekday, weekday: .sunday, weeksAhead: 0))

        // A time range after a date is not a date range.
        #expect(DatePhraseParser.parse("Oct 3 3-5pm")?.end == nil)
    }

    @Test func bareDayNeedsMonth() {
        #expect(DatePhraseParser.parse("22") == nil)
        #expect(DatePhraseParser.parse("22", defaultMonth: 10)?.start == DateSpec(kind: .absolute, month: 10, day: 22))
        #expect(DatePhraseParser.parse("22nd", defaultMonth: 10)?.start == DateSpec(kind: .absolute, month: 10, day: 22))
    }

    /// Regression: the model once put "3-5pm" in the end-date field, which became "Sep 3".
    @Test(arguments: ["3-5pm", "3 - 5 pm", "3pm", "3:00", "3 to 5", "5 p.m."])
    func timesAreNotBareDays(_ phrase: String) {
        #expect(DatePhraseParser.parse(phrase, defaultMonth: 9) == nil)
    }

    @Test func nothing() {
        #expect(DatePhraseParser.parse("") == nil)
        #expect(DatePhraseParser.parse("soon") == nil)
    }
}

@Suite("TimePhraseParser")
struct TimePhraseParserTests {
    private func parse(_ phrase: String) -> String {
        guard let r = TimePhraseParser.parse(phrase) else { return "nil" }
        let fmt = { (t: TimeSpec) in String(format: "%02d:%02d", t.hour, t.minute) }
        return fmt(r.start) + (r.end.map { "-" + fmt($0) } ?? "") + (r.isAmbiguous ? "?" : "")
    }

    @Test(arguments: [
        ("3pm", "15:00"), ("3 PM", "15:00"), ("11:59pm", "23:59"), ("12pm", "12:00"), ("12am", "00:00"),
        ("at noon", "12:00"), ("midnight", "00:00"), ("9:30 a.m.", "09:30"), ("14:00", "14:00"),
        ("3-5pm", "15:00-17:00"), ("from 3 to 5 pm", "15:00-17:00"), ("9:30am–12pm", "09:30-12:00"),
        ("11-1pm", "11:00-13:00"), ("10am-2", "10:00-14:00"), ("10pm-2am", "22:00-02:00"),
        ("14:00-16:30", "14:00-16:30"), ("2–3pm", "14:00-15:00"),
        ("at 7", "07:00?"), ("9:30", "09:30?"), ("at 19", "19:00"),
    ])
    func phrases(_ input: String, _ expected: String) {
        #expect(parse(input) == expected)
    }

    @Test func notTimes() {
        #expect(parse("Oct 3-5") == "nil")
        #expect(parse("") == "nil")
        #expect(parse("in the afternoon") == "nil")
    }
}

@Suite("DetailParsers")
struct DetailParsersTests {
    @Test(arguments: [
        ("2-hour workshop", 120), ("a 90 minute session", 90), ("for an hour", 60), ("1.5 hrs", 90),
        ("half an hour check-in", 30), ("45 mins", 45),
    ])
    func durations(_ text: String, _ minutes: Int) {
        #expect(DetailParsers.durationMinutes(in: text) == minutes)
    }

    @Test(arguments: ["2 hours before the deadline", "in 3 hours", "every hour", "no length here"])
    func notDurations(_ text: String) {
        #expect(DetailParsers.durationMinutes(in: text) == nil)
    }

    @Test func alerts() {
        #expect(DetailParsers.alertMinutes(in: "Remind me 30 minutes before") == [30])
        #expect(DetailParsers.alertMinutes(in: "Reminder: 1 day before and 2 hours before") == [1_440, 120])
        #expect(DetailParsers.alertMinutes(in: "Arrive 15 minutes early") == [])
    }

    @Test func ambiguity() {
        let at = { (phrase: String, hints: String) -> Int? in
            TimePhraseParser.parse(phrase).map { TimePhraseParser.resolvingAmbiguity($0, hints: hints).start.hour }
        }
        #expect(at("at 7", "dinner") == 19)
        #expect(at("at 7", "breakfast") == 7)
        #expect(at("at 7", "") == 19)
        #expect(at("at 8", "") == 8)
        #expect(at("at 12", "") == 12)
        #expect(at("at 9", "tonight") == 21)
        #expect(at("7pm", "breakfast") == 19) // explicit beats hints
    }
}
