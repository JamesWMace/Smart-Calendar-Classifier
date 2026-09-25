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

    @Test func dateWithoutTimeRequiresTime() throws {
        let c = try #require(DataDetectorExtractor().extract(from: CaptureContext(selection: "Dentist appointment on October 14")).first)
        #expect(c.title == "Dentist appointment")
        #expect(c.startTimeMissing)
        #expect(c.missingFields == [.startTime])
    }

    @Test func noDate() throws {
        let c = try #require(DataDetectorExtractor().extract(from: CaptureContext(selection: "Book club")).first)
        #expect(c.missingFields == [.date, .startTime])
    }
}
