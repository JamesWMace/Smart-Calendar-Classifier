import EventKit
import Foundation

public enum EventMappingError: Error, Equatable, LocalizedError {
    case incomplete(Set<EventCandidate.Field>)

    public var errorDescription: String? {
        switch self {
        case .incomplete: "The event still needs a title, date or start time."
        }
    }
}

/// Turns a complete `EventCandidate` into an `EKEvent`. Pure apart from EventKit object
/// creation, which needs no calendar permission, so it is unit-testable.
public enum EventMapper {
    /// - Parameters:
    ///   - defaultAlertMinutes: reminders to add when the text asked for none.
    ///   - timeZone: the user's zone; timed events are pinned to it, all-day events float.
    public static func makeEvent(
        from candidate: EventCandidate,
        in store: EKEventStore,
        calendar: EKCalendar?,
        defaultAlertMinutes: [Int] = [],
        timeZone: TimeZone = .current
    ) throws -> EKEvent {
        guard candidate.isComplete, let start = candidate.start else {
            throw EventMappingError.incomplete(candidate.missingFields)
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.location = candidate.location
        event.url = candidate.url
        event.notes = candidate.notes.isEmpty ? nil : candidate.notes

        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        if candidate.isAllDay {
            event.isAllDay = true
            event.timeZone = nil
            let firstDay = gregorian.startOfDay(for: start)
            let lastDay = gregorian.startOfDay(for: max(candidate.end ?? start, start))
            event.startDate = firstDay
            // EventKit stores an all-day event's end as the last moment of its final day.
            event.endDate = gregorian.date(byAdding: DateComponents(day: 1, second: -1), to: lastDay)!
        } else {
            event.isAllDay = false
            event.timeZone = timeZone
            event.startDate = start
            event.endDate = max(candidate.end ?? start.addingTimeInterval(3_600), start)
        }

        let alerts = candidate.alertMinutesBefore.isEmpty ? defaultAlertMinutes : candidate.alertMinutesBefore
        for minutes in Set(alerts).sorted() {
            event.addAlarm(EKAlarm(relativeOffset: -TimeInterval(minutes * 60)))
        }

        if let recurrence = candidate.recurrence {
            event.recurrenceRules = [rule(for: recurrence, calendar: gregorian)]
        }
        return event
    }

    static func rule(for recurrence: Recurrence, calendar: Calendar) -> EKRecurrenceRule {
        let frequency: EKRecurrenceFrequency = switch recurrence.frequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
        let days = recurrence.frequency == .weekly
            ? recurrence.weekdays.compactMap { EKWeekday(rawValue: $0).map(EKRecurrenceDayOfWeek.init) }
            : []
        let end: EKRecurrenceEnd? = if let until = recurrence.until {
            // "until Dec 4" includes Dec 4.
            EKRecurrenceEnd(end: calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: until))!)
        } else if let count = recurrence.occurrenceCount {
            EKRecurrenceEnd(occurrenceCount: count)
        } else {
            nil
        }
        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: max(1, recurrence.interval),
            daysOfTheWeek: days.isEmpty ? nil : days,
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: end
        )
    }
}
