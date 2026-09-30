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

    @MainActor
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

    @MainActor
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

    // MARK: A shared name never links a row by chance

    @MainActor
    func testRowWithoutIDIsLinkedByNameOnlyWhenTheNameIsUnique() {
        // Same English name, different Swedish names (organizations with the
        // same Swedish name are already combined into one by the app).
        let first = OrganizationRecord(id: "org-a", nameSv: "Fonden", nameEn: "Shared Fund", roles: [.grantProvider])
        let second = OrganizationRecord(id: "org-b", nameSv: "Stiftelsen Fonden", nameEn: "Shared Fund", roles: [.grantProvider])
        let unique = OrganizationRecord(id: "org-c", nameSv: "Stiftelsen Exempel", nameEn: "Example Foundation", roles: [.grantProvider])
        let store = makeStore(organizations: [first, second, unique])
        XCTAssertEqual(store.organizations.count, 3)

        let shared = GrantApplication(id: "a1", rowNumber: 1, organization: "Shared Fund", grantName: "Bidrag")
        XCTAssertNil(store.linkedFunder(of: shared), "two organizations share the name, so none is picked")
        let named = GrantApplication(id: "a2", rowNumber: 2, organization: "stiftelsen exempel", grantName: "Bidrag")
        XCTAssertEqual(store.linkedFunder(of: named)?.id, "org-c", "a unique name still links")
        var byID = shared
        byID.organizationID = "org-b"
        XCTAssertEqual(store.linkedFunder(of: byID)?.id, "org-b", "the id always decides")
    }

    // MARK: Merging duplicate organizations loses nothing

    @MainActor
    func testMergingOrganizationsMovesCongressesTravelTasksAndSettings() throws {
        let congress = OrganizationCongress(id: "congress-1", title: "Exempelkongressen 2026", from: "2026-05-01", to: "2026-05-03")
        var kept = OrganizationRecord(id: "org-kept", nameSv: "Exempelsällskapet", nameEn: "Example Society", roles: [.association, .fundManager])
        kept.congresses = []
        var duplicate = OrganizationRecord(id: "org-dup", nameSv: "Exempelsallskapet", nameEn: "Example Society", roles: [.association, .fundManager])
        duplicate.congresses = [congress]
        let funder = OrganizationRecord(
            id: "org-funder",
            nameSv: "Stiftelsen Exempel",
            nameEn: "Example Foundation",
            roles: [.grantProvider],
            overheadRuleExceptions: [FunderOverheadRuleException(managerOrganizationID: "org-dup", rule: FunderOverheadRule(kind: .cap, capPercent: 5))],
            preferredFundManagerID: "org-dup"
        )
        var metadata = DataSourceMetadata.bundledDefault
        metadata.calendarTravelRecords = [CalendarTravelRecord(id: "travel-1", date: "2026-04-30", congressOrganizationID: "org-dup", congressID: "congress-1")]
        metadata.taskItems = [TaskItem(id: "task-1", links: [
            TaskLink(kind: .organization, targetID: "org-dup"),
            TaskLink(kind: .congress, targetID: "congress-1", ownerID: "org-dup")
        ])]
        let store = GrantDataStore(metadata: metadata, organizations: [kept, duplicate, funder], skipInitialMigration: true)

        XCTAssertTrue(store.mergeDuplicateRecords(groupKind: .managers, canonicalRecordID: "org-kept", duplicateRecordIDs: ["org-dup"]))

        XCTAssertNil(store.organization(id: "org-dup"))
        XCTAssertEqual(store.organization(id: "org-kept")?.congresses.map(\.id), ["congress-1"], "the duplicate's congress is kept")
        XCTAssertEqual(store.metadata.calendarTravelRecords?.first?.congressOrganizationID, "org-kept", "travel follows the congress")
        let links = store.metadata.taskItems?.first?.links ?? []
        XCTAssertTrue(links.contains(TaskLink(kind: .organization, targetID: "org-kept")))
        XCTAssertTrue(links.contains(TaskLink(kind: .congress, targetID: "congress-1", ownerID: "org-kept")))
        XCTAssertEqual(store.organization(id: "org-funder")?.preferredFundManagerID, "org-kept")
        XCTAssertEqual(store.organization(id: "org-funder")?.overheadRuleExceptions?.map(\.managerOrganizationID), ["org-kept"])
    }

    @MainActor
    func testMergeListsLockedRecordsBeforeChangingThem() {
        let kept = OrganizationRecord(id: "org-kept", nameSv: "Fonden", nameEn: "The Fund", roles: [.grantProvider])
        let duplicate = OrganizationRecord(id: "org-dup", nameSv: "Fonden AB", nameEn: "The Fund Ltd", roles: [.grantProvider])
        var locked = GrantApplication(id: "a-locked", rowNumber: 1, organizationID: "org-dup", organization: "Fonden AB", grantName: "Bidrag")
        locked.isEditingLocked = true
        let open = GrantApplication(id: "a-open", rowNumber: 2, organizationID: "org-dup", organization: "Fonden AB", grantName: "Resa")
        let store = makeStore(organizations: [kept, duplicate], applications: [locked, open])

        XCTAssertEqual(store.lockedRecordsRewrittenByMerge(groupKind: .funders, duplicateIDs: ["org-dup"]).count, 1, "only the locked record is listed")

        XCTAssertTrue(store.mergeDuplicateRecords(groupKind: .funders, canonicalRecordID: "org-kept", duplicateRecordIDs: ["org-dup"]))
        XCTAssertNotNil(store.organization(id: "org-dup"), "nothing is merged before the answer")
        XCTAssertEqual(store.applications.first { $0.id == "a-locked" }?.organization, "Fonden AB")

        XCTAssertTrue(store.mergeDuplicateRecords(groupKind: .funders, canonicalRecordID: "org-kept", duplicateRecordIDs: ["org-dup"], lockedRecordsConfirmed: true))
        XCTAssertNil(store.organization(id: "org-dup"))
        XCTAssertEqual(store.applications.first { $0.id == "a-locked" }?.organizationID, "org-kept")
    }
}
