import XCTest
@testable import Footprint

/// Round 16, list filters (part B). All names and values below are made up.
final class Round16FiltersBTests: XCTestCase {

    // MARK: Archive: delete only what is selected and visible

    func testArchiveDeletesOnlySelectedVisibleRecords() {
        let selected: Set<String> = ["a", "b", "hidden"]
        let visible = ["a", "b", "c"]
        XCTAssertEqual(ArchiveSelectionPolicy.deletableIDs(selected: selected, visibleIDs: visible), ["a", "b"])
        XCTAssertTrue(ArchiveSelectionPolicy.deletableIDs(selected: ["hidden"], visibleIDs: visible).isEmpty)
    }

    func testArchiveSelectAllComparesSetsNotCounts() {
        // Same count, different records: not "all selected".
        XCTAssertFalse(ArchiveSelectionPolicy.allVisibleSelected(selected: ["x", "y"], visibleIDs: ["a", "b"]))
        XCTAssertTrue(ArchiveSelectionPolicy.allVisibleSelected(selected: ["a", "b", "x"], visibleIDs: ["a", "b"]))
        XCTAssertFalse(ArchiveSelectionPolicy.allVisibleSelected(selected: [], visibleIDs: []))
    }

    // MARK: Year range that follows the available years

    func testFollowingRangeWidensWithNewYears() {
        let range = FollowingYearRange(lower: 2020, upper: 2024, follows: true)
        let next = range.reconciled(to: 2020...2026)
        XCTAssertEqual(next, FollowingYearRange(lower: 2020, upper: 2026, follows: true))
    }

    func testNarrowedRangeIsKept() {
        let range = FollowingYearRange(lower: 2021, upper: 2022, follows: false)
        XCTAssertEqual(range.reconciled(to: 2018...2026), range)
    }

    func testEmptyRowsNeverClampTheRange() {
        let range = FollowingYearRange(lower: 2021, upper: 2022, follows: false)
        XCTAssertEqual(range.reconciled(to: nil), range)
    }

    func testRecordsWithoutYearHiddenOnlyWhenNarrowed() {
        XCTAssertTrue(FollowingYearRange(lower: 2020, upper: 2024, follows: true).matches(year: nil))
        XCTAssertFalse(FollowingYearRange(lower: 2020, upper: 2024, follows: false).matches(year: nil))
        XCTAssertTrue(FollowingYearRange(lower: 2020, upper: 2024, follows: false).matches(year: 2022))
        XCTAssertFalse(FollowingYearRange(lower: 2020, upper: 2024, follows: false).matches(year: 2025))
        XCTAssertTrue(FollowingYearRange(lower: 2020, upper: 2020, follows: false).matches(anyOf: [2019, 2020]))
        XCTAssertTrue(FollowingYearRange(lower: 2020, upper: 2020, follows: true).matches(anyOf: []))
    }

    func testSliderAtFullRangeFollowsAgain() {
        XCTAssertTrue(FollowingYearRange.userSet(lower: 2018, upper: 2026, bounds: 2018...2026).follows)
        XCTAssertFalse(FollowingYearRange.userSet(lower: 2019, upper: 2026, bounds: 2018...2026).follows)
    }

    func testLegacySavedRanges() {
        XCTAssertTrue(FollowingYearRange.legacyFollows(lower: 0, upper: 0, bounds: nil))
        XCTAssertTrue(FollowingYearRange.legacyFollows(lower: 2018, upper: 2026, bounds: 2018...2026))
        XCTAssertFalse(FollowingYearRange.legacyFollows(lower: 2020, upper: 2022, bounds: 2018...2026))
    }

    // MARK: Selection after a filter change

    func testSelectionMovesToFirstVisibleRowWhenHidden() {
        XCTAssertEqual(ListSelectionPolicy.selectionAfterFilterChange(selected: "b", visibleIDs: ["a", "b"]), "b")
        XCTAssertEqual(ListSelectionPolicy.selectionAfterFilterChange(selected: "z", visibleIDs: ["a", "b"]), "a")
        XCTAssertNil(ListSelectionPolicy.selectionAfterFilterChange(selected: "z", visibleIDs: []))
        XCTAssertNil(ListSelectionPolicy.selectionAfterFilterChange(selected: nil, visibleIDs: ["a"]))
    }

    // MARK: Chip groups

    func testChipGroupsAreOrWithinAndBetween() {
        let row: Set<String> = ["ongoing", "overdue"]
        XCTAssertTrue(matchesFilterChipGroups([(selected: ["completed", "overdue"], values: row)]))
        XCTAssertFalse(matchesFilterChipGroups([
            (selected: ["ongoing"], values: row),
            (selected: ["journalReview"], values: ["doctoralExamination"]),
        ]))
        XCTAssertTrue(matchesFilterChipGroups([
            (selected: [], values: row),
            (selected: ["journalReview"], values: ["journalReview"]),
        ]))
    }

    // MARK: Expert assignments status chips

    func testExpertAssignmentStatusKeys() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let today = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-06-15"))

        let noDates = CVReviewEntry()
        XCTAssertEqual(ExpertAssignmentStatusKey.keys(for: noDates, referenceDate: today, calendar: calendar), [.noStatus])

        let declined = CVReviewEntry(deadlineDate: "2026-05-01")
        XCTAssertEqual(ExpertAssignmentStatusKey.keys(for: declined, referenceDate: today, calendar: calendar), [.declined])

        let ongoing = CVReviewEntry(acceptedDate: "2026-06-01", deadlineDate: "2026-07-01")
        XCTAssertEqual(ExpertAssignmentStatusKey.keys(for: ongoing, referenceDate: today, calendar: calendar), [.ongoing])

        let overdue = CVReviewEntry(acceptedDate: "2026-04-01", deadlineDate: "2026-05-01")
        XCTAssertEqual(ExpertAssignmentStatusKey.keys(for: overdue, referenceDate: today, calendar: calendar), [.ongoing, .overdue])

        let done = CVReviewEntry(acceptedDate: "2026-04-01", date: "2026-04-20")
        XCTAssertEqual(ExpertAssignmentStatusKey.keys(for: done, referenceDate: today, calendar: calendar), [.completed])
    }

    func testExpertStatusChipTitles() {
        XCTAssertEqual(
            ExpertAssignmentStatusKey.allCases.map { $0.title(language: .swedish) },
            ["Pågående", "Försenade", "Klara", "Avböjda", "Utan status"]
        )
    }

    // MARK: Doctoral candidates

    func testEffectiveDisputationDatePrefersActualDate() {
        let planned = DoctoralCandidateRecord(plannedDisputationDate: "2027-05-01")
        XCTAssertEqual(planned.effectiveDisputationDate, "2027-05-01")
        let held = DoctoralCandidateRecord(disputationDate: "2026-03-10", plannedDisputationDate: "2027-05-01")
        XCTAssertEqual(held.effectiveDisputationDate, "2026-03-10")
    }

    func testActiveExcludesCompletedAndEndedEarly() throws {
        let today = try XCTUnwrap(DateParsers.isoDay.date(from: "2026-06-15"))
        XCTAssertTrue(DoctoralCandidateRecord(plannedDisputationDate: "2027-05-01").isActiveDoctoralCandidate(today: today))
        XCTAssertTrue(DoctoralCandidateRecord().isActiveDoctoralCandidate(today: today))
        XCTAssertFalse(DoctoralCandidateRecord(
            plannedDisputationDate: "2027-05-01",
            plannedDisputationOutcomeRaw: DoctoralMilestoneOutcome.completed.rawValue
        ).isActiveDoctoralCandidate(today: today))
        XCTAssertFalse(DoctoralCandidateRecord(
            halftimeOutcomeRaw: DoctoralMilestoneOutcome.endedBefore.rawValue,
            plannedDisputationDate: "2027-05-01"
        ).isActiveDoctoralCandidate(today: today))
        XCTAssertFalse(DoctoralCandidateRecord(
            disputationDate: "2026-03-10",
            plannedDisputationDate: "2027-05-01"
        ).isActiveDoctoralCandidate(today: today))
    }

    // MARK: Teaching programme filter across languages

    func testProgramFilterSurvivesLanguageChange() {
        let programs = [
            (swedish: "Påhittat program", english: "Invented programme"),
            (swedish: "Annat program", english: "Other programme"),
        ]
        let english = TeachingProgramFilterKeys.remap(["Påhittat program"], programs: programs, language: .english)
        XCTAssertEqual(english, ["Invented programme"])
        let swedish = TeachingProgramFilterKeys.remap(english, programs: programs, language: .swedish)
        XCTAssertEqual(swedish, ["Påhittat program"])
        XCTAssertTrue(TeachingProgramFilterKeys.remap(["Removed programme"], programs: programs, language: .english).isEmpty)
        XCTAssertTrue(TeachingProgramFilterKeys.matches(["PÅHITTAT  program"], swedish: "Påhittat program", english: "Invented programme"))
        XCTAssertFalse(TeachingProgramFilterKeys.matches(["Other programme"], swedish: "Påhittat program", english: "Invented programme"))
    }

    func testTeachingFilterMovesToAccountScopeOnce() throws {
        let suiteName = "Round16FiltersBTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacy = Data("{\"searchText\":\"invented\"}".utf8)
        defaults.set(legacy, forKey: "legacy")

        TeachingFilterStorageMigration.migrateIfNeeded(defaults: defaults, legacyKey: "legacy", scopedKey: "scoped", migrationFlagKey: "flag")
        XCTAssertEqual(defaults.data(forKey: "scoped"), legacy)
        XCTAssertEqual(defaults.data(forKey: "legacy"), legacy, "the old value is kept")

        // A second account must not inherit the old value again.
        TeachingFilterStorageMigration.migrateIfNeeded(defaults: defaults, legacyKey: "legacy", scopedKey: "otherAccount", migrationFlagKey: "flag")
        XCTAssertNil(defaults.data(forKey: "otherAccount"))
    }

    // MARK: Search: accents and several words

    func testSearchIgnoresAccentsAndNeedsEveryWord() {
        let haystack = "Östergren Inventedsson"
        XCTAssertTrue(SearchFilterQuery(raw: "Ostergren").matches(haystack: haystack))
        XCTAssertTrue(SearchFilterQuery(raw: "inventedsson ostergren").matches(haystack: haystack))
        XCTAssertFalse(SearchFilterQuery(raw: "ostergren -inventedsson").matches(haystack: haystack))
    }

    // MARK: Statistics drilldown order

    func testDrilldownSortsByOrganizationThenName() {
        let rows = [
            (organization: "B Invented Fund", name: "Alpha"),
            (organization: "A Invented Fund", name: "Zeta"),
            (organization: "A Invented Fund", name: "Beta"),
        ]
        let sorted = rows.sorted {
            statisticsDrilldownOrganizationThenNameOrder(
                lhsOrganization: $0.organization,
                lhsName: $0.name,
                rhsOrganization: $1.organization,
                rhsName: $1.name
            )
        }
        XCTAssertEqual(sorted.map(\.name), ["Beta", "Zeta", "Alpha"])
    }

    // MARK: Researchers: incomplete-data filter is named

    func testIncompleteDataFilterHasAVisibleTitle() {
        XCTAssertNil(PersonIncompleteDataFilter.none.activeFilterTitle(language: .swedish))
        for filter in PersonIncompleteDataFilter.allCases where filter != .none {
            XCTAssertNotNil(filter.activeFilterTitle(language: .swedish))
        }
    }
}
