import Foundation
import SmartCalendarCore

/// Human-readable descriptions of events, shared by the preview panel and Try It.
enum EventFormatting {
    static func when(_ candidate: EventCandidate) -> String {
        guard let start = candidate.start else {
            if let hint = candidate.startTimeHint, let hour = hint.hour {
                return String(format: "Date needed · %d:%02d", hour, hint.minute ?? 0)
            }
            return "Date needed"
        }
        if candidate.isAllDay {
            let day = start.formatted(date: .abbreviated, time: .omitted)
            guard let end = candidate.end, !Calendar.current.isDate(end, inSameDayAs: start) else { return "\(day) · all day" }
            return "\(day) – \(end.formatted(date: .abbreviated, time: .omitted)) · all day"
        }
        if candidate.startTimeMissing {
            return "\(start.formatted(date: .complete, time: .omitted)) · time needed"
        }
        var text = start.formatted(date: .complete, time: .shortened)
        if let end = candidate.end {
            let sameDay = Calendar.current.isDate(end, inSameDayAs: start)
            text += " – " + end.formatted(date: sameDay ? .omitted : .abbreviated, time: .shortened)
        }
        return text
    }

    static func list(_ fields: Set<EventCandidate.Field>) -> String {
        let names = fields.map { field in
            switch field {
            case .title: "a title"
            case .date: "a date"
            case .startTime: "a start time"
            }
        }
        return ListFormatter.localizedString(byJoining: names.sorted())
    }

    static func describe(_ recurrence: Recurrence) -> String {
        let unit = switch recurrence.frequency {
        case .daily: "day"
        case .weekly: "week"
        case .monthly: "month"
        case .yearly: "year"
        }
        var text = recurrence.interval == 1 ? "Every \(unit)" : "Every \(recurrence.interval) \(unit)s"
        if !recurrence.weekdays.isEmpty {
            let symbols = Calendar.current.shortWeekdaySymbols
            text += " on " + recurrence.weekdays.map { symbols[$0 - 1] }.joined(separator: ", ")
        }
        if let until = recurrence.until { text += " until " + until.formatted(date: .abbreviated, time: .omitted) }
        if let count = recurrence.occurrenceCount { text += ", \(count) times" }
        return text
    }
}
