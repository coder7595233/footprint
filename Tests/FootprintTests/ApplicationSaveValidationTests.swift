import XCTest
@testable import Footprint

/// F19: dates in the wrong order on an application are flagged after the
/// edit is saved, also for a call that is still open ("Att söka"), which the
/// Data view otherwise leaves alone until it closes.
final class ApplicationSaveValidationTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ApplicationSaveValidationTests-\(UUID().uuidString)", isDirectory: true)
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
    private func store(with application: GrantApplication) -> GrantDataStore {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = "sv"
        return GrantDataStore(applications: [application], metadata: metadata, skipInitialMigration: true)
    }

    private static var nextYear: Int {
        Calendar.current.component(.year, from: Date()) + 1
    }

    @MainActor
    private func assertReversedDispositionIsFlagged(
        _ application: GrantApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let testStore = store(with: application)
        _ = testStore.missingFieldIssues()

        var edited = application
        edited.firstDispositionOn = "\(Self.nextYear + 1)-01-01"
        edited.lastDispositionOn = "\(Self.nextYear)-12-31"
        testStore.autosave(application: edited)
        testStore.runSaveValidation()

        XCTAssertEqual(
            testStore.applications.first?.lastDispositionOn,
            "\(Self.nextYear)-12-31",
            "the save is never stopped",
            file: file,
            line: line
        )
        XCTAssertEqual(testStore.notice?.tone, .info, file: file, line: line)
        XCTAssertTrue(
            testStore.notice?.message.contains("Sista disponering före första disponering") == true,
            testStore.notice?.message ?? "no notice",
            file: file,
            line: line
        )
    }

    @MainActor
    func testGrantedApplicationWithLastDispositionFirstIsFlagged() {
        assertReversedDispositionIsFlagged(
            GrantApplication(
                id: "granted",
                rowNumber: 1,
                organization: "Stiftelsen",
                grantName: "Projektbidrag",
                firstDispositionOn: "\(Self.nextYear)-01-01",
                lastDispositionOn: "\(Self.nextYear + 1)-12-31",
                appliedOn: "2025-03-01",
                grantedOn: "2025-11-01",
                result: "Beviljat"
            )
        )
    }

    @MainActor
    func testOpenCallWithLastDispositionFirstIsFlagged() {
        assertReversedDispositionIsFlagged(
            GrantApplication(
                id: "open-call",
                rowNumber: 1,
                organization: "Stiftelsen",
                grantName: "Projektbidrag",
                closesOn: "\(Self.nextYear)-06-30",
                result: "Att söka"
            )
        )
    }

    @MainActor
    func testOpenCallIsStillNotListedForMissingFields() {
        let testStore = store(
            with: GrantApplication(
                id: "open-call",
                rowNumber: 1,
                organization: "Stiftelsen",
                grantName: "Projektbidrag",
                closesOn: "\(Self.nextYear)-06-30",
                result: "Att söka"
            )
        )
        XCTAssertFalse(
            testStore.missingFieldIssues(includeHidden: true).contains { $0.recordID == "open-call" },
            "an open call is not expected to be complete"
        )
    }
}
