import XCTest
@testable import Footprint

/// Round 16: one word per application outcome, one amount format and small
/// localisation helpers. All values below are made up.
final class Round16WordingTests: XCTestCase {

    // MARK: Outcome wording table

    func testApplicationOutcomeLabelsInSwedish() {
        XCTAssertEqual(ApplicationOutcome.toApply.label(.swedish), "Att söka")
        XCTAssertEqual(ApplicationOutcome.awaitingDecision.label(.swedish), "Väntar svar")
        XCTAssertEqual(ApplicationOutcome.granted.label(.swedish), "Beviljat")
        XCTAssertEqual(ApplicationOutcome.declined.label(.swedish), "Avslag")
        XCTAssertEqual(ApplicationOutcome.withdrawn.label(.swedish), "Tillbakadragen")
        XCTAssertEqual(ApplicationOutcome.notApplied.label(.swedish), "Ej sökt")
    }

    func testApplicationOutcomeHeadingsInSwedish() {
        XCTAssertEqual(ApplicationOutcome.toApply.heading(.swedish), "Att söka")
        XCTAssertEqual(ApplicationOutcome.awaitingDecision.heading(.swedish), "Väntar svar")
        XCTAssertEqual(ApplicationOutcome.granted.heading(.swedish), "Beviljade")
        XCTAssertEqual(ApplicationOutcome.declined.heading(.swedish), "Avslagna")
        XCTAssertEqual(ApplicationOutcome.withdrawn.heading(.swedish), "Tillbakadragna")
        XCTAssertEqual(ApplicationOutcome.notApplied.heading(.swedish), "Ej sökta")
    }

    func testApplicationOutcomeWordsInEnglish() {
        let expected: [ApplicationOutcome: String] = [
            .toApply: "To apply",
            .awaitingDecision: "Awaiting decision",
            .granted: "Granted",
            .declined: "Declined",
            .withdrawn: "Withdrawn",
            .notApplied: "Not applied",
        ]
        for (outcome, word) in expected {
            XCTAssertEqual(outcome.label(.english), word)
            XCTAssertEqual(outcome.heading(.english), word)
        }
    }

    func testOutcomeWordingNeverUsesTheOldOrPublicationWords() {
        let banned = ["Awarded", "Pending", "Awaiting response", "Accepted", "Rejected",
                      "Väntar beslut", "Avslagen", "Beviljad", "Accepterad", "Refuserad"]
        for outcome in ApplicationOutcome.allCases {
            for language in AppLanguage.allCases {
                for word in [outcome.label(language), outcome.heading(language)] {
                    XCTAssertFalse(banned.contains(word), "\(outcome) shows \(word)")
                }
            }
        }
    }

    func testStoredValuesAreUnchanged() {
        XCTAssertEqual(ApplicationOutcome.allCases.map(\.rawValue), GrantParsing.statusOptions)
        XCTAssertEqual(ApplicationOutcome(storedValue: " Beviljat "), .granted)
        XCTAssertNil(ApplicationOutcome(storedValue: "Invented status"))
    }

    func testStatusPickerUsesTheSameSingularWords() {
        for outcome in ApplicationOutcome.allCases {
            XCTAssertEqual(AppLanguage.swedish.localizedStatus(outcome.rawValue), outcome.label(.swedish))
            XCTAssertEqual(AppLanguage.english.localizedStatus(outcome.rawValue), outcome.label(.english))
        }
    }

    func testPublicationRejectionWording() {
        XCTAssertEqual(PublicationOutcomeWording.rejectedLabel(.swedish), "Refuserad")
        XCTAssertEqual(PublicationOutcomeWording.rejectedHeading(.swedish), "Refuserade")
        XCTAssertEqual(PublicationOutcomeWording.rejectedLabel(.english), "Rejected")
    }

    // MARK: Amounts

    func testKronorFollowTheLanguage() {
        XCTAssertEqual(AmountFormatter.sek(1_250_000, language: .swedish), "1 250 000 kr")
        XCTAssertEqual(AmountFormatter.sek(1_250_000, language: .english), "1 250 000 SEK")
        XCTAssertEqual(AmountFormatter.sek(nil, language: .swedish), "–")
        XCTAssertEqual(AmountFormatter.sek(nil, language: .english), "–")
    }

    func testMillionsFollowTheLanguage() {
        XCTAssertEqual(AmountFormatter.millions(1_300_000, language: .swedish), "1,3 mkr")
        XCTAssertEqual(AmountFormatter.millions(1_300_000, language: .english), "1.3 MSEK")
        XCTAssertEqual(AmountFormatter.millions(2_000_000, language: .swedish), "2 mkr")
        XCTAssertEqual(AmountFormatter.millionsUnit(.swedish), "mkr")
        XCTAssertEqual(AmountFormatter.millionsUnit(.english), "MSEK")
    }

    func testCurrencyFormatterWithLanguage() {
        XCTAssertEqual(CurrencyFormatter.format(40_000, code: "SEK", language: .swedish), "40 000 kr")
        XCTAssertEqual(CurrencyFormatter.format(40_000, code: "SEK", language: .english), "40 000 SEK")
        XCTAssertEqual(CurrencyFormatter.format(40_000, code: "EUR", language: .swedish), "40 000 EUR")
        // Without a language the code is kept as before.
        XCTAssertEqual(CurrencyFormatter.format(40_000, code: "SEK"), "40 000 SEK")
        // A missing amount is a dash, never "N/A".
        XCTAssertEqual(CurrencyFormatter.format(nil, code: "SEK"), "–")
        XCTAssertEqual(CurrencyFormatter.format(nil, code: "SEK", language: .swedish), "–")
    }

    func testInlineStatisticsUseTheSharedFormatter() {
        XCTAssertEqual(inlineStatisticsSEKText(12_500, language: .swedish), "12 500 kr")
        XCTAssertEqual(inlineStatisticsSEKText(12_500, language: .english), "12 500 SEK")
    }

    // MARK: Small localisation

    func testDatePlaceholderFollowsTheLanguage() {
        XCTAssertEqual(AppLanguage.swedish.datePlaceholder, "ÅÅÅÅ-MM-DD")
        XCTAssertEqual(AppLanguage.english.datePlaceholder, "YYYY-MM-DD")
    }

    func testTimestampsUseISODateAnd24HourTime() throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = 2026
        components.month = 3
        components.day = 4
        components.hour = 15
        components.minute = 7
        let date = try XCTUnwrap(components.date)
        XCTAssertEqual(AppTimestampFormatter.dateAndTime(date), "2026-03-04 15:07")
        XCTAssertEqual(AppTimestampFormatter.time(date), "15:07")
    }
}
