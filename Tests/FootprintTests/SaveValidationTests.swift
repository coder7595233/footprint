import XCTest
@testable import Footprint

/// F19: a save that introduces a wrong value is saved, and then flagged.
final class SaveValidationTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SaveValidationTests-\(UUID().uuidString)", isDirectory: true)
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
    private func makeStore() -> GrantDataStore {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = "sv"
        let assignment = TeachingAssignment(
            id: "a1",
            periods: [TeachingAssignmentPeriod(from: "2026-01-01", to: "2026-06-30")],
            activityName: "Seminarier",
            roles: [TeachingAssignmentRole("Lärare")]
        )
        return GrantDataStore(metadata: metadata, teachingAssignments: [assignment], skipInitialMigration: true)
    }

    @MainActor
    func testAnEndDateBeforeTheStartIsSavedAndFlagged() {
        let store = makeStore()
        _ = store.missingFieldIssues()

        guard var edited = store.teachingAssignments.first(where: { $0.id == "a1" }) else {
            return XCTFail("uppdraget saknas")
        }
        edited.periods = [TeachingAssignmentPeriod(from: "2026-06-30", to: "2026-01-01")]
        store.autosaveTeachingAssignment(edited)
        store.runSaveValidation()

        XCTAssertEqual(store.teachingAssignments.first { $0.id == "a1" }?.periods.first?.to, "2026-01-01", "sparningen stoppades")
        XCTAssertEqual(store.notice?.tone, .info)
        XCTAssertTrue(store.notice?.message.contains("Period slutar före den börjar") == true, store.notice?.message ?? "inget meddelande")
    }

    @MainActor
    func testAnUnrelatedSaveDoesNotRepeatAnOldWarning() {
        let store = makeStore()
        _ = store.missingFieldIssues()
        guard var edited = store.teachingAssignments.first(where: { $0.id == "a1" }) else {
            return XCTFail("uppdraget saknas")
        }
        edited.periods = [TeachingAssignmentPeriod(from: "2026-06-30", to: "2026-01-01")]
        store.autosaveTeachingAssignment(edited)
        store.runSaveValidation()

        store.notice = nil
        edited.comment = "En kommentar"
        store.autosaveTeachingAssignment(edited)
        store.runSaveValidation()
        XCTAssertFalse(store.notice?.message.contains("kontrollera") ?? false, "samma fel ska inte påpekas igen")
    }

    @MainActor
    func testMissingFieldsAreNotWarnedAboutWhileFillingIn() {
        let store = makeStore()
        _ = store.missingFieldIssues()
        guard var edited = store.teachingAssignments.first(where: { $0.id == "a1" }) else {
            return XCTFail("uppdraget saknas")
        }
        edited.periods = []
        store.autosaveTeachingAssignment(edited)
        store.notice = nil
        store.runSaveValidation()
        XCTAssertNil(store.notice, "saknade fält ska bara synas i Data-vyn")
    }

    func testOnlyWrongValuesCountAsCritical() {
        XCTAssertTrue(GrantDataStore.isCriticalDataQualityField("Period slutar före den börjar"))
        XCTAssertTrue(GrantDataStore.isCriticalDataQualityField("DOI-formatet är ogiltigt"))
        XCTAssertFalse(GrantDataStore.isCriticalDataQualityField("Engelskt namn saknas"))
        XCTAssertFalse(GrantDataStore.isCriticalDataQualityField("Undervisningsperioder"))
    }
}
