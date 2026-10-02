import XCTest
@testable import Footprint

/// Fixes after round 17. All names below are made up.
final class Round18FixesTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Round18FixesTests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: "Aktiva uppgifter" in the project list

    @MainActor
    func testProjectWithLinkedOpenTaskHasActiveTasks() {
        let withTask = ProjectRecord(id: "p-open", nameSv: "Påhittat projekt A", nameEn: "")
        let withDoneTask = ProjectRecord(id: "p-done", nameSv: "Påhittat projekt B", nameEn: "")
        let withoutTask = ProjectRecord(id: "p-none", nameSv: "Påhittat projekt C", nameEn: "")
        var metadata = DataSourceMetadata.bundledDefault
        metadata.taskItems = [
            TaskItem(id: "t-open", deadline: "2099-12-31", comment: "Påhittad uppgift",
                     links: [TaskLink(kind: .project, targetID: "p-open", ownerID: nil)]),
            TaskItem(id: "t-done", deadline: "2020-01-01", comment: "Påhittad klar uppgift",
                     links: [TaskLink(kind: .project, targetID: "p-done", ownerID: nil)],
                     completedOn: "2020-01-02"),
        ]
        let store = GrantDataStore(metadata: metadata, projects: [withTask, withDoneTask, withoutTask])
        let active = Dictionary(uniqueKeysWithValues: store.projectRowSnapshots().map { ($0.id, $0.hasActiveTasks) })
        XCTAssertEqual(active["p-open"], true)
        XCTAssertEqual(active["p-done"], false)
        XCTAssertEqual(active["p-none"], false)
    }
}
