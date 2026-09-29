import XCTest
@testable import Footprint

/// The calendar source index applies single-record edits as deltas instead of
/// rebuilding every source; these tests pin the delta semantics: edits,
/// additions, removals, sort order, out-of-range fallback, and the
/// multi-entry (travel) case.
final class CalendarSourceIndexDeltaTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ iso: String) -> Date {
        calendar.startOfDay(for: DateParsers.isoDay.date(from: iso)!)
    }

    private func meeting(_ id: String, date: String, title: String = "Meeting") -> CalendarMeetingRecord {
        CalendarMeetingRecord(id: id, date: date, title: title)
    }

    private func meetingEntries(_ meeting: CalendarMeetingRecord) -> [CalendarDatedValue<CalendarMeetingRecord>] {
        guard let parsed = DateParsers.isoDay.date(from: meeting.date) else { return [] }
        return [CalendarDatedValue(day: calendar.startOfDay(for: parsed), value: meeting)]
    }

    private func makeIndex(meetings: [CalendarMeetingRecord]) -> CalendarWorkspaceEventSourceIndex {
        var index = CalendarWorkspaceEventSourceIndex(visibleRange: day("2026-01-01")...day("2026-12-31"))
        index.meetingRecords = meetings.flatMap(meetingEntries)
        index.meetingRecords.sort { $0.day < $1.day }
        return index
    }

    func testEditedRecordReplacesItsEntryAndKeepsOrder() {
        let a = meeting("a", date: "2026-03-01")
        let b = meeting("b", date: "2026-05-01")
        let c = meeting("c", date: "2026-07-01")
        var index = makeIndex(meetings: [a, b, c])

        var editedB = b
        editedB.date = "2026-08-15"
        editedB.title = "Moved"
        let applied = index.applyDatedDelta(
            to: \.meetingRecords,
            records: [a, editedB, c],
            entriesFor: meetingEntries
        )

        XCTAssertTrue(applied)
        XCTAssertEqual(index.meetingRecords.map(\.value.id), ["a", "c", "b"])
        XCTAssertEqual(index.meetingRecords.map(\.day), [day("2026-03-01"), day("2026-07-01"), day("2026-08-15")])
        XCTAssertEqual(index.meetingRecords.last?.value.title, "Moved")
    }

    func testAddedAndRemovedRecordsAreApplied() {
        let a = meeting("a", date: "2026-03-01")
        let b = meeting("b", date: "2026-05-01")
        var index = makeIndex(meetings: [a, b])

        let added = meeting("new", date: "2026-04-01")
        let applied = index.applyDatedDelta(
            to: \.meetingRecords,
            records: [a, added],
            entriesFor: meetingEntries
        )

        XCTAssertTrue(applied)
        XCTAssertEqual(index.meetingRecords.map(\.value.id), ["a", "new"])
    }

    func testUnchangedRecordsShortCircuit() {
        let a = meeting("a", date: "2026-03-01")
        let b = meeting("b", date: "2026-05-01")
        var index = makeIndex(meetings: [a, b])
        let before = index.meetingRecords.map(\.value)

        let applied = index.applyDatedDelta(
            to: \.meetingRecords,
            records: [b, a],
            entriesFor: meetingEntries
        )

        XCTAssertTrue(applied)
        XCTAssertEqual(index.meetingRecords.map(\.value), before)
    }

    func testOutOfRangeDateRequestsFullRebuild() {
        let a = meeting("a", date: "2026-03-01")
        var index = makeIndex(meetings: [a])

        var moved = a
        moved.date = "2027-02-01"
        let applied = index.applyDatedDelta(
            to: \.meetingRecords,
            records: [moved],
            entriesFor: meetingEntries
        )

        XCTAssertFalse(applied, "a date outside the visible range must fall back to a full rebuild")
    }

    func testDatelessRecordDropsItsEntries() {
        let a = meeting("a", date: "2026-03-01")
        var index = makeIndex(meetings: [a])

        var cleared = a
        cleared.date = ""
        let applied = index.applyDatedDelta(
            to: \.meetingRecords,
            records: [cleared],
            entriesFor: meetingEntries
        )

        XCTAssertTrue(applied)
        XCTAssertTrue(index.meetingRecords.isEmpty)
    }

    func testTravelStyleMultiEntryRecordsReplaceAllTheirEntries() {
        let travel = CalendarTravelRecord(id: "t1", date: "2026-03-01", arrivalDate: "2026-03-03")
        func entries(_ record: CalendarTravelRecord) -> [CalendarDatedValue<CalendarTravelRecord>] {
            let days = [
                DateParsers.isoDay.date(from: record.date),
                DateParsers.isoDay.date(from: record.resolvedArrivalDateString())
            ]
            .compactMap { $0.map { calendar.startOfDay(for: $0) } }
            return Set(days).map { CalendarDatedValue(day: $0, value: record) }
        }

        var index = CalendarWorkspaceEventSourceIndex(visibleRange: day("2026-01-01")...day("2026-12-31"))
        index.travelRecords = entries(travel).sorted { $0.day < $1.day }
        XCTAssertEqual(index.travelRecords.count, 2)

        var edited = travel
        edited.arrivalDate = "2026-03-05"
        let applied = index.applyDatedDelta(
            to: \.travelRecords,
            records: [edited],
            entriesFor: entries
        )

        XCTAssertTrue(applied)
        XCTAssertEqual(index.travelRecords.count, 2)
        XCTAssertEqual(
            index.travelRecords.map(\.day),
            [day("2026-03-01"), day("2026-03-05")],
            "both old entries must be replaced, not just the changed day"
        )
    }

    func testRangedDeltaReplacesAccommodationEntry() {
        let stay = CalendarAccommodationRecord(id: "h1", hotelName: "Hotel", checkInDate: "2026-06-01", checkOutDate: "2026-06-04")
        func entries(_ record: CalendarAccommodationRecord) -> [CalendarRangedValue<CalendarAccommodationRecord>] {
            let days = [
                record.checkInDate.nonEmpty.flatMap(DateParsers.isoDay.date(from:)),
                record.checkOutDate.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
            ]
            .compactMap { $0.map { calendar.startOfDay(for: $0) } }
            guard let start = days.min(), let end = days.max() else { return [] }
            return [CalendarRangedValue(start: start, end: end, value: record)]
        }

        var index = CalendarWorkspaceEventSourceIndex(visibleRange: day("2026-01-01")...day("2026-12-31"))
        index.accommodationRecords = entries(stay)

        var edited = stay
        edited.checkOutDate = "2026-06-06"
        let applied = index.applyRangedDelta(
            to: \.accommodationRecords,
            records: [edited],
            entriesFor: entries
        )

        XCTAssertTrue(applied)
        XCTAssertEqual(index.accommodationRecords.first?.end, day("2026-06-06"))
        XCTAssertEqual(index.accommodationRecords.first?.value.checkOutDate, "2026-06-06")
    }
}
