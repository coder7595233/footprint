import Foundation

// Chronological order for calendar meetings and travel.
//
// The comparators used to parse both records' dates (and normalize both
// start times) inside every comparison. Sorting ~1,800 meetings makes about
// 20,000 comparisons, so one edit re-parsed the same dates some 40,000 times:
// about 200 ms on the main thread, both when a meeting was saved and when the
// calendar re-read its meetings afterwards. The keys are now computed once
// per record. The comparison itself is unchanged, so the order is identical.

/// The parts of a meeting that decide its place in the calendar list.
struct CalendarMeetingSortKey: Equatable {
    let day: Date
    let startTime: String

    init(record: CalendarMeetingRecord) {
        day = DateParsers.isoDay.date(from: record.date) ?? .distantFuture
        startTime = normalizedCalendarTimeInput(record.startTime)
    }
}

/// Date, then start time (meetings without one last), then title, then id.
func calendarMeetingRecordPrecedes(
    _ left: CalendarMeetingRecord,
    _ leftKey: CalendarMeetingSortKey,
    _ right: CalendarMeetingRecord,
    _ rightKey: CalendarMeetingSortKey
) -> Bool {
    if leftKey.day != rightKey.day {
        return leftKey.day < rightKey.day
    }
    if leftKey.startTime != rightKey.startTime {
        if leftKey.startTime.isEmpty { return false }
        if rightKey.startTime.isEmpty { return true }
        return leftKey.startTime.localizedStandardCompare(rightKey.startTime) == .orderedAscending
    }
    let comparison = left.title.localizedStandardCompare(right.title)
    if comparison != .orderedSame {
        return comparison == .orderedAscending
    }
    return left.id < right.id
}

func calendarMeetingRecordsSortedChronologically(_ records: [CalendarMeetingRecord]) -> [CalendarMeetingRecord] {
    calendarMeetingRecordsSortedChronologically(
        keyed: records.map { (record: $0, key: CalendarMeetingSortKey(record: $0)) }
    )
}

/// For callers that already hold the keys (the store keeps them per record).
func calendarMeetingRecordsSortedChronologically(
    keyed: [(record: CalendarMeetingRecord, key: CalendarMeetingSortKey)]
) -> [CalendarMeetingRecord] {
    keyed
        .sorted { calendarMeetingRecordPrecedes($0.record, $0.key, $1.record, $1.key) }
        .map { $0.record }
}

/// Travel: departure date, then departure time as written, then id.
func calendarTravelRecordsSortedChronologically(_ records: [CalendarTravelRecord]) -> [CalendarTravelRecord] {
    records
        .map { (record: $0, day: DateParsers.isoDay.date(from: $0.date) ?? Date.distantFuture) }
        .sorted { left, right in
            if left.day != right.day {
                return left.day < right.day
            }
            if left.record.departureTime != right.record.departureTime {
                return left.record.departureTime.localizedStandardCompare(right.record.departureTime) == .orderedAscending
            }
            return left.record.id < right.record.id
        }
        .map { $0.record }
}
