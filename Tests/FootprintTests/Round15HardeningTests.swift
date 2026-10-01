import XCTest
@testable import Footprint

/// Round 15 (exports, mail links, reminders, exchange rates, hardening).
/// All names and values below are made up.
final class Round15HardeningTests: XCTestCase {

    // MARK: Attachment list for Excel

    func testFieldsStartingLikeAFormulaAreShownAsText() {
        XCTAssertEqual(GrantDataStore.csvField("=HYPERLINK(\"http://x\")"), "\"'=HYPERLINK(\"\"http://x\"\")\"")
        XCTAssertEqual(GrantDataStore.csvField("+46 invented"), "'+46 invented")
        XCTAssertEqual(GrantDataStore.csvField("-1"), "'-1")
        XCTAssertEqual(GrantDataStore.csvField("@invented"), "'@invented")
        XCTAssertEqual(GrantDataStore.csvField("Invented report.pdf"), "Invented report.pdf")
        XCTAssertEqual(GrantDataStore.csvField("a;b"), "\"a;b\"")
    }

    // MARK: Mail links

    func testMailLinkTakesOnlyAPlainAddress() {
        XCTAssertEqual(singleRecipientMailtoURL(" person@example.org ")?.absoluteString, "mailto:person@example.org")
        XCTAssertNil(singleRecipientMailtoURL("person@example.org?bcc=other@example.org"))
        XCTAssertNil(singleRecipientMailtoURL("person@example.org&body=invented"))
        XCTAssertNil(singleRecipientMailtoURL("not an address"))
        XCTAssertNil(singleRecipientMailtoURL(""))
    }

    func testMailLinksWithAQueryAreRefused() {
        XCTAssertNil(safeExternalURL(URL(string: "mailto:person@example.org?bcc=other@example.org")))
        XCTAssertNotNil(safeExternalURL(URL(string: "mailto:person@example.org")))
        XCTAssertNotNil(safeExternalURL(URL(string: "mailto:a@example.org,b@example.org")), "group mail still works")
    }

    // MARK: Reminders

    func testGrantReminderKeepsClockTimeOnSummerTimeDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Stockholm"))
        let settings = CalendarReminderSettings.standard
        let expectedHour = settings.grantReminderHourMinute.hour
        for text in ["2027-03-28", "2027-10-31", "2027-06-15"] {
            var components = DateComponents()
            let parts = text.split(separator: "-").compactMap { Int($0) }
            components.year = parts[0]; components.month = parts[1]; components.day = parts[2]
            let day = try XCTUnwrap(calendar.date(from: components))
            let fire = GrantReminderCoordinator.reminderDate(on: day, settings: settings, calendar: calendar)
            XCTAssertEqual(calendar.component(.hour, from: fire), expectedHour, text)
            XCTAssertEqual(calendar.component(.day, from: fire), parts[2], text)
        }
    }

    // MARK: Long numbers

    func testVeryLongNumbersAreNotAmounts() {
        XCTAssertNil(GrantParsing.numericValue(from: "12345678901234567890"))
        XCTAssertNil(GrantParsing.numericValue(from: String(repeating: "9", count: 400)))
        XCTAssertEqual(GrantParsing.numericValue(from: "1 250 000"), 1_250_000)
    }

    // MARK: Exchange rates

    func testRatesBeforeAWeekendFirstDateAreKept() throws {
        let xml = """
        <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
          <Cube>
            <Cube time="2026-03-09">
              <Cube currency="USD" rate="1.0000"/>
              <Cube currency="SEK" rate="10.0000"/>
            </Cube>
            <Cube time="2026-03-06">
              <Cube currency="USD" rate="1.0000"/>
              <Cube currency="SEK" rate="10.0000"/>
            </Cube>
            <Cube time="2026-01-02">
              <Cube currency="USD" rate="1.0000"/>
              <Cube currency="SEK" rate="10.0000"/>
            </Cube>
          </Cube>
        </gesmes:Envelope>
        """
        // 2026-03-07 is a Saturday: the Friday before is kept, so a rate
        // "on or before" that day exists. A day long before is not kept.
        let cache = try CurrencyExchangeRateCache.parsedECBHistoricalXML(
            Data(xml.utf8),
            firstApplicationDate: "2026-03-07",
            fetchedAt: DateParsers.isoDay.date(from: "2026-03-10")!
        )
        XCTAssertEqual(cache.days.map(\.date), ["2026-03-09", "2026-03-06"])
        XCTAssertNotNil(cache.convertingToSEK(100, currency: "USD", onOrBefore: "2026-03-07"))
    }
}
