import XCTest
@testable import Footprint

/// Round 7 (Handledningstimmar, user decision): the hours on a doctoral
/// candidate's supervision periods are hours per term. The hours so far are
/// the hours per term times the terms from the period's start to its end date
/// (or today), counted in proportion to the months (months / 6, one decimal).
/// The teaching merits export uses this sum; there is no separate field.
final class DoctoralSupervisionHoursTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DoctoralSupervisionHoursTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        setenv("FOOTPRINT_STORAGE_DIRECTORY", storageDirectory.path, 1)
        WorkflowDefaultSettingsRegistry.replace(with: .builtIn)
    }

    override func tearDown() {
        WorkflowDefaultSettingsRegistry.replace(with: .builtIn)
        unsetenv("FOOTPRINT_STORAGE_DIRECTORY")
        if let storageDirectory {
            try? FileManager.default.removeItem(at: storageDirectory)
        }
        storageDirectory = nil
        super.tearDown()
    }

    private func day(_ text: String) throws -> Date {
        try XCTUnwrap(DateParsers.isoDay.date(from: text))
    }

    // MARK: Terms and hours per period

    func testEighteenMonthsAreThreeTermsAndFifteenHoursAtFiveHoursPerTerm() throws {
        let reference = try day("2026-09-29")
        XCTAssertEqual(DoctoralSupervisionPeriod.accruedTerms(from: "2025-02-06", to: "2026-08-06", referenceDate: reference), 3.0)
        let period = DoctoralSupervisionPeriod(from: "2025-02-06", to: "2026-08-06", hoursPerSemester: "5")
        XCTAssertEqual(period.accruedSupervisionHours(referenceDate: reference), 15)
    }

    func testOpenEndCountsToTheReferenceDate() throws {
        let period = DoctoralSupervisionPeriod(from: "2026-01-01", to: "", hoursPerSemester: "10")
        XCTAssertEqual(period.accruedSupervisionHours(referenceDate: try day("2026-07-01")), 10, "one term so far")
        XCTAssertEqual(period.accruedSupervisionHours(referenceDate: try day("2026-04-01")), 5, "half a term so far")
        XCTAssertTrue(period.accruesUntilReferenceDate(try day("2026-07-01")))
    }

    func testEndDateLaterThanTodayStopsAtToday() throws {
        let period = DoctoralSupervisionPeriod(from: "2026-01-01", to: "2030-12-31", hoursPerSemester: "10")
        XCTAssertEqual(period.accruedSupervisionHours(referenceDate: try day("2026-07-01")), 10)
        XCTAssertTrue(period.accruesUntilReferenceDate(try day("2026-07-01")))
    }

    func testEndDateInThePastCountsToTheEndDate() throws {
        let period = DoctoralSupervisionPeriod(from: "2024-01-01", to: "2024-06-30", hoursPerSemester: "40")
        XCTAssertEqual(period.accruedSupervisionHours(referenceDate: try day("2026-09-29")), 40)
        XCTAssertFalse(period.accruesUntilReferenceDate(try day("2026-09-29")))
    }

    func testMissingOrFutureStartGivesZeroAndMissingHoursGiveNothing() throws {
        let reference = try day("2026-09-29")
        XCTAssertEqual(DoctoralSupervisionPeriod(from: "", to: "2025-06-30", hoursPerSemester: "10").accruedSupervisionHours(referenceDate: reference), 0)
        XCTAssertEqual(DoctoralSupervisionPeriod(from: "2027-01-01", to: "", hoursPerSemester: "10").accruedSupervisionHours(referenceDate: reference), 0)
        XCTAssertNil(DoctoralSupervisionPeriod(from: "2024-01-01", to: "2024-06-30", hoursPerSemester: "").accruedSupervisionHours(referenceDate: reference))
    }

    func testCandidateTotalIsTheSumAndNilWithoutHoursPerTerm() throws {
        let reference = try day("2026-09-29")
        let candidate = DoctoralCandidateRecord(
            id: "c",
            supervisionPeriods: [
                DoctoralSupervisionPeriod(from: "2024-01-01", to: "2024-06-30", hoursPerSemester: "40"),
                DoctoralSupervisionPeriod(from: "2025-02-06", to: "2026-08-06", hoursPerSemester: "5")
            ]
        )
        XCTAssertEqual(candidate.accruedSupervisionHours(referenceDate: reference), 55)

        let withoutHours = DoctoralCandidateRecord(
            id: "e",
            supervisionPeriods: [DoctoralSupervisionPeriod(from: "2024-01-01", to: "2024-06-30")]
        )
        XCTAssertNil(withoutHours.accruedSupervisionHours(referenceDate: reference))
    }

    // MARK: Stored data

    func testOldHandEnteredHoursStillDecodeButAreDroppedOnSave() throws {
        let json = """
        {"id":"old","candidateName":"Gammal Doktorand","supervisors":[],"supervisionPeriods":[{"from":"2024-01-01","to":"2024-06-30","hoursPerSemester":"10"}],"teachingMeritSupervisionHours":"120"}
        """
        var candidate = try JSONDecoder().decode(DoctoralCandidateRecord.self, from: Data(json.utf8))
        XCTAssertEqual(candidate.teachingMeritSupervisionHours, "120", "data written by the earlier version loads")
        XCTAssertEqual(candidate.supervisionPeriods.first?.hoursPerSemester, "10")

        candidate.normalize()
        XCTAssertNil(candidate.teachingMeritSupervisionHours)
        let text = try XCTUnwrap(String(data: JSONEncoder().encode(candidate), encoding: .utf8))
        XCTAssertFalse(text.contains("teachingMeritSupervisionHours"), "the unused value is not written again")
        XCTAssertTrue(text.contains("hoursPerSemester"))
    }

    // MARK: Store and export

    @MainActor
    private func makeStore() -> GrantDataStore {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = "sv"
        let me = PublicationAuthor(id: "author-me", name: "Anna Testsson")
        let principalCandidate = DoctoralCandidateRecord(
            id: "principal",
            candidateName: "Doktorand Huvud",
            institution: "Exempelköpings universitet",
            admissionDate: "2024-01-01",
            supervisors: [
                DoctoralSupervisorLink(authorID: me.id, name: me.name, from: "2024-01-01"),
                DoctoralSupervisorLink(name: "Annan Handledare", from: "2024-01-01")
            ],
            supervisionPeriods: [
                DoctoralSupervisionPeriod(from: "2024-01-01", to: "2024-06-30", hoursPerSemester: "40"),
                DoctoralSupervisionPeriod(from: "2026-01-01", to: "", hoursPerSemester: "10")
            ],
            teachingMeritSupervisionHours: "150"
        )
        let assistantCandidate = DoctoralCandidateRecord(
            id: "assistant",
            candidateName: "Doktorand Bi",
            institution: "Exempelköpings universitet",
            admissionDate: "2019-01-01",
            supervisors: [
                DoctoralSupervisorLink(name: "Annan Huvudhandledare", from: "2019-01-01"),
                DoctoralSupervisorLink(authorID: me.id, name: me.name, from: "2020-01-01", to: "2024-12-31")
            ],
            supervisionPeriods: [
                DoctoralSupervisionPeriod(from: "2020-01-01", to: "2020-06-30")
            ]
        )
        let otherCandidate = DoctoralCandidateRecord(
            id: "other",
            candidateName: "Doktorand Annan",
            supervisors: [DoctoralSupervisorLink(name: "Någon Annan", from: "2020-01-01")]
        )
        return GrantDataStore(
            metadata: metadata,
            doctoralCandidates: [principalCandidate, assistantCandidate, otherCandidate],
            publicationAuthors: [me],
            skipInitialMigration: true
        )
    }

    @MainActor
    func testExportSumsTheHoursPerTermAndIgnoresTheOldField() throws {
        let store = makeStore()
        let reference = try day("2026-07-01")
        let document = store.teachingMeritsExportDocument(referenceDate: reference)
        let supervision = try XCTUnwrap(document.groups.first { $0.title == "Handledning" })

        let principalTable = try XCTUnwrap(supervision.tables.first { $0.title.contains("forskarnivå - huvudhandledare") })
        XCTAssertEqual(principalTable.rows.count, 1)
        XCTAssertEqual(principalTable.rows[0][1], "50", "40 h for one past term + 10 h for the open term so far; the old 150 is ignored")
        XCTAssertEqual(principalTable.rows[0][5], "Doktorand Huvud")
        XCTAssertEqual(principalTable.sumValue, "50")
        XCTAssertTrue(principalTable.title.contains("6 månader"), "the heading from the settings is unchanged")

        let assistantTable = try XCTUnwrap(supervision.tables.first { $0.title.contains("forskarnivå - bihandledare") })
        XCTAssertEqual(assistantTable.rows.count, 1)
        XCTAssertEqual(assistantTable.rows[0][1], "", "no hours per term: the cell stays empty")
        XCTAssertEqual(assistantTable.sumValue, "0")

        let summary = try XCTUnwrap(document.summaryRows.first { $0.first == "Total tid handledning av studerande på forskarnivå som huvudhandledare" })
        XCTAssertEqual(summary[1], "50")
    }

    @MainActor
    func testExportCellUsesTheComputedTotal() throws {
        let store = makeStore()
        let reference = try day("2026-07-01")
        let principal = try XCTUnwrap(store.doctoralCandidates.first { $0.id == "principal" })
        XCTAssertEqual(store.teachingMeritsDoctoralCandidateHoursCell(principal, referenceDate: reference), "50")
        let assistant = try XCTUnwrap(store.doctoralCandidates.first { $0.id == "assistant" })
        XCTAssertEqual(store.teachingMeritsDoctoralCandidateHoursCell(assistant, referenceDate: reference), "")
    }

    @MainActor
    func testPreviewNoLongerWritesEjAngivet() throws {
        let store = makeStore()
        let tables = store.teachingMeritsPreviewDocument().groups.flatMap(\.tables)
        let assistantTable = try XCTUnwrap(tables.first { $0.title.contains("forskarnivå - bihandledare") })
        XCTAssertEqual(assistantTable.rows.first?[1], "")
        XCTAssertFalse(tables.flatMap(\.rows).flatMap { $0 }.contains("ej angivet"))
    }
}
