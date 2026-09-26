import Foundation
import SmartCalendarCore

/// State behind the preview panel for one capture: streams events in, tracks which are
/// checked and where they go, and saves or undoes them.
@MainActor
@Observable
final class PreviewModel {
    struct Item: Identifiable {
        var candidate: EventCandidate
        var isIncluded = true
        var calendarID: String
        /// How the calendar was picked; stale once the user picks another.
        var choice: CalendarChoice?
        var id: UUID { candidate.id }

        /// Why this calendar, while it's still the app's pick.
        var calendarReason: String? {
            guard let choice, choice.calendarID == calendarID else { return nil }
            return switch choice.reason {
            case .namedInText: "Named in the text"
            case .similarEvents: "Similar events are in this calendar"
            case .suggested: "Suggested by Apple Intelligence"
            case .defaultCalendar: nil
            }
        }
    }

    enum Phase: Equatable {
        case extracting
        case ready
        case saved([SavedEvent])
    }

    let capture: CapturedText
    var items: [Item] = []
    private(set) var phase = Phase.extracting
    private(set) var engine: ExtractionService.Engine?
    var errorMessage: String?
    /// How long reading took ("first event 2.1 s, all 3.4 s"), for the details popover.
    private(set) var timing: String?
    @ObservationIgnored private var firstEventAfter: Duration?
    /// True while optional notes summaries are being written.
    private(set) var isSummarizing = false
    @ObservationIgnored private var context: CaptureContext?
    @ObservationIgnored private var summaryTask: Task<Void, Never>?
    /// Saved events by candidate, so late summaries can reach events already added.
    @ObservationIgnored private var savedByCandidate: [UUID: SavedEvent] = [:]
    #if DEBUG
    @ObservationIgnored private(set) var debugPrompt = ""
    #endif

    @ObservationIgnored let calendars: CalendarService
    @ObservationIgnored private let history: HistoryStore
    @ObservationIgnored private var task: Task<Void, Never>?

    init(capture: CapturedText, calendars: CalendarService, history: HistoryStore) {
        self.capture = capture
        self.calendars = calendars
        self.history = history
    }

    var included: [Item] { items.filter(\.isIncluded) }

    var canSave: Bool {
        calendars.hasFullAccess && !included.isEmpty
            && included.allSatisfy { $0.candidate.isComplete && !$0.calendarID.isEmpty }
    }

    /// Why "Add" is disabled, if it is.
    var saveBlocker: String? {
        if !calendars.hasFullAccess { return "Allow calendar access first." }
        if included.isEmpty { return phase == .extracting ? nil : "Nothing selected." }
        if included.contains(where: { !$0.candidate.isComplete }) { return "Fill in the highlighted details." }
        return nil
    }

    var defaultDuration: TimeInterval {
        let minutes = UserDefaults.standard.integer(forKey: SettingsKey.defaultDurationMinutes)
        return TimeInterval((minutes > 0 ? minutes : 60) * 60)
    }

    func start() {
        let context = CaptureContext(
            selection: capture.selection,
            textBefore: capture.before,
            textAfter: capture.after,
            appName: capture.appName,
            windowTitle: capture.windowTitle,
            url: capture.url,
            calendarNames: calendars.calendars.map(\.title).reduce(into: []) { names, title in
                if !names.contains(title) { names.append(title) }
            }
        )
        self.context = context
        #if DEBUG
        debugPrompt = PromptBuilder.prompt(for: context)
        #endif
        let service = ExtractionService(options: ResolutionOptions(defaultDurationMinutes: Int(defaultDuration / 60)))
        let clock = ContinuousClock()
        let began = clock.now
        // A menu bar app is never frontmost; without this, App Nap throttles the extraction.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Reading events")
        task = Task(priority: .userInitiated) { [weak self] in
            defer { ProcessInfo.processInfo.endActivity(activity) }
            let outcome = await service.extract(from: context) { [weak self] candidate in
                if self?.firstEventAfter == nil { self?.firstEventAfter = clock.now - began }
                self?.append(candidate)
            }
            guard let self, !Task.isCancelled else { return }
            let format = { (duration: Duration) in duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow, maximumUnitCount: 1)) }
            timing = (firstEventAfter.map { "first event \(format($0)), " } ?? "") + "all \(format(clock.now - began))"
            engine = outcome.engine
            if phase == .extracting { phase = .ready }
            // Trust mode (decision #12): add right away unless something needs the user.
            if UserDefaults.standard.bool(forKey: SettingsKey.trustMode), canSave { save() }
            if outcome.engine == .appleIntelligence, UserDefaults.standard.bool(forKey: SettingsKey.summarizeNotes) {
                summarize()
            }
        }
    }

    func cancel() {
        task?.cancel()
        if phase == .extracting { phase = .ready }
        // Summaries still matter for events already added; otherwise there's nowhere for them to go.
        if case .saved = phase {} else { summaryTask?.cancel() }
    }

    /// Writes each event's notes summary, one at a time, after the events are shown.
    private func summarize() {
        guard let context else { return }
        let targets = items.map(\.candidate)
        isSummarizing = true
        summaryTask = Task(priority: .userInitiated) { [weak self] in
            let writer = SummaryWriter()
            for candidate in targets {
                guard !Task.isCancelled else { break }
                guard let summary = try? await writer.summary(for: candidate, context: context) else { continue }
                self?.applySummary(summary, to: candidate.id, context: context)
            }
            self?.isSummarizing = false
        }
    }

    private func applySummary(_ summary: String, to id: UUID, context: CaptureContext) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let candidate = items[index].candidate
        let notes = NotesComposer.compose(
            summary: summary, context: context, sourceTimeZone: candidate.sourceTimeZone, start: candidate.start
        )
        items[index].candidate.notes = notes
        if let saved = savedByCandidate[id] { try? calendars.updateNotes(of: saved, to: notes) }
    }

    /// A blank event when the model found nothing but the user still wants one.
    func addBlankEvent() {
        let firstLine = capture.selection.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        append(EventCandidate(title: String(firstLine.prefix(60)), isAllDay: true, start: nil, end: nil))
    }

    func save() {
        task?.cancel()
        let alerts = (UserDefaults.standard.object(forKey: SettingsKey.defaultAlertMinutes) as? Int ?? -1).alertMinutesSetting
        var saved: [SavedEvent] = []
        do {
            for item in included {
                let event = try calendars.save(item.candidate, calendarID: item.calendarID, defaultAlertMinutes: alerts)
                saved.append(event)
                savedByCandidate[item.id] = event
            }
            errorMessage = nil
            history.record(saved, source: capture.appName)
            phase = .saved(saved)
        } catch {
            // Don't leave half a batch behind.
            for event in saved { try? calendars.remove(event) }
            savedByCandidate = [:]
            errorMessage = error.localizedDescription
        }
    }

    func undo() {
        guard case .saved(let saved) = phase else { return }
        for event in saved { try? calendars.remove(event) }
        history.markRemoved(saved)
        savedByCandidate = [:]
        phase = .ready
    }

    private func append(_ candidate: EventCandidate) {
        let preferred = UserDefaults.standard.string(forKey: SettingsKey.defaultCalendarID).flatMap { $0.isEmpty ? nil : $0 }
        let choice = calendars.choose(for: candidate, source: capture.appName, preferredID: preferred)
        items.append(Item(candidate: candidate, calendarID: choice?.calendarID ?? "", choice: choice))
    }
}
