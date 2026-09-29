import XCTest
@testable import Footprint

/// F13c: the Data view's "Names to link" section lists person names written
/// in records that match no researcher, one row per name, with how many
/// records use it. A name can be linked to a researcher (it becomes a name
/// variant), turned into a new researcher, or hidden.
final class NameLinkTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NameLinkTests-\(UUID().uuidString)", isDirectory: true)
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

    private static func application(id: String, coApplicants: [String]) -> GrantApplication {
        var application = GrantApplication(
            id: id,
            rowNumber: 1,
            organization: "Funder",
            grantName: "Grant \(id)"
        )
        application.coApplicants = coApplicants
        return application
    }

    @MainActor
    private func store(
        applications: [GrantApplication] = [],
        authors: [PublicationAuthor] = []
    ) -> GrantDataStore {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = "sv"
        return GrantDataStore(
            applications: applications,
            metadata: metadata,
            publicationAuthors: authors,
            skipInitialMigration: true
        )
    }

    private static func anna() -> PublicationAuthor {
        PublicationAuthor(
            id: "author-anna",
            name: "Anna Andersson",
            firstName: "Anna",
            lastName: "Andersson",
            nameVariants: ["A. Andersson"]
        )
    }

    @MainActor
    func testUnmatchedCoApplicantIsListedWithCount() {
        let testStore = store(
            applications: [
                Self.application(id: "application-1", coApplicants: ["Bertil Berg"]),
                Self.application(id: "application-2", coApplicants: ["  bertil berg "]),
            ],
            authors: [Self.anna()]
        )

        let rows = testStore.unlinkedPersonNames()
        XCTAssertEqual(rows.count, 1, "\(rows)")
        guard let row = rows.first else { return }
        XCTAssertEqual(row.key, "bertil berg")
        XCTAssertEqual(row.id, "name-link|bertil berg")
        XCTAssertEqual(row.usages.map(\.kind), [.application])
        XCTAssertEqual(row.usages.first?.count, 2)
        XCTAssertEqual(row.totalCount, 2)
        XCTAssertEqual(row.usageSummary(language: .swedish), "2 ansökningar")
    }

    @MainActor
    func testNameMatchingResearcherOrNameVariantIsNotListed() {
        let testStore = store(
            applications: [
                Self.application(id: "application-1", coApplicants: ["A. Andersson", "anna andersson", ""]),
            ],
            authors: [Self.anna()]
        )

        XCTAssertTrue(testStore.unlinkedPersonNames(includeHidden: true).isEmpty)
    }

    @MainActor
    func testLinkingAddsNameVariantAndRemovesRow() {
        let testStore = store(
            applications: [
                Self.application(id: "application-1", coApplicants: ["Bertil Berg"]),
            ],
            authors: [
                Self.anna(),
                PublicationAuthor(id: "author-bertil", name: "Bertil Bergström", firstName: "Bertil", lastName: "Bergström"),
            ]
        )
        guard let row = testStore.unlinkedPersonNames().first else {
            return XCTFail("expected a row for Bertil Berg")
        }

        testStore.linkPersonName(row.name, toAuthorID: "author-bertil")

        let bertil = testStore.publicationAuthor(id: "author-bertil")
        XCTAssertTrue(bertil?.nameVariants.contains("Bertil Berg") ?? false, "\(String(describing: bertil?.nameVariants))")
        XCTAssertEqual(testStore.publicationAuthor(matchingPresentedName: "Bertil Berg")?.id, "author-bertil")
        XCTAssertTrue(testStore.unlinkedPersonNames(includeHidden: true).isEmpty)

        testStore.undoManager.undo()
        XCTAssertEqual(testStore.unlinkedPersonNames().map(\.key), ["bertil berg"])
    }

    @MainActor
    func testCreatingNewResearcherRemovesRow() {
        let testStore = store(
            applications: [
                Self.application(id: "application-1", coApplicants: ["Cecilia Carlsson"]),
            ]
        )
        guard let row = testStore.unlinkedPersonNames().first else {
            return XCTFail("expected a row for Cecilia Carlsson")
        }

        let newID = testStore.createResearcher(forUnlinkedName: row.name)

        let created = testStore.publicationAuthor(id: newID)
        XCTAssertEqual(created?.name, "Cecilia Carlsson")
        XCTAssertEqual(created?.firstName, "Cecilia")
        XCTAssertEqual(created?.lastName, "Carlsson")
        // The first researcher still becomes the current user, as before.
        XCTAssertEqual(testStore.metadata.currentUserAuthorID, newID)
        XCTAssertTrue(testStore.unlinkedPersonNames(includeHidden: true).isEmpty)
    }

    @MainActor
    func testHiddenRowIsLeftOutUnlessAskedFor() {
        let testStore = store(
            applications: [
                Self.application(id: "application-1", coApplicants: ["Bertil Berg"]),
            ],
            authors: [Self.anna()]
        )
        guard let row = testStore.unlinkedPersonNames().first else {
            return XCTFail("expected a row for Bertil Berg")
        }

        testStore.hideDataQualityWarning(row)

        XCTAssertTrue(testStore.isDataQualityWarningHidden(row))
        XCTAssertTrue(testStore.unlinkedPersonNames().isEmpty)
        XCTAssertEqual(testStore.unlinkedPersonNames(includeHidden: true).map(\.key), ["bertil berg"])
        XCTAssertTrue(testStore.metadata.hiddenDataQualityWarningKeys?.contains("name-link|bertil berg") ?? false)

        testStore.showDataQualityWarning(row)
        XCTAssertEqual(testStore.unlinkedPersonNames().map(\.key), ["bertil berg"])
    }

    @MainActor
    func testListFollowsEditedRecords() {
        var application = Self.application(id: "application-1", coApplicants: [])
        let testStore = store(applications: [application], authors: [Self.anna()])
        XCTAssertTrue(testStore.unlinkedPersonNames().isEmpty)

        application.coApplicants = ["David Dahl"]
        testStore.autosave(application: application)

        XCTAssertEqual(testStore.unlinkedPersonNames().map(\.name), ["David Dahl"])
    }
}
