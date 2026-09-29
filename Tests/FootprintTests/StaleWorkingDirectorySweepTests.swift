import XCTest
@testable import Footprint

final class StaleWorkingDirectorySweepTests: XCTestCase {
    private var storageDirectory: URL!

    // Storage isolation is NOT automatic under this test runner — a store
    // without this override reads and writes the user's real database.
    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StaleWorkingDirectorySweepTests-\(UUID().uuidString)", isDirectory: true)
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

    func testSweepRemovesOnlyStaleAppOwnedWorkingDirectories() throws {
        let fileManager = FileManager.default
        let now = Date()
        let staleDate = now.addingTimeInterval(-10 * 24 * 3600)
        let backups = storageDirectory.appendingPathComponent("Backups", isDirectory: true)
        let quarantine = backups.appendingPathComponent("Recovery Quarantine", isDirectory: true)

        func makeDirectory(_ url: URL, modifiedAt date: Date?) throws {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            if let date {
                try fileManager.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
            }
        }

        let staleAttachmentStaging = storageDirectory.appendingPathComponent(".attachment-snapshot-OLD")
        let freshAttachmentStaging = storageDirectory.appendingPathComponent(".attachment-snapshot-NEW")
        let staleBackupStaging = backups.appendingPathComponent(".20260101-000000.backup-in-progress-OLD")
        let staleQuarantine = quarantine.appendingPathComponent("20250101-000000-quarantine")
        let realBackup = backups.appendingPathComponent("20260101-000000")
        let attachmentDirectory = storageDirectory.appendingPathComponent("Publication PDFs")

        try makeDirectory(staleAttachmentStaging, modifiedAt: staleDate)
        try makeDirectory(freshAttachmentStaging, modifiedAt: nil)
        try makeDirectory(staleBackupStaging, modifiedAt: staleDate)
        try makeDirectory(staleQuarantine, modifiedAt: now.addingTimeInterval(-60 * 24 * 3600))
        try makeDirectory(realBackup, modifiedAt: staleDate)
        try makeDirectory(attachmentDirectory, modifiedAt: staleDate)

        GrantDataStore.sweepStaleWorkingDirectories(now: now)

        XCTAssertFalse(fileManager.fileExists(atPath: staleAttachmentStaging.path), "stale staging must be removed")
        XCTAssertFalse(fileManager.fileExists(atPath: staleBackupStaging.path), "stale backup staging must be removed")
        XCTAssertFalse(fileManager.fileExists(atPath: staleQuarantine.path), "old quarantine must be removed")
        XCTAssertTrue(fileManager.fileExists(atPath: freshAttachmentStaging.path), "fresh staging may be in flight")
        XCTAssertTrue(fileManager.fileExists(atPath: realBackup.path), "real backups are never touched")
        XCTAssertTrue(fileManager.fileExists(atPath: attachmentDirectory.path), "attachment directories are never touched")
    }
}
