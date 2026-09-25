import Foundation

public struct ResolutionOptions: Sendable, Equatable {
    /// Used for the end time when the text gives neither an end nor a duration.
    public var defaultDurationMinutes: Int

    public init(defaultDurationMinutes: Int = 60) {
        self.defaultDurationMinutes = defaultDurationMinutes
    }
}

/// Assembles an `EventCandidate` from what the model extracted plus the capture context.
/// All times are converted into the user's local zone (decision #8).
public struct EventResolver: Sendable {
    public let context: CaptureContext
    public let options: ResolutionOptions
    private let dates: DateResolver
    /// Everything the user could see; locations and links must appear in it.
    private let sourceText: String

    public init(context: CaptureContext, options: ResolutionOptions = .init()) {
        self.context = context
        self.options = options
        self.dates = DateResolver(referenceDate: context.referenceDate, timeZone: context.timeZone)
        self.sourceText = [context.windowTitle, context.textBefore, context.selection, context.textAfter]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    /// Resolves every event, dropping exact duplicates (the model occasionally repeats one).
    public func resolveAll(_ events: [ExtractedEvent]) -> [EventCandidate] {
        var seen: [EventCandidate] = []
        for candidate in events.map(resolve) {
            let isDuplicate = seen.contains {
                $0.title.caseInsensitiveCompare(candidate.title) == .orderedSame
                    && $0.start == candidate.start && $0.end == candidate.end
            }
            if !isDuplicate { seen.append(candidate) }
        }
        return seen
    }

    public func resolve(_ event: ExtractedEvent) -> EventCandidate {
        let statedZone = TimeZoneResolver.resolve(event.timeZone)
        let eventZone = statedZone ?? context.timeZone
        let (startDay, endDay) = days(for: event)
        let (startTime, endTime) = times(for: event)

        let isMultiDay = startDay != nil && endDay != nil && endDay! > startDay!
        let isAllDay = event.timing == .allDay && (startTime == nil || isMultiDay)

        let (location, locationURL) = groundedLocation(event.location)
        var candidate = EventCandidate(
            title: event.title.trimmingCharacters(in: .whitespacesAndNewlines),
            isAllDay: isAllDay,
            start: nil,
            end: nil,
            location: location,
            url: groundedURL(event.url) ?? locationURL,
            recurrence: recurrence(from: event.recurrence),
            alertMinutesBefore: event.alertMinutesBefore.filter { (0...40_320).contains($0) },
            suggestedCalendarName: matchCalendar(event.suggestedCalendar, title: event.title)
        )

        if isAllDay {
            candidate.start = startDay
            candidate.end = endDay ?? startDay
        } else if let startDay, let startTime {
            let start = instant(on: startDay, at: startTime, in: eventZone)
            candidate.start = start
            candidate.end = end(for: event, endTime: endTime, start: start, startDay: startDay, endDay: endDay,
                                zone: eventZone, assumed: &candidate.endIsAssumed)
            if let statedZone, statedZone.secondsFromGMT(for: start) != context.timeZone.secondsFromGMT(for: start) {
                candidate.sourceTimeZone = statedZone
            }
        } else if let startDay {
            // A day but no time: keep the day, make the user enter the time (decision #7).
            candidate.start = startDay
            candidate.startTimeMissing = true
        } else if let startTime {
            // A time but no day: remember the time for when the user picks the day.
            candidate.startTimeHint = DateComponents(timeZone: eventZone, hour: startTime.hour, minute: startTime.minute)
            candidate.sourceTimeZone = statedZone
        } else {
            candidate.startTimeMissing = true
        }

        candidate.notes = NotesComposer.compose(
            summary: event.summary,
            context: context,
            sourceTimeZone: candidate.sourceTimeZone,
            start: candidate.start
        )
        return candidate
    }

    // MARK: - Dates and times

    private func days(for event: ExtractedEvent) -> (start: Date?, end: Date?) {
        let calendar = dates.calendar
        let parsed = DatePhraseParser.parse(event.startDatePhrase)
        guard let startDay = parsed.flatMap({ dates.day(for: $0.start) }) else { return (nil, nil) }

        let startMonth = calendar.component(.month, from: startDay)
        let endSpec = DatePhraseParser.parse(event.endDatePhrase, defaultMonth: startMonth)?.start ?? parsed?.end
        guard let endSpec, var endDay = dates.day(for: endSpec) else { return (startDay, nil) }

        // "Dec 28 – Jan 3" or "Friday – Monday": an end that lands before the start means the
        // next one — but only when that makes a short range, not a year-long event.
        var rolled = false
        if endDay < startDay {
            switch endSpec.kind {
            case .absolute where endSpec.year == nil:
                endDay = calendar.date(byAdding: endSpec.month == nil ? .month : .year, value: 1, to: endDay)!
                rolled = true
            case .weekday:
                endDay = calendar.date(byAdding: .day, value: 7, to: endDay)!
            default:
                break
            }
        }
        // A misread end (e.g. a time taken for a day) must never stretch the event absurdly.
        let span = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        let maxSpan = rolled ? Self.maxRolledSpanDays : event.timing == .allDay ? Self.maxAllDaySpanDays : Self.maxTimedSpanDays
        return (startDay, (0...maxSpan).contains(span) ? endDay : nil)
    }

    /// Longest believable events, in days: a timed event (a hackathon, an overnight trip), an
    /// all-day range (a term, a long trip), and a range whose end had to be moved to next year.
    static let maxTimedSpanDays = 7
    static let maxAllDaySpanDays = 180
    static let maxRolledSpanDays = 62

    /// The parsed phrase wins unless it is ambiguous ("at 7"), in which case the model's
    /// reading — which saw the context — is used. With no time words at all, the model's
    /// structured time is ignored: it tends to invent midnight.
    private func times(for event: ExtractedEvent) -> (start: TimeSpec?, end: TimeSpec?) {
        let parsed = TimePhraseParser.parse(event.timePhrase) ?? TimePhraseParser.parse(event.startDatePhrase)
        guard let parsed else {
            return TimePhraseParser.mentionsTime(event.timePhrase) ? (event.startTime, event.endTime) : (nil, nil)
        }
        if parsed.isAmbiguous, let modelStart = event.startTime {
            return (modelStart, event.endTime ?? parsed.end)
        }
        return (parsed.start, parsed.end ?? event.endTime)
    }

    private func end(
        for event: ExtractedEvent, endTime: TimeSpec?, start: Date, startDay: Date, endDay: Date?, zone: TimeZone,
        assumed: inout Bool
    ) -> Date {
        if let endTime {
            var end = instant(on: endDay ?? startDay, at: endTime, in: zone)
            if end <= start && endDay == nil {
                end = dates.calendar.date(byAdding: .day, value: 1, to: end)! // "10pm–2am"
            }
            if end > start { return end }
        }
        if let minutes = event.durationMinutes, minutes > 0 {
            return start.addingTimeInterval(TimeInterval(minutes * 60))
        }
        assumed = true
        return start.addingTimeInterval(TimeInterval(options.defaultDurationMinutes * 60))
    }

    /// `day` is a local midnight; its calendar date is combined with `time` as read in `zone`.
    private func instant(on day: Date, at time: TimeSpec, in zone: TimeZone) -> Date {
        let ymd = dates.calendar.dateComponents([.year, .month, .day], from: day)
        var zoned = Calendar(identifier: .gregorian)
        zoned.timeZone = zone
        let components = DateComponents(year: ymd.year, month: ymd.month, day: ymd.day, hour: time.hour, minute: time.minute)
        return zoned.date(from: components)!
    }

    private func recurrence(from spec: RecurrenceSpec?) -> Recurrence? {
        guard let spec else { return nil }
        let frequency: Recurrence.Frequency = switch spec.frequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
        return Recurrence(
            frequency: frequency,
            interval: max(1, spec.interval),
            weekdays: spec.weekdays.map(\.calendarValue),
            until: DatePhraseParser.parse(spec.untilPhrase).flatMap { dates.day(for: $0.start) },
            occurrenceCount: spec.occurrenceCount.flatMap { $0 > 0 ? $0 : nil }
        )
    }

    // MARK: - Grounding

    /// Drops locations the model made up ("Lunch spot") by requiring them to appear in the
    /// text. A link offered as the location is returned as a URL instead.
    private func groundedLocation(_ text: String?) -> (location: String?, url: URL?) {
        guard var location = text.nonEmpty else { return (nil, nil) }
        if let url = Self.url(from: location), location.contains("://") || location.hasPrefix("www.") {
            return (nil, sourceText.localizedCaseInsensitiveContains(location) ? url : nil)
        }
        for prefix in ["in ", "at ", "@ ", "the "] where location.lowercased().hasPrefix(prefix) {
            location = String(location.dropFirst(prefix.count))
        }
        return (sourceText.localizedCaseInsensitiveContains(location) ? location : nil, nil)
    }

    private func groundedURL(_ text: String?) -> URL? {
        guard let text = text.nonEmpty, sourceText.localizedCaseInsensitiveContains(text) else { return nil }
        return Self.url(from: text)
    }

    /// A calendar named outright beats the model's semantic guess: "Office Hours" goes to a
    /// calendar called "Office Hours", not to "Class". Any name counts in the title; only
    /// multi-word names count in the selection, so "let's work on it" doesn't mean "Work".
    /// The longest (most specific) match wins.
    private func matchCalendar(_ suggestion: String?, title: String) -> String? {
        let titleWords = Self.words(title)
        let selectionWords = Self.words(context.selection)
        let named = context.calendarNames
            .sorted { $0.count > $1.count }
            .first { name in
                let nameWords = Self.words(name)
                return Self.contains(titleWords, nameWords) || (nameWords.count > 1 && Self.contains(selectionWords, nameWords))
            }
        if let named { return named }
        guard let suggestion = suggestion.nonEmpty else { return nil }
        return context.calendarNames.first { $0.caseInsensitiveCompare(suggestion) == .orderedSame }
    }

    static func words(_ text: String) -> [Substring] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }
    }

    /// Whether `needle` appears in `haystack` as consecutive whole words.
    static func contains(_ haystack: [Substring], _ needle: [Substring]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        return (0...(haystack.count - needle.count)).contains { haystack[$0..<($0 + needle.count)].elementsEqual(needle) }
    }

    static func url(from text: String?) -> URL? {
        guard let text = text.nonEmpty else { return nil }
        let withScheme = text.contains("://") ? text : "https://" + text
        guard let url = URL(string: withScheme), let host = url.host(), host.contains(".") else { return nil }
        return url
    }
}

extension Optional where Wrapped == String {
    /// The trimmed string, or `nil` when absent or blank.
    var nonEmpty: String? {
        guard let trimmed = self?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
