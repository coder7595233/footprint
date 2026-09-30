import XCTest
@testable import Footprint

/// Round 11 (data safety). All names below are made up.
final class Round11DataSafetyTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Round11DataSafetyTests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: Hidden salary calculators

    private static func calculator(overheadPercent: String) -> ManagerSalaryCalculator {
        let year = Calendar.current.component(.year, from: Date())
        return ManagerSalaryCalculator(
            birthDate: "2000-01-01",
            monthlySalaryPeriods: [],
            employerFeePeriods: [],
            regionalCostPeriods: [],
            itInfrastructureFeePeriods: [],
            listedPatientCountPeriods: [],
            overheadPeriods: [SalaryCalculatorPeriod(value: overheadPercent, from: "\(year)-01-01", to: "\(year)-12-31")],
            annualIncreaseAfterCurrentYearPercent: "0",
            allocationPercent: "",
            allocationMonths: ""
        )
    }

    /// Employer and fund manager: its calculator is shown and stays.
    private static var employer: OrganizationRecord {
        OrganizationRecord(
            id: "org-region",
            nameSv: "Region Exempelgöta",
            nameEn: "Region Exempelgota",
            roles: [.fundManager, .employer],
            salaryCalculator: calculator(overheadPercent: "8.8")
        )
    }

    /// Fund manager but not employer, with a calculator it never shows.
    private static var hiddenManager: OrganizationRecord {
        OrganizationRecord(
            id: "org-university",
            nameSv: "Exempelköpings universitet",
            nameEn: "Exempelköping University",
            roles: [.fundManager, .institution],
            salaryCalculator: calculator(overheadPercent: "8.8")
        )
    }

    /// Only an institution, with a leftover calculator.
    private static var hiddenInstitution: OrganizationRecord {
        OrganizationRecord(
            id: "org-institute",
            nameSv: "Exempelinstitutet",
            nameEn: "Example Institute",
            roles: [.institution],
            salaryCalculator: calculator(overheadPercent: "12")
        )
    }

    /// Chosen in Settings as the application salary calculator: kept.
    private static var settingsCalculator: OrganizationRecord {
        OrganizationRecord(
            id: "org-settings",
            nameSv: "Exempelbolaget",
            nameEn: "Example Company",
            roles: [.company],
            salaryCalculator: calculator(overheadPercent: "20"),
            usesAsApplicationSalaryCalculator: true
        )
    }

    @MainActor
    private func makeStore(
        organizations: [OrganizationRecord] = [employer, hiddenManager, hiddenInstitution, settingsCalculator],
        applications: [GrantApplication] = []
    ) -> GrantDataStore {
        GrantDataStore(
            applications: applications,
            organizations: organizations,
            skipInitialMigration: true
        )
    }

    func testOverheadSuggestionOnlyComesFromAnEmployersCalculator() {
        XCTAssertEqual(Self.employer.managerOverheadDefaultPercent(), 8.8)
        XCTAssertNil(Self.hiddenManager.managerOverheadDefaultPercent(), "a calculator the app does not show is never used")
        var withOwnNumber = Self.hiddenManager
        withOwnNumber.managerOverheadPercent = 30
        XCTAssertEqual(withOwnNumber.managerOverheadDefaultPercent(), 30)

        let plan = GrantOverheadPlan.resolved(funder: nil, manager: Self.hiddenManager)
        XCTAssertTrue(plan.managerOverheadPeriods.isEmpty, "the OH plan does not read a hidden calculator either")
        XCTAssertFalse(GrantOverheadPlan.resolved(funder: nil, manager: Self.employer).managerOverheadPeriods.isEmpty)
    }

    @MainActor
    func testHiddenCalculatorsAreRemovedOnceAndEmployersKeepTheirs() {
        let store = makeStore()
        XCTAssertTrue(store.runRound11OneTimeDataMigrations())

        XCTAssertNotNil(store.organization(id: "org-region")?.salaryCalculator, "an employer keeps its calculator")
        XCTAssertNotNil(store.organization(id: "org-settings")?.salaryCalculator, "the calculator chosen in Settings stays")
        XCTAssertNil(store.organization(id: "org-university")?.salaryCalculator)
        XCTAssertNil(store.organization(id: "org-institute")?.salaryCalculator)
        XCTAssertEqual(store.organizations.count, 4, "no organization is lost or added")
        XCTAssertEqual(store.organization(id: "org-university")?.roles, [.fundManager, .institution], "roles are not touched")
        XCTAssertTrue((store.metadata.migrationLog ?? []).contains { $0.key == "round11-hidden-salary-calculators" })

        XCTAssertFalse(store.runRound11OneTimeDataMigrations(), "the migration runs only once")
        XCTAssertFalse(store.removeHiddenSalaryCalculatorsForRound11(), "running the step again changes nothing")
    }

    @MainActor
    func testMigrationDoesNotDependOnNames() {
        var renamed = Self.hiddenManager
        renamed.nameSv = "Helt annat namn"
        renamed.nameEn = "Something else"
        let store = makeStore(organizations: [Self.employer, renamed])
        XCTAssertTrue(store.removeHiddenSalaryCalculatorsForRound11())
        XCTAssertNil(store.organization(id: "org-university")?.salaryCalculator)
        XCTAssertNotNil(store.organization(id: "org-region")?.salaryCalculator)
    }

    // MARK: "Ej sökt" keeps hidden application details

    func testHiddenApplicationDetailsAreListed() {
        var record = GrantApplication(id: "a1", rowNumber: 1, organization: "Stiftelsen Exempel", grantName: "Projektbidrag")
        XCTAssertTrue(record.hiddenApplicationDetailTitles(hasOtherApplicants: false, language: .swedish).isEmpty)

        record.secondaryLink = "https://example.org/ansokan"
        record.appliedCaseNumber = "  "
        record.applicationManager = "Exempelköpings universitet"
        XCTAssertEqual(
            record.hiddenApplicationDetailTitles(hasOtherApplicants: true, language: .swedish),
            ["Medsökande", "Medelsförvaltare", "Länk till ansökan"],
            "only fields that hold something are listed, in the editor's order"
        )
    }

    // MARK: Delete key asks first and leaves locked records alone

    @MainActor
    func testDeleteKeyAsksFirstAndNeverTouchesALockedRecord() {
        var locked = GrantApplication(id: "a-locked", rowNumber: 1, organization: "Stiftelsen Exempel", grantName: "Låst")
        locked.isEditingLocked = true
        let open = GrantApplication(id: "a-open", rowNumber: 2, organization: "Stiftelsen Exempel", grantName: "Öppen")
        let store = makeStore(organizations: [], applications: [locked, open])
        var deleted: [String] = []

        store.requestKeyboardDeletion(recordTitle: locked.displayTitle, isLocked: true) { deleted.append(locked.id) }
        XCTAssertNil(store.deletionImpactWarning, "a locked record gets no delete question at all")
        XCTAssertNotNil(store.notice, "the user is told why nothing happened")

        store.requestKeyboardDeletion(recordTitle: open.displayTitle, isLocked: false) { deleted.append(open.id) }
        XCTAssertNotNil(store.deletionImpactWarning, "the Delete key asks first")
        XCTAssertTrue(deleted.isEmpty, "nothing is removed before the answer")

        store.cancelDeletionImpactWarning()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(deleted.isEmpty, "Avbryt removes nothing")

        store.requestKeyboardDeletion(recordTitle: open.displayTitle, isLocked: false) { deleted.append(open.id) }
        store.confirmDeletionImpactWarning()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(deleted, ["a-open"])
    }

    // MARK: Undo after delete also takes the record out of the archive

    @MainActor
    func testUndoAfterDeleteTakesTheRecordOutOfTheArchive() throws {
        let record = GrantApplication(id: "a-undo", rowNumber: 1, organization: "Stiftelsen Exempel", grantName: "Projektbidrag")
        let store = makeStore(organizations: [], applications: [record])
        XCTAssertTrue(try store.loadArchivedRecords().isEmpty)

        store.deleteApplication(id: record.id)
        XCTAssertNil(store.applications.first { $0.id == record.id })
        XCTAssertEqual(try store.loadArchivedRecords().filter { $0.kind == "application" }.count, 1)

        XCTAssertTrue(store.undoManager.canUndo)
        store.undoManager.undo()
        XCTAssertNotNil(store.applications.first { $0.id == record.id }, "Undo brings the record back")
        XCTAssertTrue(try store.loadArchivedRecords().isEmpty, "and it is no longer also in the archive")

        XCTAssertTrue(store.undoManager.canRedo)
        store.undoManager.redo()
        XCTAssertNil(store.applications.first { $0.id == record.id })
        XCTAssertEqual(try store.loadArchivedRecords().filter { $0.kind == "application" }.count, 1, "Redo archives it again")
    }

    // MARK: Deleting an organization keeps the written names

    @MainActor
    func testDeletingAnOrganizationKeepsFunderAndManagerNames() {
        let funder = OrganizationRecord(id: "org-funder", nameSv: "Stiftelsen Exempel", nameEn: "Example Foundation", roles: [.grantProvider])
        var linked = GrantApplication(id: "a-linked", rowNumber: 1, organizationID: "org-funder", organization: "", grantName: "Projektbidrag")
        linked.applicationManagerID = "org-funder"
        let textOnly = GrantApplication(id: "a-text", rowNumber: 2, organization: "Stiftelsen Exempel", grantName: "Resebidrag")
        let store = makeStore(organizations: [funder], applications: [linked, textOnly])

        store.deleteOrganization(id: "org-funder")
        store.confirmDeletionImpactWarning()

        XCTAssertFalse(store.organizations.contains { $0.id == "org-funder" })
        let afterLinked = store.applications.first { $0.id == "a-linked" }
        XCTAssertNil(afterLinked?.organizationID, "the link is gone")
        XCTAssertEqual(afterLinked?.organization, "Stiftelsen Exempel", "the funder's name is written in instead of left blank")
        XCTAssertNil(afterLinked?.applicationManagerID)
        XCTAssertEqual(afterLinked?.applicationManager, "Stiftelsen Exempel")
        XCTAssertEqual(store.applications.first { $0.id == "a-text" }?.organization, "Stiftelsen Exempel", "a row without a link keeps its text")
    }

    // MARK: Course codes edited by hand are never reset

    @MainActor
    func testEditedCourseCodeHistoryIsNotResetAtStart() {
        // The code list as the user left it: the earlier code removed by hand.
        let edited = TeachingCourse(
            id: "course-edited",
            nameSv: "Exempelkurs",
            courseCode: "8LA100",
            courseCodes: [TeachingCourseCodeEntry(code: "8LA100", validFrom: "2024-01-01")]
        )
        let untouched = TeachingCourse(id: "course-new", nameSv: "Annan kurs", courseCode: "8LA110")
        let store = GrantDataStore(metadata: .bundledDefault, teachingCourses: [edited, untouched])

        store.migrateTeachingCatalogForRound2c()

        let afterEdited = store.teachingCourses.first { $0.id == "course-edited" }
        XCTAssertEqual(afterEdited?.courseCodes.map(\.code), ["8LA100"], "a list edited by hand stays as it is")
        XCTAssertEqual(afterEdited?.courseCodes.first?.validFrom, "2024-01-01")
        XCTAssertEqual(store.teachingCourses.first { $0.id == "course-new" }?.courseCodes.count, 2, "a course without history still gets it")
        XCTAssertTrue(store.migrateTeachingCatalogForRound2c().isEmpty, "the next start changes nothing")
    }
}
