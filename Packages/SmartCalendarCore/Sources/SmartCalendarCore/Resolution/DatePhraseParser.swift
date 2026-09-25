import Foundation

/// Parses short English date phrases picked out by the model — "next Tuesday", "Oct 15, 2026",
/// "10/05", "the 14th", "October 20–22", "Saturday to Sunday" — into `DateSpec`s.
///
/// The phrase may carry extra words ("on Thursday, Oct 15 at 3pm"); patterns are tried from
/// most to least specific, so an explicit month and day beats a weekday name.
public enum DatePhraseParser {
    public struct Result: Sendable, Equatable {
        public var start: DateSpec
        /// Set when the phrase itself is a range, like "October 20–22".
        public var end: DateSpec?
    }

    /// - Parameter defaultMonth: month to assume for a bare day number, as in the "22" of
    ///   "Oct 20–22" or an end-date phrase of just "22".
    public static func parse(_ phrase: String, defaultMonth: Int? = nil) -> Result? {
        let text = normalize(phrase)
        guard !text.isEmpty, let (start, range) = firstDate(in: text, defaultMonth: defaultMonth, anchored: false) else {
            return nil
        }
        var end: DateSpec?
        let rest = text[range.upperBound...]
        if let separator = rest.prefixMatch(of: /\s*(?:-|to|through|thru|until|till)\s*/) {
            let remainder = String(rest[separator.range.upperBound...])
            end = firstDate(in: remainder, defaultMonth: start.month ?? defaultMonth, anchored: true)?.0
        }
        return Result(start: start, end: end)
    }

    static func normalize(_ phrase: String) -> String {
        phrase.lowercased()
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private typealias Matcher = @Sendable (String, Int?) -> (DateSpec, Range<String.Index>)?

    private static let matchers: [Matcher] = [iso, slashed, monthDay, dayMonth, relative, weekday, ordinalDay, bareDay]

    private static func firstDate(in text: String, defaultMonth: Int?, anchored: Bool) -> (DateSpec, Range<String.Index>)? {
        for matcher in matchers {
            guard let (spec, range) = matcher(text, defaultMonth) else { continue }
            if anchored && range.lowerBound != text.startIndex { continue }
            return (spec, range)
        }
        return nil
    }

    // MARK: - Patterns

    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    private static func month(_ name: Substring) -> Int? {
        months.firstIndex(of: String(name.prefix(3))).map { $0 + 1 }
    }

    private static func year(_ text: Substring?) -> Int? {
        guard let text, let value = Int(text) else { return nil }
        return value < 100 ? 2000 + value : value
    }

    /// 2026-10-05
    private static func iso(_ text: String, _: Int?) -> (DateSpec, Range<String.Index>)? {
        guard let m = text.firstMatch(of: /\b(\d{4})-(\d{1,2})-(\d{1,2})\b/),
              let y = Int(m.1), let mo = Int(m.2), let d = Int(m.3) else { return nil }
        return (DateSpec(kind: .absolute, year: y, month: mo, day: d), m.range)
    }

    /// 10/5, 10/05/2026, 10/5/26 (US order)
    private static func slashed(_ text: String, _: Int?) -> (DateSpec, Range<String.Index>)? {
        guard let m = text.firstMatch(of: /\b(\d{1,2})\/(\d{1,2})(?:\/(\d{2}|\d{4}))?\b/),
              let mo = Int(m.1), let d = Int(m.2), (1...12).contains(mo) else { return nil }
        return (DateSpec(kind: .absolute, year: year(m.3), month: mo, day: d), m.range)
    }

    /// October 20, Oct. 20th, Oct 20 2026, Oct 20, 2026
    private static func monthDay(_ text: String, _: Int?) -> (DateSpec, Range<String.Index>)? {
        let pattern = /\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b(?:,?\s+(\d{4})\b)?/
        guard let m = text.firstMatch(of: pattern), let mo = month(m.1), let d = Int(m.2) else { return nil }
        return (DateSpec(kind: .absolute, year: year(m.3), month: mo, day: d), m.range)
    }

    /// 20 October, the 20th of October 2026
    private static func dayMonth(_ text: String, _: Int?) -> (DateSpec, Range<String.Index>)? {
        let pattern = /\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b(?:,?\s+(\d{4})\b)?/
        guard let m = text.firstMatch(of: pattern), let mo = month(m.2), let d = Int(m.1) else { return nil }
        return (DateSpec(kind: .absolute, year: year(m.3), month: mo, day: d), m.range)
    }

    private static let numberWords = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
                                      "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10]

    /// today, tonight, tomorrow, day after tomorrow, in 3 days, in two weeks
    private static func relative(_ text: String, _: Int?) -> (DateSpec, Range<String.Index>)? {
        if let m = text.firstMatch(of: /\bday after tomorrow\b/) {
            return (DateSpec(kind: .relative, daysFromToday: 2), m.range)
        }
        if let m = text.firstMatch(of: /\b(?:tomorrow|tmrw|tmr)\b/) {
            return (DateSpec(kind: .relative, daysFromToday: 1), m.range)
        }
        if let m = text.firstMatch(of: /\b(?:today|tonight|this (?:morning|afternoon|evening))\b/) {
            return (DateSpec(kind: .relative, daysFromToday: 0), m.range)
        }
        if let m = text.firstMatch(of: /\bin\s+(\d+|an?|one|two|three|four|five|six|seven|eight|nine|ten)\s+(day|week)s?\b/) {
            guard let n = Int(m.1) ?? numberWords[String(m.1)] else { return nil }
            return (DateSpec(kind: .relative, daysFromToday: m.2 == "week" ? n * 7 : n), m.range)
        }
        return nil
    }

    private static let weekdayNames: [(String, Weekday)] = [
        ("mon", .monday), ("tue", .tuesday), ("wed", .wednesday), ("thu", .thursday),
        ("fri", .friday), ("sat", .saturday), ("sun", .sunday),
    ]

    /// Tuesday, this Tue, next Friday, Friday after next
    private static func weekday(_ text: String, _: Int?) -> (DateSpec, Range<String.Index>)? {
        let pattern = /\b(?:(this|next|coming|following)\s+)?(monday|mon|tuesday|tues|tue|wednesday|wed|thursday|thurs|thur|thu|friday|fri|saturday|sat|sunday|sun)s?\b(\s+after\s+next)?/
        guard let m = text.firstMatch(of: pattern),
              let weekday = weekdayNames.first(where: { m.2.hasPrefix($0.0) })?.1 else { return nil }
        let weeksAhead = m.3 != nil ? 2 : (m.1 == "next" || m.1 == "following") ? 1 : 0
        return (DateSpec(kind: .weekday, weekday: weekday, weeksAhead: weeksAhead), m.range)
    }

    /// the 14th
    private static func ordinalDay(_ text: String, _ defaultMonth: Int?) -> (DateSpec, Range<String.Index>)? {
        guard let m = text.firstMatch(of: /\b(\d{1,2})(?:st|nd|rd|th)\b/), let d = Int(m.1) else { return nil }
        return (DateSpec(kind: .absolute, month: defaultMonth, day: d), m.range)
    }

    /// "22" — only meaningful when a month is already known, as in the end of "Oct 20-22".
    private static func bareDay(_ text: String, _ defaultMonth: Int?) -> (DateSpec, Range<String.Index>)? {
        guard let defaultMonth, let m = text.prefixMatch(of: /(\d{1,2})\b(?!:|\s*[ap]\.?m)/), let d = Int(m.1),
              (1...31).contains(d) else { return nil }
        return (DateSpec(kind: .absolute, month: defaultMonth, day: d), m.range)
    }
}
