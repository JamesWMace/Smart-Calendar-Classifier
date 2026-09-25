import Foundation
import Testing
@testable import SmartCalendarCore

@Suite("TimeZoneResolver")
struct TimeZoneResolverTests {
    @Test(arguments: [
        ("ET", "America/New_York"), ("est", "America/New_York"), ("PST", "America/Los_Angeles"),
        ("PDT", "America/Los_Angeles"), ("Pacific Time", "America/Los_Angeles"), ("CEST", "Europe/Paris"),
        ("London time", "Europe/London"), ("Europe/Berlin", "Europe/Berlin"),
    ])
    func named(_ input: String, _ identifier: String) {
        #expect(TimeZoneResolver.resolve(input)?.identifier == identifier)
    }

    @Test func offsets() {
        #expect(TimeZoneResolver.resolve("UTC")?.secondsFromGMT() == 0)
        #expect(TimeZoneResolver.resolve("UTC+2")?.secondsFromGMT() == 7_200)
        #expect(TimeZoneResolver.resolve("GMT-05:30")?.secondsFromGMT() == -19_800)
        #expect(TimeZoneResolver.resolve("+0530")?.secondsFromGMT() == 19_800)
    }

    @Test func findInPhrase() {
        #expect(TimeZoneResolver.find(in: "3pm ET")?.identifier == "America/New_York")
        #expect(TimeZoneResolver.find(in: "9:30am Pacific Time")?.identifier == "America/Los_Angeles")
        #expect(TimeZoneResolver.find(in: "14:00 UTC+2")?.secondsFromGMT() == 7_200)
        #expect(TimeZoneResolver.find(in: "noon New York time")?.identifier == "America/New_York")
        #expect(TimeZoneResolver.find(in: "at 3pm") == nil)
        #expect(TimeZoneResolver.find(in: "10am in LA") == nil) // too ambiguous inside a phrase
    }

    @Test func unknown() {
        #expect(TimeZoneResolver.resolve(nil) == nil)
        #expect(TimeZoneResolver.resolve("  ") == nil)
        #expect(TimeZoneResolver.resolve("banana") == nil)
    }
}

@Suite("PromptBuilder")
struct PromptBuilderTests {
    @Test func includesAllContext() {
        let context = CaptureContext(
            selection: "see you then!",
            textBefore: "Can we meet Monday at 9?",
            textAfter: "Cheers, Sam",
            appName: "Mail",
            windowTitle: "Budget review",
            url: URL(string: "https://example.com/thread"),
            calendarNames: ["Work", "Personal"]
        )
        let prompt = PromptBuilder.prompt(for: context)
        for expected in ["Source app: Mail", "Window title: Budget review", "https://example.com/thread",
                         "User's calendars: Work, Personal", "Can we meet Monday at 9?",
                         "SELECTED TEXT:\nsee you then!", "Cheers, Sam"] {
            #expect(prompt.contains(expected), "missing \(expected)")
        }
        #expect(prompt.range(of: "CONTEXT BEFORE")!.lowerBound < prompt.range(of: "SELECTED TEXT")!.lowerBound)
    }

    @Test func omitsEmptySections() {
        let prompt = PromptBuilder.prompt(for: CaptureContext(selection: "Lunch tomorrow", textBefore: "  "))
        #expect(!prompt.contains("CONTEXT"))
        #expect(!prompt.contains("Source app"))
    }

    @Test func respectsBudget() {
        let long = String(repeating: "word ", count: 2_000)
        var budget = PromptBuilder.Budget()
        budget.selection = 100
        budget.contextBefore = 50
        let prompt = PromptBuilder.prompt(for: CaptureContext(selection: long, textBefore: long), budget: budget)
        #expect(prompt.count < 400)
        #expect(prompt.contains("… word"))
        #expect(prompt.contains("word …"))
    }
}

@Suite("NotesComposer")
struct NotesComposerTests {
    @Test func sectionsInOrder() {
        let context = CaptureContext(
            selection: "Webinar Thursday 3pm ET", appName: "Safari", windowTitle: "Events",
            url: URL(string: "https://example.com")
        )
        let notes = NotesComposer.compose(
            summary: "Intro to SwiftUI.", context: context,
            sourceTimeZone: TimeZone(identifier: "America/New_York"), start: TestClock.local("2026-10-01T12:00")
        )
        #expect(notes == """
            Intro to SwiftUI.

            Originally 3:00 PM EDT.

            — Original text —
            Webinar Thursday 3pm ET

            Source: Safari — Events
            https://example.com
            """)
    }
}

@Suite("DataDetectorExtractor")
struct DataDetectorExtractorTests {
    @Test func timedSelection() throws {
        let candidates = DataDetectorExtractor().extract(from: CaptureContext(selection: "Lunch with Sam tomorrow at 1pm"))
        let c = try #require(candidates.first)
        #expect(c.title == "Lunch with Sam")
        #expect(!c.startTimeMissing)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        #expect(Calendar.current.isDate(try #require(c.start), inSameDayAs: tomorrow))
        #expect(Calendar.current.component(.hour, from: c.start!) == 13)
        #expect(c.endIsAssumed)
    }

    @Test func dateWithoutTimeIsAllDay() throws {
        let c = try #require(DataDetectorExtractor().extract(from: CaptureContext(selection: "Dentist appointment on October 14")).first)
        #expect(c.title == "Dentist appointment")
        #expect(c.isAllDay)
        #expect(c.isComplete)
    }

    @Test func noDate() throws {
        let c = try #require(DataDetectorExtractor().extract(from: CaptureContext(selection: "Book club")).first)
        #expect(c.missingFields == [.date])
    }
}

@Suite("SurroundingText")
struct SurroundingTextTests {
    private func range(of needle: String, in text: String) -> NSRange {
        (text as NSString).range(of: needle)
    }

    @Test func slicesAroundSelection() throws {
        let text = "Hi team! Design review next Tuesday 3-5pm. Bring your mocks."
        let slice = try #require(SurroundingText.slice(text, selection: range(of: "next Tuesday 3-5pm", in: text)))
        #expect(slice.before == "Hi team! Design review ")
        #expect(slice.selected == "next Tuesday 3-5pm")
        #expect(slice.after == ". Bring your mocks.")
    }

    @Test func trimsToWordBoundaries() throws {
        let text = "alpha bravo charlie SELECTED delta echo foxtrot"
        let slice = try #require(SurroundingText.slice(text, selection: range(of: "SELECTED", in: text), maxBefore: 10, maxAfter: 9))
        #expect(slice.before == "charlie ")   // "o charlie " cut back to a word start
        #expect(slice.after == " delta")      // " delta ec" cut back to a word end
    }

    @Test func locateToleratesWhitespace() throws {
        let page = "Inbox\nLabels\nIMPORTANT DATES: prospective dates.\nAugust 17th 2026 - Module is now available.\nSeptember 28th 2026 - First day to submit.\nAccount activation"
        let copied = "August 17th 2026 - Module is now available. September 28th 2026 -\n First day to submit."
        let range = try #require(SurroundingText.locate(copied, in: page))
        let slice = try #require(SurroundingText.slice(page, selection: range))
        #expect(slice.before.hasSuffix("IMPORTANT DATES: prospective dates.\n"))
        #expect(slice.after == "\nAccount activation")
        #expect(SurroundingText.locate("not on the page", in: page) == nil)
    }

    @Test func locateLongSelection() throws {
        let body = (1...60).map { "word\($0)" }.joined(separator: " ")
        let page = "header " + body + " footer"
        let range = try #require(SurroundingText.locate(body.replacingOccurrences(of: " ", with: "\n"), in: page))
        #expect((page as NSString).substring(with: range) == body)
    }

    @Test func emojiAndOutOfRange() throws {
        let text = "🎉🎉 Party Saturday 8pm 🎉"
        let slice = try #require(SurroundingText.slice(text, selection: range(of: "Saturday 8pm", in: text)))
        #expect(slice.before == "🎉🎉 Party ")
        #expect(slice.after == " 🎉")
        #expect(SurroundingText.slice("short", selection: NSRange(location: 3, length: 10)) == nil)
    }
}
