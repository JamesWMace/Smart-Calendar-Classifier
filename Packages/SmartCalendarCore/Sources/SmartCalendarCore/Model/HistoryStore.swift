import Foundation
import Observation

/// One event the app added, remembered so it can be found, opened or removed later.
public struct HistoryEntry: Identifiable, Sendable, Equatable, Codable {
    public var id: UUID
    public var event: SavedEvent
    public var addedAt: Date
    /// The app the text came from, e.g. "Mail".
    public var source: String?
    /// Set when the user removed the event through the app.
    public var removedAt: Date?

    public init(id: UUID = UUID(), event: SavedEvent, addedAt: Date = .now, source: String? = nil, removedAt: Date? = nil) {
        self.id = id
        self.event = event
        self.addedAt = addedAt
        self.source = source
        self.removedAt = removedAt
    }
}

/// Recently added events, newest first, persisted as JSON.
@MainActor
@Observable
public final class HistoryStore {
    public private(set) var entries: [HistoryEntry] = []
    public static let limit = 500

    @ObservationIgnored private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = saved
        }
    }

    /// ~/Library/Application Support/<bundle id>/history.json
    public static var defaultFileURL: URL {
        let support = URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "SmartCalendarClassifier", directoryHint: .isDirectory)
        return support.appending(path: "history.json")
    }

    public func record(_ events: [SavedEvent], source: String?) {
        let now = Date.now
        entries.insert(contentsOf: events.map { HistoryEntry(event: $0, addedAt: now, source: source) }, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        save()
    }

    /// Marks events as removed (after Undo), keeping them in the list.
    public func markRemoved(_ events: [SavedEvent]) {
        let identifiers = Set(events.map(\.eventIdentifier))
        let now = Date.now
        for index in entries.indices where identifiers.contains(entries[index].event.eventIdentifier) && entries[index].removedAt == nil {
            entries[index].removedAt = now
        }
        save()
    }

    public func clear() {
        entries = []
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            // History is a convenience; failing to write it must never block adding events.
        }
    }
}
