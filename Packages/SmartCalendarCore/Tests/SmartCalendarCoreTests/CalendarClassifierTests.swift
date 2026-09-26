import Testing
@testable import SmartCalendarCore

@Suite("CalendarClassifier")
struct CalendarClassifierTests {
    /// A plausible student's calendars, with repeats like real recurring events.
    private let classifier: CalendarClassifier = {
        var examples: [CalendarClassifier.Example] = []
        func add(_ calendar: String, _ text: String, times: Int = 1, source: String? = nil) {
            examples += Array(repeating: CalendarClassifier.Example(calendarID: calendar, text: text, source: source), count: times)
        }
        add("class", "CS 153 Lecture WCH 110", times: 30)
        add("class", "CS160 Lab Bourns A265", times: 15)
        add("class", "MATH 120 Discussion", times: 10)
        add("class", "Homework 3 Due", source: "Canvas")
        add("work", "Team Standup", times: 40)
        add("work", "Design review Orion conference room", times: 3)
        add("work", "1:1 with Dana")
        add("personal", "Dinner with Priya")
        add("personal", "Dentist appointment")
        add("personal", "Mom's birthday")
        add("office", "Office Hours WCH 110", times: 20)
        return CalendarClassifier(examples: examples)
    }()

    @Test(arguments: [
        ("CS 153 Midterm", "class"),
        ("cs153 final exam", "class"),
        ("Design review for onboarding", "work"),
        ("Standup moved", "work"),
        ("Dentist cleaning", "personal"),
        ("Office Hours", "office"),
    ])
    func picksTheCalendarWithSimilarEvents(_ title: String, _ calendar: String) {
        #expect(classifier.classify(title)?.calendarID == calendar)
    }

    @Test func learnsFromTheSourceApp() {
        #expect(classifier.classify("Quiz 4", source: "Canvas")?.calendarID == "class")
        #expect(classifier.classify("Quiz 4") == nil)
    }

    @Test(arguments: ["Coffee with Alex", "Tuesday", "Event", ""])
    func staysQuietWithoutEvidence(_ title: String) {
        #expect(classifier.classify(title) == nil)
    }

    @Test func ambiguousEvidenceIsNotEnough() {
        // "WCH 110" is where both lectures and office hours happen.
        #expect(classifier.classify("Session in WCH 110") == nil)
    }

    @Test func tokens() {
        #expect(CalendarClassifier.tokens("CS 153 Midterm on Oct 15 at 10am") == ["midterm", "cs153"])
        #expect(CalendarClassifier.tokens("x", source: "Mail") == ["app:mail"])
    }

    @Test func needsTwoCalendars() {
        let single = CalendarClassifier(examples: [.init(calendarID: "only", text: "CS 153 Lecture")])
        #expect(single.classify("CS 153 Midterm") == nil)
    }
}
