import XCTest
@testable import Footprint

/// Attachment files are named after their record's id; files saved under the
/// older "unsafe-id-<digest>" name for an ordinary id are still found.
final class AttachmentNamingTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttachmentNamingTests-\(UUID().uuidString)", isDirectory: true)
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

    func testOrdinaryIDsKeepTheirOwnName() {
        for id in ["33612FC8-5B09-52AE-8D80-1117869EB8D8", "0b6358cb-4c5b-5ac8-83bb-0dbdc1e9d3de", "legacy-publication", "media_1.v2"] {
            XCTAssertEqual(GrantDataStore.managedAttachmentFileStem(for: id), id)
        }
        for id in ["", ".", "..", "a/b", #"a\b"#, "50%", " padded", "a\u{0}b", "ö"] {
            XCTAssertTrue(GrantDataStore.managedAttachmentFileStem(for: id).hasPrefix("unsafe-id-"), id)
        }
    }

    func testAFileUnderTheOlderDigestNameIsStillFound() throws {
        let id = "3566D110-1E40-5F00-ABAC-3B56F9C13FF2"
        try FileManager.default.createDirectory(at: GrantDataStore.publicationPDFsDirectory, withIntermediateDirectories: true)
        let legacy = GrantDataStore.publicationPDFsDirectory
            .appendingPathComponent("\(GrantDataStore.legacyUnsafeAttachmentFileStem(for: id)).pdf")
        try Data("%PDF-1.4".utf8).write(to: legacy)

        let resolved = GrantDataStore.resolvePublicationPDFURL(
            publicationID: id,
            finalPDFPath: "Publication PDFs/\(legacy.lastPathComponent)",
            finalPDFFilename: "Artikel.pdf"
        )
        XCTAssertEqual(resolved?.lastPathComponent, legacy.lastPathComponent)
    }

    func testAFileUnderTheIDNameIsFoundEvenWhenTheRecordPointsToTheOldName() throws {
        let id = "33612FC8-5B09-52AE-8D80-1117869EB8D8"
        try FileManager.default.createDirectory(at: GrantDataStore.publicationPDFsDirectory, withIntermediateDirectories: true)
        let current = GrantDataStore.publicationPDFsDirectory.appendingPathComponent("\(id).pdf")
        try Data("%PDF-1.4".utf8).write(to: current)

        let resolved = GrantDataStore.resolvePublicationPDFURL(
            publicationID: id,
            finalPDFPath: "Publication PDFs/\(GrantDataStore.legacyUnsafeAttachmentFileStem(for: id)).pdf",
            finalPDFFilename: "Artikel.pdf"
        )
        XCTAssertEqual(resolved?.lastPathComponent, "\(id).pdf")
    }
}
