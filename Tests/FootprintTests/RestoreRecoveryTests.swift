import XCTest
@testable import Footprint

/// Regression tests for the 2026-08-17 review round: undo baselines while a
/// silent metadata write is pending, maintenance-marker fallbacks surviving a
/// restore, and restore as the recovery path out of a blocked-writes state.
final class RestoreRecoveryTests: XCTestCase {
    private var storageDirectory: URL!

    // Storage isolation is NOT automatic under this test runner — a store
    // without this override reads and writes the user's real database.
    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RestoreRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        setenv("FOOTPRINT_STORAGE_DIRECTORY", storageDirectory.path, 1)
    }

    override func tearDown() {
        GrantDataStore.clearMaintenanceMarkerFallbacks()
        unsetenv("FOOTPRINT_STORAGE_DIRECTORY")
        if let storageDirectory {
            try? FileManager.default.removeItem(at: storageDirectory)
        }
        storageDirectory = nil
        super.tearDown()
    }

    @MainActor
    func testUndoBaselineReflectsPendingMetadataEdit() throws {
        let store = GrantDataStore()
        try store.persistAll()

        var metadata = store.editableMetadataSnapshot
        var meetings = metadata.calendarMeetingRecords ?? []
        meetings.append(CalendarMeetingRecord(
            id: "pending-meeting",
            date: "2026-08-17",
            title: "Pending calendar edit"
        ))
        metadata.calendarMeetingRecords = meetings
        store.persistMetadataSilently(metadata)

        // The metadata write is still pending; a baseline taken from the
        // document cache would miss the meeting and a later undo would
        // silently revert it.
        let baseline = try store.persistedBaselineDocumentStates(for: [.calendarMeetingRecords])
        guard let meetingState = baseline.first(where: { $0.storageKey == "calendar_meeting_records" }) else {
            return XCTFail("baseline is missing the calendar meeting document")
        }
        let decoded = try JSONDecoder().decode([CalendarMeetingRecord].self, from: meetingState.data)
        XCTAssertTrue(
            decoded.contains(where: { $0.id == "pending-meeting" }),
            "the undo baseline must include the pending silent-metadata edit"
        )
        _ = store.flushPendingMetadataPersistenceIfNeeded()
    }

    @MainActor
    func testExpeditedMetadataPersistenceWritesWithoutBlockingFlush() async throws {
        let store = GrantDataStore()
        try store.persistAll()

        var metadata = store.editableMetadataSnapshot
        metadata.lastSelectedTab = "projects"
        store.persistMetadataSilently(metadata)
        store.expeditePendingMetadataPersistence()

        // The write runs on the persistence queue; the expedite call itself
        // must not block, and the data must land without a synchronous flush.
        let deadline = Date().addingTimeInterval(5)
        var storedTab: String?
        while Date() < deadline {
            let sqliteStore = try SQLiteDocumentStore(url: GrantDataStore.databaseURL)
            storedTab = try sqliteStore.load(DataSourceMetadata.self, named: "metadata")?.lastSelectedTab
            if storedTab == "projects" { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(storedTab, "projects")
    }

    @MainActor
    func testBulkArchiveDeletionRemovesSelectionAsOneUndoableStep() throws {
        let store = GrantDataStore(projects: [
            ProjectRecord(id: "bulk-a", nameSv: "Bulk A", nameEn: "Bulk A"),
            ProjectRecord(id: "bulk-b", nameSv: "Bulk B", nameEn: "Bulk B"),
        ])
        try store.persistAll()
        store.deleteProject(id: "bulk-a")
        store.deleteProject(id: "bulk-b")
        let archived = try store.loadArchivedRecords()
        XCTAssertEqual(archived.count, 2)

        store.permanentlyDeleteArchivedRecords(ids: Set(archived.map(\.id)))

        XCTAssertTrue(try store.loadArchivedRecords().isEmpty)
        XCTAssertEqual(store.notice?.tone, .success)

        // One undo step restores the whole selection.
        store.undoManager.undo()
        XCTAssertEqual(try store.loadArchivedRecords().count, 2)
    }

    @MainActor
    func testRestoreClearsMaintenanceMarkerFallbacks() throws {
        let seededStore = GrantDataStore(projects: [
            ProjectRecord(id: "restore-marker-project", nameSv: "Projekt", nameEn: "Project"),
        ])
        try seededStore.persistAll()
        let snapshot = seededStore.currentSnapshot()

        let defaults = UserDefaults.standard
        defaults.set("v99", forKey: GrantDataStore.startupMaintenanceMarkerDefaultsKey)
        defaults.set("v99", forKey: GrantDataStore.deferredLaunchMaintenanceMarkerDefaultsKey)
        try Data("v99".utf8).write(to: GrantDataStore.startupMaintenanceMarkerURL)
        try Data("v99".utf8).write(to: GrantDataStore.deferredLaunchMaintenanceMarkerURL)

        _ = try GrantDataStore.writeRestorePayloadToStorage(
            .init(snapshot: snapshot, archivedRecords: [], receivedGrantsData: nil),
            expectedReport: GrantDataStore.healthReport(for: snapshot)
        )

        XCTAssertNil(
            defaults.string(forKey: GrantDataStore.startupMaintenanceMarkerDefaultsKey),
            "restore must clear the startup marker fallback so maintenance re-runs"
        )
        XCTAssertNil(
            defaults.string(forKey: GrantDataStore.deferredLaunchMaintenanceMarkerDefaultsKey),
            "restore must clear the deferred-launch marker fallback so migrations re-run"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: GrantDataStore.startupMaintenanceMarkerURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: GrantDataStore.deferredLaunchMaintenanceMarkerURL.path))
    }

    @MainActor
    func testRestoreRecoversFromBlockedWritesAndClearsGate() async throws {
        // A valid backup taken from healthy data.
        let seededStore = GrantDataStore(projects: [
            ProjectRecord(id: "recovery-project", nameSv: "Projekt", nameEn: "Project"),
        ])
        try seededStore.persistAll()
        let backupURL = try GrantDataStore.createForcedBackupSnapshot(
            snapshot: seededStore.currentSnapshot(),
            archivedRecords: [],
            receivedGrantsData: nil,
            prefix: "recovery-test"
        )

        // Damage the database so the next load blocks writes.
        try Data("not a sqlite database".utf8).write(to: GrantDataStore.databaseURL)
        try? FileManager.default.removeItem(at: GrantDataStore.databaseWALURL)
        try? FileManager.default.removeItem(at: GrantDataStore.databaseSHMURL)

        let store = GrantDataStore.loadFromBundle()
        XCTAssertTrue(store.storageWritesBlockedByLoadFailure)

        // Bootstrap has already posted a load-failure notice; clear it so the
        // wait below observes the restore's own outcome.
        store.notice = nil
        store.loadError = nil
        store.restoreFromBackupAsync(directoryURL: backupURL)
        let deadline = Date().addingTimeInterval(15)
        while store.notice == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(store.notice?.tone, .success, store.notice?.message ?? "no notice")
        XCTAssertFalse(
            store.storageWritesBlockedByLoadFailure,
            "a verified restore must lift the load-failure write gate"
        )
        XCTAssertEqual(store.projects.map(\.id), ["recovery-project"])
        XCTAssertFalse(
            store.undoManager.canUndo,
            "no undo into the empty pre-restore memory may be registered"
        )
        XCTAssertNoThrow(try store.persistAll())
    }
}
