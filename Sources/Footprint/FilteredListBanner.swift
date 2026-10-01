import SwiftUI

/// Which list filters came back from an earlier run of the app. The key is
/// the unscoped filter key ("Applications.Filter.FutureOnly"); a workspace is
/// the part before the first dot ("Applications").
///
/// Round 17: whether a key came back is decided once per key and app launch.
/// Workspaces are rebuilt on every data change and tab switch, and a filter
/// the user just chose must not be called "kept from last time" when the
/// workspace is rebuilt.
@MainActor
enum RestoredListFilters {
    private static var restoredKeys = Set<String>()
    private static var evaluatedKeys = LaunchOnceKeys()

    /// Records, the first time a key is seen in this run, whether its saved
    /// value hides something. Later calls for the same key do nothing.
    static func evaluateAtLaunch(key: String, isRestored: Bool) {
        let key = unscoped(key)
        guard evaluatedKeys.takeFirst(key) else { return }
        if isRestored {
            restoredKeys.insert(key)
        }
    }

    /// A saved filter came back at launch (only the first evaluation counts).
    static func markRestored(key: String) {
        evaluateAtLaunch(key: key, isRestored: true)
    }

    /// The user changed the filter, so it no longer counts as restored, and
    /// never will again in this run.
    static func markChanged(key: String) {
        let key = unscoped(key)
        _ = evaluatedKeys.takeFirst(key)
        restoredKeys.remove(key)
    }

    static func wasRestored(key: String) -> Bool {
        restoredKeys.contains(unscoped(key))
    }

    static func wasRestored(workspace: String) -> Bool {
        restoredKeys.contains { $0 == workspace || $0.hasPrefix(workspace + ".") }
    }

    static func forget(workspace: String) {
        restoredKeys = restoredKeys.filter { !($0 == workspace || $0.hasPrefix(workspace + ".")) }
    }

    private static func unscoped(_ key: String) -> String {
        let prefix = AppRuntime.defaultsPrefix + "."
        return key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : key
    }
}

/// The line shown above every list while a filter is on (user decision
/// 2026-10-01: filters are kept, but a filtered list always says so):
/// "Filtrerad lista: 12 av 116 visas · År 2020–2024 · Rensa filter".
struct AppFilteredListBanner: View {
    let displayedCount: Int
    let totalCount: Int
    /// Short descriptions of the active filters, in the user's language.
    var activeFilters: [String] = []
    /// Shows "Sparat från förra gången" when the filters came back at start.
    var restoredFromLastSession = false
    /// Round 17: replaces "x av y visas" where one total would mix different
    /// things (the Data view's sections), e.g. "Dubbletter 1 av 4".
    var countSummary: String? = nil
    let language: AppLanguage
    let clearAction: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(.secondary)
            Text(summary)
                .appTypography(.secondary)
                .foregroundStyle(AppPalette.appText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if restoredFromLastSession {
                Text(language.text("Kept from last time", "Sparat från förra gången"))
                    .appTypography(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    // Round 17: a quiet grey note, not a warning colour.
                    .background(
                        RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                            .fill(AppPalette.statusFill(.inactive))
                    )
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(language.text("Clear filters", "Rensa filter"), action: clearAction)
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                .fill(AppPalette.appText.opacity(0.06))
        )
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        let head: String
        if let countSummary {
            head = language.text("Filtered: \(countSummary)", "Filtrerat: \(countSummary)")
        } else {
            head = language.text(
                "Filtered list: \(displayedCount) of \(totalCount) shown",
                "Filtrerad lista: \(displayedCount) av \(totalCount) visas"
            )
        }
        return ([head] + activeFilters).joined(separator: " · ")
    }
}

/// Round 17: the same line for a view without a record count (the calendar):
/// "Aktiva filter: … · Rensa filter".
struct AppActiveFiltersBanner: View {
    let summary: String
    let language: AppLanguage
    let clearAction: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(.secondary)
            Text(summary)
                .appTypography(.secondary)
                .foregroundStyle(AppPalette.appText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(language.text("Clear filters", "Rensa filter"), action: clearAction)
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                .fill(AppPalette.appText.opacity(0.06))
        )
        .accessibilityElement(children: .combine)
    }
}
