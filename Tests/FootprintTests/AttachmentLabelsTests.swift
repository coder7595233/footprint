import XCTest
@testable import Footprint

/// F1b: attachments are shown under a name built from the record, and the
/// export package gets a readable attachment list.
final class AttachmentLabelsTests: XCTestCase {
    func testPublicationLabelUsesTitleAndYear() {
        var publication = PublicationRecord(id: "pub-1", title: "Body mass index\nand  outcomes", year: "2026")
        publication.finalPDFFilename = "s00000-026-00000-0.pdf"
        XCTAssertEqual(
            AttachmentLabels.publication(publication, language: .swedish),
            "Body mass index and outcomes (2026).pdf"
        )
    }

    func testPublicationLabelWithoutYearAndWithoutTitle() {
        let withoutYear = PublicationRecord(id: "pub-2", title: "Utan år")
        XCTAssertEqual(AttachmentLabels.publication(withoutYear, language: .swedish), "Utan år.pdf")

        let withoutTitle = PublicationRecord(id: "pub-3", title: "  ", year: "2024")
        XCTAssertNil(AttachmentLabels.publication(withoutTitle, language: .swedish))
    }

    func testLabelReplacesCharactersThatCannotBeInFileNames() {
        let publication = PublicationRecord(id: "pub-4", title: "Hypo/hypertension: a study", year: "2025")
        XCTAssertEqual(
            AttachmentLabels.publication(publication, language: .swedish),
            "Hypo-hypertension - a study (2025).pdf"
        )
    }

    func testReviewCertificateLabelUsesJournalAndDate() {
        let entry = CVReviewEntry(id: "r1", date: "2026-08-05", journalName: "BMC Geriatrics")
        XCTAssertEqual(
            AttachmentLabels.reviewCertificate(entry, language: .swedish),
            "Granskningsintyg – BMC Geriatrics 2026-08-05.pdf"
        )
        XCTAssertEqual(
            AttachmentLabels.reviewCertificate(entry, language: .english),
            "Review certificate – BMC Geriatrics 2026-08-05.pdf"
        )

        let withRound = CVReviewEntry(
            id: "r2",
            date: "2026-07-08",
            journalName: "European Journal of Preventive Cardiology",
            reviewRound: "R1"
        )
        XCTAssertEqual(
            AttachmentLabels.reviewCertificate(withRound, language: .swedish),
            "Granskningsintyg – European Journal of Preventive Cardiology R1 2026-07-08.pdf"
        )
    }

    func testConferenceContributionLabelUsesTitleAndYear() {
        let contribution = CVConferenceContribution(
            id: "c1",
            from: "2025-05-23",
            title: "Self-measured home orthostatic hypotension"
        )
        XCTAssertEqual(
            AttachmentLabels.conferenceContribution(contribution, language: .swedish),
            "Self-measured home orthostatic hypotension (2025).pdf"
        )
    }

    func testMediaAppearanceLabelUsesTitleAndDate() {
        let appearance = CVMediaAppearance(id: "m1", date: "2026-03-01", title: "Radiointervju om blodtryck")
        XCTAssertEqual(
            AttachmentLabels.mediaAppearance(appearance, language: .swedish),
            "Media – Radiointervju om blodtryck 2026-03-01.pdf"
        )
    }

    func testDoctoralDocumentLabelUsesCandidateTitleAndDate() {
        let document = DoctoralCandidateDocument(
            id: "d1",
            title: "Protokoll startseminarium",
            date: "2026-03-04",
            filename: "Protokoll Anna.pdf"
        )
        XCTAssertEqual(
            AttachmentLabels.doctoralDocument(document, candidateName: "Anna Exempel", language: .swedish),
            "Anna Exempel – Protokoll startseminarium 2026-03-04.pdf"
        )
        let untitled = DoctoralCandidateDocument(id: "d2", filename: "x.pdf")
        XCTAssertNil(AttachmentLabels.doctoralDocument(untitled, candidateName: "Anna Exempel", language: .swedish))
    }

    @MainActor
    func testAttachmentListRowsReportPackagePathAndWhetherFileExists() throws {
        let packageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FootprintAttachmentListTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: packageDirectory) }
        let payloadDirectory = packageDirectory.appendingPathComponent("payload", isDirectory: true)
        let publicationDirectory = payloadDirectory.appendingPathComponent("Publication PDFs", isDirectory: true)
        try FileManager.default.createDirectory(at: publicationDirectory, withIntermediateDirectories: true)
        try Data("%PDF-1.4".utf8).write(to: publicationDirectory.appendingPathComponent("pub-present.pdf"))

        var present = PublicationRecord(id: "pub-present", title: "Finns", year: "2026")
        present.finalPDFFilename = "original.pdf"
        present.finalPDFPath = "Publication PDFs/pub-present.pdf"
        var missing = PublicationRecord(id: "pub-missing", title: "Saknas; med semikolon", year: "2025")
        missing.finalPDFFilename = "borta.pdf"
        let withoutPDF = PublicationRecord(id: "pub-none", title: "Ingen PDF", year: "2024")
        var review = CVReviewEntry(id: "review-1", date: "2026-08-05", journalName: "BMC Geriatrics")
        review.certificateFilename = "Reviewer Certificate.pdf"
        var candidate = DoctoralCandidateRecord(id: "candidate-1", candidateName: "Erik Exempelsson")
        candidate.documents = [
            DoctoralCandidateDocument(id: "doc-1", title: "Forskningsplan", date: "2026-02-03", filename: "plan.pdf")
        ]

        let snapshot = GrantDataStoreSnapshotFactory.snapshot(
            publicationRecords: [present, missing, withoutPDF],
            cvReviewEntries: [review],
            doctoralCandidates: [candidate]
        )
        let rows = GrantDataStore.databaseExportAttachmentListRows(
            snapshot: snapshot,
            payloadDirectory: payloadDirectory,
            payloadDirectoryName: "payload",
            language: .swedish
        )

        XCTAssertEqual(rows.map(\.recordID), ["pub-present", "pub-missing", "review-1", "doc-1"])
        XCTAssertEqual(rows[0].label, "Finns (2026).pdf")
        XCTAssertEqual(rows[0].originalFilename, "original.pdf")
        XCTAssertEqual(rows[0].packagePath, "payload/Publication PDFs/pub-present.pdf")
        XCTAssertTrue(rows[0].fileExists)
        XCTAssertFalse(rows[1].fileExists)
        XCTAssertEqual(rows[2].register, "Granskningsintyg")
        XCTAssertEqual(rows[2].label, "Granskningsintyg – BMC Geriatrics 2026-08-05.pdf")
        XCTAssertEqual(rows[3].register, "Doktorander")
        XCTAssertEqual(rows[3].label, "Erik Exempelsson – Forskningsplan 2026-02-03.pdf")

        let csv = GrantDataStore.databaseExportAttachmentListCSV(rows: rows, language: .swedish)
        let lines = csv.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 5)
        XCTAssertEqual(
            lines[0],
            "\u{FEFF}Register;Post-id;Postens etikett;Ursprungligt filnamn;Fil i paketet;Filen finns"
        )
        XCTAssertTrue(lines[1].hasSuffix(";ja"))
        XCTAssertTrue(lines[2].contains("\"Saknas; med semikolon (2025).pdf\""))
        XCTAssertTrue(lines[2].hasSuffix(";nej"))
    }

    func testRemovedDoctoralStatisticsAreaIsGoneAndItsStoredValueFallsBack() {
        XCTAssertNil(StatisticsDashboardTab(rawValue: "doctoral"))
        XCTAssertEqual(StatisticsDashboardTab.allCases, [.grants, .publications, .teaching, .activities])
    }
}

/// Builds a `GrantDataStore.Snapshot` without a store.
@MainActor
enum GrantDataStoreSnapshotFactory {
    static func snapshot(
        publicationRecords: [PublicationRecord] = [],
        cvReviewEntries: [CVReviewEntry] = [],
        doctoralCandidates: [DoctoralCandidateRecord] = []
    ) -> GrantDataStore.Snapshot {
        GrantDataStore.Snapshot(
            applications: [],
            metadata: .bundledDefault,
            organizations: [],
            managers: [],
            projects: [],
            teachingCourses: [],
            teachingComponents: [],
            teachingFormats: [],
            teachingAssignments: [],
            doctoralCandidates: doctoralCandidates,
            cvPersonalResume: CVPersonalResume(),
            cvConferenceContributions: [],
            cvMediaAppearances: [],
            cvReviewEntries: cvReviewEntries,
            cvOtherPublications: [],
            publicationAuthors: [],
            publicationJournals: [],
            publicationRecords: publicationRecords
        )
    }
}
