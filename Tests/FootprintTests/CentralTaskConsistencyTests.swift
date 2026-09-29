import XCTest
@testable import Footprint

final class CentralTaskConsistencyTests: XCTestCase {
    private var storageDirectory: URL!

    // Storage isolation is NOT automatic under this test runner — a store
    // without this override reads and writes the user's real database.
    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CentralTaskConsistencyTests-\(UUID().uuidString)", isDirectory: true)
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

    private let overdueDay = "2020-01-01"

    @MainActor
    private func makeProjectWithLegacyTask(taskID: String) -> ProjectRecord {
        var project = ProjectRecord(nameSv: "Exempelprojekt", nameEn: "Exempelprojekt")
        var task = ProjectTaskItem()
        task.id = taskID
        task.comment = "Svar från Charlotta Mård om budget?"
        task.deadline = overdueDay
        project.projectTasks = [task]
        return project
    }

    @MainActor
    func testStaleLegacyTaskWithoutCentralCopyStillWarns() {
        let project = makeProjectWithLegacyTask(taskID: "task-1")
        let store = GrantDataStore(projects: [project])

        let overdue = store.dataQualityIntegrityIssues().filter { $0.subtitle.contains("Overdue project task") }
        XCTAssertEqual(overdue.count, 1)
        XCTAssertNotNil(overdue.first?.calendarRevealDayString)
    }

    @MainActor
    func testCentralCopySupersedesLegacyTask() {
        let project = makeProjectWithLegacyTask(taskID: "task-1")
        // The user rescheduled the task centrally: same id, future deadline.
        var metadata = DataSourceMetadata.bundledDefault
        metadata.taskItems = [
            TaskItem(id: "task-1", deadline: "2099-12-31", comment: "Svar om budget?")
        ]
        let store = GrantDataStore(metadata: metadata, projects: [project])

        let overdue = store.dataQualityIntegrityIssues().filter {
            $0.subtitle.contains("Overdue project task") || $0.subtitle == "Overdue task"
        }
        XCTAssertTrue(overdue.isEmpty, "a rescheduled central task must silence the stale legacy copy")
    }

    @MainActor
    func testOverdueCentralTaskWarnsWithCalendarReveal() {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.taskItems = [
            TaskItem(id: "task-2", deadline: overdueDay, comment: "Läs ansökan")
        ]
        let store = GrantDataStore(metadata: metadata)

        let overdue = store.dataQualityIntegrityIssues().filter { $0.subtitle.contains("Overdue task") }
        XCTAssertEqual(overdue.count, 1)
        XCTAssertEqual(overdue.first?.calendarRevealDayString, overdueDay)
        if case .teachingTask(let taskID)? = overdue.first?.calendarEventSource {
            XCTAssertEqual(taskID, "task-2")
        } else {
            XCTFail("central task reveal must use the .teachingTask source the calendar rows carry")
        }
    }

    @MainActor
    func testMigrationPromotesEveryLegacyTaskKindToCentral() {
        var project = ProjectRecord(id: "project-1", nameSv: "Projekt", nameEn: "Project")
        project.projectTasks = [ProjectTaskItem(id: "t-project", deadline: overdueDay, comment: "Projektuppgift")]

        var congress = OrganizationCongress(id: "congress-1", title: "Kongress")
        congress.tasks = [ProjectTaskItem(id: "t-congress", deadline: overdueDay, comment: "Kongressuppgift")]
        var organization = OrganizationRecord(id: "org-1", nameSv: "Organisation", nameEn: "Organisation")
        organization.projectTasks = [ProjectTaskItem(id: "t-organization", deadline: overdueDay, comment: "Organisationsuppgift")]
        organization.congresses = [congress]

        var publication = PublicationRecord(id: "publication-1", title: "Publikation", year: "2025")
        publication.publicationTasks = [
            PublicationTaskItem(id: "t-publication", deadline: overdueDay, comment: "Publikationsuppgift"),
        ]

        var assignment = TeachingAssignment(id: "assignment-1", authorID: "author", activityName: "Föreläsning")
        assignment.tasks = [PublicationTaskItem(id: "t-assignment", deadline: overdueDay, comment: "Uppdragsuppgift")]

        var course = TeachingCourse(id: "course-1", name: "Kurs")
        course.tasks = [PublicationTaskItem(id: "t-course", deadline: overdueDay, comment: "Kursuppgift")]

        var candidate = DoctoralCandidateRecord(id: "candidate-1")
        candidate.tasks = [ProjectTaskItem(id: "t-candidate", deadline: overdueDay, comment: "Doktoranduppgift")]

        var contribution = CVConferenceContribution(id: "contribution-1")
        contribution.tasks = [PublicationTaskItem(id: "t-contribution", deadline: overdueDay, comment: "Bidraguppgift")]

        var metadata = DataSourceMetadata.bundledDefault
        metadata.teachingWorkspaceTasks = [
            PublicationTaskItem(id: "t-general", deadline: overdueDay, comment: "Allmän uppgift"),
        ]

        let store = GrantDataStore(
            metadata: metadata,
            organizations: [organization],
            projects: [project],
            teachingCourses: [course],
            teachingAssignments: [assignment],
            doctoralCandidates: [candidate],
            cvConferenceContributions: [contribution],
            publicationRecords: [publication]
        )

        store.migrateLegacyTasksToCentral()

        let central = Dictionary(uniqueKeysWithValues: store.taskItems.map { ($0.id, $0) })
        XCTAssertEqual(
            Set(central.keys),
            [
                "t-project", "t-organization", "t-congress", "t-publication",
                "t-assignment", "t-course", "t-candidate", "t-contribution", "t-general",
            ]
        )
        XCTAssertEqual(central["t-project"]?.links, [TaskLink(kind: .project, targetID: "project-1")])
        XCTAssertEqual(central["t-organization"]?.links, [TaskLink(kind: .organization, targetID: "org-1")])
        XCTAssertEqual(
            central["t-congress"]?.links,
            [TaskLink(kind: .congress, targetID: "congress-1", ownerID: "org-1")]
        )
        XCTAssertEqual(central["t-publication"]?.links, [TaskLink(kind: .publication, targetID: "publication-1")])
        XCTAssertEqual(central["t-assignment"]?.links, [TaskLink(kind: .teachingAssignment, targetID: "assignment-1")])
        XCTAssertEqual(central["t-course"]?.links, [TaskLink(kind: .teachingCourse, targetID: "course-1")])
        XCTAssertEqual(central["t-candidate"]?.links, [TaskLink(kind: .doctoralCandidate, targetID: "candidate-1")])
        XCTAssertEqual(central["t-contribution"]?.links, [TaskLink(kind: .conferenceContribution, targetID: "contribution-1")])
        XCTAssertEqual(central["t-general"]?.links, [])
        XCTAssertEqual(central["t-project"]?.deadline, overdueDay)
        XCTAssertEqual(central["t-project"]?.comment, "Projektuppgift")

        XCTAssertTrue(store.projects.allSatisfy(\.projectTasks.isEmpty))
        XCTAssertTrue(store.organizations.allSatisfy(\.projectTasks.isEmpty))
        XCTAssertTrue(store.organizations.flatMap(\.congresses).allSatisfy(\.tasks.isEmpty))
        XCTAssertTrue(store.publicationRecords.allSatisfy(\.publicationTasks.isEmpty))
        XCTAssertTrue(store.teachingAssignments.allSatisfy(\.tasks.isEmpty))
        XCTAssertTrue(store.teachingCourses.allSatisfy(\.tasks.isEmpty))
        XCTAssertTrue(store.doctoralCandidates.allSatisfy(\.tasks.isEmpty))
        XCTAssertTrue(store.cvConferenceContributions.allSatisfy(\.tasks.isEmpty))
        XCTAssertEqual(store.teachingWorkspaceTasks, [])
    }

    @MainActor
    func testMigrationKeepsExistingCentralCopyAndDropsLegacy() {
        let project = makeProjectWithLegacyTask(taskID: "task-1")
        var metadata = DataSourceMetadata.bundledDefault
        metadata.taskItems = [
            TaskItem(id: "task-1", deadline: "2099-12-31", comment: "Centralt schemalagd"),
        ]
        let store = GrantDataStore(metadata: metadata, projects: [project])

        store.migrateLegacyTasksToCentral()

        XCTAssertEqual(store.taskItems.count, 1)
        XCTAssertEqual(store.taskItems.first?.deadline, "2099-12-31", "the central copy is the source of truth")
        XCTAssertTrue(store.projects.allSatisfy(\.projectTasks.isEmpty))
    }

    @MainActor
    func testReminderEngineIgnoresSupersededTeachingAssignmentTasks() {
        var assignment = TeachingAssignment(id: "assignment-1", authorID: "author", activityName: "Föreläsning")
        assignment.tasks = [
            PublicationTaskItem(id: "task-1", deadline: overdueDay, comment: "Gammal deadline"),
        ]
        var metadata = DataSourceMetadata.bundledDefault
        metadata.taskItems = [
            TaskItem(id: "task-1", deadline: "2099-12-31", comment: "Gammal deadline"),
        ]
        let store = GrantDataStore(metadata: metadata, teachingAssignments: [assignment])

        let entries = calendarTaskReminderEntries(store: store, language: .swedish, calendar: .current)

        let staleEntries = entries.filter { entry in
            entry.title == "Gammal deadline" && entry.displayDate < Date()
        }
        XCTAssertTrue(
            staleEntries.isEmpty,
            "a centrally rescheduled teaching-assignment task must not remind on its stale legacy deadline"
        )
    }

    @MainActor
    func testCleanupRemovesSupersededLegacyCopiesOnly() {
        let superseded = makeProjectWithLegacyTask(taskID: "task-1")
        let genuine = makeProjectWithLegacyTask(taskID: "task-9")
        var metadata = DataSourceMetadata.bundledDefault
        metadata.taskItems = [
            TaskItem(id: "task-1", deadline: "2099-12-31", comment: "Svar om budget?")
        ]
        let store = GrantDataStore(metadata: metadata, projects: [superseded, genuine])

        store.removeLegacyTaskCopiesSupersededByCentral()

        let tasksByProject = Dictionary(
            uniqueKeysWithValues: store.projects.map { ($0.id, $0.projectTasks.map(\.id)) }
        )
        XCTAssertEqual(tasksByProject[superseded.id], [], "superseded legacy copy must be removed")
        XCTAssertEqual(tasksByProject[genuine.id], ["task-9"], "genuine legacy task must survive")
    }
}
