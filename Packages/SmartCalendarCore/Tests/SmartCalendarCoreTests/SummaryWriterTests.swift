import Foundation
import Testing
@testable import SmartCalendarCore

@Suite("SummaryWriter", .enabled(if: ModelAvailability.current == .available, "Apple Intelligence unavailable"))
struct SummaryWriterTests {
    @Test func writesShortGroundedNotes() async throws {
        let context = CaptureContext(
            selection: "Hi team, let's do the design review next Tuesday from 3-5pm in the Orion conference room. Please bring printed mocks of the onboarding flow.",
            referenceDate: TestClock.friday, timeZone: TestClock.pacific
        )
        let candidate = EventCandidate(title: "Design Review", isAllDay: false, start: nil, end: nil, location: "Orion conference room")
        let summary = try #require(try await SummaryWriter().summary(for: candidate, context: context))
        #expect(summary.count <= 400)
        #expect(summary.localizedCaseInsensitiveContains("mock"))
        #expect(!summary.lowercased().hasPrefix("sure"))
    }
}
