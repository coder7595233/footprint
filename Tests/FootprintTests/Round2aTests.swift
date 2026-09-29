import XCTest
@testable import Footprint

final class Round2aTests: XCTestCase {
    private var storageDirectory: URL!

    // F34: every test gets its own storage folder, as in the other suites, so
    // no test can write over records another test (or the user) left behind.
    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Round2aTests-\(UUID().uuidString)", isDirectory: true)
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

    func testReviewRoundRoundTripsAndShowsInListTitle() throws {
        var entry = CVReviewEntry(id: "r1", category: .journalReview, journalName: "BMC Geriatrics", subjectTitle: "A manuscript", reviewRound: "R1")
        entry.normalize()
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(CVReviewEntry.self, from: data)
        XCTAssertEqual(decoded.reviewRound, "R1")
        XCTAssertTrue(decoded.listTitle.contains("R1"))
    }

    func testLegacyReviewEntryWithoutReviewRoundDecodes() throws {
        let json = #"{"id":"r2","date":"2026-01-01","category":"journalReview","subjectTitle":"Old row"}"#
        let decoded = try JSONDecoder().decode(CVReviewEntry.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.reviewRound, "")
    }

    @MainActor
    func testOverdueTasksAreNotIntegrityIssues() {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.taskItems = [TaskItem(id: "task-9", deadline: "2000-01-01", comment: "Gammal uppgift")]
        let store = GrantDataStore(metadata: metadata)
        XCTAssertTrue(store.integrityIssues(includeHidden: true).allSatisfy { !$0.subtitle.contains("Overdue") && !$0.subtitle.contains("Försenad") })
        XCTAssertFalse(store.dataQualityIntegrityIssues().filter { $0.subtitle.contains("Overdue") }.isEmpty)
    }
}
