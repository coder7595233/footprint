import XCTest
@testable import Footprint

/// F13d: the readers that decide "is this me?" or "is this that researcher?"
/// use the researcher links first and the written names second.
/// F43: links to researchers that no longer exist show in the Data view and
/// after a save.
/// F44: one calendar change is handled with one calendar refresh.
final class IDFirstReaderTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IDFirstReaderTests-\(UUID().uuidString)", isDirectory: true)
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

    /// The current user after a rename: the records still say "Anna
    /// Andersson", which is no longer one of her names, but their id links
    /// point to her.
    private var renamedAnna: PublicationAuthor {
        PublicationAuthor(id: "au-anna", name: "Anna Lind", firstName: "Anna", lastName: "Lind")
    }

    /// Another researcher after a rename: the records still say "Bo Berg".
    private var renamedBo: PublicationAuthor {
        PublicationAuthor(id: "au-bo", name: "Bo Holm", firstName: "Bo", lastName: "Holm")
    }

    private static func isoDay(daysFromNow days: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return DateParsers.isoDay.string(from: date)
    }

    @MainActor
    private func makeStore(
        applications: [GrantApplication] = [],
        projects: [ProjectRecord] = [],
        publications: [PublicationRecord] = [],
        meetings: [CalendarMeetingRecord] = [],
        teachingAssignments: [TeachingAssignment] = [],
        conferenceContributions: [CVConferenceContribution] = [],
        authors: [PublicationAuthor]? = nil,
        currentUserAuthorID: String? = "au-anna"
    ) -> GrantDataStore {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = "sv"
        metadata.currentUserAuthorID = currentUserAuthorID
        metadata.calendarMeetingRecords = meetings
        return GrantDataStore(
            applications: applications,
            metadata: metadata,
            projects: projects,
            teachingAssignments: teachingAssignments,
            cvConferenceContributions: conferenceContributions,
            publicationAuthors: authors ?? [renamedAnna, renamedBo],
            publicationRecords: publications,
            skipInitialMigration: true
        )
    }

    private func makeApplication(
        id: String,
        names: [String],
        ids: [String]
    ) -> GrantApplication {
        var application = GrantApplication(
            id: id,
            rowNumber: 1,
            organization: "Fonden",
            grantName: "Projektbidrag",
            coApplicants: names
        )
        application.coApplicantAuthorIDs = ids
        return application
    }

    // MARK: - F13d: "mine" by id link

    @MainActor
    func testTheOldNameNoLongerMatchesButTheIDStillDoes() {
        let store = makeStore()
        XCTAssertFalse(store.isCurrentUserPresentedName("Anna Andersson"), "förutsättning: det gamla namnet är inte längre hennes")
        XCTAssertTrue(store.isCurrentUserAmong(ids: ["au-anna"], names: ["Anna Andersson"]))
        XCTAssertFalse(store.isCurrentUserAmong(ids: [], names: ["Anna Andersson"]), "utan koppling avgör namnet, som förut")
        XCTAssertTrue(store.isCurrentUserAmong(ids: [], names: ["Anna Lind"]), "namnet räcker fortfarande när kopplingen saknas")
        XCTAssertFalse(store.isCurrentUserAmong(ids: ["au-bo"], names: ["Bo Berg"]))
    }

    @MainActor
    func testMainApplicantIsFoundByIDAfterTheRename() {
        let mine = makeApplication(id: "app-mine", names: ["Anna Andersson", "Bo Berg"], ids: ["au-anna", "au-bo"])
        let theirs = makeApplication(id: "app-theirs", names: ["Bo Berg", "Anna Andersson"], ids: ["au-bo", "au-anna"])
        let unlinked = makeApplication(id: "app-unlinked", names: ["Anna Andersson", "Extern Person"], ids: [])
        let store = makeStore(applications: [mine, theirs, unlinked])

        XCTAssertTrue(store.isCurrentUserFirstPerson(ids: mine.coApplicantAuthorIDs, names: mine.coApplicants))
        XCTAssertTrue(store.isCurrentUserFirstApplicant(mine), "huvudsökande känns inte igen efter namnbytet")
        XCTAssertFalse(store.isCurrentUserFirstApplicant(theirs))
        XCTAssertTrue(store.isCurrentUserAmong(ids: theirs.coApplicantAuthorIDs, names: theirs.coApplicants), "medsökande räknas som mitt")
        XCTAssertFalse(store.isCurrentUserFirstApplicant(unlinked), "utan koppling och med ett gammalt namn är det inte mitt")
        // The names written in the records are left as they were.
        XCTAssertEqual(store.applications.first { $0.id == "app-mine" }?.coApplicants, ["Anna Andersson", "Bo Berg"])
    }

    @MainActor
    func testAuthorPositionUsesTheIDWhenEveryNameIsLinked() {
        let store = makeStore()
        XCTAssertEqual(
            store.currentUserPersonIndex(ids: ["au-bo", "au-anna"], names: ["Bo Berg", "Anna Andersson"]),
            1
        )
        // When not every name has a link the ids do not line up with the
        // names, so the written name decides as before.
        XCTAssertNil(store.currentUserPersonIndex(ids: ["au-anna"], names: ["Extern Person", "Anna Andersson"]))
        XCTAssertEqual(store.currentUserPersonIndex(ids: [], names: ["Bo Berg", "Anna Lind"]), 1)
    }

    @MainActor
    func testCalendarResearcherRowsFindRecordsWrittenWithTheOldName() {
        let meeting = CalendarMeetingRecord(
            id: "meeting-1",
            date: Self.isoDay(daysFromNow: 30),
            title: "Möte",
            participantNames: ["Anna Andersson"],
            participantAuthorIDs: ["au-anna"]
        )
        let otherMeeting = CalendarMeetingRecord(
            id: "meeting-2",
            date: Self.isoDay(daysFromNow: 31),
            title: "Annat möte",
            participantNames: ["Extern Person"]
        )
        let store = makeStore(meetings: [meeting, otherMeeting])

        let rows = calendarLinkedEventRows(store: store, language: .swedish, scope: .researcher("Anna Lind"))
        XCTAssertTrue(rows.contains { $0.source == .meeting("meeting-1") }, "mötet med det gamla namnet saknas")
        XCTAssertFalse(rows.contains { $0.source == .meeting("meeting-2") })

        let byOldName = calendarLinkedEventRows(store: store, language: .swedish, scope: .researcher("Anna Andersson"))
        XCTAssertTrue(byOldName.contains { $0.source == .meeting("meeting-1") }, "det skrivna namnet ska fortfarande hittas")
    }

    @MainActor
    func testMeetingStatisticsCountParticipantsByID() {
        let meeting = CalendarMeetingRecord(
            id: "meeting-1",
            date: Self.isoDay(daysFromNow: 10),
            title: "Möte",
            participantNames: ["Bo Berg"],
            participantAuthorIDs: ["au-bo"]
        )
        let store = makeStore(meetings: [meeting])
        let summary = calendarMeetingHoursSummary(store: store, scope: .researcher(renamedBo))
        XCTAssertEqual(summary.plannedMeetingCount + summary.completedMeetingCount, 1, "mötet räknas inte för forskaren efter namnbytet")
    }

    // MARK: - F43: links to researchers that no longer exist

    @MainActor
    func testLinksToMissingResearchersAreFlaggedWithTheWrittenName() {
        let application = makeApplication(
            id: "app-1",
            names: ["Anna Andersson", "Borttagen Person"],
            ids: ["au-anna", "au-gone"]
        )
        var project = ProjectRecord(
            id: "proj-1",
            nameSv: "Projekt",
            nameEn: "Project",
            collaboratorNames: ["Extern Person", "Någon Annan"]
        )
        project.collaboratorAuthorIDs = ["au-gone"]
        var publication = PublicationRecord(
            id: "pub-1",
            title: "Artikel",
            authorNames: ["Borttagen Person"],
            correspondingAuthorName: "Borttagen Person"
        )
        publication.authorIDs = ["au-gone"]
        publication.correspondingAuthorID = "au-gone"
        let meeting = CalendarMeetingRecord(
            id: "meeting-1",
            date: "2027-02-10",
            title: "Möte",
            participantNames: ["Borttagen Person"],
            participantAuthorIDs: ["au-gone"]
        )
        var assignment = TeachingAssignment(id: "ta-1", periods: [], activityName: "Handledning", roles: [])
        assignment.studentName = "Borttagen Student"
        assignment.studentAuthorID = "au-gone-student"
        var contribution = CVConferenceContribution(id: "c1", title: "Abstrakt")
        contribution.presentedBy = "Borttagen Person"
        contribution.presentedByAuthorID = "au-gone"
        let store = makeStore(
            applications: [application],
            projects: [project],
            publications: [publication],
            meetings: [meeting],
            teachingAssignments: [assignment],
            conferenceContributions: [contribution]
        )

        let subtitle = "Kopplad till en forskare som inte finns"
        let flagged = store.integrityIssues(includeHidden: true).filter { $0.subtitle == subtitle }

        func details(for recordID: String) -> [String] {
            flagged.filter { $0.recordID == recordID }.map(\.details)
        }
        XCTAssertEqual(details(for: "app-1"), ["Borttagen Person"], "namnet ska visas när det är känt")
        XCTAssertEqual(details(for: "proj-1"), ["au-gone"], "utan känt namn visas id:t")
        XCTAssertEqual(details(for: "pub-1"), ["Borttagen Person"], "samma person ska bara nämnas en gång")
        XCTAssertEqual(details(for: "meeting-1"), ["Borttagen Person"])
        XCTAssertTrue(flagged.allSatisfy { $0.kind == .brokenLink })

        // Kinds that already have their own row are not shown twice in the
        // Data view: the student and the presenter keep their old rows.
        XCTAssertEqual(details(for: "ta-1"), [])
        XCTAssertEqual(details(for: "conferenceContribution:c1"), [])
        let allSubtitles = Set(store.integrityIssues(includeHidden: true).map(\.subtitle))
        XCTAssertTrue(allSubtitles.contains("Student-ID länkar till saknad forskare"))
        XCTAssertTrue(allSubtitles.contains("Presentatörs-id länkar till saknad forskare"))

        // The check after saving has the new rows too, plus the presenter,
        // whose old row is only part of the Data view's full list.
        let saveCheck = store.dataQualityLinkAndTimeIssues(forSaveCheck: true).filter { $0.subtitle == subtitle }
        XCTAssertTrue(Set(flagged.map(\.id)).isSubset(of: Set(saveCheck.map(\.id))))
        XCTAssertEqual(
            saveCheck.filter { $0.recordID == "conferenceContribution:c1" }.map(\.details),
            ["Borttagen Person"]
        )
        XCTAssertFalse(saveCheck.contains { $0.recordID == "ta-1" }, "studenten har redan sin egen rad")

        // Nothing was changed in the records.
        XCTAssertEqual(store.applications.first?.coApplicantAuthorIDs, ["au-anna", "au-gone"])
        XCTAssertEqual(store.projects.first?.collaboratorAuthorIDs, ["au-gone"])
    }

    @MainActor
    func testLinksToExistingResearchersAreNotFlagged() {
        let application = makeApplication(id: "app-1", names: ["Anna Andersson", "Bo Berg"], ids: ["au-anna", "au-bo"])
        let store = makeStore(applications: [application])
        let subtitle = "Kopplad till en forskare som inte finns"
        XCTAssertFalse(store.integrityIssues(includeHidden: true).contains { $0.subtitle == subtitle })
    }

    @MainActor
    func testASaveThatLeavesALinkToAMissingResearcherIsWarnedAbout() {
        // Without researchers the stored links are kept as they are on save,
        // which is how a link to a removed researcher can survive a save.
        let original = makeApplication(id: "app-1", names: ["Extern Person"], ids: [])
        let store = makeStore(applications: [original], authors: [], currentUserAuthorID: nil)
        _ = store.missingFieldIssues()

        var edited = original
        edited.coApplicants = ["Borttagen Person"]
        edited.coApplicantAuthorIDs = ["au-gone"]
        store.autosave(application: edited)
        store.runSaveValidation()

        XCTAssertEqual(store.applications.first?.coApplicantAuthorIDs, ["au-gone"], "sparningen stoppades")
        XCTAssertEqual(store.notice?.tone, .info)
        XCTAssertTrue(
            store.notice?.message.contains("Kopplad till en forskare som inte finns") == true,
            store.notice?.message ?? "inget meddelande"
        )
    }

    // MARK: - F44: one calendar change, one refresh

    func testOneEditIsHandledAsOneSingleRecordRefresh() {
        var pending = CalendarPendingContentRefresh()
        pending.generationBumps += 1
        pending.updates.append(CalendarContentUpdate(source: .meeting("m1")))
        XCTAssertEqual(pending.incrementalSource, .meeting("m1"))
        XCTAssertEqual(pending.pulseSource, .meeting("m1"))
    }

    func testSeveralChangesInOneTurnRebuildEverything() {
        var twoUpdates = CalendarPendingContentRefresh()
        twoUpdates.generationBumps = 2
        twoUpdates.updates = [
            CalendarContentUpdate(source: .meeting("m1")),
            CalendarContentUpdate(source: .travel("t1")),
        ]
        XCTAssertNil(twoUpdates.incrementalSource)
        XCTAssertEqual(twoUpdates.pulseSource, .travel("t1"))

        var generationOnly = CalendarPendingContentRefresh()
        generationOnly.generationBumps = 1
        XCTAssertNil(generationOnly.incrementalSource)
        XCTAssertNil(generationOnly.pulseSource)

        var extraChange = CalendarPendingContentRefresh()
        extraChange.generationBumps = 2
        extraChange.updates = [CalendarContentUpdate(source: .meeting("m1"))]
        XCTAssertNil(extraChange.incrementalSource, "en ändring från annat håll i samma varv kräver full omräkning")
    }

    func testADeletionDoesNotHighlightTheRemovedEvent() {
        var pending = CalendarPendingContentRefresh()
        pending.generationBumps = 1
        pending.updates = [CalendarContentUpdate(source: .meeting("m1"), pulses: false)]
        XCTAssertEqual(pending.incrementalSource, .meeting("m1"))
        XCTAssertNil(pending.pulseSource)
    }

    @MainActor
    func testDeletingAMeetingNamesTheRemovedRecordForTheCalendar() throws {
        let store = GrantDataStore(skipInitialMigration: true)
        try store.persistAll()
        let meeting = CalendarMeetingRecord(id: "meeting-1", date: "2027-02-10", title: "Möte")
        store.autosaveCalendarMeetingRecords([meeting])
        XCTAssertTrue(store.flushPendingMetadataPersistenceIfNeeded())
        store.calendarContentUpdate = nil
        let generationBefore = store.calendarContentGeneration

        XCTAssertTrue(store.deleteCalendarEvent(source: .meeting("meeting-1")))

        XCTAssertEqual(store.calendarContentGeneration, generationBefore + 1, "exakt en ändringssignal från metadata")
        XCTAssertEqual(store.calendarContentUpdate?.source, .meeting("meeting-1"))
        XCTAssertEqual(store.calendarContentUpdate?.pulses, false)
        XCTAssertTrue(store.calendarMeetingRecords.isEmpty)
    }

    @MainActor
    func testAnEditStillPulsesTheEditedRecord() {
        let original = CalendarMeetingRecord(id: "meeting-1", date: "2027-02-10", title: "Möte")
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarMeetingRecords = [original]
        let store = GrantDataStore(metadata: metadata, skipInitialMigration: true)
        let generationBefore = store.calendarContentGeneration
        var updated = original
        updated.date = "2027-02-11"

        store.autosaveCalendarMeetingRecords([updated])

        XCTAssertEqual(store.calendarContentGeneration, generationBefore + 1)
        XCTAssertEqual(store.calendarContentUpdate?.source, .meeting("meeting-1"))
        XCTAssertEqual(store.calendarContentUpdate?.pulses, true)
    }

    @MainActor
    func testARecentVerifiedBackupInMemorySkipsTheBackupRound() {
        let store = GrantDataStore(skipInitialMigration: true)
        let now = Date()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("IDFirstReaderTests-backup", isDirectory: true)

        store.backupSnapshotsCache = nil
        XCTAssertFalse(store.hasRecentVerifiedPeriodicBackupInMemory(now: now), "okänt läge: gör som förut")

        store.backupSnapshotsCache = [GrantDataStore.BackupSnapshot(url: url, date: now.addingTimeInterval(-5 * 60), isVerified: true)]
        XCTAssertTrue(store.hasRecentVerifiedPeriodicBackupInMemory(now: now))

        store.backupSnapshotsCache = [GrantDataStore.BackupSnapshot(url: url, date: now.addingTimeInterval(-20 * 60), isVerified: true)]
        XCTAssertFalse(store.hasRecentVerifiedPeriodicBackupInMemory(now: now), "en backup är på väg att behövas")

        store.backupSnapshotsCache = [GrantDataStore.BackupSnapshot(url: url, date: now.addingTimeInterval(-5 * 60), isVerified: false)]
        XCTAssertFalse(store.hasRecentVerifiedPeriodicBackupInMemory(now: now), "en overifierad backup räknas inte")
    }
}
