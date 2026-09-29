import XCTest
@testable import Footprint

/// Round 8: the OH of an application depends on both the fund manager (its
/// own full OH) and the grant provider ("OH-regel": the fund manager's full
/// OH, at most a percent, or no OH, with exceptions per fund manager). All
/// names below are made up.
final class Round8FunderOverheadRuleTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Round8FunderOverheadRuleTests-\(UUID().uuidString)", isDirectory: true)
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
    private static let funderID = "org-forskningsradet"

    private static func calculator(overheadPercent: String?) -> ManagerSalaryCalculator {
        ManagerSalaryCalculator(
            birthDate: "2000-01-01",
            monthlySalaryPeriods: [SalaryCalculatorPeriod(value: "1000", from: "2027-01-01", to: "2028-12-31")],
            employerFeePeriods: [],
            regionalCostPeriods: [],
            itInfrastructureFeePeriods: [],
            listedPatientCountPeriods: [],
            overheadPeriods: overheadPercent.map { [SalaryCalculatorPeriod(value: $0, from: "2027-01-01", to: "2028-12-31")] } ?? [],
            annualIncreaseAfterCurrentYearPercent: "0",
            allocationPercent: "",
            allocationMonths: ""
        )
    }

    /// Fund manager with OH 20 % in its salary calculator.
    private static var university: OrganizationRecord {
        OrganizationRecord(
            id: universityID,
            nameSv: "Exempelköpings universitet",
            nameEn: "Exempelköping University",
            roles: [.fundManager, .employer, .institution],
            salaryCalculator: calculator(overheadPercent: "20")
        )
    }

    /// Fund manager without a salary calculator, with "Förvaltarens fulla OH" 30 %.
    private static var region: OrganizationRecord {
        OrganizationRecord(
            id: regionID,
            nameSv: "Region Exempelgöta",
            nameEn: "Region Exempelgota",
            roles: [.fundManager],
            managerOverheadPercent: 30
        )
    }

    private static func funder(
        rule: FunderOverheadRule? = nil,
        exceptions: [FunderOverheadRuleException]? = nil
    ) -> OrganizationRecord {
        OrganizationRecord(
            id: funderID,
            nameSv: "Forskningsrådet Exempel",
            nameEn: "Example Research Council",
            roles: [.grantProvider],
            overheadRule: rule,
            overheadRuleExceptions: exceptions
        )
    }

    private static let full = FunderOverheadRule()
    private static let noOH = FunderOverheadRule(kind: .noOverhead)
    private static func cap(_ percent: Double) -> FunderOverheadRule {
        FunderOverheadRule(kind: .cap, capPercent: percent)
    }

    // MARK: 1. Rule resolution matrix

    func testEffectiveRateForEachChoice() {
        XCTAssertEqual(Self.full.effectiveRate(managerRate: 0.20), 0.20, accuracy: 0.000_001, "full OH")
        XCTAssertEqual(Self.cap(15).effectiveRate(managerRate: 0.20), 0.15, accuracy: 0.000_001, "cap below the fund manager's OH")
        XCTAssertEqual(Self.cap(25).effectiveRate(managerRate: 0.20), 0.20, accuracy: 0.000_001, "cap above the fund manager's OH gives the fund manager's OH")
        XCTAssertEqual(Self.cap(0).effectiveRate(managerRate: 0.20), 0, "cap 0 gives no OH")
        XCTAssertEqual(Self.noOH.effectiveRate(managerRate: 0.20), 0, "no OH")
        XCTAssertEqual(
            FunderOverheadRule(kind: .cap, capPercent: nil).effectiveRate(managerRate: 0.20),
            0.20,
            accuracy: 0.000_001,
            "\"at most\" without a number caps nothing"
        )
    }

    func testDefaultRuleWithoutAnyException() {
        let exceptionForRegion = FunderOverheadRuleException(managerOrganizationID: Self.regionID, rule: Self.noOH)
        for rule in [Self.full, Self.cap(15), Self.noOH] {
            let funder = Self.funder(rule: rule, exceptions: [exceptionForRegion])
            XCTAssertEqual(funder.resolvedOverheadRule(forManagerOrganizationID: Self.universityID), rule, "another fund manager's exception does not count")
            XCTAssertEqual(funder.resolvedOverheadRule(forManagerOrganizationID: nil), rule, "no fund manager: the default")
        }
        XCTAssertEqual(Self.funder().resolvedOverheadRule(forManagerOrganizationID: Self.universityID), Self.full, "no rule set = full OH")
    }

    func testExceptionOverridesTheDefaultForItsFundManager() {
        for defaultRule in [Self.full, Self.cap(15), Self.noOH] {
            for exceptionRule in [Self.full, Self.cap(10), Self.noOH] {
                let funder = Self.funder(
                    rule: defaultRule,
                    exceptions: [FunderOverheadRuleException(managerOrganizationID: Self.regionID, rule: exceptionRule)]
                )
                XCTAssertEqual(funder.resolvedOverheadRule(forManagerOrganizationID: Self.regionID), exceptionRule)
                XCTAssertEqual(funder.resolvedOverheadRule(forManagerOrganizationID: Self.universityID), defaultRule)
            }
        }
    }

    func testExceptionWithoutChosenFundManagerIsIgnored() {
        let funder = Self.funder(rule: Self.cap(15), exceptions: [FunderOverheadRuleException(managerOrganizationID: "", rule: Self.noOH)])
        XCTAssertEqual(funder.resolvedOverheadRule(forManagerOrganizationID: ""), Self.cap(15))
        XCTAssertEqual(funder.resolvedOverheadRule(forManagerOrganizationID: nil), Self.cap(15))
    }

    func testPlanTakesTheFundManagersOwnOverhead() throws {
        let start = try XCTUnwrap(DateParsers.isoDay.date(from: "2027-03-01"))
        let applicationCalculator = Self.calculator(overheadPercent: "5")

        // The fund manager's own calculator periods (20 %) count first.
        let universityPlan = GrantOverheadPlan.resolved(funder: Self.funder(rule: Self.cap(15)), manager: Self.university)
        let universityRates = grantOverheadRates(on: start, calculator: applicationCalculator, plan: universityPlan)
        XCTAssertEqual(universityRates.manager, 0.20, accuracy: 0.000_001)
        XCTAssertEqual(universityRates.effective, 0.15, accuracy: 0.000_001)

        // Without periods, "Förvaltarens fulla OH (%)" (30 %) counts.
        let regionPlan = GrantOverheadPlan.resolved(funder: Self.funder(rule: Self.cap(40)), manager: Self.region)
        let regionRates = grantOverheadRates(on: start, calculator: applicationCalculator, plan: regionPlan)
        XCTAssertEqual(regionRates.manager, 0.30, accuracy: 0.000_001)
        XCTAssertEqual(regionRates.effective, 0.30, accuracy: 0.000_001, "cap above the fund manager's OH")

        // No fund manager: the application salary calculator's OH (5 %), as before.
        let noManagerPlan = GrantOverheadPlan.resolved(funder: Self.funder(rule: Self.noOH), manager: nil)
        let noManagerRates = grantOverheadRates(on: start, calculator: applicationCalculator, plan: noManagerPlan)
        XCTAssertEqual(noManagerRates.manager, 0.05, accuracy: 0.000_001)
        XCTAssertEqual(noManagerRates.effective, 0)
    }

    @MainActor
    func testStoreFindsFunderAndFundManagerByID() throws {
        var application = GrantApplication(
            id: "app-1",
            rowNumber: 1,
            organizationID: Self.funderID,
            organization: "Namn som inte stämmer",
            grantName: "Projektbidrag"
        )
        application.applicationManagerID = Self.regionID
        application.applicationManager = "Ett gammalt namn"
        let funder = Self.funder(
            rule: Self.cap(15),
            exceptions: [FunderOverheadRuleException(managerOrganizationID: Self.regionID, rule: Self.noOH)]
        )
        let store = GrantDataStore(
            applications: [application],
            organizations: [Self.university, Self.region, funder],
            managers: [
                ManagerOption(id: Self.universityID, nameSv: "Exempelköpings universitet", nameEn: "Exempelköping University", reason: nil),
                ManagerOption(id: Self.regionID, nameSv: "Region Exempelgöta", nameEn: "Region Exempelgota", reason: nil)
            ],
            skipInitialMigration: true
        )
        let stored = try XCTUnwrap(store.applications.first)
        let plan = store.overheadPlan(for: stored)
        XCTAssertEqual(plan.rule, Self.noOH, "the exception for the application's fund manager")
        XCTAssertEqual(plan.managerOverheadPercent, 30)
        XCTAssertEqual(store.fundManagerOrganizations.map(\.id), [Self.universityID, Self.regionID], "only fund managers, by name")

        var other = stored
        other.applicationManagerID = Self.universityID
        XCTAssertEqual(store.overheadPlan(for: other).rule, Self.cap(15), "another fund manager: the default rule")
    }

    // MARK: 2. Co-funding

    func testCofundingIsTheFundManagersOverheadMinusTheOverheadThatCounts() throws {
        let calculator = Self.calculator(overheadPercent: "20")
        let startMonth = try XCTUnwrap(DateParsers.isoDay.date(from: "2027-01-01"))
        func breakdown(_ plan: GrantOverheadPlan, includesOverhead: Bool = true) throws -> GrantSalaryApproximationBreakdown {
            try XCTUnwrap(
                calculateGrantSalaryApproximation(
                    calculator: calculator,
                    percentageText: "50",
                    monthsText: "12",
                    startMonth: startMonth,
                    includesOverhead: includesOverhead,
                    overheadPlan: plan
                )
            )
        }
        let base = try breakdown(GrantOverheadPlan(), includesOverhead: false).totalAmount
        XCTAssertGreaterThan(base, 0)

        let fullOH = try breakdown(GrantOverheadPlan(rule: Self.full))
        XCTAssertEqual(fullOH.totalAmount, base * 1.20, accuracy: 0.01)
        XCTAssertEqual(fullOH.cofundingAmount, 0, accuracy: 0.01, "full OH: nothing to co-fund")

        let capped = try breakdown(GrantOverheadPlan(rule: Self.cap(15)))
        XCTAssertEqual(capped.totalAmount, base * 1.15, accuracy: 0.01)
        XCTAssertEqual(capped.cofundingAmount, base * 0.05, accuracy: 0.01, "20 % − 15 % of the same base")

        let none = try breakdown(GrantOverheadPlan(rule: Self.noOH))
        XCTAssertEqual(none.totalAmount, base, accuracy: 0.01)
        XCTAssertEqual(none.cofundingAmount, base * 0.20, accuracy: 0.01)

        let capAbove = try breakdown(GrantOverheadPlan(rule: Self.cap(30)))
        XCTAssertEqual(capAbove.totalAmount, base * 1.20, accuracy: 0.01)
        XCTAssertEqual(capAbove.cofundingAmount, 0, accuracy: 0.01)

        let withoutOverhead = try breakdown(GrantOverheadPlan(rule: Self.noOH), includesOverhead: false)
        XCTAssertEqual(withoutOverhead.cofundingAmount, 0, "OH not included: no co-funding line")
        XCTAssertEqual(withoutOverhead.totalAmount, base, accuracy: 0.01, "the \"Inkluderar OH\" box works as before")

        let managerOwn = try breakdown(GrantOverheadPlan(rule: Self.cap(15), managerOverheadPercent: 30))
        XCTAssertEqual(managerOwn.totalAmount, base * 1.15, accuracy: 0.01)
        XCTAssertEqual(managerOwn.cofundingAmount, base * 0.15, accuracy: 0.01, "30 % − 15 %")
    }

    // MARK: 3. Text next to the budget

    func testSummaryText() {
        XCTAssertEqual(
            grantOverheadSummaryText(managerPercent: 20, effectivePercent: 15, rule: Self.cap(15), language: .swedish),
            "OH: 15 % (förvaltarens 20 %, anslagsgivarens tak 15 %)"
        )
        XCTAssertEqual(
            grantOverheadSummaryText(managerPercent: 20, effectivePercent: 20, rule: Self.full, language: .swedish),
            "OH: 20 % (förvaltarens 20 %, anslagsgivaren godtar full OH)"
        )
        XCTAssertEqual(
            grantOverheadSummaryText(managerPercent: 12.5, effectivePercent: 0, rule: Self.noOH, language: .swedish),
            "OH: 0 % (förvaltarens 12,5 %, anslagsgivaren ger ingen OH)"
        )
        XCTAssertEqual(grantFormattedPercent(33.333), "33,33 %")
    }

    // MARK: 4. Migration from "Max OH (%)"

    func testMigratedRuleFromMaxOverhead() {
        XCTAssertNil(FunderOverheadRule.migrated(fromLegacyMaxOverheadPercent: nil), "no value: the standard")
        XCTAssertEqual(FunderOverheadRule.migrated(fromLegacyMaxOverheadPercent: 0), Self.noOH, "0 = no OH")
        XCTAssertEqual(FunderOverheadRule.migrated(fromLegacyMaxOverheadPercent: 12.5), Self.cap(12.5))
        XCTAssertEqual(FunderOverheadRule.migrated(fromLegacyMaxOverheadPercent: 250), Self.cap(100))
    }

    @MainActor
    func testStoreMigrationMovesMaxOverheadOnce() throws {
        let withValue = OrganizationRecord(id: "f1", nameSv: "Stiftelsen Exempel", nameEn: "Example Foundation", roles: [.grantProvider], legacyMaxOverheadPercent: 10)
        let withZero = OrganizationRecord(id: "f2", nameSv: "Fonden Exempel", nameEn: "Example Fund", roles: [.grantProvider], legacyMaxOverheadPercent: 0)
        let withoutValue = OrganizationRecord(id: "f3", nameSv: "Forskningsrådet Exempel", nameEn: "Example Research Council", roles: [.grantProvider])
        let alreadySet = OrganizationRecord(
            id: "f4",
            nameSv: "Förbundet Exempel",
            nameEn: "Example Association",
            roles: [.grantProvider],
            legacyMaxOverheadPercent: 10,
            overheadRule: Self.noOH
        )
        let store = GrantDataStore(organizations: [withValue, withZero, withoutValue, alreadySet], skipInitialMigration: true)

        XCTAssertTrue(store.runRound8OneTimeDataMigrations())
        XCTAssertEqual(store.organization(id: "f1")?.overheadRule, Self.cap(10))
        XCTAssertEqual(store.organization(id: "f2")?.overheadRule, Self.noOH)
        XCTAssertNil(store.organization(id: "f3")?.overheadRule)
        XCTAssertEqual(store.organization(id: "f4")?.overheadRule, Self.noOH, "a rule already set is kept")
        XCTAssertTrue(store.organizations.allSatisfy { $0.legacyMaxOverheadPercent == nil }, "the earlier value is cleared")
        XCTAssertEqual(store.organizations.count, 4, "no organization is lost or added")
        XCTAssertTrue((store.metadata.migrationLog ?? []).contains { $0.key == "round8-funder-overhead-rule" })

        XCTAssertFalse(store.runRound8OneTimeDataMigrations(), "the migration runs only once")
        XCTAssertFalse(store.migrateFunderMaxOverheadToOverheadRuleForRound8(), "running the step again changes nothing")
    }

    // MARK: 5. Older and newer data

    func testDecodingOldAndNewData() throws {
        let zero = #"{"id":"o1","nameSv":"Organisation","nameEn":"Organisation","maxOverheadPercent":0}"#
        let decodedZero = try JSONDecoder().decode(OrganizationRecord.self, from: Data(zero.utf8))
        XCTAssertEqual(decodedZero.overheadRule, Self.noOH)
        XCTAssertEqual(decodedZero.legacyMaxOverheadPercent, 0, "kept until the one-time step clears it")
        XCTAssertNil(decodedZero.overheadRuleExceptions)
        XCTAssertNil(decodedZero.managerOverheadPercent)

        let both = #"{"id":"o2","nameSv":"Organisation","nameEn":"Organisation","maxOverheadPercent":10,"overheadRule":{"kind":"managerFull"}}"#
        XCTAssertEqual(try JSONDecoder().decode(OrganizationRecord.self, from: Data(both.utf8)).overheadRule, Self.full, "a stored rule wins")

        let full = OrganizationRecord(
            id: "o3",
            nameSv: "Organisation",
            nameEn: "Organisation",
            roles: [.grantProvider, .fundManager],
            overheadRule: FunderOverheadRule(kind: .cap, capPercent: 15, capIncludesPremises: true),
            overheadRuleExceptions: [FunderOverheadRuleException(id: "e1", managerOrganizationID: "m1", rule: Self.noOH)],
            managerOverheadPercent: 22
        )
        let data = try JSONEncoder().encode(full)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["maxOverheadPercent"])
        let rule = try XCTUnwrap(object["overheadRule"] as? [String: Any])
        XCTAssertEqual(rule["kind"] as? String, "cap")
        let exceptionRule = try XCTUnwrap(((object["overheadRuleExceptions"] as? [[String: Any]])?.first?["rule"]) as? [String: Any])
        XCTAssertEqual(exceptionRule["kind"] as? String, "none", "\"Ingen OH\" is stored as none")
        XCTAssertEqual(try JSONDecoder().decode(OrganizationRecord.self, from: data), full)

        let unknownKind = #"{"kind":"somethingNew","capPercent":5}"#
        XCTAssertEqual(try JSONDecoder().decode(FunderOverheadRule.self, from: Data(unknownKind.utf8)).kind, .managerFull)
        let emptyException = try JSONDecoder().decode(FunderOverheadRuleException.self, from: Data("{}".utf8))
        XCTAssertEqual(emptyException.managerOrganizationID, "")
        XCTAssertEqual(emptyException.rule, Self.full)
    }

    // MARK: 6. Settings on the organizations

    @MainActor
    func testSettersStoreOnlyWhatIsSet() {
        let store = GrantDataStore(organizations: [Self.funder(), Self.region], skipInitialMigration: true)
        XCTAssertFalse(store.setOrganizationOverheadRule(organizationID: Self.funderID, rule: Self.full), "the standard is stored as nothing")
        XCTAssertTrue(store.setOrganizationOverheadRule(organizationID: Self.funderID, rule: FunderOverheadRule(kind: .cap, capPercent: 150)))
        XCTAssertEqual(store.organization(id: Self.funderID)?.overheadRule, Self.cap(100), "kept between 0 and 100")
        XCTAssertTrue(store.setOrganizationOverheadRule(organizationID: Self.funderID, rule: nil))
        XCTAssertNil(store.organization(id: Self.funderID)?.overheadRule)

        let exception = FunderOverheadRuleException(id: "e1", managerOrganizationID: " \(Self.regionID) ", rule: Self.noOH)
        XCTAssertTrue(store.setOrganizationOverheadRuleExceptions(organizationID: Self.funderID, exceptions: [exception]))
        XCTAssertEqual(store.organization(id: Self.funderID)?.overheadRuleExceptions?.first?.managerOrganizationID, Self.regionID)
        XCTAssertTrue(store.setOrganizationOverheadRuleExceptions(organizationID: Self.funderID, exceptions: []))
        XCTAssertNil(store.organization(id: Self.funderID)?.overheadRuleExceptions, "an empty list is stored as nothing")

        XCTAssertTrue(store.setOrganizationManagerOverheadPercent(organizationID: Self.regionID, percent: 25))
        XCTAssertEqual(store.organization(id: Self.regionID)?.managerOverheadPercent, 25)
        XCTAssertFalse(store.setOrganizationManagerOverheadPercent(organizationID: Self.regionID, percent: 25), "no change, nothing saved")
        store.setOrganizationManagerOverheadPercent(organizationID: Self.regionID, percent: nil)
        XCTAssertNil(store.organization(id: Self.regionID)?.managerOverheadPercent)
    }
}
