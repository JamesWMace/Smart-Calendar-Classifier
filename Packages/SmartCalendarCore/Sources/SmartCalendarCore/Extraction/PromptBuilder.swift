import Foundation

/// Builds the instructions and prompt for the on-device model, keeping the whole request
/// comfortably inside its ~4K-token context window (schema included).
public enum PromptBuilder {
    public struct Budget: Sendable {
        public var selection = 3_000
        public var contextBefore = 1_000
        public var contextAfter = 600
        public var windowTitle = 200
        public var calendarNames = 20

        public init() {}
    }

    public static let instructions = """
        You turn text that a user highlighted on their Mac into calendar events.

        Rules:
        - Create events for what the SELECTED TEXT describes or refers to. Use the surrounding \
        context, window title and app name to resolve references such as 'then' or 'the \
        meeting' and to fill in details such as names, places and course codes. Do not create \
        events for other things mentioned only in the context.
        - Never invent a date or a time. If the text does not state one, use kind missing or \
        leave the time out.
        - Copy the words for dates, times and time zones exactly as written. Do not convert \
        or calculate anything.
        - One event per distinct occasion. A time range such as '3-5pm' is one event with a \
        start and end time. A multi-day range such as 'Oct 3-5' is one event with an end date.
        - Deadlines such as 'due Friday' or 'submit by Oct 3' are events whose title ends in 'Due' or 'Deadline'.
        """

    public static func prompt(for context: CaptureContext, budget: Budget = .init()) -> String {
        var lines: [String] = []

        if let app = context.appName.nonEmpty {
            lines.append("Source app: \(app)")
        }
        if let title = context.windowTitle.nonEmpty {
            lines.append("Window title: \(truncate(title, to: budget.windowTitle))")
        }
        if let url = context.url {
            lines.append("Page address: \(truncate(url.absoluteString, to: 300))")
        }
        if !context.calendarNames.isEmpty {
            let names = context.calendarNames.prefix(budget.calendarNames).joined(separator: ", ")
            lines.append("User's calendars: \(names)")
        }

        if let before = context.textBefore.nonEmpty {
            lines.append("")
            lines.append("CONTEXT BEFORE THE SELECTION:")
            lines.append(tail(before, maxLength: budget.contextBefore))
        }

        lines.append("")
        lines.append("SELECTED TEXT:")
        lines.append(truncate(context.selection.trimmingCharacters(in: .whitespacesAndNewlines), to: budget.selection))

        if let after = context.textAfter.nonEmpty {
            lines.append("")
            lines.append("CONTEXT AFTER THE SELECTION:")
            lines.append(truncate(after, to: budget.contextAfter))
        }

        lines.append("")
        lines.append("Extract the calendar events from the SELECTED TEXT.")
        return lines.joined(separator: "\n")
    }

    /// Keeps the start of `text`, cut at a word boundary.
    static func truncate(_ text: String, to maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let prefix = text.prefix(maxLength)
        let cut = prefix.lastIndex(where: \.isWhitespace) ?? prefix.endIndex
        return String(prefix[..<cut]) + " …"
    }

    /// Keeps the end of `text` (the part nearest the selection), cut at a word boundary.
    static func tail(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let suffix = text.suffix(maxLength)
        let cut = suffix.firstIndex(where: \.isWhitespace).map { suffix.index(after: $0) } ?? suffix.startIndex
        return "… " + String(suffix[cut...])
    }
}
