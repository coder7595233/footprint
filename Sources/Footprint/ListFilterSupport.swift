import Foundation

// Round 16 (list filters): small pure rules shared by the list workspaces, kept
// here so they can be tested without a view.

// MARK: - Short descriptions for the filtered-list banner

enum ListFilterLabels {
    /// "Sök: ”text”" for the banner, nil when there is no search text.
    static func search(_ text: String, language: AppLanguage) -> String? {
        guard let trimmed = text.trimmedOrNil else { return nil }
        return language.text("Search: “\(trimmed)”", "Sök: ”\(trimmed)”")
    }

    /// "År 2020–2024" for a narrowed year range.
    static func yearRange(title: String, lower: Double, upper: Double) -> String {
        let low = Int(min(lower, upper))
        let high = Int(max(lower, upper))
        return low == high ? "\(title) \(low)" : "\(title) \(low)–\(high)"
    }

    /// The selected chip titles of one filter group, joined.
    static func chips(_ titles: [String]) -> String? {
        let visible = titles.compactMap(\.trimmedOrNil)
        return visible.isEmpty ? nil : visible.joined(separator: ", ")
    }
}

// MARK: - Selection after a filter change

enum ListSelectionPolicy {
    /// The record to select after the visible rows changed. A selected record
    /// that is still visible stays selected; one that a filter now hides is
    /// replaced by the first visible row. No selection stays no selection.
    static func selectionAfterFilterChange(selected: String?, visibleIDs: [String]) -> String? {
        guard let selected else { return nil }
        return visibleIDs.contains(selected) ? selected : visibleIDs.first
    }
}

// MARK: - Archive selection (Data quality)

enum ArchiveSelectionPolicy {
    /// Only records that are both selected and visible right now can be
    /// deleted; records hidden by the search or category never are.
    static func deletableIDs(selected: Set<String>, visibleIDs: [String]) -> Set<String> {
        selected.intersection(visibleIDs)
    }

    /// True when every visible record is selected (and there is at least one).
    static func allVisibleSelected(selected: Set<String>, visibleIDs: [String]) -> Bool {
        !visibleIDs.isEmpty && Set(visibleIDs).isSubset(of: selected)
    }
}

// MARK: - Year range that follows the available years

/// A year range filter that by default covers every year in the list and
/// widens by itself when records in new years appear ("follows"). Once the
/// user narrows it, the narrowed range is kept. Records without a year are
/// hidden only while the user has narrowed the range.
struct FollowingYearRange: Equatable {
    var lower: Double
    var upper: Double
    var follows: Bool

    /// Old saved filters had no "follows" flag: a range that is unset (0–0) or
    /// covers every available year is treated as following.
    static func legacyFollows(lower: Double, upper: Double, bounds: ClosedRange<Double>?) -> Bool {
        if lower == 0 && upper == 0 { return true }
        guard let bounds else { return false }
        return min(lower, upper) <= bounds.lowerBound && max(lower, upper) >= bounds.upperBound
    }

    /// The range the user picked with the slider: following again when it
    /// covers every available year.
    static func userSet(lower: Double, upper: Double, bounds: ClosedRange<Double>?) -> FollowingYearRange {
        let covers = bounds.map { min(lower, upper) <= $0.lowerBound && max(lower, upper) >= $0.upperBound } ?? false
        return FollowingYearRange(lower: lower, upper: upper, follows: covers)
    }

    /// Adjusts the range to the years now in the list. `bounds` is nil when no
    /// record has a year; then nothing changes (never clamp on empty rows).
    func reconciled(to bounds: ClosedRange<Double>?) -> FollowingYearRange {
        guard let bounds else { return self }
        if follows {
            return FollowingYearRange(lower: bounds.lowerBound, upper: bounds.upperBound, follows: true)
        }
        let low = min(max(min(lower, upper), bounds.lowerBound), bounds.upperBound)
        let high = min(max(max(lower, upper), bounds.lowerBound), bounds.upperBound)
        // A narrowed range that now covers every year is no narrowing at all.
        let coversAll = low <= bounds.lowerBound && high >= bounds.upperBound
        return FollowingYearRange(lower: low, upper: high, follows: coversAll)
    }

    var isNarrowed: Bool { !follows }

    func matches(year: Int?) -> Bool {
        guard !follows else { return true }
        guard let year else { return false }
        return Double(year) >= min(lower, upper) && Double(year) <= max(lower, upper)
    }

    /// For records spanning several years (teaching periods).
    func matches(anyOf years: [Int]) -> Bool {
        guard !follows else { return true }
        return years.contains { matches(year: $0) }
    }

    static func bounds(for years: [Int]) -> ClosedRange<Double>? {
        guard let low = years.min(), let high = years.max() else { return nil }
        return Double(low)...Double(high)
    }
}

// MARK: - Chip groups

/// OR within a group, AND between groups. An empty group does not filter.
func matchesFilterChipGroups(_ groups: [(selected: Set<String>, values: Set<String>)]) -> Bool {
    groups.allSatisfy { group in
        group.selected.isEmpty || !group.selected.isDisjoint(with: group.values)
    }
}

// MARK: - Expert assignments

/// The status chips of the expert-assignment list (user decision round 16).
enum ExpertAssignmentStatusKey: String, CaseIterable, Codable, Sendable {
    /// Accepted and not completed, also when the deadline has passed.
    case ongoing
    /// Accepted, not completed and past the deadline.
    case overdue
    case completed
    /// Has a deadline but was never accepted.
    case declined
    /// No dates yet.
    case noStatus

    func title(language: AppLanguage) -> String {
        switch self {
        case .ongoing:
            return language.text("Ongoing", "Pågående")
        case .overdue:
            return language.text("Overdue", "Försenade")
        case .completed:
            return language.text("Completed", "Klara")
        case .declined:
            return language.text("Declined", "Avböjda")
        case .noStatus:
            return language.text("No status", "Utan status")
        }
    }

    static func keys(for entry: CVReviewEntry, referenceDate: Date = Date(), calendar: Calendar = .current) -> Set<ExpertAssignmentStatusKey> {
        switch entry.workflowStatus(referenceDate: referenceDate, calendar: calendar) {
        case .completed:
            return [.completed]
        case .accepted:
            return [.ongoing]
        case .overdue:
            return [.ongoing, .overdue]
        case nil:
            let hasAnyDate = entry.acceptedDate.trimmedOrNil != nil
                || entry.deadlineDate.trimmedOrNil != nil
                || entry.date.trimmedOrNil != nil
            return hasAnyDate ? [.declined] : [.noStatus]
        }
    }
}

// MARK: - Doctoral candidates

extension DoctoralCandidateRecord {
    /// The dissertation date used by the list: the actual date when there is
    /// one, otherwise the planned date.
    var effectiveDisputationDate: String {
        disputationDate.trimmedOrNil ?? plannedDisputationDate
    }

    /// Finished (dissertation completed) or left the programme early.
    var hasEndedDoctoralStudies: Bool {
        let disputationOutcome = DoctoralMilestoneOutcome(rawValue: plannedDisputationOutcomeRaw ?? "")
        if disputationOutcome != nil { return true }
        return [admissionOutcomeRaw, planningSeminarOutcomeRaw, halftimeOutcomeRaw]
            .contains { DoctoralMilestoneOutcome(rawValue: $0 ?? "") == .endedBefore }
    }

    /// "Aktiva": not completed, not ended early, and no dissertation date in
    /// the past.
    func isActiveDoctoralCandidate(today: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard !hasEndedDoctoralStudies else { return false }
        guard let date = DateParsers.isoDay.date(from: effectiveDisputationDate) else { return true }
        return calendar.startOfDay(for: date) >= calendar.startOfDay(for: today)
    }
}

// MARK: - Teaching programme filter

enum TeachingProgramFilterKeys {
    /// Saved programme names can be in either language (the list shows the
    /// current one). Maps each saved name to the name shown in `language` and
    /// drops names that no longer exist.
    static func remap(
        _ selected: Set<String>,
        programs: [(swedish: String, english: String)],
        language: AppLanguage
    ) -> Set<String> {
        var result = Set<String>()
        for value in selected {
            let key = PublicationDerivation.normalizedName(value)
            guard !key.isEmpty,
                  let program = programs.first(where: {
                      PublicationDerivation.normalizedName($0.swedish) == key
                          || PublicationDerivation.normalizedName($0.english) == key
                  }) else { continue }
            let shown = language == .swedish ? program.swedish : program.english
            if let trimmed = shown.trimmedOrNil {
                result.insert(trimmed)
            }
        }
        return result
    }

    /// True when the programme (by either language name) is among the
    /// selected names, compared without case, accents or punctuation.
    static func matches(_ selected: Set<String>, swedish: String, english: String) -> Bool {
        let keys = Set(selected.map(PublicationDerivation.normalizedName).filter { !$0.isEmpty })
        let sv = PublicationDerivation.normalizedName(swedish)
        let en = PublicationDerivation.normalizedName(english)
        return (!sv.isEmpty && keys.contains(sv)) || (!en.isEmpty && keys.contains(en))
    }
}

// MARK: - Teaching filter storage

enum TeachingFilterStorageMigration {
    /// Copies the old app-wide saved value to the account-scoped key once.
    /// The old value is left in place; a flag stops a second copy (so a
    /// second account does not inherit it).
    static func migrateIfNeeded(
        defaults: UserDefaults,
        legacyKey: String,
        scopedKey: String,
        migrationFlagKey: String
    ) {
        guard !defaults.bool(forKey: migrationFlagKey) else { return }
        defaults.set(true, forKey: migrationFlagKey)
        guard defaults.data(forKey: scopedKey) == nil,
              let legacy = defaults.data(forKey: legacyKey) else { return }
        defaults.set(legacy, forKey: scopedKey)
    }
}

// MARK: - Researchers: incomplete-data filter (set from the app menu)

extension PersonIncompleteDataFilter {
    /// Chip and banner title; nil when no such filter is on.
    func activeFilterTitle(language: AppLanguage) -> String? {
        switch self {
        case .none:
            return nil
        case .any:
            return language.text("Incomplete data", "Ofullständiga data")
        case .orcid:
            return language.text("Missing ORCID", "Saknar ORCID")
        case .email:
            return language.text("Missing email", "Saknar e-post")
        case .organization:
            return language.text("Missing primary organization", "Saknar primär organisation")
        case .country:
            return language.text("Missing primary country", "Saknar primärt land")
        case .title:
            return language.text("Missing title", "Saknar titel")
        }
    }
}

// MARK: - Statistics drilldown

/// Organization first, then name (a valid strict ordering).
func statisticsDrilldownOrganizationThenNameOrder(
    lhsOrganization: String,
    lhsName: String,
    rhsOrganization: String,
    rhsName: String
) -> Bool {
    let organizationOrder = lhsOrganization.localizedStandardCompare(rhsOrganization)
    if organizationOrder != .orderedSame {
        return organizationOrder == .orderedAscending
    }
    return lhsName.localizedStandardCompare(rhsName) == .orderedAscending
}
