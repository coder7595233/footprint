import XCTest
@testable import Footprint

/// F12: the Data view lists fields written in one language only in their own
/// section, "Missing translations", one row per field with Swedish and English
/// side by side. "Missing fields" carries no language notes.
final class LanguageCheckTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LanguageCheckTests-\(UUID().uuidString)", isDirectory: true)
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

    @MainActor
    private func store(
        courses: [TeachingCourse] = [],
        organizations: [OrganizationRecord] = [],
        authors: [PublicationAuthor] = []
    ) -> GrantDataStore {
        var metadata = DataSourceMetadata.bundledDefault
        metadata.interfaceLanguage = "sv"
        return GrantDataStore(
            metadata: metadata,
            organizations: organizations,
            teachingCourses: courses,
            publicationAuthors: authors,
            skipInitialMigration: true
        )
    }

    private static func isLanguageNote(_ field: String) -> Bool {
        field.hasPrefix("Engelsk") || field.hasPrefix("Svensk")
    }

    @MainActor
    func testCourseWithoutEnglishNameIsFlagged() {
        var course = TeachingCourse(id: "c1", name: "Klinisk medicin 2")
        course.nameSv = "Klinisk medicin 2"
        course.nameEn = ""
        let issues = store(courses: [course]).translationIssues(includeHidden: true)
            .filter { $0.recordID == "c1" && $0.field == .name }
        XCTAssertEqual(issues.map(\.reason), [.missingEnglish], "\(issues)")
        XCTAssertEqual(issues.first?.valueSv, "Klinisk medicin 2")
        XCTAssertEqual(issues.first?.valueEn, "")
    }

    @MainActor
    func testUntranslatedProgrammeNameIsFlagged() {
        var programme = TeachingCourse(id: "p1", contextType: .programTrack)
        programme.programSv = "Fristående kurser"
        programme.programEn = "Fristående kurser"
        let issues = store(courses: [programme]).translationIssues(includeHidden: true)
            .filter { $0.recordID == "p1" && $0.field == .program }
        XCTAssertEqual(issues.map(\.reason), [.identical], "\(issues)")
    }

    @MainActor
    func testFullyTranslatedCourseIsNotFlaggedForLanguage() {
        var course = TeachingCourse(id: "c2", name: "Klinisk medicin 4")
        course.nameSv = "Klinisk medicin 4"
        course.nameEn = "Clinical Medicine 4"
        course.programSv = "Exempelprogrammet"
        course.programEn = "Example Programme"
        let issues = store(courses: [course]).translationIssues(includeHidden: true)
            .filter { $0.recordID == "c2" }
        XCTAssertTrue(issues.isEmpty, "\(issues)")
    }

    @MainActor
    func testOrganizationWithTheSameNameIsOnlyListedUnderTranslations() {
        // The translation list has always flagged identical organization
        // names; the user hides the ones that are meant to be the same.
        let organization = OrganizationRecord(id: "o1", nameSv: "Abbott", nameEn: "Abbott")
        let testStore = store(organizations: [organization])
        let fields = testStore.missingFieldIssues(includeHidden: true)
            .filter { $0.recordID == "o1" }
            .flatMap(\.missingFields)
        XCTAssertFalse(fields.contains(where: Self.isLanguageNote), "\(fields)")
        let issues = testStore.translationIssues(includeHidden: true).filter { $0.recordID == "o1" }
        XCTAssertEqual(issues.map(\.reason), [.identical], "\(issues)")
    }

    @MainActor
    func testMissingFieldsCarryNoLanguageNotes() {
        var course = TeachingCourse(id: "c3", name: "")
        course.nameSv = "Hälsa och sjukdom 1"
        course.nameEn = ""
        course.institution = ""
        let testStore = store(courses: [course])
        let fields = testStore.missingFieldIssues(includeHidden: true)
            .filter { $0.recordID == "c3" }
            .flatMap(\.missingFields)
        XCTAssertFalse(fields.contains(where: Self.isLanguageNote), "\(fields)")
        XCTAssertTrue(
            testStore.translationIssues(includeHidden: true)
                .contains { $0.recordID == "c3" && $0.field == .name && $0.reason == .missingEnglish }
        )
    }

    @MainActor
    func testOneRowPerBilingualField() {
        var author = PublicationAuthor(id: "a1", name: "Anna Andersson")
        author.titleSv = "Docent"
        author.titleEn = ""
        author.positionSv = ""
        author.positionEn = "Senior consultant"
        author.degreeSv = ""
        author.degreeEn = ""
        let issues = store(authors: [author]).translationIssues(includeHidden: true)
            .filter { $0.recordID == "a1" }
        XCTAssertEqual(issues.map(\.field), [.title, .position], "\(issues)")
        XCTAssertEqual(issues.map(\.reason), [.missingEnglish, .missingSwedish])
        XCTAssertEqual(Set(issues.map(\.id)).count, 2, "each field has its own row")
    }

    @MainActor
    func testHiddenRowIsLeftOutUnlessAskedFor() {
        var course = TeachingCourse(id: "c5", name: "Kliniskt resonemang")
        course.nameSv = "Kliniskt resonemang"
        course.nameEn = "Kliniskt resonemang"
        let testStore = store(courses: [course])
        guard let issue = testStore.translationIssues().first(where: { $0.recordID == "c5" }) else {
            return XCTFail("expected a row for the identical course name")
        }
        testStore.hideDataQualityWarning(issue)
        XCTAssertFalse(testStore.translationIssues().contains { $0.recordID == "c5" })
        XCTAssertTrue(testStore.translationIssues(includeHidden: true).contains { $0.recordID == "c5" })
    }

    @MainActor
    func testEditingTheEnglishCellSavesTheRecordAndRemovesTheRow() {
        var course = TeachingCourse(id: "c4", name: "Klinisk medicin 2")
        course.nameSv = "Klinisk medicin 2"
        course.nameEn = ""
        course.termSv = "Termin 6"
        var other = TeachingCourse(id: "c6", name: "Klinisk medicin 3")
        other.nameSv = "Klinisk medicin 3"
        other.nameEn = ""
        let testStore = store(courses: [course, other])
        guard let issue = testStore.translationIssues()
            .first(where: { $0.recordID == "c4" && $0.field == .name }) else {
            return XCTFail("expected a row for the missing English name")
        }

        testStore.saveTranslation(for: issue, sv: issue.valueSv, en: "Clinical Medicine 2")

        let saved = testStore.teachingCourses.first { $0.id == "c4" }
        XCTAssertEqual(saved?.nameEn, "Clinical Medicine 2")
        XCTAssertEqual(saved?.nameSv, "Klinisk medicin 2")
        XCTAssertEqual(saved?.termSv, "Termin 6", "other fields are left alone")
        let remaining = testStore.translationIssues(includeHidden: true)
        XCTAssertFalse(remaining.contains { $0.recordID == "c4" && $0.field == .name }, "the fixed row disappears")
        XCTAssertTrue(remaining.contains { $0.recordID == "c6" && $0.field == .name }, "other untranslated rows stay listed")
    }

    @MainActor
    func testEditingAResearcherFieldSavesOnlyThatField() {
        var author = PublicationAuthor(id: "a2", name: "Anna Andersson")
        author.positionSv = "Överläkare"
        author.positionEn = ""
        author.titleSv = "Docent"
        author.titleEn = ""
        let testStore = store(authors: [author])
        guard let issue = testStore.translationIssues()
            .first(where: { $0.recordID == "a2" && $0.field == .position }) else {
            return XCTFail("expected a row for the missing English position")
        }

        testStore.saveTranslation(for: issue, sv: issue.valueSv, en: "Senior consultant")

        let saved = testStore.publicationAuthors.first { $0.id == "a2" }
        XCTAssertEqual(saved?.positionEn, "Senior consultant")
        XCTAssertEqual(saved?.titleEn, "", "the title was not touched")
        XCTAssertFalse(testStore.translationIssues().contains { $0.recordID == "a2" && $0.field == .position })
    }
}
