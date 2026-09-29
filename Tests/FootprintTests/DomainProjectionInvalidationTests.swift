import XCTest
@testable import Footprint

/// The root view and every workspace observe DataStoreDomainProjection
/// revisions instead of the whole store. Any mutation whose UI feedback lives
/// on those surfaces MUST bump the corresponding projection, or the change is
/// invisible until an unrelated render (the "list updates only after switching
/// tabs" class of bug).
final class DomainProjectionInvalidationTests: XCTestCase {
    private var storageDirectory: URL!

    // Storage isolation is NOT automatic under this test runner — a store
    // without this override reads and writes the user's real database.
    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DomainProjectionInvalidationTests-\(UUID().uuidString)", isDirectory: true)
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
    private func makeSeededStore() throws -> GrantDataStore {
        let store = GrantDataStore(projects: [
            ProjectRecord(id: "proj-1", nameSv: "Projekt", nameEn: "Project"),
        ])
        try store.persistAll()
        return store
    }

    @MainActor
    func testPublicationDeletionBumpsPublicationsProjection() throws {
        let store = try makeSeededStore()
        let publicationID = store.addPublication()
        let projection = DataStoreDomainProjection(store: store, domain: .publications)
        let before = projection.revision

        store.deletePublication(id: publicationID)

        XCTAssertGreaterThan(
            projection.revision,
            before,
            "deleting a publication must invalidate the publications workspace"
        )
        XCTAssertFalse(store.publicationRecords.contains(where: { $0.id == publicationID }))
    }

    @MainActor
    func testProjectDeletionBumpsProjectsProjection() throws {
        let store = try makeSeededStore()
        let projection = DataStoreDomainProjection(store: store, domain: .projects)
        let before = projection.revision

        store.deleteProject(id: "proj-1")
        store.confirmDeletionImpactWarning()

        XCTAssertGreaterThan(
            projection.revision,
            before,
            "deleting a project must invalidate the projects workspace"
        )
        XCTAssertFalse(store.projects.contains(where: { $0.id == "proj-1" }))
    }

    @MainActor
    func testLinkingPublicationBecomesVisibleInProjectViewData() async throws {
        let store = try makeSeededStore()

        // The user's exact sequence: view the project first (memoizing an
        // empty resolution), then link a publication to it.
        let emptyBefore = store.projectViewData(forProjectName: "Projekt", language: .swedish)
        XCTAssertEqual(emptyBefore?.relatedPublications.count ?? 0, 0)

        let publicationID = store.addPublication()
        guard var publication = store.publicationRecords.first(where: { $0.id == publicationID }) else {
            return XCTFail("publication was not created")
        }
        publication.projectName = "Projekt"
        store.autosavePublication(publication)

        // The async project-view cache rebuild debounces ~250 ms; the linked
        // publication must become visible without any dirty-marking edit.
        let deadline = Date().addingTimeInterval(5)
        var linkedCount = 0
        while Date() < deadline {
            linkedCount = store.projectViewData(forProjectName: "Projekt", language: .swedish)?
                .relatedPublications.count ?? 0
            if linkedCount > 0 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(
            linkedCount,
            1,
            "a publication linked to a project must appear in the project's view data once the cache rebuild lands"
        )
        _ = store.flushAllPendingPersistenceIfNeeded()
    }

    @MainActor
    func testDeletionImpactWarningReachesTheRootObservationBoundary() throws {
        let store = try makeSeededStore()
        // Link a publication to the project so deletion requires confirmation.
        let publicationID = store.addPublication()
        if var publication = store.publicationRecords.first(where: { $0.id == publicationID }) {
            publication.projectID = "proj-1"
            publication.projectName = "Projekt"
            store.savePublication(publication)
        }
        // ContentView (which hosts the confirmation alert) observes exactly
        // the navigation projection; the warning must reach it.
        let projection = DataStoreDomainProjection(store: store, domain: .navigation)
        let before = projection.revision

        store.deleteProject(id: "proj-1")

        XCTAssertNotNil(
            store.deletionImpactWarning,
            "a project with linked records must request confirmation"
        )
        XCTAssertGreaterThan(
            projection.revision,
            before,
            "the deletion confirmation must invalidate the root observation boundary or the dialog stays invisible until an unrelated render"
        )
    }
}
