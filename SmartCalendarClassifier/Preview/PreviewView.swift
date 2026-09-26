import AppKit
import SmartCalendarCore
import SwiftUI

/// The preview panel (decisions #5, #7, #12, #13): events stream into a checklist, anything
/// missing is highlighted and must be filled in, and ↩ adds everything that's checked.
struct PreviewView: View {
    @Bindable var model: PreviewModel
    let close: () -> Void

    @State private var expanded: Set<UUID> = []
    @State private var listHeight: CGFloat = 0
    @State private var showDetails = false
    @State private var autoClose: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)
            Divider()
            content
            Divider()
            footer
                .padding(12)
        }
        .frame(width: 460)
        .onExitCommand(perform: close)
        .onChange(of: model.items.count) { autoExpand() }
        .onChange(of: model.phase) { _, phase in
            autoClose?.cancel()
            if case .saved = phase {
                autoClose = Task {
                    try? await Task.sleep(for: .seconds(6))
                    if !Task.isCancelled { close() }
                }
            }
        }
        // Once the user is looking at or using the result, it stays until they dismiss it.
        .onHover { hovering in if hovering { autoClose?.cancel() } }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            if model.items.count > 1 && !isSaved {
                // Lines up with the rows' checkboxes; shows a dash when only some are checked.
                Toggle(sources: $model.items, isOn: \.isIncluded) { EmptyView() }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help("Select or deselect all")
                    .padding(.leading, 6)
            }
            if let icon = sourceIcon {
                Image(nsImage: icon).resizable().frame(width: 28, height: 28)
            } else {
                Image(systemName: "calendar.badge.plus").font(.title2).foregroundStyle(.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.headline)
                if let source = sourceLine {
                    Text(source).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            if model.phase == .extracting {
                ProgressView().controlSize(.small)
            } else if model.isSummarizing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Writing notes…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var headline: String {
        switch model.phase {
        case .extracting:
            model.items.isEmpty ? "Reading your selection…" : "Found \(model.items.count) so far…"
        case .ready:
            model.items.isEmpty ? "No events found" : model.items.count == 1 ? "1 event" : "\(model.items.count) events"
        case .saved(let saved):
            "Added \(saved.count) event\(saved.count == 1 ? "" : "s")"
        }
    }

    private var sourceLine: String? {
        let parts = [model.capture.appName, model.capture.windowTitle].compactMap { $0 }
        return parts.isEmpty ? nil : "from " + parts.joined(separator: " — ")
    }

    private var sourceIcon: NSImage? {
        guard let bundleID = model.capture.appBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if model.items.isEmpty {
            VStack(spacing: 10) {
                if model.phase == .extracting {
                    Text("Apple Intelligence is looking for dates, times and places.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Nothing in the selection looked like an event.").foregroundStyle(.secondary)
                    Button("Create an Event Anyway") { model.addBlankEvent() }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach($model.items) { $item in
                        EventRow(
                            item: $item,
                            showsCheckbox: model.items.count > 1,
                            isExpanded: expanded.contains(item.id),
                            isLocked: isSaved,
                            defaultDuration: model.defaultDuration,
                            toggleExpanded: { toggle(item.id) }
                        )
                    }
                }
                .padding(12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            // Grow with the list up to a comfortable height, then scroll.
            .frame(height: min(max(listHeight, 80), 470))
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var isSaved: Bool {
        if case .saved = model.phase { true } else { false }
    }

    private func toggle(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    /// A lone event opens for editing; so does any event that's missing something.
    private func autoExpand() {
        if model.items.count == 1, let only = model.items.first { expanded.insert(only.id) }
        for item in model.items where !item.candidate.isComplete { expanded.insert(item.id) }
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        if case .saved(let saved) = model.phase {
            HStack {
                Label("Added to \(Set(saved.map(\.calendarTitle)).sorted().joined(separator: ", "))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .lineLimit(1)
                Spacer()
                Button("Undo") { model.undo() }
                if let first = saved.first, let url = first.calendarAppURL {
                    Button("Open in Calendar") {
                        // Keep the panel (it floats above Calendar) so Undo stays in reach.
                        autoClose?.cancel()
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Done", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            HStack {
                Button {
                    showDetails.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("How this was captured")
                .popover(isPresented: $showDetails, arrowEdge: .bottom) {
                    CaptureDetails(capture: model.capture, engine: model.engine, timing: model.timing)
                }

                if let message = model.errorMessage ?? model.saveBlocker {
                    Text(message).font(.caption).foregroundStyle(model.errorMessage == nil ? Color.secondary : .red).lineLimit(2)
                }
                Spacer()
                Button("Cancel", action: close)
                    .keyboardShortcut(.cancelAction)
                Button(addTitle) { model.save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSave)
            }
        }
    }

    private var addTitle: String {
        let count = model.included.count
        return count <= 1 ? "Add to Calendar" : "Add \(count) Events"
    }
}

// MARK: - Row

private struct EventRow: View {
    @Binding var item: PreviewModel.Item
    let showsCheckbox: Bool
    let isExpanded: Bool
    let isLocked: Bool
    let defaultDuration: TimeInterval
    let toggleExpanded: () -> Void

    @Environment(CalendarService.self) private var calendars

    private var candidate: EventCandidate { item.candidate }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if showsCheckbox {
                Toggle("", isOn: $item.isIncluded)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(isLocked)
            }
            VStack(alignment: .leading, spacing: 4) {
                summary
                    .contentShape(Rectangle())
                    .onTapGesture(perform: toggleExpanded)
                if isExpanded && !isLocked {
                    EventEditor(item: $item, defaultDuration: defaultDuration)
                        .padding(.top, 6)
                }
            }
        }
        .padding(10)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
        .opacity(item.isIncluded ? 1 : 0.5)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(candidate.title.isEmpty ? "Untitled" : candidate.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 8)
                calendarBadge
                if !isLocked {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(EventFormatting.when(candidate)).font(.callout).foregroundStyle(.secondary)
            if let location = candidate.location {
                Label(location, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary)
            }
            if let recurrence = candidate.recurrence {
                Label(EventFormatting.describe(recurrence), systemImage: "repeat").font(.caption).foregroundStyle(.secondary)
            }
            if !candidate.missingFields.isEmpty && item.isIncluded {
                Label("Needs " + EventFormatting.list(candidate.missingFields), systemImage: "exclamationmark.circle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            ForEach(calendars.conflicts(for: candidate)) { conflict in
                Label("Overlaps “\(conflict.title)”", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var calendarBadge: some View {
        if let calendar = calendars.calendars.first(where: { $0.id == item.calendarID }) {
            HStack(spacing: 4) {
                Circle().fill(Color(red: calendar.red, green: calendar.green, blue: calendar.blue)).frame(width: 8, height: 8)
                Text(calendar.title).font(.caption).foregroundStyle(.secondary)
            }
            .help(item.calendarReason ?? "")
        }
    }
}

// MARK: - Editor

private struct EventEditor: View {
    @Binding var item: PreviewModel.Item
    let defaultDuration: TimeInterval

    @Environment(CalendarService.self) private var calendars
    private let calendar = Calendar.current

    private var candidate: EventCandidate { item.candidate }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                label("Title")
                TextField("Title", text: $item.candidate.title)
                    .textFieldStyle(.roundedBorder)
                    .overlay(missing(.title))
            }
            GridRow {
                label("All-day")
                Toggle("", isOn: Binding(
                    get: { candidate.isAllDay },
                    set: { item.candidate.setAllDay($0, calendar: calendar) }
                ))
                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
            GridRow {
                label(candidate.isAllDay ? "First day" : "Date")
                if candidate.start == nil {
                    fillButton("Choose a date") {
                        item.candidate.setDay(.now, calendar: calendar, defaultDuration: defaultDuration)
                    }
                } else {
                    DatePicker("", selection: dayBinding, displayedComponents: .date).labelsHidden().fixedSize()
                }
            }
            if candidate.isAllDay, candidate.start != nil {
                GridRow {
                    label("Last day")
                    DatePicker("", selection: Binding(
                        get: { candidate.end ?? candidate.start ?? .now },
                        set: { item.candidate.setLastDay($0, calendar: calendar) }
                    ), displayedComponents: .date).labelsHidden().fixedSize()
                }
            }
            if !candidate.isAllDay {
                GridRow {
                    label("Starts")
                    if candidate.startTimeMissing || candidate.start == nil {
                        fillButton("Choose a time") {
                            let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
                            item.candidate.setStartTime(nine, calendar: calendar, defaultDuration: defaultDuration)
                        }
                        .disabled(candidate.start == nil)
                    } else {
                        DatePicker("", selection: Binding(
                            get: { candidate.start ?? .now },
                            set: { item.candidate.setStartTime($0, calendar: calendar, defaultDuration: defaultDuration) }
                        ), displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
                    }
                }
                if !candidate.startTimeMissing, candidate.start != nil {
                    GridRow {
                        label("Ends")
                        HStack {
                            DatePicker("", selection: Binding(
                                get: { candidate.end ?? candidate.start ?? .now },
                                set: { item.candidate.setEndTime($0, calendar: calendar) }
                            ), displayedComponents: .hourAndMinute).labelsHidden().fixedSize()
                            if candidate.endIsAssumed {
                                Text("default length").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            GridRow {
                label("Location")
                TextField("None", text: Binding(
                    get: { candidate.location ?? "" },
                    set: { item.candidate.location = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
            if !candidate.notes.isEmpty {
                GridRow(alignment: .top) {
                    label("Notes")
                    Text(candidate.notes)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            GridRow {
                label("Calendar")
                VStack(alignment: .leading, spacing: 2) {
                    Picker("", selection: $item.calendarID) {
                        CalendarPickerItems(calendars: calendars.calendars)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!calendars.hasFullAccess)
                    if let reason = item.calendarReason {
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .font(.callout)
    }

    private var dayBinding: Binding<Date> {
        Binding(
            get: { candidate.start ?? .now },
            set: { item.candidate.setDay($0, calendar: calendar, defaultDuration: defaultDuration) }
        )
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }

    private func fillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "exclamationmark.circle.fill")
        }
        .tint(.orange)
    }

    @ViewBuilder
    private func missing(_ field: EventCandidate.Field) -> some View {
        if candidate.missingFields.contains(field) {
            RoundedRectangle(cornerRadius: 5).stroke(.orange, lineWidth: 1.5)
        }
    }
}

// MARK: - Details

private struct CaptureDetails: View {
    let capture: CapturedText
    let engine: ExtractionService.Engine?
    let timing: String?

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            row("Captured via", capture.method.rawValue)
            if let engine {
                switch engine {
                case .appleIntelligence: row("Read by", "Apple Intelligence")
                case .dataDetector(let reason): row("Read by", "Basic date detector — \(reason)")
                }
            }
            if let timing { row("Took", timing) }
            if let url = capture.url { row("Page", url.absoluteString) }
            row("Context", "\(capture.before?.count ?? 0) characters before, \(capture.after?.count ?? 0) after")
            if !capture.trace.isEmpty { row("Log", capture.trace.joined(separator: " → ")) }
        }
        .font(.caption)
        .textSelection(.enabled)
        .padding(12)
        .frame(width: 380)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow(alignment: .top) {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).lineLimit(4)
        }
    }
}
