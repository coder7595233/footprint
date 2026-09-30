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
}
