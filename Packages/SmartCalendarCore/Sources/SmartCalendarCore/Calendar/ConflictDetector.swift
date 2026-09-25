import Foundation

/// An existing calendar event, reduced to what conflict checks and the UI need.
public struct ExistingEvent: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// False for events marked "free" or that the user declined.
    public var blocksTime: Bool
    public var calendarTitle: String

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, blocksTime: Bool = true, calendarTitle: String = "") {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.blocksTime = blocksTime
        self.calendarTitle = calendarTitle
    }
}

/// Decides which existing events clash with a candidate (decision #11).
public enum ConflictDetector {
    /// Only timed events that overlap in time count. All-day events (birthdays, holidays,
    /// trips) and events marked free don't make a timed meeting a conflict, and a new
    /// all-day event never conflicts. Events that merely touch (one ends at 3, the next
    /// starts at 3) don't overlap.
    public static func conflicts(for candidate: EventCandidate, among existing: [ExistingEvent]) -> [ExistingEvent] {
        guard !candidate.isAllDay, !candidate.startTimeMissing,
              let start = candidate.start, let end = candidate.end, end > start else { return [] }
        return existing
            .filter { !$0.isAllDay && $0.blocksTime && $0.start < end && $0.end > start }
            .sorted { $0.start < $1.start }
    }
}
