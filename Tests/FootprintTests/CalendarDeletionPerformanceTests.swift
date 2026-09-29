import SQLite3
import XCTest
@testable import Footprint

/// Deleting one calendar meeting, travel or hotel stay must only touch the
/// calendar: no whole-store undo snapshot, no synchronous rewrite of other
/// registers, no re-derivation of applications, projects or publications.
/// The real store holds ~1,800 meetings; before this was fixed every single
/// deletion encoded and rewrote several megabytes on the main thread.
final class CalendarDeletionPerformanceTests: XCTestCase {
    private var storageDirectory: URL!

    // Storage isolation is NOT automatic under this test runner — a store
    // without this override reads and writes the user's real database.
    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CalendarDeletionPerformanceTests-\(UUID().uuidString)", isDirectory: true)
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

    private static let meetingCount = 2_000

    private static let unrelatedDocumentKeys = [
        "applications",
        "organizations",
        "projects",
        "publication_records",
        "publication_authors",
        "publication_journals",
        "teaching_assignments",
    ]

    @MainActor
    private func makeStoreWithManyMeetings() throws -> (GrantDataStore, [CalendarMeetingRecord]) {
        let organization = OrganizationRecord(id: "organization-1", nameSv: "Organisation", nameEn: "Organization")
        let project = ProjectRecord(id: "project-1", nameSv: "Projekt", nameEn: "Project")
        let publication = PublicationRecord(id: "publication-1", title: "Publication")
        let store = GrantDataStore(
            organizations: [organization],
            projects: [project],
            publicationRecords: [publication],
            skipInitialMigration: true
        )
        XCTAssertNotNil(store.sqliteStore, "the test needs a real SQLite store in the temp directory")
        try store.persistAll()

        let meetings = (0..<Self.meetingCount).map { index in
            CalendarMeetingRecord(
                id: "meeting-\(index)",
                date: String(format: "2026-%02ld-%02ld", index % 12 + 1, index % 28 + 1),
                title: "Meeting \(index)"
            )
        }
        store.autosaveCalendarMeetingRecords(meetings)
        XCTAssertTrue(store.flushPendingMetadataPersistenceIfNeeded())
        store.undoManager.removeAllActions()
        XCTAssertEqual(store.calendarMeetingRecords.count, Self.meetingCount)
        XCTAssertEqual(try storedMeetingIDs().count, Self.meetingCount)
        return (store, meetings)
    }

    @MainActor
    func testDeletingOneMeetingAmongTwoThousandTouchesOnlyTheCalendar() throws {
        let (store, meetings) = try makeStoreWithManyMeetings()
        let target = meetings[1_000]

        let persistCountBefore = store.synchronousPersistCount
        let applicationRowsBefore = store.applicationRowSnapshotGeneration
        let projectRowsBefore = store.projectRowSnapshotGeneration
        let organizationRowsBefore = store.organizationRowSnapshotGeneration
        let authorRowsBefore = store.publicationAuthorRowSnapshotGeneration
        let searchBefore = store.workspaceSearchGeneration
        let calendarBefore = store.calendarContentGeneration
        let updatedAtBefore = try documentUpdatedAt()

        let startedAt = CFAbsoluteTimeGetCurrent()
        XCTAssertTrue(store.deleteCalendarEvent(source: .meeting(target.id)))
        let elapsed = CFAbsoluteTimeGetCurrent() - startedAt

        // Generous: the old path took well over this on real data; the new
        // one only filters one list and queues a background write.
        XCTAssertLessThan(elapsed, 1.0, "deleting one meeting took \(elapsed) s")
        XCTAssertFalse(store.calendarMeetingRecords.contains { $0.id == target.id })
        XCTAssertEqual(store.calendarMeetingRecords.count, Self.meetingCount - 1)

        // Nothing was persisted synchronously and nothing outside the
        // calendar was re-derived.
        XCTAssertEqual(store.synchronousPersistCount, persistCountBefore)
        XCTAssertEqual(store.applicationRowSnapshotGeneration, applicationRowsBefore)
        XCTAssertEqual(store.projectRowSnapshotGeneration, projectRowsBefore)
        XCTAssertEqual(store.organizationRowSnapshotGeneration, organizationRowsBefore)
        XCTAssertEqual(store.publicationAuthorRowSnapshotGeneration, authorRowsBefore)
        XCTAssertEqual(store.workspaceSearchGeneration, searchBefore)
        XCTAssertNotEqual(store.calendarContentGeneration, calendarBefore)

        // The queued write reaches disk with only the calendar changed.
        XCTAssertTrue(store.flushPendingMetadataPersistenceIfNeeded())
        let storedIDs = try storedMeetingIDs()
        XCTAssertEqual(storedIDs.count, Self.meetingCount - 1)
        XCTAssertFalse(storedIDs.contains(target.id))
        XCTAssertEqual(try relationalMeetingCount(), Self.meetingCount - 1)

        let updatedAtAfter = try documentUpdatedAt()
        for key in Self.unrelatedDocumentKeys {
            XCTAssertEqual(updatedAtAfter[key], updatedAtBefore[key], "\(key) must not be rewritten")
        }
        XCTAssertNotEqual(updatedAtAfter["calendar_meeting_records"], updatedAtBefore["calendar_meeting_records"])

        // Undo brings the meeting back, in memory and on disk.
        XCTAssertTrue(store.undoManager.canUndo)
        store.undoManager.undo()
        XCTAssertTrue(store.calendarMeetingRecords.contains { $0.id == target.id })
        XCTAssertEqual(store.calendarMeetingRecords.count, Self.meetingCount)
        XCTAssertTrue(store.flushPendingMetadataPersistenceIfNeeded())
        XCTAssertTrue(try storedMeetingIDs().contains(target.id))
        XCTAssertEqual(try relationalMeetingCount(), Self.meetingCount)

        // Redo removes it again.
        XCTAssertTrue(store.undoManager.canRedo)
        store.undoManager.redo()
        XCTAssertFalse(store.calendarMeetingRecords.contains { $0.id == target.id })
        XCTAssertTrue(store.flushPendingMetadataPersistenceIfNeeded())
        XCTAssertFalse(try storedMeetingIDs().contains(target.id))
    }

    /// Undo right after the queued write reached the database, but before its
    /// completion updated the in-memory document cache, must still write the
    /// restored meeting back.
    @MainActor
    func testUndoWhileTheDeletionWriteIsInFlightRestoresTheMeetingOnDisk() throws {
        let (store, meetings) = try makeStoreWithManyMeetings()
        let target = meetings[42]

        XCTAssertTrue(store.deleteCalendarEvent(source: .meeting(target.id)))
        // Start the queued write now; its main-queue completion cannot run
        // before the undo below, which runs synchronously on this thread.
        store.expeditePendingMetadataPersistence()
        store.undoManager.undo()

        XCTAssertTrue(store.calendarMeetingRecords.contains { $0.id == target.id })
        XCTAssertTrue(store.flushPendingMetadataPersistenceIfNeeded())
        XCTAssertTrue(try storedMeetingIDs().contains(target.id), "undo must reach disk")
        XCTAssertEqual(try storedMeetingIDs().count, Self.meetingCount)
        XCTAssertEqual(try relationalMeetingCount(), Self.meetingCount)
    }

    @MainActor
    func testDeletingTravelAndHotelStaysInTheCalendarScopeAndUndoes() throws {
        let store = GrantDataStore(skipInitialMigration: true)
        try store.persistAll()
        let travel = CalendarTravelRecord(id: "travel-1", date: "2027-02-11", toCity: "Oslo")
        let accommodation = CalendarAccommodationRecord(id: "hotel-1", hotelName: "Hotel", checkInDate: "2027-02-11")
        store.autosaveCalendarTravelRecords([travel])
        store.autosaveCalendarAccommodationRecords([accommodation])
        XCTAssertTrue(store.flushPendingMetadataPersistenceIfNeeded())
        store.undoManager.removeAllActions()
        let persistCountBefore = store.synchronousPersistCount

        XCTAssertTrue(store.deleteCalendarEvent(source: .travel(travel.id)))
        XCTAssertTrue(store.deleteCalendarEvent(source: .accommodation(accommodation.id)))
        XCTAssertEqual(store.synchronousPersistCount, persistCountBefore)
        XCTAssertTrue(store.calendarTravelRecords.isEmpty)
        XCTAssertTrue(store.calendarAccommodationRecords.isEmpty)

        store.undoManager.undo()
        XCTAssertEqual(store.calendarAccommodationRecords.map(\.id), [accommodation.id])
        store.undoManager.undo()
        XCTAssertEqual(store.calendarTravelRecords.map(\.id), [travel.id])

        XCTAssertFalse(store.deleteCalendarEvent(source: .travel("missing")))
        XCTAssertFalse(store.deleteCalendarEvent(source: .meeting("missing")))
    }

    // MARK: - Write guard shortcuts keep their answers

    func testEmptyListCheckMatchesAFullParse() {
        let samples = [
            "[]", " [ ] ", "[\n\n]", "\t[\r\n]\n", "[1]", "[{}]", "{}", "", "[", "]",
            "[] x", "x []", "[ ,]", "null", "[{\"id\":\"a\"}]",
        ]
        for sample in samples {
            let data = Data(sample.utf8)
            let parsed = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [Any]
            let expected = parsed?.isEmpty ?? false
            XCTAssertEqual(EmptyDocumentWriteGuard.isEmptyList(data), expected, "sample: \(sample)")
        }
    }

    func testRememberedIDsAreOnlyUsedForIdenticalStoredBytes() throws {
        let key = "cv_review_entries"
        let written = records((1...20).map { "keep-\($0)" })
        // Remember the ids of a write.
        XCTAssertTrue(
            EmptyDocumentWriteGuard.refusedReplacementKeys(
                writing: [(key: key, data: written)],
                existing: { _ in nil }
            ).isEmpty
        )
        // The stored copy was then replaced by something else: the guard must
        // compare against those stored records, not the remembered ones.
        let storedElsewhere = records((1...20).map { "other-\($0)" })
        let refused = EmptyDocumentWriteGuard.refusedReplacementKeys(
            writing: [(key: key, data: written)],
            existing: { _ in storedElsewhere }
        )
        XCTAssertEqual(refused, [key])
        // Stored bytes identical to the remembered write: removing one record
        // is ordinary editing.
        let oneRemoved = records((2...20).map { "keep-\($0)" })
        XCTAssertTrue(
            EmptyDocumentWriteGuard.refusedReplacementKeys(
                writing: [(key: key, data: oneRemoved)],
                existing: { _ in written }
            ).isEmpty
        )
    }

    // MARK: - Helpers

    private func records(_ ids: [String]) -> Data {
        let body = ids.map { "{\"id\":\"\($0)\"}" }.joined(separator: ",")
        return Data("[\(body)]".utf8)
    }

    private func storedMeetingIDs() throws -> [String] {
        let store = try SQLiteDocumentStore(url: GrantDataStore.databaseURL)
        let data = try XCTUnwrap(store.loadData(named: "calendar_meeting_records"))
        return try JSONDecoder().decode([CalendarMeetingRecord].self, from: data).map(\.id)
    }

    private func relationalMeetingCount() throws -> Int? {
        try SQLiteDocumentStore(url: GrantDataStore.databaseURL).relationalTableCounts()["rel_calendar_meetings"]
    }

    private func documentUpdatedAt() throws -> [String: Double] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(GrantDataStore.databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            sqlite3_close_v2(database)
            throw NSError(domain: "CalendarDeletionPerformanceTests", code: 1)
        }
        defer { sqlite3_close_v2(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT key, updated_at FROM documents;", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw NSError(domain: "CalendarDeletionPerformanceTests", code: 2)
        }
        defer { sqlite3_finalize(statement) }
        var result: [String: Double] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let keyPointer = sqlite3_column_text(statement, 0) else { continue }
            result[String(cString: keyPointer)] = sqlite3_column_double(statement, 1)
        }
        return result
    }
}
