import Foundation
import SwiftUI
import XCTest
@testable import Footprint

final class ArchitecturePerformanceBudgetTests: XCTestCase {
    func testVisitedWorkspaceTreesAreRetained() {
        XCTAssertEqual(WorkspaceMountPolicy.maximumMountedWorkspaceCount, Int.max)
    }

    @MainActor
    func testWorkspaceFilterStateSurvivesWorkspaceReconstruction() {
        let key = "ArchitecturePerformanceBudgetTests.Filter.\(UUID().uuidString)"
        let scopedKey = AppRuntime.scopedDefaultsKey(key)
        defer { UserDefaults.standard.removeObject(forKey: scopedKey) }

        let first = WorkspaceFilterState(wrappedValue: Set<String>(), key)
        first.wrappedValue = ["active", "own"]
        let reconstructed = WorkspaceFilterState(wrappedValue: Set<String>(), key)
        let restored = reconstructed.wrappedValue

        XCTAssertEqual(restored, ["active", "own"])
    }

    @MainActor
    func testDomainProjectionDoesNotInvalidateUnrelatedWorkspace() throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("footprint-projection-budget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        setenv("FOOTPRINT_STORAGE_DIRECTORY", storageDirectory.path, 1)
        defer {
            unsetenv("FOOTPRINT_STORAGE_DIRECTORY")
            try? FileManager.default.removeItem(at: storageDirectory)
        }

        let store = GrantDataStore(skipInitialMigration: true)
        let applications = DataStoreDomainProjection(store: store, domain: .applications)
        let projects = DataStoreDomainProjection(store: store, domain: .projects)
        let status = DataStoreDomainProjection(store: store, domain: .status)
        XCTAssertEqual(applications.revision, 0)
        XCTAssertEqual(projects.revision, 0)
        XCTAssertEqual(status.revision, 0)
        let applicationRevision = applications.revision
        let projectRevision = projects.revision
        let statusRevision = status.revision

        store.notice = StoreNotice(message: "Fixture", tone: .info)

        XCTAssertEqual(applications.revision, applicationRevision)
        XCTAssertEqual(projects.revision, projectRevision)
        XCTAssertGreaterThan(status.revision, statusRevision)

        DataStoreBodyUpdateInstrumentation.reset()
        applications.recordBodyEvaluation()
        applications.recordBodyEvaluation()
        projects.recordBodyEvaluation()
        XCTAssertEqual(DataStoreBodyUpdateInstrumentation.count(for: .applications), 2)
        XCTAssertEqual(DataStoreBodyUpdateInstrumentation.count(for: .projects), 1)
        XCTAssertEqual(DataStoreBodyUpdateInstrumentation.count(for: .status), 0)

        let firstHost = DataStoreDomainProjectionHost(
            store: store,
            domain: .applications,
            inputKey: "stable-input"
        ) { _ in EmptyView() }
        let equivalentHost = DataStoreDomainProjectionHost(
            store: store,
            domain: .applications,
            inputKey: "stable-input"
        ) { _ in EmptyView() }
        let changedHost = DataStoreDomainProjectionHost(
            store: store,
            domain: .applications,
            inputKey: "changed-input"
        ) { _ in EmptyView() }
        XCTAssertEqual(firstHost, equivalentHost)
        XCTAssertNotEqual(firstHost, changedHost)
        XCTAssertTrue(store.flushAllPendingPersistenceIfNeeded())
        XCTAssertTrue(GrantDataStore.waitForPendingPeriodicBackupWork(timeout: 10))
    }

    @MainActor
    func testNavigationProjectionInvalidatesForEveryInternalLinkTrigger() throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("footprint-navigation-projection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        setenv("FOOTPRINT_STORAGE_DIRECTORY", storageDirectory.path, 1)
        defer {
            unsetenv("FOOTPRINT_STORAGE_DIRECTORY")
            try? FileManager.default.removeItem(at: storageDirectory)
        }

        let store = GrantDataStore(skipInitialMigration: true)
        let navigation = DataStoreDomainProjection(store: store, domain: .navigation)

        func assertInvalidates(_ mutation: () -> Void, file: StaticString = #filePath, line: UInt = #line) {
            let previousRevision = navigation.revision
            mutation()
            XCTAssertGreaterThan(navigation.revision, previousRevision, file: file, line: line)
        }

        assertInvalidates {
            store.route = AppRoute(recordID: "researcher-1", destination: .people)
        }
        assertInvalidates {
            store.route = AppRoute(recordID: "project-1", destination: .projects)
        }
        assertInvalidates {
            store.pendingCongressRouteToken = UUID()
        }
        assertInvalidates {
            store.pendingCalendarOpenRequest = CalendarOpenRequest(kind: .projectTask(projectID: "project-1"), recordID: "task-1")
        }
        assertInvalidates {
            store.pendingCalendarRevealRequest = CalendarRevealRequest(dayString: "2026-08-04")
        }
        assertInvalidates {
            store.pendingCalendarRevealToken = UUID()
        }
        assertInvalidates {
            store.undoRevealRequest = UndoRevealRequest(
                target: UndoRevealTarget(
                    destination: .route(AppRoute(recordID: "publication-1", destination: .publications))
                ),
                actionName: "Test",
                isRedo: false
            )
        }
    }

    func testProductionScaleSingleRowRelationalUpdateBudget() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("footprint-relational-budget-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: databaseURL.path + suffix)
                )
            }
        }
        let store = try SQLiteDocumentStore(url: databaseURL)
        let encoder = GrantDataStore.makePersistenceEncoder()
        let projects = (0..<5_000).map {
            RelationalSQLiteProjectRecord(
                id: "project-\($0)",
                nameSv: "Projekt \($0)",
                nameEn: "Project \($0)"
            )
        }
        var initial = GrantDataStore.relationalSQLiteSnapshot(
            applications: [],
            metadata: .bundledDefault,
            organizations: [],
            projects: [],
            publicationAuthors: [],
            publicationRecords: [],
            cvConferenceContributions: []
        )
        initial.projects = projects
        try store.saveBatch([
            ("relational_sqlite_snapshot", try encoder.encode(initial))
        ])

        var updated = initial
        updated.projects[2_500].nameEn = "Changed"
        let clock = ContinuousClock()
        let startedAt = clock.now
        try store.saveBatch([
            ("relational_sqlite_snapshot", try encoder.encode(updated))
        ])
        let elapsed = startedAt.duration(to: clock.now)

        XCTAssertEqual(store.lastIncrementalRelationalTablesUpdated, ["rel_projects"])
        XCTAssertEqual(store.lastIncrementalRelationalRowChanges, ["rel_projects": 1])
        XCTAssertEqual(try store.relationalTableCounts()["rel_projects"], 5_000)
        XCTAssertLessThan(
            elapsed,
            .seconds(2),
            "A one-row relational/search update exceeded the 2 s CI safety budget for 5,000 rows."
        )
    }

    func testProductionScaleRelationalSnapshotDerivationBudget() {
        let projects = (0..<10_000).map {
            ProjectRecord(
                id: "project-\($0)",
                nameSv: "Projekt \($0)",
                nameEn: "Project \($0)"
            )
        }
        let clock = ContinuousClock()
        let startedAt = clock.now
        let snapshot = GrantDataStore.relationalSQLiteSnapshot(
            applications: [],
            metadata: .bundledDefault,
            organizations: [],
            projects: projects,
            publicationAuthors: [],
            publicationRecords: [],
            cvConferenceContributions: []
        )
        let elapsed = startedAt.duration(to: clock.now)

        XCTAssertEqual(snapshot.projects.count, projects.count)
        XCTAssertLessThan(
            elapsed,
            .seconds(2),
            "Relational snapshot derivation exceeded the 2 s CI safety budget for 10,000 projects."
        )
    }

    @MainActor
    func testCalendarLinkedIndexIsReusedAtProductionScale() throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("footprint-calendar-index-budget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        setenv("FOOTPRINT_STORAGE_DIRECTORY", storageDirectory.path, 1)
        defer {
            unsetenv("FOOTPRINT_STORAGE_DIRECTORY")
            try? FileManager.default.removeItem(at: storageDirectory)
        }

        let projectID = "project-1"
        let futureMeetingDate = DateParsers.isoDay.string(
            from: try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: Date()))
        )
        let updatedFutureMeetingDate = DateParsers.isoDay.string(
            from: try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 2, to: Date()))
        )
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarMeetingRecords = (0..<2_000).map { index in
            CalendarMeetingRecord(
                id: "meeting-\(index)",
                date: futureMeetingDate,
                title: "Meeting \(index)",
                projectIDs: index.isMultiple(of: 10) ? [projectID] : []
            )
        }
        let store = GrantDataStore(
            metadata: metadata,
            projects: [ProjectRecord(id: projectID, nameSv: "Projekt", nameEn: "Project")],
            skipInitialMigration: true
        )

        let clock = ContinuousClock()
        let firstStartedAt = clock.now
        let firstRows = calendarLinkedEventRows(
            store: store,
            language: .english,
            scope: .project(projectID)
        )
        let firstElapsed = firstStartedAt.duration(to: clock.now)
        let secondStartedAt = clock.now
        let secondRows = calendarLinkedEventRows(
            store: store,
            language: .english,
            scope: .project(projectID)
        )
        let secondElapsed = secondStartedAt.duration(to: clock.now)

        XCTAssertEqual(firstRows, secondRows)
        XCTAssertEqual(firstRows.count, 200)
        XCTAssertEqual(store.calendarLinkedEventIndexBuildCount, 1)
        XCTAssertLessThan(firstElapsed, .seconds(1))
        XCTAssertLessThan(secondElapsed, .milliseconds(100))

        var updatedMetadata = store.editableMetadataSnapshot
        updatedMetadata.calendarMeetingRecords?.append(
            CalendarMeetingRecord(
                id: "meeting-new",
                date: updatedFutureMeetingDate,
                title: "New",
                projectIDs: [projectID]
            )
        )
        store.persistMetadataSilently(updatedMetadata, includeBackup: false)
        _ = calendarLinkedEventRows(store: store, language: .english, scope: .project(projectID))
        XCTAssertEqual(store.calendarLinkedEventIndexBuildCount, 2)
        XCTAssertTrue(store.flushAllPendingPersistenceIfNeeded())
    }

    func testProductionScaleProjectTimelineSnapshotsStayWithinBudget() {
        let applications = (0..<2_000).map { index in
            GrantApplication(
                id: "application-\(index)",
                rowNumber: index,
                organization: "Funder \(index % 25)",
                grantName: "Grant \(index)",
                firstDispositionOn: "2024-01-01",
                lastDispositionOn: "2028-12-31",
                projectID: "project-1",
                grantedOn: "2024-01-01",
                grantedAmountValue: Double(index + 1) * 1_000,
                result: "Beviljat"
            )
        }
        let organizationLabels = Dictionary(
            uniqueKeysWithValues: (0..<25).map { ("Funder \($0)", "Funder \($0)") }
        )
        let effectiveRemainingAmounts = Dictionary(
            uniqueKeysWithValues: applications.map { ($0.id, $0.grantedAmountValue ?? 0) }
        )
        let clock = ContinuousClock()
        let startedAt = clock.now
        let complete = GrantDataStore.buildProjectTimelineSnapshot(
            project: ProjectRecord(id: "project-1", nameSv: "Projekt", nameEn: "Project"),
            orderedTimelineApplications: applications,
            publications: [],
            organizationLabels: organizationLabels,
            language: .english,
            effectiveRemainingAmountsByApplicationID: effectiveRemainingAmounts
        )
        let owned = GrantDataStore.buildProjectTimelineSnapshot(
            project: ProjectRecord(id: "project-1", nameSv: "Projekt", nameEn: "Project"),
            orderedTimelineApplications: Array(applications.prefix(1_000)),
            publications: [],
            organizationLabels: organizationLabels,
            language: .english,
            effectiveRemainingAmountsByApplicationID: effectiveRemainingAmounts
        )
        let elapsed = startedAt.duration(to: clock.now)

        XCTAssertEqual(complete.grantBars.count, 2_000)
        XCTAssertEqual(owned.grantBars.count, 1_000)
        XCTAssertLessThan(
            elapsed,
            .seconds(3),
            "Building both cached project timeline variants exceeded the 3 s CI budget."
        )
    }

    @MainActor
    func testCompleteProjectViewSnapshotIsReusedWithinSelectionBudget() throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("footprint-project-view-budget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        setenv("FOOTPRINT_STORAGE_DIRECTORY", storageDirectory.path, 1)
        defer {
            unsetenv("FOOTPRINT_STORAGE_DIRECTORY")
            try? FileManager.default.removeItem(at: storageDirectory)
        }

        let project = ProjectRecord(id: "project-1", nameSv: "Projekt", nameEn: "Project")
        let applications = (0..<200).map { index in
            GrantApplication(
                id: "application-\(index)",
                rowNumber: index,
                organization: "Funder \(index % 10)",
                grantName: "Grant \(index)",
                firstDispositionOn: "2024-01-01",
                lastDispositionOn: "2028-12-31",
                projectID: project.id,
                projectType: project.nameSv,
                grantedOn: "2024-01-01",
                grantedAmountValue: Double(index + 1) * 1_000,
                result: "Beviljat"
            )
        }
        let store = GrantDataStore(
            applications: applications,
            projects: [project],
            skipInitialMigration: true
        )

        let first = store.projectViewData(forProjectName: project.nameSv, language: .english)
        XCTAssertEqual(first?.relatedApplications.count, applications.count)
        XCTAssertEqual(first?.timelineSnapshot.grantBars.count, applications.count)

        let clock = ContinuousClock()
        let startedAt = clock.now
        for _ in 0..<100 {
            let reused = store.projectViewData(forProjectName: project.nameSv, language: .english)
            XCTAssertEqual(reused?.relatedApplications.count, applications.count)
        }
        let elapsed = startedAt.duration(to: clock.now)

        XCTAssertLessThan(
            elapsed,
            .milliseconds(250),
            "Reusing a complete project snapshot exceeded the 2.5 ms per-selection CI budget."
        )
        XCTAssertTrue(store.flushAllPendingPersistenceIfNeeded())
    }

    @MainActor
    func testProductionJournalRowsDoNotSynthesizeLTWAOnListOpen() throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("footprint-journal-row-budget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        setenv("FOOTPRINT_STORAGE_DIRECTORY", storageDirectory.path, 1)
        defer {
            unsetenv("FOOTPRINT_STORAGE_DIRECTORY")
            try? FileManager.default.removeItem(at: storageDirectory)
        }

        let journals = (0..<3_100).map { index in
            PublicationJournal(
                id: "journal-\(index)",
                name: "International Journal of Example Medicine and Science \(index)",
                abbreviatedName: "Int J Example \(index)",
                category: "Medicine"
            )
        }
        let store = GrantDataStore(
            publicationJournals: journals,
            skipInitialMigration: true
        )

        let clock = ContinuousClock()
        let startedAt = clock.now
        let snapshots = store.publicationJournalRowSnapshots()
        let elapsed = startedAt.duration(to: clock.now)

        XCTAssertEqual(snapshots.count, journals.count)
        XCTAssertLessThan(
            elapsed,
            .seconds(1),
            "Building production-scale journal list rows exceeded the one-second safety budget."
        )
    }

    func testDiagnosticPrivacyRedactionBudget() {
        let message = "project=Example id=123E4567-E89B-12D3-A456-426614174000 author=Person email=test@example.com duration_ms=12.4"
        let clock = ContinuousClock()
        let startedAt = clock.now
        for _ in 0..<5_000 {
            _ = PerformanceDiagnosticPrivacy.redact(message)
        }
        let elapsed = startedAt.duration(to: clock.now)

        XCTAssertLessThan(elapsed, .seconds(2))
    }
}
