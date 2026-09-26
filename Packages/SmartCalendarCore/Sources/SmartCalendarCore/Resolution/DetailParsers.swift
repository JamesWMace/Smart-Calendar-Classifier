import Foundation

/// Details read straight from the event's text instead of asking the model for them.
public enum DetailParsers {
    private static let numberWords: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "half an": 0.5, "half a": 0.5,
    ]

    private static func number(_ text: Substring) -> Double? {
        Double(text) ?? numberWords[String(text)]
    }

    private static func minutes(_ amount: Double, unit: Substring) -> Int {
        let multiplier: Double = switch unit.first {
        case "h": 60
        case "d": 1_440
        case "w": 10_080
        default: 1
        }
        return Int((amount * multiplier).rounded())
    }

    /// "2-hour workshop", "90 minute session", "for an hour", "1.5 hrs" → minutes. Offsets
    /// ("2 hours before", "in 3 hours", "every hour") are not durations.
    public static func durationMinutes(in text: String) -> Int? {
        let pattern = /\b(in|every|within)?\s*(half an?|\d+(?:\.\d+)?|an?|one|two|three|four|five|six)\s*-?\s*(hours?|hrs?|minutes?|mins?)\b(\s+(?:before|prior|early|ahead|beforehand|in advance))?/
        for match in text.lowercased().matches(of: pattern) where match.1 == nil && match.4 == nil {
            if let amount = number(match.2), amount > 0 { return minutes(amount, unit: match.3) }
        }
        return nil
    }

    /// "remind me 30 minutes before", "Reminder: 1 day before", "alert 2 hours ahead" → minutes.
    public static func alertMinutes(in text: String) -> [Int] {
        // The clause that asks for a reminder, then every "<n> <unit> before" inside it.
        let clauses = text.lowercased().matches(of: /\b(?:remind|reminder|reminders|alert|notify)\b[^.\n]*/)
        let offset = /\b(half an?|\d+(?:\.\d+)?|an?|one|two|three|four|five|six)\s*-?\s*(minutes?|mins?|hours?|hrs?|days?|weeks?)\s+(?:before|prior|ahead|early|beforehand|in advance)/
        return clauses.flatMap { clause in
            clause.output.matches(of: offset).compactMap { match in number(match.1).map { minutes($0, unit: match.2) } }
        }
    }

    /// The link on the event's own line, or the only link in the whole selection.
    public static func link(inLine line: String, selection: String) -> URL? {
        let onLine = links(in: line)
        if let first = onLine.first { return first }
        let all = links(in: selection)
        return all.count == 1 ? all[0] : nil
    }

    private static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap(\.url)
            .filter { $0.scheme == "http" || $0.scheme == "https" }
    }
}

extension TimePhraseParser {
    /// Settles times written without am/pm ("at 7", "9:30-11"): words nearby decide
    /// ("dinner", "evening", "tonight" → PM; "morning", "breakfast" → AM); otherwise 1–7 is
    /// PM and 8–11 is AM, the way Calendar reads them.
    public static func resolvingAmbiguity(_ result: Result, hints: String) -> Result {
        guard result.isAmbiguous else { return result }
        let text = hints.lowercased()
        let afternoon: Bool
        if text.contains(/\b(evening|tonight|night|dinner|supper|afternoon)\b|\d\s*p\.?m\b/) {
            afternoon = true
        } else if text.contains(/\b(morning|breakfast)\b|\d\s*a\.?m\b/) {
            afternoon = false
        } else {
            afternoon = (1...7).contains(result.start.hour)
        }
        guard afternoon, result.start.hour < 12 else { return Result(start: result.start, end: result.end, isAmbiguous: false) }
        // "7-9" at dinner is 7–9 PM: the end moves with the start.
        let end = result.end.map { $0.hour < 12 ? TimeSpec(hour: $0.hour + 12, minute: $0.minute) : $0 }
        return Result(start: TimeSpec(hour: result.start.hour + 12, minute: result.start.minute), end: end, isAmbiguous: false)
    }
}
