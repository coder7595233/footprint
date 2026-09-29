import XCTest
@testable import Footprint

/// The write gate after a failed load is the app's most important data-loss
/// guard: persistence is whole-document overwrite, so a save issued after a
/// failed load would replace good on-disk data with the empty in-memory state.
final class StorageWriteGateTests: XCTestCase {
    private var storageDirectory: URL!

    // Storage isolation is NOT automatic under this test runner — a store
    // without this override reads and writes the user's real database.
    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorageWriteGateTests-\(UUID().uuidString)", isDirectory: true)
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

    @MainActor
    func testUnloadableDatabaseBlocksEveryPersistencePath() throws {
        let corruptBytes = Data("not a sqlite database, but it is the user's data".utf8)
        try corruptBytes.write(to: GrantDataStore.databaseURL)

        let store = GrantDataStore.loadFromBundle()

        XCTAssertTrue(store.storageWritesBlockedByLoadFailure)
        XCTAssertNotNil(store.loadError)

        XCTAssertThrowsError(try store.persistAll())
        XCTAssertThrowsError(try store.persist(.publicationJournals))
        XCTAssertThrowsError(try store.saveArchivedRecords([]))

        store.loadError = nil
        var metadata = store.metadata
        metadata.lastSelectedTab = "projects"
        store.persistMetadataSilently(metadata)
        XCTAssertNotNil(store.loadError, "gated metadata persistence must surface an error")
        _ = store.flushPendingMetadataPersistenceIfNeeded()

        // A real user action that persists through the undoable/deferred path.
        store.loadError = nil
        _ = store.addPublicationJournal()
        XCTAssertNotNil(store.loadError, "gated undoable change must surface an error")
        store.flushPendingPersistenceIfNeeded()

        XCTAssertEqual(
            try Data(contentsOf: GrantDataStore.databaseURL),
            corruptBytes,
            "no persistence path may touch the unloadable database"
        )
    }

    @MainActor
    func testPersistenceStorageKeysMatchEncodedDocuments() throws {
        let store = GrantDataStore()
        let sets: [GrantDataStore.PersistenceSet] = [
            .allCoreData,
            [.publicationJournals],
            [.metadata],
            [.organizations],
            [.projects, .applications],
            [.calendarMeetingRecords],
            [.teachingAssignments, .teachingCourses],
            [.cvReviewEntries, .cvOtherPublications],
            [.appSettings],
            [.publicationJournals, .publicationRecords, .cvConferenceContributions, .cvReviewEntries],
        ]
        for set in sets {
            let encodedKeys = try store.encodedSQLiteDocuments(for: set).map(\.0)
            XCTAssertEqual(
                encodedKeys,
                GrantDataStore.persistenceStorageKeys(for: set),
                "the undo-baseline key list must mirror encodedPersistenceDocuments exactly"
            )
        }
    }

    @MainActor
    func testUndoBaselineFromCacheRestoresPreEditState() throws {
        let seededStore = GrantDataStore()
        let journalID = seededStore.addPublicationJournal()
        guard var journal = seededStore.publicationJournals.first(where: { $0.id == journalID }) else {
            return XCTFail("journal was not created")
        }
        let originalName = journal.name

        journal.name = "Baseline Regression Journal"
        seededStore.savePublicationJournal(journal, previousName: originalName)
        XCTAssertEqual(
            seededStore.publicationJournals.first(where: { $0.id == journalID })?.name,
            "Baseline Regression Journal"
        )

        seededStore.undoManager.undo()
        XCTAssertEqual(
            seededStore.publicationJournals.first(where: { $0.id == journalID })?.name,
            originalName,
            "undo must restore the exact pre-edit state from the cached baseline"
        )
    }

    @MainActor
    func testHealthyDatabaseKeepsWritesEnabled() throws {
        let seededStore = GrantDataStore(projects: [
            ProjectRecord(id: "write-gate-project", nameSv: "Projekt", nameEn: "Project"),
        ])
        try seededStore.persistAll()

        let store = GrantDataStore.loadFromBundle()

        XCTAssertFalse(store.storageWritesBlockedByLoadFailure)
        XCTAssertNoThrow(try store.persistAll())
    }
}
