import Foundation

/// Fallback used when Apple Intelligence is unavailable: finds the first date in the selection
/// with `NSDataDetector` and makes a best-effort title from the surrounding words.
///
/// `NSDataDetector` always resolves relative dates against the real current date, so this
/// ignores `context.referenceDate`.
public struct DataDetectorExtractor: Sendable {
    public init() {}

    private static var explicitTime: some RegexComponent { /(?i)\b\d{1,2}(:\d{2})?\s*(a\.?m\.?|p\.?m\.?)|\b\d{1,2}:\d{2}\b|\bnoon\b|\bmidnight\b/ }

    public func extract(from context: CaptureContext, options: ResolutionOptions = .init()) -> [EventCandidate] {
        let text = context.selection
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return [] }
        let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = context.timeZone

        var candidate = EventCandidate(title: Self.title(from: text, removing: match), isAllDay: false, start: nil, end: nil)

        if let match, let date = match.date, let range = Range(match.range, in: text) {
            let hasTime = text[range].contains(Self.explicitTime)
            if hasTime {
                candidate.start = date
                if match.duration > 0 {
                    candidate.end = date.addingTimeInterval(match.duration)
                } else {
                    candidate.end = date.addingTimeInterval(TimeInterval(options.defaultDurationMinutes * 60))
                    candidate.endIsAssumed = true
                }
                if let zone = match.timeZone, zone.secondsFromGMT(for: date) != context.timeZone.secondsFromGMT(for: date) {
                    candidate.sourceTimeZone = zone
                }
            } else {
                candidate.start = calendar.startOfDay(for: date)
                candidate.startTimeMissing = true
            }
        } else {
            candidate.startTimeMissing = true
        }

        candidate.notes = NotesComposer.compose(
            summary: "", context: context, sourceTimeZone: candidate.sourceTimeZone, start: candidate.start
        )
        return [candidate]
    }

    /// The first line of the selection with the date phrase removed, capped at ~8 words.
    static func title(from text: String, removing match: NSTextCheckingResult?) -> String {
        var text = text
        if let match, let range = Range(match.range, in: text) {
            text.replaceSubrange(range, with: " ")
        }
        let firstLine = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let words = firstLine.split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "#&"))) }
            .filter { !$0.isEmpty && !["on", "at", "from", "by", "-", "–"].contains($0.lowercased()) }
        return words.prefix(8).joined(separator: " ")
    }
}
