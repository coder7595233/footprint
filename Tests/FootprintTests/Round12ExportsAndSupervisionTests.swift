import XCTest
@testable import Footprint

/// Round 12 (CV, exports, supervision hours, event tasks). All names below
/// are made up.
final class Round12ExportsAndSupervisionTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Round12ExportsAndSupervisionTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        setenv("FOOTPRINT_STORAGE_DIRECTORY", storageDirectory.path, 1)
    }

    override func tearDown() {
        unsetenv("FOOTPRINT_STORAGE_DIRECTORY")
        if let storageDirectory {
            try? FileManager.default.removeItem(at: storageDirectory)
        }
        storageDirectory = nil
        super.tearDown()
    }

    private func day(_ text: String) -> Date {
        DateParsers.isoDay.date(from: text)!
    }

    // MARK: Conference contributions in the CV

    @MainActor
    func testOnlySubmittedAndAcceptedContributionsAreReported() {
        XCTAssertFalse(CVConferenceContribution(status: .planned).isCVReportable, "planned, not submitted")
        XCTAssertTrue(CVConferenceContribution(status: .planned, submissionAppliedOn: "2026-03-01").isCVReportable, "submitted, awaiting decision")
        XCTAssertTrue(CVConferenceContribution(status: .accepted).isCVReportable)
        XCTAssertTrue(CVConferenceContribution(status: .presented).isCVReportable)
        XCTAssertFalse(CVConferenceContribution(status: .rejected).isCVReportable)
        XCTAssertFalse(CVConferenceContribution(status: .planned, submissionAppliedOn: "2026-03-01", submissionOutcome: .declined).isCVReportable)
    }

    // MARK: AMA in the export's language

    @MainActor
    func testAcceptedArticleSaysSoInTheExportLanguage() {
        let store = GrantDataStore()
        let paper = PublicationRecord(id: "p1", title: "Invented article", status: PublicationStatus.accepted.rawValue)
        var options = PublicationExportOptions()
        options.exportLanguage = .swedish
        XCTAssertTrue(store.amaCitationItem(for: paper, options: options).plain.contains("Accepterad för publicering"))
        options.exportLanguage = .english
        XCTAssertTrue(store.amaCitationItem(for: paper, options: options).plain.contains("Accepted for publication"))

        let inReview = PublicationRecord(id: "p2", title: "Invented manuscript", status: PublicationStatus.submitted.rawValue)
        options.exportLanguage = .swedish
        XCTAssertTrue(store.amaCitationItem(for: inReview, options: options).plain.contains("Under granskning"))
    }

    // MARK: Supervision hours in proportion to days

    @MainActor
    func testAWholeHalfYearGivesTheFullHoursAndHalfTheDaysHalfTheHours() {
        let spring = DoctoralSupervisionPeriod(from: "2025-01-01", to: "2025-06-30", hoursPerSemester: "40")
        XCTAssertEqual(spring.supervisionHours(untilReferenceDate: false, referenceDate: day("2026-09-29")), 40, accuracy: 0.001)

        let autumn = DoctoralSupervisionPeriod(from: "2025-07-01", to: "2025-12-31", hoursPerSemester: "40")
        XCTAssertEqual(autumn.supervisionHours(untilReferenceDate: false, referenceDate: day("2026-09-29")), 40, accuracy: 0.001)

        // 1 Jan–31 Mar 2025 is 90 of the 181 spring days.
        let quarter = DoctoralSupervisionPeriod(from: "2025-01-01", to: "2025-03-31", hoursPerSemester: "40")
        XCTAssertEqual(quarter.supervisionHours(untilReferenceDate: false, referenceDate: day("2026-09-29")), 40.0 * 90 / 181, accuracy: 0.001)

        // Split by year: a period over the new year counts in each year.
        let overNewYear = DoctoralSupervisionPeriod(from: "2025-07-01", to: "2026-06-30", hoursPerSemester: "10")
        XCTAssertEqual(overNewYear.supervisionHours(inYear: 2025, untilReferenceDate: false, referenceDate: day("2026-09-29")), 10, accuracy: 0.001)
        XCTAssertEqual(overNewYear.supervisionHours(inYear: 2026, untilReferenceDate: false, referenceDate: day("2026-09-29")), 10, accuracy: 0.001)
    }

    @MainActor
    func testAShortPeriodOverTheSummerKeepsBothHalfYears() {
        // The old walker stepped a month at a time and lost the autumn here.
        let shares = DoctoralSupervisionPeriod.termShares(from: "2025-06-30", to: "2025-07-15", referenceDate: day("2026-09-29"))
        XCTAssertEqual(shares.map(\.half), [1, 2])
    }

    // MARK: Event tasks

    @MainActor
    func testPublishingALinkedPublicationMakesItsProjectTaskDueToday() {
        let task = ProjectTaskItem(id: "t1", deadline: "2030-01-01", reminder: .publicationPublished, comment: "Skicka pressmeddelande")
        let project = ProjectRecord(id: "proj-1", nameSv: "Exempelprojektet", nameEn: "Example project", projectTasks: [task])
        let paper = PublicationRecord(id: "p1", projectID: "proj-1", title: "Invented article", status: PublicationStatus.accepted.rawValue)
        let store = GrantDataStore(projects: [project], publicationRecords: [paper])

        var published = paper
        published.status = PublicationStatus.published.rawValue
        XCTAssertEqual(store.projects.map(\.id), ["proj-1"])
        XCTAssertEqual(store.projects.first?.projectTasks.map(\.reminder), [.publicationPublished])
        XCTAssertEqual(store.publicationRecords.first?.projectID, "proj-1", "linked before saving")
        store.savePublication(published)
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.publicationRecords.first?.projectID, "proj-1", "still linked after saving")
        XCTAssertEqual(PublicationStatus.fromStored(store.publicationRecords.first?.statusLabel ?? ""), .published)

        let today = DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date()))
        XCTAssertEqual(store.projects.first?.projectTasks.first?.deadline, today)
    }

    // MARK: Hidden warnings

    @MainActor
    func testAHiddenWarningShowsAgainWhenAnotherFieldGoesMissing() {
        let store = GrantDataStore()
        let oneField = GrantDataStore.MissingFieldIssue(
            id: "doctoral-c1", entityKind: .teaching, recordID: "c1", destination: .doctoralCandidates,
            title: "Doktorand", subtitle: "", missingFields: ["Antagningsdatum"]
        )
        XCTAssertTrue(store.hideDataQualityWarning(oneField))
        XCTAssertTrue(store.isDataQualityWarningHidden(oneField))

        let twoFields = GrantDataStore.MissingFieldIssue(
            id: "doctoral-c1", entityKind: .teaching, recordID: "c1", destination: .doctoralCandidates,
            title: "Doktorand", subtitle: "", missingFields: ["Antagningsdatum", "Handledningstimmar"]
        )
        XCTAssertFalse(store.isDataQualityWarningHidden(twoFields), "a new problem on the same record is shown")

        XCTAssertTrue(store.showDataQualityWarning(oneField))
        XCTAssertFalse(store.isDataQualityWarningHidden(oneField))
    }
}
