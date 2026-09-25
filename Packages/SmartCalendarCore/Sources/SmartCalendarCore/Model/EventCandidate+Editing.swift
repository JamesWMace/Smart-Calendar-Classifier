import Foundation

/// Edits made in the preview panel. Each keeps the event consistent the way Calendar does:
/// moving the day keeps the times and length, moving the start keeps the length, and so on.
extension EventCandidate {
    /// Sets the (first) day, keeping the time of day and the length. When the day was missing,
    /// a time the text stated without a day ("call at 3pm") is applied now.
    public mutating func setDay(_ day: Date, calendar: Calendar, defaultDuration: TimeInterval) {
        let newDay = calendar.startOfDay(for: day)
        guard let start else {
            if isAllDay {
                start = newDay
                end = newDay
            } else if let hint = startTimeHint, let hour = hint.hour {
                var zoned = calendar
                zoned.timeZone = hint.timeZone ?? calendar.timeZone
                var components = calendar.dateComponents([.year, .month, .day], from: newDay)
                components.hour = hour
                components.minute = hint.minute ?? 0
                let begin = zoned.date(from: components) ?? newDay
                start = begin
                end = begin.addingTimeInterval(defaultDuration)
                endIsAssumed = true
                startTimeMissing = false
                startTimeHint = nil
            } else {
                start = newDay
                startTimeMissing = true
            }
            return
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: newDay).day ?? 0
        self.start = calendar.date(byAdding: .day, value: days, to: start)
        end = end.flatMap { calendar.date(byAdding: .day, value: days, to: $0) }
    }

    /// Sets the start's time of day on its current day, keeping the length (or using the
    /// default length when there was no real end yet).
    public mutating func setStartTime(_ time: Date, calendar: Calendar, defaultDuration: TimeInterval) {
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        guard let start else {
            startTimeHint = DateComponents(timeZone: calendar.timeZone, hour: clock.hour, minute: clock.minute)
            return
        }
        let length = !startTimeMissing && !isAllDay ? end.map { $0.timeIntervalSince(start) }.flatMap { $0 > 0 ? $0 : nil } : nil
        let newStart = calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: start) ?? start
        self.start = newStart
        end = newStart.addingTimeInterval(length ?? defaultDuration)
        if length == nil { endIsAssumed = true }
        isAllDay = false
        startTimeMissing = false
    }

    /// Sets the end's time of day, on the start's day or — if earlier than the start — the next.
    public mutating func setEndTime(_ time: Date, calendar: Calendar) {
        guard let start, !startTimeMissing else { return }
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        let endDay = end.map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: start)
        var newEnd = calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: endDay) ?? start
        if newEnd <= start {
            newEnd = calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: start) ?? start
            if newEnd <= start { newEnd = calendar.date(byAdding: .day, value: 1, to: newEnd)! }
        }
        end = newEnd
        endIsAssumed = false
    }

    /// The last day of an all-day event (never before the first).
    public mutating func setLastDay(_ day: Date, calendar: Calendar) {
        guard let start, isAllDay else { return }
        end = max(calendar.startOfDay(for: day), calendar.startOfDay(for: start))
    }

    public mutating func setAllDay(_ allDay: Bool, calendar: Calendar) {
        guard allDay != isAllDay else { return }
        isAllDay = allDay
        guard let start else { return }
        if allDay {
            self.start = calendar.startOfDay(for: start)
            end = calendar.startOfDay(for: end ?? start)
            startTimeMissing = false
            endIsAssumed = false
        } else {
            // Back to a timed event: the day stays, the time must be chosen.
            self.start = calendar.startOfDay(for: start)
            end = nil
            startTimeMissing = true
        }
    }
}
