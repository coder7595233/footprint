import XCTest
@testable import Footprint

/// F13b: people who were stored by name only (co-applicants, project members,
/// publication authors, task and meeting participants) also get an id link.
/// The names stay as display text; a name that matches nobody gets no id.
final class PersonIDLinkTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersonIDLinkTests-\(UUID().uuidString)", isDirectory: true)
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

    private func testData<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("TestData/\(name).json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("TestData/\(name).json saknas.")
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    private var anna: PublicationAuthor {
        PublicationAuthor(id: "au-anna", name: "Anna Andersson", firstName: "Anna", lastName: "Andersson")
    }

    private var bo: PublicationAuthor {
        PublicationAuthor(id: "au-bo", name: "Bo Berg", firstName: "Bo", lastName: "Berg")
    }

    @MainActor
    private func makeStore(
        applications: [GrantApplication] = [],
        projects: [ProjectRecord] = [],
        publications: [PublicationRecord] = [],
        currentUserAuthorID: String? = nil,
        interfaceLanguage: String = "sv"
    ) -> GrantDataStore {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = interfaceLanguage
        metadata.currentUserAuthorID = currentUserAuthorID
        return GrantDataStore(
            applications: applications,
            metadata: metadata,
            projects: projects,
            publicationAuthors: [anna, bo],
            publicationRecords: publications,
            skipInitialMigration: true
        )
    }

    // MARK: - Migration

    @MainActor
    func testMigrationFillsIDsAndLeavesNamesAlone() {
        let application = GrantApplication(
            id: "app-1",
            rowNumber: 1,
            organization: "Fonden",
            grantName: "Projektbidrag",
            coApplicants: ["Anna Andersson", "Extern Person", "Bo Berg"]
        )
        let project = ProjectRecord(
            id: "proj-1",
            nameSv: "Hjärtprojekt",
            nameEn: "Heart project",
            collaboratorNames: ["Bo Berg", "Okänd Forskare"]
        )
        let publication = PublicationRecord(
            id: "pub-1",
            title: "Artikel",
            authorNames: ["Anna Andersson", "Någon Annan", "Bo Berg"],
            correspondingAuthorName: "Bo Berg"
        )
        let store = makeStore(applications: [application], projects: [project], publications: [publication])

        let report = store.migratePersonReferencesToIDsForF13b()
        XCTAssertFalse(report.isEmpty, "migreringen rapporterade ingenting")
        XCTAssertTrue(report.allSatisfy { $0.contains("kopplade med id") }, "\(report)")

        let migratedApplication = store.applications.first { $0.id == "app-1" }
        XCTAssertEqual(migratedApplication?.coApplicantAuthorIDs, ["au-anna", "au-bo"])
        XCTAssertEqual(migratedApplication?.coApplicants, ["Anna Andersson", "Extern Person", "Bo Berg"], "namnen ändrades")

        let migratedProject = store.projects.first { $0.id == "proj-1" }
        XCTAssertEqual(migratedProject?.collaboratorAuthorIDs, ["au-bo"], "ett okänt namn fick id")
        XCTAssertEqual(migratedProject?.collaboratorNames, ["Bo Berg", "Okänd Forskare"], "namnen ändrades")

        let migratedPublication = store.publicationRecords.first { $0.id == "pub-1" }
        XCTAssertEqual(migratedPublication?.authorIDs, ["au-anna", "au-bo"])
        XCTAssertEqual(migratedPublication?.correspondingAuthorID, "au-bo")
        XCTAssertEqual(migratedPublication?.authorNames, ["Anna Andersson", "Någon Annan", "Bo Berg"], "namnen ändrades")
        XCTAssertEqual(migratedPublication?.correspondingAuthorName, "Bo Berg")

        XCTAssertEqual(store.applications.count, 1)
        XCTAssertEqual(store.projects.count, 1)
        XCTAssertEqual(store.publicationRecords.count, 1)
    }

    @MainActor
    func testUnknownNamesGetNoID() {
        let project = ProjectRecord(
            id: "proj-1",
            nameSv: "Projekt",
            nameEn: "Project",
            collaboratorNames: ["Okänd Forskare", "Extern Person"]
        )
        let store = makeStore(projects: [project])
        store.migratePersonReferencesToIDsForF13b()
        XCTAssertEqual(store.projects.first?.collaboratorAuthorIDs, [])
        XCTAssertEqual(store.projects.first?.collaboratorNames, ["Okänd Forskare", "Extern Person"])
    }

    @MainActor
    func testRunningTheMigrationTwiceChangesNothing() {
        let application = GrantApplication(
            id: "app-1",
            rowNumber: 1,
            organization: "Fonden",
            grantName: "Projektbidrag",
            coApplicants: ["Anna Andersson", "Bo Berg"]
        )
        let store = makeStore(applications: [application])
        XCTAssertFalse(store.migratePersonReferencesToIDsForF13b().isEmpty)
        let afterFirst = store.applications
        XCTAssertTrue(store.migratePersonReferencesToIDsForF13b().isEmpty, "andra körningen ska inte ändra något")
        XCTAssertEqual(store.applications, afterFirst)
    }

    @MainActor
    func testRealDataGetsIDsWithoutLosingRecordsOrNames() throws {
        let applications = try testData("applications", as: [GrantApplication].self)
        let projects = try testData("projects", as: [ProjectRecord].self)
        let publications = try testData("publication_records", as: [PublicationRecord].self)
        let authors = try testData("publication_authors", as: [PublicationAuthor].self)

        let store = GrantDataStore(
            applications: applications,
            projects: projects,
            publicationAuthors: authors,
            publicationRecords: publications,
            skipInitialMigration: true
        )
        let namesBefore = (
            applications: store.applications.map(\.coApplicants),
            projects: store.projects.map(\.collaboratorNames),
            publications: store.publicationRecords.map(\.authorNames)
        )
        store.migratePersonReferencesToIDsForF13b()

        XCTAssertEqual(store.applications.count, applications.count, "ansökningar försvann")
        XCTAssertEqual(store.projects.count, projects.count, "projekt försvann")
        XCTAssertEqual(store.publicationRecords.count, publications.count, "publikationer försvann")
        XCTAssertEqual(store.applications.map(\.coApplicants), namesBefore.applications, "sökandenas namn ändrades")
        XCTAssertEqual(store.projects.map(\.collaboratorNames), namesBefore.projects, "projektmedarbetarnas namn ändrades")
        XCTAssertEqual(store.publicationRecords.map(\.authorNames), namesBefore.publications, "författarnamnen ändrades")

        let authorIDs = Set(authors.map(\.id))
        let linked = store.applications.flatMap(\.coApplicantAuthorIDs)
            + store.projects.flatMap(\.collaboratorAuthorIDs)
            + store.publicationRecords.flatMap(\.authorIDs)
        XCTAssertGreaterThan(linked.count, 0, "inga personer fick id")
        XCTAssertTrue(linked.allSatisfy(authorIDs.contains), "ett id pekar på en forskare som inte finns")
    }

    // MARK: - Saving keeps the ids in step with the names

    @MainActor
    func testRemovingANameOnSaveAlsoRemovesItsID() {
        let application = GrantApplication(
            id: "app-1",
            rowNumber: 1,
            organization: "Fonden",
            grantName: "Projektbidrag",
            coApplicants: ["Anna Andersson", "Bo Berg"]
        )
        let store = makeStore(applications: [application])
        store.migratePersonReferencesToIDsForF13b()
        guard var edited = store.applications.first(where: { $0.id == "app-1" }) else {
            return XCTFail("ansökan saknas")
        }
        XCTAssertEqual(edited.coApplicantAuthorIDs, ["au-anna", "au-bo"])

        edited.coApplicants = ["Bo Berg"]
        store.autosave(application: edited)

        let saved = store.applications.first { $0.id == "app-1" }
        XCTAssertEqual(saved?.coApplicants, ["Bo Berg"])
        XCTAssertEqual(saved?.coApplicantAuthorIDs, ["au-bo"], "id:t för den borttagna personen blev kvar")
    }

    // MARK: - Renaming a researcher keeps the link

    @MainActor
    func testRenamingTheAuthorKeepsTheIDLinkAndTheLeaderCheck() {
        let application = GrantApplication(
            id: "app-1",
            rowNumber: 1,
            organization: "Fonden",
            grantName: "Projektbidrag",
            coApplicants: ["Anna Andersson", "Bo Berg"]
        )
        let project = ProjectRecord(
            id: "proj-1",
            nameSv: "Hjärtprojekt",
            nameEn: "Heart project",
            collaboratorNames: ["Anna Andersson", "Bo Berg"]
        )
        let otherProject = ProjectRecord(
            id: "proj-2",
            nameSv: "Lungprojekt",
            nameEn: "Lung project",
            collaboratorNames: ["Bo Berg", "Anna Andersson"]
        )
        let store = makeStore(
            applications: [application],
            projects: [project, otherProject],
            currentUserAuthorID: "au-anna"
        )
        store.migratePersonReferencesToIDsForF13b()
        XCTAssertEqual(store.projects.first { $0.id == "proj-1" }?.collaboratorAuthorIDs.first, "au-anna")

        var renamed = anna
        renamed.name = "Anna Lind"
        renamed.lastName = "Lind"
        store.savePublicationAuthor(renamed, previousName: "Anna Andersson")
        XCTAssertEqual(store.publicationAuthor(id: "au-anna")?.name, "Anna Lind")

        let savedProject = store.projects.first { $0.id == "proj-1" }
        XCTAssertEqual(savedProject?.collaboratorAuthorIDs.first, "au-anna", "projektet tappade kopplingen")
        XCTAssertEqual(store.applications.first?.coApplicantAuthorIDs.first, "au-anna", "ansökan tappade kopplingen")

        if let savedProject {
            XCTAssertTrue(store.isCurrentUserProjectLeader(savedProject), "projektledaren känns inte igen efter namnbytet")
        }
        if let savedOtherProject = store.projects.first(where: { $0.id == "proj-2" }) {
            XCTAssertFalse(store.isCurrentUserProjectLeader(savedOtherProject))
        }
        if let savedApplication = store.applications.first {
            XCTAssertTrue(store.isCurrentUserFirstApplicant(savedApplication), "huvudsökande känns inte igen efter namnbytet")
        }
    }

    // MARK: - Grants list, "by project" filter

    @MainActor
    func testProjectFilterMatchesByIDAlsoInEnglish() {
        let project = ProjectRecord(id: "proj-1", nameSv: "Hjärtprojekt", nameEn: "Heart project")
        let other = ProjectRecord(id: "proj-2", nameSv: "Lungprojekt", nameEn: "Lung project")
        let linked = GrantApplication(
            id: "app-1",
            rowNumber: 1,
            organization: "Fonden",
            grantName: "Bidrag A",
            projectID: "proj-1",
            projectType: "Hjärtprojekt"
        )
        let otherLinked = GrantApplication(
            id: "app-2",
            rowNumber: 2,
            organization: "Fonden",
            grantName: "Bidrag B",
            projectID: "proj-2",
            projectType: "Lungprojekt"
        )
        let nameOnly = GrantApplication(
            id: "app-3",
            rowNumber: 3,
            organization: "Fonden",
            grantName: "Bidrag C",
            projectType: "Gammalt projekt"
        )
        let store = makeStore(
            applications: [linked, otherLinked, nameOnly],
            projects: [project, other],
            interfaceLanguage: "en"
        )

        let filter = store.applicationProjectFilter(selectedProjects: ["Hjärtprojekt"])
        XCTAssertTrue(filter.matches(projectID: "proj-1", projectName: "Heart project"), "id:t ska avgöra, inte namnet som visas")
        XCTAssertFalse(filter.matches(projectID: "proj-2", projectName: "Hjärtprojekt"))
        XCTAssertFalse(filter.matches(projectID: nil, projectName: "Gammalt projekt"))

        let rows = store.applicationRowSnapshots()
        let matchingIDs = Set(rows.filter { filter.matches(projectID: $0.projectID, projectName: $0.projectName) }.map(\.id))
        XCTAssertEqual(matchingIDs, ["app-1"])

        let nameFilter = store.applicationProjectFilter(selectedProjects: ["Gammalt projekt"])
        XCTAssertTrue(nameFilter.matches(projectID: nil, projectName: "Gammalt projekt"), "en ansökan utan projekt-id ska hittas på namnet")
        XCTAssertFalse(nameFilter.matches(projectID: "proj-1", projectName: "Hjärtprojekt"))

        XCTAssertTrue(store.applicationProjectFilter(selectedProjects: []).matches(projectID: "proj-2", projectName: nil))
    }

    // MARK: - Stored data

    func testOlderJSONWithoutTheNewKeysStillDecodes() throws {
        let application = try JSONDecoder().decode(
            GrantApplication.self,
            from: Data(#"{"id":"a1","rowNumber":1,"organization":"O","grantName":"G","coApplicants":["Anna Andersson"]}"#.utf8)
        )
        XCTAssertEqual(application.coApplicants, ["Anna Andersson"])
        XCTAssertEqual(application.coApplicantAuthorIDs, [])

        let project = try JSONDecoder().decode(
            ProjectRecord.self,
            from: Data(#"{"id":"p1","nameSv":"Projekt","nameEn":"Project","collaboratorNames":["Anna Andersson"]}"#.utf8)
        )
        XCTAssertEqual(project.collaboratorNames, ["Anna Andersson"])
        XCTAssertEqual(project.collaboratorAuthorIDs, [])

        let publication = try JSONDecoder().decode(
            PublicationRecord.self,
            from: Data(#"{"id":"r1","title":"T","authorNames":["Anna Andersson"],"correspondingAuthorName":"Anna Andersson"}"#.utf8)
        )
        XCTAssertEqual(publication.authorNames, ["Anna Andersson"])
        XCTAssertEqual(publication.authorIDs, [])
        XCTAssertNil(publication.correspondingAuthorID)

        let task = try JSONDecoder().decode(TaskItem.self, from: Data(#"{"id":"t1","participantNames":["Anna Andersson"]}"#.utf8))
        XCTAssertEqual(task.participantAuthorIDs, [])
        let projectTask = try JSONDecoder().decode(ProjectTaskItem.self, from: Data(#"{"id":"t2","participantNames":["Anna Andersson"]}"#.utf8))
        XCTAssertEqual(projectTask.participantAuthorIDs, [])
        let publicationTask = try JSONDecoder().decode(PublicationTaskItem.self, from: Data(#"{"id":"t3","participantNames":["Anna Andersson"]}"#.utf8))
        XCTAssertEqual(publicationTask.participantAuthorIDs, [])
        let meeting = try JSONDecoder().decode(CalendarMeetingRecord.self, from: Data(#"{"id":"m1","participantNames":["Anna Andersson"]}"#.utf8))
        XCTAssertEqual(meeting.participantAuthorIDs, [])
    }

    func testNewIDFieldsSurviveEncoding() throws {
        var application = GrantApplication(id: "a1", rowNumber: 1, organization: "O", grantName: "G", coApplicants: ["Anna Andersson"])
        application.coApplicantAuthorIDs = ["au-anna"]
        XCTAssertEqual(try roundTrip(application).coApplicantAuthorIDs, ["au-anna"])

        var project = ProjectRecord(id: "p1", nameSv: "Projekt", nameEn: "Project", collaboratorNames: ["Anna Andersson"])
        project.collaboratorAuthorIDs = ["au-anna"]
        XCTAssertEqual(try roundTrip(project).collaboratorAuthorIDs, ["au-anna"])

        var publication = PublicationRecord(id: "r1", title: "T", authorNames: ["Anna Andersson"], correspondingAuthorName: "Anna Andersson")
        publication.authorIDs = ["au-anna"]
        publication.correspondingAuthorID = "au-anna"
        let decodedPublication = try roundTrip(publication)
        XCTAssertEqual(decodedPublication.authorIDs, ["au-anna"])
        XCTAssertEqual(decodedPublication.correspondingAuthorID, "au-anna")

        var task = TaskItem(id: "t1", participantNames: ["Anna Andersson"])
        task.participantAuthorIDs = ["au-anna"]
        XCTAssertEqual(try roundTrip(task).participantAuthorIDs, ["au-anna"])

        var meeting = CalendarMeetingRecord(id: "m1", participantNames: ["Anna Andersson"])
        meeting.participantAuthorIDs = ["au-anna"]
        XCTAssertEqual(try roundTrip(meeting).participantAuthorIDs, ["au-anna"])
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }
}
