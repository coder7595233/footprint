import XCTest
@testable import Footprint

/// Round 8: the old checkbox that left overhead out of a salary calculator
/// is cleared once, without any organization names in the code. The funder
/// setting that replaced it, "Max OH (%)", is now the "OH-regel" (see
/// Round8FunderOverheadRuleTests); these tests check it through that rule.
final class Round8FunderMaxOverheadTests: XCTestCase {
    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Round8FunderMaxOverheadTests-\(UUID().uuidString)", isDirectory: true)
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

    private static func calculator(excludesOverhead: Bool) -> ManagerSalaryCalculator {
        ManagerSalaryCalculator(
            birthDate: "",
            monthlySalaryPeriods: [],
            employerFeePeriods: [],
            regionalCostPeriods: [],
            itInfrastructureFeePeriods: [],
            listedPatientCountPeriods: [],
            overheadPeriods: [SalaryCalculatorPeriod(value: "20 %", from: "2027-01-01", to: "2028-12-31")],
            annualIncreaseAfterCurrentYearPercent: "3",
            allocationPercent: "",
            allocationMonths: "",
            legacyExcludesOverhead: excludesOverhead
        )
    }

    /// Ticked the old checkbox, no maximum yet.
    private static var funderA: OrganizationRecord {
        OrganizationRecord(
            id: "org-a",
            nameSv: "Organisation A",
            nameEn: "Organisation A",
            roles: [.grantProvider, .employer],
            salaryCalculator: calculator(excludesOverhead: true)
        )
    }

    /// Ticked the old checkbox, but already has a maximum of its own
    /// (stored with the earlier "Max OH (%)").
    private static var funderB: OrganizationRecord {
        OrganizationRecord(
            id: "org-b",
            nameSv: "Organisation B",
            nameEn: "Organisation B",
            roles: [.grantProvider],
            salaryCalculator: calculator(excludesOverhead: true),
            legacyMaxOverheadPercent: 15
        )
    }

    /// Did not tick the checkbox.
    private static var funderC: OrganizationRecord {
        OrganizationRecord(
            id: "org-c",
            nameSv: "Organisation C",
            nameEn: "Organisation C",
            roles: [.grantProvider, .employer],
            salaryCalculator: calculator(excludesOverhead: false)
        )
    }

    @MainActor
    private func makeStore(
        organizations: [OrganizationRecord] = [Round8FunderMaxOverheadTests.funderA, Round8FunderMaxOverheadTests.funderB, Round8FunderMaxOverheadTests.funderC],
        applications: [GrantApplication] = []
    ) -> GrantDataStore {
        GrantDataStore(
            applications: applications,
            organizations: organizations,
            skipInitialMigration: true
        )
    }

    // MARK: 1. Migration

    @MainActor
    func testMigrationClearsTheOldCheckboxOnceWithoutGuessingACap() throws {
        let store = makeStore()
        XCTAssertTrue(store.runRound8OneTimeDataMigrations())

        XCTAssertNil(store.organization(id: "org-a")?.overheadRule, "no cap is guessed from the old checkbox")
        XCTAssertEqual(
            store.organization(id: "org-b")?.overheadRule,
            FunderOverheadRule(kind: .cap, capPercent: 15),
            "a maximum already set is kept, now as the OH rule"
        )
        XCTAssertNil(store.organization(id: "org-b")?.legacyMaxOverheadPercent, "the earlier Max OH is no longer kept")
        XCTAssertNil(store.organization(id: "org-c")?.overheadRule, "an organization without the checkbox gets no cap")
        XCTAssertTrue(store.organizations.allSatisfy { $0.salaryCalculator?.legacyExcludesOverhead != true }, "the checkbox is cleared")
        XCTAssertEqual(store.organizations.count, 3, "no organization is lost or added")
        XCTAssertTrue((store.metadata.migrationLog ?? []).contains { $0.key == "round8-funder-max-overhead" })

        XCTAssertFalse(store.runRound8OneTimeDataMigrations(), "the migration runs only once")
        XCTAssertFalse(store.migrateLegacyOverheadCheckboxToFunderCapForRound8(), "running the step again changes nothing")
        XCTAssertNil(store.organization(id: "org-a")?.overheadRule)
    }

    @MainActor
    func testMigrationDoesNotDependOnNames() throws {
        var renamed = Self.funderA
        renamed.nameSv = "Helt annat namn"
        renamed.nameEn = "Another name"
        let store = makeStore(organizations: [renamed, Self.funderC])
        XCTAssertTrue(store.migrateLegacyOverheadCheckboxToFunderCapForRound8())
        XCTAssertNil(store.organization(id: "org-a")?.overheadRule)
        XCTAssertNil(store.organization(id: "org-c")?.overheadRule)
    }

    @MainActor
    func testMigrationWithoutCheckboxChangesNothing() {
        let store = makeStore(organizations: [Self.funderC])
        XCTAssertFalse(store.migrateLegacyOverheadCheckboxToFunderCapForRound8())
        XCTAssertNil(store.organization(id: "org-c")?.overheadRule)
    }

    @MainActor
    func testApplicationFindsFunderCapByIDFirst() throws {
        let application = GrantApplication(
            id: "app-1",
            rowNumber: 1,
            organizationID: "org-a",
            organization: "Namn som inte stämmer",
            grantName: "Projektbidrag"
        )
        let store = makeStore(applications: [application])
        store.runRound8OneTimeDataMigrations()
        let stored = try XCTUnwrap(store.applications.first)
        XCTAssertEqual(store.linkedFunder(of: stored)?.id, "org-a")
        // The old checkbox gives no rule (nothing is guessed): the standard.
        XCTAssertNil(store.linkedFunder(of: stored)?.overheadRule)
        XCTAssertEqual(store.overheadPlan(for: stored).rule, FunderOverheadRule())
    }

    @MainActor
    func testSettingMaxOverheadSetsTheOverheadRuleBetweenZeroAndHundred() {
        let store = makeStore(organizations: [Self.funderC])
        XCTAssertTrue(store.setOrganizationMaxOverheadPercent(organizationID: "org-c", percent: 10))
        XCTAssertEqual(store.organization(id: "org-c")?.overheadRule, FunderOverheadRule(kind: .cap, capPercent: 10))
        XCTAssertFalse(store.setOrganizationMaxOverheadPercent(organizationID: "org-c", percent: 10), "no change, nothing saved")
        store.setOrganizationMaxOverheadPercent(organizationID: "org-c", percent: 250)
        XCTAssertEqual(store.organization(id: "org-c")?.overheadRule, FunderOverheadRule(kind: .cap, capPercent: 100))
        store.setOrganizationMaxOverheadPercent(organizationID: "org-c", percent: -5)
        XCTAssertEqual(store.organization(id: "org-c")?.overheadRule, FunderOverheadRule(kind: .noOverhead), "0 or less = no OH")
        store.setOrganizationMaxOverheadPercent(organizationID: "org-c", percent: nil)
        XCTAssertNil(store.organization(id: "org-c")?.overheadRule, "empty = the fund manager's full OH (the standard)")
    }

    // MARK: 2. Calculation

    func testOverheadRateIsCappedByTheFunder() {
        XCTAssertEqual(grantOverheadRate(0.20, cappedAtPercent: 10), 0.10, accuracy: 0.000_001)
        XCTAssertEqual(grantOverheadRate(0.20, cappedAtPercent: 0), 0)
        XCTAssertEqual(grantOverheadRate(0.20, cappedAtPercent: nil), 0.20, accuracy: 0.000_001)
        XCTAssertEqual(grantOverheadRate(0.08, cappedAtPercent: 10), 0.08, accuracy: 0.000_001, "a cap above the rate changes nothing")
    }

    func testSalaryApproximationUsesTheCap() throws {
        let calculator = ManagerSalaryCalculator(
            birthDate: "2000-01-01",
            monthlySalaryPeriods: [SalaryCalculatorPeriod(value: "1000", from: "2027-01-01", to: "2028-12-31")],
            employerFeePeriods: [],
            regionalCostPeriods: [],
            itInfrastructureFeePeriods: [],
            listedPatientCountPeriods: [],
            overheadPeriods: [SalaryCalculatorPeriod(value: "20", from: "2027-01-01", to: "2028-12-31")],
            annualIncreaseAfterCurrentYearPercent: "0",
            allocationPercent: "",
            allocationMonths: ""
        )
        let startMonth = try XCTUnwrap(DateParsers.isoDay.date(from: "2027-01-01"))
        func total(includesOverhead: Bool, cap: Double?) throws -> Double {
            try XCTUnwrap(
                calculateGrantSalaryApproximation(
                    calculator: calculator,
                    percentageText: "100",
                    monthsText: "12",
                    startMonth: startMonth,
                    includesOverhead: includesOverhead,
                    maxOverheadPercent: cap
                )
            ).totalAmount
        }
        let withoutOverhead = try total(includesOverhead: false, cap: nil)
        XCTAssertGreaterThan(withoutOverhead, 0)
        XCTAssertEqual(try total(includesOverhead: true, cap: nil), withoutOverhead * 1.20, accuracy: 0.01, "no cap: 20 % OH")
        XCTAssertEqual(try total(includesOverhead: true, cap: 10), withoutOverhead * 1.10, accuracy: 0.01, "20 % OH with max 10 gives 10 %")
        XCTAssertEqual(try total(includesOverhead: true, cap: 0), withoutOverhead, accuracy: 0.01, "max 0 gives no OH")
    }

    // MARK: 3. Older data

    func testOldCalculatorWithCheckboxDecodesAndIsNotWrittenAgain() throws {
        let storedKey = ManagerSalaryCalculator.CodingKeys.legacyExcludesOverhead.rawValue
        let payload: [String: Any] = ["birthDate": "", storedKey: true]
        let old = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONDecoder().decode(ManagerSalaryCalculator.self, from: old)
        XCTAssertTrue(decoded.legacyExcludesOverhead, "older data still decodes")

        let written = try JSONEncoder().encode(decoded)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: written) as? [String: Any])
        XCTAssertNil(object[storedKey], "the old checkbox is not written")

        let missing = try JSONDecoder().decode(ManagerSalaryCalculator.self, from: Data(#"{"birthDate":""}"#.utf8))
        XCTAssertFalse(missing.legacyExcludesOverhead)
    }

    func testOrganizationMaxOverheadDecodesFromOldDataIntoTheOverheadRule() throws {
        let old = #"{"id":"o1","nameSv":"Organisation","nameEn":"Organisation"}"#
        let decodedOld = try JSONDecoder().decode(OrganizationRecord.self, from: Data(old.utf8))
        XCTAssertNil(decodedOld.overheadRule, "older data has no rule")
        XCTAssertNil(decodedOld.legacyMaxOverheadPercent)
        let writtenOld = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decodedOld)) as? [String: Any])
        XCTAssertNil(writtenOld["maxOverheadPercent"], "no cap is not written")
        XCTAssertNil(writtenOld["overheadRule"], "no rule is not written")

        let withMax = #"{"id":"o2","nameSv":"Organisation","nameEn":"Organisation","maxOverheadPercent":12.5}"#
        let decodedWithMax = try JSONDecoder().decode(OrganizationRecord.self, from: Data(withMax.utf8))
        XCTAssertEqual(decodedWithMax.overheadRule, FunderOverheadRule(kind: .cap, capPercent: 12.5))
        let written = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decodedWithMax)) as? [String: Any])
        XCTAssertNil(written["maxOverheadPercent"], "the earlier Max OH is no longer written")
        XCTAssertNotNil(written["overheadRule"])
        let roundTripped = try JSONDecoder().decode(OrganizationRecord.self, from: JSONEncoder().encode(decodedWithMax))
        XCTAssertEqual(roundTripped.overheadRule, FunderOverheadRule(kind: .cap, capPercent: 12.5))
    }
}
