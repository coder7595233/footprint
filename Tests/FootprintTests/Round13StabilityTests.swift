import XCTest
@testable import Footprint

/// Round 13 (stability and correctness). All names and amounts below are
/// made up.
final class Round13StabilityTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Round13StabilityTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        setenv("FOOTPRINT_STORAGE_DIRECTORY", storageDirectory.path, 1)
    }

    private func day(_ text: String) -> Date {
        DateParsers.isoDay.date(from: text)!
    }

    override func tearDown() {
        unsetenv("FOOTPRINT_STORAGE_DIRECTORY")
        if let storageDirectory {
            try? FileManager.default.removeItem(at: storageDirectory)
        }
        storageDirectory = nil
        super.tearDown()
    }

    // MARK: Repeated keys no longer stop the app

    func testRepeatedKeysKeepTheFirstValue() {
        let pairs = [("same", 1), ("other", 2), ("same", 3)]
        let dictionary = Dictionary(firstWinsKeysWithValues: pairs)
        XCTAssertEqual(dictionary["same"], 1)
        XCTAssertEqual(dictionary["other"], 2)
        XCTAssertEqual(dictionary.count, 2)
    }

    // MARK: Amounts typed in different ways

    func testAmountInputUnderstandsCommonWritings() {
        XCTAssertEqual(GrantParsing.formatAmountInput("1250000"), "1 250 000")
        XCTAssertEqual(GrantParsing.formatAmountInput("1 250 000 kr"), "1 250 000")
        XCTAssertEqual(GrantParsing.formatAmountInput("1 250 000,50 kr"), "1 250 000", "öre are dropped")
        XCTAssertEqual(GrantParsing.formatAmountInput("1.250.000"), "1 250 000")
        XCTAssertEqual(GrantParsing.formatAmountInput("40,000 EUR"), "40 000")
        XCTAssertEqual(GrantParsing.formatAmountInput("€ 40 000"), "40 000")
        XCTAssertEqual(GrantParsing.formatAmountInput("1,5 M"), "1 500 000")
        XCTAssertEqual(GrantParsing.formatAmountInput("1.5M"), "1 500 000")
        XCTAssertEqual(GrantParsing.formatAmountInput("1,15 milj"), "1 150 000")
        XCTAssertEqual(GrantParsing.formatAmountInput("2 mkr"), "2 000 000")
        XCTAssertEqual(GrantParsing.formatAmountInput("250 tkr"), "250 000")
        XCTAssertEqual(GrantParsing.formatAmountInput("250k"), "250 000")
        XCTAssertEqual(GrantParsing.formatAmountInput("ca 500 000"), "500 000", "other text keeps the digits")
        XCTAssertNil(GrantParsing.formatAmountInput("   "))
        XCTAssertNil(GrantParsing.formatAmountInput("okänt"))
    }

    func testFormattedAmountsStayTheSame() {
        for stored in ["0", "12", "999", "1 000", "250 000", "1 250 000", "12 345 678"] {
            XCTAssertEqual(GrantParsing.formatAmountInput(stored), stored)
        }
    }

    // MARK: Amounts without an exchange rate

    @MainActor
    func testForeignAmountWithoutRateCountsAsZeroAndIsMarked() {
        let store = GrantDataStore()
        let kronor = GrantApplication(
            id: "a-sek", rowNumber: 1, organization: "Invented Fund", grantName: "Invented grant",
            currency: "SEK", appliedAmount: "100 000", appliedAmountValue: 100_000
        )
        let dollars = GrantApplication(
            id: "a-usd", rowNumber: 2, organization: "Invented Fund", grantName: "Invented grant",
            currency: "USD", appliedAmount: "50 000", appliedAmountValue: 50_000
        )
        XCTAssertEqual(store.grantStatisticsAmountInSEK(for: kronor, amount: 100_000), 100_000)
        XCTAssertEqual(store.grantStatisticsAmountInSEK(for: dollars, amount: 50_000), 0, "not counted as kronor")
        XCTAssertFalse(store.isGrantAmountUnconverted(for: kronor, amount: 100_000))
        XCTAssertTrue(store.isGrantAmountUnconverted(for: dollars, amount: 50_000))

        let summary = store.formattedGrantAmountSummaryInSEK(for: [kronor, dollars], value: \.appliedAmountValue)
        XCTAssertTrue(summary.contains("100"), summary)
        XCTAssertTrue(summary.contains("ej omräknat") || summary.contains("not converted"), summary)
        XCTAssertTrue(summary.contains("USD"), summary)

        XCTAssertEqual(store.unconvertedAmountSuffix(for: [(kronor, 100_000)]), "")
        XCTAssertFalse(store.unconvertedAmountSuffix(for: [(dollars, 50_000)]).isEmpty)
    }

    func testSalaryEstimateInKronorIsNotReadAsForeignBudget() {
        let inEuro = GrantApplication(
            id: "a-eur", rowNumber: 1, organization: "Invented Fund", grantName: "Invented grant",
            currency: "EUR", approximateAmount: "900 000", approximateAmountValue: 900_000,
            appliedAmount: "80 000", appliedAmountValue: 80_000
        )
        XCTAssertEqual(inEuro.preferredBudgetAmountValue, 80_000)

        let inKronor = GrantApplication(
            id: "a-sek", rowNumber: 2, organization: "Invented Fund", grantName: "Invented grant",
            currency: "SEK", approximateAmount: "900 000", approximateAmountValue: 900_000,
            appliedAmount: "80 000", appliedAmountValue: 80_000
        )
        XCTAssertEqual(inKronor.preferredBudgetAmountValue, 900_000)
    }

    // MARK: Show all hidden warnings

    @MainActor
    func testShowAllHiddenWarningsClearsEveryHiddenWarningAndCanBeUndone() {
        let store = GrantDataStore()
        let first = GrantDataStore.MissingFieldIssue(
            id: "doctoral-c1", entityKind: .teaching, recordID: "c1", destination: .doctoralCandidates,
            title: "Doktorand", subtitle: "", missingFields: ["Antagningsdatum"]
        )
        let second = GrantDataStore.MissingFieldIssue(
            id: "doctoral-c2", entityKind: .teaching, recordID: "c2", destination: .doctoralCandidates,
            title: "Doktorand", subtitle: "", missingFields: ["Handledningstimmar"]
        )
        XCTAssertTrue(store.hideDataQualityWarning(first))
        XCTAssertTrue(store.hideDataQualityWarning(second))
        XCTAssertEqual(store.hiddenDataQualityWarningTotalCount, 2)

        XCTAssertTrue(store.showAllHiddenDataQualityWarnings())
        XCTAssertEqual(store.hiddenDataQualityWarningTotalCount, 0)
        XCTAssertFalse(store.isDataQualityWarningHidden(first))
        XCTAssertFalse(store.isDataQualityWarningHidden(second))
        XCTAssertFalse(store.showAllHiddenDataQualityWarnings(), "nothing left to show")
    }

    // MARK: Closed calls that still say "Att söka"

    private func closedCall(id: String = "call-1") -> GrantApplication {
        GrantApplication(
            id: id, rowNumber: 1, organization: "Invented Foundation", grantName: "Invented call",
            opensOn: "2026-08-01", closesOn: "2026-09-15"
        )
    }

    func testClosedCallWithoutAnswerAwaitsAnAnswer() {
        let call = closedCall()
        XCTAssertFalse(call.awaitsAppliedAnswer(today: day("2026-09-15")), "closing day itself is still open")
        XCTAssertTrue(call.awaitsAppliedAnswer(today: day("2026-09-16")))

        var applied = call
        applied.appliedOn = "2026-09-10"
        XCTAssertFalse(applied.awaitsAppliedAnswer(today: day("2026-10-01")))

        var notApplied = call
        notApplied.notAppliedOn = "2026-09-10"
        notApplied.result = "Ej sökt"
        XCTAssertFalse(notApplied.awaitsAppliedAnswer(today: day("2026-10-01")))
    }

    @MainActor
    func testAnsweringAppliedSetsTheClosingDayAsUncertainAppliedDate() {
        let store = GrantDataStore(applications: [closedCall()], skipInitialMigration: true)
        XCTAssertEqual(store.applicationsAwaitingAppliedAnswer(today: day("2026-10-01")).map(\.id), ["call-1"])
        store.askAppliedQuestion(applicationID: "call-1")
        XCTAssertEqual(store.pendingAppliedQuestionApplicationID, "call-1")

        XCTAssertTrue(store.answerAppliedQuestion(applicationID: "call-1", applied: true, today: day("2026-10-01")))
        XCTAssertNil(store.pendingAppliedQuestionApplicationID)
        let saved = store.applications.first { $0.id == "call-1" }
        XCTAssertEqual(saved?.appliedOn, "2026-09-15")
        XCTAssertEqual(saved?.appliedOnUncertain, true)
        XCTAssertEqual(saved?.resultLabel, "Väntar svar")
        XCTAssertTrue(store.applicationsAwaitingAppliedAnswer(today: day("2026-10-01")).isEmpty)
    }

    @MainActor
    func testAnsweringNotAppliedMarksTheCallEjSokt() {
        let store = GrantDataStore(applications: [closedCall()], skipInitialMigration: true)
        XCTAssertTrue(store.answerAppliedQuestion(applicationID: "call-1", applied: false, today: day("2026-10-01")))
        let saved = store.applications.first { $0.id == "call-1" }
        XCTAssertEqual(saved?.notAppliedOn, "2026-09-15")
        XCTAssertEqual(saved?.resultLabel, "Ej sökt")
        XCTAssertFalse(store.answerAppliedQuestion(applicationID: "call-1", applied: true, today: day("2026-10-01")), "already answered")
    }

    func testClosedUnansweredCallGetsANotificationTheDayAfterClosing() {
        let schedules = GrantReminderCoordinator.reminderSchedule(
            for: closedCall(), settings: .standard, calendar: Calendar.current
        )
        let question = schedules.first { $0.kind == .closedUnanswered }
        XCTAssertEqual(question.map { DateParsers.isoDay.string(from: $0.fireDate) }, "2026-09-16")
    }
}
