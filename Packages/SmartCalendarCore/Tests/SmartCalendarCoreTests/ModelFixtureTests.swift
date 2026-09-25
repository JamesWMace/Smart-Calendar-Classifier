import Foundation
import Testing
@testable import SmartCalendarCore

/// End-to-end checks of the on-device model + resolver against realistic texts in
/// `Fixtures/extraction-cases.json`. All cases use Friday Sep 25 2026, 10 AM Pacific as "now".
///
/// Runs only when Apple Intelligence is available. These are quality checks for prompt and
/// schema tuning rather than strict unit tests: a failure means the model misread a case.
@Suite("Model fixtures", .enabled(if: ModelAvailability.current == .available, "Apple Intelligence unavailable"))
struct ModelFixtureTests {
    struct Case: Decodable, CustomTestStringConvertible, Sendable {
        var name: String
        var selection: String
        var textBefore: String?
        var textAfter: String?
        var appName: String?
        var windowTitle: String?
        /// Defaults to Work, Personal, School.
        var calendars: [String]?
        var expected: [Expectation]

        var testDescription: String { name }
    }

    struct Expectation: Decodable, Sendable {
        /// Any one of these (case-insensitive) must appear in the title.
        var titleContains: [String]
        var start: String?
        var end: String?
        var startDay: String?
        var endDay: String?
        var isAllDay: Bool?
        var startTimeMissing: Bool?
        var dateMissing: Bool?
        var locationContains: String?
        var urlContains: String?
        var sourceTimeZone: String?
        var recurrence: String?
        var calendar: String?
    }

    static let cases: [Case] = {
        let url = Bundle.module.url(forResource: "extraction-cases", withExtension: "json", subdirectory: "Fixtures")!
        return try! JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
    }()

    @Test(arguments: cases)
    func extraction(_ fixture: Case) async throws {
        let context = CaptureContext(
            selection: fixture.selection,
            textBefore: fixture.textBefore,
            textAfter: fixture.textAfter,
            appName: fixture.appName,
            windowTitle: fixture.windowTitle,
            referenceDate: TestClock.friday,
            timeZone: TestClock.pacific,
            calendarNames: fixture.calendars ?? ["Work", "Personal", "School"]
        )
        let raw = try await FoundationModelsExtractor().extractRaw(from: context)
        let resolver = EventResolver(context: context)
        let candidates = resolver.resolveAll(raw)
        let summary = candidates.map { c in
            "\(c.title) | \(TestClock.format(c.start, allDay: c.isAllDay))–\(TestClock.format(c.end, allDay: c.isAllDay))"
                + " allDay=\(c.isAllDay) missing=\(c.missingFields) loc=\(c.location ?? "-")"
        }.joined(separator: "\n")
        let comment = Comment(rawValue: "Got:\n\(summary)")

        if fixture.expected.isEmpty {
            // Either no event, or a blank draft with no date is acceptable for non-events.
            #expect(candidates.allSatisfy { $0.start == nil }, comment)
            return
        }
        try #require(candidates.count == fixture.expected.count, comment)

        for (c, e) in zip(candidates, fixture.expected) {
            #expect(e.titleContains.contains { c.title.localizedCaseInsensitiveContains($0) }, comment)
            if let start = e.start { #expect(TestClock.format(c.start) == start, comment) }
            if let end = e.end { #expect(TestClock.format(c.end) == end, comment) }
            if let day = e.startDay { #expect(TestClock.format(c.start, allDay: true) == day, comment) }
            if let day = e.endDay { #expect(TestClock.format(c.end, allDay: true) == day, comment) }
            if let allDay = e.isAllDay { #expect(c.isAllDay == allDay, comment) }
            if let missing = e.startTimeMissing { #expect(c.startTimeMissing == missing, comment) }
            if e.dateMissing == true { #expect(c.missingFields.contains(.date), comment) }
            if let location = e.locationContains {
                #expect(c.location?.localizedCaseInsensitiveContains(location) == true, comment)
            }
            if let url = e.urlContains { #expect(c.url?.absoluteString.contains(url) == true, comment) }
            if let zone = e.sourceTimeZone { #expect(c.sourceTimeZone?.identifier == zone, comment) }
            if let calendar = e.calendar { #expect(c.suggestedCalendarName == calendar, comment) }
            if let recurrence = e.recurrence { #expect(c.recurrence.map { "\($0.frequency)" } == recurrence, comment) }
        }
    }
}
