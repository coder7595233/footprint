import XCTest
@testable import Footprint

final class DatabaseTransferTests: XCTestCase {
    private var isolatedStorageDirectory: URL!

    override func setUpWithError() throws {
        XCTAssertTrue(
            GrantDataStore.waitForPendingPeriodicBackupWork(timeout: 10),
            "Periodic backup work from the previous test did not finish."
        )
        isolatedStorageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FootprintDatabaseTransferTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: isolatedStorageDirectory, withIntermediateDirectories: true)
        setenv("FOOTPRINT_STORAGE_DIRECTORY", isolatedStorageDirectory.path, 1)
    }

    override func tearDownWithError() throws {
        XCTAssertTrue(
            GrantDataStore.waitForPendingPeriodicBackupWork(timeout: 10),
            "Periodic backup work did not finish before test storage cleanup."
        )
        unsetenv("FOOTPRINT_STORAGE_DIRECTORY")
        if let isolatedStorageDirectory {
            try? FileManager.default.removeItem(at: isolatedStorageDirectory)
        }
        isolatedStorageDirectory = nil
    }

    func testExcelSafetyExportOnlyAllowsEntireApp() {
        XCTAssertEqual(
            FootprintDataExchangeScope.availableCases(for: .excelWorkbook),
            [.entireApp]
        )
        XCTAssertTrue(FootprintDataExchangeCategory.selectableCases(for: .excelWorkbook).isEmpty)
    }

    func testSelectiveDatabaseExportIncludesJournalsAndOnlySelfContainedCategories() {
        let categories = Set(FootprintDataExchangeCategory.selectableCases(for: .databasePackage))
        XCTAssertTrue(categories.contains(.journals))
        XCTAssertTrue(categories.contains(.applications))
        XCTAssertTrue(categories.contains(.projects))
        XCTAssertTrue(categories.contains(.organizations))
        XCTAssertTrue(categories.contains(.researchers))
        XCTAssertTrue(categories.contains(.teaching))
        XCTAssertFalse(categories.contains(.publications))
        XCTAssertFalse(categories.contains(.cv))
        XCTAssertFalse(categories.contains(.calendar))
        XCTAssertFalse(categories.contains(.appSettings))
    }

    func testDatabaseExportDescriptorRoundTripsWithoutChangingScope() throws {
        let descriptor = FootprintDatabaseExportDescriptor(
            formatVersion: FootprintDatabaseExportDescriptor.currentFormatVersion,
            exportedAt: "2026-07-28T12:00:00Z",
            categories: [.journals],
            isCompleteDatabase: false,
            payloadDirectoryName: "payload"
        )

        let data = try JSONEncoder().encode(descriptor)
        XCTAssertEqual(try JSONDecoder().decode(FootprintDatabaseExportDescriptor.self, from: data), descriptor)
    }

    func testJournalTransferIdentityMatchesStableIdentifiersDespiteFormatting() {
        let existing = PublicationJournal(
            name: "Journal of Clinical Research",
            issn: "1234-567X",
            eissn: "9876-5432"
        )
        let incoming = PublicationJournal(
            name: "journal  of clinical research",
            issn: "1234567X",
            eissn: "9876 5432"
        )

        XCTAssertGreaterThanOrEqual(existing.transferIdentityMatchScore(with: incoming), 2)
    }

    @MainActor
    func testDestructiveCommitBarrierRejectsEditMadeDuringPreparation() throws {
        let original = GrantApplication(
            id: "application-1",
            rowNumber: 1,
            organization: "Funder",
            grantName: "Original"
        )
        let store = GrantDataStore(applications: [original], skipInitialMigration: true)
        let preparedSnapshot = store.currentSnapshot()
        let preparedArchives = try store.loadArchivedRecords()
        let preparedReceivedGrants = try store.loadReceivedGrantsData()

        var edited = original
        edited.grantName = "Edited while import was preparing"
        store.autosave(application: edited)

        XCTAssertThrowsError(
            try store.requireUnchangedDataForDestructiveCommit(
                snapshot: preparedSnapshot,
                archivedRecords: preparedArchives,
                receivedGrantsData: preparedReceivedGrants
            )
        )
        XCTAssertEqual(store.applications.first?.grantName, edited.grantName)
    }

    @MainActor
    func testSelectiveJournalExportProducesVerifiedImportablePackage() async throws {
        let journal = PublicationJournal(
            id: "journal-transfer-1",
            name: "Journal of Verified Transfers",
            issn: "1234-5678"
        )
        let store = GrantDataStore(
            applications: [
                GrantApplication(
                    id: "application-not-selected",
                    rowNumber: 1,
                    organization: "Funder",
                    grantName: "Not selected"
                )
            ],
            publicationJournals: [journal],
            skipInitialMigration: true
        )
        let destination = isolatedStorageDirectory.appendingPathComponent(
            "journals.footprintdb",
            isDirectory: true
        )

        store.exportDatabasePackage(to: destination, scope: .selectedCategories, categories: [.journals])
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: destination.path) {
            try await Task.sleep(for: .milliseconds(25))
        }

        let descriptorData = try Data(
            contentsOf: destination.appendingPathComponent("database_export.json")
        )
        let descriptor = try JSONDecoder().decode(FootprintDatabaseExportDescriptor.self, from: descriptorData)
        XCTAssertEqual(descriptor.categories, [.journals])
        XCTAssertFalse(descriptor.isCompleteDatabase)

        let payload = try GrantDataStore.decodeRestorePayload(
            from: destination.appendingPathComponent(descriptor.payloadDirectoryName, isDirectory: true)
        )
        XCTAssertEqual(payload.snapshot.publicationJournals.map(\.id), [journal.id])
        XCTAssertTrue(payload.snapshot.applications.isEmpty)

        let localJournal = PublicationJournal(
            id: "local-journal-id",
            name: "journal  of verified transfers",
            issn: journal.issn
        )
        let localApplication = GrantApplication(
            id: "local-application",
            rowNumber: 1,
            organization: "Local funder",
            grantName: "Must remain"
        )
        let importingStore = GrantDataStore(
            applications: [localApplication],
            publicationJournals: [localJournal],
            skipInitialMigration: true
        )
        importingStore.importDatabasePackage(from: destination)
        for _ in 0..<200 where importingStore.backgroundActivityMessage != nil {
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(importingStore.applications.map(\.id), [localApplication.id])
        XCTAssertEqual(importingStore.publicationJournals.count, 1)
        XCTAssertEqual(importingStore.publicationJournals.first?.id, localJournal.id)
        XCTAssertEqual(importingStore.publicationJournals.first?.name, journal.name)
    }

    @MainActor
    func testDatabaseExportPackageContainsAttachmentListAndStillImports() async throws {
        var publication = PublicationRecord(id: "pub-with-pdf", title: "Artikel med PDF", year: "2026")
        let storedURL = try GrantDataStore.persistManagedPublicationPDF(
            data: Data("%PDF-1.4\n%test\n".utf8),
            forPublicationID: publication.id
        )
        publication.finalPDFFilename = "s00000-026-00000-0.pdf"
        publication.finalPDFPath = GrantDataStore.portableAttachmentPath(for: storedURL)
        let store = GrantDataStore(publicationRecords: [publication], skipInitialMigration: true)
        let language = store.language
        let destination = isolatedStorageDirectory.appendingPathComponent(
            "hela.footprintdb",
            isDirectory: true
        )

        store.exportDatabasePackage(to: destination, scope: .entireApp, categories: [])
        for _ in 0..<400 where !FileManager.default.fileExists(atPath: destination.path) {
            try await Task.sleep(for: .milliseconds(25))
        }

        let listURL = destination.appendingPathComponent(GrantDataStore.databaseExportAttachmentListFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: listURL.path))
        let list = try String(contentsOf: listURL, encoding: .utf8)
        XCTAssertTrue(list.contains(language.text("Record label", "Postens etikett")))
        XCTAssertTrue(list.contains(
            "pub-with-pdf;Artikel med PDF (2026).pdf;s00000-026-00000-0.pdf;payload/Publication PDFs/pub-with-pdf.pdf;"
                + language.text("yes", "ja")
        ))

        // The list lies beside the payload; the payload itself is unchanged
        // and still reads as a verified restore payload.
        let descriptorData = try Data(contentsOf: destination.appendingPathComponent("database_export.json"))
        let descriptor = try JSONDecoder().decode(FootprintDatabaseExportDescriptor.self, from: descriptorData)
        let payloadURL = destination.appendingPathComponent(descriptor.payloadDirectoryName, isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: payloadURL.appendingPathComponent(GrantDataStore.databaseExportAttachmentListFileName).path
        ))
        let payload = try GrantDataStore.decodeRestorePayload(from: payloadURL)
        XCTAssertEqual(payload.snapshot.publicationRecords.map(\.id), [publication.id])
    }
}
