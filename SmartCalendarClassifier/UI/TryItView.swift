import SmartCalendarCore
import SwiftUI

/// A playground for the extraction engine: paste text (plus optional context), see what the
/// model extracts and how it resolves. Stands in for the capture layer until phase 4.
struct TryItView: View {
    @Environment(CalendarService.self) private var calendars
    @AppStorage(SettingsKey.defaultDurationMinutes) private var defaultDurationMinutes = 60

    @State private var selection = "Hi team, let's do the design review next Tuesday from 3-5pm in the Orion conference room."
    @State private var textBefore = ""
    @State private var appName = ""
    @State private var windowTitle = ""
    @State private var showContext = false

    @State private var outcome: ExtractionService.Outcome?
    @State private var elapsed: Duration?
    @State private var isExtracting = false

    private let availability = ModelAvailability.current

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            TextEditor(text: $selection)
                .font(.body)
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background.secondary, in: .rect(cornerRadius: 8))

            DisclosureGroup("Context (optional)", isExpanded: $showContext) {
                Grid(alignment: .leading, verticalSpacing: 6) {
                    GridRow { Text("App"); TextField("e.g. Mail", text: $appName) }
                    GridRow { Text("Window title"); TextField("e.g. Re: Design review", text: $windowTitle) }
                    GridRow(alignment: .top) {
                        Text("Text before")
                        TextField("Earlier text in the same document", text: $textBefore, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(.top, 6)
            }

            HStack {
                Button(action: extract) {
                    Label("Extract Events", systemImage: "sparkles")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(isExtracting || selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if isExtracting { ProgressView().controlSize(.small) }
                Spacer()
                if let outcome, let elapsed { engineBadge(outcome.engine, elapsed: elapsed) }
            }

            Divider()
            results
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 520)
        .onAppear { if availability == .available { FoundationModelsExtractor.prewarm() } }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Paste or type some text").font(.headline)
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                switch availability {
                case .available:
                    Label("Apple Intelligence ready", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                case .unavailable(let reason):
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                CalendarAccessView()
            }
            .font(.callout)
        }
    }

    private func engineBadge(_ engine: ExtractionService.Engine, elapsed: Duration) -> some View {
        let seconds = elapsed.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow, maximumUnitCount: 1))
        return Group {
            switch engine {
            case .appleIntelligence:
                Text("Apple Intelligence · \(seconds)")
            case .dataDetector(let reason):
                Text("Fallback detector · \(seconds) — \(reason)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var results: some View {
        if let outcome {
            if outcome.candidates.isEmpty {
                ContentUnavailableView("No events found", systemImage: "calendar.badge.exclamationmark")
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(outcome.candidates) { CandidateCard(candidate: $0) }
                    }
                }
            }
        } else {
            ContentUnavailableView("Press ⌘↩ to extract", systemImage: "calendar.badge.plus")
        }
    }

    private func extract() {
        let context = CaptureContext(
            selection: selection,
            textBefore: textBefore.isEmpty ? nil : textBefore,
            appName: appName.isEmpty ? nil : appName,
            windowTitle: windowTitle.isEmpty ? nil : windowTitle,
            calendarNames: calendars.calendars.map(\.title).reduce(into: []) { names, title in
                if !names.contains(title) { names.append(title) }
            }
        )
        let service = ExtractionService(options: ResolutionOptions(defaultDurationMinutes: defaultDurationMinutes))
        isExtracting = true
        Task {
            let clock = ContinuousClock()
            let start = clock.now
            let result = await service.extract(from: context)
            elapsed = clock.now - start
            outcome = result
            isExtracting = false
        }
    }
}

private struct CandidateCard: View {
    let candidate: EventCandidate
    @Environment(CalendarService.self) private var calendars
    @AppStorage(SettingsKey.defaultCalendarID) private var preferredCalendarID = ""
    @AppStorage(SettingsKey.defaultAlertMinutes) private var defaultAlertMinutes = -1

    @State private var showNotes = false
    @State private var calendarID = ""
    @State private var conflicts: [ExistingEvent] = []
    @State private var saved: SavedEvent?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(candidate.title.isEmpty ? "Untitled" : candidate.title)
                    .font(.title3.weight(.semibold))
                Spacer()
            }
            row("calendar", when)
            if let location = candidate.location { row("mappin.and.ellipse", location) }
            if let url = candidate.url { row("link", url.absoluteString) }
            if let recurrence = candidate.recurrence { row("repeat", describe(recurrence)) }
            if !candidate.alertMinutesBefore.isEmpty {
                row("bell", candidate.alertMinutesBefore.map { "\($0) min before" }.joined(separator: ", "))
            }
            if !candidate.missingFields.isEmpty {
                Label("Needs: " + candidate.missingFields.map(label).sorted().joined(separator: ", "),
                      systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            ForEach(conflicts) { conflict in
                Label("Overlaps “\(conflict.title)” \(conflict.start.formatted(date: .omitted, time: .shortened))–\(conflict.end.formatted(date: .omitted, time: .shortened))",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            DisclosureGroup("Notes", isExpanded: $showNotes) {
                Text(candidate.notes).font(.callout).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.callout)
            Divider()
            saveBar
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
        .task(id: calendars.calendars) { refreshCalendarState() }
    }

    @ViewBuilder
    private var saveBar: some View {
        HStack {
            if let saved {
                Label("Added to \(saved.calendarTitle)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                if let url = saved.calendarAppURL {
                    Button("Open in Calendar") { NSWorkspace.shared.open(url) }
                }
                Button("Undo") { undo(saved) }
            } else {
                Picker("Calendar", selection: $calendarID) {
                    CalendarPickerItems(calendars: calendars.calendars)
                }
                .labelsHidden()
                .fixedSize()
                .disabled(!calendars.hasFullAccess)
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.caption).lineLimit(2)
                }
                Spacer()
                Button("Add to Calendar", systemImage: "calendar.badge.plus", action: save)
                    .disabled(!calendars.hasFullAccess || !candidate.isComplete || calendarID.isEmpty)
                    .help(candidate.isComplete ? "" : "Fill in the missing details first (editing arrives with the preview panel).")
            }
        }
        .font(.callout)
    }

    private func refreshCalendarState() {
        if calendarID.isEmpty || !calendars.calendars.contains(where: { $0.id == calendarID }) {
            calendarID = calendars.calendarID(
                suggestedName: candidate.suggestedCalendarName,
                preferredID: preferredCalendarID.isEmpty ? nil : preferredCalendarID
            ) ?? ""
        }
        conflicts = calendars.conflicts(for: candidate)
    }

    private func save() {
        do {
            saved = try calendars.save(candidate, calendarID: calendarID, defaultAlertMinutes: defaultAlertMinutes.alertMinutesSetting)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func undo(_ event: SavedEvent) {
        do {
            try calendars.remove(event)
            saved = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.callout).textSelection(.enabled)
    }

    private var when: String {
        guard let start = candidate.start else {
            if let hint = candidate.startTimeHint, let hour = hint.hour {
                return String(format: "Date needed · %d:%02d", hour, hint.minute ?? 0)
            }
            return "Date needed"
        }
        if candidate.isAllDay {
            let day = start.formatted(date: .abbreviated, time: .omitted)
            guard let end = candidate.end, !Calendar.current.isDate(end, inSameDayAs: start) else { return "\(day) · all day" }
            return "\(day) – \(end.formatted(date: .abbreviated, time: .omitted)) · all day"
        }
        if candidate.startTimeMissing {
            return "\(start.formatted(date: .complete, time: .omitted)) · time needed"
        }
        var text = start.formatted(date: .complete, time: .shortened)
        if let end = candidate.end {
            let sameDay = Calendar.current.isDate(end, inSameDayAs: start)
            text += " – " + end.formatted(date: sameDay ? .omitted : .abbreviated, time: .shortened)
            if candidate.endIsAssumed { text += " (assumed)" }
        }
        return text
    }

    private func label(_ field: EventCandidate.Field) -> String {
        switch field {
        case .title: "title"
        case .date: "date"
        case .startTime: "start time"
        }
    }

    private func describe(_ recurrence: Recurrence) -> String {
        let unit = switch recurrence.frequency {
        case .daily: "day"
        case .weekly: "week"
        case .monthly: "month"
        case .yearly: "year"
        }
        var text = recurrence.interval == 1 ? "Every \(unit)" : "Every \(recurrence.interval) \(unit)s"
        if !recurrence.weekdays.isEmpty {
            let symbols = Calendar.current.shortWeekdaySymbols
            text += " on " + recurrence.weekdays.map { symbols[$0 - 1] }.joined(separator: ", ")
        }
        if let until = recurrence.until { text += " until " + until.formatted(date: .abbreviated, time: .omitted) }
        if let count = recurrence.occurrenceCount { text += ", \(count) times" }
        return text
    }
}
