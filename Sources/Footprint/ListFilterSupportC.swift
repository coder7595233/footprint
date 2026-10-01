import Foundation

// Round 17 (list filters): more small pure rules shared by the list
// workspaces, kept apart from the views so they can be tested.

// MARK: - Decided once per app launch

/// Keys whose question has already been answered in this run of the app.
/// Workspaces are rebuilt on every data change and tab switch; anything that
/// is only true "at launch" must be decided the first time and never again.
struct LaunchOnceKeys: Sendable {
    private(set) var keys = Set<String>()

    /// True the first time a key is seen, false every time after that.
    mutating func takeFirst(_ key: String) -> Bool {
        keys.insert(key).inserted
    }

    func contains(_ key: String) -> Bool {
        keys.contains(key)
    }
}

/// Round 17: with "keep filters" off in Settings, filters saved by an earlier
/// run are cleared the first time the list is shown, not only when the user
/// leaves it. Decided once per list and app launch, so a list that is shown
/// again later in the same run keeps what the user picked.
@MainActor
enum ListFilterLaunchPolicy {
    private static var handled = LaunchOnceKeys()

    static func shouldClearSavedFilters(for list: ListFilterPersistenceKey, retainsFilters: Bool) -> Bool {
        shouldClear(&handled, list: list.rawValue, retainsFilters: retainsFilters)
    }

    /// The rule itself, separate from the shared state (tests).
    nonisolated static func shouldClear(_ handled: inout LaunchOnceKeys, list: String, retainsFilters: Bool) -> Bool {
        guard handled.takeFirst(list) else { return false }
        return !retainsFilters
    }
}

// MARK: - Records without a year

/// Round 17: one rule for every list with a year filter. Records without a
/// year are shown while the whole year range is selected and hidden as soon
/// as the user narrows it; the banner then says how many were hidden.
enum YearlessRecordRule {
    static func isShown(year: Int?, rangeIsNarrowed: Bool, rangeContains: (Int) -> Bool) -> Bool {
        guard rangeIsNarrowed else { return true }
        guard let year else { return false }
        return rangeContains(year)
    }

    /// How many records the narrowed range hides only because they have no
    /// year (0 while the whole range is selected).
    static func hiddenCount(years: [Int?], rangeIsNarrowed: Bool) -> Int {
        guard rangeIsNarrowed else { return 0 }
        return years.reduce(0) { $0 + ($1 == nil ? 1 : 0) }
    }
}

extension ListYearRangeFilter {
    /// The year test for one record, records without a year included.
    func matches(year: Int?, within bounds: ClosedRange<Double>?) -> Bool {
        YearlessRecordRule.isShown(
            year: year,
            rangeIsNarrowed: isNarrowed(within: bounds),
            rangeContains: { contains(year: $0) }
        )
    }
}

extension ListFilterLabels {
    /// "3 utan årtal dolda" for the banner, nil when none are hidden.
    static func yearlessHidden(count: Int, language: AppLanguage) -> String? {
        guard count > 0 else { return nil }
        return language.text("\(count) without year hidden", "\(count) utan årtal dolda")
    }

    /// Round 17 (Data view): each section's own count, "Dubbletter 1 av 4,
    /// Saknade fält 3 av 12". Sections with nothing in them are left out;
    /// nil when no section has anything.
    static func sectionCounts(_ sections: [(title: String, shown: Int, total: Int)], language: AppLanguage) -> String? {
        let parts = sections
            .filter { $0.total > 0 }
            .map { language.text("\($0.title) \($0.shown) of \($0.total)", "\($0.title) \($0.shown) av \($0.total)") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// The line under "Inga poster matchar filtren": how many are hidden.
    static func hiddenByFilters(count: Int, language: AppLanguage) -> String {
        if count == 1 {
            return language.text("1 record is hidden by the filters.", "1 post döljs av filtren.")
        }
        return language.text("\(count) records are hidden by the filters.", "\(count) poster döljs av filtren.")
    }
}

// MARK: - Grants: statuses outside the six fixed ones

extension ApplicationStatusCanonical {
    /// Round 17: the "Övriga" chip. Any status that is not one of the six
    /// fixed ones is counted here, so it no longer vanishes as soon as a
    /// status chip is on.
    static let otherFilterKey = "Övriga"

    /// The chip a stored status belongs to.
    static func filterKey(for raw: String?) -> String {
        let status = canonical(raw)
        return all.contains(status) ? status : otherFilterKey
    }

    /// No chip on: every status. Otherwise the record's chip must be on.
    static func matchesFilter(selected: Set<String>, raw: String?) -> Bool {
        selected.isEmpty || selected.contains(filterKey(for: raw))
    }

    static func otherCount(in raws: [String]) -> Int {
        raws.reduce(0) { $0 + (filterKey(for: $1) == otherFilterKey ? 1 : 0) }
    }
}

// MARK: - Researchers: organization filter by id

/// Round 17: the researcher list's organization filter is stored by
/// organization id, so it survives a language switch and a renamed
/// organization. An affiliation that is not linked to an organization is
/// stored by its written name.
enum ResearcherOrganizationFilterKeys {
    /// The filter key of one affiliation: its organization id when linked,
    /// otherwise its written name; nil when it has neither.
    static func key(organizationID: String?, writtenName: String) -> String? {
        organizationID?.trimmedOrNil ?? writtenName.trimmedOrNil
    }

    /// Converts stored entries once: keys that still exist are kept, an old
    /// organization name becomes its id, and anything else is dropped (it
    /// would otherwise hide every researcher without showing why).
    static func migrated(
        _ stored: Set<String>,
        knownKeys: Set<String>,
        organizationIDForName: (String) -> String?
    ) -> Set<String> {
        Set(stored.compactMap { entry -> String? in
            if knownKeys.contains(entry) {
                return entry
            }
            if let id = organizationIDForName(entry), knownKeys.contains(id) {
                return id
            }
            return nil
        })
    }
}

// MARK: - Publications: chips that stand for several statuses

enum PublicationStatusChipValues {
    /// "Publicerad/accepterad" covers both statuses.
    static let publishedAccepted: Set<String> = [
        PublicationStatus.published.rawValue,
        PublicationStatus.accepted.rawValue,
    ]
    static let submitted: Set<String> = [PublicationStatus.submitted.rawValue]

    /// Round 17: a chip looks selected only when every status it stands for
    /// is selected.
    static func isChipSelected(values: Set<String>, selected: Set<String>) -> Bool {
        !values.isEmpty && values.isSubset(of: selected)
    }

    /// The statuses a preset from the overview selects: always a chip's full
    /// value set, so the chip and the list agree.
    static func statuses(for preset: PublicationListPreset) -> Set<String> {
        switch preset {
        case .all:
            return []
        case .originalPublished, .originalPublishedIndependentLeadAfterPhD:
            return publishedAccepted
        case .originalSubmitted, .originalSubmittedIndependentLeadAfterPhD:
            return submitted
        }
    }
}
