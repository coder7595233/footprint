import XCTest
@testable import Footprint

final class Round1Tests: XCTestCase {
    func testPlainIdentifiersKeepTheirNameAsAttachmentFile() {
        let id = "ABAED6A4-3C0A-4B9B-96F1-593392AC3D8D"
        let url = GrantDataStore.managedCVConferenceContributionPDFURL(forContributionID: id)
        XCTAssertEqual(url.lastPathComponent, "\(id).pdf")
        XCTAssertEqual(GrantDataStore.managedPublicationPDFURL(forPublicationID: "legacy-publication").lastPathComponent, "legacy-publication.pdf")
    }

    func testPortableAttachmentPathsDropTheStorageDirectory() {
        let managed = GrantDataStore.reviewCertificatePDFsDirectory.appendingPathComponent("ABC.pdf")
        let stored = GrantDataStore.portableAttachmentPath(for: managed)
        XCTAssertEqual(stored, "Review Certificate PDFs/ABC.pdf")
        XCTAssertEqual(GrantDataStore.absoluteAttachmentURL(fromStored: stored)?.standardizedFileURL, managed.standardizedFileURL)
        let otherAccount = "/Users/privat/Library/Application Support/Footprint/Review Certificate PDFs/ABC.pdf"
        XCTAssertEqual(GrantDataStore.absoluteAttachmentURL(fromStored: otherAccount)?.lastPathComponent, "ABC.pdf")
        XCTAssertTrue(GrantDataStore.absoluteAttachmentURL(fromStored: otherAccount)?.path.hasPrefix(GrantDataStore.storageDirectory.path) ?? false)
    }

    func testImpossibleDaysMoveToTheLastDayOfTheMonth() {
        XCTAssertEqual(DateParsers.canonicalizedDayInput("2025-09-31"), "2025-09-30")
        XCTAssertEqual(DateParsers.canonicalizedDayInput("2025-02-30"), "2025-02-28")
        XCTAssertEqual(DateParsers.canonicalizedDayInput("2024-02-30"), "2024-02-29")
        XCTAssertEqual(DateParsers.canonicalizedDayInput("2026-12-31"), "2026-12-31")
        XCTAssertEqual(DateParsers.canonicalizedDayInput("20250431"), "2025-04-30")
    }

    func testORCIDNormalizationAndChecksum() {
        XCTAssertEqual(PublicationAuthor.normalizedORCID(" https://orcid.org/0000-0002-1694-233x "), "0000-0002-1694-233X")
        XCTAssertEqual(PublicationAuthor.normalizedORCID("0000000216942 33X"), "0000-0002-1694-233X")
        XCTAssertEqual(PublicationAuthor.normalizedORCID("not an orcid"), "not an orcid")
        XCTAssertTrue(PublicationAuthor.isValidORCID("0000-0002-1694-233X"))
        XCTAssertFalse(PublicationAuthor.isValidORCID("0000-0002-1694-2330"))
    }

    func testConferenceStatusFollowsOutcome() {
        var contribution = CVConferenceContribution(id: "c1")
        contribution.submissionOutcome = .declined
        XCTAssertEqual(contribution.derivedStatus(today: "2026-09-27"), .rejected)
        contribution.submissionOutcome = .granted
        contribution.from = "2026-12-01"
        contribution.to = "2026-12-03"
        XCTAssertEqual(contribution.derivedStatus(today: "2026-09-27"), .accepted)
        XCTAssertEqual(contribution.derivedStatus(today: "2027-01-01"), .presented)
    }
}
