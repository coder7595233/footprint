import XCTest
@testable import Footprint

/// Calendar week view: week bounds, title, time placement and side-by-side
/// columns. Only pure helpers are tested here; all values below are made up.
final class CalendarWeekViewTests: XCTestCase {

    private func mondayCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        calendar.locale = Locale(identifier: "sv_SE")
        calendar.firstWeekday = 2
        return calendar
    }

    private func sundayCalendar() -> Calendar {
        var calendar = mondayCalendar()
        calendar.firstWeekday = 1
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: Week start and end

    func testWeekStartAndEndWithMondayStart() {
        let calendar = mondayCalendar()
        // Thursday 8 October 2026, in the afternoon.
        let thursday = day(2026, 10, 8, hour: 15, minute: 30, in: calendar)
        XCTAssertEqual(calendarWeekViewWeekStart(for: thursday, calendar: calendar), day(2026, 10, 5, in: calendar))
        XCTAssertEqual(calendarWeekViewWeekEnd(for: thursday, calendar: calendar), day(2026, 10, 11, in: calendar))
    }

    func testWeekStartOnTheFirstAndLastDayOfTheWeek() {
        let calendar = mondayCalendar()
        XCTAssertEqual(
            calendarWeekViewWeekStart(for: day(2026, 10, 5, in: calendar), calendar: calendar),
            day(2026, 10, 5, in: calendar)
        )
        XCTAssertEqual(
            calendarWeekViewWeekStart(for: day(2026, 10, 11, hour: 23, minute: 59, in: calendar), calendar: calendar),
            day(2026, 10, 5, in: calendar)
        )
    }

    func testWeekStartFollowsSundayWeekStartSetting() {
        let calendar = sundayCalendar()
        let thursday = day(2026, 10, 8, in: calendar)
        XCTAssertEqual(calendarWeekViewWeekStart(for: thursday, calendar: calendar), day(2026, 10, 4, in: calendar))
        XCTAssertEqual(calendarWeekViewWeekEnd(for: thursday, calendar: calendar), day(2026, 10, 10, in: calendar))
    }

    func testWeekHasSevenDaysInOrder() {
        let calendar = mondayCalendar()
        let days = calendarWeekViewDays(weekStart: day(2026, 10, 5, in: calendar), calendar: calendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first, day(2026, 10, 5, in: calendar))
        XCTAssertEqual(days.last, day(2026, 10, 11, in: calendar))
    }

    func testWeekAcrossDaylightSavingChangeStillHasSevenMidnights() {
        let calendar = mondayCalendar()
        // Summer time ends on Sunday 25 October 2026 in Stockholm.
        let days = calendarWeekViewDays(weekStart: day(2026, 10, 19, in: calendar), calendar: calendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.last, day(2026, 10, 25, in: calendar))
        XCTAssertTrue(days.allSatisfy { calendar.component(.hour, from: $0) == 0 })
    }

    // MARK: Week title

    func testWeekTitleInsideOneMonth() {
        let calendar = mondayCalendar()
        XCTAssertEqual(
            calendarWeekViewTitle(weekStart: day(2026, 10, 5, in: calendar), calendar: calendar, language: .swedish),
            "Vecka 41 · 5–11 okt 2026"
        )
        XCTAssertEqual(
            calendarWeekViewTitle(weekStart: day(2026, 10, 5, in: calendar), calendar: calendar, language: .english),
            "Week 41 · 5–11 Oct 2026"
        )
    }

    func testWeekTitleAcrossTwoMonths() {
        let calendar = mondayCalendar()
        XCTAssertEqual(
            calendarWeekViewTitle(weekStart: day(2026, 9, 28, in: calendar), calendar: calendar, language: .swedish),
            "Vecka 40 · 28 sep–4 okt 2026"
        )
    }

    func testWeekTitleAcrossTwoYears() {
        let calendar = mondayCalendar()
        XCTAssertEqual(
            calendarWeekViewTitle(weekStart: day(2026, 12, 28, in: calendar), calendar: calendar, language: .swedish),
            "Vecka 53 · 28 dec 2026–3 jan 2027"
        )
    }

    // MARK: Times

    func testClockRangeReadsRangesSingleTimesAndUncertainTimes() {
        XCTAssertEqual(calendarWeekViewClockRange(from: "09:00–10:30")?.start, 540)
        XCTAssertEqual(calendarWeekViewClockRange(from: "09:00–10:30")?.end, 630)
        XCTAssertEqual(calendarWeekViewClockRange(from: "14:15")?.start, 855)
        XCTAssertNil(calendarWeekViewClockRange(from: "14:15")?.end)
        XCTAssertEqual(calendarWeekViewClockRange(from: "07:40?–11:05?")?.start, 460)
        XCTAssertEqual(calendarWeekViewClockRange(from: "07:40?–11:05?")?.end, 665)
        XCTAssertNil(calendarWeekViewClockRange(from: ""))
        XCTAssertNil(calendarWeekViewClockRange(from: "lunch"))
        XCTAssertNil(calendarWeekViewMinute(fromClockText: "25:00"))
        XCTAssertEqual(calendarWeekViewMinute(fromClockText: "24:00"), 1440)
    }

    // MARK: All-day or timed

    func testMeetingWithTimesIsTimed() {
        XCTAssertEqual(
            calendarWeekViewPlacement(kind: .meeting, timeText: "10:00–11:30"),
            .timed(CalendarWeekTimeSpan(startMinute: 600, endMinute: 690))
        )
    }

    func testMeetingWithOnlyAStartTimeGetsOneHour() {
        XCTAssertEqual(
            calendarWeekViewPlacement(kind: .meeting, timeText: "13:00"),
            .timed(CalendarWeekTimeSpan(startMinute: 780, endMinute: 840))
        )
    }

    func testMeetingWithoutTimeGoesInAllDayStrip() {
        XCTAssertEqual(calendarWeekViewPlacement(kind: .meeting, timeText: ""), .allDay)
    }

    func testTaskWithDeadlineTimeIsAShortBlock() {
        XCTAssertEqual(
            calendarWeekViewPlacement(kind: .taskDeadline, timeText: "16:00"),
            .timed(CalendarWeekTimeSpan(startMinute: 960, endMinute: 990))
        )
        XCTAssertEqual(calendarWeekViewPlacement(kind: .taskDeadline, timeText: ""), .allDay)
    }

    func testCongressDeadlineAndAccommodationAreAlwaysAllDay() {
        XCTAssertEqual(calendarWeekViewPlacement(kind: .congress, timeText: "09:00–17:00"), .allDay)
        XCTAssertEqual(calendarWeekViewPlacement(kind: .applicationDeadline, timeText: "23:59"), .allDay)
        XCTAssertEqual(calendarWeekViewPlacement(kind: .accommodation, timeText: "15:00"), .allDay)
    }

    func testOvernightTravelIsCutAtMidnight() {
        XCTAssertEqual(
            calendarWeekViewPlacement(kind: .travel, timeText: "22:10–06:45"),
            .timed(CalendarWeekTimeSpan(startMinute: 1330, endMinute: 1440))
        )
    }

    // MARK: Position and height

    func testYOffsetAndBlockFrame() {
        XCTAssertEqual(calendarWeekViewYOffset(minute: 0, hourHeight: 48), 0)
        XCTAssertEqual(calendarWeekViewYOffset(minute: 7 * 60 + 30, hourHeight: 48), 360)
        XCTAssertEqual(
            calendarWeekViewBlockFrame(
                span: CalendarWeekTimeSpan(startMinute: 9 * 60, endMinute: 10 * 60 + 30),
                hourHeight: 48,
                minimumHeight: 22
            ),
            CalendarWeekBlockFrame(y: 432, height: 72)
        )
    }

    func testShortBlockGetsMinimumHeight() {
        XCTAssertEqual(
            calendarWeekViewBlockFrame(
                span: CalendarWeekTimeSpan(startMinute: 600, endMinute: 610),
                hourHeight: 48,
                minimumHeight: 22
            ),
            CalendarWeekBlockFrame(y: 480, height: 22)
        )
    }

    func testBlockAtMidnightStaysInsideTheDay() {
        let frame = calendarWeekViewBlockFrame(
            span: CalendarWeekTimeSpan(startMinute: 1435, endMinute: 1440),
            hourHeight: 48,
            minimumHeight: 22
        )
        XCTAssertEqual(frame.height, 22)
        XCTAssertEqual(frame.y + frame.height, 24 * 48)
    }

    // MARK: Side-by-side columns

    func testSeparateBlocksKeepFullWidth() {
        let slots = calendarWeekViewPackColumns([
            CalendarWeekTimeSpan(startMinute: 480, endMinute: 540),
            CalendarWeekTimeSpan(startMinute: 540, endMinute: 600)
        ])
        XCTAssertEqual(slots, [
            CalendarWeekColumnSlot(column: 0, columnCount: 1),
            CalendarWeekColumnSlot(column: 0, columnCount: 1)
        ])
    }

    func testTwoOverlappingBlocksShareTheWidth() {
        let slots = calendarWeekViewPackColumns([
            CalendarWeekTimeSpan(startMinute: 540, endMinute: 660),
            CalendarWeekTimeSpan(startMinute: 600, endMinute: 630)
        ])
        XCTAssertEqual(slots, [
            CalendarWeekColumnSlot(column: 0, columnCount: 2),
            CalendarWeekColumnSlot(column: 1, columnCount: 2)
        ])
    }

    func testFreedColumnIsReusedInsideAGroup() {
        // A 09–12, B 09:30–10, C 10:30–11: C fits under B in column 1.
        let slots = calendarWeekViewPackColumns([
            CalendarWeekTimeSpan(startMinute: 540, endMinute: 720),
            CalendarWeekTimeSpan(startMinute: 570, endMinute: 600),
            CalendarWeekTimeSpan(startMinute: 630, endMinute: 660)
        ])
        XCTAssertEqual(slots.map(\.column), [0, 1, 1])
        XCTAssertEqual(slots.map(\.columnCount), [2, 2, 2])
    }

    func testThreeAtOnceAndALaterSeparateBlock() {
        let slots = calendarWeekViewPackColumns([
            CalendarWeekTimeSpan(startMinute: 840, endMinute: 900),
            CalendarWeekTimeSpan(startMinute: 600, endMinute: 660),
            CalendarWeekTimeSpan(startMinute: 600, endMinute: 690),
            CalendarWeekTimeSpan(startMinute: 615, endMinute: 645)
        ])
        // Input order is kept; the longer of the two 10:00 blocks goes first.
        XCTAssertEqual(slots[0], CalendarWeekColumnSlot(column: 0, columnCount: 1))
        XCTAssertEqual(slots[2], CalendarWeekColumnSlot(column: 0, columnCount: 3))
        XCTAssertEqual(slots[1], CalendarWeekColumnSlot(column: 1, columnCount: 3))
        XCTAssertEqual(slots[3], CalendarWeekColumnSlot(column: 2, columnCount: 3))
    }

    func testMinimumDurationMakesTouchingShortBlocksSideBySide() {
        // Two task deadlines five minutes apart are drawn at least 30
        // minutes tall, so they must not cover each other.
        let slots = calendarWeekViewPackColumns(
            [
                CalendarWeekTimeSpan(startMinute: 600, endMinute: 605),
                CalendarWeekTimeSpan(startMinute: 605, endMinute: 610)
            ],
            minimumDuration: 30
        )
        XCTAssertEqual(slots.map(\.columnCount), [2, 2])
        XCTAssertEqual(Set(slots.map(\.column)), [0, 1])
    }

    func testEmptyInputGivesNoSlots() {
        XCTAssertEqual(calendarWeekViewPackColumns([]), [])
    }
}
