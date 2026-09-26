import Foundation

/// Parses short English time phrases — "3pm", "3-5pm", "9:30am–12pm", "11-1pm", "noon",
/// "at 7", "14:00" — into start and optional end times.
public enum TimePhraseParser {
    public struct Result: Sendable, Equatable {
        public var start: TimeSpec
        public var end: TimeSpec?
        /// True when the start has no am/pm and could be either ("at 7", "9:30"). The
        /// model's own reading, which sees the context, should win in that case.
        public var isAmbiguous: Bool
    }

    public static func parse(_ phrase: String) -> Result? {
        let text = normalize(phrase)
        guard !text.isEmpty else { return nil }
        return range(in: text) ?? single(in: text)
    }

    /// Whether the phrase talks about a time of day at all ("7", "noon", "this evening",
    /// "after lunch") as opposed to filler like "unknown" or "TBD".
    public static func mentionsTime(_ phrase: String) -> Bool {
        let text = phrase.lowercased()
        return text.contains(/\d/)
            || text.contains(/\b(noon|midnight|morning|afternoon|evening|night|tonight|lunch|dinner|breakfast|brunch)\b/)
    }

    static func normalize(_ phrase: String) -> String {
        phrase.lowercased()
            .replacingOccurrences(of: "a.m.", with: "am")
            .replacingOccurrences(of: "p.m.", with: "pm")
            .replacingOccurrences(of: "a.m", with: "am")
            .replacingOccurrences(of: "p.m", with: "pm")
            .replacingOccurrences(of: "noon", with: "12:00pm")
            .replacingOccurrences(of: "midnight", with: "12:00am")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
    }

    private enum Meridiem: Equatable {
        case am, pm
        init?(_ text: Substring?) {
            switch text { case "am"?: self = .am; case "pm"?: self = .pm; default: return nil }
        }
        var opposite: Meridiem { self == .am ? .pm : .am }
    }

    /// "3-5pm", "9:30am-12pm", "11-1pm", "14:00 to 16:00"
    private static func range(in text: String) -> Result? {
        let pattern = /\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:-|to|until|till)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b/
        guard let m = text.firstMatch(of: pattern),
              var startHour = Int(m.1), var endHour = Int(m.4) else { return nil }
        let startMinute = m.2.flatMap { Int($0) } ?? 0
        let endMinute = m.5.flatMap { Int($0) } ?? 0
        let startMeridiem = Meridiem(m.3), endMeridiem = Meridiem(m.6)
        // Without an am/pm or a colon this is probably a date range ("Oct 3-5"), not times.
        guard startMeridiem != nil || endMeridiem != nil || m.2 != nil || m.5 != nil else { return nil }
        guard (0...23).contains(startHour), (0...23).contains(endHour),
              (0...59).contains(startMinute), (0...59).contains(endMinute) else { return nil }

        var ambiguous = false
        switch (startMeridiem, endMeridiem) {
        case let (s?, e?):
            startHour = to24(startHour, s)
            endHour = to24(endHour, e)
        case let (nil, e?):
            // "3-5pm" → both pm; "11-1pm" → 11am because 11pm would come after 1pm.
            let sameHalf = to24(startHour, e)
            endHour = to24(endHour, e)
            startHour = startHour <= 12 && sameHalf > endHour ? to24(startHour, e.opposite) : sameHalf
        case let (s?, nil):
            startHour = to24(startHour, s)
            let sameHalf = to24(endHour, s)
            endHour = endHour <= 12 && sameHalf <= startHour ? to24(endHour, s.opposite) : sameHalf
        case (nil, nil):
            ambiguous = (1...11).contains(startHour)
            if endHour < startHour && endHour < 12 { endHour += 12 }
        }
        return Result(
            start: TimeSpec(hour: startHour, minute: startMinute),
            end: TimeSpec(hour: endHour, minute: endMinute),
            isAmbiguous: ambiguous
        )
    }

    /// "3pm", "11:59 pm", "14:00", "at 7"; two separate times ("10am … Sunday at 4pm") are a
    /// start and an end.
    private static func single(in text: String) -> Result? {
        let explicit = text.matches(of: /\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b/).compactMap { m -> TimeSpec? in
            guard let hour = Int(m.1), (1...12).contains(hour), let meridiem = Meridiem(m.3) else { return nil }
            let minute = m.2.flatMap { Int($0) } ?? 0
            return (0...59).contains(minute) ? TimeSpec(hour: to24(hour, meridiem), minute: minute) : nil
        }
        if let first = explicit.first {
            return Result(start: first, end: explicit.count > 1 ? explicit.last : nil, isAmbiguous: false)
        }
        if let m = text.firstMatch(of: /\b(\d{1,2}):(\d{2})\b/),
           let hour = Int(m.1), let minute = Int(m.2), (0...23).contains(hour), (0...59).contains(minute) {
            return Result(start: TimeSpec(hour: hour, minute: minute), end: nil, isAmbiguous: (1...11).contains(hour))
        }
        if let m = text.firstMatch(of: /\b(?:at|@)\s*(\d{1,2})\b/), let hour = Int(m.1), (0...23).contains(hour) {
            return Result(start: TimeSpec(hour: hour), end: nil, isAmbiguous: (1...11).contains(hour))
        }
        return nil
    }

    private static func to24(_ hour: Int, _ meridiem: Meridiem) -> Int {
        switch (meridiem, hour) {
        case (.am, 12): 0
        case (.pm, 1...11): hour + 12
        default: hour
        }
    }
}
