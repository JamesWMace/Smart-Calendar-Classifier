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
public struct SavedEvent: Sendable, Equatable, Codable {
    public var eventIdentifier: String
    public var calendarItemIdentifier: String
    /// Optional so history saved before it existed still loads.
    public var calendarID: String?
    public var calendarTitle: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool

    public init(
        eventIdentifier: String, calendarItemIdentifier: String, calendarID: String? = nil, calendarTitle: String,
        title: String, start: Date, end: Date, isAllDay: Bool
    ) {
        self.eventIdentifier = eventIdentifier
        self.calendarItemIdentifier = calendarItemIdentifier
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
    }

    /// Deep link that opens the event in Calendar.app.
    public var calendarAppURL: URL? {
        URL(string: "ical://ekevent/\(calendarItemIdentifier)?method=show&options=more")
    }
}

/// Which calendar was picked for an event, and why (shown in the preview panel).
public struct CalendarChoice: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        /// The text names the calendar.
        case namedInText
        /// Similar events already live there (or events from the same app went there).
        case similarEvents
        /// The on-device model's guess from calendar names.
        case suggested
        /// The default from Settings or the system.
        case defaultCalendar
    }

    public var calendarID: String
    public var reason: Reason
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
    /// Learned from the calendars' own events plus history; rebuilt in the background.
    @ObservationIgnored private var classifier = CalendarClassifier(examples: [])
    @ObservationIgnored private var classifierTask: Task<Void, Never>?
    /// Past additions (with the app they came from), supplied by the app.
    @ObservationIgnored public var historyProvider: (@MainActor () -> [HistoryEntry])? {
        didSet { rebuildClassifier() }
    }

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
        rebuildClassifier()
    }

    /// The calendar to preselect, strongest evidence first: a calendar the text names, then
    /// where similar events already are, then the model's guess, then the default.
    public func choose(for candidate: EventCandidate, source: String?, preferredID: String?) -> CalendarChoice? {
        func id(named name: String?) -> String? {
            name.flatMap { name in calendars.first { $0.title.caseInsensitiveCompare(name) == .orderedSame }?.id }
        }
        if let named = id(named: candidate.namedCalendar) {
            return CalendarChoice(calendarID: named, reason: .namedInText)
        }
        let text = [candidate.title, candidate.location ?? ""].joined(separator: " ")
        if let match = classifier.classify(text, source: source), calendars.contains(where: { $0.id == match.calendarID }) {
            return CalendarChoice(calendarID: match.calendarID, reason: .similarEvents)
        }
        if let suggested = id(named: candidate.suggestedCalendarName) {
            return CalendarChoice(calendarID: suggested, reason: .suggested)
        }
        let fallback = preferredID.flatMap { id in calendars.contains { $0.id == id } ? id : nil } ?? defaultCalendarID ?? calendars.first?.id
        return fallback.map { CalendarChoice(calendarID: $0, reason: .defaultCalendar) }
    }

    /// Re-learns what each calendar holds: titles and places of events from the past year and
    /// the coming six months, plus past additions and the apps they came from. Runs in the
    /// background, debounced, since a save or sync can fire several changes at once.
    private func rebuildClassifier() {
        classifierTask?.cancel()
        guard hasFullAccess else { return }
        let ids = Set(calendars.map(\.id))
        let titles = Dictionary(calendars.map { ($0.title, $0.id) }, uniquingKeysWith: { first, _ in first })
        let history = (historyProvider?() ?? []).compactMap { entry -> CalendarClassifier.Example? in
            guard entry.removedAt == nil, let id = entry.event.calendarID ?? titles[entry.event.calendarTitle] else { return nil }
            return CalendarClassifier.Example(calendarID: id, text: entry.event.title, source: entry.source)
        }
        classifierTask = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let store = EKEventStore()
            let calendars = store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
            let now = Date.now
            let predicate = store.predicateForEvents(
                withStart: now.addingTimeInterval(-365 * 86_400), end: now.addingTimeInterval(182 * 86_400), calendars: calendars
            )
            let examples = store.events(matching: predicate).compactMap { event -> CalendarClassifier.Example? in
                guard let id = event.calendar?.calendarIdentifier else { return nil }
                return CalendarClassifier.Example(calendarID: id, text: [event.title, event.location].compactMap { $0 }.joined(separator: " "))
            }
            let classifier = CalendarClassifier(examples: examples + history)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.classifier = classifier }
        }
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
            calendarID: event.calendar?.calendarIdentifier,
            calendarTitle: event.calendar?.title ?? "",
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay
        )
    }

    /// Whether a saved event is still in the calendar (it may have been deleted in Calendar).
    public func exists(_ saved: SavedEvent) -> Bool {
        hasFullAccess && store.event(withIdentifier: saved.eventIdentifier) != nil
    }

    /// Undo for a saved event.
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
