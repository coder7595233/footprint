import XCTest
@testable import Footprint

/// Round 17: list filters ("kept from last time" decided once, one rule for
/// records without a year, the "Övriga" status chip, the researcher
/// organization filter by id, publication presets). All names and values
/// below are made up.
final class Round17FiltersTests: XCTestCase {

    // MARK: "Sparat från förra gången" is decided once per launch

    func testLaunchOnceKeysAnswerOnlyTheFirstTime() {
        var keys = LaunchOnceKeys()
        XCTAssertTrue(keys.takeFirst("Invented.Filter.Search"))
        XCTAssertFalse(keys.takeFirst("Invented.Filter.Search"))
        XCTAssertTrue(keys.takeFirst("Invented.Filter.Other"))
        XCTAssertTrue(keys.contains("Invented.Filter.Search"))
    }

    @MainActor
    func testSavedFilterIsRestoredOnlyAtFirstRead() throws {
        let workspace = "Round17Restored\(UUID().uuidString.prefix(8))"
        let key = "\(workspace).Filter.Search"
        let scopedKey = AppRuntime.scopedDefaultsKey(key)
        defer { UserDefaults.standard.removeObject(forKey: scopedKey) }
        UserDefaults.standard.set(try JSONEncoder().encode("saved earlier"), forKey: scopedKey)

        _ = WorkspaceFilterState(wrappedValue: "", key)
        XCTAssertTrue(RestoredListFilters.wasRestored(workspace: workspace))

        // The user picks a new value; the workspace is then rebuilt (a data
        // change or tab switch) and reads the stored value again.
        let state = WorkspaceFilterState(wrappedValue: "", key)
        state.wrappedValue = "chosen now"
        XCTAssertFalse(RestoredListFilters.wasRestored(workspace: workspace))
        _ = WorkspaceFilterState(wrappedValue: "", key)
        XCTAssertFalse(RestoredListFilters.wasRestored(workspace: workspace), "a value chosen in this run is never 'kept from last time'")
    }

    @MainActor
    func testFirstReadOfADefaultValueIsNotRestoredLater() {
        let workspace = "Round17Default\(UUID().uuidString.prefix(8))"
        let key = "\(workspace).Filter.Flag"
        let scopedKey = AppRuntime.scopedDefaultsKey(key)
        defer { UserDefaults.standard.removeObject(forKey: scopedKey) }

        _ = WorkspaceFilterState(wrappedValue: false, key)
        XCTAssertFalse(RestoredListFilters.wasRestored(workspace: workspace))
        // Another view stored a value meanwhile; a rebuild must not call it
        // restored, since it was evaluated already.
        UserDefaults.standard.set(try? JSONEncoder().encode(true), forKey: scopedKey)
        _ = WorkspaceFilterState(wrappedValue: false, key)
        XCTAssertFalse(RestoredListFilters.wasRestored(workspace: workspace))
    }

    @MainActor
    func testValuesThatAreNoFilterOnTheirOwnAreNotTracked() {
        let workspace = "Round17Years\(UUID().uuidString.prefix(8))"
        let key = "\(workspace).Filter.MinimumYear"
        let scopedKey = AppRuntime.scopedDefaultsKey(key)
        defer { UserDefaults.standard.removeObject(forKey: scopedKey) }
        UserDefaults.standard.set(try? JSONEncoder().encode(2019.0), forKey: scopedKey)

        _ = WorkspaceFilterState(wrappedValue: 0.0, key, tracksRestored: false)
        XCTAssertFalse(RestoredListFilters.wasRestored(workspace: workspace))

        // The workspace decides against the data, once.
        RestoredListFilters.evaluateAtLaunch(key: "\(workspace).Filter.YearRange", isRestored: false)
        RestoredListFilters.evaluateAtLaunch(key: "\(workspace).Filter.YearRange", isRestored: true)
        XCTAssertFalse(RestoredListFilters.wasRestored(workspace: workspace))
    }

    @MainActor
    func testMarkRestoredCountsOnlyAtTheFirstEvaluation() {
        let workspace = "Round17Marked\(UUID().uuidString.prefix(8))"
        RestoredListFilters.markRestored(key: "\(workspace).Filter.Assignments")
        XCTAssertTrue(RestoredListFilters.wasRestored(workspace: workspace))
        RestoredListFilters.markChanged(key: "\(workspace).Filter.Assignments")
        RestoredListFilters.markRestored(key: "\(workspace).Filter.Assignments")
        XCTAssertFalse(RestoredListFilters.wasRestored(workspace: workspace))
    }

    // MARK: "Keep filters" off: cleared once at launch

    func testLaunchClearingHappensOncePerList() {
        var handled = LaunchOnceKeys()
        XCTAssertTrue(ListFilterLaunchPolicy.shouldClear(&handled, list: "journals", retainsFilters: false))
        XCTAssertFalse(ListFilterLaunchPolicy.shouldClear(&handled, list: "journals", retainsFilters: false))
        XCTAssertFalse(ListFilterLaunchPolicy.shouldClear(&handled, list: "teaching", retainsFilters: true))
        XCTAssertFalse(ListFilterLaunchPolicy.shouldClear(&handled, list: "teaching", retainsFilters: false))
    }

    // MARK: Records without a year

    func testYearlessRecordsShownOnlyWhileTheWholeRangeIsSelected() {
        XCTAssertTrue(YearlessRecordRule.isShown(year: nil, rangeIsNarrowed: false, rangeContains: { _ in false }))
        XCTAssertFalse(YearlessRecordRule.isShown(year: nil, rangeIsNarrowed: true, rangeContains: { _ in true }))
        XCTAssertTrue(YearlessRecordRule.isShown(year: 2021, rangeIsNarrowed: true, rangeContains: { $0 == 2021 }))
        XCTAssertFalse(YearlessRecordRule.isShown(year: 2018, rangeIsNarrowed: true, rangeContains: { $0 == 2021 }))
    }

    func testYearRangeFilterUsesTheSameRule() {
        let bounds: ClosedRange<Double> = 2016...2026
        let all = ListYearRangeFilter.full(bounds)
        XCTAssertTrue(all.matches(year: nil, within: bounds))
        XCTAssertTrue(all.matches(year: 2016, within: bounds))

        let narrowed = ListYearRangeFilter.userEdited(lower: 2020, upper: 2022, within: bounds)
        XCTAssertFalse(narrowed.matches(year: nil, within: bounds))
        XCTAssertTrue(narrowed.matches(year: 2021, within: bounds))
        XCTAssertFalse(narrowed.matches(year: 2024, within: bounds))

        // The same rule as the following range used by teaching and
        // doctoral candidates.
        XCTAssertEqual(
            FollowingYearRange(lower: 2020, upper: 2022, follows: false).matches(year: nil),
            narrowed.matches(year: nil, within: bounds)
        )
    }

    func testYearlessHiddenCountAndLabel() {
        let years: [Int?] = [2020, nil, 2021, nil, nil]
        XCTAssertEqual(YearlessRecordRule.hiddenCount(years: years, rangeIsNarrowed: true), 3)
        XCTAssertEqual(YearlessRecordRule.hiddenCount(years: years, rangeIsNarrowed: false), 0)
        XCTAssertEqual(ListFilterLabels.yearlessHidden(count: 3, language: .swedish), "3 utan årtal dolda")
        XCTAssertEqual(ListFilterLabels.yearlessHidden(count: 3, language: .english), "3 without year hidden")
        XCTAssertNil(ListFilterLabels.yearlessHidden(count: 0, language: .swedish))
    }

    // MARK: Grants: "Övriga"

    func testUnknownStatusesFallInTheOtherBucket() {
        XCTAssertEqual(ApplicationStatusCanonical.filterKey(for: "Beviljad"), "Beviljat")
        XCTAssertEqual(ApplicationStatusCanonical.filterKey(for: nil), "Att söka")
        XCTAssertEqual(ApplicationStatusCanonical.filterKey(for: "Invented status"), ApplicationStatusCanonical.otherFilterKey)

        let ongoing: Set<String> = ["Att söka", "Väntar svar"]
        XCTAssertFalse(ApplicationStatusCanonical.matchesFilter(selected: ongoing, raw: "Invented status"))
        XCTAssertTrue(ApplicationStatusCanonical.matchesFilter(selected: [ApplicationStatusCanonical.otherFilterKey], raw: "Invented status"))
        XCTAssertFalse(ApplicationStatusCanonical.matchesFilter(selected: [ApplicationStatusCanonical.otherFilterKey], raw: "Avslagen"))
        XCTAssertTrue(ApplicationStatusCanonical.matchesFilter(selected: [], raw: "Invented status"))

        XCTAssertEqual(ApplicationStatusCanonical.otherCount(in: ["Beviljat", "Invented status", "Another made-up word", "Avslag"]), 2)
        XCTAssertEqual(ApplicationStatusCanonical.otherCount(in: ["Beviljat", "Ej sökt"]), 0)
    }

    // MARK: Researchers: organization filter by id

    func testOrganizationFilterKeyPrefersTheLinkedOrganization() {
        XCTAssertEqual(ResearcherOrganizationFilterKeys.key(organizationID: "org-1", writtenName: "Invented University"), "org-1")
        XCTAssertEqual(ResearcherOrganizationFilterKeys.key(organizationID: nil, writtenName: " Invented Clinic "), "Invented Clinic")
        XCTAssertEqual(ResearcherOrganizationFilterKeys.key(organizationID: "  ", writtenName: "Invented Clinic"), "Invented Clinic")
        XCTAssertNil(ResearcherOrganizationFilterKeys.key(organizationID: nil, writtenName: ""))
    }

    func testOldOrganizationNamesBecomeIdsAndStaleOnesAreDropped() {
        let migrated = ResearcherOrganizationFilterKeys.migrated(
            ["Invented University", "org-2", "Invented Clinic", "Closed Institute"],
            knownKeys: ["org-1", "org-2", "Invented Clinic"],
            organizationIDForName: { name in
                switch name {
                case "Invented University": return "org-1"
                case "Closed Institute": return "org-9"
                default: return nil
                }
            }
        )
        // org-9 is not used by any researcher any more, so it is dropped.
        XCTAssertEqual(migrated, ["org-1", "org-2", "Invented Clinic"])
    }

    // MARK: Publications: chips and presets

    func testPublishedChipIsSelectedOnlyWhenBothStatusesAre() {
        let chip = PublicationStatusChipValues.publishedAccepted
        XCTAssertFalse(PublicationStatusChipValues.isChipSelected(values: chip, selected: [PublicationStatus.published.rawValue]))
        XCTAssertTrue(PublicationStatusChipValues.isChipSelected(values: chip, selected: chip))
        XCTAssertTrue(PublicationStatusChipValues.isChipSelected(values: chip, selected: chip.union([PublicationStatus.rejected.rawValue])))
        XCTAssertFalse(PublicationStatusChipValues.isChipSelected(values: [], selected: chip))
    }

    func testPresetsSelectTheChipsFullValueSet() {
        XCTAssertEqual(PublicationStatusChipValues.statuses(for: .originalPublished), PublicationStatusChipValues.publishedAccepted)
        XCTAssertEqual(PublicationStatusChipValues.statuses(for: .originalPublishedIndependentLeadAfterPhD), PublicationStatusChipValues.publishedAccepted)
        XCTAssertEqual(PublicationStatusChipValues.statuses(for: .originalSubmitted), [PublicationStatus.submitted.rawValue])
        XCTAssertEqual(PublicationStatusChipValues.statuses(for: .all), [])
        XCTAssertTrue(PublicationStatusChipValues.isChipSelected(
            values: PublicationStatusChipValues.publishedAccepted,
            selected: PublicationStatusChipValues.statuses(for: .originalPublished)
        ))
    }

    // MARK: Wording

    func testSearchLabelIsTheSameEverywhere() {
        XCTAssertEqual(ListFilterLabels.search("  invented ", language: .swedish), "Sökning ”invented”")
        XCTAssertEqual(ListFilterLabels.search("invented", language: .english), "Search “invented”")
        XCTAssertNil(ListFilterLabels.search("   ", language: .swedish))
    }

    func testHiddenByFiltersLine() {
        XCTAssertEqual(ListFilterLabels.hiddenByFilters(count: 1, language: .swedish), "1 post döljs av filtren.")
        XCTAssertEqual(ListFilterLabels.hiddenByFilters(count: 12, language: .swedish), "12 poster döljs av filtren.")
        XCTAssertEqual(ListFilterLabels.hiddenByFilters(count: 12, language: .english), "12 records are hidden by the filters.")
    }

    func testDataViewBannerCountsEachSectionByItself() {
        let text = ListFilterLabels.sectionCounts(
            [
                (title: "Saknade fält", shown: 3, total: 12),
                (title: "Dubbletter", shown: 0, total: 0),
                (title: "Arkiv", shown: 1, total: 4),
            ],
            language: .swedish
        )
        XCTAssertEqual(text, "Saknade fält 3 av 12, Arkiv 1 av 4")
        XCTAssertNil(ListFilterLabels.sectionCounts([(title: "Dubbletter", shown: 0, total: 0)], language: .swedish))
    }
}
