import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum DataWorkspaceSection: String, CaseIterable, Identifiable {
    case quality
    case missing
    case duplicates
    case integrity
    case structure
    case translations
    case revisions
    case archive

    var id: String { rawValue }
}

// One single view: every area is a collapsible section with a summary
// in its header. DataWorkspaceSection remains the external navigation
// contract (menus/notifications) and maps onto these.
private enum DataQualitySectionKey: String, Codable, CaseIterable, Identifiable {
    case structure
    case integrity
    case missingFields
    case translations
    case nameLinks
    case doctoralActivityLinks
    case duplicates
    case archive
    case revisions

    var id: String { rawValue }

    init?(section: DataWorkspaceSection) {
        switch section {
        case .quality:
            return nil
        case .missing:
            self = .missingFields
        case .duplicates:
            self = .duplicates
        case .integrity:
            self = .integrity
        case .structure:
            self = .structure
        case .translations:
            self = .translations
        case .archive:
            self = .archive
        case .revisions:
            self = .revisions
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .structure:
            return language.text("Overall structure", "Övergripande struktur")
        case .integrity:
            return language.text("Integrity", "Integritet")
        case .missingFields:
            return language.text("Missing fields", "Saknade fält")
        case .translations:
            return language.text("Missing translations", "Saknade översättningar")
        case .nameLinks:
            return language.text("Names to link", "Namn att koppla")
        case .doctoralActivityLinks:
            return language.text("Activities to link to a doctoral candidate", "Aktiviteter att koppla till doktorand")
        case .duplicates:
            return language.text("Possible duplicates", "Möjliga dubletter")
        case .archive:
            return language.text("Archive", "Arkiv")
        case .revisions:
            return language.text("History", "Historik")
        }
    }

    var systemImage: String {
        switch self {
        case .structure:
            return "externaldrive.badge.checkmark"
        case .integrity:
            return "link.badge.plus"
        case .missingFields:
            return "text.badge.xmark"
        case .translations:
            return "character.book.closed"
        case .nameLinks:
            return "person.crop.circle.badge.questionmark"
        case .doctoralActivityLinks:
            return "calendar.badge.plus"
        case .duplicates:
            return "square.on.square"
        case .archive:
            return "archivebox"
        case .revisions:
            return "clock.arrow.circlepath"
        }
    }
}

private enum DataQualityCategory: String, Codable, CaseIterable, Identifiable {
    case all
    case applications
    case projects
    case organizations
    case researchers
    case journals
    case publications
    case teaching

    var id: String { rawValue }

    static var completenessCases: [DataQualityCategory] {
        [.applications, .projects, .organizations, .researchers, .journals, .publications, .teaching]
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .all:
            return language.text("All categories", "Alla kategorier")
        case .applications:
            return language.text("Applications", "Ansökningar")
        case .projects:
            return language.text("Projects", "Projekt")
        case .organizations:
            return language.text("Organizations", "Organisationer")
        case .researchers:
            return language.text("Researchers", "Forskare")
        case .journals:
            return language.text("Journals", "Tidskrifter")
        case .publications:
            return language.text("Publications", "Publikationer")
        case .teaching:
            return language.text("Teaching", "Undervisning")
        }
    }

}

private enum DataQualityIssueFilter: String, Codable, CaseIterable, Identifiable {
    case missingFields
    case duplicates
    case integrity
    case structure
    case archive
    case revisions

    var id: String { rawValue }

    /// The Data view section that shows this list.
    var sectionKey: DataQualitySectionKey {
        switch self {
        case .missingFields: return .missingFields
        case .duplicates: return .duplicates
        case .integrity: return .integrity
        case .structure: return .structure
        case .archive: return .archive
        case .revisions: return .revisions
        }
    }

    static let loadOrder: [DataQualityIssueFilter] = [
        .missingFields,
        .duplicates,
        .integrity,
        .structure,
        .archive,
        .revisions
    ]

    static let defaultSelection: Set<DataQualityIssueFilter> = [
        .missingFields,
        .duplicates,
        .integrity,
        .structure
    ]

    static func selection(for section: DataWorkspaceSection) -> Set<DataQualityIssueFilter> {
        switch section {
        case .quality:
            return defaultSelection
        case .missing:
            return [.missingFields]
        case .duplicates:
            return [.duplicates]
        case .integrity:
            return [.integrity]
        case .structure:
            return [.structure]
        case .translations:
            return []
        case .revisions:
            return [.revisions]
        case .archive:
            return [.archive]
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .missingFields:
            return language.text("Missing fields", "Saknade fält")
        case .duplicates:
            return language.text("Duplicates", "Dubletter")
        case .integrity:
            return language.text("Integrity", "Integritet")
        case .structure:
            return language.text("Structure", "Struktur")
        case .archive:
            return language.text("Archive", "Arkiv")
        case .revisions:
            return language.text("Recent changes", "Senaste ändringar")
        }
    }

    var systemImage: String {
        switch self {
        case .missingFields:
            return "text.badge.xmark"
        case .duplicates:
            return "square.on.square"
        case .integrity:
            return "link.badge.plus"
        case .structure:
            return "externaldrive.badge.checkmark"
        case .archive:
            return "archivebox"
        case .revisions:
            return "clock.arrow.circlepath"
        }
    }
}

private enum DataQualityUnifiedIssue: Identifiable {
    case missing(GrantDataStore.MissingFieldIssue)
    case duplicate(GrantDataStore.DuplicateIssue)
    case integrity(GrantDataStore.IntegrityIssue)
    case structure(GrantDataStore.DataStructureDiagnosticItem)
    case archive(GrantDataStore.ArchivedRecordSummary)
    case revision(GrantDataStore.RecordRevisionEntry)

    var id: String {
        switch self {
        case .missing(let issue):
            return "missing-\(issue.id)"
        case .duplicate(let issue):
            return "duplicate-\(issue.id)"
        case .integrity(let issue):
            return "integrity-\(issue.id)"
        case .structure(let item):
            return "structure-\(item.id)"
        case .archive(let item):
            return "archive-\(item.id)"
        case .revision(let entry):
            return "revision-\(entry.id)"
        }
    }

    var filter: DataQualityIssueFilter {
        switch self {
        case .missing:
            return .missingFields
        case .duplicate:
            return .duplicates
        case .integrity:
            return .integrity
        case .structure:
            return .structure
        case .archive:
            return .archive
        case .revision:
            return .revisions
        }
    }
}

private struct DataCompletenessSummaryItem: Identifiable {
    let category: DataQualityCategory
    let title: String
    let totalRecords: Int
    let flaggedRecords: Int

    var id: String { category.rawValue }
    var completeRecords: Int { max(0, totalRecords - flaggedRecords) }
    var completionFraction: Double {
        guard totalRecords > 0 else { return 1 }
        return Double(completeRecords) / Double(totalRecords)
    }
}

private enum DataQualityStatusTone {
    case ok
    case warning
    case critical
    case info
}

private struct DataQualityOverviewSummaryItem: Identifiable {
    let id: String
    let title: String
    let count: Int
    let tone: DataQualityStatusTone
}

private struct DataQualityStatusIcon: View {
    let tone: DataQualityStatusTone
    var size: CGFloat = 14

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size + 4, height: size + 4)
    }

    private var symbol: String {
        switch tone {
        case .ok:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.circle.fill"
        case .critical:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle"
        }
    }

    private var color: Color {
        switch tone {
        // Round 16: readable text colours for symbols on the background.
        case .ok:
            return AppPalette.statusText(.done)
        case .warning:
            return AppPalette.statusText(.warning)
        case .critical:
            return AppPalette.statusText(.negative)
        case .info:
            return AppPalette.linkAction
        }
    }
}

struct DataMaintenanceWorkspaceView: View {
    @ObservedObject var store: GrantDataStore
    @Binding var section: DataWorkspaceSection
    let dismiss: () -> Void
    let isActive: Bool
    @WorkspaceFilterState("DataQuality.Filter.QueryDraft") private var queryDraft = ""
    @WorkspaceFilterState("DataQuality.Filter.Query") private var query = ""
    @WorkspaceFilterState("DataQuality.Filter.Category") private var category: DataQualityCategory = .all
    // Round 17: the stored choice is respected (default: every list, so each
    // section header has a live count).
    @WorkspaceFilterState("DataQuality.Filter.IssueTypes") private var selectedIssueFilters = Set(DataQualityIssueFilter.allCases)
    @WorkspaceFilterState("DataQuality.Filter.ExpandedArchive") private var expandedArchivedIDs = Set<String>()
    @State private var selectedArchivedIDs = Set<String>()
    @WorkspaceFilterState("DataQuality.ExpandedSections") private var expandedSectionKeys = Set<DataQualitySectionKey>()
    @State private var cachedMissingIssues: [GrantDataStore.MissingFieldIssue] = []
    @State private var cachedDuplicateIssues: [GrantDataStore.DuplicateIssue] = []
    @State private var cachedIntegrityIssues: [GrantDataStore.IntegrityIssue] = []
    @State private var cachedStructureDiagnostics: [GrantDataStore.DataStructureDiagnosticItem] = []
    @State private var cachedArchivedItems: [GrantDataStore.ArchivedRecordSummary] = []
    @State private var cachedRevisionHistory: [GrantDataStore.RecordRevisionEntry] = []
    @State private var needsDiagnosticsRefreshWhenActive = false
    @State private var showHiddenWarnings = false
    @State private var showsShowAllHiddenConfirmation = false
    @State private var pendingDuplicateMergeIssue: GrantDataStore.DuplicateIssue?
    @State private var loadedIssueFilters = Set<DataQualityIssueFilter>()
    /// Lists in collapsed sections that still show their count from before
    /// the latest change; they are reloaded when their section is opened.
    @State private var staleIssueFilters = Set<DataQualityIssueFilter>()
    @State private var loadingIssueFilters = Set<DataQualityIssueFilter>()
    @State private var diagnosticsRefreshGeneration = 0
    @State private var diagnosticLoadTasks: [DataQualityIssueFilter: DispatchWorkItem] = [:]
    @State private var pendingQueryUpdateTask: DispatchWorkItem?

    private var summaryItems: [DataQualityOverviewSummaryItem] {
        [
            .init(
                id: "missing-records",
                title: store.language.text("Records with missing fields", "Poster med saknade fält"),
                count: missingIssues.count,
                tone: missingIssues.isEmpty ? .ok : .warning
            ),
            .init(
                id: "missing-fields",
                title: store.language.text("Missing fields total", "Saknade fält totalt"),
                count: missingIssues.reduce(0) { $0 + $1.missingFields.count },
                tone: missingIssues.isEmpty ? .ok : .warning
            ),
            .init(
                id: "duplicate-groups",
                title: store.language.text("Possible duplicate groups", "Möjliga dublettgrupper"),
                count: duplicateIssues.count,
                tone: duplicateIssues.isEmpty ? .ok : .warning
            ),
            .init(
                id: "integrity",
                title: store.language.text("Integrity issues", "Integritetsproblem"),
                count: integrityIssues.count,
                tone: integrityIssues.isEmpty ? .ok : .critical
            ),
            .init(
                id: "archived",
                title: store.language.text("Archived records", "Arkiverade poster"),
                count: archivedItems.count,
                tone: .info
            ),
            .init(
                id: "recent",
                title: store.language.text("Recent changes", "Senaste ändringar"),
                count: revisionHistory.count,
                tone: .info
            )
        ]
    }

    private var completenessItems: [DataCompletenessSummaryItem] {
        let visibleCategories = category == .all ? DataQualityCategory.completenessCases : [category]
        return visibleCategories.map { category in
            let flaggedRecords = Set(
                visibleMissingIssues(in: category)
                    .map(\.recordID)
            ).count
            return DataCompletenessSummaryItem(
                category: category,
                title: category.title(language: store.language),
                totalRecords: totalRecordCount(for: category),
                flaggedRecords: flaggedRecords
            )
        }
    }

    private var missingIssues: [GrantDataStore.MissingFieldIssue] {
        let filteredByCategory = visibleMissingIssues()
        guard let query = query.nonEmpty else { return filteredByCategory }
        return filteredByCategory.filter {
            matches(query: query, fields: [$0.title, $0.subtitle] + $0.missingFields)
        }
    }

    private var duplicateIssues: [GrantDataStore.DuplicateIssue] {
        let filteredByCategory = visibleDuplicateIssues()
        guard let query = query.nonEmpty else { return filteredByCategory }
        return filteredByCategory.filter { issue in
            matches(query: query, fields: [issue.title] + issue.entries.flatMap { [$0.title, $0.subtitle] })
        }
    }

    private var archivedItems: [GrantDataStore.ArchivedRecordSummary] {
        let filteredByCategory = cachedArchivedItems.filter { matchesArchivedCategory($0.kind) }
        guard let query = query.nonEmpty else { return filteredByCategory }
        return filteredByCategory.filter {
            matches(
                query: query,
                fields: [$0.title, $0.localizedKind, $0.deletedAtText]
                    + $0.fieldLines
                    + $0.relatedDocuments.flatMap { [$0.title] + $0.fieldLines }
            )
        }
    }

    private var integrityIssues: [GrantDataStore.IntegrityIssue] {
        let filteredByCategory = visibleIntegrityIssues()
        guard let query = query.nonEmpty else { return filteredByCategory }
        return filteredByCategory.filter { matches(query: query, fields: [$0.title, $0.subtitle, $0.details]) }
    }

    private var structureDiagnostics: [GrantDataStore.DataStructureDiagnosticItem] {
        guard let query = query.nonEmpty else { return cachedStructureDiagnostics }
        return cachedStructureDiagnostics.filter { item in
            matches(
                query: query,
                fields: [item.title, item.value, item.detail] + item.details.flatMap { [$0.title, $0.value] }
            )
        }
    }

    private var unifiedIssues: [DataQualityUnifiedIssue] {
        var rows: [DataQualityUnifiedIssue] = []
        if selectedIssueFilters.contains(.missingFields) {
            rows.append(contentsOf: missingIssues.map(DataQualityUnifiedIssue.missing))
        }
        if selectedIssueFilters.contains(.duplicates) {
            rows.append(contentsOf: duplicateIssues.map(DataQualityUnifiedIssue.duplicate))
        }
        if selectedIssueFilters.contains(.integrity) {
            rows.append(contentsOf: integrityIssues.map(DataQualityUnifiedIssue.integrity))
        }
        if selectedIssueFilters.contains(.structure) {
            rows.append(contentsOf: structureDiagnostics.map(DataQualityUnifiedIssue.structure))
        }
        if selectedIssueFilters.contains(.archive) {
            rows.append(contentsOf: archivedItems.map(DataQualityUnifiedIssue.archive))
        }
        if selectedIssueFilters.contains(.revisions) {
            rows.append(contentsOf: revisionHistory.map(DataQualityUnifiedIssue.revision))
        }
        return rows
    }

    private var hiddenWarningCount: Int {
        cachedMissingIssues.filter { store.isDataQualityWarningHidden($0) }.count
            + cachedDuplicateIssues.filter { store.isDataQualityWarningHidden($0) }.count
            + cachedIntegrityIssues.filter { store.isDataQualityWarningHidden($0) }.count
    }

    private func visibleMissingIssues(in category: DataQualityCategory? = nil) -> [GrantDataStore.MissingFieldIssue] {
        cachedMissingIssues.filter { issue in
            let matchesVisibleCategory = category.map { matchesCategory(issue.entityKind, in: $0) } ?? matchesCategory(issue.entityKind)
            return matchesVisibleCategory && (showHiddenWarnings || !store.isDataQualityWarningHidden(issue))
        }
    }

    private func visibleDuplicateIssues() -> [GrantDataStore.DuplicateIssue] {
        cachedDuplicateIssues.filter {
            matchesCategory($0.groupKind) && (showHiddenWarnings || !store.isDataQualityWarningHidden($0))
        }
    }

    private func visibleIntegrityIssues() -> [GrantDataStore.IntegrityIssue] {
        cachedIntegrityIssues.filter {
            matchesCategory($0.destination) && (showHiddenWarnings || !store.isDataQualityWarningHidden($0))
        }
    }

    private var revisionHistory: [GrantDataStore.RecordRevisionEntry] {
        let filteredByCategory = cachedRevisionHistory.filter { matchesRevisionCategory($0.destination) }
        guard let query = query.nonEmpty else { return filteredByCategory }
        return filteredByCategory.filter { matches(query: query, fields: [$0.title, $0.subtitle, $0.actionName]) }
    }

    var body: some View {
        let language = store.language
        // Every section header shows a summary, so each redraw of this view
        // computes all of them; timed so the log shows what a redraw costs.
        let summariesStartedAt = CFAbsoluteTimeGetCurrent()
        let sectionSummaries = Dictionary(
            firstWinsKeysWithValues: DataQualitySectionKey.allCases.map { ($0, sectionSummary($0, language: language)) }
        )
        let _ = reportSlowSectionSummaries(startedAt: summariesStartedAt)

        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text(language.text("Data quality", "Datakvalitet"))
                    .appTypography(.pageTitle)
                Spacer()
                TextField(language.text("Filter", "Filtrera"), text: $queryDraft)
                    .appTextInputChrome()
                    .frame(width: 240)
                    .overlay(alignment: .trailing) {
                        if !queryDraft.isEmpty {
                            Button {
                                clearDataQualitySearch()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 6)
                            .help(language.text("Clear search", "Rensa sökningen"))
                            .accessibilityLabel(language.text("Clear search", "Rensa sökningen"))
                        }
                    }
                AppMenuSelectionField(
                    selection: $category,
                    options: DataQualityCategory.allCases.map { ($0.title(language: language), $0) },
                    placeholder: nil
                )
                .frame(width: 190, alignment: .leading)
                let hiddenTotal = store.hiddenDataQualityWarningTotalCount
                Toggle(isOn: $showHiddenWarnings) {
                    Text(hiddenTotal > 0
                        ? language.text("Hidden (\(hiddenTotal))", "Dolda (\(hiddenTotal))")
                        : language.text("Hidden", "Dolda"))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
                .help(language.text(
                    "Include warnings you have hidden. Each hidden row gets a Show again button.",
                    "Visa även varningar som du har dolt. Varje dold rad får knappen Visa igen."
                ))
                if hiddenTotal > 0 {
                    Button(language.text("Show all hidden", "Visa alla dolda")) {
                        showsShowAllHiddenConfirmation = true
                    }
                    .controlSize(.small)
                    .help(language.text(
                        "Stop hiding every hidden warning. Can be undone.",
                        "Sluta dölja alla dolda varningar. Kan ångras."
                    ))
                    .confirmationDialog(
                        language.text(
                            "Show all \(hiddenTotal) hidden warnings again?",
                            "Visa alla \(hiddenTotal) dolda varningar igen?"
                        ),
                        isPresented: $showsShowAllHiddenConfirmation
                    ) {
                        Button(language.text("Show all", "Visa alla")) {
                            store.showAllHiddenDataQualityWarnings()
                        }
                        Button(language.text("Cancel", "Avbryt"), role: .cancel) {}
                    } message: {
                        Text(language.text(
                            "Warnings you hid, also in older versions of the app, are shown in the lists again. You can undo this with Undo.",
                            "Varningar som du har dolt, även i äldre versioner av appen, visas i listorna igen. Du kan ångra med Ångra."
                        ))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if isDataQualityFilterActive {
                        dataQualityFilterBanner(language: language)
                    }
                    ForEach(DataQualitySectionKey.allCases) { key in
                        collapsibleSection(
                            key,
                            summary: sectionSummaries[key] ?? sectionSummary(key, language: language),
                            language: language
                        )
                    }
                }
                .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [AppPalette.canvasTop, AppPalette.canvasBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            // Round 17: the issue types the user chose are kept (they used to
            // be reset to all on every appear). With "keep filters" off in
            // Settings, filters saved by an earlier run are cleared the
            // first time the view is shown.
            if ListFilterLaunchPolicy.shouldClearSavedFilters(
                for: .dataQuality,
                retainsFilters: store.shouldRetainListFilters(for: .dataQuality)
            ) {
                clearDataQualityFilters()
                selectedIssueFilters = Set(DataQualityIssueFilter.allCases)
                expandedArchivedIDs.removeAll()
            }
            queryDraft = query
            refreshCachedDiagnosticsIfActive(reason: "appear", force: false)
        }
        .onChange(of: section) { _, value in
            // External navigation (menus, notifications) still speaks
            // DataWorkspaceSection; expand the requested section.
            guard let key = DataQualitySectionKey(section: value) else { return }
            expandedSectionKeys = [key]
        }
        .onChange(of: queryDraft) { _, value in
            scheduleDataQualityQueryUpdate(value)
        }
        // The archive selection follows what is visible: a search, category
        // change, restore or deletion drops hidden ids from the selection, also
        // while the archive section is collapsed.
        .onChange(of: archivedItems.map(\.id)) { _, ids in
            selectedArchivedIDs.formIntersection(ids)
        }
        .onChange(of: selectedIssueFilters) { _, _ in
            refreshCachedDiagnosticsIfActive(reason: "filter-change", force: false)
        }
        .onChange(of: store.dataQualityCacheGeneration) { _, _ in
            guard isActive else {
                loadedIssueFilters.removeAll()
                staleIssueFilters.removeAll()
                refreshCachedDiagnosticsIfActive(reason: "data-change", force: true)
                return
            }
            // Reloading every list takes about three seconds on the main
            // thread, which made each save in the Data view (a translated
            // title, say) freeze the app. Only the open sections are reloaded
            // now; collapsed ones keep their count and reload when opened.
            let openFilters = Set(DataQualityIssueFilter.allCases.filter { expandedSectionKeys.contains($0.sectionKey) })
            staleIssueFilters.formUnion(loadedIssueFilters.subtracting(openFilters))
            loadedIssueFilters.subtract(openFilters)
            refreshCachedDiagnostics(reason: "data-change", force: false)
        }
        .onChange(of: expandedSectionKeys) { _, keys in
            let reopened = staleIssueFilters.filter { keys.contains($0.sectionKey) }
            guard !reopened.isEmpty else { return }
            staleIssueFilters.subtract(reopened)
            loadedIssueFilters.subtract(reopened)
            refreshCachedDiagnosticsIfActive(reason: "section-open", force: false)
        }
        .onChange(of: isActive) { _, active in
            if !active {
                cancelPendingDiagnosticLoads()
                pendingQueryUpdateTask?.cancel()
                pendingQueryUpdateTask = nil
                clearDataQualityFiltersForDeactivationIfNeeded()
                return
            }
            guard needsDiagnosticsRefreshWhenActive else { return }
            refreshCachedDiagnostics(reason: "became-active", force: false)
            needsDiagnosticsRefreshWhenActive = false
        }
        .sheet(item: $pendingDuplicateMergeIssue) { issue in
            DuplicateMergeAssistantSheet(store: store, issue: issue) {
                pendingDuplicateMergeIssue = nil
                loadedIssueFilters.removeAll()
                refreshCachedDiagnosticsIfActive(reason: "duplicate-merge", force: true)
            }
        }
    }

    private func reportSlowSectionSummaries(startedAt: CFAbsoluteTime) {
        let duration = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        guard duration >= 20 else { return }
        store.appendPerformanceDiagnostic(
            String(format: "data-quality-redraw-summaries total_ms=%.2f", duration)
        )
    }

    private func refreshCachedDiagnosticsIfActive(reason: String, force: Bool) {
        guard isActive else {
            needsDiagnosticsRefreshWhenActive = true
            return
        }
        refreshCachedDiagnostics(reason: reason, force: force)
        needsDiagnosticsRefreshWhenActive = false
    }

    private func refreshCachedDiagnostics(reason: String, force: Bool) {
        cancelPendingDiagnosticLoads()
        diagnosticsRefreshGeneration &+= 1
        let generation = diagnosticsRefreshGeneration
        let filters = selectedIssueFilters
        let filtersToLoad = DataQualityIssueFilter.loadOrder.filter { filter in
            filters.contains(filter) && (force || !loadedIssueFilters.contains(filter))
        }
        guard !filtersToLoad.isEmpty else {
            store.appendPerformanceDiagnostic(
                String(
                    format: "data-quality-refresh-skip reason=%@ selected=%@ loaded=%@",
                    reason,
                    filters.map(\.rawValue).sorted().joined(separator: ","),
                    loadedIssueFilters.map(\.rawValue).sorted().joined(separator: ",")
                )
            )
            return
        }
        loadingIssueFilters.formUnion(filtersToLoad)
        store.appendPerformanceDiagnostic(
            String(
                format: "data-quality-refresh-schedule reason=%@ filters=%@",
                reason,
                filtersToLoad.map(\.rawValue).joined(separator: ",")
            )
        )
        for filter in filtersToLoad {
            let task = DispatchWorkItem {
                guard generation == diagnosticsRefreshGeneration else { return }
                loadDiagnosticFilter(filter, reason: reason, generation: generation)
            }
            diagnosticLoadTasks[filter] = task
            DispatchQueue.main.asyncAfter(
                deadline: .now() + dataQualityDiagnosticLoadDelay(
                    for: filter,
                    totalCount: filtersToLoad.count,
                    reason: reason
                ),
                execute: task
            )
        }
    }

    private func dataQualityDiagnosticLoadDelay(
        for filter: DataQualityIssueFilter,
        totalCount: Int,
        reason: String
    ) -> TimeInterval {
        let isInitialBatch = ["appear", "became-active", "data-change"].contains(reason)
        let baseDelay: TimeInterval = isInitialBatch ? 0.16 : 0.06
        guard totalCount > 1 else { return baseDelay }
        switch filter {
        case .missingFields:
            return baseDelay
        case .duplicates:
            return baseDelay + 0.55
        case .integrity:
            return baseDelay + 0.90
        case .structure:
            return baseDelay + 1.25
        case .archive:
            return baseDelay + 1.55
        case .revisions:
            return baseDelay + 1.85
        }
    }

    private func loadDiagnosticFilter(_ filter: DataQualityIssueFilter, reason: String, generation: Int) {
        guard generation == diagnosticsRefreshGeneration else { return }
        if filter == .structure {
            // The structure view runs integrity_check/quick_check PRAGMAs over
            // the whole database file; prefetch them off the main thread and
            // assemble the items afterwards.
            Task { @MainActor in
                await store.refreshSQLiteDiagnosticsPrefetch()
                guard generation == diagnosticsRefreshGeneration else {
                    loadingIssueFilters.remove(filter)
                    diagnosticLoadTasks[filter] = nil
                    return
                }
                finishDiagnosticFilterLoad(filter, reason: reason) {
                    cachedStructureDiagnostics = store.dataStructureDiagnostics()
                    return cachedStructureDiagnostics.count
                }
            }
            return
        }
        finishDiagnosticFilterLoad(filter, reason: reason) {
            switch filter {
            case .missingFields:
                cachedMissingIssues = store.missingFieldIssues(includeHidden: true)
                return cachedMissingIssues.count
            case .duplicates:
                cachedDuplicateIssues = store.duplicateIssues(includeHidden: true)
                return cachedDuplicateIssues.count
            case .integrity:
                cachedIntegrityIssues = store.integrityIssues(includeHidden: true)
                return cachedIntegrityIssues.count
            case .structure:
                return cachedStructureDiagnostics.count
            case .archive:
                cachedArchivedItems = store.archivedRecordSummaries()
                return cachedArchivedItems.count
            case .revisions:
                cachedRevisionHistory = store.recentRecordRevisions()
                return cachedRevisionHistory.count
            }
        }
    }

    private func finishDiagnosticFilterLoad(
        _ filter: DataQualityIssueFilter,
        reason: String,
        compute: () -> Int
    ) {
        let activityLabel = "data-quality-load-\(filter.rawValue)"
        let startedAt = store.beginMainThreadActivity(activityLabel)
        let count = compute()
        store.endMainThreadActivity(activityLabel, startedAt: startedAt)
        loadedIssueFilters.insert(filter)
        loadingIssueFilters.remove(filter)
        diagnosticLoadTasks[filter] = nil
        store.appendPerformanceDiagnostic(
            String(
                format: "data-quality-load filter=%@ reason=%@ count=%ld total_ms=%.2f",
                filter.rawValue,
                reason,
                count,
                (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            )
        )
    }

    private func cancelPendingDiagnosticLoads() {
        for task in diagnosticLoadTasks.values {
            task.cancel()
        }
        diagnosticLoadTasks.removeAll()
        loadingIssueFilters.removeAll()
    }

    private func scheduleDataQualityQueryUpdate(_ value: String) {
        pendingQueryUpdateTask?.cancel()
        let task = DispatchWorkItem {
            let startedAt = CFAbsoluteTimeGetCurrent()
            query = value
            store.appendPerformanceDiagnostic(
                String(
                    format: "data-quality-query-applied length=%ld total_ms=%.2f",
                    value.count,
                    (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
                )
            )
            pendingQueryUpdateTask = nil
        }
        pendingQueryUpdateTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: task)
    }

    private func clearDataQualityFiltersForDeactivationIfNeeded() {
        guard !store.shouldRetainListFilters(for: .dataQuality) else { return }
        queryDraft = ""
        query = ""
        category = .all
        selectedIssueFilters = Set(DataQualityIssueFilter.allCases)
        expandedArchivedIDs.removeAll()
    }

    private func syncIssueFiltersFromSection() {
        let selection = DataQualityIssueFilter.selection(for: section)
        guard !selection.isEmpty else { return }
        selectedIssueFilters = selection
    }

    private func isSectionExpanded(_ key: DataQualitySectionKey) -> Bool {
        expandedSectionKeys.contains(key)
    }

    private func toggleSection(_ key: DataQualitySectionKey) {
        if expandedSectionKeys.contains(key) {
            expandedSectionKeys.remove(key)
        } else {
            expandedSectionKeys.insert(key)
        }
    }

    private struct DataQualitySectionSummary {
        let text: String
        let tone: DataQualityStatusTone
    }

    /// A search or a category narrows the lists below.
    private var isDataQualityFilterActive: Bool {
        query.trimmedOrNil != nil || category != .all
    }

    private func clearDataQualitySearch() {
        pendingQueryUpdateTask?.cancel()
        pendingQueryUpdateTask = nil
        queryDraft = ""
        query = ""
    }

    private func clearDataQualityFilters() {
        clearDataQualitySearch()
        category = .all
        RestoredListFilters.forget(workspace: "DataQuality")
    }

    /// Shown and unfiltered counts of the sections the search and category
    /// narrow; nil for sections they do not affect.
    private func filteredSectionCounts(_ key: DataQualitySectionKey) -> (shown: Int, total: Int)? {
        switch key {
        case .structure:
            return (structureDiagnostics.count, cachedStructureDiagnostics.count)
        case .integrity:
            let total = cachedIntegrityIssues.filter { showHiddenWarnings || !store.isDataQualityWarningHidden($0) }.count
            return (integrityIssues.count, total)
        case .missingFields:
            let total = Set(
                cachedMissingIssues
                    .filter { showHiddenWarnings || !store.isDataQualityWarningHidden($0) }
                    .map(\.recordID)
            ).count
            return (Set(missingIssues.map(\.recordID)).count, total)
        case .duplicates:
            let total = cachedDuplicateIssues.filter { showHiddenWarnings || !store.isDataQualityWarningHidden($0) }.count
            return (duplicateIssues.count, total)
        case .archive:
            return (archivedItems.count, cachedArchivedItems.count)
        case .revisions:
            return (revisionHistory.count, cachedRevisionHistory.count)
        case .translations, .nameLinks, .doctoralActivityLinks:
            return nil
        }
    }

    @ViewBuilder
    private func dataQualityFilterBanner(language: AppLanguage) -> some View {
        // Round 17: the sections count different things (records, issues,
        // pairs), so the banner gives each section's own count instead of
        // one sum that mixes them.
        let counts = DataQualitySectionKey.allCases.compactMap { key -> (title: String, shown: Int, total: Int)? in
            guard let count = filteredSectionCounts(key) else { return nil }
            return (title: key.title(language: language), shown: count.shown, total: count.total)
        }
        let activeFilters = [
            ListFilterLabels.search(query, language: language),
            category == .all ? nil : category.title(language: language),
        ].compactMap { $0 }
        let restored = (query.trimmedOrNil != nil && RestoredListFilters.wasRestored(workspace: "DataQuality.Filter.Query"))
            || (category != .all && RestoredListFilters.wasRestored(workspace: "DataQuality.Filter.Category"))
        AppFilteredListBanner(
            displayedCount: counts.reduce(0) { $0 + $1.shown },
            totalCount: counts.reduce(0) { $0 + $1.total },
            activeFilters: activeFilters,
            restoredFromLastSession: restored,
            countSummary: ListFilterLabels.sectionCounts(counts, language: language)
                ?? language.text("nothing to show", "inget att visa"),
            language: language,
            clearAction: clearDataQualityFilters
        )
    }

    private func sectionSummary(_ key: DataQualitySectionKey, language: AppLanguage) -> DataQualitySectionSummary {
        // While a search or category is on, a section never reports a green
        // "No issues": it says how much of it is shown ("3 av 12 (filtrerat)").
        if isDataQualityFilterActive,
           let counts = filteredSectionCounts(key),
           counts.total > 0 {
            return DataQualitySectionSummary(
                text: language.text(
                    "\(counts.shown) of \(counts.total) (filtered)",
                    "\(counts.shown) av \(counts.total) (filtrerat)"
                ),
                tone: filteredSectionTone(key, shownCount: counts.shown)
            )
        }
        switch key {
        case .structure:
            let total = structureDiagnostics.count
            let remarks = structureDiagnostics.filter { $0.tone != .ok }.count
            if total == 0 {
                return DataQualitySectionSummary(text: language.text("Not checked yet", "Inte kontrollerad ännu"), tone: .info)
            }
            return remarks == 0
                ? DataQualitySectionSummary(
                    text: language.text("\(total) checks without remarks", "\(total) kontroller utan anmärkning"),
                    tone: .ok
                )
                : DataQualitySectionSummary(
                    text: language.text("\(remarks) of \(total) checks need review", "\(remarks) av \(total) kontroller behöver granskas"),
                    tone: .critical
                )
        case .integrity:
            let count = integrityIssues.count
            return count == 0
                ? DataQualitySectionSummary(text: language.text("No issues", "Inga problem"), tone: .ok)
                : DataQualitySectionSummary(text: language.text("\(count) issues", "\(count) problem"), tone: .critical)
        case .missingFields:
            let records = Set(missingIssues.map(\.recordID)).count
            return records == 0
                ? DataQualitySectionSummary(text: language.text("Nothing missing", "Inget saknas"), tone: .ok)
                : DataQualitySectionSummary(
                    text: language.text("\(records) records · \(missingFieldTotal) fields", "\(records) poster · \(missingFieldTotal) fält"),
                    tone: .warning
                )
        case .translations:
            let count = store.translationIssues().count
            return count == 0
                ? DataQualitySectionSummary(text: language.text("Everything translated", "Allt är översatt"), tone: .ok)
                : DataQualitySectionSummary(text: language.text("\(count) fields", "\(count) fält"), tone: .warning)
        case .nameLinks:
            let count = store.unlinkedPersonNames().count
            return count == 0
                ? DataQualitySectionSummary(text: language.text("All names are linked", "Alla namn är kopplade"), tone: .ok)
                : DataQualitySectionSummary(text: language.text("\(count) names", "\(count) namn"), tone: .warning)
        case .doctoralActivityLinks:
            let count = store.doctoralActivityLinkSuggestions().count
            return count == 0
                ? DataQualitySectionSummary(text: language.text("Nothing to link", "Inget att koppla"), tone: .ok)
                : DataQualitySectionSummary(text: language.text("\(count) activities", "\(count) aktiviteter"), tone: .warning)
        case .duplicates:
            let count = duplicateIssues.count
            return count == 0
                ? DataQualitySectionSummary(text: language.text("No duplicates found", "Inga dubletter hittade"), tone: .ok)
                : DataQualitySectionSummary(text: language.text("\(count) groups", "\(count) grupper"), tone: .warning)
        case .archive:
            return DataQualitySectionSummary(
                text: language.text("\(archivedItems.count) records", "\(archivedItems.count) poster"),
                tone: .info
            )
        case .revisions:
            return DataQualitySectionSummary(
                text: language.text("\(revisionHistory.count) changes", "\(revisionHistory.count) ändringar"),
                tone: .info
            )
        }
    }

    private func filteredSectionTone(_ key: DataQualitySectionKey, shownCount: Int) -> DataQualityStatusTone {
        guard shownCount > 0 else { return .info }
        switch key {
        case .integrity:
            return .critical
        case .structure:
            return structureDiagnostics.contains { $0.tone != .ok } ? .critical : .info
        case .missingFields, .duplicates:
            return .warning
        case .archive, .revisions, .translations, .nameLinks, .doctoralActivityLinks:
            return .info
        }
    }

    @ViewBuilder
    private func collapsibleSection(
        _ key: DataQualitySectionKey,
        summary: DataQualitySectionSummary,
        language: AppLanguage
    ) -> some View {
        let isExpanded = isSectionExpanded(key)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                toggleSection(key)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Image(systemName: key.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppPalette.linkAction)
                        .frame(width: 22)
                    Text(key.title(language: language))
                        .appTypography(.sectionTitle)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(summary.text)
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)
                    DataQualityStatusIcon(tone: summary.tone, size: 15)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(key.title(language: language))
            .accessibilityValue(summary.text)
            .accessibilityAddTraits(isExpanded ? .isSelected : [])

            if isExpanded {
                sectionContent(key, language: language)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppPalette.cardSurface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppPalette.subtleBorder, lineWidth: 1))
    }

    @ViewBuilder
    private func sectionContent(_ key: DataQualitySectionKey, language: AppLanguage) -> some View {
        switch key {
        case .structure:
            issuesCard(structureDiagnostics.map(DataQualityUnifiedIssue.structure), language: language)
        case .integrity:
            issuesCard(integrityIssues.map(DataQualityUnifiedIssue.integrity), language: language)
        case .missingFields:
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(completenessItems) { item in
                        completenessRow(item, language: language)
                    }
                }
                issuesCard(missingIssues.map(DataQualityUnifiedIssue.missing), language: language)
            }
        case .translations:
            translationsSectionContent(language: language)
        case .nameLinks:
            nameLinksSectionContent(language: language)
        case .doctoralActivityLinks:
            doctoralActivityLinksSectionContent(language: language)
        case .duplicates:
            issuesCard(duplicateIssues.map(DataQualityUnifiedIssue.duplicate), language: language)
        case .archive:
            VStack(alignment: .leading, spacing: 10) {
                if !archivedItems.isEmpty {
                    archiveSelectionToolbar(language: language)
                }
                issuesCard(archivedItems.map(DataQualityUnifiedIssue.archive), language: language)
            }
        case .revisions:
            issuesCard(revisionHistory.map(DataQualityUnifiedIssue.revision), language: language)
        }
    }

    @ViewBuilder
    private func issuesCard(_ rows: [DataQualityUnifiedIssue], language: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty {
                dataQualityEmptyState(language: language)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, issue in
                    unifiedDataQualityRow(issue, language: language)
                    if index < rows.count - 1 {
                        Divider()
                            .padding(.leading, 42)
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppPalette.secondaryCardSurface))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppPalette.subtleBorder.opacity(0.7), lineWidth: 1))
    }

    @ViewBuilder
    private func dataQualityFilterCheckboxes(language: AppLanguage) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(DataQualityIssueFilter.allCases) { filter in
                Toggle(
                    isOn: Binding(
                        get: { selectedIssueFilters.contains(filter) },
                        set: { isSelected in
                            if isSelected {
                                selectedIssueFilters.insert(filter)
                            } else {
                                selectedIssueFilters.remove(filter)
                            }
                        }
                    )
                ) {
                    HStack(spacing: 6) {
                        Image(systemName: filter.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(filterTint(filter))
                        Text(filter.title(language: language))
                            .appTypography(.secondary)
                            .lineLimit(1)
                        Text(issueCountText(for: filter, language: language))
                            .font(appFont(.secondary).weight(.semibold).monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                    .appCheckboxStyle()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppPalette.cardSurface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppPalette.subtleBorder, lineWidth: 1))
    }

    private func dataQualityResultCountText(rowCount: Int, language: AppLanguage) -> String {
        if selectedIssueFilters.isEmpty {
            return language.text("No problem types selected", "Inga problemtyper valda")
        }
        if !selectedIssueFilters.isDisjoint(with: loadingIssueFilters) {
            return language.text("Loading \(rowCount) rows...", "Laddar \(rowCount) rader...")
        }
        return language.text("\(rowCount) rows", "\(rowCount) rader")
    }

    private func issueCountText(for filter: DataQualityIssueFilter, language: AppLanguage) -> String {
        if loadingIssueFilters.contains(filter) {
            return "..."
        }
        guard loadedIssueFilters.contains(filter) else {
            return "–"
        }
        return "\(issueCount(for: filter))"
    }

    private func issueCount(for filter: DataQualityIssueFilter) -> Int {
        switch filter {
        case .missingFields:
            return missingIssues.count
        case .duplicates:
            return duplicateIssues.count
        case .integrity:
            return integrityIssues.count
        case .structure:
            return structureDiagnostics.count
        case .archive:
            return archivedItems.count
        case .revisions:
            return revisionHistory.count
        }
    }

    private var dataQualityColumnFilters: [DataQualityIssueFilter] {
        [.missingFields, .duplicates, .integrity, .structure]
    }

    private var usesDataQualityColumnLayout: Bool {
        Set(dataQualityColumnFilters).isSuperset(of: selectedIssueFilters)
    }

    @ViewBuilder
    private func dataQualityIssuesView(rows: [DataQualityUnifiedIssue], language: AppLanguage) -> some View {
        if usesDataQualityColumnLayout {
            dataQualityColumnBoard(language: language)
        } else {
            unifiedDataQualityList(rows: rows, language: language)
        }
    }

    @ViewBuilder
    private func dataQualityColumnBoard(language: AppLanguage) -> some View {
        let rows = dataQualityColumnFilters.flatMap { dataQualityColumnIssues(for: $0) }
        GeometryReader { proxy in
            let spacing: CGFloat = 10
            let columnWidth = max(240, (proxy.size.width - (spacing * 3)) / 4)

            ScrollView([.vertical, .horizontal]) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(dataQualityColumnFilters, id: \.rawValue) { filter in
                        dataQualityColumn(filter: filter, language: language, width: columnWidth)
                    }
                }
                .frame(minWidth: proxy.size.width, alignment: .leading)
                .padding(.bottom, 2)
            }
            .onAppear {
                reportDataQualityRows(rows)
            }
            .onChange(of: dataQualityRowsSignature(rows)) { _, _ in
                reportDataQualityRows(rows)
            }
        }
    }

    private func dataQualityColumnIssues(for filter: DataQualityIssueFilter) -> [DataQualityUnifiedIssue] {
        guard selectedIssueFilters.contains(filter) else { return [] }
        switch filter {
        case .missingFields:
            return missingIssues.map(DataQualityUnifiedIssue.missing)
        case .duplicates:
            return duplicateIssues.map(DataQualityUnifiedIssue.duplicate)
        case .integrity:
            return integrityIssues.map(DataQualityUnifiedIssue.integrity)
        case .structure:
            return structureDiagnostics.map(DataQualityUnifiedIssue.structure)
        case .archive, .revisions:
            return []
        }
    }

    @ViewBuilder
    private func dataQualityColumn(filter: DataQualityIssueFilter, language: AppLanguage, width: CGFloat) -> some View {
        let issues = dataQualityColumnIssues(for: filter)
        let isSelected = selectedIssueFilters.contains(filter)
        let isLoading = loadingIssueFilters.contains(filter)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: filter.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(filterTint(filter))
                    .frame(width: 14)
                Text(filter.title(language: language))
                    .appTypography(.tableHeader)
                    .foregroundStyle(AppPalette.appText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(isSelected ? issueCountText(for: filter, language: language) : "–")
                    .font(appFont(.secondary).weight(.semibold).monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(filterTint(filter).opacity(0.08))

            Divider()

            if !isSelected {
                dataQualityColumnEmptyText(language.text("Not selected", "Inte vald"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if isLoading && issues.isEmpty {
                dataQualityColumnEmptyText(language.text("Loading...", "Laddar..."))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if issues.isEmpty {
                dataQualityColumnEmptyText(language.text("No rows", "Inga rader"))
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(issues.enumerated()), id: \.element.id) { index, issue in
                        dataQualityColumnRow(issue, language: language)
                        if index < issues.count - 1 {
                            Divider()
                                .padding(.leading, 24)
                        }
                    }
                }
            }
        }
        .frame(width: width, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppPalette.cardSurface.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppPalette.subtleBorder, lineWidth: 1))
    }

    private func dataQualityColumnEmptyText(_ text: String) -> some View {
        Text(text)
            .appTypography(.secondary)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
    }

    @ViewBuilder
    private func dataQualityColumnRow(_ issue: DataQualityUnifiedIssue, language: AppLanguage) -> some View {
        HStack(alignment: .top, spacing: 7) {
            DataQualityStatusIcon(tone: unifiedTone(for: issue), size: 12)
                .frame(width: 16, height: 18, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(dataQualityColumnPrimaryText(for: issue))
                        .appTypography(.tableHeader)
                        .foregroundStyle(AppPalette.appText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if isUnifiedIssueHidden(issue) {
                        hiddenWarningBadge(language: language)
                    }
                    Spacer(minLength: 4)
                    unifiedIssueActions(issue, language: language)
                }

                if let secondary = dataQualityColumnSecondaryText(for: issue, language: language).nonEmpty {
                    Text(secondary)
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(dataQualityColumnSecondaryLineLimit(for: issue))
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                }

                if let detail = dataQualityColumnDetailText(for: issue, language: language).nonEmpty {
                    Text(detail)
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(minHeight: 58, alignment: .topLeading)
        .background(isUnifiedIssueHidden(issue) ? AppPalette.fieldSurface.opacity(0.42) : Color.clear)
    }

    private func dataQualityColumnPrimaryText(for issue: DataQualityUnifiedIssue) -> String {
        switch issue {
        case .missing(let missing):
            if let subtitle = missing.subtitle.nonEmpty {
                return "\(missing.title) (\(subtitle))"
            }
            return missing.title
        default:
            return unifiedTitle(for: issue)
        }
    }

    private func dataQualityColumnSecondaryText(for issue: DataQualityUnifiedIssue, language: AppLanguage) -> String {
        switch issue {
        case .missing(let missing):
            return missing.missingFields.joined(separator: ", ")
        default:
            return unifiedSubtitle(for: issue)
        }
    }

    private func dataQualityColumnDetailText(for issue: DataQualityUnifiedIssue, language: AppLanguage) -> String {
        switch issue {
        case .missing:
            return ""
        default:
            return unifiedDetail(for: issue, language: language)
        }
    }

    private func dataQualityColumnSecondaryLineLimit(for issue: DataQualityUnifiedIssue) -> Int {
        switch issue {
        case .missing:
            return 2
        default:
            return 1
        }
    }

    @ViewBuilder
    private func unifiedDataQualityList(rows: [DataQualityUnifiedIssue], language: AppLanguage) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if rows.isEmpty {
                    dataQualityEmptyState(language: language)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, issue in
                        unifiedDataQualityRow(issue, language: language)
                        if index < rows.count - 1 {
                            Divider()
                                .padding(.leading, 42)
                        }
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppPalette.cardSurface))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppPalette.subtleBorder, lineWidth: 1))
        }
        .onAppear {
            reportDataQualityRows(rows)
        }
        .onChange(of: dataQualityRowsSignature(rows)) { _, _ in
            reportDataQualityRows(rows)
        }
    }

    private func dataQualityRowsSignature(_ rows: [DataQualityUnifiedIssue]) -> String {
        [
            "\(rows.count)",
            rows.first?.id ?? "-",
            rows.last?.id ?? "-",
            selectedIssueFilters.map(\.rawValue).sorted().joined(separator: ","),
            loadingIssueFilters.map(\.rawValue).sorted().joined(separator: ","),
            query
        ].joined(separator: "|")
    }

    private func reportDataQualityRows(_ rows: [DataQualityUnifiedIssue]) {
        store.appendPerformanceDiagnostic(
            String(
                format: "data-quality-rows rows=%ld selected=%@ loading=%@ query_length=%ld",
                rows.count,
                selectedIssueFilters.map(\.rawValue).sorted().joined(separator: ","),
                loadingIssueFilters.map(\.rawValue).sorted().joined(separator: ","),
                query.count
            )
        )
    }

    @ViewBuilder
    private func dataQualityEmptyState(language: AppLanguage) -> some View {
        HStack(spacing: 10) {
            DataQualityStatusIcon(tone: .ok, size: 15)
            Text(language.text("No rows match the current filters.", "Inga rader matchar nuvarande filter."))
                .appTypography(.body)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(14)
    }

    @ViewBuilder
    private func unifiedDataQualityRow(_ issue: DataQualityUnifiedIssue, language: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 9) {
                if case .archive(let archivedItem) = issue {
                    archiveSelectionCheckbox(for: archivedItem.id, language: language)
                        .frame(width: 18, height: 22, alignment: .center)
                }
                DataQualityStatusIcon(tone: unifiedTone(for: issue), size: 14)
                    .frame(width: 18, height: 22, alignment: .center)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        dataQualityTypeBadge(issue.filter, language: language)
                        if isUnifiedIssueHidden(issue) {
                            hiddenWarningBadge(language: language)
                        }
                        Text(unifiedTitle(for: issue))
                            .appTypography(.tableHeader)
                            .foregroundStyle(AppPalette.appText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    if let subtitle = unifiedSubtitle(for: issue).nonEmpty {
                        Text(subtitle)
                            .appTypography(.secondary)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    if let detail = unifiedDetail(for: issue, language: language).nonEmpty {
                        Text(detail)
                            .appTypography(.secondary)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .textSelection(.enabled)
                    }
                }

                Spacer(minLength: 12)

                unifiedIssueActions(issue, language: language)
            }

            if case .archive(let item) = issue, expandedArchivedIDs.contains(item.id) {
                VStack(alignment: .leading, spacing: 8) {
                    archiveDetailBlock(
                        title: language.text("Stored fields", "Sparade fält"),
                        lines: item.fieldLines,
                        emptyText: language.text("No stored fields found.", "Inga sparade fält hittades.")
                    )
                    if !item.relatedDocuments.isEmpty {
                        ForEach(item.relatedDocuments) { document in
                            archiveDetailBlock(
                                title: document.title,
                                lines: document.fieldLines,
                                emptyText: language.text("No stored fields found.", "Inga sparade fält hittades.")
                            )
                        }
                    }
                }
                .padding(.leading, 27)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isUnifiedIssueHidden(issue) ? AppPalette.fieldSurface.opacity(0.42) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { openUnifiedIssueRow(issue) }
    }

    // F23: the whole row opens the record, like the Show button.
    private func openUnifiedIssueRow(_ issue: DataQualityUnifiedIssue) {
        switch issue {
        case .missing(let missing):
            dismiss()
            store.openIssue(destination: missing.destination, recordID: missing.recordID)
        case .integrity(let integrity):
            dismiss()
            openIntegrityIssue(integrity)
        case .archive(let item):
            toggleArchivedExpansion(item.id)
        case .duplicate, .structure, .revision:
            break
        }
    }

    @ViewBuilder
    private func dataQualityTypeBadge(_ filter: DataQualityIssueFilter, language: AppLanguage) -> some View {
        Label(filter.title(language: language), systemImage: filter.systemImage)
            .appTypography(.tableHeader)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(filterTint(filter))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(filterTint(filter).opacity(0.12)))
            .fixedSize()
    }

    @ViewBuilder
    private func unifiedIssueActions(_ issue: DataQualityUnifiedIssue, language: AppLanguage) -> some View {
        HStack(spacing: 5) {
            switch issue {
            case .missing(let missing):
                dataQualityHideToggle(isHidden: store.isDataQualityWarningHidden(missing), language: language) {
                    if store.isDataQualityWarningHidden(missing) {
                        if store.showDataQualityWarning(missing) {
                            // The lists keep hidden rows and the redraw filters them, so
                            // nothing is reloaded (reloading took about three seconds).
                        }
                    } else if store.hideDataQualityWarning(missing) {
                        // The lists keep hidden rows and the redraw filters them, so
                        // nothing is reloaded (reloading took about three seconds).
                    }
                }
                dataQualityIconButton(
                    systemImage: "arrow.right.circle",
                    help: language.text("Show", "Visa")
                ) {
                    dismiss()
                    store.openIssue(destination: missing.destination, recordID: missing.recordID)
                }

            case .duplicate(let duplicate):
                dataQualityHideToggle(isHidden: store.isDataQualityWarningHidden(duplicate), language: language) {
                    if store.isDataQualityWarningHidden(duplicate) {
                        if store.showDataQualityWarning(duplicate) {
                            // The lists keep hidden rows and the redraw filters them, so
                            // nothing is reloaded (reloading took about three seconds).
                        }
                    } else if store.hideDataQualityWarning(duplicate) {
                        // The lists keep hidden rows and the redraw filters them, so
                        // nothing is reloaded (reloading took about three seconds).
                    }
                }
                if store.supportsDuplicateMerge(for: duplicate.groupKind), duplicate.entries.count > 1 {
                    dataQualityIconButton(
                        systemImage: "arrow.triangle.merge",
                        help: language.text("Merge", "Slå ihop")
                    ) {
                        pendingDuplicateMergeIssue = duplicate
                    }
                }
                Menu {
                    ForEach(duplicate.entries) { entry in
                        Button(entry.title) {
                            dismiss()
                            store.openIssue(destination: entry.destination, recordID: entry.recordID)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.right.circle")
                        .frame(width: 24, height: 22)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help(language.text("Open record", "Öppna post"))
                .accessibilityLabel(language.text("Open record", "Öppna post"))

            case .integrity(let integrity):
                dataQualityHideToggle(isHidden: store.isDataQualityWarningHidden(integrity), language: language) {
                    if store.isDataQualityWarningHidden(integrity) {
                        if store.showDataQualityWarning(integrity) {
                            // The lists keep hidden rows and the redraw filters them, so
                            // nothing is reloaded (reloading took about three seconds).
                        }
                    } else if store.hideDataQualityWarning(integrity) {
                        // The lists keep hidden rows and the redraw filters them, so
                        // nothing is reloaded (reloading took about three seconds).
                    }
                }
                if store.missingAttachmentTarget(for: integrity) != nil {
                    dataQualityIconButton(
                        systemImage: "doc.badge.plus",
                        help: language.text("Choose file", "Välj fil")
                    ) {
                        store.chooseFileForMissingAttachment(integrity)
                        loadedIssueFilters.removeAll()
                        refreshCachedDiagnosticsIfActive(reason: "attach-file", force: true)
                    }
                }
                dataQualityIconButton(
                    systemImage: "arrow.right.circle",
                    help: language.text("Show", "Visa")
                ) {
                    dismiss()
                    openIntegrityIssue(integrity)
                }

            case .structure:
                EmptyView()

            case .archive(let item):
                dataQualityIconButton(
                    systemImage: expandedArchivedIDs.contains(item.id) ? "chevron.down" : "chevron.right",
                    help: language.text("Details", "Detaljer")
                ) {
                    toggleArchivedExpansion(item.id)
                }
                dataQualityIconButton(
                    systemImage: "arrow.uturn.backward",
                    help: language.text("Restore", "Återställ")
                ) {
                    store.restoreArchivedRecord(id: item.id)
                }
                ArchivePermanentDeleteIconButton(language: language) {
                    store.permanentlyDeleteArchivedRecord(id: item.id)
                }

            case .revision(let entry):
                if let destination = entry.destination,
                   let recordID = entry.recordID {
                    dataQualityIconButton(
                        systemImage: "arrow.right.circle",
                        help: language.text("Show", "Visa")
                    ) {
                        dismiss()
                        store.openIssue(destination: destination, recordID: recordID)
                    }
                }
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func dataQualityHideToggle(isHidden: Bool, language: AppLanguage, action: @escaping () -> Void) -> some View {
        dataQualityIconButton(
            systemImage: isHidden ? "eye" : "eye.slash",
            help: isHidden
                ? language.text("Show again", "Visa igen")
                : language.text("Hide", "Dölj"),
            action: action
        )
    }

    // Findings that live in the calendar (overdue project tasks) reveal
    // their day and event there; everything else routes to its record.
    private func openIntegrityIssue(_ issue: GrantDataStore.IntegrityIssue) {
        if let dayString = issue.calendarRevealDayString,
           let date = DateParsers.isoDay.date(from: dayString) {
            store.revealCalendarWorkspace(on: date, eventSource: issue.calendarEventSource)
            return
        }
        store.openIssue(destination: issue.destination, recordID: issue.recordID)
    }

    private func dataQualityIconButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        // F23: text instead of icons.
        Button(action: action) {
            Text(help)
                .font(appFont(.secondary).weight(.semibold))
                .frame(height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }

    private func unifiedTone(for issue: DataQualityUnifiedIssue) -> DataQualityStatusTone {
        switch issue {
        case .missing(let missing):
            switch missing.severity {
            case .critical:
                return .critical
            case .warning:
                return .warning
            }
        case .duplicate:
            return .warning
        case .integrity:
            return .critical
        case .structure(let item):
            return dataQualityStatusTone(for: item.tone)
        case .archive, .revision:
            return .info
        }
    }

    private func filterTint(_ filter: DataQualityIssueFilter) -> Color {
        switch filter {
        case .missingFields:
            return AppPalette.statusText(.warning)
        case .duplicates:
            return AppPalette.linkAction
        case .integrity:
            return AppPalette.statusText(.negative)
        case .structure:
            return AppPalette.statusText(.done)
        case .archive, .revisions:
            return AppPalette.appText.opacity(0.62)
        }
    }

    private func unifiedTitle(for issue: DataQualityUnifiedIssue) -> String {
        switch issue {
        case .missing(let missing):
            return missing.title
        case .duplicate(let duplicate):
            return duplicate.title
        case .integrity(let integrity):
            return integrity.title
        case .structure(let item):
            return item.title
        case .archive(let item):
            return item.title
        case .revision(let entry):
            return entry.title
        }
    }

    private func unifiedSubtitle(for issue: DataQualityUnifiedIssue) -> String {
        switch issue {
        case .missing(let missing):
            return missing.subtitle
        case .duplicate(let duplicate):
            return duplicate.entries
                .prefix(3)
                .map(\.title)
                .joined(separator: " · ")
        case .integrity(let integrity):
            return integrity.subtitle
        case .structure(let item):
            return item.detail
        case .archive(let item):
            return "\(item.localizedKind) · \(item.deletedAtText)"
        case .revision(let entry):
            return entry.actionName
        }
    }

    private func unifiedDetail(for issue: DataQualityUnifiedIssue, language: AppLanguage) -> String {
        switch issue {
        case .missing(let missing):
            let fields = missing.missingFields.joined(separator: ", ")
            if let why = missing.whyFlagged.nonEmpty {
                return "\(fields) · \(why)"
            }
            return fields
        case .duplicate(let duplicate):
            let additionalCount = max(0, duplicate.entries.count - 3)
            if additionalCount > 0 {
                return language.text(
                    "\(additionalCount) additional possible duplicates",
                    "\(additionalCount) ytterligare möjliga dubletter"
                )
            }
            return duplicate.entries.map(\.subtitle).compactMap(\.nonEmpty).prefix(2).joined(separator: " · ")
        case .integrity(let integrity):
            return integrity.details
        case .structure(let item):
            let details = item.details.prefix(3).map { "\($0.title): \($0.value)" }.joined(separator: " · ")
            return details.nonEmpty ?? item.value
        case .archive(let item):
            return item.fieldLines.prefix(2).joined(separator: " · ")
        case .revision(let entry):
            var parts = [relativeDateString(entry.timestamp)]
            if let destination = entry.destination {
                parts.append(localizedDestinationName(destination, language: language))
            }
            if let subtitle = entry.subtitle.nonEmpty {
                parts.append(subtitle)
            }
            return parts.joined(separator: " · ")
        }
    }

    private func isUnifiedIssueHidden(_ issue: DataQualityUnifiedIssue) -> Bool {
        switch issue {
        case .missing(let missing):
            return store.isDataQualityWarningHidden(missing)
        case .duplicate(let duplicate):
            return store.isDataQualityWarningHidden(duplicate)
        case .integrity(let integrity):
            return store.isDataQualityWarningHidden(integrity)
        case .structure, .archive, .revision:
            return false
        }
    }

    private var missingFieldTotal: Int {
        missingIssues.reduce(0) { $0 + $1.missingFields.count }
    }

    @ViewBuilder
    private func missingFieldsList(language: AppLanguage) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(missingIssues) { issue in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(issue.title)
                                    .appTypography(.panelTitle)
                                if let subtitle = issue.subtitle.nonEmpty {
                                    Text(subtitle)
                                        .appTypography(.secondary)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            IssueSeverityBadge(severity: issue.severity, language: language)
                            if store.isDataQualityWarningHidden(issue) {
                                hiddenWarningBadge(language: language)
                                Button(language.text("Show again", "Visa igen")) {
                                    if store.showDataQualityWarning(issue) {
                                        // The lists keep hidden rows and the redraw filters them, so
                                        // nothing is reloaded (reloading took about three seconds).
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                Button {
                                    if store.hideDataQualityWarning(issue) {
                                        // The lists keep hidden rows and the redraw filters them, so
                                        // nothing is reloaded (reloading took about three seconds).
                                    }
                                } label: {
                                    Label(language.text("Hide warning", "Dölj varning"), systemImage: "eye.slash")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help(language.text("Hide this warning", "Dölj den här varningen"))
                            }
                            Button(language.text("Open", "Öppna")) {
                                dismiss()
                                store.openIssue(destination: issue.destination, recordID: issue.recordID)
                            }
                            .controlSize(.small)
                        }
                        IssueFieldBadges(fields: issue.missingFields)
                        if let why = issue.whyFlagged.nonEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                AppFieldLabelText(text: language.text("Why flagged", "Varför flaggad"))
                                Text(why)
                                    .appTypography(.secondary)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let fix = issue.suggestedFix.nonEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                AppFieldLabelText(text: language.text("Suggested action", "Föreslagen åtgärd"))
                                Text(fix)
                                    .appTypography(.secondary)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppPalette.cardSurface))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppPalette.border, lineWidth: 1))
                }
            }
        }
    }

    @ViewBuilder
    private func duplicatesList(language: AppLanguage) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(duplicateIssues) { issue in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(issue.title)
                                .appTypography(.panelTitle)
                            Spacer()
                            if store.isDataQualityWarningHidden(issue) {
                                hiddenWarningBadge(language: language)
                                Button(language.text("Show again", "Visa igen")) {
                                    if store.showDataQualityWarning(issue) {
                                        // The lists keep hidden rows and the redraw filters them, so
                                        // nothing is reloaded (reloading took about three seconds).
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                Button {
                                    if store.hideDataQualityWarning(issue) {
                                        // The lists keep hidden rows and the redraw filters them, so
                                        // nothing is reloaded (reloading took about three seconds).
                                    }
                                } label: {
                                    Label(language.text("Not duplicate", "Inte dublett"), systemImage: "eye.slash")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help(language.text("Hide this duplicate warning", "Dölj den här dublettvarningen"))
                            }
                            if store.supportsDuplicateMerge(for: issue.groupKind), issue.entries.count > 1 {
                                Button(language.text("Merge...", "Slå ihop...")) {
                                    pendingDuplicateMergeIssue = issue
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        ForEach(issue.entries) { entry in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.title)
                                        .appTypography(.body)
                                    if let subtitle = entry.subtitle.nonEmpty {
                                        Text(subtitle)
                                            .appTypography(.secondary)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button(language.text("Open", "Öppna")) {
                                    dismiss()
                                    store.openIssue(destination: entry.destination, recordID: entry.recordID)
                                }
                            }
                            if entry.id != issue.entries.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppPalette.cardSurface))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppPalette.border, lineWidth: 1))
                }
            }
        }
    }

    @ViewBuilder
    private func archiveSelectionToolbar(language: AppLanguage) -> some View {
        // Only what is selected and visible right now counts: a record hidden
        // by the search or category is never deleted with "Delete selected".
        let visibleIDs = archivedItems.map(\.id)
        let deletableIDs = ArchiveSelectionPolicy.deletableIDs(selected: selectedArchivedIDs, visibleIDs: visibleIDs)
        let allSelected = ArchiveSelectionPolicy.allVisibleSelected(selected: selectedArchivedIDs, visibleIDs: visibleIDs)
        HStack(spacing: 12) {
            Button(
                allSelected
                    ? language.text("Deselect all", "Avmarkera alla")
                    : language.text("Select all", "Välj alla")
            ) {
                if allSelected {
                    selectedArchivedIDs.removeAll()
                } else {
                    selectedArchivedIDs = Set(visibleIDs)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if !deletableIDs.isEmpty {
                Text(language.text("\(deletableIDs.count) selected", "\(deletableIDs.count) valda"))
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
                DeleteActionButton(
                    title: language.text("Delete selected", "Ta bort valda"),
                    confirmationTitle: language.text(
                        "Permanently delete \(deletableIDs.count) archived records?",
                        "Ta bort \(deletableIDs.count) arkiverade poster permanent?"
                    ),
                    cancelTitle: language.text("Cancel", "Avbryt")
                ) {
                    // Exactly the records the dialog counted, if still visible.
                    let idsToDelete = deletableIDs.intersection(archivedItems.map(\.id))
                    guard !idsToDelete.isEmpty else { return }
                    store.permanentlyDeleteArchivedRecords(ids: idsToDelete)
                    selectedArchivedIDs.subtract(idsToDelete)
                }
            }
            Spacer()
        }
    }

    private func archiveSelectionCheckbox(for itemID: String, language: AppLanguage) -> some View {
        Button {
            if selectedArchivedIDs.contains(itemID) {
                selectedArchivedIDs.remove(itemID)
            } else {
                selectedArchivedIDs.insert(itemID)
            }
        } label: {
            Image(systemName: selectedArchivedIDs.contains(itemID) ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(selectedArchivedIDs.contains(itemID) ? AppPalette.statusMark(.done) : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            selectedArchivedIDs.contains(itemID)
                ? language.text("Deselect record", "Avmarkera post")
                : language.text("Select record", "Markera post")
        )
    }

    @ViewBuilder
    private func archiveDetailBlock(title: String, lines: [String], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AppFieldLabelText(text: title)
            VStack(alignment: .leading, spacing: 6) {
                if lines.isEmpty {
                    Text(emptyText)
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(appFont(.secondary).monospaced())
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppPalette.fieldSurface))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppPalette.subtleBorder, lineWidth: 1))
        }
    }

    private func toggleArchivedExpansion(_ id: String) {
        if expandedArchivedIDs.contains(id) {
            expandedArchivedIDs.remove(id)
        } else {
            expandedArchivedIDs.insert(id)
        }
    }

    @ViewBuilder
    private func integrityList(language: AppLanguage) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if !integrityIssues.isEmpty {
                    ForEach(integrityIssues) { issue in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                if isAttachmentIntegrityIssue(issue) {
                                    AttachmentWarningIcon(
                                        size: 17,
                                        help: language.text("Missing or problematic attachment", "Saknad eller problematisk bilaga")
                                    )
                                } else {
                                    DataQualityStatusIcon(tone: .critical, size: 15)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(issue.title)
                                        .appTypography(.panelTitle)
                                    Text(issue.subtitle)
                                        .appTypography(.secondary)
                                        .foregroundStyle(.secondary)
                                    Text(issue.details)
                                        .appTypography(.secondary)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.isDataQualityWarningHidden(issue) {
                                    hiddenWarningBadge(language: language)
                                    Button(language.text("Show again", "Visa igen")) {
                                        if store.showDataQualityWarning(issue) {
                                            // The lists keep hidden rows and the redraw filters them, so
                                            // nothing is reloaded (reloading took about three seconds).
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                } else {
                                    Button {
                                        if store.hideDataQualityWarning(issue) {
                                            // The lists keep hidden rows and the redraw filters them, so
                                            // nothing is reloaded (reloading took about three seconds).
                                        }
                                    } label: {
                                        Label(language.text("Hide warning", "Dölj varning"), systemImage: "eye.slash")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help(language.text("Hide this warning", "Dölj den här varningen"))
                                }
                                Button(language.text("Open", "Öppna")) {
                                    dismiss()
                                    openIntegrityIssue(issue)
                                }
                                .controlSize(.small)
                            }
                        }
                        .appCardChrome(padding: 14, stroke: AppPalette.border)
                    }
                }

                if !revisionHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        AppPanelHeadingText(text: language.text("Recent changes", "Senaste ändringar"))
                        ForEach(revisionHistory) { entry in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title)
                                        .appTypography(.panelTitle)
                                    Text(entry.actionName)
                                        .appTypography(.secondary)
                                        .foregroundStyle(.secondary)
                                    if let destination = entry.destination {
                                        Text(localizedDestinationName(destination, language: language))
                                            .appTypography(.secondary)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(relativeDateString(entry.timestamp))
                                    .appTypography(.secondary)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppPalette.fieldSurface))
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppPalette.cardSurface))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppPalette.border, lineWidth: 1))
                }
            }
        }
    }

    private func isAttachmentIntegrityIssue(_ issue: GrantDataStore.IntegrityIssue) -> Bool {
        let combinedText = [issue.subtitle, issue.details]
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        return combinedText.contains("pdf")
            || combinedText.contains("bilaga")
            || combinedText.contains("attachment")
            || combinedText.contains("certificate")
            || combinedText.contains("intyg")
    }

    @ViewBuilder
    private func structureDiagnosticsList(language: AppLanguage) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(cachedStructureDiagnostics) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        DataQualityStatusIcon(tone: dataQualityStatusTone(for: item.tone), size: 15)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .appTypography(.panelTitle)
                            Text(item.detail)
                                .appTypography(.secondary)
                                .foregroundStyle(.secondary)
                            if !item.details.isEmpty {
                                LazyVGrid(
                                    columns: [
                                        GridItem(.adaptive(minimum: 210), spacing: 10, alignment: .leading)
                                    ],
                                    alignment: .leading,
                                    spacing: 6
                                ) {
                                    ForEach(item.details) { detail in
                                        HStack(spacing: 6) {
                                            Text(detail.title)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .foregroundStyle(.secondary)
                                            Spacer(minLength: 8)
                                            Text(detail.value)
                                                .font(appFont(.secondary).weight(.semibold).monospaced())
                                                .foregroundStyle(.primary)
                                        }
                                        .font(appFont(.secondary))
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                        Spacer()
                        Text(item.value)
                            .font(appFont(.body).weight(.semibold).monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppPalette.cardSurface))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppPalette.border, lineWidth: 1))
                }
            }
        }
    }

    private func dataQualityStatusTone(for tone: GrantDataStore.DataStructureDiagnosticItem.Tone) -> DataQualityStatusTone {
        switch tone {
        case .ok:
            return .ok
        case .warning:
            return .warning
        case .critical:
            return .critical
        }
    }

    @ViewBuilder
    private func revisionHistoryList(language: AppLanguage) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if revisionHistory.isEmpty {
                    Text(language.text("No recent changes", "Inga senaste ändringar"))
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(revisionHistory) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title)
                                    .appTypography(.panelTitle)
                                Text(entry.actionName)
                                    .appTypography(.secondary)
                                    .foregroundStyle(.secondary)
                                if let destination = entry.destination {
                                    Text(localizedDestinationName(destination, language: language))
                                        .appTypography(.secondary)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let destination = entry.destination,
                               let recordID = entry.recordID {
                                Button(language.text("Open", "Öppna")) {
                                    dismiss()
                                    store.openIssue(destination: destination, recordID: recordID)
                                }
                            }
                            Text(relativeDateString(entry.timestamp))
                                .appTypography(.secondary)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppPalette.cardSurface))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppPalette.border, lineWidth: 1))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func overviewBlockHeader(title: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        HStack {
            AppPanelHeadingText(text: title)
            Spacer()
            Button(buttonTitle, action: action)
        }
    }

    @ViewBuilder
    private func completenessRow(_ item: DataCompletenessSummaryItem, language: AppLanguage) -> some View {
        let percent = Int((item.completionFraction * 100).rounded())
        AppFieldSurfaceCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .appTypography(.panelTitle)
                    Spacer()
                    Text("\(percent)%")
                        .appTypography(.tableHeader)
                        .foregroundStyle(percent == 100 ? AppPalette.statusText(.done) : AppPalette.linkAction)
                }
                ProgressView(value: item.completionFraction)
                    .progressViewStyle(.linear)
                    .tint(percent == 100 ? AppPalette.statusText(.done) : AppPalette.linkAction)
                HStack {
                    Text(language.text(
                        "\(item.completeRecords) of \(item.totalRecords) complete",
                        "\(item.completeRecords) av \(item.totalRecords) kompletta"
                    ))
                    Spacer()
                    if item.flaggedRecords > 0 {
                        Text(language.text(
                            "\(item.flaggedRecords) flagged",
                            "\(item.flaggedRecords) flaggade"
                        ))
                    } else {
                        Text(language.text("No missing fields", "Inga saknade fält"))
                    }
                }
                .font(appFont(.secondary))
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func issueRow(title: String, subtitle: String, rightText: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        AppFieldSurfaceCard(padding: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .appTypography(.panelTitle)
                    if let subtitle = subtitle.nonEmpty {
                        Text(subtitle)
                            .appTypography(.secondary)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(rightText)
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
                Button(buttonTitle, action: action)
            }
        }
    }

    @ViewBuilder
    private func issueRow(title: String, subtitle: String, rightText: String, buttonTitle: String?, action: @escaping () -> Void) -> some View {
        AppFieldSurfaceCard(padding: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .appTypography(.panelTitle)
                    if let subtitle = subtitle.nonEmpty {
                        Text(subtitle)
                            .appTypography(.secondary)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(rightText)
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
                if let buttonTitle {
                    Button(buttonTitle, action: action)
                }
            }
        }
    }

    private func hiddenWarningBadge(language: AppLanguage) -> some View {
        Label(language.text("Hidden", "Dold"), systemImage: "eye.slash")
            .appTypography(.tableHeader)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppPalette.fieldSurface))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppPalette.subtleBorder, lineWidth: 1))
            .fixedSize()
    }

    private func matches(query: String, fields: [String]) -> Bool {
        let searchQuery = SearchFilterQuery(raw: query)
        guard !searchQuery.isEmpty else { return true }
        return searchQuery.matches(haystack: fields.joined(separator: " "))
    }

    private func totalRecordCount(for category: DataQualityCategory) -> Int {
        switch category {
        case .all:
            return DataQualityCategory.completenessCases.reduce(0) { $0 + totalRecordCount(for: $1) }
        case .applications:
            return store.applications.count
        case .projects:
            return store.projects.count
        case .organizations:
            return store.organizations.count
        case .researchers:
            return store.publicationAuthors.count
        case .journals:
            return store.publicationJournals.count
        case .publications:
            return store.publicationRecords.count
        case .teaching:
            return store.teachingCourses.count + store.teachingAssignments.count + store.doctoralCandidates.count
        }
    }

    private func matchesCategory(
        _ kind: GrantDataStore.MissingFieldIssue.EntityKind,
        in selectedCategory: DataQualityCategory
    ) -> Bool {
        switch selectedCategory {
        case .all:
            return true
        case .applications:
            return kind == .application
        case .projects:
            return kind == .project
        case .organizations:
            return kind == .organization
        case .researchers:
            return kind == .researcher
        case .journals:
            return kind == .journal
        case .publications:
            return kind == .publication
        case .teaching:
            return kind == .teaching
        }
    }

    private func matchesCategory(_ kind: GrantDataStore.MissingFieldIssue.EntityKind) -> Bool {
        matchesCategory(kind, in: category)
    }

    private func matchesCategory(_ kind: GrantDataStore.DuplicateIssue.GroupKind) -> Bool {
        switch category {
        case .all:
            return true
        case .applications:
            return false
        case .projects:
            return kind == .projects
        case .organizations:
            return kind == .funders
        case .researchers:
            return kind == .researchers
        case .journals:
            return kind == .journals
        case .publications:
            return kind == .publications
        case .teaching:
            return false
        }
    }

    private func matchesCategory(_ destination: AppRoute.Destination) -> Bool {
        switch category {
        case .all:
            return true
        case .applications:
            return destination == .applications
        case .organizations where destination == .congresses:
            return true
        case .projects:
            return destination == .projects
        case .organizations:
            return destination == .organizations
        case .researchers:
            return destination == .people
        case .journals:
            return destination == .journals
        case .publications:
            return destination == .publications
        case .teaching:
            return destination == .teaching
        }
    }

    private func matchesRevisionCategory(_ destination: AppRoute.Destination?) -> Bool {
        guard let destination else { return category == .all }
        return matchesCategory(destination)
    }

    private func matchesArchivedCategory(_ kind: String) -> Bool {
        switch category {
        case .all:
            return true
        case .applications:
            return kind == "application"
        case .projects:
            return kind == "project"
        case .organizations:
            return kind == "organization"
        case .researchers:
            return kind == "publication_author"
        case .journals:
            return kind == "publication_journal"
        case .publications:
            return kind == "publication_record"
        case .teaching:
            return kind.hasPrefix("teaching_")
        }
    }

    private func relativeDateString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: store.language == .swedish ? "sv_SE" : "en_US")
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func localizedDestinationName(_ destination: AppRoute.Destination, language: AppLanguage) -> String {
        switch destination {
        case .applications:
            return language.text("Applications", "Ansökningar")
        case .congresses:
            return language.text("Congresses", "Kongresser")
        case .cv:
            return "CV"
        case .expertAssignments:
            return language.text("Expert assignments", "Sakkunniguppdrag")
        case .publications:
            return language.text("Publications", "Publikationer")
        case .projects:
            return language.text("Projects", "Projekt")
        case .teaching:
            return language.text("Teaching", "Undervisning")
        case .doctoralCandidates:
            return language.text("Doctoral candidates", "Doktorander")
        case .organizations:
            return language.text("Organizations", "Organisationer")
        case .people:
            return language.text("Researchers", "Forskare")
        case .journals:
            return language.text("Journals", "Tidskrifter")
        }
    }
}

private struct DuplicateMergeAssistantSheet: View {
    @ObservedObject var store: GrantDataStore
    let issue: GrantDataStore.DuplicateIssue
    let onClose: () -> Void
    @State private var canonicalRecordID: String

    init(
        store: GrantDataStore,
        issue: GrantDataStore.DuplicateIssue,
        onClose: @escaping () -> Void
    ) {
        self.store = store
        self.issue = issue
        self.onClose = onClose
        _canonicalRecordID = State(initialValue: issue.entries.first?.recordID ?? "")
    }

    private var duplicateEntries: [GrantDataStore.DuplicateEntry] {
        issue.entries.filter { $0.recordID != canonicalRecordID }
    }

    var body: some View {
        let language = store.language

        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(language.text("Merge duplicate records", "Slå ihop dublettposter"))
                    .appTypography(.sectionTitle)
                Text(language.text(
                    "Choose the record that should remain. Links are moved to that record and the other records are archived unchanged.",
                    "Välj posten som ska vara kvar. Kopplingar flyttas till den posten och övriga poster arkiveras oförändrade."
                ))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)
            }

            Text(issue.title)
                .appTypography(.panelTitle)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(issue.entries) { entry in
                        Button {
                            canonicalRecordID = entry.recordID
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: entry.recordID == canonicalRecordID ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(entry.recordID == canonicalRecordID ? AppPalette.linkAction : .secondary)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(entry.title)
                                            .appTypography(.tableHeader)
                                        if entry.recordID == canonicalRecordID {
                                            Text(language.text("Keep", "Behåll"))
                                                .appTypography(.tableHeader)
                                                .foregroundStyle(AppPalette.linkAction)
                                        }
                                    }
                                    if let subtitle = entry.subtitle.nonEmpty {
                                        Text(subtitle)
                                            .appTypography(.secondary)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(entry.recordID == canonicalRecordID ? AppPalette.activeTabSurface.opacity(0.16) : AppPalette.fieldSurface)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minHeight: 180, maxHeight: 300)

            Text(language.text(
                "\(duplicateEntries.count) record(s) will be archived.",
                "\(duplicateEntries.count) post(er) arkiveras."
            ))
            .appTypography(.secondary)
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(language.text("Cancel", "Avbryt")) {
                    onClose()
                }
                Button(language.text("Merge duplicates", "Slå ihop dubletter")) {
                    let success = store.mergeDuplicateRecords(
                        groupKind: issue.groupKind,
                        canonicalRecordID: canonicalRecordID,
                        duplicateRecordIDs: duplicateEntries.map(\.recordID)
                    )
                    if success {
                        onClose()
                    }
                }
                .appSaveButtonStyle()
                .disabled(canonicalRecordID.isEmpty || duplicateEntries.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}

private struct IssueFieldBadges: View {
    let fields: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(fields, id: \.self) { field in
                AppTextPill(
                    text: field,
                    background: AppPalette.pillSurface.opacity(0.8),
                    stroke: AppPalette.border.opacity(0.25)
                )
            }
        }
    }
}

private struct IssueSeverityBadge: View {
    let severity: GrantDataStore.MissingFieldIssue.Severity
    let language: AppLanguage

    private var title: String {
        switch severity {
        case .critical:
            return language.text("Critical", "Kritisk")
        case .warning:
            return language.text("Warning", "Varning")
        }
    }

    private var fill: Color {
        switch severity {
        case .critical:
            return AppPalette.statusFill(.negative).opacity(0.22)
        case .warning:
            return AppPalette.pillSurface.opacity(0.9)
        }
    }

    private var textColor: Color {
        switch severity {
        case .critical:
            return AppPalette.statusText(.negative)
        case .warning:
            return AppPalette.statusText(.warning)
        }
    }

    var body: some View {
        AppToneBadge(
            text: title,
            foreground: textColor,
            background: fill,
            stroke: textColor.opacity(0.24),
            horizontalPadding: 10,
            verticalPadding: 5,
            showsIndicator: true,
            indicatorColor: textColor
        )
        .help(title)
    }
}

// Permanent archive deletion is the one delete in the app that no backup
// undoes from the UI; it must never fire from a single stray click.
private struct ArchivePermanentDeleteIconButton: View {
    let language: AppLanguage
    let action: () -> Void
    @State private var showsConfirmation = false

    var body: some View {
        Button(role: .destructive) {
            showsConfirmation = true
        } label: {
            Image(systemName: "trash")
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.borderless)
        .help(language.text("Delete permanently", "Ta bort permanent"))
        .accessibilityLabel(language.text("Delete permanently", "Ta bort permanent"))
        .confirmationDialog(
            language.text("Delete archived record permanently?", "Ta bort arkiverad post permanent?"),
            isPresented: $showsConfirmation,
            titleVisibility: .visible
        ) {
            Button(language.text("Delete", "Ta bort"), role: .destructive, action: action)
            Button(language.text("Cancel", "Avbryt"), role: .cancel) {}
        }
    }
}

// MARK: - Translations section

extension DataMaintenanceWorkspaceView {
    /// F12: one row per bilingual field, Swedish on the left and English on
    /// the right. Editing a cell saves the record directly; the row goes away
    /// once the field is translated.
    @ViewBuilder
    func translationsSectionContent(language: AppLanguage) -> some View {
        let issues = store.translationIssues(includeHidden: showHiddenWarnings)
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text(
                "Fields where one language is empty, or where the English text is the same as the Swedish. Type directly in the cells: the record is saved when you press Return or move to another field, exactly as when you edit the record itself. Hide marks a field as intentionally like this.",
                "Fält där ena språket är tomt, eller där den engelska texten är samma som den svenska. Skriv direkt i rutorna: posten sparas när du trycker Retur eller går till ett annat fält, precis som när du redigerar själva posten. Dölj markerar ett fält som avsiktligt så här."
            ))
            .appTypography(.secondary)
            .foregroundStyle(.secondary)

            if issues.isEmpty {
                HStack(spacing: 10) {
                    DataQualityStatusIcon(tone: .ok, size: 15)
                    Text(language.text("Everything is translated.", "Allt är översatt."))
                        .appTypography(.body)
                    Spacer()
                }
                .padding(10)
            } else {
                HStack(spacing: 10) {
                    Text(language.text("Record and field", "Post och fält"))
                        .appTypography(.tableHeader)
                        .frame(width: TranslationFixRow.recordColumnWidth, alignment: .leading)
                    Text(language.text("Swedish", "Svenska"))
                        .appTypography(.tableHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(width: 20, height: 1)
                    Text(language.text("English", "Engelska"))
                        .appTypography(.tableHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(width: TranslationFixRow.actionColumnWidth, height: 1)
                }
                .padding(.horizontal, 12)

                LazyVStack(spacing: 0) {
                    ForEach(Array(issues.enumerated()), id: \.element.id) { index, issue in
                        TranslationFixRow(
                            store: store,
                            issue: issue,
                            isHidden: store.isDataQualityWarningHidden(issue),
                            language: language,
                            onOpen: translationOpenAction(for: issue)
                        )
                        if index < issues.count - 1 {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppPalette.secondaryCardSurface))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppPalette.subtleBorder.opacity(0.7), lineWidth: 1))
            }
        }
    }

    /// Clicking the record title opens the record, like the other rows in
    /// the Data view. Records without a page of their own get no link.
    private func translationOpenAction(for issue: GrantDataStore.TranslationIssue) -> (() -> Void)? {
        guard let destination = issue.destination else { return nil }
        let recordID = issue.routeRecordID
        return {
            dismiss()
            store.openIssue(destination: destination, recordID: recordID)
        }
    }
}

private struct TranslationFixRow: View {
    static let recordColumnWidth: CGFloat = 230
    static let actionColumnWidth: CGFloat = 72

    private enum Side: Hashable {
        case swedish
        case english
    }

    let store: GrantDataStore
    let issue: GrantDataStore.TranslationIssue
    let isHidden: Bool
    let language: AppLanguage
    let onOpen: (() -> Void)?
    @State private var draftSv: String
    @State private var draftEn: String
    @FocusState private var focusedSide: Side?

    init(
        store: GrantDataStore,
        issue: GrantDataStore.TranslationIssue,
        isHidden: Bool,
        language: AppLanguage,
        onOpen: (() -> Void)?
    ) {
        self.store = store
        self.issue = issue
        self.isHidden = isHidden
        self.language = language
        self.onOpen = onOpen
        _draftSv = State(initialValue: issue.valueSv)
        _draftEn = State(initialValue: issue.valueEn)
    }

    private var fieldLabel: String {
        issue.fieldLabel(language: language)
    }

    private var hideTitle: String {
        isHidden ? language.text("Show again", "Visa igen") : language.text("Hide", "Dölj")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                recordTitleView
                Text("\(issue.kindTitle(language: language)) · \(fieldLabel)")
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(
                    isHidden
                        ? "\(language.text("Hidden", "Dold")) · \(issue.reasonText(language: language))"
                        : issue.reasonText(language: language)
                )
                .appTypography(.secondary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(width: Self.recordColumnWidth, alignment: .leading)

            TextField(language.text("Swedish", "Svenska"), text: $draftSv)
                .appTextInputChrome()
                .focused($focusedSide, equals: .swedish)
                .onSubmit(save)
                .accessibilityLabel(language.text("Swedish: \(fieldLabel)", "Svenska: \(fieldLabel)"))

            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            TextField(language.text("English", "Engelska"), text: $draftEn)
                .appTextInputChrome()
                .focused($focusedSide, equals: .english)
                .onSubmit(save)
                .accessibilityLabel(language.text("English: \(fieldLabel)", "Engelska: \(fieldLabel)"))

            Button(action: toggleHidden) {
                Text(hideTitle)
                    .font(appFont(.secondary).weight(.semibold))
                    .frame(height: 22)
            }
            .buttonStyle(.borderless)
            .help(
                isHidden
                    ? language.text("Show again", "Visa igen")
                    : language.text("Hide: the field is intentionally like this", "Dölj: fältet är avsiktligt så här")
            )
            .accessibilityLabel(hideTitle)
            .frame(width: Self.actionColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHidden ? AppPalette.fieldSurface.opacity(0.42) : Color.clear)
        .contextMenu {
            if let onOpen {
                Button(language.text("Open the record", "Öppna posten"), action: onOpen)
            }
            if isHidden {
                Button(language.text("Show again", "Visa igen"), action: toggleHidden)
            } else {
                if issue.reason == .identical {
                    Button(language.text("✓ Intentionally identical", "✓ Avsiktligt likadant"), action: toggleHidden)
                }
                Button(language.text("Hide", "Dölj"), action: toggleHidden)
            }
        }
        // Leaving a cell saves it, like the record's own editor.
        .onChange(of: focusedSide) { oldValue, newValue in
            if oldValue != nil, oldValue != newValue {
                save()
            }
        }
        .onChange(of: issue.valueSv) { _, value in
            if focusedSide != .swedish {
                draftSv = value
            }
        }
        .onChange(of: issue.valueEn) { _, value in
            if focusedSide != .english {
                draftEn = value
            }
        }
    }

    @ViewBuilder
    private var recordTitleView: some View {
        if let onOpen {
            Button(action: onOpen) {
                Text(issue.recordTitle)
                    .appTypography(.tableHeader)
                    .foregroundStyle(AppPalette.linkAction)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .buttonStyle(.plain)
            .help(language.text("Open the record", "Öppna posten"))
        } else {
            Text(issue.recordTitle)
                .appTypography(.tableHeader)
                .foregroundStyle(AppPalette.appText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func toggleHidden() {
        if isHidden {
            store.showDataQualityWarning(issue)
        } else {
            store.hideDataQualityWarning(issue)
        }
    }

    /// Saves what was typed. A cell that was emptied keeps its old text:
    /// this list only adds translations, it never erases a name.
    private func save() {
        let newSv = draftSv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? issue.valueSv : draftSv
        let newEn = draftEn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? issue.valueEn : draftEn
        guard newSv != issue.valueSv || newEn != issue.valueEn else { return }
        store.saveTranslation(for: issue, sv: newSv, en: newEn)
    }
}

// MARK: - Names to link section

extension DataMaintenanceWorkspaceView {
    /// F13c: one row per person name that no researcher answers to, with how
    /// many records use it and where. The name can be linked to a researcher,
    /// become a new researcher, or be hidden.
    @ViewBuilder
    func nameLinksSectionContent(language: AppLanguage) -> some View {
        let names = store.unlinkedPersonNames(includeHidden: showHiddenWarnings)
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text(
                "Names written in records that do not match any researcher. Link a name to the researcher it belongs to and it is recognized from then on, create a new researcher with the name, or hide names that should stay as they are.",
                "Namn som står i poster men inte hör ihop med någon forskare. Koppla namnet till rätt forskare så känns det igen från och med nu, skapa en ny forskare med namnet, eller dölj namn som ska vara som de är."
            ))
            .appTypography(.secondary)
            .foregroundStyle(.secondary)

            if names.isEmpty {
                HStack(spacing: 10) {
                    DataQualityStatusIcon(tone: .ok, size: 15)
                    Text(language.text("All names are linked.", "Alla namn är kopplade."))
                        .appTypography(.body)
                    Spacer()
                }
                .padding(10)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(names.enumerated()), id: \.element.id) { index, entry in
                        NameLinkRow(
                            store: store,
                            entry: entry,
                            isHidden: store.isDataQualityWarningHidden(entry),
                            language: language,
                            onOpenUsage: { usage in
                                openNameLinkUsage(usage)
                            }
                        )
                        if index < names.count - 1 {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppPalette.secondaryCardSurface))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppPalette.subtleBorder.opacity(0.7), lineWidth: 1))
            }
        }
    }

    /// Clicking a usage opens the first record of that kind, like the other
    /// rows in the Data view. Meetings and central tasks have no page of
    /// their own and are not clickable.
    private func openNameLinkUsage(_ usage: GrantDataStore.UnlinkedPersonName.Usage) {
        guard let destination = usage.destination else { return }
        dismiss()
        store.openIssue(destination: destination, recordID: usage.routeRecordID)
    }
}

private struct NameLinkRow: View {
    static let actionColumnWidth: CGFloat = 72

    let store: GrantDataStore
    let entry: GrantDataStore.UnlinkedPersonName
    let isHidden: Bool
    let language: AppLanguage
    let onOpenUsage: (GrantDataStore.UnlinkedPersonName.Usage) -> Void
    @State private var showsResearcherPicker = false

    private var hideTitle: String {
        isHidden ? language.text("Show again", "Visa igen") : language.text("Hide", "Dölj")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .appTypography(.tableHeader)
                    .foregroundStyle(AppPalette.appText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                usageLine
                if isHidden {
                    Text(language.text("Hidden", "Dold"))
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showsResearcherPicker = true
            } label: {
                Text(language.text("Link to…", "Koppla till…"))
                    .font(appFont(.secondary).weight(.semibold))
                    .frame(height: 22)
            }
            .buttonStyle(.borderless)
            .help(language.text(
                "Link the name to an existing researcher. The name is added as one of the researcher's name variants.",
                "Koppla namnet till en befintlig forskare. Namnet läggs till som en av forskarens namnvarianter."
            ))
            .popover(isPresented: $showsResearcherPicker, arrowEdge: .bottom) {
                NameLinkResearcherPicker(
                    store: store,
                    writtenName: entry.name,
                    language: language,
                    onPick: { authorID in
                        showsResearcherPicker = false
                        store.linkPersonName(entry.name, toAuthorID: authorID)
                    }
                )
            }

            Button {
                _ = store.createResearcher(forUnlinkedName: entry.name)
            } label: {
                Text(language.text("New researcher", "Ny forskare"))
                    .font(appFont(.secondary).weight(.semibold))
                    .frame(height: 22)
            }
            .buttonStyle(.borderless)
            .help(language.text(
                "Create a new researcher with this name.",
                "Skapa en ny forskare med det här namnet."
            ))

            Button(action: toggleHidden) {
                Text(hideTitle)
                    .font(appFont(.secondary).weight(.semibold))
                    .frame(height: 22)
            }
            .buttonStyle(.borderless)
            .help(
                isHidden
                    ? language.text("Show again", "Visa igen")
                    : language.text("Hide: the name should stay as it is", "Dölj: namnet ska vara som det är")
            )
            .accessibilityLabel(hideTitle)
            .frame(width: Self.actionColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHidden ? AppPalette.fieldSurface.opacity(0.42) : Color.clear)
        .contextMenu {
            Button(language.text("Link to…", "Koppla till…")) {
                showsResearcherPicker = true
            }
            Button(language.text("New researcher", "Ny forskare")) {
                _ = store.createResearcher(forUnlinkedName: entry.name)
            }
            Button(hideTitle, action: toggleHidden)
        }
    }

    /// "3 applications, 1 project"; each part opens the first such record.
    private var usageLine: some View {
        HStack(spacing: 0) {
            ForEach(Array(entry.usages.enumerated()), id: \.element.kind) { index, usage in
                usageSegment(usage)
                if index < entry.usages.count - 1 {
                    Text(", ")
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }

    @ViewBuilder
    private func usageSegment(_ usage: GrantDataStore.UnlinkedPersonName.Usage) -> some View {
        let text = usage.kind.countText(usage.count, language: language)
        if usage.destination != nil {
            Button {
                onOpenUsage(usage)
            } label: {
                Text(text)
                    .appTypography(.secondary)
                    .foregroundStyle(AppPalette.linkAction)
            }
            .buttonStyle(.plain)
            .help(language.text("Open the first record", "Öppna den första posten"))
        } else {
            Text(text)
                .appTypography(.secondary)
                .foregroundStyle(.secondary)
        }
    }

    private func toggleHidden() {
        if isHidden {
            store.showDataQualityWarning(entry)
        } else {
            store.hideDataQualityWarning(entry)
        }
    }
}

/// The searchable list of researchers behind "Link to…".
private struct NameLinkResearcherPicker: View {
    private struct Option: Identifiable {
        let id: String
        let title: String
        let detail: String
    }

    let store: GrantDataStore
    let writtenName: String
    let language: AppLanguage
    let onPick: (String) -> Void
    @State private var query: String

    init(store: GrantDataStore, writtenName: String, language: AppLanguage, onPick: @escaping (String) -> Void) {
        self.store = store
        self.writtenName = writtenName
        self.language = language
        self.onPick = onPick
        _query = State(initialValue: Self.suggestedQuery(for: writtenName))
    }

    /// Starts the search on the longest word of the written name, usually
    /// the surname, so the likely researcher is at the top.
    private static func suggestedQuery(for name: String) -> String {
        let words = name
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { !$0.isEmpty }
        return words.max(by: { $0.count < $1.count }) ?? ""
    }

    private var matchingOptions: [Option] {
        // Same search rules as the lists: accents ignored ("Ostergren" finds
        // "Östergren"), several words must all match, "-word" excludes.
        let searchQuery = SearchFilterQuery(raw: query)
        var result: [Option] = []
        for author in store.publicationAuthors {
            let title = author.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let variants = author.nameVariants
            if !searchQuery.isEmpty,
               !searchQuery.matches(haystack: ([title] + variants).joined(separator: " ")) {
                continue
            }
            result.append(Option(id: author.id, title: title, detail: variants.prefix(3).joined(separator: ", ")))
        }
        return result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        let options = matchingOptions
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text("Link “\(writtenName)” to", "Koppla ”\(writtenName)” till"))
                .appTypography(.tableHeader)
                .lineLimit(1)
                .truncationMode(.tail)
            TextField(language.text("Search researchers", "Sök forskare"), text: $query)
                .appTextInputChrome()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if options.isEmpty {
                        Text(language.text("No researcher matches.", "Ingen forskare matchar."))
                            .appTypography(.secondary)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                    ForEach(options) { option in
                        Button {
                            onPick(option.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.title)
                                    .appTypography(.body)
                                    .foregroundStyle(AppPalette.appText)
                                    .lineLimit(1)
                                if !option.detail.isEmpty {
                                    Text(option.detail)
                                        .appTypography(.secondary)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 260)
        }
        .padding(12)
        .frame(width: 320)
    }
}

// MARK: - Activities to link to a doctoral candidate (round 7)

extension DataMaintenanceWorkspaceView {
    /// Round 7 (user decision): activities that the doctoral candidate page
    /// used to show through the candidate's project or name, but that are
    /// not linked to the candidate. Each can be linked or hidden; nothing is
    /// linked automatically.
    @ViewBuilder
    func doctoralActivityLinksSectionContent(language: AppLanguage) -> some View {
        let suggestions = store.doctoralActivityLinkSuggestions(includeHidden: showHiddenWarnings)
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text(
                "The doctoral candidate page now shows only activities that are linked to the candidate. These activities were shown there before because of the candidate's project or name. Link the ones that belong to the candidate, and hide the others.",
                "Doktorandsidan visar nu bara aktiviteter som är kopplade till doktoranden. De här aktiviteterna visades där tidigare för att de hör till doktorandens projekt eller har doktorandens namn bland deltagarna. Koppla de som hör till doktoranden och dölj de andra."
            ))
            .appTypography(.secondary)
            .foregroundStyle(.secondary)

            if suggestions.isEmpty {
                HStack(spacing: 10) {
                    DataQualityStatusIcon(tone: .ok, size: 15)
                    Text(language.text("Nothing to link.", "Inget att koppla."))
                        .appTypography(.body)
                    Spacer()
                }
                .padding(10)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        DoctoralActivityLinkRow(
                            store: store,
                            suggestion: suggestion,
                            isHidden: store.isDataQualityWarningHidden(suggestion),
                            language: language,
                            onOpen: {
                                openSuggestedActivity(suggestion)
                            }
                        )
                        if index < suggestions.count - 1 {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppPalette.secondaryCardSurface))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppPalette.subtleBorder.opacity(0.7), lineWidth: 1))
            }
        }
    }

    /// Clicking the activity shows it in the calendar.
    private func openSuggestedActivity(_ suggestion: DoctoralActivityLinkSuggestion) {
        guard let date = DateParsers.isoDay.date(from: suggestion.date) else { return }
        dismiss()
        store.revealCalendarWorkspace(on: date, eventSource: .meeting(suggestion.meetingID))
    }
}

private struct DoctoralActivityLinkRow: View {
    static let actionColumnWidth: CGFloat = 72

    let store: GrantDataStore
    let suggestion: DoctoralActivityLinkSuggestion
    let isHidden: Bool
    let language: AppLanguage
    let onOpen: () -> Void

    private var hideTitle: String {
        isHidden ? language.text("Show again", "Visa igen") : language.text("Hide", "Dölj")
    }

    private var reasonText: String {
        switch (suggestion.matchedByProject, suggestion.matchedByName) {
        case (true, true):
            return language.text("the candidate's project and name", "doktorandens projekt och namn")
        case (true, false):
            return language.text("the candidate's project", "doktorandens projekt")
        default:
            return language.text("the candidate's name among the participants", "doktorandens namn bland deltagarna")
        }
    }

    private var headline: String {
        let date = suggestion.date.nonEmpty ?? "–"
        let title = suggestion.title.nonEmpty ?? language.text("Activity", "Aktivitet")
        return "\(date)  \(title)"
    }

    private var detailLine: String {
        language.text(
            "Doctoral candidate: \(suggestion.candidateName) · found through \(reasonText)",
            "Doktorand: \(suggestion.candidateName) · hittad via \(reasonText)"
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Button(action: onOpen) {
                    Text(headline)
                        .appTypography(.tableHeader)
                        .foregroundStyle(AppPalette.appText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .buttonStyle(.plain)
                .help(language.text("Show the activity in the calendar", "Visa aktiviteten i kalendern"))
                Text(detailLine)
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if isHidden {
                    Text(language.text("Hidden", "Dold"))
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: link) {
                Text(language.text("Link", "Koppla"))
                    .font(appFont(.secondary).weight(.semibold))
                    .frame(height: 22)
            }
            .buttonStyle(.borderless)
            .help(language.text(
                "Link the activity to the doctoral candidate. Can be undone.",
                "Koppla aktiviteten till doktoranden. Går att ångra."
            ))

            Button(action: toggleHidden) {
                Text(hideTitle)
                    .font(appFont(.secondary).weight(.semibold))
                    .frame(height: 22)
            }
            .buttonStyle(.borderless)
            .help(
                isHidden
                    ? language.text("Show again", "Visa igen")
                    : language.text("Hide: the activity does not belong to the candidate", "Dölj: aktiviteten hör inte till doktoranden")
            )
            .accessibilityLabel(hideTitle)
            .frame(width: Self.actionColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHidden ? AppPalette.fieldSurface.opacity(0.42) : Color.clear)
    }

    private func link() {
        store.linkSuggestedDoctoralActivity(suggestion)
    }

    private func toggleHidden() {
        if isHidden {
            store.showDataQualityWarning(suggestion)
        } else {
            store.hideDataQualityWarning(suggestion)
        }
    }
}
