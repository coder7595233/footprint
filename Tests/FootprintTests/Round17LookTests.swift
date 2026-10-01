import XCTest
@testable import Footprint

/// Round 17: look and wording. Only pure helpers are tested here; all values
/// below are made up.
final class Round17LookTests: XCTestCase {

    // MARK: Excel grant statistics in kronor

    func testGrantStatisticsWorkbookColumnIsInWholeKronor() {
        // Before round 17 the column was divided by 1 000 ("tkr").
        XCTAssertEqual(GrantDataStore.grantStatisticsWorkbookKronorText(1_250_000), "1250000")
        XCTAssertEqual(GrantDataStore.grantStatisticsWorkbookKronorText(999.6), "1000")
        XCTAssertEqual(GrantDataStore.grantStatisticsWorkbookKronorText(0), "0")
    }

    func testGrantStatisticsWorkbookColumnNeverCrashesOnBadNumbers() {
        XCTAssertEqual(GrantDataStore.grantStatisticsWorkbookKronorText(.nan), "0")
        XCTAssertEqual(GrantDataStore.grantStatisticsWorkbookKronorText(.infinity), "0")
    }

    // MARK: Millions

    func testMillionsUseOneDecimalAtMost() {
        XCTAssertEqual(AmountFormatter.millions(1_234_567, language: .swedish), "1,2 mkr")
        XCTAssertEqual(AmountFormatter.millions(1_234_567, language: .english), "1.2 MSEK")
        XCTAssertEqual(AmountFormatter.millions(3_000_000, language: .swedish), "3 mkr")
    }

    func testHeatRowValuesInMillionsUseOneDecimalAtMost() {
        // The statistics heat row "Beviljat (mkr)" used up to two decimals.
        XCTAssertEqual(AmountFormatter.decimal(1.234, language: .swedish), "1,2")
        XCTAssertEqual(AmountFormatter.decimal(12, language: .english), "12")
    }

    // MARK: Dates

    private func sampleDate() throws -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = 2026
        components.month = 10
        components.day = 1
        components.hour = 12
        return try XCTUnwrap(components.date)
    }

    func testSwedishMonthStaysLowercase() throws {
        let text = AppTimestampFormatter.dayMonthYear(try sampleDate(), language: .swedish)
        XCTAssertTrue(text.hasPrefix("1 okt"), text)
        XCTAssertFalse(text.contains("Okt"), text)
        XCTAssertTrue(text.hasSuffix("2026"), text)
    }

    func testEnglishMonthKeepsItsCapital() throws {
        let text = AppTimestampFormatter.dayMonthYear(try sampleDate(), language: .english)
        XCTAssertEqual(text, "1 Oct 2026")
    }

    func testSharedDayMonthYearFollowsTheCalendarLocale() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "sv_SE")
        let text = AppTimestampFormatter.dayMonthYear(try sampleDate(), locale: calendar.locale, calendar: calendar)
        XCTAssertTrue(text.hasPrefix("1 okt"), text)
    }

    // MARK: Icons

    func testTabSymbolsAreTheOneIconSource() {
        // The calendar and CV preview now reuse these instead of their own
        // symbols ("building.2", "person.3", "megaphone", "📄", …).
        for tab in [AppTab.organizations, .congresses, .doctoralCandidates, .dissemination, .publications] {
            XCTAssertFalse(tab.symbolName.isEmpty)
            XCTAssertFalse(["building.2", "person.3", "megaphone", "person.crop.rectangle.stack"].contains(tab.symbolName))
        }
    }
}
