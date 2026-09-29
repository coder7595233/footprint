import XCTest
@testable import Footprint

final class ReviewCertificateMigrationTests: XCTestCase {
    private let pdfBytes = Data("%PDF-1.4 test certificate".utf8)
    private var storageDirectory: URL!

    // Storage isolation is NOT automatic under this test runner — a store
    // without this override reads and writes the user's real database.
    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReviewCertificateMigrationTests-\(UUID().uuidString)", isDirectory: true)
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
    func testInlineCertificateIsExtractedToManagedFile() throws {
        var review = CVReviewEntry(
            id: "review-cert-migration",
            date: "2026-01-15",
            journalName: "Journal of Testing"
        )
        review.certificatePDFData = pdfBytes
        let store = GrantDataStore(cvReviewEntries: [review])

        let didChange = store.migrateRecordsIfNeeded()

        XCTAssertTrue(didChange)
        let migrated = try XCTUnwrap(store.cvReviewEntries.first(where: { $0.id == review.id }))
        XCTAssertNil(migrated.certificatePDFData, "inline data must be cleared after extraction")
        XCTAssertNotNil(migrated.certificateFilename)
        let managedURL = GrantDataStore.managedCVReviewCertificatePDFURL(forReviewEntryID: review.id)
        XCTAssertEqual(migrated.certificatePath, GrantDataStore.portableAttachmentPath(for: managedURL))
        XCTAssertEqual(try Data(contentsOf: managedURL), pdfBytes)

        let resolved = GrantDataStore.resolveCVReviewCertificatePDFURL(
            reviewEntryID: migrated.id,
            certificatePath: migrated.certificatePath,
            certificateFilename: migrated.certificateFilename
        )
        XCTAssertEqual(resolved?.path, managedURL.path)
    }

    @MainActor
    func testExtractionIsSkippedWhenGated() throws {
        var review = CVReviewEntry(
            id: "review-cert-gated",
            date: "2026-01-15",
            journalName: "Journal of Testing"
        )
        review.certificatePDFData = pdfBytes
        let store = GrantDataStore(cvReviewEntries: [review])

        _ = store.migrateRecordsIfNeeded(extractInlineReviewCertificates: false)

        let entry = try XCTUnwrap(store.cvReviewEntries.first(where: { $0.id == review.id }))
        XCTAssertEqual(entry.certificatePDFData, pdfBytes, "gated migration must leave inline data untouched")
    }

    func testLegacyInlineEntryStillDecodes() throws {
        var review = CVReviewEntry(
            id: "review-cert-decode",
            date: "2025-05-01",
            journalName: "Legacy Journal"
        )
        review.certificatePDFData = pdfBytes
        let encoded = try JSONEncoder().encode([review])
        let decoded = try JSONDecoder().decode([CVReviewEntry].self, from: encoded)
        XCTAssertEqual(decoded.first?.certificatePDFData, pdfBytes)

        review.certificatePDFData = nil
        let migratedEncoded = try JSONEncoder().encode([review])
        // The whole point of the migration: the certificate bytes must not
        // ride along in the JSON document once extracted.
        XCTAssertLessThan(migratedEncoded.count, encoded.count)
    }

    @MainActor
    func testDeleteRemovesManagedFileAndArchiveKeepsPDF() throws {
        var review = CVReviewEntry(
            id: "review-cert-delete",
            date: "2026-02-01",
            journalName: "Journal of Deletion"
        )
        review.certificatePDFData = pdfBytes
        let store = GrantDataStore(cvReviewEntries: [review])
        _ = store.migrateRecordsIfNeeded()
        let managedURL = GrantDataStore.managedCVReviewCertificatePDFURL(forReviewEntryID: review.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: managedURL.path))

        store.deleteCVReviewEntry(id: review.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: managedURL.path))
        let archived = try store.loadArchivedRecords()
        let envelope = try XCTUnwrap(archived.first(where: { $0.kind == "cv_review_entry" }))
        let archivedReview = try JSONDecoder().decode(CVReviewEntry.self, from: envelope.payload)
        XCTAssertEqual(archivedReview.certificatePDFData, pdfBytes, "archive must stay self-contained")
    }
}
