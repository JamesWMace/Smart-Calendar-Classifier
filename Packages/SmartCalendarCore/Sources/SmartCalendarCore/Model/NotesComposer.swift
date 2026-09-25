import Foundation

/// Builds the event's notes: AI summary, original-time note, the highlighted text, and where
/// it came from (decision #9).
public enum NotesComposer {
    public static func compose(
        summary: String,
        context: CaptureContext,
        sourceTimeZone: TimeZone?,
        start: Date?
    ) -> String {
        var sections: [String] = []

        let summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty { sections.append(summary) }

        if let sourceTimeZone, let start {
            sections.append("Originally \(originalTime(start, in: sourceTimeZone)).")
        }

        let selection = context.selection.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selection.isEmpty {
            sections.append("— Original text —\n" + selection)
        }

        var source: [String] = []
        if let app = context.appName.nonEmpty {
            source.append(context.windowTitle.nonEmpty.map { "\(app) — \($0)" } ?? app)
        }
        if let url = context.url { source.append(url.absoluteString) }
        if !source.isEmpty {
            sections.append("Source: " + source.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    /// "3:00 PM EDT" — the time as it was written, in the writer's zone.
    static func originalTime(_ date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "h:mm a zzz"
        return formatter.string(from: date)
    }
}
