import XCTest
@testable import Footprint

/// F13: references between records are kept by id; names follow renames.
final class NameReferenceIDTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NameReferenceIDTests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: - Real data

    @MainActor
    func testRealTeachingDataGetsIDsWithoutLosingRecords() throws {
        let organizations = try testData("organizations", as: [OrganizationRecord].self)
        let courses = try testData("teaching_courses", as: [TeachingCourse].self)
        let components = try testData("teaching_components", as: [TeachingComponent].self)
        let formats = try testData("teaching_formats", as: [TeachingFormatOption].self)
        let assignments = try testData("teaching_assignments", as: [TeachingAssignment].self)
        let authors = try testData("publication_authors", as: [PublicationAuthor].self)

        let store = GrantDataStore(
            organizations: organizations,
            teachingCourses: courses,
            teachingComponents: components,
            teachingFormats: formats,
            teachingAssignments: assignments,
            publicationAuthors: authors,
            skipInitialMigration: true
        )
        store.migrateNameReferencesToIDsForF13()

        XCTAssertEqual(store.teachingAssignments.count, assignments.count, "uppdrag försvann")
        XCTAssertEqual(store.teachingComponents.count, components.count, "moment försvann")
        XCTAssertEqual(store.teachingFormats.count, formats.count, "format försvann")

        let formatIDs = Set(store.teachingFormats.map(\.id))
        let linkedFormats = store.teachingAssignments.compactMap(\.activityTypeID)
        XCTAssertGreaterThan(linkedFormats.count, 0, "inga uppdrag fick format-id")
        XCTAssertTrue(linkedFormats.allSatisfy(formatIDs.contains), "ett uppdrag pekar på ett format som inte finns")

        let organizationIDs = Set(store.organizations.map(\.id))
        let linkedOrganizations = store.teachingComponents.compactMap(\.institutionID)
        XCTAssertGreaterThan(linkedOrganizations.count, 0, "inga moment fick organisations-id")
        XCTAssertTrue(linkedOrganizations.allSatisfy(organizationIDs.contains))

        // Names are never removed: every name that was there is still there.
        for original in assignments where original.activityTypeName.nonEmpty != nil {
            let migrated = store.teachingAssignments.first { $0.id == original.id }
            XCTAssertNotNil(migrated?.activityTypeName.nonEmpty, "\(original.id) tappade sitt formatnamn")
        }
        for original in assignments where original.studentName.nonEmpty != nil {
            let migrated = store.teachingAssignments.first { $0.id == original.id }
            XCTAssertNotNil(migrated?.studentName.nonEmpty, "\(original.id) tappade studentens namn")
        }
    }

    @MainActor
    func testRunningTheMigrationTwiceChangesNothing() throws {
        let formats = try testData("teaching_formats", as: [TeachingFormatOption].self)
        let assignments = try testData("teaching_assignments", as: [TeachingAssignment].self)
        let store = GrantDataStore(teachingFormats: formats, teachingAssignments: assignments, skipInitialMigration: true)
        store.migrateNameReferencesToIDsForF13()
        let afterFirst = store.teachingAssignments
        XCTAssertTrue(store.migrateNameReferencesToIDsForF13().isEmpty, "andra körningen ska inte ändra något")
        XCTAssertEqual(store.teachingAssignments, afterFirst)
    }

    // MARK: - Renames follow the id

    @MainActor
    func testRenamingAFormatFollowsThroughToMomentsAndAssignments() {
        let format = TeachingFormatOption(id: "f1", name: "Föreläsning")
        let component = TeachingComponent(id: "m1", name: "Introduktion", activityTypeName: "Föreläsning")
        let assignment = TeachingAssignment(id: "a1", activityTypeName: "Föreläsning")
        let store = GrantDataStore(
            teachingComponents: [component],
            teachingFormats: [format],
            teachingAssignments: [assignment],
            skipInitialMigration: true
        )
        store.migrateNameReferencesToIDsForF13()
        XCTAssertEqual(store.teachingAssignments.first?.activityTypeID, "f1")

        var renamed = format
        renamed.name = "Storföreläsning"
        store.saveTeachingFormat(renamed)

        XCTAssertEqual(store.teachingAssignments.first { $0.id == "a1" }?.activityTypeName, "Storföreläsning")
        XCTAssertEqual(store.teachingComponents.first { $0.id == "m1" }?.activityTypeName, "Storföreläsning")
        XCTAssertEqual(store.teachingComponents.first { $0.id == "m1" }?.activityTypeID, "f1")
    }

    @MainActor
    func testPickingAnotherFormatByNameMovesTheID() {
        let lecture = TeachingFormatOption(id: "f1", name: "Föreläsning")
        let seminar = TeachingFormatOption(id: "f2", name: "Seminarium")
        let store = GrantDataStore(
            teachingFormats: [lecture, seminar],
            teachingAssignments: [TeachingAssignment(id: "a1", activityTypeName: "Föreläsning")],
            skipInitialMigration: true
        )
        store.migrateNameReferencesToIDsForF13()
        guard var edited = store.teachingAssignments.first(where: { $0.id == "a1" }) else {
            return XCTFail("uppdraget saknas")
        }
        XCTAssertEqual(edited.activityTypeID, "f1")
        edited.activityTypeName = "Seminarium"
        store.autosaveTeachingAssignment(edited)

        let saved = store.teachingAssignments.first { $0.id == "a1" }
        XCTAssertEqual(saved?.activityTypeID, "f2", "id:t följde inte med bytet")
        XCTAssertEqual(saved?.activityTypeName, "Seminarium", "namnet återställdes från det gamla id:t")
    }

    @MainActor
    func testAFormatNameThatMatchesNothingStaysAsText() {
        let store = GrantDataStore(
            teachingFormats: [TeachingFormatOption(id: "f1", name: "Föreläsning")],
            teachingAssignments: [TeachingAssignment(id: "a1", activityTypeName: "Individuell handledning")],
            skipInitialMigration: true
        )
        store.migrateNameReferencesToIDsForF13()
        let saved = store.teachingAssignments.first { $0.id == "a1" }
        XCTAssertNil(saved?.activityTypeID)
        XCTAssertEqual(saved?.activityTypeName, "Individuell handledning")
    }

    @MainActor
    func testRenamingAJournalFollowsThroughToPublicationsAndEarlierAttempts() {
        let journal = PublicationJournal(id: "j1", name: "Old Journal")
        var publication = PublicationRecord(id: "p1", title: "Artikel", journal: "Old Journal")
        publication.previousAttempts = [PublicationAttempt(journal: "Old Journal", submittedOn: "2025-01-01", rejectedOn: "2025-02-01")]
        let store = GrantDataStore(
            publicationJournals: [journal],
            publicationRecords: [publication],
            skipInitialMigration: true
        )
        store.migrateNameReferencesToIDsForF13()
        XCTAssertEqual(store.publicationRecords.first?.journalID, "j1")

        var renamed = journal
        renamed.name = "New Journal"
        store.savePublicationJournal(renamed, previousName: "Old Journal")

        let saved = store.publicationRecords.first { $0.id == "p1" }
        XCTAssertEqual(saved?.journal, "New Journal")
        XCTAssertEqual(saved?.journalID, "j1")
        XCTAssertEqual(saved?.previousAttempts.first?.journal, "New Journal")
        XCTAssertEqual(saved?.previousAttempts.first?.journalID, "j1")
    }

    func testNewIDFieldsSurviveEncodingAndOlderDataDecodes() throws {
        var assignment = TeachingAssignment(id: "a1", activityTypeName: "Föreläsning", studentName: "Anna")
        assignment.activityTypeID = "f1"
        assignment.studentAuthorID = "au1"
        let decoded = try JSONDecoder().decode(TeachingAssignment.self, from: JSONEncoder().encode(assignment))
        XCTAssertEqual(decoded.activityTypeID, "f1")
        XCTAssertEqual(decoded.studentAuthorID, "au1")

        let older = #"{"id":"m1","nameSv":"Moment","nameEn":"Moment","institution":"EXU","activityTypeName":"","allowedContextIDs":[]}"#
        let component = try JSONDecoder().decode(TeachingComponent.self, from: Data(older.utf8))
        XCTAssertNil(component.institutionID)
        XCTAssertEqual(component.institution, "EXU")
    }
}
