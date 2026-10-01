import SwiftUI

/// Which list filters came back from an earlier run of the app. The key is
/// the unscoped filter key ("Applications.Filter.FutureOnly"); a workspace is
/// the part before the first dot ("Applications").
@MainActor
enum RestoredListFilters {
    private static var restoredKeys = Set<String>()

    static func markRestored(key: String) {
        restoredKeys.insert(unscoped(key))
    }

    /// The user changed the filter, so it no longer counts as restored.
    static func markChanged(key: String) {
        restoredKeys.remove(unscoped(key))
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
                    .background(
                        RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                            .fill(AppPalette.statusFill(.pending))
                    )
                    .foregroundStyle(AppPalette.statusOnFill)
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
        let head = language.text(
            "Filtered list: \(displayedCount) of \(totalCount) shown",
            "Filtrerad lista: \(displayedCount) av \(totalCount) visas"
        )
        return ([head] + activeFilters).joined(separator: " · ")
    }
}
