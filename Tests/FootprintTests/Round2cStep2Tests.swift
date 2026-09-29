import XCTest
@testable import Footprint

final class Round2cStep2Tests: XCTestCase {
    private var storageDirectory: URL!

    // F34: every test gets its own storage folder, as in the other suites, so
    // no test can write over records another test (or the user) left behind.
    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Round2cStep2Tests-\(UUID().uuidString)", isDirectory: true)
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

    private func storedCourses() throws -> [TeachingCourse] {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("TestData/teaching_courses.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("TestData/teaching_courses.json saknas.")
        }
        return try JSONDecoder().decode([TeachingCourse].self, from: Data(contentsOf: url))
    }

    @MainActor
    func testMigrationKeepsEveryCourseAndLinksProgrammes() throws {
        let courses = try storedCourses()
        let store = GrantDataStore(metadata: .bundledDefault, teachingCourses: courses)
        let report = store.migrateTeachingCatalogForRound2c()

        XCTAssertEqual(store.teachingCourses.count, courses.count, "migreringen tappade poster")
        XCTAssertFalse(report.isEmpty, "migreringen borde ha kopplat program")

        let linked = store.teachingCourses.filter { $0.contextType != .programTrack && $0.programID != nil }
        XCTAssertGreaterThan(linked.count, 0)
        let programmeIDs = Set(store.teachingCourses.filter { $0.contextType == .programTrack }.map(\.id))
        for course in linked {
            XCTAssertTrue(programmeIDs.contains(course.programID ?? ""), "\(course.nameSv) pekar på ett program som inte finns")
        }
    }

    @MainActor
    func testTheRenamedCourseCodesGetTheirHistory() throws {
        let store = GrantDataStore(metadata: .bundledDefault, teachingCourses: try storedCourses())
        store.migrateTeachingCatalogForRound2c()

        for (current, previous) in [("8LA100", "8LAA10"), ("8LA110", "8LAA11")] {
            guard let course = store.teachingCourses.first(where: { $0.courseCode == current }) else { continue }
            XCTAssertEqual(course.courseCode(on: "2025-09-01"), previous)
            XCTAssertEqual(course.courseCode(on: "2026-09-01"), current)
        }
    }

    @MainActor
    func testRunningTheMigrationTwiceChangesNothing() throws {
        let store = GrantDataStore(metadata: .bundledDefault, teachingCourses: try storedCourses())
        store.migrateTeachingCatalogForRound2c()
        let afterFirst = store.teachingCourses
        let second = store.migrateTeachingCatalogForRound2c()
        XCTAssertTrue(second.isEmpty, "migreringen ska inte göra något andra gången")
        XCTAssertEqual(store.teachingCourses, afterFirst)
    }

    @MainActor
    func testRenamingAProgrammeFollowsThroughToItsCourses() {
        let programme = TeachingCourse(
            id: "prog-1",
            contextType: .programTrack,
            programSv: "Exempelprogrammet",
            programEn: "Exempelprogrammet",
            institution: "Exempelköpings universitet"
        )
        var course = TeachingCourse(
            id: "course-1",
            nameSv: "Klinisk medicin 4",
            contextType: .course,
            programSv: "Exempelprogrammet",
            programEn: "Exempelprogrammet",
            institution: "Exempelköpings universitet"
        )
        course.programID = "prog-1"
        // The write guard refuses a save that would empty a register, so the
        // store has to carry the other teaching registers too, as a real one does.
        let store = GrantDataStore(
            metadata: .bundledDefault,
            teachingCourses: [programme, course],
            teachingComponents: (1...3).map { TeachingComponent(id: "component-\($0)", name: "Moment \($0)") },
            teachingFormats: (1...3).map { TeachingFormatOption(id: "format-\($0)", name: "Format \($0)") },
            teachingAssignments: (1...3).map {
                TeachingAssignment(id: "assignment-\($0)", authorID: "author", activityName: "Uppdrag \($0)")
            },
            doctoralCandidates: (1...3).map { DoctoralCandidateRecord(id: "doctoral-\($0)") }
        )

        var renamed = programme
        renamed.programEn = "Example Programme"
        store.saveTeachingCourse(renamed)

        XCTAssertEqual(store.teachingCourses.count, 2)
        let savedProgramme = store.teachingCourses.first { $0.id == "prog-1" }
        let savedCourse = store.teachingCourses.first { $0.id == "course-1" }
        let failure = store.loadError ?? "inget sparningsfel"

        XCTAssertEqual(
            savedProgramme?.programEn,
            "Example Programme",
            "programmet självt tappade namnbytet, alltså rullades sparningen tillbaka (\(failure))"
        )
        XCTAssertEqual(
            savedCourse?.programEn,
            "Example Programme",
            "kursen följde inte med programmets nya namn (\(failure))"
        )
        XCTAssertEqual(savedCourse?.programSv, "Exempelprogrammet")
    }

    @MainActor
    func testEditingOneCourseLeavesTheOthersAlone() throws {
        let courses = try storedCourses()
        let store = GrantDataStore(metadata: .bundledDefault, teachingCourses: courses)
        guard var first = store.teachingCourses.first(where: { $0.contextType == .course }) else {
            throw XCTSkip("inga kurser i underlaget")
        }
        first.credits = "31"
        store.saveTeachingCourse(first)
        XCTAssertEqual(store.teachingCourses.count, courses.count, "en sparning tappade poster")
    }

    func testRowValidityCoversOpenAndClosedPeriods() {
        var course = TeachingCourse(nameSv: "Gammal kurs")
        course.validTo = "2024-12-31"
        course.normalize()
        XCTAssertTrue(course.isValid(on: "2024-05-01"))
        XCTAssertFalse(course.isValid(on: "2025-05-01"))
    }
}
