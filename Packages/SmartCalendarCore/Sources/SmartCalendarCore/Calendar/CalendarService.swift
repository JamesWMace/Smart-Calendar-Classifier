import CoreGraphics
import EventKit
import Observation

public enum CalendarAuthorization: Sendable, Equatable {
    case notDetermined
    case fullAccess
    /// Can add events but not see calendars or conflicts; the user must upgrade in System Settings.
    case writeOnly
    case denied
    case restricted
}

public struct CalendarInfo: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    /// The account it belongs to, e.g. "iCloud" or "Google".
    public var sourceTitle: String
    /// sRGB components, for drawing the calendar's color dot.
    public var red: Double, green: Double, blue: Double

    init(_ calendar: EKCalendar) {
        id = calendar.calendarIdentifier
        title = calendar.title
        sourceTitle = calendar.source?.title ?? ""
        let srgb = calendar.cgColor.flatMap {
            $0.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)
        }
        let components = srgb?.components ?? [0.5, 0.5, 0.5, 1]
        (red, green, blue) = (Double(components[0]), Double(components[1]), Double(components[2]))
    }
}

/// A saved event, kept so it can be opened in Calendar or undone.
public struct SavedEvent: Sendable, Equatable {
    public var eventIdentifier: String
    public var calendarItemIdentifier: String
    public var calendarTitle: String
    public var start: Date

    /// Deep link that opens the event in Calendar.app.
    public var calendarAppURL: URL? {
        URL(string: "ical://ekevent/\(calendarItemIdentifier)?method=show&options=more")
    }
}

/// The app's single gateway to Apple Calendar: permission, the list of writable calendars,
/// conflict checks and saving (decisions #10, #11).
@MainActor
@Observable
public final class CalendarService {
    public private(set) var authorization: CalendarAuthorization
    /// Calendars the user can add events to, grouped by account.
    public private(set) var calendars: [CalendarInfo] = []
    public private(set) var defaultCalendarID: String?

    @ObservationIgnored private var store = EKEventStore()
    @ObservationIgnored private var changeObserver: NSObjectProtocol?

    public init() {
        authorization = Self.currentAuthorization()
        observeChanges()
        reload()
    }

    isolated deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
    }

    public var hasFullAccess: Bool { authorization == .fullAccess }

    /// Shows the system permission prompt the first time; afterwards it only re-reads the status.
    public func requestAccess() async {
        _ = try? await store.requestFullAccessToEvents()
        authorization = Self.currentAuthorization()
        if hasFullAccess {
            // A store created before access was granted can keep returning no calendars.
            store = EKEventStore()
            observeChanges()
        }
        reload()
    }

    public func reload() {
        authorization = Self.currentAuthorization()
        guard hasFullAccess else {
            calendars = []
            defaultCalendarID = nil
            return
        }
        calendars = store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map(CalendarInfo.init)
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
        defaultCalendarID = store.defaultCalendarForNewEvents?.calendarIdentifier
    }

    /// The calendar to preselect: the model's suggestion if it names a real calendar, then
    /// the user's preferred calendar from Settings, then the system default.
    public func calendarID(suggestedName: String?, preferredID: String?) -> String? {
        if let suggestedName,
           let match = calendars.first(where: { $0.title.caseInsensitiveCompare(suggestedName) == .orderedSame }) {
            return match.id
        }
        if let preferredID, calendars.contains(where: { $0.id == preferredID }) { return preferredID }
        return defaultCalendarID ?? calendars.first?.id
    }

    public func conflicts(for candidate: EventCandidate) -> [ExistingEvent] {
        guard hasFullAccess, !candidate.isAllDay, let start = candidate.start, let end = candidate.end, end > start else {
            return []
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let existing = store.events(matching: predicate).map(ExistingEvent.init)
        return ConflictDetector.conflicts(for: candidate, among: existing)
    }

    @discardableResult
    public func save(_ candidate: EventCandidate, calendarID: String?, defaultAlertMinutes: [Int]) throws -> SavedEvent {
        let calendar = calendarID.flatMap(store.calendar(withIdentifier:)) ?? store.defaultCalendarForNewEvents
        let event = try EventMapper.makeEvent(
            from: candidate, in: store, calendar: calendar, defaultAlertMinutes: defaultAlertMinutes
        )
        try store.save(event, span: .futureEvents, commit: true)
        return SavedEvent(
            eventIdentifier: event.eventIdentifier ?? "",
            calendarItemIdentifier: event.calendarItemIdentifier,
            calendarTitle: event.calendar?.title ?? "",
            start: event.startDate
        )
    }

    /// Undo for a just-saved event.
    public func remove(_ saved: SavedEvent) throws {
        guard let event = store.event(withIdentifier: saved.eventIdentifier) else { return }
        try store.remove(event, span: .futureEvents, commit: true)
    }

    private func observeChanges() {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    private static func currentAuthorization() -> CalendarAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .fullAccess
        case .writeOnly: .writeOnly
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }
}

extension ExistingEvent {
    init(_ event: EKEvent) {
        let declined = event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
        self.init(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "Untitled",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            blocksTime: event.availability != .free && !declined,
            calendarTitle: event.calendar?.title ?? ""
        )
    }
}
