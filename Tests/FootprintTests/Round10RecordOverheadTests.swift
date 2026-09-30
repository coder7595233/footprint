import XCTest
@testable import Footprint

/// Round 10 ("Utlysningar och anslag"): the funder's "Godkänd OH, högst" and
/// the fund manager's "OH som tas ut" are one number each, copied into a
/// record as defaults. A later change on the organizations never changes a
/// record, and locked or already applied records are never filled in. All
/// names below are made up.
final class Round10RecordOverheadTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Round10RecordOverheadTests-\(UUID().uuidString)", isDirectory: true)
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

    // MARK: Test data (fictional)

    private static let universityID = "org-exempelkoping"
    private static let regionID = "org-exempelgota"
    private static let funderID = "org-stiftelsen"

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

    /// Fund manager with only a salary calculator (OH 30 % this year).
    private static var university: OrganizationRecord {
        OrganizationRecord(
            id: universityID,
            nameSv: "Exempelköpings universitet",
            nameEn: "Exempelköping University",
            roles: [.fundManager, .employer],
            salaryCalculator: calculator(overheadPercent: "30")
        )
    }

    /// Fund manager with its own "OH som tas ut" (8,8 %).
    private static var region: OrganizationRecord {
        OrganizationRecord(
            id: regionID,
            nameSv: "Region Exempelgöta",
            nameEn: "Region Exempelgota",
            roles: [.fundManager, .grantProvider],
            managerOverheadPercent: 8.8
        )
    }

    /// Grant provider that accepts at most 20 %, and 5 % when the region manages.
    private static var funder: OrganizationRecord {
        OrganizationRecord(
            id: funderID,
            nameSv: "Stiftelsen Exempel",
            nameEn: "Example Foundation",
            roles: [.grantProvider],
            overheadRule: FunderOverheadRule(kind: .cap, capPercent: 20),
            overheadRuleExceptions: [
                FunderOverheadRuleException(managerOrganizationID: regionID, rule: FunderOverheadRule(kind: .cap, capPercent: 5))
            ],
            preferredFundManagerID: universityID
        )
    }

    private static func record(
        id: String,
        status: String,
        locked: Bool = false,
        managerID: String? = universityID
    ) -> GrantApplication {
        // "Väntar svar" is shown only with an application date.
        let appliedOn: String? = status == "Väntar svar" ? "2026-09-01" : nil
        var application = GrantApplication(
            id: id,
            rowNumber: 1,
            organizationID: funderID,
            organization: "Stiftelsen Exempel",
            grantName: "Projektbidrag",
            appliedOn: appliedOn,
            result: status,
            applicationManagerID: managerID,
            applicationManager: managerID == nil ? nil : "Exempelköpings universitet"
        )
        application.isEditingLocked = locked
        return application
    }

    @MainActor
    private func makeStore(applications: [GrantApplication], defaultManagerID: String? = nil) -> GrantDataStore {
        let store = GrantDataStore(
            applications: applications,
            organizations: [Self.university, Self.region, Self.funder],
            managers: [
                ManagerOption(id: Self.universityID, nameSv: "Exempelköpings universitet", nameEn: "Exempelköping University", reason: nil),
                ManagerOption(id: Self.regionID, nameSv: "Region Exempelgöta", nameEn: "Region Exempelgota", reason: nil)
            ],
            skipInitialMigration: true
        )
        if let defaultManagerID {
            store.autosaveHomeOrganizationSettings(
                homeCountry: "Sweden",
                homeRegionOrganizationID: "",
                defaultFundManagerOrganizationID: defaultManagerID
            )
        }
        return store
    }

    // MARK: One number per side

    func testRuleAsOneNumberAndBack() {
        XCTAssertEqual(FunderOverheadRule().approvedMaxPercent, 100, "full OH is 100")
        XCTAssertEqual(FunderOverheadRule(kind: .noOverhead).approvedMaxPercent, 0)
        XCTAssertEqual(FunderOverheadRule(kind: .cap, capPercent: 21.95).approvedMaxPercent, 21.95)
        XCTAssertNil(FunderOverheadRule(kind: .cap, capPercent: nil).approvedMaxPercent)

        XCTAssertEqual(FunderOverheadRule(approvedMaxPercent: 100).kind, .managerFull)
        XCTAssertEqual(FunderOverheadRule(approvedMaxPercent: 150).kind, .managerFull)
        XCTAssertEqual(FunderOverheadRule(approvedMaxPercent: 0).kind, .noOverhead)
        XCTAssertEqual(FunderOverheadRule(approvedMaxPercent: 21.95), FunderOverheadRule(kind: .cap, capPercent: 21.95))
        let withNote = FunderOverheadRule(kind: .cap, capPercent: 10, capIncludesPremises: true)
        XCTAssertTrue(FunderOverheadRule(approvedMaxPercent: 12, keepingPremisesFrom: withNote).capIncludesPremises)
    }

    func testDefaultsCopyTheFundersNumberForTheChosenFundManager() {
        let forUniversity = GrantOverheadDefaults.resolved(funder: Self.funder, manager: Self.university)
        XCTAssertEqual(forUniversity.funderMaxPercent, 20)
        XCTAssertEqual(forUniversity.managerPercent, 30, "this year's period in the salary calculator")

        let forRegion = GrantOverheadDefaults.resolved(funder: Self.funder, manager: Self.region)
        XCTAssertEqual(forRegion.funderMaxPercent, 5, "the exception for the region")
        XCTAssertEqual(forRegion.managerPercent, 8.8, "the fund manager's own number")

        let noOrganizations = GrantOverheadDefaults.resolved(funder: nil, manager: nil)
        XCTAssertNil(noOrganizations.funderMaxPercent)
        XCTAssertNil(noOrganizations.managerPercent)
    }

    func testRecordNumbersDecideTheOverheadAndTheCofundingGap() throws {
        var application = Self.record(id: "a", status: "Att söka")
        application.funderMaxOverheadPercent = 21.95
        application.managerOverheadPercent = 30
        XCTAssertEqual(application.cofundingOverheadGapPercent, 8.05, accuracy: 0.000_001)

        let plan = GrantOverheadPlan.resolved(for: application, funder: Self.funder, manager: Self.university)
        let date = try XCTUnwrap(DateParsers.isoDay.date(from: "2027-03-01"))
        let rates = grantOverheadRates(on: date, calculator: Self.calculator(overheadPercent: "1"), plan: plan)
        XCTAssertEqual(rates.manager, 0.30, accuracy: 0.000_001, "the record's own number, not the organizations'")
        XCTAssertEqual(rates.effective, 0.2195, accuracy: 0.000_001)

        application.managerOverheadPercent = 15
        XCTAssertEqual(application.cofundingOverheadGapPercent, 0, "nothing to co-fund when the funder accepts more")
        application.funderMaxOverheadPercent = nil
        XCTAssertEqual(application.cofundingOverheadGapPercent, 0, "a missing number gives no question")
    }

    func testRecordWithoutNumbersKeepsTheEarlierCalculation() {
        let application = Self.record(id: "a", status: "Väntar svar")
        let plan = GrantOverheadPlan.resolved(for: application, funder: Self.funder, manager: Self.region)
        XCTAssertEqual(plan, GrantOverheadPlan.resolved(funder: Self.funder, manager: Self.region))
    }

    // MARK: Stored data

    func testNewFieldsAreStoredAndOldDataLoads() throws {
        var application = Self.record(id: "a", status: "Att söka")
        application.funderMaxOverheadPercent = 20
        application.managerOverheadPercent = 30
        application.cofundingDecision = .no
        application.cofundingDecisionOn = "2026-09-29"
        let decoded = try JSONDecoder().decode(GrantApplication.self, from: JSONEncoder().encode(application))
        XCTAssertEqual(decoded.funderMaxOverheadPercent, 20)
        XCTAssertEqual(decoded.managerOverheadPercent, 30)
        XCTAssertEqual(decoded.cofundingDecision, .no)
        XCTAssertEqual(decoded.cofundingDecisionOn, "2026-09-29")

        let old = try JSONDecoder().decode(
            GrantApplication.self,
            from: Data(#"{"id":"old","organization":"Stiftelsen Exempel","grantName":"Bidrag"}"#.utf8)
        )
        XCTAssertNil(old.funderMaxOverheadPercent)
        XCTAssertNil(old.managerOverheadPercent)
        XCTAssertNil(old.cofundingDecision)

        let organization = try JSONDecoder().decode(OrganizationRecord.self, from: JSONEncoder().encode(Self.funder))
        XCTAssertEqual(organization.preferredFundManagerID, Self.universityID)
    }

    // MARK: Preferred fund manager

    @MainActor
    func testPreferredFundManagerComesFromTheFunderThenFromSettings() {
        let store = makeStore(applications: [], defaultManagerID: Self.regionID)
        XCTAssertEqual(store.preferredFundManagerOrganization(forFunderID: Self.funderID)?.id, Self.universityID)
        XCTAssertEqual(store.preferredFundManagerOrganization(forFunderID: Self.regionID)?.id, Self.regionID, "no preference on the funder: Settings")
        XCTAssertEqual(store.preferredFundManagerOrganization(forFunderID: nil)?.id, Self.regionID)

        store.setOrganizationPreferredFundManager(organizationID: Self.funderID, managerID: "")
        XCTAssertNil(store.organization(id: Self.funderID)?.preferredFundManagerID, "empty = back to the default")
    }

    // MARK: One-time step

    @MainActor
    func testOneTimeStepFillsOnlyUnlockedRecordsNotYetApplied() throws {
        let store = makeStore(applications: [
            Self.record(id: "to-apply", status: "Att söka"),
            Self.record(id: "not-applied", status: "Ej sökt", managerID: Self.regionID),
            Self.record(id: "awaiting", status: "Väntar svar"),
            Self.record(id: "declined-open", status: "Avslag"),
            Self.record(id: "locked-to-apply", status: "Att söka", locked: true),
            Self.record(id: "granted", status: "Beviljat", locked: true)
        ])
        let before = store.applications.count

        XCTAssertTrue(store.runRound10OneTimeDataMigrations())
        XCTAssertEqual(store.applications.count, before, "no record is lost")

        func record(_ id: String) throws -> GrantApplication {
            try XCTUnwrap(store.applications.first(where: { $0.id == id }))
        }
        XCTAssertEqual(try record("to-apply").funderMaxOverheadPercent, 20)
        XCTAssertEqual(try record("to-apply").managerOverheadPercent, 30)
        XCTAssertEqual(try record("not-applied").funderMaxOverheadPercent, 5, "the region's exception")
        XCTAssertEqual(try record("not-applied").managerOverheadPercent, 8.8)
        for untouched in ["awaiting", "declined-open", "locked-to-apply", "granted"] {
            XCTAssertNil(try record(untouched).funderMaxOverheadPercent, untouched)
            XCTAssertNil(try record(untouched).managerOverheadPercent, untouched)
        }

        // The university's empty "OH som tas ut" got this year's calculator OH;
        // the region's own number is kept.
        XCTAssertEqual(store.organization(id: Self.universityID)?.managerOverheadPercent, 30)
        XCTAssertEqual(store.organization(id: Self.regionID)?.managerOverheadPercent, 8.8)

        // Runs once: a later change on the funder does not reach the records.
        store.setOrganizationOverheadRule(organizationID: Self.funderID, rule: FunderOverheadRule(kind: .cap, capPercent: 25))
        XCTAssertFalse(store.runRound10OneTimeDataMigrations())
        XCTAssertEqual(try record("to-apply").funderMaxOverheadPercent, 20)
    }

    func testCopyToNextYearKeepsTheRecordsNumbersButNotTheAnswer() {
        var application = Self.record(id: "a", status: "Beviljat", locked: true)
        application.funderMaxOverheadPercent = 20
        application.managerOverheadPercent = 30
        application.cofundingDecision = .yes
        application.cofundingDecisionOn = "2026-03-01"
        let copy = application.copiedToNextYear(newID: "b", rowNumber: 2, status: "Att söka")
        XCTAssertEqual(copy.funderMaxOverheadPercent, 20)
        XCTAssertEqual(copy.managerOverheadPercent, 30)
        XCTAssertNil(copy.cofundingDecision)
        XCTAssertNil(copy.cofundingDecisionOn)
    }

    // MARK: Rules in force on the application day (user decision 2026-09-29)

    func testNumbersTypedByHandAreNeverReplaced() {
        var application = Self.record(id: "a", status: "Att söka")
        XCTAssertTrue(application.applyOverheadDefaults(GrantOverheadDefaults(funderMaxPercent: 20, managerPercent: 30)))
        application.cofundingDecision = .yes
        application.cofundingDecisionOn = "2026-09-29"

        // A new default (another funder) replaces the numbers and the answer.
        XCTAssertTrue(application.applyOverheadDefaults(GrantOverheadDefaults(funderMaxPercent: 15, managerPercent: 30)))
        XCTAssertEqual(application.funderMaxOverheadPercent, 15)
        XCTAssertNil(application.cofundingDecision, "the answer was about the earlier numbers")

        // The same numbers again change nothing and keep the answer.
        application.cofundingDecision = .no
        XCTAssertFalse(application.applyOverheadDefaults(GrantOverheadDefaults(funderMaxPercent: 15, managerPercent: 30)))
        XCTAssertEqual(application.cofundingDecision, .no)

        // Typed by hand: never replaced.
        application.managerOverheadPercent = 32
        application.overheadNumbersSetByHand = true
        XCTAssertFalse(application.applyOverheadDefaults(GrantOverheadDefaults(funderMaxPercent: 25, managerPercent: 29)))
        XCTAssertEqual(application.managerOverheadPercent, 32)
        XCTAssertEqual(application.funderMaxOverheadPercent, 15)
    }

    func testOnlyRecordsNotYetAppliedFollowTheDefaults() {
        XCTAssertTrue(Self.record(id: "a", status: "Att söka").isNotYetApplied)
        XCTAssertTrue(Self.record(id: "b", status: "Ej sökt").isNotYetApplied)
        XCTAssertFalse(Self.record(id: "c", status: "Väntar svar").isNotYetApplied)
        XCTAssertFalse(Self.record(id: "d", status: "Beviljat").isNotYetApplied)
        let applied = Self.record(id: "e", status: "Väntar svar")
        XCTAssertEqual(DateParsers.isoDay.string(from: applied.overheadDefaultsDate), "2026-09-01", "read on the application day")
    }

    func testCalculatorOverheadFallsBackToTheLatestEndedPeriod() throws {
        let calculator = ManagerSalaryCalculator(
            birthDate: "",
            monthlySalaryPeriods: [],
            employerFeePeriods: [],
            regionalCostPeriods: [],
            itInfrastructureFeePeriods: [],
            listedPatientCountPeriods: [],
            overheadPeriods: [
                SalaryCalculatorPeriod(value: "31 %", from: "2024-01-01", to: "2024-12-31"),
                SalaryCalculatorPeriod(value: "30 %", from: "2025-01-01", to: "2025-12-31"),
            ],
            annualIncreaseAfterCurrentYearPercent: "3",
            allocationPercent: "",
            allocationMonths: ""
        )
        XCTAssertEqual(calculator.overheadPercent(on: try XCTUnwrap(DateParsers.isoDay.date(from: "2024-06-01"))), 31)
        XCTAssertEqual(calculator.overheadPercent(on: try XCTUnwrap(DateParsers.isoDay.date(from: "2027-03-01"))), 30, "no period this year: the latest one")
        XCTAssertNil(calculator.overheadPercent(on: try XCTUnwrap(DateParsers.isoDay.date(from: "2020-01-01"))))
    }

    // MARK: Numbers in free text

    func testYearCountAndAmountsAreReadAsWritten() {
        XCTAssertEqual(GrantParsing.largestNumber(in: "2-3"), 3)
        XCTAssertEqual(GrantParsing.largestNumber(in: "1,5 år"), 1.5)
        XCTAssertNil(GrantParsing.largestNumber(in: "okänt"))
        var application = Self.record(id: "a", status: "Att söka")
        application.maxAmount = "500 000"
        application.yearCount = "2-3"
        XCTAssertEqual(application.maximumTotalAmountValue, 1_500_000, "was 23 years before")

        XCTAssertEqual(GrantParsing.formatAmountInput("1 250 000,50"), "1 250 000")
        XCTAssertEqual(GrantParsing.formatAmountInput("1250000.5 kr"), "1 250 000")
        XCTAssertEqual(GrantParsing.formatAmountInput("1 500 000"), "1 500 000")
        XCTAssertEqual(GrantParsing.formatAmountInput("1.500.000"), "1 500 000", "points between thousands stay thousands")
    }
}
