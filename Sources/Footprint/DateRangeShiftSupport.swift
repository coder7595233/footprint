import Foundation

func committedCalendarTimeForRangeShift(_ raw: String?) -> String? {
    let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if trimmed.contains(":") {
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let hourPart = String(parts[0])
        let minutePart = String(parts[1])
        guard (1...2).contains(hourPart.count),
              minutePart.count == 2,
              hourPart.allSatisfy(\.isNumber),
              minutePart.allSatisfy(\.isNumber),
              let hours = Int(hourPart),
              let minutes = Int(minutePart),
              (0..<24).contains(hours),
              (0..<60).contains(minutes) else {
            return nil
        }
        return String(format: "%02d:%02d", hours, minutes)
    }

    guard trimmed.count == 4,
          trimmed.allSatisfy(\.isNumber) else {
        return nil
    }

    let hours = Int(trimmed.prefix(2)) ?? -1
    let minutes = Int(trimmed.suffix(2)) ?? -1
    guard (0..<24).contains(hours),
          (0..<60).contains(minutes) else {
        return nil
    }

    return String(format: "%02d:%02d", hours, minutes)
}

func updatingCommittedTimeRangeEnd(
    previousCommittedStart: String?,
    newInput: String,
    currentEnd: String
) -> (committedStart: String?, shiftedEnd: String?) {
    guard let newCommittedStart = committedCalendarTimeForRangeShift(newInput) else {
        return (previousCommittedStart, nil)
    }
    guard let previousCommittedStart else {
        return (newCommittedStart, nil)
    }
    return (
        newCommittedStart,
        shiftedTimeRangeEnd(
            previousStart: previousCommittedStart,
            newStart: newCommittedStart,
            currentEnd: currentEnd
        )
    )
}

func updatingCommittedDateTimeRangeEnd(
    previousCommittedStartDate: String,
    previousCommittedStartTime: String?,
    newStartDate: String,
    newStartTimeInput: String,
    currentEndDate: String,
    currentEndTime: String,
    calendar: Calendar = .current
) -> (committedStartTime: String?, shiftedEnd: (date: String, time: String)?) {
    guard let newCommittedStartTime = committedCalendarTimeForRangeShift(newStartTimeInput) else {
        return (previousCommittedStartTime, nil)
    }
    guard let previousCommittedStartTime else {
        return (newCommittedStartTime, nil)
    }
    return (
        newCommittedStartTime,
        shiftedDateTimeRangeEnd(
            previousStartDate: previousCommittedStartDate,
            previousStartTime: previousCommittedStartTime,
            newStartDate: newStartDate,
            newStartTime: newCommittedStartTime,
            currentEndDate: currentEndDate,
            currentEndTime: currentEndTime,
            calendar: calendar
        )
    )
}

func shiftedDateRangeEnd(
    previousStart: String,
    newStart: String,
    currentEnd: String,
    calendar: Calendar = .current
) -> String? {
    let normalizedPreviousStart = DateParsers.canonicalizedDayInput(previousStart)
    let normalizedNewStart = DateParsers.canonicalizedDayInput(newStart)
    let normalizedCurrentEnd = DateParsers.canonicalizedDayInput(currentEnd)

    guard let previousStartDate = DateParsers.isoDay.date(from: normalizedPreviousStart),
          let newStartDate = DateParsers.isoDay.date(from: normalizedNewStart),
          let currentEndDate = DateParsers.isoDay.date(from: normalizedCurrentEnd) else {
        return nil
    }

    let dayDelta = calendar.dateComponents([.day], from: previousStartDate, to: newStartDate).day ?? 0
    guard dayDelta != 0,
          let shiftedEndDate = calendar.date(byAdding: .day, value: dayDelta, to: currentEndDate) else {
        return nil
    }

    return DateParsers.isoDay.string(from: shiftedEndDate)
}

func shiftedTimeRangeEnd(previousStart: String, newStart: String, currentEnd: String) -> String? {
    guard let previousStartMinutes = calendarTimeMinutes(previousStart),
          let newStartMinutes = calendarTimeMinutes(newStart),
          let currentEndMinutes = calendarTimeMinutes(currentEnd) else {
        return nil
    }

    let minuteDelta = newStartMinutes - previousStartMinutes
    guard minuteDelta != 0 else { return nil }

    let (_, shiftedMinutes) = normalizedDayAndTimeOffset(for: currentEndMinutes + minuteDelta)
    return formattedCalendarTime(minutes: shiftedMinutes)
}

func shiftedDateTimeRangeEnd(
    previousStartDate: String,
    previousStartTime: String,
    newStartDate: String,
    newStartTime: String,
    currentEndDate: String,
    currentEndTime: String,
    calendar: Calendar = .current
) -> (date: String, time: String)? {
    guard let previousStart = calendarDateTime(
            date: previousStartDate,
            time: previousStartTime,
            calendar: calendar
          ),
          let newStart = calendarDateTime(
            date: newStartDate,
            time: newStartTime,
            calendar: calendar
          ),
          let currentEnd = calendarDateTime(
            date: currentEndDate,
            time: currentEndTime,
            calendar: calendar
          ) else {
        return nil
    }

    let minuteDelta = calendar.dateComponents([.minute], from: previousStart, to: newStart).minute ?? 0
    guard minuteDelta != 0 else { return nil }
    guard let shiftedEnd = calendar.date(byAdding: .minute, value: minuteDelta, to: currentEnd) else {
        return nil
    }

    return (
        date: DateParsers.isoDay.string(from: shiftedEnd),
        time: formattedCalendarTime(for: shiftedEnd, calendar: calendar)
    )
}

private func calendarTimeMinutes(_ raw: String) -> Int? {
    let normalized = normalizedCalendarTimeInput(raw)
    let parts = normalized.split(separator: ":")
    guard parts.count == 2,
          let hours = Int(parts[0]),
          let minutes = Int(parts[1]),
          (0..<24).contains(hours),
          (0..<60).contains(minutes) else {
        return nil
    }

    return (hours * 60) + minutes
}

private func formattedCalendarTime(minutes: Int) -> String {
    let hours = minutes / 60
    let remainder = minutes % 60
    return String(format: "%02d:%02d", hours, remainder)
}

private func formattedCalendarTime(for date: Date, calendar: Calendar) -> String {
    let components = calendar.dateComponents([.hour, .minute], from: date)
    let hours = components.hour ?? 0
    let minutes = components.minute ?? 0
    return String(format: "%02d:%02d", hours, minutes)
}

private func calendarDateTime(date: String, time: String, calendar: Calendar) -> Date? {
    let normalizedDate = DateParsers.canonicalizedDayInput(date)
    guard let day = DateParsers.isoDay.date(from: normalizedDate),
          let minutes = calendarTimeMinutes(time) else {
        return nil
    }

    return calendar.date(byAdding: .minute, value: minutes, to: day)
}

private func normalizedDayAndTimeOffset(for totalMinutes: Int) -> (dayOffset: Int, minuteOfDay: Int) {
    var dayOffset = totalMinutes / 1_440
    var minuteOfDay = totalMinutes % 1_440
    if minuteOfDay < 0 {
        minuteOfDay += 1_440
        dayOffset -= 1
    }
    return (dayOffset, minuteOfDay)
}
