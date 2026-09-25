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
        var id: UUID { candidate.id }
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

    @ObservationIgnored let calendars: CalendarService
    @ObservationIgnored private var task: Task<Void, Never>?

    init(capture: CapturedText, calendars: CalendarService) {
        self.capture = capture
        self.calendars = calendars
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
        let service = ExtractionService(options: ResolutionOptions(defaultDurationMinutes: Int(defaultDuration / 60)))
        task = Task { [weak self] in
            let outcome = await service.extract(from: context) { [weak self] candidate in self?.append(candidate) }
            guard let self, !Task.isCancelled else { return }
            engine = outcome.engine
            if phase == .extracting { phase = .ready }
        }
    }

    func cancel() {
        task?.cancel()
        if phase == .extracting { phase = .ready }
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
                saved.append(try calendars.save(item.candidate, calendarID: item.calendarID, defaultAlertMinutes: alerts))
            }
            errorMessage = nil
            phase = .saved(saved)
        } catch {
            // Don't leave half a batch behind.
            for event in saved { try? calendars.remove(event) }
            errorMessage = error.localizedDescription
        }
    }

    func undo() {
        guard case .saved(let saved) = phase else { return }
        for event in saved { try? calendars.remove(event) }
        phase = .ready
    }

    private func append(_ candidate: EventCandidate) {
        let preferred = UserDefaults.standard.string(forKey: SettingsKey.defaultCalendarID).flatMap { $0.isEmpty ? nil : $0 }
        let calendarID = calendars.calendarID(suggestedName: candidate.suggestedCalendarName, preferredID: preferred) ?? ""
        items.append(Item(candidate: candidate, calendarID: calendarID))
    }
}
