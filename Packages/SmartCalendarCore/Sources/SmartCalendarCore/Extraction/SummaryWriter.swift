import Foundation
import FoundationModels

/// Optionally writes a short summary for an event's notes (Settings → "Write a summary in
/// notes"). Kept out of the main extraction, where it cost about a second per event: the
/// events appear first and summaries fill in afterwards.
public struct SummaryWriter: Sendable {
    @Generable
    struct Summary {
        @Guide(description: "One or two plain sentences for the event's calendar notes: what it is and anything the attendee needs to know or bring. Do not repeat the date, time or title.")
        var text: String
    }

    static let instructions = """
        You write short notes for calendar events from the text they were found in. Use only \
        facts from the text. Never invent details.
        """

    public init() {}

    /// A summary of `candidate` drawn from the captured text, or nil if the model had
    /// nothing useful to add.
    public func summary(for candidate: EventCandidate, context: CaptureContext) async throws -> String? {
        let session = LanguageModelSession(instructions: Self.instructions)
        var lines = ["Event: \(candidate.title)"]
        if let location = candidate.location { lines.append("Place: \(location)") }
        if let before = context.textBefore, !before.isEmpty {
            lines += ["", "CONTEXT BEFORE:", PromptBuilder.tail(before, maxLength: 600)]
        }
        lines += ["", "TEXT:", PromptBuilder.truncate(context.selection, to: 2_000)]
        if let after = context.textAfter, !after.isEmpty {
            lines += ["", "CONTEXT AFTER:", PromptBuilder.truncate(after, to: 400)]
        }
        lines += ["", "Write the notes for this event."]

        let response = try await session.respond(
            to: lines.joined(separator: "\n"), generating: Summary.self, options: GenerationOptions(samplingMode: .greedy)
        )
        let text = response.content.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : PromptBuilder.truncate(text, to: 400)
    }
}
