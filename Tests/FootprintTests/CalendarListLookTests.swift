import XCTest
@testable import Footprint

/// Calendar list look: week header row, merged day column and meeting icons.
/// Only pure helpers are tested here; all values below are made up.
final class CalendarListLookTests: XCTestCase {

    // MARK: Week header row

    func testWeekHeaderAcrossTwoMonths() {
        XCTAssertEqual(
            calendarListWeekHeaderLabel(
                weekNumber: 40,
                startDay: 28, startMonth: 9, startYear: 2026,
                endDay: 4, endMonth: 10, endYear: 2026,
                showsYear: true,
                language: .swedish
            ),
            "Vecka 40 · 28 sep – 4 okt 2026"
        )
        XCTAssertEqual(
            calendarListWeekHeaderLabel(
                weekNumber: 40,
                startDay: 28, startMonth: 9, startYear: 2026,
                endDay: 4, endMonth: 10, endYear: 2026,
                showsYear: true,
                language: .english
            ),
            "Week 40 · 28 Sep – 4 Oct 2026"
        )
    }

    func testWeekHeaderInsideOneMonthNamesTheMonthOnce() {
        XCTAssertEqual(
            calendarListWeekHeaderLabel(
                weekNumber: 41,
                startDay: 5, startMonth: 10, startYear: 2026,
                endDay: 11, endMonth: 10, endYear: 2026,
                showsYear: true,
                language: .swedish
            ),
            "Vecka 41 · 5 – 11 okt 2026"
        )
    }

    func testWeekHeaderLeavesOutHiddenWeekNumberAndYear() {
        XCTAssertEqual(
            calendarListWeekHeaderLabel(
                weekNumber: nil,
                startDay: 28, startMonth: 9, startYear: 2026,
                endDay: 4, endMonth: 10, endYear: 2026,
                showsYear: true,
                language: .swedish
            ),
            "28 sep – 4 okt 2026"
        )
        XCTAssertEqual(
            calendarListWeekHeaderLabel(
                weekNumber: 40,
                startDay: 28, startMonth: 9, startYear: 2026,
                endDay: 4, endMonth: 10, endYear: 2026,
                showsYear: false,
                language: .swedish
            ),
            "Vecka 40 · 28 sep – 4 okt"
        )
    }

    func testWeekHeaderAcrossNewYearShowsBothYears() {
        XCTAssertEqual(
            calendarListWeekHeaderLabel(
                weekNumber: 53,
                startDay: 28, startMonth: 12, startYear: 2026,
                endDay: 3, endMonth: 1, endYear: 2027,
                showsYear: true,
                language: .swedish
            ),
            "Vecka 53 · 28 dec 2026 – 3 jan 2027"
        )
    }

    // MARK: Merged day column

    func testShortDayLabel() {
        // Calendar weekday 6 is Friday.
        XCTAssertEqual(calendarListShortDayLabel(weekday: 6, day: 2, month: 10, language: .swedish), "Fre 2 okt")
        XCTAssertEqual(calendarListShortDayLabel(weekday: 6, day: 2, month: 10, language: .english), "Fri 2 Oct")
        XCTAssertEqual(calendarListShortDayLabel(weekday: 1, day: 3, month: 5, language: .swedish), "Sön 3 maj")
    }

    // MARK: Meeting icons

    func testOnlineAndInPersonMeetingsGetDifferentIcons() {
        XCTAssertEqual(calendarMeetingCategoryIconName(place: "Online"), "video")
        XCTAssertEqual(calendarMeetingCategoryIconName(place: " online "), "video")
        XCTAssertEqual(calendarMeetingCategoryIconName(place: "Telefon"), "phone")
        XCTAssertEqual(calendarMeetingCategoryIconName(place: "Exempelstad"), "person.2")
        XCTAssertEqual(calendarMeetingCategoryIconName(place: ""), "person.2")
    }
}
