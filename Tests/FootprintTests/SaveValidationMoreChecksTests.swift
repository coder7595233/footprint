import XCTest
@testable import Footprint

/// F19: the remaining checks from the change log (ORCID check digit, times
/// in the wrong order, a decision after the congress, links to records that
/// no longer exist) show in the Data view and count as wrong values.
final class SaveValidationMoreChecksTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SaveValidationMoreChecksTests-\(UUID().uuidString)", isDirectory: true)
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

    private func swedishMetadata() -> DataSourceMetadata {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = "sv"
        return metadata
    }

    @MainActor
    private func fields(_ store: GrantDataStore, recordID: String) -> [String] {
        store.missingFieldIssues(includeHidden: true)
            .filter { $0.recordID == recordID }
            .flatMap(\.missingFields)
    }

    @MainActor
    private func subtitles(_ store: GrantDataStore) -> [String] {
        store.integrityIssues(includeHidden: true).map(\.subtitle)
    }

    // MARK: - 1. ORCID

    @MainActor
    func testAnORCIDWithAWrongCheckDigitIsFlagged() {
        var wrong = PublicationAuthor(id: "author-wrong", name: "Anna Andersson")
        wrong.orcid = "0000-0002-1825-0098"
        var right = PublicationAuthor(id: "author-right", name: "Bo Berg")
        right.orcid = "https://orcid.org/0000-0002-1825-0097"
        let store = GrantDataStore(metadata: swedishMetadata(), publicationAuthors: [wrong, right], skipInitialMigration: true)

        XCTAssertTrue(fields(store, recordID: "author-wrong").contains("ORCID har ogiltig kontrollsiffra"))
        XCTAssertFalse(fields(store, recordID: "author-right").contains("ORCID har ogiltig kontrollsiffra"))
        XCTAssertFalse(fields(store, recordID: "author-right").contains("ORCID-formatet är ogiltigt"))
    }

    // MARK: - 2. Times and dates

    @MainActor
    func testACalendarEventEndingBeforeItStartsIsFlagged() {
        var metadata = swedishMetadata()
        metadata.calendarMeetingRecords = [
            CalendarMeetingRecord(id: "m-wrong", date: "2026-03-02", startTime: "14:00", endTime: "13:00", title: "Projektmöte"),
            CalendarMeetingRecord(id: "m-midnight", date: "2026-03-02", startTime: "20:00", endTime: "00:00", title: "Kvällsmöte"),
            CalendarMeetingRecord(id: "m-right", date: "2026-03-02", startTime: "09:00", endTime: "10:00", title: "Handledning"),
        ]
        let store = GrantDataStore(metadata: metadata, skipInitialMigration: true)

        let flagged = store.integrityIssues(includeHidden: true)
            .filter { $0.subtitle == "Kalenderhändelse slutar före den börjar" }
        XCTAssertEqual(flagged.map(\.recordID), ["m-wrong"])
        XCTAssertEqual(flagged.first?.calendarRevealDayString, "2026-03-02")
    }

    @MainActor
    func testTravelArrivingBeforeItDepartsIsFlagged() {
        var metadata = swedishMetadata()
        metadata.calendarTravelRecords = [
            CalendarTravelRecord(
                id: "t-date", date: "2026-03-02", arrivalDate: "2026-03-01",
                departureTime: "08:00", fromCity: "Exempelköping", fromCountry: "Sverige",
                arrivalTime: "09:00", toCity: "Stockholm", toCountry: "Sverige", mode: .train
            ),
            CalendarTravelRecord(
                id: "t-time", date: "2026-03-02", arrivalDate: "2026-03-02",
                departureTime: "10:00", fromCity: "Exempelköping", fromCountry: "Sverige",
                arrivalTime: "09:00", toCity: "Stockholm", toCountry: "Sverige", mode: .train
            ),
            // Helsinki is an hour ahead: an earlier local arrival time is correct.
            CalendarTravelRecord(
                id: "t-timezone", date: "2026-03-02", arrivalDate: "2026-03-02",
                departureTime: "08:00", fromCity: "Helsingfors", fromCountry: "Finland",
                arrivalTime: "07:55", toCity: "Stockholm", toCountry: "Sverige", mode: .flight
            ),
        ]
        let store = GrantDataStore(metadata: metadata, skipInitialMigration: true)
        let issues = store.integrityIssues(includeHidden: true)

        XCTAssertTrue(issues.contains { $0.recordID == "t-date" && $0.subtitle == "Resa kommer fram före avresan" })
        XCTAssertTrue(issues.contains { $0.recordID == "t-time" && $0.subtitle == "Resans ankomsttid före avgångstid" })
        XCTAssertFalse(issues.contains { $0.recordID == "t-timezone" })
    }

    @MainActor
    func testCheckOutBeforeCheckInIsFlagged() {
        // Reversed dates are swapped when the record is normalized, so only a
        // same-day stay with the check-out time before check-in can be wrong.
        var metadata = swedishMetadata()
        metadata.calendarAccommodationRecords = [
            CalendarAccommodationRecord(id: "h-wrong", hotelName: "Hotell", checkInDate: "2026-03-05", checkInTime: "15:00", checkOutDate: "2026-03-05", checkOutTime: "11:00", city: "Wien"),
            CalendarAccommodationRecord(id: "h-right", hotelName: "Hotell 2", checkInDate: "2026-03-04", checkInTime: "15:00", checkOutDate: "2026-03-05", checkOutTime: "11:00", city: "Wien"),
        ]
        let store = GrantDataStore(metadata: metadata, skipInitialMigration: true)
        let flagged = store.integrityIssues(includeHidden: true).filter { $0.subtitle == "Utcheckning före incheckning" }

        XCTAssertEqual(flagged.map(\.recordID), ["h-wrong"])
    }

    @MainActor
    func testAMediaAppearanceEndingBeforeItStartsIsFlagged() {
        let media = CVMediaAppearance(id: "media-1", date: "2026-03-02", startTime: "10:00", endTime: "09:30", title: "Radiointervju")
        let store = GrantDataStore(metadata: swedishMetadata(), cvMediaAppearances: [media], skipInitialMigration: true)

        XCTAssertTrue(fields(store, recordID: "mediaAppearance:media-1").contains("Sluttid före starttid"))
    }

    @MainActor
    func testACourseValidityEndingBeforeItStartsIsFlagged() {
        var course = TeachingCourse(id: "course-1", name: "Klinisk medicin 2")
        course.validFrom = "2026-06-01"
        course.validTo = "2026-01-01"
        let store = GrantDataStore(metadata: swedishMetadata(), teachingCourses: [course], skipInitialMigration: true)

        XCTAssertTrue(fields(store, recordID: "course-1").contains("Giltighet slutar före den börjar"))
    }

    // MARK: - 3. Decision after the congress

    @MainActor
    func testADecisionAfterTheCongressIsFlagged() {
        let late = CVConferenceContribution(
            id: "late", from: "2025-05-23", to: "2025-05-26", title: "Sent beslut",
            submissionDecisionOn: "2025-06-01", submissionOutcome: .granted
        )
        let onTime = CVConferenceContribution(
            id: "on-time", from: "2025-05-23", to: "2025-05-26", title: "Beslut i tid",
            submissionDecisionOn: "2025-03-07", submissionOutcome: .granted
        )
        let store = GrantDataStore(metadata: swedishMetadata(), cvConferenceContributions: [late, onTime], skipInitialMigration: true)

        XCTAssertTrue(fields(store, recordID: "conferenceContribution:late").contains("Beslut efter kongressen"))
        XCTAssertFalse(fields(store, recordID: "conferenceContribution:on-time").contains("Beslut efter kongressen"))
    }

    // MARK: - 4. Links to records that no longer exist

    @MainActor
    func testLinksToMissingRecordsAreFlagged() {
        var assignment = TeachingAssignment(id: "a1", periods: [], activityName: "Föreläsning", roles: [])
        assignment.activityTypeID = "missing-format"
        var course = TeachingCourse(id: "course-1", name: "Klinisk medicin 2")
        course.programID = "missing-programme"
        var publication = PublicationRecord(id: "pub-1", title: "Artikel")
        publication.journalID = "missing-journal"
        var contribution = CVConferenceContribution(id: "c1", title: "Abstrakt")
        contribution.projectID = "missing-project"
        let store = GrantDataStore(
            metadata: swedishMetadata(),
            teachingCourses: [course],
            teachingAssignments: [assignment],
            cvConferenceContributions: [contribution],
            publicationRecords: [publication],
            skipInitialMigration: true
        )
        let broken = store.integrityIssues(includeHidden: true).filter { $0.kind == .brokenLink }
        let details = Set(broken.map(\.details))

        XCTAssertTrue(details.contains("missing-format"))
        XCTAssertTrue(details.contains("missing-programme"))
        XCTAssertTrue(details.contains("missing-journal"))
        XCTAssertTrue(details.contains("missing-project"))
    }

    @MainActor
    func testANewBrokenLinkIsWarnedAboutAfterSaving() {
        let assignment = TeachingAssignment(
            id: "a1",
            periods: [TeachingAssignmentPeriod(from: "2026-01-01", to: "2026-06-30")],
            activityName: "Seminarier",
            roles: [TeachingAssignmentRole("Lärare")]
        )
        let store = GrantDataStore(metadata: swedishMetadata(), teachingAssignments: [assignment], skipInitialMigration: true)
        _ = store.missingFieldIssues()

        guard var edited = store.teachingAssignments.first(where: { $0.id == "a1" }) else {
            return XCTFail("uppdraget saknas")
        }
        edited.authorID = "borttagen-forskare"
        store.autosaveTeachingAssignment(edited)
        store.runSaveValidation()

        XCTAssertEqual(store.teachingAssignments.first { $0.id == "a1" }?.authorID, "borttagen-forskare", "sparningen stoppades")
        XCTAssertEqual(store.notice?.tone, .info)
        XCTAssertTrue(
            store.notice?.message.contains("Lärar-ID länkar till saknad forskare") == true,
            store.notice?.message ?? "inget meddelande"
        )

        // The same broken link is not pointed out again on the next save.
        store.notice = nil
        edited.comment = "En kommentar"
        store.autosaveTeachingAssignment(edited)
        store.runSaveValidation()
        XCTAssertFalse(store.notice?.message.contains("kontrollera") ?? false)
    }

    // MARK: - Counted as wrong values

    func testTheNewChecksCountAsCritical() {
        for field in [
            "ORCID har ogiltig kontrollsiffra", "ORCID check digit is invalid",
            "Sluttid före starttid", "End time before start time",
            "Giltighet slutar före den börjar", "Validity ends before it starts",
            "Kurskodens giltighet slutar före den börjar",
            "Beslut efter kongressen", "Decision after the congress",
        ] {
            XCTAssertTrue(GrantDataStore.isCriticalDataQualityField(field), field)
        }
    }

    func testTimesAreComparedAsClockTimes() {
        XCTAssertTrue(GrantDataStore.dataQualityTimeEndsBeforeStart(start: "14:00", end: "13:59"))
        XCTAssertTrue(GrantDataStore.dataQualityTimeEndsBeforeStart(start: "930", end: "9:00"))
        XCTAssertFalse(GrantDataStore.dataQualityTimeEndsBeforeStart(start: "09:00", end: "10:00"))
        XCTAssertFalse(GrantDataStore.dataQualityTimeEndsBeforeStart(start: "22:00", end: "00:00"))
        XCTAssertFalse(GrantDataStore.dataQualityTimeEndsBeforeStart(start: "", end: "08:00"))
        XCTAssertFalse(GrantDataStore.dataQualityTimeEndsBeforeStart(start: "??", end: "08:00"))
    }
}
