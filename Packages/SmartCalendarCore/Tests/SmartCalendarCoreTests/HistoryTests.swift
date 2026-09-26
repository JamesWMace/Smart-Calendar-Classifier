import Foundation
import Testing
@testable import SmartCalendarCore

@Suite("HistoryStore") @MainActor
struct HistoryTests {
    private let file = URL.temporaryDirectory.appending(path: "history-\(UUID()).json")

    private func event(_ id: String) -> SavedEvent {
        SavedEvent(eventIdentifier: id, calendarItemIdentifier: id, calendarTitle: "Work", title: "Event \(id)",
                   start: TestClock.local("2026-09-29T15:00"), end: TestClock.local("2026-09-29T16:00"), isAllDay: false)
    }

    @Test func recordsNewestFirstAndPersists() {
        let store = HistoryStore(fileURL: file)
        store.record([event("a")], source: "Mail")
        store.record([event("b"), event("c")], source: "Safari")
        #expect(store.entries.map(\.event.eventIdentifier) == ["b", "c", "a"])

        let reloaded = HistoryStore(fileURL: file)
        #expect(reloaded.entries == store.entries)
        #expect(reloaded.entries.last?.source == "Mail")
    }

    @Test func markRemovedKeepsTheEntry() {
        let store = HistoryStore(fileURL: file)
        store.record([event("a"), event("b")], source: nil)
        store.markRemoved([event("a")])
        #expect(store.entries.first { $0.event.eventIdentifier == "a" }?.removedAt != nil)
        #expect(store.entries.first { $0.event.eventIdentifier == "b" }?.removedAt == nil)
        #expect(HistoryStore(fileURL: file).entries.count == 2)
    }

    @Test func capsAndClears() {
        let store = HistoryStore(fileURL: file)
        store.record((0..<(HistoryStore.limit + 5)).map { event("\($0)") }, source: nil)
        #expect(store.entries.count == HistoryStore.limit)
        store.clear()
        #expect(HistoryStore(fileURL: file).entries.isEmpty)
    }

    @Test func missingFileStartsEmpty() {
        #expect(HistoryStore(fileURL: file).entries.isEmpty)
    }
}
