import Foundation
import XCTest
@testable import Footprint

final class PersistenceArchitectureTests: XCTestCase {
    func testSingleDomainRelationalSaveDoesNotRebuildUnchangedTables() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("footprint-incremental-relational-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: databaseURL.path + suffix)
                )
            }
        }
        let sqliteStore = try SQLiteDocumentStore(url: databaseURL)
        let encoder = GrantDataStore.makePersistenceEncoder()
        let organization = OrganizationRecord(
            id: "organization-1",
            nameSv: "Oförändrad",
            nameEn: "Unchanged"
        )
        let oldProject = ProjectRecord(id: "project-1", nameSv: "Gammalt", nameEn: "Old")
        let newProject = ProjectRecord(id: "project-1", nameSv: "Nytt", nameEn: "New")
        let unchangedProject = ProjectRecord(id: "project-2", nameSv: "Stabilt", nameEn: "Stable")
        let initial = GrantDataStore.relationalSQLiteSnapshot(
            applications: [],
            metadata: .bundledDefault,
            organizations: [organization],
            projects: [oldProject, unchangedProject],
            publicationAuthors: [],
            publicationRecords: [],
            cvConferenceContributions: []
        )
        let updated = GrantDataStore.relationalSQLiteSnapshot(
            applications: [],
            metadata: .bundledDefault,
            organizations: [organization],
            projects: [newProject, unchangedProject],
            publicationAuthors: [],
            publicationRecords: [],
            cvConferenceContributions: []
        )

        try sqliteStore.saveBatch([
            ("relational_sqlite_snapshot", try encoder.encode(initial))
        ])
        try sqliteStore.saveBatch([
            ("relational_sqlite_snapshot", try encoder.encode(updated))
        ])

        XCTAssertEqual(sqliteStore.lastIncrementalRelationalTablesUpdated, ["rel_projects"])
        XCTAssertEqual(sqliteStore.lastIncrementalRelationalRowChanges, ["rel_projects": 1])
        XCTAssertEqual(try sqliteStore.relationalTableCounts()["rel_organizations"], 1)
        XCTAssertEqual(try sqliteStore.relationalTableCounts()["rel_projects"], 2)
    }

    func testForeignKeyHealthIncludesLegacyRelationalReferenceAudit() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("footprint-relational-reference-audit-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: databaseURL.path + suffix)
                )
            }
        }
        let sqliteStore = try SQLiteDocumentStore(url: databaseURL)
        let encoder = GrantDataStore.makePersistenceEncoder()
        var snapshot = GrantDataStore.relationalSQLiteSnapshot(
            applications: [],
            metadata: .bundledDefault,
            organizations: [],
            projects: [],
            publicationAuthors: [],
            publicationRecords: [],
            cvConferenceContributions: []
        )
        snapshot.applications = [
            RelationalSQLiteApplicationRecord(
                id: "application-1",
                title: "Broken reference fixture",
                organizationID: nil,
                projectID: "missing-project",
                status: ""
            )
        ]

        try sqliteStore.saveBatch([
            ("relational_sqlite_snapshot", try encoder.encode(snapshot))
        ])

        XCTAssertEqual(try sqliteStore.relationalIntegritySummary().brokenReferenceCount, 1)
        XCTAssertEqual(try sqliteStore.foreignKeyViolationCount(), 1)
        XCTAssertFalse(try sqliteStore.storageHealthSummary().foreignKeyCheck.isPassed)
    }
}
