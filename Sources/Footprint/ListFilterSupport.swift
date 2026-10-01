import Foundation

/// Round 16: a year range filter for a list. By default it covers every year
/// present and grows by itself when new years appear (for example a call that
/// closes next year). When the user narrows one end, that end is kept as
/// chosen; dragging it back to the outermost year makes it follow again.
struct ListYearRangeFilter: Equatable, Sendable {
    var lower: Double
    var upper: Double
    /// The lower end sits on the earliest year and moves with it.
    var followsLower: Bool
    /// The upper end sits on the latest year and moves with it.
    var followsUpper: Bool

    /// The years present, or nil while the list has no rows yet.
    static func bounds(forYears years: [Int]) -> ClosedRange<Double>? {
        guard let first = years.min(), let last = years.max() else { return nil }
        return Double(first)...Double(last)
    }

    static func full(_ bounds: ClosedRange<Double>) -> ListYearRangeFilter {
        ListYearRangeFilter(lower: bounds.lowerBound, upper: bounds.upperBound, followsLower: true, followsUpper: true)
    }

    /// The range after the user moved a knob: an end placed on the outermost
    /// year follows new years again.
    static func userEdited(lower: Double, upper: Double, within bounds: ClosedRange<Double>) -> ListYearRangeFilter {
        let low = min(lower, upper)
        let high = max(lower, upper)
        return ListYearRangeFilter(
            lower: low,
            upper: high,
            followsLower: low <= bounds.lowerBound,
            followsUpper: high >= bounds.upperBound
        )
    }

    /// The stored range fitted to the years present. Without rows (still
    /// loading) nothing is changed, so a saved range is never collapsed to the
    /// current year.
    func resolved(within bounds: ClosedRange<Double>?) -> ListYearRangeFilter {
        guard let bounds else { return self }
        if lower == 0 && upper == 0 {
            return .full(bounds)
        }
        var result = self
        result.lower = followsLower ? bounds.lowerBound : Self.clamp(min(lower, upper), to: bounds)
        result.upper = followsUpper ? bounds.upperBound : Self.clamp(max(lower, upper), to: bounds)
        if result.lower > result.upper {
            result.lower = result.upper
        }
        // An end that ends up on the outermost year must also follow it;
        // otherwise a range that looks complete would hide new years.
        result.followsLower = result.lower <= bounds.lowerBound
        result.followsUpper = result.upper >= bounds.upperBound
        return result
    }

    /// True when the range hides some of the years present.
    func isNarrowed(within bounds: ClosedRange<Double>?) -> Bool {
        guard let bounds else {
            return !(lower == 0 && upper == 0) && !(followsLower && followsUpper)
        }
        if lower == 0 && upper == 0 { return false }
        let effective = resolved(within: bounds)
        return effective.lower > bounds.lowerBound || effective.upper < bounds.upperBound
    }

    func contains(year: Int) -> Bool {
        let value = Double(year)
        return value >= min(lower, upper) && value <= max(lower, upper)
    }

    private static func clamp(_ value: Double, to bounds: ClosedRange<Double>) -> Double {
        min(max(value, bounds.lowerBound), bounds.upperBound)
    }
}

/// Round 16: the one place that turns an application's stored status into the
/// app's fixed status word. Filter chips, row colours and sorting all use it,
/// so older spellings ("Beviljad", "Avslagen") land in the right group.
enum ApplicationStatusCanonical {
    static let toApply = "Att söka"
    static let awaitingResponse = "Väntar svar"
    static let granted = "Beviljat"
    static let declined = "Avslag"
    static let withdrawn = "Tillbakadragen"
    static let notApplied = "Ej sökt"

    static let all = [toApply, awaitingResponse, granted, withdrawn, declined, notApplied]

    static func canonical(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return toApply }
        // Plain lowercasing (no locale-dependent accent folding), with the
        // spellings written out.
        switch collapsingWhitespaceRuns(trimmed.lowercased()) {
        case "att söka", "att soka", "to apply":
            return toApply
        case "väntar svar", "vantar svar", "väntar beslut", "awaiting response", "awaiting decision", "pending":
            return awaitingResponse
        case "beviljat", "beviljad", "beviljade", "awarded", "granted":
            return granted
        case "avslag", "avslagen", "avslaget", "avslagna", "declined", "rejected":
            return declined
        case "tillbakadragen", "tillbakadraget", "tillbakadragna", "withdrawn":
            return withdrawn
        case "ej sökt", "ej sokt", "ej sökta", "not applied":
            return notApplied
        default:
            return trimmed
        }
    }

    /// Both languages' names for a status, so a search for "Awarded" or
    /// "Beviljad" finds the granted applications whatever language is shown.
    static func searchLabels(for raw: String?) -> [String] {
        let status = canonical(raw)
        var labels = [status]
        for language in AppLanguage.allCases {
            let label = language.localizedStatus(status)
            if !labels.contains(label) {
                labels.append(label)
            }
        }
        return labels
    }
}

/// Round 16: the grants list's project filter is stored by project id, so a
/// renamed project keeps working. A written project name without a project
/// record is stored as its text.
enum ApplicationProjectFilterKeys {
    /// Converts stored entries: ids are kept, old project names become ids,
    /// and entries that no longer match anything are dropped (they would
    /// otherwise hide every application without showing why).
    static func migrated(
        _ stored: Set<String>,
        knownProjectIDs: Set<String>,
        projectIDForName: (String) -> String?,
        writtenNames: Set<String>
    ) -> Set<String> {
        Set(stored.compactMap { entry -> String? in
            if knownProjectIDs.contains(entry) {
                return entry
            }
            if let id = projectIDForName(entry) {
                return id
            }
            return writtenNames.contains(entry) ? entry : nil
        })
    }

    /// The filter for the stored keys. `namesByProjectID` gives each selected
    /// project's names, used for applications that only have a written name.
    static func filter(
        selectedKeys: Set<String>,
        knownProjectIDs: Set<String>,
        namesByProjectID: [String: [String]]
    ) -> ApplicationProjectFilter {
        let selectedIDs = selectedKeys.intersection(knownProjectIDs)
        var names = selectedKeys.subtracting(selectedIDs)
        for id in selectedIDs {
            names.formUnion((namesByProjectID[id] ?? []).filter { !$0.isEmpty })
        }
        if names.isEmpty && !selectedKeys.isEmpty {
            // Keeps the filter switched on even for a project without a name.
            names = selectedKeys
        }
        return ApplicationProjectFilter(
            selectedNames: names,
            selectedProjectIDs: selectedIDs,
            knownProjectIDs: knownProjectIDs
        )
    }
}

/// Round 16: matching for the researcher menu in Projects; like the search,
/// it ignores case, accents and extra spaces.
enum ListFilterTextMatch {
    static func matches(_ value: String, _ other: String) -> Bool {
        normalizedSearchFilterText(value) == normalizedSearchFilterText(other)
    }

    /// The option that matches a stored value, or nil when none does.
    static func matchingOption(for stored: String, in options: [String]) -> String? {
        let key = normalizedSearchFilterText(stored)
        guard !key.isEmpty else { return nil }
        return options.first { normalizedSearchFilterText($0) == key }
    }
}
