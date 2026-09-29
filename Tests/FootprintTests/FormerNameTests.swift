import XCTest
@testable import Footprint

/// F16: a person has a current name and former names. Renaming keeps the old
/// name as a former name (with the day it stopped being used), records keep the
/// name they were written with, and old data still reads as spelling variants.
final class FormerNameTests: XCTestCase {
    private var storageDirectory: URL!

    // Storage isolation is NOT automatic under this test runner — a store
    // without this override reads and writes the user's real database.
    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FormerNameTests-\(UUID().uuidString)", isDirectory: true)
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

    private func makeAuthor(spellings: [PublicationAuthorNameVariant] = []) -> PublicationAuthor {
        PublicationAuthor(
            id: "author-1",
            name: "Anna Berg",
            firstName: "Anna",
            lastName: "Berg",
            nameVariantRows: spellings,
            affiliations: [PublicationAffiliation(isPrimary: true)]
        )
    }

    private func makePublicationWithOldName() -> PublicationRecord {
        PublicationRecord(
            id: "pub-1",
            projectName: "",
            title: "Blood pressure at home",
            journal: "",
            year: "2024",
            authorNames: ["Anna Berg", "Other Person"]
        )
    }

    @MainActor
    private func renamedStore(publicationRecords: [PublicationRecord] = []) -> GrantDataStore {
        let author = makeAuthor(spellings: [PublicationAuthorNameVariant(firstName: "A.", lastName: "Berg")])
        let store = GrantDataStore(
            publicationAuthors: [author],
            publicationRecords: publicationRecords,
            skipInitialMigration: true
        )
        var renamed = author
        renamed.lastName = "Lind"
        store.autosavePublicationAuthor(renamed, previousName: author.name)
        return store
    }

    @MainActor
    func testRenameStoresPreviousNameAsFormerNameWithTodaysDate() throws {
        let store = renamedStore()
        let updated = try XCTUnwrap(store.publicationAuthors.first)

        XCTAssertEqual(updated.name, "Anna Lind")
        XCTAssertEqual(updated.formerNames.map(\.displayName), ["Anna Berg"])
        XCTAssertEqual(updated.formerNames.first?.firstName, "Anna")
        XCTAssertEqual(updated.formerNames.first?.lastName, "Berg")
        XCTAssertEqual(updated.formerNames.first?.usedUntil, DateParsers.isoDay.string(from: Date()))

        // An existing spelling variant stays a spelling variant.
        let spelling = try XCTUnwrap(updated.nameVariantRows.first { $0.displayName == "A. Berg" })
        XCTAssertFalse(spelling.isFormerName)
        XCTAssertEqual(spelling.usedUntil, "")
    }

    @MainActor
    func testSaveRenameAlsoStoresFormerName() throws {
        let author = makeAuthor()
        let store = GrantDataStore(publicationAuthors: [author], skipInitialMigration: true)
        var renamed = author
        renamed.lastName = "Lind"

        store.savePublicationAuthor(renamed, previousName: author.name)

        let updated = try XCTUnwrap(store.publicationAuthors.first)
        XCTAssertEqual(updated.name, "Anna Lind")
        XCTAssertEqual(updated.formerNames.map(\.displayName), ["Anna Berg"])
        XCTAssertEqual(updated.formerNames.first?.usedUntil, DateParsers.isoDay.string(from: Date()))
    }

    @MainActor
    func testFormerNameStillResolvesToAuthor() throws {
        let store = renamedStore()

        XCTAssertEqual(store.publicationAuthor(matchingPresentedName: "Anna Berg")?.id, "author-1")
        XCTAssertEqual(store.publicationAuthor(matchingPresentedName: "Anna Lind")?.id, "author-1")
        let updated = try XCTUnwrap(store.publicationAuthors.first)
        XCTAssertTrue(updated.presentedNameCandidates.contains("Anna Berg"))
    }

    @MainActor
    func testPublicationWrittenWithOldNameKeepsOldName() throws {
        let store = renamedStore(publicationRecords: [makePublicationWithOldName()])

        let publication = try XCTUnwrap(store.publicationRecords.first { $0.id == "pub-1" })
        XCTAssertEqual(publication.authorNames, ["Anna Berg", "Other Person"])
        XCTAssertEqual(store.publications(forAuthorID: "author-1").map(\.id), ["pub-1"])
    }

    func testLegacyPlainNameVariantsDecodeAsSpellings() throws {
        let json = """
        {
          "id": "author-legacy",
          "name": "Anna Lind",
          "firstName": "Anna",
          "lastName": "Lind",
          "nameVariants": ["Anna Berg", "A. Lind"]
        }
        """
        let author = try JSONDecoder().decode(PublicationAuthor.self, from: Data(json.utf8))

        XCTAssertEqual(author.nameVariantRows.map(\.displayName), ["Anna Berg", "A. Lind"])
        XCTAssertTrue(author.formerNames.isEmpty)
        XCTAssertTrue(author.nameVariantRows.allSatisfy { $0.usedUntil.isEmpty })
    }

    func testLegacyVariantRowsWithoutKindDecodeAsSpellings() throws {
        let json = """
        {
          "id": "author-legacy",
          "name": "Anna Lind",
          "firstName": "Anna",
          "lastName": "Lind",
          "nameVariantRows": [{ "firstName": "Anna", "lastName": "Berg" }]
        }
        """
        let author = try JSONDecoder().decode(PublicationAuthor.self, from: Data(json.utf8))

        XCTAssertEqual(author.nameVariantRows, [PublicationAuthorNameVariant(firstName: "Anna", lastName: "Berg")])
        XCTAssertTrue(author.formerNames.isEmpty)
    }

    func testFormerNameSurvivesEncodingRoundTrip() throws {
        var author = makeAuthor()
        author.markFormerName(firstName: "Anna", lastName: "Holm", usedUntil: "2019")

        let decoded = try JSONDecoder().decode(PublicationAuthor.self, from: JSONEncoder().encode(author))

        XCTAssertEqual(decoded.formerNames, [
            PublicationAuthorNameVariant(firstName: "Anna", lastName: "Holm", isFormerName: true, usedUntil: "2019")
        ])
    }

    @MainActor
    func testUseCurrentNameRewritesRecordsAndRemovesTheFormerName() {
        let author = PublicationAuthor(
            id: "author-1",
            name: "Anna Lind",
            firstName: "Anna",
            lastName: "Lind",
            nameVariantRows: [
                PublicationAuthorNameVariant(firstName: "Anna", lastName: "Berg", isFormerName: true, usedUntil: "2024")
            ],
            affiliations: [PublicationAffiliation(isPrimary: true)]
        )
        let application = GrantApplication(
            id: "app-1",
            rowNumber: 1,
            organization: "Stiftelsen",
            grantName: "Projektbidrag",
            coApplicants: ["Anna Berg", "Other Person"]
        )
        let store = GrantDataStore(
            applications: [application],
            publicationAuthors: [author],
            publicationRecords: [makePublicationWithOldName()],
            skipInitialMigration: true
        )
        let variant = author.nameVariantRows[0]
        XCTAssertEqual(store.authorNameVariantUsageCount(authorID: "author-1", variant: variant), 2)

        store.replaceAuthorNameVariantWithCurrentName(authorID: "author-1", variant: variant)
        XCTAssertNotNil(store.deletionImpactWarning, "the change is confirmed first")
        store.confirmDeletionImpactWarning()

        XCTAssertEqual(store.publicationRecords.first?.authorNames, ["Anna Lind", "Other Person"])
        XCTAssertEqual(store.applications.first?.coApplicants, ["Anna Lind", "Other Person"])
        XCTAssertEqual(
            store.publicationAuthors.first?.nameVariantRows.count,
            0,
            "the former name is removed from the researcher card"
        )

        store.undoManager.undo()
        XCTAssertEqual(store.publicationRecords.first?.authorNames, ["Anna Berg", "Other Person"])
        XCTAssertEqual(store.publicationAuthors.first?.formerNames.map(\.displayName), ["Anna Berg"])
    }
}
