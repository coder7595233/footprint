import XCTest
@testable import Footprint

final class AuthorNameVariantRemovalTests: XCTestCase {
    private var storageDirectory: URL!

    // Storage isolation is NOT automatic under this test runner — a store
    // without this override reads and writes the user's real database.
    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuthorNameVariantRemovalTests-\(UUID().uuidString)", isDirectory: true)
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
    private func makeAuthorWithVariant() -> PublicationAuthor {
        var author = PublicationAuthor(
            name: "Tove A. Lindberg",
            affiliations: [PublicationAffiliation(isPrimary: true)]
        )
        author.firstName = "Tove A."
        author.lastName = "Lindberg"
        author.nameVariantRows = [
            PublicationAuthorNameVariant(firstName: "Tove", lastName: "Lindberg")
        ]
        return author
    }

    @MainActor
    func testRemovingReferencedVariantRewritesLinksToCurrentName() throws {
        let author = makeAuthorWithVariant()
        let variant = try XCTUnwrap(author.nameVariantRows.first)
        let publication = PublicationRecord(
            id: "pub-1",
            projectName: "",
            title: "BMI and MACE after myocardial infarction",
            journal: "",
            year: "2025",
            authorNames: ["Tove Lindberg", "Other Person"]
        )
        let store = GrantDataStore(
            publicationAuthors: [author],
            publicationRecords: [publication]
        )

        let impact = store.authorNameVariantRemovalImpact(authorID: author.id, variant: variant)
        XCTAssertEqual(impact.map(\.recordID), ["pub-1"])
        XCTAssertFalse(impact[0].isProtected)

        store.removeAuthorNameVariantRewritingReferences(authorID: author.id, variant: variant)

        let updatedPublication = try XCTUnwrap(store.publicationRecords.first(where: { $0.id == "pub-1" }))
        XCTAssertEqual(updatedPublication.authorNames, ["Tove A. Lindberg", "Other Person"])
        let updatedAuthor = try XCTUnwrap(store.publicationAuthors.first(where: { $0.id == author.id }))
        XCTAssertTrue(updatedAuthor.nameVariantRows.isEmpty)
        XCTAssertNil(store.deletionImpactWarning, "no confirmation needed for unprotected records")
    }

    @MainActor
    func testProtectedRecordsRequireConfirmationBeforeRewrite() throws {
        let author = makeAuthorWithVariant()
        let variant = try XCTUnwrap(author.nameVariantRows.first)
        var publication = PublicationRecord(
            id: "pub-locked",
            projectName: "",
            title: "Published SWEDEHEART report",
            journal: "",
            year: "2024",
            authorNames: ["Tove Lindberg"]
        )
        publication.status = PublicationStatus.published.rawValue
        publication.isEditingLocked = true
        let store = GrantDataStore(
            publicationAuthors: [author],
            publicationRecords: [publication]
        )

        let impact = store.authorNameVariantRemovalImpact(authorID: author.id, variant: variant)
        XCTAssertTrue(try XCTUnwrap(impact.first).isProtected)

        store.removeAuthorNameVariantRewritingReferences(authorID: author.id, variant: variant)

        // Nothing changes until the user confirms the warning.
        XCTAssertNotNil(store.deletionImpactWarning)
        XCTAssertEqual(
            store.publicationRecords.first(where: { $0.id == "pub-locked" })?.authorNames,
            ["Tove Lindberg"]
        )
        XCTAssertFalse(try XCTUnwrap(store.publicationAuthors.first).nameVariantRows.isEmpty)

        store.confirmDeletionImpactWarning()

        XCTAssertEqual(
            store.publicationRecords.first(where: { $0.id == "pub-locked" })?.authorNames,
            ["Tove A. Lindberg"]
        )
        XCTAssertTrue(try XCTUnwrap(store.publicationAuthors.first).nameVariantRows.isEmpty)
    }

    @MainActor
    func testUnreferencedVariantHasNoImpact() throws {
        let author = makeAuthorWithVariant()
        let variant = try XCTUnwrap(author.nameVariantRows.first)
        let store = GrantDataStore(publicationAuthors: [author])

        XCTAssertTrue(store.authorNameVariantRemovalImpact(authorID: author.id, variant: variant).isEmpty)
    }

    @MainActor
    func testDuplicateSpellingInAnotherRowMakesRemovalHarmless() throws {
        var author = makeAuthorWithVariant()
        author.nameVariantRows.append(
            PublicationAuthorNameVariant(firstName: "Tove", lastName: "Lindberg")
        )
        let variant = try XCTUnwrap(author.nameVariantRows.first)
        let publication = PublicationRecord(
            id: "pub-1",
            projectName: "",
            title: "Still linked via the duplicate row",
            journal: "",
            year: "2025",
            authorNames: ["Tove Lindberg"]
        )
        let store = GrantDataStore(
            publicationAuthors: [author],
            publicationRecords: [publication]
        )

        XCTAssertTrue(
            store.authorNameVariantRemovalImpact(authorID: author.id, variant: variant).isEmpty,
            "the same spelling in another row keeps the link alive"
        )
    }
}
