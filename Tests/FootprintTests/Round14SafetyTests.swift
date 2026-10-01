import XCTest
@testable import Footprint

/// Round 14 (attachments, repeated repairs, locked records, editors, old
/// decisions, export folder). All names and values below are made up.
final class Round14SafetyTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Round14SafetyTests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: Attachment locations from the database

    func testStoredAttachmentLocationsStayInsideStorageOrArePDFs() {
        let root = GrantDataStore.storageDirectory.standardizedFileURL.path
        let inside = GrantDataStore.absoluteAttachmentURL(fromStored: "Publication PDFs/abc.pdf")
        XCTAssertEqual(inside?.path, root + "/Publication PDFs/abc.pdf")

        XCTAssertNil(GrantDataStore.absoluteAttachmentURL(fromStored: "../../outside/secret.txt"), "relative path leaving storage")
        XCTAssertNil(GrantDataStore.absoluteAttachmentURL(fromStored: "/tmp/invented/notes.txt"), "absolute non-PDF")
        XCTAssertNil(GrantDataStore.absoluteAttachmentURL(fromStored: "/Applications/Invented.app"), "an app")
        XCTAssertEqual(
            GrantDataStore.absoluteAttachmentURL(fromStored: "/tmp/invented/paper.pdf")?.path,
            "/tmp/invented/paper.pdf",
            "an older record pointing at a PDF elsewhere still works"
        )
        XCTAssertNil(GrantDataStore.absoluteAttachmentURL(fromStored: "   "))
    }

    func testTemporaryPDFNameCannotLeaveTheTemporaryFolder() {
        XCTAssertEqual(safeTemporaryPDFFilename("../../../Library/LaunchAgents/x.plist", fallback: "file.pdf"), "x.pdf")
        XCTAssertEqual(safeTemporaryPDFFilename("Invented certificate.pdf", fallback: "file.pdf"), "Invented certificate.pdf")
        XCTAssertEqual(safeTemporaryPDFFilename("page.html", fallback: "file.pdf"), "page.pdf")
        XCTAssertEqual(safeTemporaryPDFFilename(nil, fallback: "review-certificate.pdf"), "review-certificate.pdf")
        XCTAssertEqual(safeTemporaryPDFFilename("..", fallback: "publication.pdf"), "publication.pdf")
    }

    func testOnlyRealPDFsAreLoadedForOpening() throws {
        let folder = storageDirectory.appendingPathComponent("open-check", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let script = folder.appendingPathComponent("run.command")
        try Data("echo invented".utf8).write(to: script)
        XCTAssertThrowsError(try loadPDFDataForUserAction(from: script))

        let fakePDF = folder.appendingPathComponent("fake.pdf")
        try Data("<html>invented</html>".utf8).write(to: fakePDF)
        XCTAssertThrowsError(try loadPDFDataForUserAction(from: fakePDF))

        let realPDF = folder.appendingPathComponent("real.pdf")
        try Data("%PDF-1.4 invented".utf8).write(to: realPDF)
        XCTAssertNoThrow(try loadPDFDataForUserAction(from: realPDF))
    }

    // MARK: Old decided records without a decision date

    func testOldGrantedRecordWithoutDecisionDateStaysGranted() throws {
        let json = """
        {"id":"old-1","rowNumber":1,"organization":"Invented Fund","grantName":"Invented grant",
         "result":"Beviljat","appliedOn":"2020-02-01","decisionExpectedOn":"2020-06-01",
         "grantedAmount":"100 000","grantedAmountValue":100000}
        """
        let application = try JSONDecoder().decode(GrantApplication.self, from: Data(json.utf8))
        XCTAssertEqual(application.resultLabel, "Beviljat")
        XCTAssertEqual(application.grantedOn, "2020-06-01")
        XCTAssertTrue(application.grantedOnUncertain)
        var refreshed = application
        refreshed.refreshDerivedValues()
        XCTAssertEqual(refreshed.resultLabel, "Beviljat")
        XCTAssertEqual(refreshed.grantedAmountValue, 100_000, "the granted amount is kept")
    }

    func testOldDeclinedRecordFallsBackToTheAppliedDate() throws {
        let json = """
        {"id":"old-2","rowNumber":2,"organization":"Invented Fund","grantName":"Invented grant",
         "result":"Avslag","appliedOn":"2021-03-01"}
        """
        let application = try JSONDecoder().decode(GrantApplication.self, from: Data(json.utf8))
        XCTAssertEqual(application.resultLabel, "Avslag")
        XCTAssertEqual(application.deniedOn, "2021-03-01")
    }

    func testRecordWithDecisionDateIsUnchanged() throws {
        let json = """
        {"id":"old-3","rowNumber":3,"organization":"Invented Fund","grantName":"Invented grant",
         "result":"Beviljat","appliedOn":"2022-01-10","grantedOn":"2022-05-05"}
        """
        let application = try JSONDecoder().decode(GrantApplication.self, from: Data(json.utf8))
        XCTAssertEqual(application.grantedOn, "2022-05-05")
        XCTAssertFalse(application.grantedOnUncertain)
    }

    // MARK: Locked records in the translation list

    @MainActor
    func testLockedProjectIsNotOfferedForTranslation() {
        var locked = ProjectRecord(id: "locked-1", nameSv: "Påhittat låst projekt", nameEn: "")
        locked.isEditingLocked = true
        let open = ProjectRecord(id: "open-1", nameSv: "Påhittat öppet projekt", nameEn: "")
        let store = GrantDataStore(projects: [locked, open])
        let projectIssueIDs = Set(
            store.translationIssues(includeHidden: true)
                .filter { $0.kind == .project }
                .map(\.recordID)
        )
        XCTAssertFalse(projectIssueIDs.contains("locked-1"))
        XCTAssertTrue(projectIssueIDs.contains("open-1"))
    }

    // MARK: Copy of data to a folder

    func testCopyToAFolderIsOffUntilChosen() {
        let defaults = UserDefaults.standard
        let enabledKey = FootprintExportWriter.enabledDefaultsKey
        let folderKey = FootprintExportWriter.folderDefaultsKey
        let previousEnabled = defaults.object(forKey: enabledKey)
        let previousFolder = defaults.object(forKey: folderKey)
        defer {
            defaults.set(previousEnabled, forKey: enabledKey)
            defaults.set(previousFolder, forKey: folderKey)
        }
        defaults.removeObject(forKey: enabledKey)
        defaults.removeObject(forKey: folderKey)
        XCTAssertFalse(FootprintExportWriter.isSwitchedOn)
        XCTAssertNil(FootprintExportWriter.chosenFolder)
        XCTAssertFalse(FootprintExportWriter.shared.isEnabled, "off by default")

        FootprintExportWriter.shared.configure(enabled: true, folder: URL(fileURLWithPath: "/tmp/invented-export", isDirectory: true))
        XCTAssertTrue(FootprintExportWriter.isSwitchedOn)
        XCTAssertEqual(FootprintExportWriter.chosenFolder?.path, "/tmp/invented-export")
        XCTAssertFalse(FootprintExportWriter.shared.isEnabled, "a test run never exports")
    }
}
