import XCTest
@testable import Footprint

/// Round 16, part 1: list filters (year range that follows new years, one
/// status mapping, project filter by id, researcher matching, dashes in
/// search). All names and values below are made up.
final class Round16FiltersATests: XCTestCase {

    // MARK: Year range

    func testRangeIsLeftAloneWhileThereAreNoRows() {
        let saved = ListYearRangeFilter(lower: 2018, upper: 2022, followsLower: false, followsUpper: false)
        XCTAssertEqual(saved.resolved(within: nil), saved)
        XCTAssertNil(ListYearRangeFilter.bounds(forYears: []))
    }

    func testUnsetRangeCoversAllYears() {
        let unset = ListYearRangeFilter(lower: 0, upper: 0, followsLower: true, followsUpper: true)
        let bounds = ListYearRangeFilter.bounds(forYears: [2021, 2017, 2024])
        XCTAssertEqual(bounds, 2017...2024)
        let resolved = unset.resolved(within: bounds)
        XCTAssertEqual(resolved, ListYearRangeFilter(lower: 2017, upper: 2024, followsLower: true, followsUpper: true))
        XCTAssertFalse(resolved.isNarrowed(within: bounds))
        XCTAssertFalse(unset.isNarrowed(within: nil))
    }

    func testFollowingRangeGrowsWithANewYear() {
        let range = ListYearRangeFilter(lower: 2017, upper: 2026, followsLower: true, followsUpper: true)
        let resolved = range.resolved(within: 2017...2027)
        XCTAssertEqual(resolved.upper, 2027)
        XCTAssertTrue(resolved.followsUpper)
        XCTAssertFalse(resolved.isNarrowed(within: 2017...2027))
    }

    func testNarrowedRangeIsKept() {
        let narrowed = ListYearRangeFilter.userEdited(lower: 2019, upper: 2022, within: 2017...2026)
        XCTAssertFalse(narrowed.followsLower)
        XCTAssertFalse(narrowed.followsUpper)
        let later = narrowed.resolved(within: 2017...2027)
        XCTAssertEqual(later.lower, 2019)
        XCTAssertEqual(later.upper, 2022)
        XCTAssertTrue(later.isNarrowed(within: 2017...2027))
        XCTAssertTrue(later.contains(year: 2020))
        XCTAssertFalse(later.contains(year: 2027))
    }

    func testUpperKnobOnTheLatestYearFollowsAgain() {
        let edited = ListYearRangeFilter.userEdited(lower: 2020, upper: 2026, within: 2017...2026)
        XCTAssertFalse(edited.followsLower)
        XCTAssertTrue(edited.followsUpper)
        let later = edited.resolved(within: 2017...2027)
        XCTAssertEqual(later.lower, 2020)
        XCTAssertEqual(later.upper, 2027)
    }

    func testClampedEndThatReachesTheEdgeFollowsIt() {
        // Saved 2015-2030 but only 2017-2026 exist: it now covers everything
        // and must not hide a later year.
        let saved = ListYearRangeFilter(lower: 2015, upper: 2030, followsLower: false, followsUpper: false)
        let resolved = saved.resolved(within: 2017...2026)
        XCTAssertEqual(resolved, ListYearRangeFilter(lower: 2017, upper: 2026, followsLower: true, followsUpper: true))
        XCTAssertFalse(resolved.isNarrowed(within: 2017...2026))
    }

    func testSavedNarrowRangeCountsAsFilterWhileLoading() {
        let saved = ListYearRangeFilter(lower: 2019, upper: 2021, followsLower: false, followsUpper: false)
        XCTAssertTrue(saved.isNarrowed(within: nil))
        let following = ListYearRangeFilter(lower: 2019, upper: 2021, followsLower: true, followsUpper: true)
        XCTAssertFalse(following.isNarrowed(within: nil))
    }

    // MARK: Status mapping

    func testLegacyStatusWordsMapToTheFixedOnes() {
        XCTAssertEqual(ApplicationStatusCanonical.canonical("Beviljad"), "Beviljat")
        XCTAssertEqual(ApplicationStatusCanonical.canonical(" beviljat "), "Beviljat")
        XCTAssertEqual(ApplicationStatusCanonical.canonical("Avslagen"), "Avslag")
        XCTAssertEqual(ApplicationStatusCanonical.canonical("Avslag"), "Avslag")
        XCTAssertEqual(ApplicationStatusCanonical.canonical("Ej sökt"), "Ej sökt")
        XCTAssertEqual(ApplicationStatusCanonical.canonical(nil), "Att söka")
        XCTAssertEqual(ApplicationStatusCanonical.canonical("  "), "Att söka")
        XCTAssertEqual(ApplicationStatusCanonical.canonical("Invented status"), "Invented status")
    }

    func testStatusSearchTextHasBothLanguages() {
        let labels = ApplicationStatusCanonical.searchLabels(for: "Beviljad")
        XCTAssertTrue(labels.contains("Beviljat"))
        XCTAssertTrue(labels.contains(AppLanguage.english.localizedStatus("Beviljat")))
        XCTAssertTrue(labels.contains(AppLanguage.swedish.localizedStatus("Beviljat")))
    }

    // MARK: Project filter by id

    func testOldProjectNamesBecomeIdsAndStaleOnesAreDropped() {
        let migrated = ApplicationProjectFilterKeys.migrated(
            ["Invented project", "proj-b", "Gone project", "Written only"],
            knownProjectIDs: ["proj-a", "proj-b"],
            projectIDForName: { $0 == "Invented project" ? "proj-a" : nil },
            writtenNames: ["Written only"]
        )
        XCTAssertEqual(migrated, ["proj-a", "proj-b", "Written only"])
    }

    func testRenamedProjectStillMatchesById() {
        let filter = ApplicationProjectFilterKeys.filter(
            selectedKeys: ["proj-a"],
            knownProjectIDs: ["proj-a", "proj-b"],
            namesByProjectID: ["proj-a": ["New name", ""]]
        )
        XCTAssertTrue(filter.matches(projectID: "proj-a", projectName: "Old name"))
        XCTAssertFalse(filter.matches(projectID: "proj-b", projectName: nil))
        // No id: matched by the project's current name.
        XCTAssertTrue(filter.matches(projectID: nil, projectName: "New name"))
        XCTAssertFalse(filter.matches(projectID: nil, projectName: "Other"))
    }

    func testWrittenProjectNameFilterMatchesText() {
        let filter = ApplicationProjectFilterKeys.filter(
            selectedKeys: ["Written only"],
            knownProjectIDs: ["proj-a"],
            namesByProjectID: [:]
        )
        XCTAssertTrue(filter.matches(projectID: nil, projectName: "Written only"))
        XCTAssertFalse(filter.matches(projectID: "proj-a", projectName: "Written only"))
    }

    func testEmptySelectionMatchesEverything() {
        let filter = ApplicationProjectFilterKeys.filter(selectedKeys: [], knownProjectIDs: ["proj-a"], namesByProjectID: [:])
        XCTAssertTrue(filter.matches(projectID: "proj-a", projectName: nil))
        XCTAssertTrue(filter.matches(projectID: nil, projectName: nil))
    }

    // MARK: Researcher menu and search text

    func testResearcherMatchIgnoresCaseAndAccents() {
        let options = ["René Exempel", "Bo Påhittad"]
        XCTAssertEqual(ListFilterTextMatch.matchingOption(for: "rene exempel", in: options), "René Exempel")
        XCTAssertEqual(ListFilterTextMatch.matchingOption(for: " BO  PÅHITTAD ", in: options), "Bo Påhittad")
        XCTAssertNil(ListFilterTextMatch.matchingOption(for: "Nobody", in: options))
        XCTAssertNil(ListFilterTextMatch.matchingOption(for: "", in: options))
        XCTAssertTrue(ListFilterTextMatch.matches("Åsa", "åSA"))
    }

    func testSearchFindsTextWrittenWithOtherDashes() {
        let haystack = normalizedSearchFilterText("Invented study COVID\u{2013}19 and A\u{2014}B")
        XCTAssertTrue(haystack.contains("covid-19"))
        XCTAssertTrue(SearchFilterQuery(raw: "COVID-19").matches(normalizedHaystack: haystack))
        XCTAssertTrue(SearchFilterQuery(raw: "a\u{2212}b").matches(normalizedHaystack: haystack))
        XCTAssertEqual(normalizedSearchFilterText("Plain-ASCII text"), "plain-ascii text")
    }
}
