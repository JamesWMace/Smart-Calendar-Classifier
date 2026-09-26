import Foundation

/// Picks the calendar a new event belongs in by comparing it with what the user already keeps
/// in each calendar — "CS 153 Midterm" goes where the "CS 153 Lecture"s are — and with where
/// events from the same app went before. Much better informed than the model, which only sees
/// calendar names. Entirely local.
public struct CalendarClassifier: Sendable {
    public struct Example: Sendable {
        public var calendarID: String
        public var text: String
        /// The app the event's text came from, when known (from history).
        public var source: String?

        public init(calendarID: String, text: String, source: String? = nil) {
            self.calendarID = calendarID
            self.text = text
            self.source = source
        }
    }

    public struct Match: Sendable, Equatable {
        public var calendarID: String
        public var score: Double
    }

    /// Minimum evidence, and how far ahead of the runner-up the winner must be.
    static let minimumScore = 0.6
    static let minimumLead = 1.5

    private let counts: [String: [String: Int]]
    private let documentFrequency: [String: Int]

    public init(examples: [Example]) {
        var counts: [String: [String: Int]] = [:]
        for example in examples {
            for token in Self.tokens(example.text, source: example.source) {
                counts[example.calendarID, default: [:]][token, default: 0] += 1
            }
        }
        self.counts = counts
        documentFrequency = counts.values.reduce(into: [:]) { frequency, tokens in
            for token in tokens.keys { frequency[token, default: 0] += 1 }
        }
    }

    public var isEmpty: Bool { counts.isEmpty }

    /// The best calendar for an event, or nil when the evidence isn't clear.
    public func classify(_ text: String, source: String? = nil) -> Match? {
        let query = Self.tokens(text, source: source)
        guard !query.isEmpty, counts.count > 1 else { return nil }
        let calendars = Double(counts.count)
        let scores = counts.map { calendarID, tokens in
            let score = query.reduce(0.0) { total, token in
                guard let count = tokens[token] else { return total }
                // Words found in fewer calendars say more; the first occurrence counts most.
                let idf = log((calendars + 1) / (Double(documentFrequency[token] ?? 0) + 0.5))
                return total + idf * (1 - exp(-Double(count)))
            }
            return Match(calendarID: calendarID, score: score)
        }.sorted { $0.score > $1.score }

        guard let best = scores.first, best.score >= Self.minimumScore else { return nil }
        let runnerUp = scores.dropFirst().first?.score ?? 0
        return best.score >= runnerUp * Self.minimumLead ? best : nil
    }

    private static let ignored: Set<String> = [
        "the", "and", "for", "with", "from", "this", "that", "are", "was", "will", "have", "has", "into", "about", "your",
        "you", "our", "all", "new", "via", "per", "day", "days", "due", "event", "events", "untitled",
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
        "january", "february", "march", "april", "june", "july", "august", "september", "october", "november", "december",
        "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat", "sun",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "today", "tomorrow",
    ]

    /// Letters that precede numbers without making a course code ("Oct 15", "at 10").
    private static let notCodes = ignored.union(["at", "on", "in", "to", "by", "am", "pm", "and", "or", "of", "rm", "no", "ext", "suite"])

    /// Distinct meaningful words, course-style codes ("CS 153" → "cs153"), and the source app.
    static func tokens(_ text: String, source: String? = nil) -> Set<String> {
        let lower = text.lowercased()
        var tokens = Set(lower.matches(of: /[a-z]{3,}/).map { String($0.output) }.filter { !ignored.contains($0) })
        for code in lower.matches(of: /\b([a-z]{2,5})\s?-?(\d{2,4}[a-z]?)\b/) where !notCodes.contains(String(code.1)) {
            tokens.insert(String(code.1) + String(code.2))
        }
        if let source, !source.isEmpty {
            tokens.insert("app:" + source.lowercased())
        }
        return tokens
    }
}
