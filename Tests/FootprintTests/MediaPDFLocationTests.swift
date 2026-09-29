import XCTest
@testable import Footprint

/// A media PDF that only lies in "Media Appearance Files" (where the earlier
/// Media attachment UI saved it) is found, and at the next start it is copied
/// to "Media Appearance PDFs" under the record's id. The original is kept.
final class MediaPDFLocationTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaPDFLocationTests-\(UUID().uuidString)", isDirectory: true)
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

    private func writeOldMediaFile(named filename: String) throws -> URL {
        let directory = GrantDataStore.mediaAppearanceFilesDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(filename)
        try Data("%PDF-1.4 exempel".utf8).write(to: url)
        return url
    }

    @MainActor
    func testFileNamedByRecordIDInOldFolderIsFoundAndCopiedIntoPlace() throws {
        let id = "MEDIA-ID-1"
        let oldURL = try writeOldMediaFile(named: "\(id).pdf")
        var appearance = CVMediaAppearance(
            id: id,
            title: "Intervju",
            pdfFilename: "Media – Intervju.pdf",
            pdfPath: "Media Appearance PDFs/\(id).pdf"
        )

        let found = GrantDataStore.resolveCVMediaAppearancePDFURL(
            mediaAppearanceID: appearance.id,
            pdfPath: appearance.pdfPath,
            pdfFilename: appearance.pdfFilename
        )
        XCTAssertEqual(found?.standardizedFileURL.path, oldURL.standardizedFileURL.path)

        XCTAssertTrue(try GrantDataStore.canonicalizeCVMediaAppearancePDFAttachment(for: &appearance))
        let managed = GrantDataStore.managedCVMediaAppearancePDFURL(forMediaAppearanceID: id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: managed.path), "copied into Media Appearance PDFs")
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.path), "the original is kept")
    }

    func testOldAttachmentWithOtherNameIsFound() throws {
        let oldURL = try writeOldMediaFile(named: "OTHER-UUID.pdf")
        var appearance = CVMediaAppearance(id: "MEDIA-ID-2", title: "Intervju", pdfFilename: "Media – Intervju.pdf")
        appearance.attachments = [CVMediaAttachment(filename: "intervju.pdf", storedFilename: "OTHER-UUID.pdf")]

        let found = GrantDataStore.resolveCVMediaAppearancePDFURL(
            mediaAppearanceID: appearance.id,
            pdfPath: appearance.pdfPath,
            pdfFilename: appearance.pdfFilename,
            legacyStoredFilenames: GrantDataStore.legacyMediaPDFCandidateNames(appearance.attachments)
        )
        XCTAssertEqual(found?.standardizedFileURL.path, oldURL.standardizedFileURL.path)
    }

    /// The data seen on the Mac: no PDF fields on the record, one old
    /// attachment whose stored name does not match any file, and the file in
    /// "Media Appearance Files" named by the attachment's id.
    func testOldAttachmentIsFoundByItsID() throws {
        let attachmentID = "36FF84D6-0819-4B24-8194-51E5D6F7B003"
        let oldURL = try writeOldMediaFile(named: "\(attachmentID).pdf")
        let attachment = CVMediaAttachment(
            id: attachmentID,
            filename: "Artikel om studien.pdf",
            storedFilename: "någon-annan-fil.pdf"
        )

        XCTAssertEqual(
            GrantDataStore.resolveLegacyMediaAppearanceAttachmentURL(attachment)?.standardizedFileURL.path,
            oldURL.standardizedFileURL.path
        )
        XCTAssertEqual(
            GrantDataStore.resolveCVMediaAppearancePDFURL(
                mediaAppearanceID: "MEDIA-ID-4",
                pdfPath: nil,
                pdfFilename: nil,
                legacyStoredFilenames: GrantDataStore.legacyMediaPDFCandidateNames([attachment])
            )?.standardizedFileURL.path,
            oldURL.standardizedFileURL.path
        )
    }

    func testLinksAndPathsOutsideTheFolderAreRefused() throws {
        let outside = storageDirectory.appendingPathComponent("utanfor.pdf")
        try Data("%PDF-1.4 utanför".utf8).write(to: outside)
        let directory = GrantDataStore.mediaAppearanceFilesDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("genvag.pdf"),
            withDestinationURL: outside
        )

        XCTAssertNil(GrantDataStore.resolveLegacyMediaAppearanceFileURL(storedFilename: "genvag.pdf"), "a link is not followed")
        XCTAssertNil(GrantDataStore.resolveLegacyMediaAppearanceFileURL(storedFilename: "../utanfor.pdf"), "no way out of the folder")
    }

    func testMissingFileStaysMissing() {
        XCTAssertNil(GrantDataStore.resolveCVMediaAppearancePDFURL(
            mediaAppearanceID: "MEDIA-ID-3",
            pdfPath: nil,
            pdfFilename: "saknas.pdf"
        ))
    }
}
