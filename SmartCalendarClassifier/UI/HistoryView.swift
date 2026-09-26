import SmartCalendarCore
import SwiftUI

/// Everything the app has added, newest first, with Open in Calendar and Remove.
struct HistoryView: View {
    @Environment(HistoryStore.self) private var history
    @Environment(CalendarService.self) private var calendars
    @State private var pendingRemoval: HistoryEntry?
    @State private var confirmClear = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if history.entries.isEmpty {
                ContentUnavailableView {
                    Label("No events yet", systemImage: "calendar.badge.plus")
                } description: {
                    Text("Select text in any app and press \(ShortcutStore.shared.shortcut.display). Events you add show up here.")
                }
            } else {
                List {
                    ForEach(sections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.entries) { entry in
                                HistoryRow(entry: entry, exists: calendars.exists(entry.event)) {
                                    pendingRemoval = entry
                                }
                            }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !history.entries.isEmpty {
                HStack {
                    if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
                    Spacer()
                    Button("Clear History…") { confirmClear = true }
                }
                .padding(10)
                .background(.bar)
            }
        }
        .confirmationDialog(
            "Remove “\(pendingRemoval?.event.title ?? "")” from your calendar?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { entry in
            Button("Remove Event", role: .destructive) { remove(entry) }
        } message: { entry in
            Text("This deletes the event from “\(entry.event.calendarTitle)”.")
        }
        .confirmationDialog("Clear the history list?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { history.clear() }
        } message: {
            Text("Events stay in your calendars; only this list is cleared.")
        }
    }

    private func remove(_ entry: HistoryEntry) {
        do {
            try calendars.remove(entry.event)
            history.markRemoved([entry.event])
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var sections: [(title: String, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        var result: [(title: String, entries: [HistoryEntry])] = []
        for entry in history.entries {
            let title: String
            if calendar.isDateInToday(entry.addedAt) {
                title = "Added Today"
            } else if calendar.isDateInYesterday(entry.addedAt) {
                title = "Added Yesterday"
            } else {
                title = "Added " + entry.addedAt.formatted(date: .abbreviated, time: .omitted)
            }
            if result.last?.title == title { result[result.count - 1].entries.append(entry) } else { result.append((title, [entry])) }
        }
        return result
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let exists: Bool
    let remove: () -> Void

    private var isGone: Bool { entry.removedAt != nil || !exists }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.event.title.isEmpty ? "Untitled" : entry.event.title)
                    .font(.body.weight(.semibold))
                    .strikethrough(isGone)
                Text(when).font(.callout).foregroundStyle(.secondary)
                Text(details).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if entry.removedAt != nil {
                Text("Removed").font(.caption).foregroundStyle(.secondary)
            } else if !exists {
                Text("Deleted in Calendar").font(.caption).foregroundStyle(.secondary)
            } else {
                if let url = entry.event.calendarAppURL {
                    Button("Open") { NSWorkspace.shared.open(url) }
                }
                Button("Remove…", action: remove)
            }
        }
        .padding(.vertical, 4)
        .opacity(isGone ? 0.6 : 1)
    }

    private var when: String {
        let start = entry.event.start, end = entry.event.end
        if entry.event.isAllDay {
            let first = start.formatted(date: .abbreviated, time: .omitted)
            return Calendar.current.isDate(start, inSameDayAs: end) ? "\(first) · all day"
                : "\(first) – \(end.formatted(date: .abbreviated, time: .omitted)) · all day"
        }
        let sameDay = Calendar.current.isDate(start, inSameDayAs: end)
        return start.formatted(date: .complete, time: .shortened) + " – " + end.formatted(date: sameDay ? .omitted : .abbreviated, time: .shortened)
    }

    private var details: String {
        var parts = [entry.event.calendarTitle]
        if let source = entry.source { parts.append("from \(source)") }
        parts.append("added \(entry.addedAt.formatted(date: .omitted, time: .shortened))")
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
