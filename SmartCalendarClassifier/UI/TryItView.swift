import SmartCalendarCore
import SwiftUI

/// A playground for the extraction engine: paste text (plus optional context) and see what the
/// model extracts and how it resolves. Real captures open in the preview panel instead.
struct TryItView: View {
    @Environment(CalendarService.self) private var calendars
    @AppStorage(SettingsKey.defaultDurationMinutes) private var defaultDurationMinutes = 60

    @State private var selection = "Hi team, let's do the design review next Tuesday from 3-5pm in the Orion conference room."
    @State private var textBefore = ""
    @State private var textAfter = ""
    @State private var appName = ""
    @State private var windowTitle = ""
    @State private var urlText = ""
    @State private var showContext = false

    @State private var outcome: ExtractionService.Outcome?
    /// Filled in as each event streams in, before `outcome` (the finished run) exists.
    @State private var candidates: [EventCandidate] = []
    /// Identifies the current run, so a superseded one stops adding cards.
    @State private var extractionID = UUID()
    @State private var elapsed: Duration?
    @State private var isExtracting = false

    private let availability = ModelAvailability.current

    var body: some View {
        // One scrolling page, so the event cards can use the whole window once the text and
        // context have been scrolled past.
        ScrollViewReader { scroller in
            ScrollView {
                form
                    .padding(16)
            }
            .onChange(of: candidates.isEmpty) { _, isEmpty in
                // Bring the first card into view; later ones append below without jumping.
                if !isEmpty { withAnimation { scroller.scrollTo(Self.resultsID, anchor: .top) } }
            }
        }
        .frame(minWidth: 620, minHeight: 520)
        .onAppear { if availability == .available { FoundationModelsExtractor.prewarm() } }
    }

    private static let resultsID = "results"

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            TextEditor(text: $selection)
                .font(.body)
                .frame(height: 150)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background.secondary, in: .rect(cornerRadius: 8))

            DisclosureGroup(isExpanded: $showContext) {
                Grid(alignment: .leading, verticalSpacing: 6) {
                    GridRow { Text("App"); TextField("e.g. Mail", text: $appName) }
                    GridRow { Text("Window title"); TextField("e.g. Re: Design review", text: $windowTitle) }
                    GridRow { Text("Page address"); TextField("https://…", text: $urlText) }
                    GridRow(alignment: .top) {
                        Text("Text before")
                        TextField("Earlier text in the same document", text: $textBefore, axis: .vertical)
                            .lineLimit(2...4)
                    }
                    GridRow(alignment: .top) {
                        Text("Text after")
                        TextField("Later text in the same document", text: $textAfter, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(.top, 6)
            } label: {
                Text("Context")
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
                if isExtracting, !candidates.isEmpty {
                    Text("\(candidates.count) found so far…").font(.caption).foregroundStyle(.secondary)
                } else if let outcome, let elapsed {
                    engineBadge(outcome.engine, elapsed: elapsed)
                }
            }

            Divider()
            results
                .id(Self.resultsID)
        }
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
        if !candidates.isEmpty {
            LazyVStack(spacing: 10) {
                ForEach(candidates) { CandidateCard(candidate: $0) }
                if isExtracting {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Looking for more events…").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
        } else if isExtracting {
            ContentUnavailableView("Finding events…", systemImage: "sparkles").frame(minHeight: 180)
        } else if outcome != nil {
            ContentUnavailableView("No events found", systemImage: "calendar.badge.exclamationmark").frame(minHeight: 180)
        } else {
            ContentUnavailableView("Press ⌘↩ to extract", systemImage: "calendar.badge.plus").frame(minHeight: 180)
        }
    }

    private func extract() {
        let context = CaptureContext(
            selection: selection,
            textBefore: textBefore.isEmpty ? nil : textBefore,
            textAfter: textAfter.isEmpty ? nil : textAfter,
            appName: appName.isEmpty ? nil : appName,
            windowTitle: windowTitle.isEmpty ? nil : windowTitle,
            url: URL(string: urlText),
            calendarNames: calendars.calendars.map(\.title).reduce(into: []) { names, title in
                if !names.contains(title) { names.append(title) }
            }
        )
        let service = ExtractionService(options: ResolutionOptions(defaultDurationMinutes: defaultDurationMinutes))
        let id = UUID()
        extractionID = id
        isExtracting = true
        outcome = nil
        candidates = []
        let current = $extractionID, cards = $candidates
        Task {
            let clock = ContinuousClock()
            let start = clock.now
            let result = await service.extract(from: context) { candidate in
                if current.wrappedValue == id { withAnimation { cards.wrappedValue.append(candidate) } }
            }
            guard extractionID == id else { return }
            elapsed = clock.now - start
            outcome = result
            isExtracting = false
        }
    }
}

private struct CandidateCard: View {
    let candidate: EventCandidate
    @Environment(CalendarService.self) private var calendars
    @Environment(HistoryStore.self) private var history
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
            row("calendar", EventFormatting.when(candidate) + (candidate.endIsAssumed && !candidate.isAllDay ? " (assumed)" : ""))
            if let location = candidate.location { row("mappin.and.ellipse", location) }
            if let url = candidate.url { row("link", url.absoluteString) }
            if let recurrence = candidate.recurrence { row("repeat", EventFormatting.describe(recurrence)) }
            if !candidate.alertMinutesBefore.isEmpty {
                row("bell", candidate.alertMinutesBefore.map { "\($0) min before" }.joined(separator: ", "))
            }
            if !candidate.missingFields.isEmpty {
                Label("Needs " + EventFormatting.list(candidate.missingFields),
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
            calendarID = calendars.choose(
                for: candidate, source: nil, preferredID: preferredCalendarID.isEmpty ? nil : preferredCalendarID
            )?.calendarID ?? ""
        }
        conflicts = calendars.conflicts(for: candidate)
    }

    private func save() {
        do {
            let event = try calendars.save(candidate, calendarID: calendarID, defaultAlertMinutes: defaultAlertMinutes.alertMinutesSetting)
            saved = event
            history.record([event], source: "Try It")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func undo(_ event: SavedEvent) {
        do {
            try calendars.remove(event)
            history.markRemoved([event])
            saved = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.callout).textSelection(.enabled)
    }
}
