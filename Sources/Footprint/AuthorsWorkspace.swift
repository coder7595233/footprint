import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

func publicationAuthorLinkedDateRangeText(
    from rawFrom: String,
    to rawTo: String,
    language: AppLanguage,
    emptyText: String = "-"
) -> String {
    let from = rawFrom.trimmingCharacters(in: .whitespacesAndNewlines)
    let to = rawTo.trimmingCharacters(in: .whitespacesAndNewlines)
    let fromDate = publicationAuthorLinkedDate(from)
    let toDate = publicationAuthorLinkedDate(to)

    switch (fromDate, toDate) {
    case let (start?, end?):
        return publicationAuthorLinkedDateRangeText(start: start, end: end, language: language)
    case let (start?, nil):
        return publicationAuthorLinkedDateText(start, language: language)
    case let (nil, end?):
        return publicationAuthorLinkedDateText(end, language: language)
    default:
        switch (from.nonEmpty, to.nonEmpty) {
        case let (start?, end?) where start != end:
            return "\(start)-\(end)"
        case let (start?, _):
            return start
        case let (_, end?):
            return end
        default:
            return emptyText
        }
    }
}

private func publicationAuthorLinkedDate(_ raw: String) -> Date? {
    let canonical = DateParsers.canonicalizedDayInput(raw)
    return DateParsers.isoDay.date(from: canonical)
}

private func publicationAuthorLinkedDateRangeText(
    start: Date,
    end: Date,
    language: AppLanguage
) -> String {
    let calendar = Calendar.current
    let startComponents = calendar.dateComponents([.day, .month, .year], from: start)
    let endComponents = calendar.dateComponents([.day, .month, .year], from: end)
    guard let startDay = startComponents.day,
          let startMonth = startComponents.month,
          let startYear = startComponents.year,
          let endDay = endComponents.day,
          let endMonth = endComponents.month,
          let endYear = endComponents.year else {
        return "\(DateParsers.isoDay.string(from: start))-\(DateParsers.isoDay.string(from: end))"
    }

    if startDay == endDay && startMonth == endMonth && startYear == endYear {
        return publicationAuthorLinkedDateText(start, language: language)
    }
    if startMonth == endMonth && startYear == endYear {
        return "\(startDay)-\(endDay) \(publicationAuthorLinkedMonthName(startMonth, language: language)) \(startYear)"
    }
    if startYear == endYear {
        return "\(startDay) \(publicationAuthorLinkedMonthName(startMonth, language: language))-\(endDay) \(publicationAuthorLinkedMonthName(endMonth, language: language)) \(startYear)"
    }
    return [
        publicationAuthorLinkedDateText(start, language: language),
        publicationAuthorLinkedDateText(end, language: language)
    ].joined(separator: "-")
}

private func publicationAuthorLinkedDateText(_ date: Date, language: AppLanguage) -> String {
    let components = Calendar.current.dateComponents([.day, .month, .year], from: date)
    guard let day = components.day,
          let month = components.month,
          let year = components.year else {
        return DateParsers.isoDay.string(from: date)
    }
    return "\(day) \(publicationAuthorLinkedMonthName(month, language: language)) \(year)"
}

private func publicationAuthorLinkedMonthName(_ month: Int, language: AppLanguage) -> String {
    let swedish = [
        "januari", "februari", "mars", "april", "maj", "juni",
        "juli", "augusti", "september", "oktober", "november", "december"
    ]
    let english = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]
    let names = language == .swedish ? swedish : english
    guard names.indices.contains(month - 1) else { return "\(month)" }
    return names[month - 1]
}

enum PublicationAuthorListSortColumn: String, Hashable {
    case name
    case organization
    case project
    case grants
    case publications
    case dissemination
    case expertAssignments
    case teaching

    var defaultAscending: Bool {
        switch self {
        case .name, .organization:
            return true
        case .project, .grants, .publications, .dissemination, .expertAssignments, .teaching:
            return false
        }
    }
}

struct PublicationAuthorListSortCriterion: AppListSortCriterion {
    let column: PublicationAuthorListSortColumn
    var ascending: Bool
}

func publicationAuthorSortComparators(
    for column: PublicationAuthorListSortColumn,
    ascending: Bool
) -> [KeyPathComparator<PublicationAuthorRowSnapshot>] {
    let order: SortOrder = ascending ? .forward : .reverse

    switch column {
    case .name:
        return [
            KeyPathComparator(\PublicationAuthorRowSnapshot.sortName, order: order),
        ]
    case .organization:
        return [
            KeyPathComparator(\PublicationAuthorRowSnapshot.sortOrganization, order: order),
        ]
    case .project:
        return [
            KeyPathComparator(\PublicationAuthorRowSnapshot.projectCount, order: order),
        ]
    case .grants:
        return [
            KeyPathComparator(\PublicationAuthorRowSnapshot.grantCount, order: order),
        ]
    case .publications:
        return [
            KeyPathComparator(\PublicationAuthorRowSnapshot.publicationCount, order: order),
        ]
    case .dissemination:
        return [
            KeyPathComparator(\PublicationAuthorRowSnapshot.disseminationCount, order: order),
        ]
    case .expertAssignments:
        return [
            KeyPathComparator(\PublicationAuthorRowSnapshot.expertAssignmentCount, order: order),
        ]
    case .teaching:
        return [
            KeyPathComparator(\PublicationAuthorRowSnapshot.teachingCount, order: order),
        ]
    }
}

struct PublicationAuthorsView: View {
    let store: GrantDataStore
    @StateObject private var linkedDataCache = PublicationAuthorLinkedDataCacheStore()
    let newRecordTrigger: Int
    let isActive: Bool
    @WorkspaceFilterState("Researchers.Filter.Search") private var searchText = ""
    @WorkspaceFilterState("Researchers.Filter.Organizations") private var organizationFilters: Set<String> = []
    @WorkspaceFilterState("Researchers.Filter.Countries") private var countryFilters: Set<String> = []
    @WorkspaceFilterState("Researchers.Filter.CurrentUser") private var showsOnlyCurrentUserAuthor = false
    @WorkspaceFilterState("Researchers.Filter.ActiveOnly") private var showsOnlyActiveAuthors = false
    @WorkspaceFilterState("Researchers.Filter.HasPublications") private var showsOnlyAuthorsWithPublications = false
    @State private var selectedAuthorID: String?
    @State private var detailAuthorID: String?
    @State private var authorRows: [PublicationAuthorRowSnapshot] = []
    @State private var filteredAuthorRows: [PublicationAuthorRowSnapshot] = []
    @State private var organizationOptionsCache: [String] = []
    @State private var countryOptionsCache: [String] = []
    @State private var authorRowsRebuildTask: DispatchWorkItem?
    @State private var authorFilterRebuildTask: DispatchWorkItem?
    @State private var pendingSelectionMeasurementID: String?
    @State private var pendingSelectionStartedAt: CFAbsoluteTime?
    @State private var baseFilteredAuthorRows: [PublicationAuthorRowSnapshot] = []
    @State private var lastAuthorSearchQuery = SearchFilterQuery(raw: "")
    @State private var lastAuthorNonSearchFilterSignature = ""
    @State private var authorRowsAppliedGeneration = 0
    @State private var authorSelectionCoordinator = AppSelectionCoordinator<String>()
    @State private var authorSortHistory: [PublicationAuthorListSortCriterion] = ListSortPersistence.load(
        defaultsKey: "PublicationAuthorsListSort",
        defaultValue: [PublicationAuthorListSortCriterion(column: .name, ascending: true)]
    )
    @State private var needsAuthorRowsRefreshWhenActive = false
    @State private var needsAuthorFilterRebuildWhenActive = false
    @State private var pendingRouteAuthorID: String?

    private enum AuthorAffiliationTone {
        case sweden
        case europe
        case international

        var background: Color? {
            switch self {
            case .sweden:
                return nil
            case .europe:
                return AppPalette.vividYellow.opacity(0.55)
            case .international:
                return AppPalette.vividGreen.opacity(0.45)
            }
        }
    }

    private var authorSelectionBinding: Binding<String?> {
        return Binding(
            get: { selectedAuthorID },
            set: { newValue in
                handleAuthorSelectionCandidate(newValue)
            }
        )
    }

    private var organizationOptions: [String] {
        organizationOptionsCache
    }

    private var countryOptions: [String] {
        countryOptionsCache
    }

    private var sortOrder: [KeyPathComparator<PublicationAuthorRowSnapshot>] {
        var columns = authorSortHistory.map(\.column)
        for fallbackColumn in [
            PublicationAuthorListSortColumn.name,
            .organization,
            .publications,
            .project,
            .grants,
            .dissemination,
            .expertAssignments,
            .teaching
        ] where !columns.contains(fallbackColumn) {
            columns.append(fallbackColumn)
        }

        return columns.flatMap { column in
            let ascending = authorSortHistory.first(where: { $0.column == column })?.ascending ?? column.defaultAscending
            return publicationAuthorSortComparators(for: column, ascending: ascending)
        }
    }

    private var authorSortSignature: String {
        authorSortHistory
            .map { "\($0.column.rawValue):\($0.ascending ? "asc" : "desc")" }
            .joined(separator: "|")
    }

    private var hasActiveAuthorFilters: Bool {
        searchText.nonEmpty != nil
            || !organizationFilters.isEmpty
            || !countryFilters.isEmpty
            || showsOnlyCurrentUserAuthor
            || showsOnlyActiveAuthors
            || showsOnlyAuthorsWithPublications
            || store.personIncompleteDataFilter != .none
    }

    var body: some View {
        let language = store.language

        PersistentSplitView(
            layout: .publicationAuthors,
            updateStrategy: .simultaneous
        ) {
            AppWorkspaceSidebar {
                VStack(alignment: .leading, spacing: 10) {
                    AppWorkspaceSidebarHeader(
                        title: language.text("Researchers", "Forskare"),
                        actionTitle: language.text("New researcher", "Ny forskare")
                    ) {
                        setSelectedAuthorID(store.addPublicationAuthor(), armLock: true)
                    }
                    .frame(minHeight: 42)

                    authorFilterBar(language: language)

                    authorResultsTable(language: language)

                    ListCountFootnote(displayedCount: filteredAuthorRows.count, totalCount: store.coauthors.count, language: language)
                }
            }
            .onAppear {
                let onAppearStartedAt = CFAbsoluteTimeGetCurrent()
                store.appendPerformanceDiagnostic("coauthors-view-onAppear-start")
                guard isActive else {
                    needsAuthorRowsRefreshWhenActive = true
                    needsAuthorFilterRebuildWhenActive = true
                    return
                }
                if let route = store.route, route.destination == .people {
                    applyRouteSelection(route.recordID)
                    store.consumeRoute()
                    let onAppearDuration = (CFAbsoluteTimeGetCurrent() - onAppearStartedAt) * 1000
                    store.appendPerformanceDiagnostic(
                        String(
                            format: "coauthors-view-onAppear-route ready_ms=%.2f selected=%@",
                            onAppearDuration,
                            selectedAuthorID ?? "-"
                        )
                    )
                    return
                }
                if selectedAuthorID == nil {
                    setSelectedAuthorID(
                        store.lastSelectedRecordID(for: .people)
                            ?? store.publicationAuthorRowSnapshots().first?.id
                    )
                }
                rebuildAuthorRows()
                rebuildFilteredAuthorRows(reason: "initial")
                if selectedAuthorID == nil {
                    setSelectedAuthorID(filteredAuthorRows.first?.id)
                }
                let onAppearDuration = (CFAbsoluteTimeGetCurrent() - onAppearStartedAt) * 1000
                store.appendPerformanceDiagnostic(
                    String(
                        format: "coauthors-view-onAppear-ready ready_ms=%.2f rows=%ld filtered=%ld selected=%@",
                        onAppearDuration,
                        authorRows.count,
                        filteredAuthorRows.count,
                        selectedAuthorID ?? "-"
                    )
                )
            }
            .onReceive(store.$publicationAuthorRowSnapshotGeneration.dropFirst()) { _ in
                guard isActive else {
                    needsAuthorRowsRefreshWhenActive = true
                    needsAuthorFilterRebuildWhenActive = true
                    return
                }
                scheduleAuthorRowsRebuild()
            }
            .onChange(of: searchText) { _, _ in
                guard isActive else {
                    needsAuthorFilterRebuildWhenActive = true
                    return
                }
                scheduleFilteredAuthorRowsRebuild()
            }
            .onChange(of: authorNonSearchFilterSignature) { _, _ in
                guard isActive else {
                    needsAuthorFilterRebuildWhenActive = true
                    return
                }
                scheduleFilteredAuthorRowsRebuild()
            }
            .onChange(of: authorSortHistory) { _, _ in
                guard isActive else {
                    needsAuthorFilterRebuildWhenActive = true
                    return
                }
                scheduleFilteredAuthorRowsRebuild()
            }
            // onReceive on the metadata field: the filter is set from the app
            // menu too, and onChange never fired in this non-observed view.
            .onReceive(
                store.$metadata.map(\.personIncompleteDataFilter).removeDuplicates().dropFirst()
            ) { _ in
                guard isActive else {
                    needsAuthorFilterRebuildWhenActive = true
                    return
                }
                scheduleFilteredAuthorRowsRebuild()
            }
            .onChange(of: store.language) { _, _ in
                organizationFilters.removeAll()
                guard isActive else {
                    needsAuthorRowsRefreshWhenActive = true
                    needsAuthorFilterRebuildWhenActive = true
                    return
                }
                scheduleAuthorRowsRebuild()
            }
            .onChange(of: filteredAuthorRows.map(\.id)) { _, ids in
                guard let selectedAuthorID else {
                    setSelectedAuthorID(ids.first, resignFirstResponder: false)
                    return
                }
                if !ids.contains(selectedAuthorID) {
                    setSelectedAuthorID(ids.first, resignFirstResponder: false)
                }
            }
            .onChange(of: store.route) { _, route in
                guard let route, route.destination == .people else { return }
                guard isActive else {
                    pendingRouteAuthorID = route.recordID
                    store.appendPerformanceDiagnostic("coauthor-route-deferred id=\(route.recordID)")
                    return
                }
                applyRouteSelection(route.recordID)
                store.consumeRoute()
            }
            .onChange(of: selectedAuthorID) { _, id in
                let resolvedAuthorID = store.publicationAuthor(id: id)?.id ?? "-"
                store.handlePendingSelectionReturnIfNeeded(for: id, in: .people)
                store.rememberSelection(id: id, for: .people)
                pendingSelectionMeasurementID = id
                pendingSelectionStartedAt = CFAbsoluteTimeGetCurrent()
                store.appendPerformanceDiagnostic(
                    String(
                        format: "coauthor-selection-start id=%@ resolved=%@",
                        id ?? "-",
                        resolvedAuthorID
                    )
                )
            }
            .onChange(of: newRecordTrigger) { _, _ in
                guard isActive else { return }
                setSelectedAuthorID(store.addPublicationAuthor(), armLock: true)
            }
            .onChange(of: isActive) { _, active in
                if active {
                    if needsAuthorRowsRefreshWhenActive {
                        rebuildAuthorRows()
                        needsAuthorRowsRefreshWhenActive = false
                    }
                    if needsAuthorFilterRebuildWhenActive {
                        rebuildFilteredAuthorRows(reason: "reactivation")
                        needsAuthorFilterRebuildWhenActive = false
                    }
                    if let pendingRouteAuthorID {
                        applyRouteSelection(pendingRouteAuthorID)
                        store.consumeRoute()
                        self.pendingRouteAuthorID = nil
                    } else if let route = store.route, route.destination == .people {
                        applyRouteSelection(route.recordID)
                        store.consumeRoute()
                    }
                } else {
                    clearAuthorFiltersForDeactivationIfNeeded()
                    authorRowsRebuildTask?.cancel()
                    authorFilterRebuildTask?.cancel()
                }
            }
            .onDisappear {
                authorRowsRebuildTask?.cancel()
                authorFilterRebuildTask?.cancel()
                authorSelectionCoordinator.clear()
            }
        } detail: {
            PublicationAuthorDetailHostView(
                store: store,
                linkedDataCache: linkedDataCache,
                selectedAuthorID: detailAuthorID,
                authorGeneration: store.publicationAuthorRowSnapshotGeneration,
                organizationGeneration: store.organizationRowSnapshotGeneration,
                language: language,
                isActive: isActive
            ) { author in
                guard pendingSelectionMeasurementID == author.id,
                      let pendingSelectionStartedAt else { return }
                let duration = (CFAbsoluteTimeGetCurrent() - pendingSelectionStartedAt) * 1000
                store.appendPerformanceDiagnostic(
                    String(
                        format: "coauthor-selection-ready author=%@ ready_ms=%.2f",
                        author.name,
                        duration
                    )
                )
                releaseAuthorSelectionLock(for: author.id)
                self.pendingSelectionMeasurementID = nil
                self.pendingSelectionStartedAt = nil
            }
            .undoRevealPulse(
                triggerID: store.undoRevealRequest?.id,
                isActive: store.undoRevealRequest?.target.matchesWholeRecord(routeDestination: .people, recordID: detailAuthorID) == true
            )
        }
        .onDeleteCommand {
            guard let selectedAuthorID, let author = store.publicationAuthor(id: selectedAuthorID) else { return }
            store.requestKeyboardDeletion(recordTitle: author.name, isLocked: false) {
                store.deletePublicationAuthor(id: author.id)
            }
        }
    }

    private func applyRouteSelection(_ recordID: String) {
        let routeStartedAt = CFAbsoluteTimeGetCurrent()
        searchText = ""
        organizationFilters = []
        countryFilters = []
        showsOnlyCurrentUserAuthor = false
        showsOnlyActiveAuthors = false
        showsOnlyAuthorsWithPublications = false
        if store.personIncompleteDataFilter != .none {
            store.setPersonIncompleteDataFilter(.none)
        }
        rebuildAuthorRows()
        rebuildFilteredAuthorRows(reason: "route")
        let availableIDs = Set(filteredAuthorRows.map(\.id))
        let targetID: String? = availableIDs.contains(recordID) ? recordID : filteredAuthorRows.first?.id
        setSelectedAuthorID(targetID, armLock: targetID != nil)
        let duration = (CFAbsoluteTimeGetCurrent() - routeStartedAt) * 1000
        store.appendPerformanceDiagnostic(
            String(
                format: "coauthor-route-apply id=%@ selected=%@ rows=%ld filtered=%ld total_ms=%.2f",
                recordID,
                targetID ?? "-",
                authorRows.count,
                filteredAuthorRows.count,
                duration
            )
        )
    }

    private var authorNonSearchFilterSignature: String {
        [
            organizationFilters.sorted().joined(separator: "|"),
            countryFilters.sorted().joined(separator: "|"),
            showsOnlyCurrentUserAuthor ? "you" : "",
            showsOnlyActiveAuthors ? "active" : "",
            showsOnlyAuthorsWithPublications ? "publications" : "",
            String(store.personIncompleteDataFilter.hashValue),
            String(authorRowsAppliedGeneration),
            authorSortSignature
        ].joined(separator: "||")
    }

    private func refreshAuthorRows() {
        let rows = store.publicationAuthorRowSnapshots()
        authorRows = rows
        organizationOptionsCache = Array(Set(rows.flatMap(\.affiliationOrganizations).compactMap(\.nonEmpty)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        countryOptionsCache = Array(Set(rows.compactMap(\.primaryCountry.trimmedOrNil)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        authorRowsAppliedGeneration &+= 1
    }

    private func rebuildAuthorRows() {
        refreshAuthorRows()
    }

    private func clearAuthorFiltersForDeactivationIfNeeded() {
        guard !store.shouldRetainListFilters(for: .researchers) else { return }
        guard hasActiveAuthorFilters else { return }
        searchText = ""
        organizationFilters.removeAll()
        countryFilters.removeAll()
        showsOnlyCurrentUserAuthor = false
        showsOnlyActiveAuthors = false
        showsOnlyAuthorsWithPublications = false
        if store.personIncompleteDataFilter != .none {
            store.setPersonIncompleteDataFilterSilently(.none)
        }
        needsAuthorFilterRebuildWhenActive = true
    }

    @ViewBuilder
    private func authorFilterBar(language: AppLanguage) -> some View {
        AppFilterCard {
            VStack(alignment: .leading, spacing: 8) {
                AppFilterRow(
                    showsClearButton: searchText.nonEmpty != nil,
                    clearAction: { searchText = "" }
                ) {
                    AppSidebarSearchField(
                        placeholder: language.text("Search people", "Sök personer"),
                        text: $searchText
                    )
                }

                AppFilterRow(
                    showsClearButton: showsOnlyCurrentUserAuthor || showsOnlyActiveAuthors || showsOnlyAuthorsWithPublications || store.personIncompleteDataFilter != .none,
                    clearAction: {
                        showsOnlyCurrentUserAuthor = false
                        showsOnlyActiveAuthors = false
                        showsOnlyAuthorsWithPublications = false
                        if store.personIncompleteDataFilter != .none {
                            store.setPersonIncompleteDataFilter(.none)
                        }
                    }
                ) {
                    AppFilterChip(
                        label: language.text("You", "Du"),
                        isSelected: showsOnlyCurrentUserAuthor
                    ) {
                        showsOnlyCurrentUserAuthor.toggle()
                    }
                    AppFilterChip(
                        label: language.text("Active", "Aktiva"),
                        isSelected: showsOnlyActiveAuthors
                    ) {
                        showsOnlyActiveAuthors.toggle()
                    }
                    AppFilterChip(
                        label: language.text("Has publications", "Har publikationer"),
                        isSelected: showsOnlyAuthorsWithPublications
                    ) {
                        showsOnlyAuthorsWithPublications.toggle()
                    }
                }

                AppFilterRow(
                    showsClearButton: !organizationFilters.isEmpty,
                    clearAction: {
                        organizationFilters.removeAll()
                    }
                ) {
                    MultiSelectFilterMenu(
                        title: language.text("Remove filter", "Ta bort filter"),
                        emptyLabel: language.text("All organizations", "Alla organisationer"),
                        options: organizationOptions,
                        selectedOptions: $organizationFilters
                    )
                }

                AppFilterRow(
                    showsClearButton: !countryFilters.isEmpty,
                    clearAction: {
                        countryFilters.removeAll()
                    }
                ) {
                    MultiSelectFilterMenu(
                        title: language.text("Remove filter", "Ta bort filter"),
                        emptyLabel: language.text("All countries", "Alla länder"),
                        options: countryOptions,
                        selectedOptions: $countryFilters,
                        display: { language.localizedCountry($0) }
                    )
                }

                AppFilterClearAllRow(isVisible: hasActiveAuthorFilters) {
                    searchText = ""
                    organizationFilters.removeAll()
                    countryFilters.removeAll()
                    showsOnlyCurrentUserAuthor = false
                    showsOnlyActiveAuthors = false
                    showsOnlyAuthorsWithPublications = false
                    if store.personIncompleteDataFilter != .none {
                        store.setPersonIncompleteDataFilter(.none)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func authorNameCell(row: PublicationAuthorRowSnapshot, language: AppLanguage) -> some View {
        let content = HStack(spacing: 6) {
            AppPersonNameText(
                name: row.displayName,
                isCurrentUser: row.isCurrentUser
            )
            let countryFlags = row.countryFlags
            if !countryFlags.isEmpty {
                Text(countryFlags.joined(separator: " "))
                    .lineLimit(1)
            }
        }

        content
    }

    private func authorResultsTable(language: AppLanguage) -> some View {
        let organizationMinWidth: CGFloat = 220
        let tableMinWidth: CGFloat = 220 + organizationMinWidth + 72 + 72 + 96 + 88 + 20
        let orderedIDs = filteredAuthorRows.map(\.id)

        return AppListTable(contentMinWidth: tableMinWidth) {
            HStack(spacing: 0) {
                authorListHeader(language.text("Name", "Namn"), column: .name)
                    .frame(width: 220, alignment: .leading)
                authorListHeader(language.text("Organization", "Organisation"), column: .organization)
                    .frame(minWidth: organizationMinWidth, maxWidth: .infinity, alignment: .leading)
                authorListHeader(language.text("Project", "Projekt"), width: 72, column: .project)
                authorListHeader(language.text("Grants", "Anslag"), width: 72, column: .grants)
                authorListHeader(language.text("Publications", "Publikationer"), width: 96, column: .publications)
                authorListHeader(language.text("Dissemination", "Spridning"), width: 88, column: .dissemination)
            }
        } rows: {
            PublicationAuthorResultsTable(
                rows: filteredAuthorRows,
                selectedAuthorID: selectedAuthorID,
                language: language,
                organizationMinWidth: organizationMinWidth,
                tableMinWidth: tableMinWidth
            ) { rowID in
                store.appendPerformanceDiagnostic("coauthor-row-click id=\(rowID)")
                handleAuthorSelectionCandidate(rowID)
            }
        }
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .appListKeyboardNavigation(
            store: store,
            destination: .people,
            isEnabled: isActive,
            orderedIDs: orderedIDs,
            selectedID: selectedAuthorID,
            onSelect: handleAuthorSelectionCandidate
        )
    }

    private func authorListHeader(
        _ title: String,
        width: CGFloat? = nil,
        column: PublicationAuthorListSortColumn
    ) -> some View {
        let criterion = authorSortCriterion(for: column)
        let sortIndex = authorSortIndex(for: column)
        return AppSortableListHeader(
            title: title,
            ascending: criterion?.ascending,
            sortIndex: sortIndex,
            width: width,
            maxWidth: width == nil ? .infinity : nil,
            resetTitle: store.language.text("Reset", "Återställ"),
            onToggle: { toggleAuthorSort(column) },
            onReset: resetAuthorSort
        )
    }

    private func rebuildFilteredAuthorRows(reason: String = "manual") {
        let searchQuery = SearchFilterQuery(raw: searchText)
        let nonSearchSignature = authorNonSearchFilterSignature
        let canReusePreviousSearchBase =
            reason == "debounced-search"
            && nonSearchSignature == lastAuthorNonSearchFilterSignature
            && searchQuery.isNarrowing(over: lastAuthorSearchQuery)

        let baseRows: [PublicationAuthorRowSnapshot]
        if canReusePreviousSearchBase {
            baseRows = baseFilteredAuthorRows
        } else {
            baseRows = authorRows
                .filter { row in
                    (organizationFilters.isEmpty || !Set(row.affiliationOrganizations).isDisjoint(with: organizationFilters))
                        && (countryFilters.isEmpty || countryFilters.contains(row.primaryCountry))
                        && (!showsOnlyCurrentUserAuthor || row.isCurrentUser)
                        && (!showsOnlyActiveAuthors || authorHasAnyActivity(row))
                        && (!showsOnlyAuthorsWithPublications || row.publicationCount > 0)
                        && matchesIncompleteDataFilter(row)
                }
                .sorted(using: sortOrder)
            baseFilteredAuthorRows = baseRows
        }

        let candidateRows = canReusePreviousSearchBase ? filteredAuthorRows : baseRows
        filteredAuthorRows = searchQuery.isEmpty
            ? baseRows
            : candidateRows.filter { searchQuery.matches(normalizedHaystack: $0.normalizedSearchBlob) }
        lastAuthorSearchQuery = searchQuery
        lastAuthorNonSearchFilterSignature = nonSearchSignature
    }

    private func toggleAuthorSort(_ column: PublicationAuthorListSortColumn) {
        if let existingIndex = authorSortHistory.firstIndex(where: { $0.column == column }) {
            if existingIndex == 0 {
                authorSortHistory[0].ascending.toggle()
            } else {
                let criterion = authorSortHistory.remove(at: existingIndex)
                authorSortHistory.insert(criterion, at: 0)
            }
        } else {
            authorSortHistory.insert(
                PublicationAuthorListSortCriterion(column: column, ascending: column.defaultAscending),
                at: 0
            )
        }
        ListSortPersistence.save(authorSortHistory, defaultsKey: "PublicationAuthorsListSort")
    }

    private func resetAuthorSort() {
        authorSortHistory = [
            PublicationAuthorListSortCriterion(column: .name, ascending: true)
        ]
        ListSortPersistence.save(authorSortHistory, defaultsKey: "PublicationAuthorsListSort")
    }

    private func authorSortCriterion(for column: PublicationAuthorListSortColumn) -> PublicationAuthorListSortCriterion? {
        authorSortHistory.first(where: { $0.column == column })
    }

    private func authorSortIndex(for column: PublicationAuthorListSortColumn) -> Int? {
        authorSortHistory.firstIndex(where: { $0.column == column })
    }

    private func scheduleAuthorRowsRebuild() {
        authorRowsRebuildTask?.cancel()
        let task = DispatchWorkItem {
            rebuildAuthorRows()
            rebuildFilteredAuthorRows(reason: "rows")
        }
        authorRowsRebuildTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: task)
    }

    private func scheduleFilteredAuthorRowsRebuild() {
        authorFilterRebuildTask?.cancel()
        let task = DispatchWorkItem {
            rebuildFilteredAuthorRows(reason: "debounced-search")
        }
        authorFilterRebuildTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: task)
    }

    private func matchesIncompleteDataFilter(_ author: PublicationAuthorRowSnapshot) -> Bool {
        switch store.personIncompleteDataFilter {
        case .none:
            return true
        case .any:
            return author.missingORCID
                || author.missingEmail
                || author.missingPrimaryOrganization
                || author.missingPrimaryCountry
                || author.missingTitle
        case .orcid:
            return author.missingORCID
        case .email:
            return author.missingEmail
        case .organization:
            return author.missingPrimaryOrganization
        case .country:
            return author.missingPrimaryCountry
        case .title:
            return author.missingTitle
        }
    }

    private func authorHasAnyActivity(_ author: PublicationAuthorRowSnapshot) -> Bool {
        author.projectCount > 0
            || author.grantCount > 0
            || author.publicationCount > 0
            || author.disseminationCount > 0
            || author.expertAssignmentCount > 0
            || author.teachingCount > 0
    }

    private func handleAuthorSelectionCandidate(_ newValue: String?) {
        store.appendPerformanceDiagnostic(
            "coauthor-selection-candidate id=\(newValue ?? "-") lock=\(authorSelectionCoordinator.lockedID ?? "-") previous=\(authorSelectionCoordinator.previousID ?? "-")"
        )
        guard authorSelectionCoordinator.accepts(candidate: newValue) else { return }
        setSelectedAuthorID(newValue, armLock: newValue != nil)
    }

    private func setSelectedAuthorID(_ newValue: String?, armLock: Bool = false, resignFirstResponder: Bool = true) {
        guard selectedAuthorID != newValue else {
            if detailAuthorID != newValue {
                var transaction = Transaction()
                transaction.animation = nil
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    detailAuthorID = newValue
                }
            }
            store.appendPerformanceDiagnostic(
                "coauthor-selection-state-skip current=\(selectedAuthorID ?? "-") detail=\(detailAuthorID ?? "-") requested=\(newValue ?? "-") arm_lock=\(armLock ? "yes" : "no")"
            )
            if armLock, let newValue {
                armAuthorSelectionLock(for: newValue)
            }
            return
        }
        store.appendPerformanceDiagnostic(
            "coauthor-selection-state-set from=\(selectedAuthorID ?? "-") to=\(newValue ?? "-") arm_lock=\(armLock ? "yes" : "no")"
        )
        let previousID = selectedAuthorID
        if resignFirstResponder {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        var transaction = Transaction()
        transaction.animation = nil
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedAuthorID = newValue
            detailAuthorID = newValue
        }
        store.appendPerformanceDiagnostic(
            "coauthor-selection-state-did-set current=\(selectedAuthorID ?? "-") detail=\(detailAuthorID ?? "-") previous=\(previousID ?? "-")"
        )
        if armLock, let newValue {
            authorSelectionCoordinator.arm(newValue, previousID: previousID)
        } else if newValue == nil {
            authorSelectionCoordinator.clear()
        }
    }

    private func armAuthorSelectionLock(for id: String) {
        authorSelectionCoordinator.arm(
            id,
            previousID: authorSelectionCoordinator.previousID
        )
    }

    private func releaseAuthorSelectionLock(for id: String) {
        authorSelectionCoordinator.release(ifMatching: id)
    }

}

private struct PublicationAuthorResultsTable: View {
    let rows: [PublicationAuthorRowSnapshot]
    let selectedAuthorID: String?
    let language: AppLanguage
    let organizationMinWidth: CGFloat
    let tableMinWidth: CGFloat
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    PublicationAuthorResultsRow(
                        row: row,
                        language: language,
                        organizationMinWidth: organizationMinWidth,
                        tableMinWidth: tableMinWidth,
                        isSelected: row.id == selectedAuthorID,
                        showsDivider: index < rows.count - 1,
                        onSelect: onSelect
                    )
                    .equatable()
                }
            }
        }
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }
}

private struct PublicationAuthorResultsRow: View, Equatable {
    let row: PublicationAuthorRowSnapshot
    let language: AppLanguage
    let organizationMinWidth: CGFloat
    let tableMinWidth: CGFloat
    let isSelected: Bool
    let showsDivider: Bool
    let onSelect: (String) -> Void

    nonisolated static func == (lhs: PublicationAuthorResultsRow, rhs: PublicationAuthorResultsRow) -> Bool {
        lhs.row == rhs.row
            && lhs.language == rhs.language
            && lhs.organizationMinWidth == rhs.organizationMinWidth
            && lhs.tableMinWidth == rhs.tableMinWidth
            && lhs.isSelected == rhs.isSelected
            && lhs.showsDivider == rhs.showsDivider
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppListRowButton(
                minWidth: tableMinWidth,
                action: { onSelect(row.id) },
                background: { rowBackground }
            ) {
                HStack(spacing: 0) {
                    authorNameCell
                        .frame(width: 220, alignment: .leading)
                    AuthorTableCell(text: row.primaryOrganization, background: nil)
                        .frame(minWidth: organizationMinWidth, maxWidth: .infinity, alignment: .leading)
                    AuthorTableCell(text: "\(row.projectCount)", background: nil)
                        .frame(width: 72, alignment: .leading)
                    AuthorTableCell(text: "\(row.grantCount)", background: nil)
                        .frame(width: 72, alignment: .leading)
                    AuthorTableCell(text: "\(row.publicationCount)", background: nil)
                        .frame(width: 96, alignment: .leading)
                    AuthorTableCell(text: "\(row.disseminationCount)", background: nil)
                        .frame(width: 88, alignment: .leading)
                }
            }

            if showsDivider {
                Divider()
            }
        }
    }

    private var authorNameCell: some View {
        HStack(spacing: 6) {
            AppPersonNameText(
                name: row.displayName,
                isCurrentUser: row.isCurrentUser
            )
            let countryFlags = row.countryFlags
            if !countryFlags.isEmpty {
                Text(countryFlags.joined(separator: " "))
                    .lineLimit(1)
            }
        }
    }

    private var rowBackground: some View {
        AppListRowBackground(isSelected: isSelected)
    }
}

private struct AuthorTableCell: View {
    let text: String
    let background: Color?

    var body: some View {
        Text(text)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            // Fixed-width columns clip silently; the tooltip recovers the value.
            .help(text)
            .background(
                Group {
                    if let background {
                        Rectangle().fill(background).padding(.horizontal, -8)
                    }
                }
            )
    }
}

private func canonicalCountryName(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let lowered = trimmed.lowercased()

    if lowered.contains("sverige") || lowered.contains("sweden") {
        return "Sweden"
    }
    if lowered.contains("norge") || lowered.contains("norway") {
        return "Norway"
    }
    if lowered.contains("danmark") || lowered.contains("denmark") {
        return "Denmark"
    }
    if lowered.contains("finland") {
        return "Finland"
    }
    if lowered.contains("tyskland") || lowered.contains("germany") {
        return "Germany"
    }
    if lowered.contains("storbritannien") || lowered == "england" || lowered == "u.k." || lowered == "uk" || lowered.contains("united kingdom") {
        return "United Kingdom"
    }
    if lowered.contains("nederländerna") || lowered.contains("netherlands") {
        return "Netherlands"
    }
    if lowered.contains("frankrike") || lowered.contains("france") {
        return "France"
    }
    if lowered.contains("spanien") || lowered.contains("spain") {
        return "Spain"
    }
    if lowered.contains("italien") || lowered.contains("italy") {
        return "Italy"
    }
    if lowered.contains("belgien") || lowered.contains("belgium") {
        return "Belgium"
    }
    if lowered.contains("schweiz") || lowered.contains("switzerland") {
        return "Switzerland"
    }
    if lowered.contains("österrike") || lowered.contains("austria") {
        return "Austria"
    }
    if lowered.contains("australien") || lowered.contains("australia") {
        return "Australia"
    }
    if lowered == "usa" || lowered.contains("förenta staterna") || lowered.contains("united states") {
        return "United States"
    }
    return trimmed
}

private struct PublicationAuthorDetailHostView: View {
    let store: GrantDataStore
    let linkedDataCache: PublicationAuthorLinkedDataCacheStore
    let selectedAuthorID: String?
    let authorGeneration: Int
    let organizationGeneration: Int
    let language: AppLanguage
    let isActive: Bool
    let selectionReady: (PublicationAuthor) -> Void

    var body: some View {
        if let author = store.publicationAuthor(id: selectedAuthorID) {
            PublicationAuthorEditorView(
                store: store,
                linkedDataCache: linkedDataCache,
                author: author,
                isActive: isActive,
                language: language,
                organizationGeneration: organizationGeneration,
                linkedDataGenerationKey: [
                    String(store.applicationRowSnapshotGeneration),
                    String(store.projectRowSnapshotGeneration),
                    String(store.publicationAuthorRowSnapshotGeneration),
                    String(organizationGeneration),
                    // Bumped by every CV/teaching/doctoral mutation; without
                    // it the linked media/review/contribution/doctoral
                    // sections stayed stale even across tab switches.
                    String(store.dataQualityCacheGeneration),
                    language.rawValue
                ].joined(separator: "|")
            )
            .id(author.id)
            .performanceScopeProbe(
                store: store,
                scope: "coauthors-detail",
                identifier: author.id,
                restartOnIdentifierChange: true
            )
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            .onAppear {
                store.appendPerformanceDiagnostic(
                    "coauthor-detail-host-author requested=\(selectedAuthorID ?? "-") author=\(author.id)"
                )
            }
            .onChange(of: author.id) { oldValue, newValue in
                store.appendPerformanceDiagnostic(
                    "coauthor-detail-host-author-change requested=\(selectedAuthorID ?? "-") from=\(oldValue) to=\(newValue)"
                )
            }
            .background(
                CoauthorSelectionReadyReporter(
                    store: store,
                    author: author
                ) {
                    selectionReady(author)
                }
            )
        } else {
            AppWorkspaceEmptyStateView(
                title: language.text("No researchers found", "Inga forskare hittades"),
                subtitle: language.text("Add or search for a researcher.", "Lägg till eller sök fram en forskare."),
                kind: .researchers,
                fillsBackground: true
            )
        }
    }
}

private struct CoauthorSelectionReadyReporter: View {
    let store: GrantDataStore
    let author: PublicationAuthor
    let onReady: () -> Void

    @State private var appearedAt: CFAbsoluteTime?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                let now = CFAbsoluteTimeGetCurrent()
                appearedAt = now
                store.appendPerformanceDiagnostic(
                    String(
                        format: "coauthor-selection-reporter-appear author=%@ authorID=%@",
                        author.name,
                        author.id
                    )
                )
                DispatchQueue.main.async {
                    let readyMs = appearedAt.map { (CFAbsoluteTimeGetCurrent() - $0) * 1000 } ?? -1
                    store.appendPerformanceDiagnostic(
                        String(
                            format: "coauthor-selection-reporter-fire author=%@ authorID=%@ appear_to_fire_ms=%.2f",
                            author.name,
                            author.id,
                            readyMs
                        )
                    )
                    onReady()
                }
            }
            .onChange(of: author.id) { _, newValue in
                store.appendPerformanceDiagnostic(
                    "coauthor-selection-reporter-author-change author=\(author.name) authorID=\(newValue)"
                )
            }
    }
}

private struct PublicationAuthorLinkedProjectRow: Identifiable, Equatable {
    let project: ProjectRecord
    let label: String

    var id: String { project.id }
}

private struct PublicationAuthorLinkedApplicationRow: Identifiable, Equatable {
    let application: GrantApplication
    let title: String

    var id: String { application.id }
}

private struct PublicationAuthorLinkedConferenceContributionRow: Identifiable, Equatable {
    let contribution: CVConferenceContribution
    let title: String
    let yearText: String

    var id: String { contribution.id }
}

private struct PublicationAuthorLinkedCongressParticipationRow: Identifiable, Equatable {
    let organizationID: String
    let congress: OrganizationCongress
    let title: String
    let subtitle: String
    let dateText: String

    var id: String { "\(organizationID):\(congress.id)" }
}

private struct PublicationAuthorLinkedAbstractRow: Identifiable, Equatable {
    let contribution: CVConferenceContribution
    let title: String
    let subtitle: String
    let dateText: String

    var id: String { contribution.id }
}

private func authorLinkedAbstractStatusFill(for contribution: CVConferenceContribution) -> Color? {
    // Round 16: the shared conference contribution tones.
    AppPalette.statusRowFill(AppStatusTones.conferenceContribution(AppConferenceContributionBadgeStatus(contribution: contribution)))
}

private func authorLinkedAbstractStatusHelp(
    for contribution: CVConferenceContribution,
    language: AppLanguage
) -> String? {
    guard contribution.isRejected else { return nil }
    return language.text("Rejected", "Refuserat")
}

private struct PublicationAuthorLinkedMediaAppearanceRow: Identifiable, Equatable {
    let appearance: CVMediaAppearance
    let title: String
    let dateText: String

    var id: String { appearance.id }
}

private struct PublicationAuthorLinkedReviewRow: Identifiable, Equatable {
    let review: CVReviewEntry
    let title: String
    let dateText: String

    var id: String { review.id }
}

private struct PublicationAuthorLinkedTeachingAssignmentRow: Identifiable, Equatable {
    let assignment: TeachingAssignment
    let title: String
    let subtitle: String
    let dateText: String

    var id: String { assignment.id }
}

private struct PublicationAuthorLinkedDoctoralCandidateRow: Identifiable, Equatable {
    let candidate: DoctoralCandidateRecord
    let title: String
    let subtitle: String

    var id: String { candidate.id }
}

private struct PublicationAuthorLinkedDataCacheEntry {
    let authorID: String
    let cacheKey: String
    let publications: [PublicationRecord]
    let conferenceContributions: [PublicationAuthorLinkedConferenceContributionRow]
    let mediaAppearances: [PublicationAuthorLinkedMediaAppearanceRow]
    let reviewEntries: [PublicationAuthorLinkedReviewRow]
    let teachingAssignments: [PublicationAuthorLinkedTeachingAssignmentRow]
    let doctoralCandidates: [PublicationAuthorLinkedDoctoralCandidateRow]
    let applications: [PublicationAuthorLinkedApplicationRow]
    let projects: [PublicationAuthorLinkedProjectRow]
    let projectRelations: [GrantDataStore.ResearcherProjectRelation]
    let congressParticipations: [PublicationAuthorLinkedCongressParticipationRow]
    let abstracts: [PublicationAuthorLinkedAbstractRow]
    let calendarEvents: [CalendarLinkedEventRow]
}

private final class PublicationAuthorLinkedDataCacheStore: ObservableObject {
    @Published var entries: [String: PublicationAuthorLinkedDataCacheEntry] = [:]
    @Published var cacheSignature: String?
}

struct CountryPickerField: View {
    @Binding var selection: String
    let language: AppLanguage
    let width: CGFloat

    private struct CachedLanguageOptions {
        let localizedByCanonical: [String: String]
        let canonicalByFoldedEnglish: [String: String]
        let canonicalByFoldedLocalized: [String: String]
        let sortedCanonicalOptions: [String]
        let menuOptions: [(label: String, value: String)]
    }

    private static let cachedOptionsByLanguage: [AppLanguage: CachedLanguageOptions] = [
        .swedish: buildCachedOptions(for: .swedish),
        .english: buildCachedOptions(for: .english)
    ]

    private static func foldedCountryLookupKey(_ raw: String) -> String {
        raw
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func buildCachedOptions(for language: AppLanguage) -> CachedLanguageOptions {
        let sortingLocale = Locale(identifier: language == .swedish ? "sv_SE" : "en_US")
        var localizedByCanonical: [String: String] = [:]
        var canonicalByFoldedEnglish: [String: String] = [:]
        var canonicalByFoldedLocalized: [String: String] = [:]

        for canonical in GrantParsing.countryOptions {
            let localized = language.localizedCountry(canonical)
            localizedByCanonical[canonical] = localized
            canonicalByFoldedEnglish[foldedCountryLookupKey(canonical)] = canonical
            canonicalByFoldedLocalized[foldedCountryLookupKey(localized)] = canonical
        }

        let sortedCanonicalOptions = GrantParsing.countryOptions.sorted {
            (localizedByCanonical[$0] ?? $0).compare(
                localizedByCanonical[$1] ?? $1,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                range: nil,
                locale: sortingLocale
            ) == .orderedAscending
        }

        return CachedLanguageOptions(
            localizedByCanonical: localizedByCanonical,
            canonicalByFoldedEnglish: canonicalByFoldedEnglish,
            canonicalByFoldedLocalized: canonicalByFoldedLocalized,
            sortedCanonicalOptions: sortedCanonicalOptions,
            menuOptions: sortedCanonicalOptions.map { (localizedByCanonical[$0] ?? $0, $0) }
        )
    }

    private var cachedOptions: CachedLanguageOptions {
        Self.cachedOptionsByLanguage[language] ?? Self.buildCachedOptions(for: language)
    }

    private var options: [String] {
        let current = canonicalSelection(selection)
        if current.isEmpty || cachedOptions.localizedByCanonical[current] != nil {
            return cachedOptions.sortedCanonicalOptions
        }
        return ([current] + cachedOptions.sortedCanonicalOptions).uniqued()
    }

    private var menuOptions: [(label: String, value: String)] {
        let current = canonicalSelection(selection)
        if current.isEmpty || cachedOptions.localizedByCanonical[current] != nil {
            return cachedOptions.menuOptions
        }
        return [(displaySelection(current), current)] + cachedOptions.menuOptions.filter { $0.value != current }
    }

    private func canonicalSelection(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let foldedTrimmed = Self.foldedCountryLookupKey(trimmed)

        if let exactCanonical = cachedOptions.canonicalByFoldedEnglish[foldedTrimmed] {
            return exactCanonical
        }

        if let localizedMatch = cachedOptions.canonicalByFoldedLocalized[foldedTrimmed] {
            return localizedMatch
        }

        let heuristicCanonical = canonicalCountryName(trimmed)
        if let canonicalMatch = cachedOptions.canonicalByFoldedEnglish[Self.foldedCountryLookupKey(heuristicCanonical)] {
            return canonicalMatch
        }

        return trimmed
    }

    private func displaySelection(_ raw: String) -> String {
        let canonical = canonicalSelection(raw)
        guard !canonical.isEmpty else { return "" }
        return cachedOptions.localizedByCanonical[canonical] ?? canonical
    }

    var body: some View {
        if AppRuntime.usesRenewedChrome {
            AppMenuSelectionField(
                selection: Binding(
                    get: { canonicalSelection(selection) },
                    set: { selection = $0 }
                ),
                options: menuOptions,
                placeholder: language.text("Select country", "Välj land"),
                clearValue: ""
            )
            .frame(width: width, alignment: .leading)
        } else {
            LegacyCountryPickerField(
                selection: $selection,
                language: language,
                width: width,
                options: options,
                displaySelection: displaySelection
            )
        }
    }

    private struct LegacyCountryPickerField: NSViewRepresentable {
        var selection: Binding<String>
        let language: AppLanguage
        let width: CGFloat
        let options: [String]
        let displaySelection: (String) -> String

        func makeCoordinator() -> Coordinator {
            Coordinator(selection: selection, options: options, language: language)
        }

        func makeNSView(context: Context) -> NSComboBox {
            let combo = NSComboBox(frame: .zero)
            combo.usesDataSource = true
            combo.dataSource = context.coordinator
            combo.delegate = context.coordinator
            combo.completes = true
            combo.isEditable = true
            combo.numberOfVisibleItems = 12
            combo.placeholderString = language.text("Select country", "Välj land")
            combo.controlSize = .regular
            combo.translatesAutoresizingMaskIntoConstraints = false
            combo.widthAnchor.constraint(equalToConstant: width).isActive = true
            combo.stringValue = displaySelection(selection.wrappedValue)
            return combo
        }

        func updateNSView(_ combo: NSComboBox, context: Context) {
            context.coordinator.selection = selection
            context.coordinator.options = options
            context.coordinator.language = language
            combo.reloadData()
            let displayValue = displaySelection(selection.wrappedValue)
            if combo.stringValue != displayValue {
                combo.stringValue = displayValue
            }
            combo.placeholderString = language.text("Select country", "Välj land")
        }

        final class Coordinator: NSObject, NSComboBoxDataSource, NSComboBoxDelegate {
            var selection: Binding<String>
            var options: [String]
            var language: AppLanguage

            init(selection: Binding<String>, options: [String], language: AppLanguage) {
                self.selection = selection
                self.options = options
                self.language = language
            }

            func numberOfItems(in comboBox: NSComboBox) -> Int {
                options.count
            }

            func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
                guard options.indices.contains(index) else { return nil }
                return language.localizedCountry(options[index])
            }

            private func canonicalValue(for raw: String) -> String {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return "" }

                if let exactCanonical = options.first(where: {
                    $0.caseInsensitiveCompare(trimmed) == .orderedSame
                }) ?? GrantParsing.countryOptions.first(where: {
                    $0.caseInsensitiveCompare(trimmed) == .orderedSame
                }) {
                    return exactCanonical
                }

                if let localizedMatch = (options + GrantParsing.countryOptions).uniqued().first(where: {
                    language.localizedCountry($0).caseInsensitiveCompare(trimmed) == .orderedSame
                }) {
                    return localizedMatch
                }

                let heuristicCanonical = canonicalCountryName(trimmed)
                if let canonicalMatch = GrantParsing.countryOptions.first(where: {
                    $0.caseInsensitiveCompare(heuristicCanonical) == .orderedSame
                }) {
                    return canonicalMatch
                }

                return trimmed
            }

            func comboBoxSelectionDidChange(_ notification: Notification) {
                guard let combo = notification.object as? NSComboBox else { return }
                let index = combo.indexOfSelectedItem
                if options.indices.contains(index) {
                    selection.wrappedValue = options[index]
                    combo.stringValue = language.localizedCountry(options[index])
                }
            }

            func controlTextDidChange(_ notification: Notification) {
                guard let combo = notification.object as? NSComboBox else { return }
                selection.wrappedValue = combo.stringValue
            }

            func controlTextDidEndEditing(_ notification: Notification) {
                guard let combo = notification.object as? NSComboBox else { return }
                let canonical = canonicalValue(for: combo.stringValue)
                selection.wrappedValue = canonical
                combo.stringValue = canonical.isEmpty ? "" : language.localizedCountry(canonical)
            }
        }
    }
}

private struct ResearcherLinkConflictCandidate: Identifiable {
    let author: PublicationAuthor
    let reason: String
    let normalizedKey: String

    var id: String { author.id }
}

private struct PublicationAuthorEditorView: View {
    let store: GrantDataStore
    @ObservedObject var linkedDataCache: PublicationAuthorLinkedDataCacheStore
    @Environment(\.scenePhase) private var scenePhase
    let author: PublicationAuthor
    let isActive: Bool
    let language: AppLanguage
    let organizationGeneration: Int
    let linkedDataGenerationKey: String

    @State private var draft: PublicationAuthor
    @State private var nameVariantRows: [PublicationAuthorNameVariant]
    @State private var autosaveTask: DispatchWorkItem?
    @State private var forcedPersistTask: DispatchWorkItem?
    @State private var draggedAffiliationID: String?
    @State private var pendingAffiliationRowID: String
    @State private var cachedLinkedDataEntry: PublicationAuthorLinkedDataCacheEntry?
    @State private var linkedDataRefreshTask: DispatchWorkItem?
    @State private var linkedCalendarRefreshTask: DispatchWorkItem?
    @State private var deferredProfileSectionsTask: DispatchWorkItem?
    @State private var primarySectionsRevealTask: DispatchWorkItem?
    @State private var showPrimarySections = false
    @State private var showDeferredProfileSections = false
    @State private var deferredLinkedSectionsTask: DispatchWorkItem?
    @State private var deferredLinkedDisseminationTask: DispatchWorkItem?
    @State private var deferredLinkedExpertTeachingTask: DispatchWorkItem?
    @State private var deferredLinkedCongressTask: DispatchWorkItem?
    @State private var showDeferredLinkedSections = false
    @State private var visibleLinkedPanelStage = 0
    @State private var deferredSectionsPreparedForAuthorID: String?
    @State private var linkedDataRefreshToken: UInt = 0
    @State private var editorAppearStartedAt: CFAbsoluteTime?
    @State private var isDoctoralThesisPanelCollapsed = true
    @State private var isPersonalResumePanelCollapsed = true
    @State private var cachedOrganizationOptions = GrantDataStore.PublicationAuthorOrganizationOptions.empty
    @State private var cachedAffiliationOrganizationSet: Set<String> = []
    @State private var organizationCacheRefreshTask: DispatchWorkItem?
    @State private var reportedEditorPanelReadyKeys: Set<String> = []
    @State private var deferredWorkGeneration: UInt = 0
    @State private var pendingAutosaveReason = "unspecified"
    @State private var pendingAutosaveScheduledAt: CFAbsoluteTime?
    @State private var lastLocalAutosaveSnapshot: PublicationAuthor?
    @State private var duplicateWarningRefreshToken: UInt = 0
    @State private var careerStageIsFocused = false

    init(
        store: GrantDataStore,
        linkedDataCache: PublicationAuthorLinkedDataCacheStore,
        author: PublicationAuthor,
        isActive: Bool = true,
        language: AppLanguage,
        organizationGeneration: Int,
        linkedDataGenerationKey: String
    ) {
        self.store = store
        self.linkedDataCache = linkedDataCache
        self.author = author
        self.isActive = isActive
        self.language = language
        self.organizationGeneration = organizationGeneration
        self.linkedDataGenerationKey = linkedDataGenerationKey
        _draft = State(initialValue: author)
        _nameVariantRows = State(initialValue: Self.editableNameVariantRows(for: author.nameVariantRows))
        _pendingAffiliationRowID = State(initialValue: UUID().uuidString)
    }

    private static func editableNameVariantRows(for rows: [PublicationAuthorNameVariant]) -> [PublicationAuthorNameVariant] {
        normalizedPublicationAuthorNameVariantRows(rows)
    }

    private func loadLinkedPublications(for authorID: String, authorName: String) -> [PublicationRecord] {
        let publications = store.publications(forAuthorID: authorID)
        if !publications.isEmpty {
            return publications.sorted(by: publicationSortOrder)
        }
        return store.publications(forAuthorName: authorName)
            .sorted(by: publicationSortOrder)
    }

    private func loadLinkedCongressParticipations(for author: PublicationAuthor) -> [PublicationAuthorLinkedCongressParticipationRow] {
        store.organizations
            .flatMap { organization in
                organization.congresses.compactMap { congress -> PublicationAuthorLinkedCongressParticipationRow? in
                    guard congressMatchesAuthorParticipation(congress, author: author) else { return nil }
                    let organizationName = organization.displayName(for: language)
                    let title = congress.title.nonEmpty ?? organizationName
                    return PublicationAuthorLinkedCongressParticipationRow(
                        organizationID: organization.id,
                        congress: congress,
                        title: title,
                        subtitle: linkedCongressSubtitle(congress: congress, organizationName: organizationName),
                        dateText: linkedDateRangeText(from: congress.from, to: congress.to)
                    )
                }
            }
            .sorted(by: linkedCongressParticipationSort)
    }

    private func loadLinkedAbstracts(for author: PublicationAuthor) -> [PublicationAuthorLinkedAbstractRow] {
        store.cvConferenceContributions
            .filter { contributionMatchesAuthor($0, author: author) }
            .sorted(by: linkedAbstractSort)
            .map { contribution in
                PublicationAuthorLinkedAbstractRow(
                    contribution: contribution,
                    title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                    subtitle: linkedAbstractSubtitle(for: contribution),
                    dateText: linkedContributionDateText(for: contribution)
                )
            }
    }

    private func loadLinkedApplications(for authorID: String, authorName: String) -> [GrantApplication] {
        let applications = store.applications(forPersonID: authorID)
        if !applications.isEmpty {
            return applications.sorted {
                let leftRank = linkedApplicationSortRank($0)
                let rightRank = linkedApplicationSortRank($1)
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                let leftDate = $0.applicationDate ?? .distantPast
                let rightDate = $1.applicationDate ?? .distantPast
                if leftDate != rightDate {
                    return leftDate > rightDate
                }
                return store.displayTitle(for: $0, language: language).localizedStandardCompare(store.displayTitle(for: $1, language: language)) == .orderedAscending
            }
        }
        return store.applications(forPersonName: authorName)
            .sorted {
                let leftRank = linkedApplicationSortRank($0)
                let rightRank = linkedApplicationSortRank($1)
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                let leftDate = $0.applicationDate ?? .distantPast
                let rightDate = $1.applicationDate ?? .distantPast
                if leftDate != rightDate {
                    return leftDate > rightDate
                }
                return store.displayTitle(for: $0, language: language).localizedStandardCompare(store.displayTitle(for: $1, language: language)) == .orderedAscending
            }
    }

    private func linkedApplicationSortRank(_ application: GrantApplication) -> Int {
        if application.isGranted {
            return 0
        }

        let status = application.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if status == "väntar svar" || status == "pending" || status == "pending decision" {
            return 1
        }
        if status == "avslag" || status == "rejected" || status == "tillbakadragen" || status == "withdrawn" {
            return 2
        }
        return 1
    }

    private func loadLinkedProjects(for authorID: String, authorName: String) -> [ProjectRecord] {
        let linkedProjectNames = {
            let names = store.authorProjectNames(forAuthorID: authorID)
            return names.isEmpty ? store.authorProjectNames(forAuthorName: authorName) : names
        }()
        let linkedProjects = linkedProjectNames
            .compactMap { store.project(named: $0) }
        let uniqueProjects = Dictionary(linkedProjects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values

        return uniqueProjects
            .sorted { lhs, rhs in
                let leftRank = linkedProjectSortRank(lhs)
                let rightRank = linkedProjectSortRank(rhs)
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                let leftLabel = store.projectLabel(for: lhs.nameSv, language: language)
                let rightLabel = store.projectLabel(for: rhs.nameSv, language: language)
                return leftLabel.localizedStandardCompare(rightLabel) == .orderedAscending
            }
    }

    private func loadLinkedMediaAppearances(for authorID: String) -> [CVMediaAppearance] {
        store.mediaAppearances(forAuthorID: authorID)
    }

    private func loadLinkedReviewEntries(for authorID: String) -> [CVReviewEntry] {
        store.reviewEntries(forAuthorID: authorID)
    }

    private func loadLinkedTeachingAssignments(for authorID: String) -> [TeachingAssignment] {
        store.researcherDetailTeachingAssignments(forAuthorID: authorID)
    }

    private func loadLinkedDoctoralCandidates(for authorID: String) -> [DoctoralCandidateRecord] {
        store.doctoralCandidates(forSupervisorAuthorID: authorID)
    }

    private func linkedDateText(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "—"
    }

    private func linkedDateRangeText(from: String, to: String) -> String {
        publicationAuthorLinkedDateRangeText(
            from: from,
            to: to,
            language: language,
            emptyText: "—"
        )
    }

    private func linkedContributionDateText(for contribution: CVConferenceContribution) -> String {
        let rangeText = publicationAuthorLinkedDateRangeText(
            from: contribution.from,
            to: contribution.to,
            language: language,
            emptyText: ""
        )
        return rangeText.nonEmpty ?? contribution.publicationYear.nonEmpty ?? "—"
    }

    private func linkedCongressSubtitle(congress: OrganizationCongress, organizationName: String) -> String {
        let place = [congress.city.nonEmpty, congress.country.nonEmpty]
            .compactMap { $0 }
            .joined(separator: ", ")
            .nonEmpty
        return [organizationName.nonEmpty, place]
            .compactMap { $0 }
            .joined(separator: " - ")
    }

    private func linkedAbstractSubtitle(for contribution: CVConferenceContribution) -> String {
        let meeting = contribution.localizedMeeting(language: language).nonEmpty
        let place = [contribution.meetingCity.nonEmpty, contribution.meetingCountry.nonEmpty]
            .compactMap { $0 }
            .joined(separator: ", ")
            .nonEmpty
        return [meeting, place]
            .compactMap { $0 }
            .joined(separator: " - ")
    }

    private func congressMatchesAuthorParticipation(_ congress: OrganizationCongress, author: PublicationAuthor) -> Bool {
        if congress.participantAuthorIDs.contains(author.id) {
            return true
        }
        if congress.participantNames.contains(where: { linkedAuthorNameMatches($0, author: author) }) {
            return true
        }
        return false
    }

    private func contributionMatchesAuthor(_ contribution: CVConferenceContribution, author: PublicationAuthor) -> Bool {
        contribution.contributorAuthorIDs.contains(author.id) ||
            contribution.presentedByAuthorID == author.id ||
            contribution.contributorNames.contains(where: { linkedAuthorNameMatches($0, author: author) }) ||
            linkedAuthorNameMatches(contribution.presentedBy, author: author)
    }

    private func linkedAuthorNameMatches(_ name: String?, author: PublicationAuthor) -> Bool {
        linkedAuthorNameCandidates(for: author)
            .contains { CongressesWorkspaceView.congressSamePersonText(name, $0) }
    }

    private func linkedAuthorNameCandidates(for author: PublicationAuthor) -> [String] {
        let values = ([author.displayName, author.name] + author.presentedNameCandidates)
            .compactMap(\.trimmedOrNil)
        return Array(NSOrderedSet(array: values)) as? [String] ?? values
    }

    private func linkedCongressParticipationSort(
        _ lhs: PublicationAuthorLinkedCongressParticipationRow,
        _ rhs: PublicationAuthorLinkedCongressParticipationRow
    ) -> Bool {
        let leftDate = linkedSortDate(from: lhs.congress.from, to: lhs.congress.to)
        let rightDate = linkedSortDate(from: rhs.congress.from, to: rhs.congress.to)
        if leftDate != rightDate {
            return leftDate > rightDate
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private func linkedAbstractSort(_ lhs: CVConferenceContribution, _ rhs: CVConferenceContribution) -> Bool {
        let leftDate = linkedSortDate(from: lhs.from, to: lhs.to, year: lhs.publicationYear)
        let rightDate = linkedSortDate(from: rhs.from, to: rhs.to, year: rhs.publicationYear)
        if leftDate != rightDate {
            return leftDate > rightDate
        }
        let leftTitle = lhs.localizedTitle(language: language).nonEmpty ?? lhs.displayTitle
        let rightTitle = rhs.localizedTitle(language: language).nonEmpty ?? rhs.displayTitle
        return leftTitle.localizedStandardCompare(rightTitle) == .orderedAscending
    }

    private func linkedSortDate(from: String, to: String, year: String = "") -> Date {
        if let date = DateParsers.isoDay.date(from: to.nonEmpty ?? from.nonEmpty ?? "") {
            return date
        }
        if let yearValue = Int(year.nonEmpty ?? ""),
           let date = Calendar.current.date(from: DateComponents(year: yearValue, month: 12, day: 31)) {
            return date
        }
        return .distantPast
    }

    private func linkedTeachingTitle(for assignment: TeachingAssignment) -> String {
        if let context = store.teachingCourses.first(where: { $0.id == assignment.contextID }) {
            return context.localizedName(language: language)
        }
        if let activity = assignment.activityName.nonEmpty {
            return activity
        }
        let kind = assignment.kind ?? inferredTeachingAssignmentKind(
            assignment: assignment,
            context: store.teachingCourses.first(where: { $0.id == assignment.contextID })
        )
        return fixedDropdownText(
            kind.translationKey,
            language: language,
            english: kind.defaultEnglishName,
            swedish: kind.defaultSwedishName
        )
    }

    private func linkedTeachingSubtitle(for assignment: TeachingAssignment) -> String {
        let firstDate =
            assignment.periods
                .compactMap { $0.from.nonEmpty ?? $0.to.nonEmpty }
                .first
        let parts = [
            assignment.activityName.nonEmpty,
            assignment.roles.first.map { store.teachingRoleDisplayName($0, language: language) },
            firstDate
        ].compactMap { $0 }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func linkedTeachingDateText(for assignment: TeachingAssignment) -> String {
        guard let period = assignment.periods.first(where: { $0.from.nonEmpty != nil || $0.to.nonEmpty != nil }) else {
            return "—"
        }
        return publicationAuthorLinkedDateRangeText(
            from: period.from,
            to: period.to,
            language: language,
            emptyText: "—"
        )
    }

    private func linkedDoctoralSubtitle(for candidate: DoctoralCandidateRecord) -> String {
        let parts = [
            candidate.doctoralProjectName.nonEmpty,
            candidate.plannedDisputationDate.nonEmpty
        ].compactMap { $0 }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private var isOwnAuthorCard: Bool {
        store.isCurrentUserAuthor(draft) || store.isCurrentUserAuthor(author)
    }

    private var researcherLinkConflictCandidates: [ResearcherLinkConflictCandidate] {
        let draftNameKeys = Set(draft.presentedNameCandidates.map(normalizedResearcherConflictText).filter { !$0.isEmpty })
        let draftInitialLastKey = researcherInitialLastKey(firstName: draft.firstName, lastName: draft.lastName)
        let draftORCID = normalizedResearcherConflictIdentifier(draft.orcid)
        let draftScopus = normalizedResearcherConflictIdentifier(draft.scopus)
        let draftResearcherID = normalizedResearcherConflictIdentifier(draft.researcherID)
        let draftEmails = Set(draft.affiliations.compactMap { normalizedResearcherConflictEmail($0.email).nonEmpty })

        func visibleCandidate(
            _ candidate: PublicationAuthor,
            reason: String,
            normalizedKey: String
        ) -> ResearcherLinkConflictCandidate? {
            guard !store.isDuplicateWarningSuppressed(
                groupKind: .researchers,
                normalizedKey: normalizedKey,
                recordIDs: [draft.id, candidate.id]
            ) else {
                return nil
            }
            return ResearcherLinkConflictCandidate(author: candidate, reason: reason, normalizedKey: normalizedKey)
        }

        return store.publicationAuthors.compactMap { candidate -> ResearcherLinkConflictCandidate? in
            guard candidate.id != draft.id else { return nil }
            if !draftORCID.isEmpty, draftORCID == normalizedResearcherConflictIdentifier(candidate.orcid) {
                return visibleCandidate(candidate, reason: "ORCID", normalizedKey: "inline:orcid:\(draftORCID)")
            }
            if !draftScopus.isEmpty, draftScopus == normalizedResearcherConflictIdentifier(candidate.scopus) {
                return visibleCandidate(candidate, reason: "Scopus ID", normalizedKey: "inline:scopus:\(draftScopus)")
            }
            if !draftResearcherID.isEmpty, draftResearcherID == normalizedResearcherConflictIdentifier(candidate.researcherID) {
                return visibleCandidate(candidate, reason: "ResearcherID", normalizedKey: "inline:researcherid:\(draftResearcherID)")
            }
            let candidateEmails = Set(candidate.affiliations.compactMap { normalizedResearcherConflictEmail($0.email).nonEmpty })
            if !draftEmails.isEmpty, let emailKey = draftEmails.intersection(candidateEmails).sorted().first {
                return visibleCandidate(candidate, reason: language.text("email", "e-post"), normalizedKey: "inline:email:\(emailKey)")
            }
            let candidateNameKeys = Set(candidate.presentedNameCandidates.map(normalizedResearcherConflictText).filter { !$0.isEmpty })
            if !draftNameKeys.isEmpty, let nameKey = draftNameKeys.intersection(candidateNameKeys).sorted().first {
                return visibleCandidate(candidate, reason: language.text("name", "namn"), normalizedKey: "inline:name:\(nameKey)")
            }
            if let draftInitialLastKey,
               draftInitialLastKey == researcherInitialLastKey(firstName: candidate.firstName, lastName: candidate.lastName) {
                return visibleCandidate(
                    candidate,
                    reason: language.text("similar name", "liknande namn"),
                    normalizedKey: "inline:initial-last:\(draftInitialLastKey)"
                )
            }
            return nil
        }
        .sorted { $0.author.displayName.localizedStandardCompare($1.author.displayName) == .orderedAscending }
    }

    private func normalizedResearcherConflictText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func normalizedResearcherConflictIdentifier(_ value: String) -> String {
        normalizedResearcherConflictText(value)
            .replacingOccurrences(of: #"^https?://"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^(orcid\.org/|doi\.org/|dx\.doi\.org/)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^(doi:|pmid:)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\?.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9x]+"#, with: "", options: .regularExpression)
    }

    private func normalizedResearcherConflictEmail(_ value: String) -> String {
        normalizedResearcherConflictText(value)
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    }

    private func researcherInitialLastKey(firstName: String, lastName: String) -> String? {
        guard
            let initial = normalizedResearcherConflictText(firstName).first,
            let last = normalizedResearcherConflictText(lastName).nonEmpty
        else {
            return nil
        }
        return "\(initial)|\(last)"
    }

    private func linkedProjectSortRank(_ project: ProjectRecord) -> Int {
        switch project.projectStatus {
        case .ongoing:
            return 0
        case .planned:
            return 1
        case .completed:
            return 2
        }
    }

    private var affiliationOrganizations: [String] {
        cachedOrganizationOptions.affiliationOptions
    }

    private var currentLinkedDataCacheKey: String {
        [author.id, author.name, linkedDataGenerationKey].joined(separator: "|")
    }

    private func undoRevealIsActive(fieldKey: String) -> Bool {
        store.undoRevealRequest?.target.matchesField(
            routeDestination: .people,
            recordID: author.id,
            fieldKey: fieldKey
        ) == true
    }

    private func emptyLinkedDataCacheEntry(for authorID: String, authorName: String) -> PublicationAuthorLinkedDataCacheEntry {
        PublicationAuthorLinkedDataCacheEntry(
            authorID: authorID,
            cacheKey: [authorID, authorName, linkedDataGenerationKey].joined(separator: "|"),
            publications: [],
            conferenceContributions: [],
            mediaAppearances: [],
            reviewEntries: [],
            teachingAssignments: [],
            doctoralCandidates: [],
            applications: [],
            projects: [],
            projectRelations: [],
            congressParticipations: [],
            abstracts: [],
            calendarEvents: []
        )
    }

    private func buildPrimaryLinkedDataCacheEntry(for authorID: String, authorName: String) -> PublicationAuthorLinkedDataCacheEntry {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let publications = loadLinkedPublications(for: authorID, authorName: authorName)
        let applications = loadLinkedApplications(for: authorID, authorName: authorName).map { application in
            PublicationAuthorLinkedApplicationRow(
                application: application,
                title: application.projectTitleWithOrganization(store: store, language: language)
            )
        }
        let projects = loadLinkedProjects(for: authorID, authorName: authorName).map { project in
            PublicationAuthorLinkedProjectRow(
                project: project,
                label: store.projectLabel(for: project.nameSv, language: language)
            )
        }
        let projectRelations = {
            let relations = store.researcherProjectRelations(forAuthorID: authorID)
            return relations.isEmpty ? store.researcherProjectRelations(forAuthorName: authorName) : relations
        }()
        var entry = emptyLinkedDataCacheEntry(for: authorID, authorName: authorName)
        entry = PublicationAuthorLinkedDataCacheEntry(
            authorID: entry.authorID,
            cacheKey: entry.cacheKey,
            publications: publications,
            conferenceContributions: entry.conferenceContributions,
            mediaAppearances: entry.mediaAppearances,
            reviewEntries: entry.reviewEntries,
            teachingAssignments: entry.teachingAssignments,
            doctoralCandidates: entry.doctoralCandidates,
            applications: applications,
            projects: projects,
            projectRelations: projectRelations,
            congressParticipations: entry.congressParticipations,
            abstracts: entry.abstracts,
            calendarEvents: entry.calendarEvents
        )
        store.recordCacheProfile(
            scope: "researcher-detail",
            cacheName: "linked-primary",
            itemCount: publications.count + applications.count + projects.count + projectRelations.count,
            startedAt: startedAt,
            detail: "author=\(authorID)"
        )
        return entry
    }

    private var visibleLinkedPublications: [PublicationRecord] {
        guard cachedLinkedDataEntry?.authorID == author.id else { return [] }
        return cachedLinkedDataEntry?.publications ?? []
    }

    private var visibleLinkedConferenceContributions: [PublicationAuthorLinkedConferenceContributionRow] {
        guard cachedLinkedDataEntry?.authorID == author.id else { return [] }
        return cachedLinkedDataEntry?.conferenceContributions ?? []
    }

    private var visibleLinkedMediaAppearances: [PublicationAuthorLinkedMediaAppearanceRow] {
        guard cachedLinkedDataEntry?.authorID == author.id else { return [] }
        return cachedLinkedDataEntry?.mediaAppearances ?? []
    }

    private var visibleLinkedReviewEntries: [PublicationAuthorLinkedReviewRow] {
        guard cachedLinkedDataEntry?.authorID == author.id else { return [] }
        return cachedLinkedDataEntry?.reviewEntries ?? []
    }

    private var visibleLinkedTeachingAssignments: [PublicationAuthorLinkedTeachingAssignmentRow] {
        guard cachedLinkedDataEntry?.authorID == author.id else { return [] }
        return cachedLinkedDataEntry?.teachingAssignments ?? []
    }

    private var visibleLinkedDoctoralCandidates: [PublicationAuthorLinkedDoctoralCandidateRow] {
        guard cachedLinkedDataEntry?.authorID == author.id else { return [] }
        return cachedLinkedDataEntry?.doctoralCandidates ?? []
    }

    private var visibleLinkedApplications: [PublicationAuthorLinkedApplicationRow] {
        guard cachedLinkedDataEntry?.authorID == author.id else { return [] }
        return cachedLinkedDataEntry?.applications ?? []
    }

    private var visibleLinkedProjects: [PublicationAuthorLinkedProjectRow] {
        guard cachedLinkedDataEntry?.authorID == author.id else { return [] }
        return cachedLinkedDataEntry?.projects ?? []
    }

    private var visibleProjectRelations: [GrantDataStore.ResearcherProjectRelation] {
        guard cachedLinkedDataEntry?.authorID == author.id else { return [] }
        return cachedLinkedDataEntry?.projectRelations ?? []
    }

    private var visibleLinkedCongressParticipations: [PublicationAuthorLinkedCongressParticipationRow] {
        guard cachedLinkedDataEntry?.authorID == author.id else { return [] }
        return cachedLinkedDataEntry?.congressParticipations ?? []
    }

    private var visibleLinkedAbstracts: [PublicationAuthorLinkedAbstractRow] {
        guard cachedLinkedDataEntry?.authorID == author.id else { return [] }
        return cachedLinkedDataEntry?.abstracts ?? []
    }

    private var visibleLinkedCalendarEvents: [CalendarLinkedEventRow] {
        guard cachedLinkedDataEntry?.authorID == author.id else { return [] }
        return cachedLinkedDataEntry?.calendarEvents ?? []
    }

    private var researcherStatisticRows: [ContributorStatisticRow] {
        let publishedPublicationCount = visibleLinkedPublications.filter(\.isPublished).count
        return [
            ContributorStatisticRow(
                label: language.text("Projects", "Projekt"),
                value: "\(visibleLinkedProjects.count)"
            ),
            ContributorStatisticRow(
                label: language.text("Applications", "Ansökningar"),
                value: "\(visibleLinkedApplications.count)"
            ),
            ContributorStatisticRow(
                label: language.text("Publications", "Publikationer"),
                value: "\(visibleLinkedPublications.count)",
                detail: language.text("of which \(publishedPublicationCount) published", "varav \(publishedPublicationCount) publicerade")
            ),
            ContributorStatisticRow(
                label: language.text("Congresses", "Kongresser"),
                value: "\(visibleLinkedCongressParticipations.count)"
            ),
            ContributorStatisticRow(
                label: language.text("Abstracts", "Abstracts"),
                value: "\(visibleLinkedAbstracts.count)"
            ),
        ]
    }

    private func applyLinkedDataCacheEntry(_ entry: PublicationAuthorLinkedDataCacheEntry, revealPanels: Bool, reason: String) {
        cachedLinkedDataEntry = entry
        logCoauthorPhase(
            "linked-data-applied",
            details: "reason=\(reason) reveal=\(revealPanels ? "yes" : "no") publications=\(entry.publications.count) conference=\(entry.conferenceContributions.count) media=\(entry.mediaAppearances.count) reviews=\(entry.reviewEntries.count) teaching=\(entry.teachingAssignments.count) doctoral=\(entry.doctoralCandidates.count) applications=\(entry.applications.count) projects=\(entry.projects.count) congresses=\(entry.congressParticipations.count) abstracts=\(entry.abstracts.count)"
        )
        if revealPanels {
            startStagedLinkedPanelReveal()
        }
        store.appendPerformanceDiagnostic(
            String(
                format: "coauthor-linked-cache-hit author=%@ reason=%@ publications=%ld conference=%ld media=%ld reviews=%ld teaching=%ld doctoral=%ld applications=%ld projects=%ld",
                author.name,
                reason,
                entry.publications.count,
                entry.conferenceContributions.count,
                entry.mediaAppearances.count,
                entry.reviewEntries.count,
                entry.teachingAssignments.count,
                entry.doctoralCandidates.count,
                entry.applications.count,
                entry.projects.count
            )
        )
    }

    private func startStagedLinkedPanelReveal() {
        let isFreshReveal = !showDeferredLinkedSections || deferredSectionsPreparedForAuthorID != author.id
        if isFreshReveal {
            visibleLinkedPanelStage = 0
        }
        showDeferredLinkedSections = true
        deferredSectionsPreparedForAuthorID = author.id
        visibleLinkedPanelStage = max(visibleLinkedPanelStage, 1)
        store.appendPerformanceDiagnostic("coauthor-linked-panels-ready author=\(author.name) stage=1")
        store.appendPerformanceDiagnostic(
            String(
                format: "coauthor-linked-panels-ready-timing author=%@ since_editor_appear_ms=%.2f",
                author.name,
                millisecondsSinceEditorAppear()
            )
        )

        let generation = deferredWorkGeneration
        let authorID = author.id
        for stage in 2...3 where visibleLinkedPanelStage < stage {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(stage - 1) * 0.14) {
                guard isActive,
                      deferredWorkGeneration == generation,
                      deferredSectionsPreparedForAuthorID == authorID,
                      showDeferredLinkedSections else { return }
                visibleLinkedPanelStage = max(visibleLinkedPanelStage, stage)
                logCoauthorPhase("linked-panel-stage", details: "stage=\(stage)")
            }
        }
    }

    private func applyCurrentAuthorLinkedDataIfAvailable(revealPanels: Bool, reason: String) {
        logCoauthorPhase("linked-data-apply-request", details: "reason=\(reason) reveal=\(revealPanels ? "yes" : "no")")
        if let cachedEntry = linkedDataCache.entries[author.id],
           cachedEntry.cacheKey == currentLinkedDataCacheKey {
            applyLinkedDataCacheEntry(cachedEntry, revealPanels: revealPanels, reason: reason)
        } else {
            let entry = buildPrimaryLinkedDataCacheEntry(for: author.id, authorName: author.name)
            linkedDataCache.entries[author.id] = entry
            linkedDataCache.cacheSignature = linkedDataGenerationKey
            applyLinkedDataCacheEntry(entry, revealPanels: revealPanels, reason: reason)
            scheduleStagedAuthorLinkedData(authorID: author.id, authorName: author.name, cacheKey: entry.cacheKey)
        }
        scheduleAuthorCalendarEventsRefresh(
            reason: reason,
            delay: revealPanels ? 0.12 : 0.04
        )
    }

    private func scheduleStagedAuthorLinkedData(authorID: String, authorName: String, cacheKey: String) {
        scheduleLinkedDataStage(task: &deferredLinkedDisseminationTask, delay: 0.04) {
            applyLinkedDisseminationStage(authorID: authorID, authorName: authorName, cacheKey: cacheKey)
        }
        scheduleLinkedDataStage(task: &deferredLinkedExpertTeachingTask, delay: 0.09) {
            applyLinkedExpertTeachingStage(authorID: authorID, authorName: authorName, cacheKey: cacheKey)
        }
        scheduleLinkedDataStage(task: &deferredLinkedCongressTask, delay: 0.14) {
            applyLinkedCongressStage(authorID: authorID, authorName: authorName, cacheKey: cacheKey)
        }
    }

    private func scheduleLinkedDataStage(
        task: inout DispatchWorkItem?,
        delay: TimeInterval,
        action: @escaping () -> Void
    ) {
        task?.cancel()
        let generation = deferredWorkGeneration
        let workItem = DispatchWorkItem {
            guard deferredWorkGeneration == generation, isActive else { return }
            action()
        }
        task = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func applyLinkedDisseminationStage(authorID: String, authorName: String, cacheKey: String) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let conferenceContributions = store.publishedConferenceContributions(forAuthorID: authorID).map { contribution in
            PublicationAuthorLinkedConferenceContributionRow(
                contribution: contribution,
                title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                yearText: contribution.publicationYear.nonEmpty ?? contribution.to.nonEmpty ?? contribution.from
            )
        }
        let mediaAppearances = loadLinkedMediaAppearances(for: authorID).map { appearance in
            PublicationAuthorLinkedMediaAppearanceRow(
                appearance: appearance,
                title: appearance.localizedTitle(language: language).nonEmpty ?? appearance.displayTitle,
                dateText: linkedDateText(appearance.publicationDate)
            )
        }
        updateLinkedDataEntry(authorID: authorID, cacheKey: cacheKey) { entry in
            PublicationAuthorLinkedDataCacheEntry(
                authorID: entry.authorID,
                cacheKey: entry.cacheKey,
                publications: entry.publications,
                conferenceContributions: conferenceContributions,
                mediaAppearances: mediaAppearances,
                reviewEntries: entry.reviewEntries,
                teachingAssignments: entry.teachingAssignments,
                doctoralCandidates: entry.doctoralCandidates,
                applications: entry.applications,
                projects: entry.projects,
                projectRelations: entry.projectRelations,
                congressParticipations: entry.congressParticipations,
                abstracts: entry.abstracts,
                calendarEvents: entry.calendarEvents
            )
        }
        store.recordCacheProfile(
            scope: "researcher-detail",
            cacheName: "linked-dissemination",
            itemCount: conferenceContributions.count + mediaAppearances.count,
            startedAt: startedAt,
            detail: "author=\(authorID) name=\(authorName)"
        )
    }

    private func applyLinkedExpertTeachingStage(authorID: String, authorName: String, cacheKey: String) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let reviewEntries = loadLinkedReviewEntries(for: authorID).map { review in
            PublicationAuthorLinkedReviewRow(
                review: review,
                title: review.displayTitle,
                dateText: linkedDateText(review.date)
            )
        }
        let teachingAssignments = loadLinkedTeachingAssignments(for: authorID).map { assignment in
            PublicationAuthorLinkedTeachingAssignmentRow(
                assignment: assignment,
                title: linkedTeachingTitle(for: assignment),
                subtitle: linkedTeachingSubtitle(for: assignment),
                dateText: linkedTeachingDateText(for: assignment)
            )
        }
        let doctoralCandidates = loadLinkedDoctoralCandidates(for: authorID).map { candidate in
            PublicationAuthorLinkedDoctoralCandidateRow(
                candidate: candidate,
                title: candidate.candidateName.nonEmpty ?? language.text("Unnamed doctoral candidate", "Namnlös doktorand"),
                subtitle: linkedDoctoralSubtitle(for: candidate)
            )
        }
        updateLinkedDataEntry(authorID: authorID, cacheKey: cacheKey) { entry in
            PublicationAuthorLinkedDataCacheEntry(
                authorID: entry.authorID,
                cacheKey: entry.cacheKey,
                publications: entry.publications,
                conferenceContributions: entry.conferenceContributions,
                mediaAppearances: entry.mediaAppearances,
                reviewEntries: reviewEntries,
                teachingAssignments: teachingAssignments,
                doctoralCandidates: doctoralCandidates,
                applications: entry.applications,
                projects: entry.projects,
                projectRelations: entry.projectRelations,
                congressParticipations: entry.congressParticipations,
                abstracts: entry.abstracts,
                calendarEvents: entry.calendarEvents
            )
        }
        store.recordCacheProfile(
            scope: "researcher-detail",
            cacheName: "linked-expert-teaching",
            itemCount: reviewEntries.count + teachingAssignments.count + doctoralCandidates.count,
            startedAt: startedAt,
            detail: "author=\(authorID) name=\(authorName)"
        )
    }

    private func applyLinkedCongressStage(authorID: String, authorName: String, cacheKey: String) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let congressParticipations = loadLinkedCongressParticipations(for: author)
        let abstracts = loadLinkedAbstracts(for: author)
        updateLinkedDataEntry(authorID: authorID, cacheKey: cacheKey) { entry in
            PublicationAuthorLinkedDataCacheEntry(
                authorID: entry.authorID,
                cacheKey: entry.cacheKey,
                publications: entry.publications,
                conferenceContributions: entry.conferenceContributions,
                mediaAppearances: entry.mediaAppearances,
                reviewEntries: entry.reviewEntries,
                teachingAssignments: entry.teachingAssignments,
                doctoralCandidates: entry.doctoralCandidates,
                applications: entry.applications,
                projects: entry.projects,
                projectRelations: entry.projectRelations,
                congressParticipations: congressParticipations,
                abstracts: abstracts,
                calendarEvents: entry.calendarEvents
            )
        }
        store.recordCacheProfile(
            scope: "researcher-detail",
            cacheName: "linked-congress",
            itemCount: congressParticipations.count + abstracts.count,
            startedAt: startedAt,
            detail: "author=\(authorID) name=\(authorName)"
        )
    }

    private func updateLinkedDataEntry(
        authorID: String,
        cacheKey: String,
        transform: (PublicationAuthorLinkedDataCacheEntry) -> PublicationAuthorLinkedDataCacheEntry
    ) {
        guard let entry = cachedLinkedDataEntry,
              entry.authorID == authorID,
              entry.cacheKey == cacheKey else {
            return
        }
        let updated = transform(entry)
        cachedLinkedDataEntry = updated
        if linkedDataCache.entries[authorID]?.cacheKey == cacheKey {
            linkedDataCache.entries[authorID] = updated
        }
    }

    private func scheduleAuthorCalendarEventsRefresh(reason: String, delay: TimeInterval) {
        linkedCalendarRefreshTask?.cancel()
        guard isActive else { return }
        let authorID = author.id
        let authorName = author.name
        let generation = deferredWorkGeneration
        let task = DispatchWorkItem {
            guard deferredWorkGeneration == generation, isActive, author.id == authorID else { return }
            refreshAuthorCalendarEvents(authorID: authorID, authorName: authorName, reason: reason)
        }
        linkedCalendarRefreshTask = task
        if delay <= 0 {
            DispatchQueue.main.async(execute: task)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
        }
    }

    private func refreshAuthorCalendarEvents(authorID: String, authorName: String, reason: String) {
        let rows = calendarLinkedEventRows(
            store: store,
            language: language,
            scope: .researcher(authorName)
        )
        guard var entry = cachedLinkedDataEntry, entry.authorID == authorID else { return }
        entry = PublicationAuthorLinkedDataCacheEntry(
            authorID: entry.authorID,
            cacheKey: entry.cacheKey,
            publications: entry.publications,
            conferenceContributions: entry.conferenceContributions,
            mediaAppearances: entry.mediaAppearances,
            reviewEntries: entry.reviewEntries,
            teachingAssignments: entry.teachingAssignments,
            doctoralCandidates: entry.doctoralCandidates,
            applications: entry.applications,
            projects: entry.projects,
            projectRelations: entry.projectRelations,
            congressParticipations: entry.congressParticipations,
            abstracts: entry.abstracts,
            calendarEvents: rows
        )
        cachedLinkedDataEntry = entry
        if let cached = linkedDataCache.entries[authorID], cached.cacheKey == entry.cacheKey {
            linkedDataCache.entries[authorID] = entry
        }
        store.appendPerformanceDiagnostic(
            "coauthor-calendar-events-refreshed author=\(authorName) reason=\(reason) rows=\(rows.count)"
        )
    }

    private func resetCollapsibleProfilePanels() {
        isDoctoralThesisPanelCollapsed = true
        isPersonalResumePanelCollapsed = true
    }

    private func logCoauthorPhase(_ phase: String, details: String = "") {
        let suffix = details.isEmpty ? "" : " \(details)"
        store.appendPerformanceDiagnostic(
            "coauthor-phase author=\(author.name) phase=\(phase) since_editor_appear_ms=\(Self.formattedMilliseconds(millisecondsSinceEditorAppear()))\(suffix)"
        )
    }

    private func handleAuthorChange() {
        logCoauthorPhase("author-change-start", details: "own=\(isOwnAuthorCard ? "yes" : "no")")
        autosaveTask?.cancel()
        forcedPersistTask?.cancel()
        lastLocalAutosaveSnapshot = nil
        draft = author
        nameVariantRows = Self.editableNameVariantRows(for: author.nameVariantRows)
        logCoauthorPhase("author-change-draft-reset")
        pendingAffiliationRowID = UUID().uuidString
        logCoauthorPhase("author-change-pending-affiliation-reset")
        ensureTrailingEditorRows()
        logCoauthorPhase(
            "author-change-trailing-rows-ready",
            details: "affiliations=\(draft.affiliations.count) employments=\(draft.employments.count) education=\(draft.educationEntries.count)"
        )
        resetCollapsibleProfilePanels()
        logCoauthorPhase("author-change-panels-collapsed")
        showPrimarySections = false
        showDeferredProfileSections = false
        showDeferredLinkedSections = false
        visibleLinkedPanelStage = 0
        deferredSectionsPreparedForAuthorID = nil
        logCoauthorPhase("author-change-reveal-reset")
        resetEditorPanelReadyTracking()
        logCoauthorPhase("author-change-panel-tracking-reset")
        schedulePrimarySectionsReveal(forceReset: true)
        scheduleDeferredProfileSections(forceReset: true)
        scheduleDeferredLinkedSections(for: author.name, forceReset: true)
        logCoauthorPhase(
            "author-change-sections-scheduled",
            details: "own=\(isOwnAuthorCard ? "yes" : "no")"
        )
    }

    private func handleAuthorRecordChange(_ newAuthor: PublicationAuthor) {
        logCoauthorPhase("author-record-change")
        if consumeLocalAutosaveEcho(newAuthor) {
            logCoauthorPhase("author-record-local-echo-suppressed")
            return
        }
        handleAuthorChange()
    }

    private func consumeLocalAutosaveEcho(_ newAuthor: PublicationAuthor) -> Bool {
        guard let lastLocalAutosaveSnapshot,
              newAuthor.id == lastLocalAutosaveSnapshot.id else {
            return false
        }

        var normalizedNewAuthor = newAuthor
        normalizedNewAuthor.normalize()
        var normalizedLocalSnapshot = lastLocalAutosaveSnapshot
        normalizedLocalSnapshot.normalize()

        guard normalizedNewAuthor == normalizedLocalSnapshot else {
            return false
        }

        self.lastLocalAutosaveSnapshot = nil
        return true
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    authorHeader(language: language)
                        .background(editorPanelReadyReporter("header"))
                    if !researcherLinkConflictCandidates.isEmpty {
                        researcherConflictWarning(language: language)
                    }
                    corePanel(language: language)
                        .background(editorPanelReadyReporter("core"))
                    if showPrimarySections {
                        affiliationsPanel(language: language)
                            .background(editorPanelReadyReporter("affiliations"))
                        ResearcherPublicationAddressPanel(
                            lines: store.publicationAddressLines(for: draft),
                            language: language
                        )
                    }
                }
                .background(editorPanelReadyReporter("shell"))

                if showDeferredLinkedSections {
                    VStack(alignment: .leading, spacing: 12) {
                        if visibleLinkedPanelStage >= 1 {
                            HStack(alignment: .top, spacing: 12) {
                                AuthorLinkedProjectsPanel(
                                    store: store,
                                    language: language,
                                    projects: visibleLinkedProjects
                                )
                                    .background(editorPanelReadyReporter("linked-projects"))
                                AuthorLinkedApplicationsPanel(
                                    store: store,
                                    language: language,
                                    applications: visibleLinkedApplications
                                )
                                    .background(editorPanelReadyReporter("linked-applications"))
                                AuthorLinkedPublicationsPanel(
                                    store: store,
                                    language: language,
                                    publications: visibleLinkedPublications,
                                    conferenceContributions: visibleLinkedConferenceContributions
                                )
                                    .background(editorPanelReadyReporter("linked-publications"))
                            }
                        }

                        if visibleLinkedPanelStage >= 2 {
                            HStack(alignment: .top, spacing: 12) {
                                AuthorLinkedDisseminationPanel(
                                    store: store,
                                    language: language,
                                    abstracts: visibleLinkedAbstracts,
                                    congressParticipations: visibleLinkedCongressParticipations,
                                    mediaAppearances: visibleLinkedMediaAppearances
                                )
                                    .background(editorPanelReadyReporter("linked-dissemination"))
                                AuthorLinkedDoctoralCandidatesPanel(
                                    store: store,
                                    language: language,
                                    doctoralCandidates: visibleLinkedDoctoralCandidates
                                )
                                    .background(editorPanelReadyReporter("linked-doctoral"))
                                AuthorLinkedCalendarEventsPanel(
                                    store: store,
                                    language: language,
                                    rows: visibleLinkedCalendarEvents
                                )
                                    .background(editorPanelReadyReporter("linked-calendar-events"))
                            }
                        }
                    }
                    .background(editorPanelReadyReporter("linked-summary"))
                }
            }
            .padding(14)
        }
        .background(AppPalette.detailPanelSurface)
        .onAppear {
            let appearStartedAt = CFAbsoluteTimeGetCurrent()
            editorAppearStartedAt = appearStartedAt
            store.appendPerformanceDiagnostic("coauthor-editor-appear-start author=\(author.name) own=\(isOwnAuthorCard ? "yes" : "no")")
            cancelDeferredAuthorWorkTasks(resetVisibleSections: false)
            resetEditorPresentationState()
            resetEditorPanelReadyTracking()
            ensureTrailingEditorRows()
            if isActive {
                schedulePrimarySectionsReveal(forceReset: true)
                scheduleDeferredProfileSections(forceReset: true)
                scheduleDeferredLinkedSections(for: author.name, forceReset: true)
            } else {
                showPrimarySections = false
                showDeferredProfileSections = false
                showDeferredLinkedSections = false
                visibleLinkedPanelStage = 0
            }
            let syncDuration = (CFAbsoluteTimeGetCurrent() - appearStartedAt) * 1000
            store.appendPerformanceDiagnostic(
                String(
                    format: "coauthor-editor-appear-sync author=%@ sync_ms=%.2f",
                    author.name,
                    syncDuration
                )
            )
            logCoauthorPhase(
                "editor-onAppear-complete",
                details: "showPrimary=\(showPrimarySections ? "yes" : "no") showProfile=\(showDeferredProfileSections ? "yes" : "no") showLinked=\(showDeferredLinkedSections ? "yes" : "no")"
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSControl.textDidEndEditingNotification)) { notification in
            let objectType = notification.object.map { String(describing: type(of: $0)) } ?? "nil"
            store.appendPerformanceDiagnostic(
                "coauthor-text-end-editing author=\(author.name) source=nscontrol object=\(objectType)"
            )
            scheduleAutosave(reason: "nscontrol-text-end")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSText.didEndEditingNotification)) { notification in
            let objectType = notification.object.map { String(describing: type(of: $0)) } ?? "nil"
            store.appendPerformanceDiagnostic(
                "coauthor-text-end-editing author=\(author.name) source=nstext object=\(objectType)"
            )
            scheduleAutosave(reason: "nstext-end")
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue != .active {
                requestImmediateAutosave()
            }
        }
        .onChange(of: organizationGeneration) { _, _ in
            scheduleOrganizationCacheRefresh(reason: "organizations-change", delay: 0, forceReload: true)
        }
        .onChange(of: language) { _, _ in
            scheduleOrganizationCacheRefresh(reason: "language-change", delay: 0, forceReload: true)
        }
        .onChange(of: nameVariantRows) { _, newValue in
            draft.nameVariantRows = normalizedPublicationAuthorNameVariantRows(
                newValue,
                currentFirstName: draft.firstName,
                currentLastName: draft.lastName,
                excluding: [draft.name, draft.displayName]
            )
        }
        .onChange(of: linkedDataGenerationKey) { _, _ in
            if isActive {
                logCoauthorPhase("linked-data-generation-change")
                schedulePrimarySectionsReveal(forceReset: false)
                scheduleDeferredProfileSections(forceReset: true)
                scheduleDeferredLinkedSections(for: author.name, forceReset: true)
            }
        }
        .onChange(of: author.id) { _, _ in
            logCoauthorPhase("author-id-change")
            handleAuthorChange()
        }
        .onChange(of: author) { oldValue, newValue in
            guard oldValue.id == newValue.id else { return }
            handleAuthorRecordChange(newValue)
        }
        .onChange(of: isActive) { _, active in
            logCoauthorPhase("active-change", details: "active=\(active ? "yes" : "no")")
            if active {
                schedulePrimarySectionsReveal(forceReset: deferredSectionsPreparedForAuthorID != author.id)
                scheduleOrganizationCacheRefresh(reason: "became-active", delay: 0)
                scheduleDeferredProfileSections(forceReset: deferredSectionsPreparedForAuthorID != author.id)
                scheduleDeferredLinkedSections(for: author.name, forceReset: deferredSectionsPreparedForAuthorID != author.id)
            } else {
                invalidateDeferredAuthorWork()
                requestImmediateAutosave()
            }
        }
        .onDisappear {
            let teardownStartedAt = CFAbsoluteTimeGetCurrent()
            let pendingSnapshot = persistenceDraft(includePartialPendingAffiliation: true)
            let hasPendingChanges = pendingSnapshot != author
            let shouldCompletePendingSelection = shouldCompletePendingAuthorSelection(for: author.id)
            autosaveTask?.cancel()
            forcedPersistTask?.cancel()
            let autosaveStartedAt = CFAbsoluteTimeGetCurrent()
            autosave(
                baseline: author,
                completePendingSelection: shouldCompletePendingSelection,
                includePartialPendingAffiliation: true,
                reason: "disappear"
            )
            let autosaveDuration = (CFAbsoluteTimeGetCurrent() - autosaveStartedAt) * 1000
            invalidateDeferredAuthorWork()
            let finalizeStartedAt = CFAbsoluteTimeGetCurrent()
            if shouldCompletePendingSelection && !hasPendingChanges {
                store.finalizePendingAuthorSelection(id: author.id)
            }
            let finalizeDuration = (CFAbsoluteTimeGetCurrent() - finalizeStartedAt) * 1000
            let totalDuration = (CFAbsoluteTimeGetCurrent() - teardownStartedAt) * 1000
            store.appendPerformanceDiagnostic(
                String(
                    format: "coauthor-editor-disappear author=%@ changed=%@ autosave_ms=%.2f finalize_ms=%.2f total_ms=%.2f",
                    author.name,
                    hasPendingChanges ? "yes" : "no",
                    autosaveDuration,
                    finalizeDuration,
                    totalDuration
                )
            )
            editorAppearStartedAt = nil
            reportedEditorPanelReadyKeys.removeAll()
        }
    }

    private func clearOrganizationCaches() {
        cachedOrganizationOptions = .empty
        cachedAffiliationOrganizationSet.removeAll()
    }

    private func clearLinkedDataCaches() {
        cachedLinkedDataEntry = nil
    }

    private func schedulePrimarySectionsReveal(forceReset: Bool) {
        primarySectionsRevealTask?.cancel()
        guard isActive else {
            showPrimarySections = false
            logCoauthorPhase("primary-sections-hidden", details: "inactive")
            return
        }
        if !forceReset && showPrimarySections {
            scheduleOrganizationCacheRefresh(reason: "primary-sections-visible", delay: 0)
            return
        }
        showPrimarySections = false
        logCoauthorPhase("primary-sections-schedule", details: "force_reset=\(forceReset ? "yes" : "no")")
        let generation = deferredWorkGeneration
        let task = DispatchWorkItem {
            guard deferredWorkGeneration == generation else { return }
            showPrimarySections = true
            primarySectionsRevealTask = nil
            logCoauthorPhase("primary-sections-fired", details: "force_reset=\(forceReset ? "yes" : "no")")
            scheduleOrganizationCacheRefresh(
                reason: forceReset ? "primary-sections-reset" : "primary-sections-visible",
                delay: 0
            )
        }
        primarySectionsRevealTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + (forceReset ? 0.02 : 0), execute: task)
    }

    private func resetEditorPresentationState() {
        logCoauthorPhase("reset-presentation-start")
        primarySectionsRevealTask?.cancel()
        showPrimarySections = false
        showDeferredProfileSections = false
        showDeferredLinkedSections = false
        visibleLinkedPanelStage = 0
        deferredSectionsPreparedForAuthorID = nil
        clearOrganizationCaches()
        clearLinkedDataCaches()
        resetCollapsibleProfilePanels()
        logCoauthorPhase("reset-presentation-done")
    }

    private func cancelDeferredAuthorWorkTasks(resetVisibleSections: Bool) {
        logCoauthorPhase("cancel-deferred-work-start", details: "reset_visible=\(resetVisibleSections ? "yes" : "no")")
        deferredWorkGeneration &+= 1
        primarySectionsRevealTask?.cancel()
        primarySectionsRevealTask = nil
        organizationCacheRefreshTask?.cancel()
        organizationCacheRefreshTask = nil
        linkedDataRefreshTask?.cancel()
        linkedDataRefreshTask = nil
        linkedCalendarRefreshTask?.cancel()
        linkedCalendarRefreshTask = nil
        deferredProfileSectionsTask?.cancel()
        deferredProfileSectionsTask = nil
        deferredLinkedSectionsTask?.cancel()
        deferredLinkedSectionsTask = nil
        deferredLinkedDisseminationTask?.cancel()
        deferredLinkedDisseminationTask = nil
        deferredLinkedExpertTeachingTask?.cancel()
        deferredLinkedExpertTeachingTask = nil
        deferredLinkedCongressTask?.cancel()
        deferredLinkedCongressTask = nil
        if resetVisibleSections {
            showPrimarySections = false
            showDeferredProfileSections = false
            showDeferredLinkedSections = false
            visibleLinkedPanelStage = 0
        }
        linkedDataRefreshToken &+= 1
        logCoauthorPhase("cancel-deferred-work-done")
    }

    private func invalidateDeferredAuthorWork() {
        logCoauthorPhase("invalidate-deferred-work-start")
        cancelDeferredAuthorWorkTasks(resetVisibleSections: true)
        deferredSectionsPreparedForAuthorID = nil
        clearLinkedDataCaches()
        logCoauthorPhase("invalidate-deferred-work-done")
    }

    private func scheduleOrganizationCacheRefresh(reason: String, delay: TimeInterval, forceReload: Bool = false) {
        organizationCacheRefreshTask?.cancel()
        guard isActive else { return }
        if !forceReload,
           (!cachedOrganizationOptions.employerOptions.isEmpty
            || !cachedOrganizationOptions.institutionOptions.isEmpty
            || !cachedOrganizationOptions.affiliationOptions.isEmpty) {
            return
        }

        let generation = deferredWorkGeneration
        let task = DispatchWorkItem {
            guard deferredWorkGeneration == generation else { return }
            refreshOrganizationCaches(reason: reason)
        }
        organizationCacheRefreshTask = task
        if delay <= 0 {
            DispatchQueue.main.async(execute: task)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
        }
    }

    private func refreshOrganizationCaches(reason: String) {
        let refreshStartedAt = CFAbsoluteTimeGetCurrent()
        let options = store.publicationAuthorOrganizationOptions(language: language)
        cachedOrganizationOptions = options
        cachedAffiliationOrganizationSet = Set(options.affiliationOptions)
        let refreshDuration = (CFAbsoluteTimeGetCurrent() - refreshStartedAt) * 1000
        store.appendPerformanceDiagnostic(
            String(
                format: "coauthor-org-options-ready author=%@ reason=%@ since_editor_appear_ms=%.2f refresh_ms=%.2f affiliation=%ld employer=%ld institution=%ld",
                author.name,
                reason,
                millisecondsSinceEditorAppear(),
                refreshDuration,
                options.affiliationOptions.count,
                options.employerOptions.count,
                options.institutionOptions.count
            )
        )
    }

    private func resetEditorPanelReadyTracking() {
        reportedEditorPanelReadyKeys.removeAll()
    }

    @ViewBuilder
    private func editorPanelReadyReporter(_ panel: String) -> some View {
        PerformanceReadyTriggerReporter(trigger: "\(author.id)::\(panel)") {
            reportEditorPanelReady(panel)
        }
    }

    private func reportEditorPanelReady(_ panel: String) {
        guard editorAppearStartedAt != nil else { return }
        let key = "\(author.id)::\(panel)"
        guard reportedEditorPanelReadyKeys.insert(key).inserted else { return }
        if panel == "shell", showPrimarySections {
            scheduleOrganizationCacheRefresh(reason: "shell-ready", delay: 0.05)
        }
        logCoauthorPhase("panel-ready", details: "panel=\(panel)")
        let suffix = panelDiagnosticSuffix(for: panel)
        store.appendPerformanceDiagnostic(
            "coauthor-panel-ready author=\(author.name) panel=\(panel) since_editor_appear_ms=\(Self.formattedMilliseconds(millisecondsSinceEditorAppear()))\(suffix)"
        )
    }

    private func panelDiagnosticSuffix(for panel: String) -> String {
        switch panel {
        case "header":
            return " own=\(isOwnAuthorCard ? "yes" : "no") has_orcid=\(draft.orcid.trimmedOrNil == nil ? "no" : "yes")"
        case "core":
            return " has_phd=\(draft.hasPhD ? "yes" : "no")"
        case "affiliations":
            return " rows=\(draft.affiliations.count) pending_id=\(pendingAffiliationRowID)"
        case "personal-details":
            return " birthdate=\(draft.birthDate.trimmedOrNil == nil ? "missing" : "present")"
        case "doctoral-thesis":
            return " collapsed=\(isDoctoralThesisPanelCollapsed ? "yes" : "no")"
        case "personal-resume":
            return " collapsed=\(isPersonalResumePanelCollapsed ? "yes" : "no")"
        case "profile":
            return " own=\(isOwnAuthorCard ? "yes" : "no")"
        case "linked-summary":
            return " projects=\(visibleLinkedProjects.count) applications=\(visibleLinkedApplications.count) publications=\(visibleLinkedPublications.count) dissemination=\(visibleLinkedConferenceContributions.count + visibleLinkedMediaAppearances.count) expert=\(visibleLinkedReviewEntries.count) teaching=\(visibleLinkedTeachingAssignments.count + visibleLinkedDoctoralCandidates.count)"
        default:
            if panel == "linked-projects" {
                return " rows=\(visibleLinkedProjects.count)"
            }
            if panel == "linked-applications" {
                return " rows=\(visibleLinkedApplications.count)"
            }
            if panel == "linked-publications" {
                return " rows=\(visibleLinkedPublications.count)"
            }
            if panel == "linked-dissemination" {
                return " rows=\(visibleLinkedConferenceContributions.count + visibleLinkedMediaAppearances.count)"
            }
            if panel == "linked-expert" {
                return " rows=\(visibleLinkedReviewEntries.count)"
            }
            if panel == "linked-teaching" {
                return " rows=\(visibleLinkedTeachingAssignments.count + visibleLinkedDoctoralCandidates.count)"
            }
            return ""
        }
    }

    private static func formattedMilliseconds(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func authorHeader(language: AppLanguage) -> some View {
        let titleFont = NSFont.systemFont(ofSize: 24, weight: .bold)
        let firstNameWidth = authorTitleFieldWidth(
            text: draft.firstName,
            placeholder: language.text("First name", "Förnamn"),
            font: titleFont,
            minimum: 0,
            maximum: 280
        )
        let lastNameWidth = authorTitleFieldWidth(
            text: draft.lastName,
            placeholder: language.text("Last name", "Efternamn"),
            font: titleFont,
            minimum: 0,
            maximum: 360
        )
        let nameFieldSpacing = ((" " as NSString).size(withAttributes: [.font: titleFont]).width).rounded(.up)

        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: nameFieldSpacing) {
                    AppInlineTitleTextField(
                        placeholder: language.text("First name", "Förnamn"),
                        text: binding(\.firstName),
                        font: titleFont,
                        minHeight: 30
                    )
                        .frame(width: firstNameWidth, height: 30, alignment: .leading)
                        .undoRevealPulse(
                            triggerID: store.undoRevealRequest?.id,
                            isActive: undoRevealIsActive(fieldKey: "name")
                        )
                    AppInlineTitleTextField(
                        placeholder: language.text("Last name", "Efternamn"),
                        text: binding(\.lastName),
                        font: titleFont,
                        minHeight: 30
                    )
                        .frame(width: lastNameWidth, height: 30, alignment: .leading)
                        .undoRevealPulse(
                            triggerID: store.undoRevealRequest?.id,
                            isActive: undoRevealIsActive(fieldKey: "name")
                        )
                    if let url = draft.orcidURL {
                        Link(destination: url) {
                            AppInlineLinkLabel(title: "ORCID")
                        }
                        .foregroundStyle(AppPalette.linkAction)
                    }
                    if let url = draft.scopusURL {
                        Link(destination: url) {
                            AppInlineLinkLabel(title: "Scopus")
                        }
                        .foregroundStyle(AppPalette.linkAction)
                    }
                    if let url = draft.webOfScienceURL {
                        Link(destination: url) {
                            AppInlineLinkLabel(title: language.text("Web of Science", "Web of Science"))
                        }
                        .foregroundStyle(AppPalette.linkAction)
                    }
                    if let url = draft.institutionWebsiteURL {
                        Link(destination: url) {
                            AppInlineLinkLabel(title: language.text("Institution", "Institution"))
                        }
                        .foregroundStyle(AppPalette.linkAction)
                    }
                }
                nameVariantsEditor(language: language)
                    .undoRevealPulse(
                        triggerID: store.undoRevealRequest?.id,
                        isActive: undoRevealIsActive(fieldKey: "nameVariantRows")
                    )
            }
            Spacer()
            AppDestructiveActionButton(title: language.text("Delete", "Ta bort")) {
                store.deletePublicationAuthor(id: author.id)
            }
        }
        .frame(minHeight: 34, alignment: .top)
    }

    private func authorTitleFieldWidth(
        text: String,
        placeholder: String,
        font: NSFont,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat {
        let visibleText = text.trimmedOrNil ?? placeholder
        let horizontalCaretAllowance: CGFloat = text.trimmedOrNil == nil ? 18 : 2
        let measured = (visibleText as NSString).size(withAttributes: [.font: font]).width
        return min(maximum, max(minimum, ceil(measured) + horizontalCaretAllowance))
    }

    private func nameVariantsEditor(language: AppLanguage) -> some View {
        let formerNameIndices = nameVariantRows.indices.filter { nameVariantRows[$0].isFormerName }
        let spellingIndices = nameVariantRows.indices.filter { !nameVariantRows[$0].isFormerName }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                AppFieldLabelText(text: language.text("Former names", "Tidigare namn"))
                Button(language.text("Add former name", "Lägg till tidigare namn")) {
                    addNameVariantRow(isFormerName: true)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
            }
            ForEach(formerNameIndices, id: \.self) { index in
                nameVariantRowEditor(index: index, language: language)
            }
            HStack(spacing: 6) {
                AppFieldLabelText(text: language.text("Other spellings", "Andra stavningar"))
                Button(language.text("Add other spelling", "Lägg till annan stavning")) {
                    addNameVariantRow(isFormerName: false)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
            }
            ForEach(spellingIndices, id: \.self) { index in
                nameVariantRowEditor(index: index, language: language)
            }
        }
    }

    @ViewBuilder
    private func nameVariantRowEditor(index: Int, language: AppLanguage) -> some View {
        if nameVariantRows.indices.contains(index) {
            let isPlaceholder = nameVariantRows[index].isEmpty
            let isFormerName = nameVariantRows[index].isFormerName
            HStack(alignment: .center, spacing: 8) {
                TextField(
                    language.text("Previous first name", "Tidigare förnamn"),
                    text: nameVariantBinding(index: index, keyPath: \.firstName)
                )
                .appTextInputChrome()
                .frame(width: 200)
                TextField(
                    language.text("Previous last name", "Tidigare efternamn"),
                    text: nameVariantBinding(index: index, keyPath: \.lastName)
                )
                .appTextInputChrome()
                .frame(width: 200)
                if isFormerName {
                    TextField(
                        language.text("Used until (date or year)", "Användes till (datum eller år)"),
                        text: nameVariantBinding(index: index, keyPath: \.usedUntil)
                    )
                    .appTextInputChrome()
                    .frame(width: 150)
                    .help(language.text(
                        "Last day or year this name was used, e.g. 2024-05-31 or 2024",
                        "Sista dag eller år namnet användes, t.ex. 2024-05-31 eller 2024"
                    ))
                }
                // One drop-down with written-out choices instead of a row of
                // symbols, so the row fits and every choice says what it does.
                Menu(language.text("Choose…", "Välj…")) {
                    Button(isFormerName
                        ? language.text("Is a spelling, not a former name", "Är en stavning, inte ett tidigare namn")
                        : language.text("Is a former name", "Är ett tidigare namn")
                    ) {
                        toggleNameVariantKind(at: index)
                    }
                    if isPlaceholder {
                        Divider()
                        Button(language.text("Remove the empty row", "Ta bort den tomma raden"), role: .destructive) {
                            removeNameVariantRow(at: index)
                        }
                    } else {
                        Button(language.text("Make this the current name", "Gör till aktuellt namn")) {
                            promoteNameVariantRow(at: index)
                        }
                        Divider()
                        Button(
                            language.text(
                                "Replace with current name in all records and remove…",
                                "Ersätt med aktuellt namn i alla poster och ta bort…"
                            ),
                            role: .destructive
                        ) {
                            replaceNameVariantInRecords(at: index)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(.system(size: 12, weight: .semibold))
                .help(language.text(
                    "Choices for this name: move it between former names and spellings, make it the current name, or replace it with the current name in all records (asks first; can be undone).",
                    "Val för detta namn: flytta mellan tidigare namn och stavningar, gör till aktuellt namn, eller ersätt med aktuellt namn i alla poster (frågar först; går att ångra)."
                ))
            }
        }
    }

    private func nameVariantBinding(
        index: Int,
        keyPath: WritableKeyPath<PublicationAuthorNameVariant, String>
    ) -> Binding<String> {
        Binding(
            get: {
                guard nameVariantRows.indices.contains(index) else { return "" }
                return nameVariantRows[index][keyPath: keyPath]
            },
            set: { newValue in
                guard nameVariantRows.indices.contains(index) else { return }
                nameVariantRows[index][keyPath: keyPath] = newValue
            }
        )
    }

    private func addNameVariantRow(isFormerName: Bool = false) {
        nameVariantRows.append(PublicationAuthorNameVariant(isFormerName: isFormerName))
    }

    private func toggleNameVariantKind(at index: Int) {
        guard nameVariantRows.indices.contains(index) else { return }
        nameVariantRows[index].isFormerName.toggle()
        scheduleAutosave(reason: "name-variant-kind")
    }

    private func replaceNameVariantInRecords(at index: Int) {
        guard nameVariantRows.indices.contains(index) else { return }
        let variant = nameVariantRows[index]
        // Save pending edits first so the store works on what is on screen.
        flushAutosaveNow(reason: "name-variant-replace-in-records")
        store.replaceAuthorNameVariantWithCurrentName(authorID: draft.id, variant: variant)
    }

    private func promoteNameVariantRow(at index: Int) {
        guard nameVariantRows.indices.contains(index) else { return }
        guard draft.promoteNameVariant(nameVariantRows[index]) else { return }
        nameVariantRows = Self.editableNameVariantRows(for: draft.nameVariantRows)
        scheduleAutosave(reason: "name-variant-promote")
    }

    private func removeNameVariantRow(at index: Int) {
        guard nameVariantRows.indices.contains(index) else { return }
        let variant = nameVariantRows[index]
        // Records may still store this spelling as their literal author
        // name; removing the variant would orphan those links. Route the
        // removal through the store, which rewrites the references to the
        // current name — after explicit confirmation when published or
        // locked records are affected.
        if !store.authorNameVariantRemovalImpact(authorID: draft.id, variant: variant).isEmpty {
            flushAutosaveNow(reason: "name-variant-delete-linked")
            store.removeAuthorNameVariantRewritingReferences(authorID: draft.id, variant: variant)
            // Rows reload via handleAuthorRecordChange when the store
            // publishes the updated author record.
            return
        }
        nameVariantRows.remove(at: index)
        scheduleAutosave(reason: "name-variant-delete")
    }

    private func researcherConflictWarning(language: AppLanguage) -> some View {
        let candidates = Array(researcherLinkConflictCandidates.prefix(3))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppPalette.statusText(.warning))
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.text("Possible existing researcher", "Möjlig befintlig forskare"))
                        .appTypography(.tableHeader)
                    Text(language.text(
                        "This record matches existing researcher data. Open the existing record if it should be the same person.",
                        "Den här posten matchar befintliga forskardata. Öppna den befintliga posten om det ska vara samma person."
                    ))
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            ForEach(candidates) { candidate in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(candidate.author.displayName)
                        .appTypography(.tableHeader)
                    Text(candidate.reason)
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        if store.ignoreDuplicateWarning(
                            groupKind: .researchers,
                            normalizedKey: candidate.normalizedKey,
                            recordIDs: [draft.id, candidate.author.id]
                        ) {
                            duplicateWarningRefreshToken &+= 1
                        }
                    } label: {
                        Label(language.text("Not duplicate", "Inte dublett"), systemImage: "eye.slash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(language.text("Hide this duplicate warning", "Dölj den här dublettvarningen"))
                    Button(language.text("Open", "Öppna")) {
                        store.openIssue(destination: .people, recordID: candidate.author.id)
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppPalette.fieldSurface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppPalette.chartRed.opacity(0.35), lineWidth: 1))
    }

    private func researcherTextField(_ placeholder: String, text: Binding<String>) -> some View {
        CommitFormattingTextField(
            placeholder: placeholder,
            text: text,
            formatter: { $0 }
        )
        .appTextInputChrome()
    }

    private func corePanel(language: AppLanguage) -> some View {
        PublicationCompactPanel(title: "", usesInnerSurface: false) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    compactField(language.text("Title", "Titel"), width: 140) {
                        researcherTextField(
                            language.text("Title", "Titel"),
                            text: localizedAuthorFieldBinding(.title, language: language)
                        )
                    }
                    .undoRevealPulse(triggerID: store.undoRevealRequest?.id, isActive: undoRevealIsActive(fieldKey: "title"))
                    compactField(language.text("Position", "Position"), width: 140) {
                        researcherTextField(
                            language.text("Position", "Position"),
                            text: localizedAuthorFieldBinding(.position, language: language)
                        )
                    }
                    .undoRevealPulse(triggerID: store.undoRevealRequest?.id, isActive: undoRevealIsActive(fieldKey: "position"))
                    compactField(language.text("Degree", "Examen"), width: 240) {
                        HStack(spacing: 10) {
                            researcherTextField(
                                language.text("Degree", "Examen"),
                                text: localizedAuthorFieldBinding(.degree, language: language)
                            )
                            Toggle("PhD", isOn: Binding(
                                get: { draft.hasPhD },
                                set: { newValue in
                                    let previous = draft
                                    draft.hasPhD = newValue
                                    reconcileCareerStage(previous: previous, forceFromPhDChange: previous.hasPhD != newValue)
                                }
                            ))
                            .appCheckboxStyle()
                            .fixedSize()
                        }
                    }
                    .undoRevealPulse(
                        triggerID: store.undoRevealRequest?.id,
                        isActive: undoRevealIsActive(fieldKey: "degree") || undoRevealIsActive(fieldKey: "hasPhD")
                    )
                    compactField(
                        language.text("Career stage (Frascati 2015)", "Karriärsteg (Frascati 2015)"),
                        width: 280,
                        helpText: PublicationAuthorCareerStage.overviewHelpText
                    ) {
                        frascatiCareerStageField()
                    }
                    .undoRevealPulse(triggerID: store.undoRevealRequest?.id, isActive: undoRevealIsActive(fieldKey: "careerStage"))
                    compactField(language.text("Gender", "Kön"), width: 130) {
                        publicationMenuField(
                            selection: binding(\.gender),
                            options: authorGenderOptions(language: language),
                            width: 130
                        )
                    }
                    .undoRevealPulse(triggerID: store.undoRevealRequest?.id, isActive: undoRevealIsActive(fieldKey: "gender"))
                }
                HStack(spacing: 10) {
                    compactField(language.text("Phone label", "Telefonetikett"), width: 120) {
                        researcherTextField(language.text("Work, home, mobile...", "Arbete, hem, mobil..."), text: binding(\.phoneLabel))
                    }
                    .undoRevealPulse(triggerID: store.undoRevealRequest?.id, isActive: undoRevealIsActive(fieldKey: "phoneLabel"))
                    compactField(language.text("Phone number", "Telefonnummer"), width: 180) {
                        researcherTextField(language.text("Phone number", "Telefonnummer"), text: binding(\.phoneNumber))
                    }
                    .undoRevealPulse(triggerID: store.undoRevealRequest?.id, isActive: undoRevealIsActive(fieldKey: "phoneNumber"))
                    compactField(language.text("Phone label 2", "Telefonetikett 2"), width: 120) {
                        researcherTextField(language.text("Work, home, mobile...", "Arbete, hem, mobil..."), text: binding(\.phoneLabelSecondary))
                    }
                    .undoRevealPulse(triggerID: store.undoRevealRequest?.id, isActive: undoRevealIsActive(fieldKey: "phoneLabelSecondary"))
                    compactField(language.text("Phone number 2", "Telefonnummer 2"), width: 180) {
                        researcherTextField(language.text("Phone number 2", "Telefonnummer 2"), text: binding(\.phoneNumberSecondary))
                    }
                    .undoRevealPulse(triggerID: store.undoRevealRequest?.id, isActive: undoRevealIsActive(fieldKey: "phoneNumberSecondary"))
                }
                HStack(spacing: 10) {
                    compactField("ORCID", width: 180) {
                        AppIdentifierField(kind: .orcid, text: binding(\.orcid), language: language)
                    }
                    .undoRevealPulse(triggerID: store.undoRevealRequest?.id, isActive: undoRevealIsActive(fieldKey: "orcid"))
                    compactField(language.text("Scopus ID", "Scopus ID"), width: 180) {
                        researcherTextField(language.text("Scopus ID", "Scopus ID"), text: binding(\.scopus))
                    }
                    .undoRevealPulse(triggerID: store.undoRevealRequest?.id, isActive: undoRevealIsActive(fieldKey: "scopus"))
                    compactField(language.text("Web of Science ResearcherID", "Web of Science ResearcherID"), width: 220) {
                        researcherTextField(language.text("Web of Science ResearcherID", "Web of Science ResearcherID"), text: binding(\.researcherID))
                    }
                    .undoRevealPulse(triggerID: store.undoRevealRequest?.id, isActive: undoRevealIsActive(fieldKey: "researcherID"))
                    compactField(language.text("Institution website", "Institutionshemsida"), width: 220) {
                        researcherTextField(language.text("Institution website", "Institutionshemsida"), text: binding(\.institutionWebsite))
                    }
                    .undoRevealPulse(triggerID: store.undoRevealRequest?.id, isActive: undoRevealIsActive(fieldKey: "institutionWebsite"))
                }
            }
        }
    }

    private func personalDetailsPanel(language: AppLanguage) -> some View {
        PublicationCompactPanel(title: language.text("Personal details", "Personuppgifter"), usesInnerSurface: false) {
            HStack(alignment: .top, spacing: 10) {
                compactField(language.text("Home address", "Hemadress"), width: 420) {
                    TextField(language.text("Home address", "Hemadress"), text: localizedAuthorFieldBinding(.homeAddress, language: language))
                        .appTextInputChrome()
                }
                .undoRevealPulse(triggerID: store.undoRevealRequest?.id, isActive: undoRevealIsActive(fieldKey: "homeAddress"))
                compactField(language.text("Date of birth", "Födelsedatum"), width: 120) {
                    PlainDateField(text: binding(\.birthDate))
                }
                .undoRevealPulse(triggerID: store.undoRevealRequest?.id, isActive: undoRevealIsActive(fieldKey: "birthDate"))
            }
        }
    }

    private func doctoralThesisPanel(language: AppLanguage) -> some View {
        PublicationCompactPanel(
            title: language.text("Doctoral thesis", "Doktorsavhandling"),
            usesInnerSurface: false,
            isCollapsed: $isDoctoralThesisPanelCollapsed
        ) {
            AuthorDoctoralThesisPanel(store: store)
        }
    }

    private func personalResumePanel(language: AppLanguage) -> some View {
        PublicationCompactPanel(
            title: language.text("Personal resume", "Personlig resumé"),
            usesInnerSurface: false,
            isCollapsed: $isPersonalResumePanelCollapsed
        ) {
            AuthorPersonalResumePanel(store: store)
        }
    }

    private func affiliationsPanel(language: AppLanguage) -> some View {
        PublicationCompactPanel(title: language.text("Affiliations", "Affilieringar"), usesInnerSurface: false) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(draft.affiliations.enumerated()), id: \.element.id) { index, affiliation in
                    HStack(spacing: 8) {
                        ReorderHandle(itemID: affiliation.id, draggedItemID: $draggedAffiliationID, language: language)
                            .opacity(affiliation.isEmpty ? 0 : 1)
                            .allowsHitTesting(!affiliation.isEmpty)
                        organizationAutocompleteField(
                            selection: localizedAffiliationOrganizationBinding(index, language: language),
                            options: selectionOptions(affiliationOrganizations, contains: cachedAffiliationOrganizationSet, current: affiliation.organization),
                            placeholder: language.text("Select organization", "Välj organisation"),
                            onCommit: { scheduleAutosave() }
                        )
                        // About 30 % narrower than before, so the unit fits better.
                        .frame(width: 280)
                        if let organization = affiliationOrganizationRecord(for: index, language: language) {
                            AppDestinationActionButton(
                                kind: .app,
                                language: language,
                                title: language.text("Open organization", "Öppna organisation"),
                                fontSize: 12,
                                width: 54,
                                height: AppPalette.fieldMinHeight
                            ) {
                                store.openRoute(for: organization)
                            }
                        } else {
                            AppDestinationPlaceholder(width: 54, height: AppPalette.fieldMinHeight)
                        }
                        OrganizationUnitPickerMenu(
                            organization: affiliationTreeOrganization(for: index),
                            unitID: affiliation.unitID,
                            language: language,
                            // Gets the department field's room when a unit is chosen.
                            width: affiliationHasUnit(at: index) ? 300 : 180
                        ) { unit in
                            selectAffiliationUnit(unit, at: index)
                        }
                        // F48: the chosen unit is the department; the free text is only for rows without a unit.
                        if !affiliationHasUnit(at: index) {
                            TextField(language.text("Department", "Avdelning"), text: localizedAffiliationDepartmentBinding(index, language: language))
                                .appTextInputChrome()
                        }
                        TextField(language.text("City", "Ort"), text: affiliationBinding(index, \.city))
                            .appTextInputChrome()
                            .frame(width: 105)
                        CountryPickerField(selection: affiliationBinding(index, \.country), language: language, width: 100)
                        HStack(alignment: .center, spacing: 8) {
                            TextField(language.text("E-mail", "E-post"), text: affiliationBinding(index, \.email))
                                .appTextInputChrome()
                            if let mailURL = affiliationMailURL(for: index) {
                                AppDestinationURLLink(
                                    kind: .email,
                                    language: language,
                                    destination: mailURL,
                                    fontSize: 12,
                                    width: 62,
                                    height: AppPalette.fieldMinHeight
                                )
                        } else {
                            AppDestinationPlaceholder()
                                .frame(width: 62, height: AppPalette.fieldMinHeight)
                        }
                    }
                        AppIconDeleteButton(
                            title: language.text("Delete affiliation", "Ta bort affiliering"),
                            width: 24
                        ) {
                            guard !affiliation.isEmpty else { return }
                            removeAffiliation(id: affiliation.id)
                        }
                        .frame(width: 24, height: AppPalette.fieldMinHeight)
                        .opacity(affiliation.isEmpty ? 0 : 1)
                        .allowsHitTesting(!affiliation.isEmpty)
                    }
                    .modifier(
                        AffiliationDropModifier(
                            enabled: !affiliation.isEmpty,
                            targetID: affiliation.id,
                            items: $draft.affiliations,
                            draggedItemID: $draggedAffiliationID
                        )
                    )
                }
            }
        }
        .id("affiliations-\(language.rawValue)")
    }

    private func projectsPanel(language: AppLanguage) -> some View {
        AuthorLinkedProjectsPanel(store: store, language: language, projects: visibleLinkedProjects)
    }

    private func projectBadgeColor(for status: ProjectLifecycleStatus) -> Color {
        AppPalette.statusCapsuleFill(AppStatusTones.project(status: status, hasProgress: false))
    }

    private func applicationsPanel(language: AppLanguage) -> some View {
        AuthorLinkedApplicationsPanel(store: store, language: language, applications: visibleLinkedApplications)
    }

    private func publicationsPanel(language: AppLanguage) -> some View {
        AuthorLinkedPublicationsPanel(
            store: store,
            language: language,
            publications: visibleLinkedPublications,
            conferenceContributions: visibleLinkedConferenceContributions
        )
    }

    private func disseminationPanel(language: AppLanguage) -> some View {
        AuthorLinkedDisseminationPanel(
            store: store,
            language: language,
            abstracts: visibleLinkedAbstracts,
            congressParticipations: visibleLinkedCongressParticipations,
            mediaAppearances: visibleLinkedMediaAppearances
        )
    }

    private func doctoralCandidatesPanel(language: AppLanguage) -> some View {
        AuthorLinkedDoctoralCandidatesPanel(
            store: store,
            language: language,
            doctoralCandidates: visibleLinkedDoctoralCandidates
        )
    }

    private func calendarEventsPanel(language: AppLanguage) -> some View {
        AuthorLinkedCalendarEventsPanel(
            store: store,
            language: language,
            rows: visibleLinkedCalendarEvents
        )
    }

    private func publicationSortOrder(_ lhs: PublicationRecord, _ rhs: PublicationRecord) -> Bool {
        let leftStatus = PublicationStatus.fromStored(lhs.statusLabel)
        let rightStatus = PublicationStatus.fromStored(rhs.statusLabel)
        let leftBucket = publicationStatusBucket(for: leftStatus)
        let rightBucket = publicationStatusBucket(for: rightStatus)

        if leftBucket != rightBucket {
            return leftBucket < rightBucket
        }

        switch leftBucket {
        case 0:
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        case 1:
            let leftDate = firstSubmittedDate(for: lhs) ?? .distantPast
            let rightDate = firstSubmittedDate(for: rhs) ?? .distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        default:
            let leftDate = publishedDate(for: lhs) ?? .distantPast
            let rightDate = publishedDate(for: rhs) ?? .distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private func publicationStatusBucket(for status: PublicationStatus) -> Int {
        switch status {
        case .inPreparation:
            return 0
        case .submitted:
            return 1
        default:
            return 2
        }
    }

    private func firstSubmittedDate(for publication: PublicationRecord) -> Date? {
        publication.statusTimeline
            .filter { PublicationStatus.fromStored($0.status).isSubmittedFamily }
            .compactMap { $0.date.flatMap(DateParsers.isoDay.date(from:)) }
            .min()
    }

    private func publishedDate(for publication: PublicationRecord) -> Date? {
        publication.statusTimeline
            .filter { PublicationStatus.fromStored($0.status) == .published }
            .compactMap { $0.date.flatMap(DateParsers.isoDay.date(from:)) }
            .max()
    }

    private func applicationStatusColor(for application: GrantApplication) -> Color {
        AppPalette.statusCapsuleFill(store.applicationStatusTone(application))
    }

    private func dispositionStatus(for application: GrantApplication) -> String {
        if store.isEffectivelyFullySpent(application) {
            return language.text("Spent, no remaining funds", "Disponerat, inga kvarvarande medel")
        }
        let remaining = store.formattedGrantAmountWithSEKApproximation(store.effectiveRemainingGrantedAmountValue(for: application), for: application)
        guard let deadline = application.lastDispositionDate ?? application.receivedUsageTo.flatMap({ DateParsers.isoDay.date(from: $0) }) else {
            return "\(remaining) \(language.text("remaining.", "kvar.")) \(language.text("Last disposition date missing", "Sista disponeringsdatum saknas"))"
        }
        let months = Calendar.current.dateComponents([.month], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: deadline)).month ?? 0
        let dateText = DateParsers.isoDay.string(from: deadline)
        if months < 0 {
            return "\(remaining) \(language.text("remaining.", "kvar.")) \(language.text("Disposition ended", "Disponering slutade")) \(dateText)"
        }
        let monthText = months == 1 ? language.text("in 1 month", "om 1 månad") : language.text("in \(months) months", "om \(months) månader")
        return "\(remaining) \(language.text("remaining.", "kvar.")) \(language.text("Disposition until", "Disponeras senast")) \(dateText) (\(monthText))"
    }

    private func dispositionStatusColor(for application: GrantApplication) -> Color {
        // Round 16: shared disposition thresholds, readable text colours.
        AppPalette.dispositionDeadlineText(application.dispositionDeadlineDate)
    }

    private func persist(completePendingSelection: Bool = false) {
        persist(
            baseline: author,
            completePendingSelection: completePendingSelection,
            includePartialPendingAffiliation: completePendingSelection
        )
    }

    private func persist(
        baseline: PublicationAuthor,
        completePendingSelection: Bool = false,
        includePartialPendingAffiliation: Bool = false
    ) {
        autosaveTask?.cancel()
        let snapshot = persistenceDraft(includePartialPendingAffiliation: includePartialPendingAffiliation)
        let hasChanges = snapshot != baseline
        let shouldFinalize = completePendingSelection && shouldCompletePendingAuthorSelection(for: baseline.id)
        guard hasChanges || shouldFinalize else { return }
        guard hasChanges else {
            if shouldFinalize {
                store.finalizePendingAuthorSelection(id: baseline.id)
            }
            return
        }
        replaceDraftKeepingPendingAffiliation(with: snapshot)
        nameVariantRows = Self.editableNameVariantRows(for: snapshot.nameVariantRows)
        ensureTrailingEditorRows()
        lastLocalAutosaveSnapshot = snapshot
        store.savePublicationAuthor(snapshot, previousName: baseline.name, completePendingSelection: shouldFinalize)
        scheduleLinkedDataRefresh(for: snapshot.id, authorName: snapshot.name, reason: "persist")
    }

    private func autosave(
        baseline: PublicationAuthor,
        completePendingSelection: Bool = false,
        includePartialPendingAffiliation: Bool = false,
        reason: String = "unspecified"
    ) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let snapshot = persistenceDraft(includePartialPendingAffiliation: includePartialPendingAffiliation)
        let hasChanges = snapshot != baseline
        let shouldFinalize = completePendingSelection && shouldCompletePendingAuthorSelection(for: baseline.id)
        guard hasChanges || shouldFinalize else {
            store.appendPerformanceDiagnostic(
                String(
                    format: "coauthor-autosave-outcome author=%@ reason=%@ mode=skip changes=no finalize=no total_ms=%.2f",
                    baseline.name,
                    reason,
                    (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
                )
            )
            return
        }
        guard hasChanges else {
            store.finalizePendingAuthorSelection(id: baseline.id)
            store.appendPerformanceDiagnostic(
                String(
                    format: "coauthor-autosave-outcome author=%@ reason=%@ mode=finalize-only changes=no finalize=yes total_ms=%.2f",
                    baseline.name,
                    reason,
                    (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
                )
            )
            return
        }
        replaceDraftKeepingPendingAffiliation(with: snapshot)
        ensureTrailingEditorRows()
        lastLocalAutosaveSnapshot = snapshot
        store.autosavePublicationAuthor(snapshot, previousName: baseline.name, completePendingSelection: shouldFinalize)
        scheduleLinkedDataRefresh(for: snapshot.id, authorName: snapshot.name, reason: "autosave")
        store.appendPerformanceDiagnostic(
            String(
                format: "coauthor-autosave-outcome author=%@ reason=%@ mode=write changes=yes finalize=%@ total_ms=%.2f",
                snapshot.name,
                reason,
                shouldFinalize ? "yes" : "no",
                (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            )
        )
    }

    private func scheduleAutosave(reason: String = "unspecified") {
        let hadExistingTask = autosaveTask != nil
        autosaveTask?.cancel()
        pendingAutosaveReason = reason
        let scheduledAt = CFAbsoluteTimeGetCurrent()
        pendingAutosaveScheduledAt = scheduledAt
        store.appendPerformanceDiagnostic(
            String(
                format: "coauthor-autosave-scheduled author=%@ reason=%@ replaced_existing=%@",
                author.name,
                reason,
                hadExistingTask ? "yes" : "no"
            )
        )
        let task = DispatchWorkItem {
            let armedMs = pendingAutosaveScheduledAt.map { (CFAbsoluteTimeGetCurrent() - $0) * 1000 } ?? 0
            store.appendPerformanceDiagnostic(
                String(
                    format: "coauthor-autosave-fired author=%@ reason=%@ armed_ms=%.2f",
                    author.name,
                    pendingAutosaveReason,
                    armedMs
                )
            )
            pendingAutosaveScheduledAt = nil
            autosave(baseline: author, reason: pendingAutosaveReason)
        }
        autosaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + autosaveDelay(for: reason), execute: task)
    }

    private func autosaveDelay(for reason: String) -> TimeInterval {
        switch reason {
        case "nscontrol-text-end", "nstext-end":
            return 2.0
        case "name-variant-promote", "name-variant-delete", "affiliation-delete":
            return 0.35
        default:
            return 1.4
        }
    }

    private func requestImmediateAutosave() {
        forcedPersistTask?.cancel()
        let task = DispatchWorkItem {
            forcedPersistTask = nil
            autosave(
                baseline: author,
                completePendingSelection: shouldCompletePendingAuthorSelection(for: author.id),
                includePartialPendingAffiliation: false,
                reason: "immediate"
            )
        }
        forcedPersistTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: task)
    }

    private func flushAutosaveNow(reason: String) {
        autosaveTask?.cancel()
        forcedPersistTask?.cancel()
        pendingAutosaveScheduledAt = nil
        autosave(
            baseline: author,
            completePendingSelection: shouldCompletePendingAuthorSelection(for: author.id),
            includePartialPendingAffiliation: false,
            reason: reason
        )
    }

    private func shouldCompletePendingAuthorSelection(for authorID: String) -> Bool {
        guard let pending = store.pendingSelectionReturn else { return false }
        return pending.entityKind == .author && pending.entityID == authorID
    }

    private enum LocalizedAuthorField {
        case title
        case position
        case degree
        case homeAddress
    }

    private func localizedAuthorFieldBinding(_ field: LocalizedAuthorField, language: AppLanguage) -> Binding<String> {
        Binding(
            get: {
                switch field {
                case .title:
                    return language == .swedish ? draft.titleSv : draft.titleEn
                case .position:
                    return language == .swedish ? draft.positionSv : draft.positionEn
                case .degree:
                    return language == .swedish ? draft.degreeSv : draft.degreeEn
                case .homeAddress:
                    return language == .swedish ? draft.homeAddressSv : draft.homeAddressEn
                }
            },
            set: { newValue in
                let previous = draft
                switch field {
                case .title:
                    draft.setLocalizedTitle(newValue, language: language)
                case .position:
                    draft.setLocalizedPosition(newValue, language: language)
                case .degree:
                    draft.setLocalizedDegree(newValue, language: language)
                case .homeAddress:
                    draft.setLocalizedHomeAddress(newValue, language: language)
                }
                switch field {
                case .title, .position:
                    reconcileCareerStage(previous: previous)
                case .degree, .homeAddress:
                    break
                }
            }
        )
    }

    private func binding(_ keyPath: WritableKeyPath<PublicationAuthor, String>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: {
                draft[keyPath: keyPath] = $0
            }
        )
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<PublicationAuthor, Value>) -> Binding<Value> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: {
                draft[keyPath: keyPath] = $0
            }
        )
    }

    private func authorGenderOptions(language: AppLanguage) -> [(label: String, value: PublicationAuthorGender)] {
        PublicationAuthorGender.allCases.map { gender in
            (gender.displayName(language: language), gender)
        }
    }

    @ViewBuilder
    private func frascatiCareerStageField() -> some View {
        HStack(spacing: 0) {
            ForEach(Array(PublicationAuthorCareerStage.editorDisplayOrder.enumerated()), id: \.element.id) { index, stage in
                frascatiCareerStageButton(for: stage)

                if index < PublicationAuthorCareerStage.editorDisplayOrder.count - 1 {
                    Rectangle()
                        .fill(AppPalette.subtleBorder)
                        .frame(width: 1, height: 18)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppPalette.fieldSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppPalette.subtleBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background {
            AppCompoundFieldFocusBridge(
                onFocusChange: { careerStageIsFocused = $0 },
                onMoveLeft: { moveCareerStageSelection(by: -1) },
                onMoveRight: { moveCareerStageSelection(by: 1) }
            )
        }
        .appKeyboardFocusPulse(isFocused: careerStageIsFocused, cornerRadius: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(language.text("Career stage (Frascati 2015)", "Karriärsteg (Frascati 2015)"))
        .accessibilityValue(draft.careerStage.rawValue)
        .accessibilityAdjustableAction { direction in
            moveCareerStageSelection(by: direction == .increment ? 1 : -1)
        }
    }

    private func moveCareerStageSelection(by offset: Int) {
        let stages = PublicationAuthorCareerStage.editorDisplayOrder
        guard !stages.isEmpty else { return }
        let currentIndex = stages.firstIndex(of: draft.careerStage) ?? 0
        draft.careerStage = stages[min(max(0, currentIndex + offset), stages.count - 1)]
    }

    @ViewBuilder
    private func frascatiCareerStageButton(for stage: PublicationAuthorCareerStage) -> some View {
        let isSelected = draft.careerStage == stage

        Button {
            draft.careerStage = stage
        } label: {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppPalette.activeTabSurface.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(AppPalette.vividBlue, lineWidth: 2.2)
                        )
                        .shadow(color: AppPalette.vividBlue.opacity(0.28), radius: 3, x: 0, y: 0)
                        .padding(2)
                }

                Text(stage.rawValue)
                    .appTypography(.tableHeader)
                    .lineLimit(1)
                    .foregroundStyle(
                        isSelected
                            ? AppPalette.appText
                            : AppPalette.appText.opacity(0.82)
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(stage.helpText)
    }

    private func reconcileCareerStage(
        previous: PublicationAuthor,
        forceFromPhDChange: Bool = false
    ) {
        if forceFromPhDChange {
            guard previous.hasPhD == false, draft.hasPhD else { return }
            if let automaticStage = PublicationAuthor.automaticCareerStageWhenEnablingPhD(from: previous.careerStage) {
                draft.careerStage = automaticStage
            }
            return
        }

        let previousSuggested = previous.suggestedCareerStage
        let currentSuggested = draft.suggestedCareerStage
        if draft.careerStage == previousSuggested {
            draft.careerStage = currentSuggested
        }
    }

    private func affiliationMailURL(for index: Int) -> URL? {
        guard index < draft.affiliations.count else { return nil }
        return mailtoURL(for: draft.affiliations[index].email)
    }

    private func affiliationOrganizationRecord(for index: Int, language: AppLanguage) -> OrganizationRecord? {
        guard index < draft.affiliations.count else { return nil }
        let affiliation = draft.affiliations[index]
        // "Alla kopplingar via id": the linked organization first.
        if let linked = affiliation.organizationID.flatMap({ store.organization(id: $0) }) {
            return linked
        }
        let candidates = [
            affiliation.organizationSv,
            affiliation.organizationEn,
            affiliation.organization
        ].compactMap(\.trimmedOrNil)
        guard !candidates.isEmpty else { return nil }
        return store.organizations.first { organization in
            let labels = [
                store.organizationLabel(for: organization.nameSv, language: language),
                organization.nameSv,
                organization.nameEn
            ].compactMap(\.trimmedOrNil)
            return labels.contains { label in
                candidates.contains { candidate in
                    candidate.caseInsensitiveCompare(label) == .orderedSame
                }
            }
        }
    }

    /// F21: the organization whose units the affiliation's unit picker
    /// lists: the linked organization, else the one the text names.
    private func affiliationTreeOrganization(for index: Int) -> OrganizationRecord? {
        guard index < draft.affiliations.count else { return nil }
        let affiliation = draft.affiliations[index]
        return OrganizationTree.rowOrganization(
            organizationID: affiliation.organizationID,
            organizationTexts: [affiliation.organizationSv, affiliation.organizationEn],
            organizations: store.organizations
        ) ?? affiliationOrganizationRecord(for: index, language: language)
    }

    /// F48: true when the row points to a unit that exists in its organization.
    private func affiliationHasUnit(at index: Int) -> Bool {
        guard index < draft.affiliations.count,
              let unitID = draft.affiliations[index].unitID?.trimmedOrNil else { return false }
        return affiliationTreeOrganization(for: index)?.unit(withID: unitID) != nil
    }

    /// F21: points the affiliation to a unit and writes the organization's
    /// and the unit's official names as the text (round 7: one correct
    /// spelling); "no unit" keeps the department text as it is.
    private func selectAffiliationUnit(_ unit: OrganizationUnit?, at index: Int) {
        guard index < draft.affiliations.count,
              let organization = affiliationTreeOrganization(for: index) else { return }
        draft.affiliations[index].organizationID = organization.id
        draft.affiliations[index].unitID = unit?.id
        draft.affiliations[index].applyOfficialNames(organization: organization, unit: unit)
        draft.affiliations[index].applyPlace(organization: organization, unit: unit)
        normalizeAffiliationRow(at: index)
        ensureTrailingEditorRows()
        synchronizePrimaryAffiliations()
        scheduleAutosave(reason: "affiliation-unit")
    }

    private func mailtoURL(for email: String) -> URL? {
        singleRecipientMailtoURL(email)
    }

    private func affiliationBinding(_ index: Int, _ keyPath: WritableKeyPath<PublicationAffiliation, String>) -> Binding<String> {
        Binding(
            get: {
                guard index < draft.affiliations.count else { return "" }
                return draft.affiliations[index][keyPath: keyPath]
            },
            set: { newValue in
                guard index < draft.affiliations.count else { return }
                draft.affiliations[index][keyPath: keyPath] = newValue
                normalizeAffiliationRow(at: index)
                ensureTrailingEditorRows()
                synchronizePrimaryAffiliations()
            }
        )
    }

    private func localizedAffiliationDepartmentBinding(_ index: Int, language: AppLanguage) -> Binding<String> {
        Binding(
            get: {
                guard index < draft.affiliations.count else { return "" }
                return language == .swedish ? draft.affiliations[index].departmentSv : draft.affiliations[index].departmentEn
            },
            set: { newValue in
                guard index < draft.affiliations.count else { return }
                draft.affiliations[index].setLocalizedDepartment(newValue, language: language)
                normalizeAffiliationRow(at: index)
                ensureTrailingEditorRows()
                synchronizePrimaryAffiliations()
            }
        )
    }

    private func localizedAffiliationOrganizationBinding(_ index: Int, language: AppLanguage) -> Binding<String> {
        Binding(
            get: {
                guard index < draft.affiliations.count else { return "" }
                return language == .swedish ? draft.affiliations[index].organizationSv : draft.affiliations[index].organizationEn
            },
            set: { newValue in
                guard index < draft.affiliations.count else { return }
                let previousText = language == .swedish ? draft.affiliations[index].organizationSv : draft.affiliations[index].organizationEn
                let previousOrganizationID = affiliationTreeOrganization(for: index)?.id
                var matchedName: String?
                if let match = store.organizations.first(where: {
                    store.organizationLabel(for: $0.nameSv, language: language) == newValue || $0.nameSv == newValue || $0.nameEn == newValue
                }) {
                    matchedName = match.nameSv
                    draft.affiliations[index].organizationSv = match.nameSv
                    draft.affiliations[index].organizationEn = match.nameEn.nonEmpty ?? match.nameSv
                } else {
                    draft.affiliations[index].setLocalizedOrganization(newValue, language: language)
                }
                // F21: another organization means another tree; the unit is
                // kept only when it belongs to the new organization.
                let linked = OrganizationTree.relinkedIDs(
                    organizationID: draft.affiliations[index].organizationID,
                    unitID: draft.affiliations[index].unitID,
                    previousOrganizationText: previousText,
                    newOrganizationText: matchedName ?? newValue,
                    organizations: store.organizations
                )
                draft.affiliations[index].organizationID = linked.organizationID
                draft.affiliations[index].unitID = linked.unitID
                // F48: a newly chosen organization fills in city and country.
                if matchedName != nil,
                   let organization = affiliationTreeOrganization(for: index),
                   organization.id != previousOrganizationID {
                    draft.affiliations[index].applyPlace(
                        organization: organization,
                        unit: organization.unit(withID: linked.unitID)
                    )
                }
                normalizeAffiliationRow(at: index)
                ensureTrailingEditorRows()
                synchronizePrimaryAffiliations()
            }
        )
    }

    private func synchronizePrimaryAffiliations() {
        for index in draft.affiliations.indices {
            draft.affiliations[index].isPrimary = index == 0 && !draft.affiliations[index].isEmpty
        }
    }

    private func removeAffiliation(id: String) {
        draft.affiliations.removeAll { $0.id == id }
        if draggedAffiliationID == id {
            draggedAffiliationID = nil
        }
        if pendingAffiliationRowID == id {
            pendingAffiliationRowID = UUID().uuidString
        }
        ensureTrailingEditorRows()
        synchronizePrimaryAffiliations()
        scheduleAutosave(reason: "affiliation-delete")
    }

    private func persistenceDraft(includePartialPendingAffiliation: Bool = false) -> PublicationAuthor {
        var snapshot = draft
        snapshot.nameVariantRows = normalizedPublicationAuthorNameVariantRows(
            nameVariantRows,
            currentFirstName: snapshot.firstName,
            currentLastName: snapshot.lastName,
            excluding: [snapshot.name, snapshot.displayName]
        )
        snapshot.affiliations = persistedAffiliations(
            from: snapshot.affiliations,
            includePendingPlaceholder: includePartialPendingAffiliation
        )
        snapshot.normalize()
        return snapshot
    }

    private func selectionOptions(_ base: [String], current: String) -> [String] {
        selectionOptions(base, contains: Set(base), current: current)
    }

    private func selectionOptions(_ base: [String], contains knownValues: Set<String>, current: String) -> [String] {
        let trimmedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCurrent.isEmpty else { return base }
        guard !knownValues.contains(trimmedCurrent) else { return base }
        return [trimmedCurrent] + base
    }

    private func normalizeEmploymentRow(at index: Int) {
        guard index < draft.employments.count else { return }
        draft.employments[index].normalize()
    }

    private func normalizeAffiliationRow(at index: Int) {
        guard index < draft.affiliations.count else { return }
        draft.affiliations[index].normalize()
    }

    private func normalizeEducationRow(at index: Int) {
        guard index < draft.educationEntries.count else { return }
        draft.educationEntries[index].normalize()
    }

    private func shouldCommitAffiliationRow(_ affiliation: PublicationAffiliation, includePartial: Bool = false) -> Bool {
        var candidate = affiliation
        candidate.normalize()
        guard !candidate.isEmpty else { return false }
        if includePartial {
            return true
        }
        return candidate.organization.nonEmpty != nil
            && (
                candidate.department.nonEmpty != nil
                || candidate.city.nonEmpty != nil
                || candidate.country.nonEmpty != nil
                || candidate.email.nonEmpty != nil
            )
    }

    private func persistedAffiliations(
        from affiliations: [PublicationAffiliation],
        includePendingPlaceholder: Bool
    ) -> [PublicationAffiliation] {
        affiliations.compactMap { row in
            var normalized = row
            normalized.normalize()
            guard !normalized.isEmpty else { return nil }
            if row.id == pendingAffiliationRowID,
               !shouldCommitAffiliationRow(normalized, includePartial: includePendingPlaceholder) {
                return nil
            }
            return normalized
        }
    }

    /// The saved copy leaves out a half-filled new affiliation (for example
    /// only a city typed so far). Replacing the draft with it used to clear
    /// that row while the user was filling it in; the row is kept.
    private func replaceDraftKeepingPendingAffiliation(with snapshot: PublicationAuthor) {
        let pendingRow = draft.affiliations.first { $0.id == pendingAffiliationRowID }
        draft = snapshot
        if let pendingRow, !draft.affiliations.contains(where: { $0.id == pendingRow.id }) {
            draft.affiliations.append(pendingRow)
        }
    }

    private func ensureTrailingEditorRows() {
        let populatedAffiliations = persistedAffiliations(
            from: draft.affiliations,
            includePendingPlaceholder: false
        )
        let pendingAffiliation = draft.affiliations.first(where: { $0.id == pendingAffiliationRowID }) ?? PublicationAffiliation(id: pendingAffiliationRowID)
        var editablePendingAffiliation = pendingAffiliation
        editablePendingAffiliation.normalize()
        let shouldKeepPendingAffiliation = populatedAffiliations.count < 4 && !shouldCommitAffiliationRow(pendingAffiliation)
        let nextPendingAffiliationID = shouldKeepPendingAffiliation ? pendingAffiliationRowID : UUID().uuidString
        let trailingAffiliation = shouldKeepPendingAffiliation
            ? editablePendingAffiliation
            : PublicationAffiliation(id: nextPendingAffiliationID)
        let trailingEmployment = draft.employments.first(where: \.isEmpty) ?? PublicationAuthorEmployment()
        let trailingEducation = draft.educationEntries.first(where: \.isEmpty) ?? PublicationAuthorEducation()

        let populatedEmployments = draft.employments.filter { !$0.isEmpty }
        let populatedEducationEntries = draft.educationEntries.filter { !$0.isEmpty }

        pendingAffiliationRowID = nextPendingAffiliationID
        draft.affiliations = Array(populatedAffiliations.prefix(4))
        if draft.affiliations.count < 4 {
            draft.affiliations.append(trailingAffiliation)
        }
        draft.employments = PublicationAuthor.sortedEmploymentsForEditor(populatedEmployments) + [trailingEmployment]
        draft.educationEntries = PublicationAuthor.sortedEducationEntriesForEditor(populatedEducationEntries) + [trailingEducation]
        synchronizePrimaryAffiliations()
    }

    private func millisecondsSinceEditorAppear() -> Double {
        guard let editorAppearStartedAt else { return -1 }
        return (CFAbsoluteTimeGetCurrent() - editorAppearStartedAt) * 1000
    }

    private func scheduleLinkedDataRefresh(for authorID: String, authorName: String, reason: String = "unspecified", revealPanelsOnApply: Bool = false) {
        guard isActive else { return }
        applyCurrentAuthorLinkedDataIfAvailable(revealPanels: revealPanelsOnApply, reason: reason)
    }

    private func scheduleDeferredProfileSections(forceReset: Bool) {
        deferredProfileSectionsTask?.cancel()
        guard isActive else {
            showDeferredProfileSections = false
            logCoauthorPhase("profile-sections-hidden", details: "inactive")
            return
        }
        guard isOwnAuthorCard else {
            showDeferredProfileSections = false
            logCoauthorPhase("profile-sections-hidden", details: "own=no")
            return
        }
        if !forceReset && showDeferredProfileSections {
            return
        }
        showDeferredProfileSections = false
        logCoauthorPhase(
            "profile-sections-schedule",
            details: "force_reset=\(forceReset ? "yes" : "no") own=yes"
        )
        let generation = deferredWorkGeneration
        let task = DispatchWorkItem {
            guard deferredWorkGeneration == generation else { return }
            showDeferredProfileSections = true
            deferredSectionsPreparedForAuthorID = author.id
            deferredProfileSectionsTask = nil
            logCoauthorPhase("profile-sections-fired", details: "own=yes")
        }
        deferredProfileSectionsTask = task
        DispatchQueue.main.async(execute: task)
    }

    private func scheduleDeferredLinkedSections(for authorName: String, forceReset: Bool) {
        deferredLinkedSectionsTask?.cancel()
        guard isActive else {
            showDeferredLinkedSections = false
            visibleLinkedPanelStage = 0
            logCoauthorPhase("linked-sections-hidden", details: "inactive")
            return
        }
        if !forceReset && showDeferredLinkedSections {
            return
        }
        showDeferredLinkedSections = false
        visibleLinkedPanelStage = 0
        logCoauthorPhase(
            "linked-sections-schedule",
            details: "force_reset=\(forceReset ? "yes" : "no") author_name=\(authorName)"
        )
        let generation = deferredWorkGeneration
        let task = DispatchWorkItem {
            guard deferredWorkGeneration == generation else { return }
            deferredLinkedSectionsTask = nil
            logCoauthorPhase("linked-sections-fired", details: "author_name=\(authorName)")
            applyCurrentAuthorLinkedDataIfAvailable(
                revealPanels: true,
                reason: forceReset ? "author-cache-reset" : "author-cache"
            )
        }
        deferredLinkedSectionsTask = task
        DispatchQueue.main.async(execute: task)
    }

    @ViewBuilder
    private func stringPicker(selection: Binding<String>, options: [String], placeholder: String) -> some View {
        publicationMenuField(
            selection: selection,
            options: [(placeholder, "")] + options.map { ($0, $0) },
            placeholder: placeholder
        )
    }

    @ViewBuilder
    private func organizationAutocompleteField(
        selection: Binding<String>,
        options: [String],
        placeholder: String,
        onCommit: @escaping () -> Void
    ) -> some View {
        AutocompleteSelectionField(
            text: selection,
            options: options,
            placeholder: placeholder,
            onCommit: onCommit,
            onSelect: { _ in onCommit() },
            updatesTextContinuously: true
        )
    }
}

@MainActor
struct AuthorLinkedTitleDateRow: View {
    let title: String
    let dateText: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(dateText)
                .appTypography(.secondary)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

@MainActor
private struct AuthorLinkedProjectsPanel: View, Equatable {
    let store: GrantDataStore
    let language: AppLanguage
    let projects: [PublicationAuthorLinkedProjectRow]

    nonisolated static func == (lhs: AuthorLinkedProjectsPanel, rhs: AuthorLinkedProjectsPanel) -> Bool {
        lhs.language == rhs.language && lhs.projects == rhs.projects
    }

    var body: some View {
        PublicationCompactPanel(title: language.text("Projects", "Projekt"), usesInnerSurface: false) {
            AppCompactReferenceList(isEmpty: projects.isEmpty, emptyTitle: language.text("No records", "Inga poster"), rowSpacing: 0) {
                ForEach(projects) { project in
                        Button(action: {
                            store.openRoute(for: project.project)
                        }) {
                            AppLinkedStatusRow(
                                fill: projectStatusShadeColor(for: project.project),
                                help: project.project.projectStatus.displayName(language: language)
                            ) {
                                Text(project.label)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                        if project.id != projects.last?.id {
                            Divider()
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func projectStatusShadeColor(for project: ProjectRecord) -> Color? {
        // Round 16: the shared project rule (completed grey).
        AppPalette.statusRowFill(store.projectStatusTone(project))
    }
}

@MainActor
private struct AuthorProjectRelationInspectorPanel: View, Equatable {
    let language: AppLanguage
    let relations: [GrantDataStore.ResearcherProjectRelation]

    nonisolated static func == (lhs: AuthorProjectRelationInspectorPanel, rhs: AuthorProjectRelationInspectorPanel) -> Bool {
        lhs.language == rhs.language && lhs.relations == rhs.relations
    }

    var body: some View {
        PublicationCompactPanel(title: "", usesInnerSurface: false) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(relations) { relation in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(relation.projectName)
                                .appTypography(.tableHeader)
                                .lineLimit(1)
                            Text(relation.sourceTitle)
                                .appTypography(.secondary)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(relation.kind.displayName(language: language))
                            .appTypography(.secondary)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Label(
                            relation.countsAsResearchProject
                                ? language.text("Counts as project", "Räknas som projekt")
                                : language.text("Application only", "Bara ansökan"),
                            systemImage: relation.countsAsResearchProject ? "checkmark.circle.fill" : "info.circle"
                        )
                        .appTypography(.tableHeader)
                        .foregroundStyle(relation.countsAsResearchProject ? AppPalette.statusText(.done) : .secondary)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                    }
                    if relation.id != relations.last?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

@MainActor
// Known limitation: the SEK approximations in this panel come from the
// store's exchange-rate state, which neither this == nor SwiftUI's
// fallback field comparison can see — amounts refresh with the next
// author-projection change rather than the moment new rates land.
private struct AuthorLinkedApplicationsPanel: View, Equatable {
    let store: GrantDataStore
    let language: AppLanguage
    let applications: [PublicationAuthorLinkedApplicationRow]

    nonisolated static func == (lhs: AuthorLinkedApplicationsPanel, rhs: AuthorLinkedApplicationsPanel) -> Bool {
        lhs.language == rhs.language && lhs.applications == rhs.applications
    }

    var body: some View {
        PublicationCompactPanel(title: language.text("Applications", "Ansökningar"), usesInnerSurface: false) {
            AppCompactReferenceList(isEmpty: applications.isEmpty, emptyTitle: language.text("No records", "Inga poster"), rowSpacing: 0) {
                ForEach(applications) { application in
                        Button(action: { store.openRoute(for: application.application) }) {
                            AppLinkedStatusRow(
                                fill: applicationStatusShadeColor(for: application.application),
                                help: language.localizedStatus(application.application.resultLabel)
                            ) {
                                AppLinkedTitleTrailingRow(
                                    title: application.title,
                                    trailingText: applicationAmountText(for: application.application)
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        if application.id != applications.last?.id {
                            Divider()
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func applicationStatusShadeColor(for application: GrantApplication) -> Color? {
        AppPalette.statusRowFill(store.applicationStatusTone(application))
    }

    private func applicationAmountText(for application: GrantApplication) -> String {
        let value = application.isToApplyStatus
            ? application.maximumTotalAmountValue
                ?? application.maximumAmountValue
                ?? application.approximateAmountValue
            : application.appliedAmountValue
                ?? application.preferredBudgetAmountValue
        return store.formattedGrantAmountWithSEKApproximation(value, for: application)
    }
}

@MainActor
private struct AuthorLinkedPublicationsPanel: View, Equatable {
    let store: GrantDataStore
    let language: AppLanguage
    let publications: [PublicationRecord]
    let conferenceContributions: [PublicationAuthorLinkedConferenceContributionRow]

    nonisolated static func == (lhs: AuthorLinkedPublicationsPanel, rhs: AuthorLinkedPublicationsPanel) -> Bool {
        lhs.language == rhs.language
            && lhs.publications == rhs.publications
            && lhs.conferenceContributions == rhs.conferenceContributions
    }

    var body: some View {
        PublicationCompactPanel(title: language.text("Publications", "Publikationer"), usesInnerSurface: false) {
            AppCompactReferenceList(isEmpty: publications.isEmpty, emptyTitle: language.text("No records", "Inga poster"), rowSpacing: 0) {
                ForEach(publications) { publication in
                        Button(action: { store.openRoute(for: publication) }) {
                            let status = PublicationStatus.fromStored(publication.statusLabel)
                            AppLinkedStatusRow(
                                fill: publicationStatusShadeColor(for: status),
                                help: status.displayName(language: language)
                            ) {
                                Text(publication.title)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                        if publication.id != publications.last?.id {
                            Divider()
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func publicationStatusShadeColor(for status: PublicationStatus) -> Color? {
        AppPalette.statusRowFill(AppStatusTones.publication(status))
    }
}

@MainActor
private struct AuthorLinkedDisseminationPanel: View, Equatable {
    let store: GrantDataStore
    let language: AppLanguage
    let abstracts: [PublicationAuthorLinkedAbstractRow]
    let congressParticipations: [PublicationAuthorLinkedCongressParticipationRow]
    let mediaAppearances: [PublicationAuthorLinkedMediaAppearanceRow]

    nonisolated static func == (lhs: AuthorLinkedDisseminationPanel, rhs: AuthorLinkedDisseminationPanel) -> Bool {
        lhs.language == rhs.language
            && lhs.abstracts == rhs.abstracts
            && lhs.congressParticipations == rhs.congressParticipations
            && lhs.mediaAppearances == rhs.mediaAppearances
    }

    var body: some View {
        PublicationCompactPanel(title: language.text("Dissemination", "Spridning"), usesInnerSurface: false) {
            AppCompactReferenceList(
                isEmpty: abstracts.isEmpty && congressParticipations.isEmpty && mediaAppearances.isEmpty,
                emptyTitle: language.text("No records", "Inga poster"),
                rowSpacing: 0
            ) {
                    if !abstracts.isEmpty {
                        AppCompactListSectionLabel(title: language.text("Abstracts", "Abstracts"))
                        ForEach(abstracts) { row in
                            Button(action: { store.openRoute(for: row.contribution) }) {
                                AppLinkedStatusRow(
                                    fill: authorLinkedAbstractStatusFill(for: row.contribution),
                                    help: authorLinkedAbstractStatusHelp(for: row.contribution, language: language)
                                ) {
                                    AuthorLinkedTitleDateRow(title: row.title, dateText: row.dateText)
                                }
                            }
                            .buttonStyle(.plain)
                            if row.id != abstracts.last?.id || !congressParticipations.isEmpty || !mediaAppearances.isEmpty {
                                Divider()
                            }
                        }
                    }

                    if !congressParticipations.isEmpty {
                        AppCompactListSectionLabel(title: language.text("Congress participation", "Kongressdeltagande"))
                        ForEach(congressParticipations) { row in
                            Button(action: {
                                store.openRouteToCongress(organizationID: row.organizationID, congressID: row.congress.id)
                            }) {
                                AppLinkedStatusRow(fill: nil) {
                                    AuthorLinkedTitleDateRow(title: row.title, dateText: row.dateText)
                                }
                            }
                            .buttonStyle(.plain)
                            if row.id != congressParticipations.last?.id || !mediaAppearances.isEmpty {
                                Divider()
                            }
                        }
                    }

                    if !mediaAppearances.isEmpty {
                        AppCompactListSectionLabel(title: language.text("Media", "Media"))
                        ForEach(mediaAppearances) { appearance in
                            Button(action: { store.openRoute(for: appearance.appearance) }) {
                                AppLinkedStatusRow(fill: nil) {
                                    AuthorLinkedTitleDateRow(title: appearance.title, dateText: appearance.dateText)
                                }
                            }
                            .buttonStyle(.plain)
                            if appearance.id != mediaAppearances.last?.id {
                                Divider()
                            }
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

@MainActor
private struct AuthorLinkedDoctoralCandidatesPanel: View, Equatable {
    let store: GrantDataStore
    let language: AppLanguage
    let doctoralCandidates: [PublicationAuthorLinkedDoctoralCandidateRow]

    nonisolated static func == (lhs: AuthorLinkedDoctoralCandidatesPanel, rhs: AuthorLinkedDoctoralCandidatesPanel) -> Bool {
        lhs.language == rhs.language
            && lhs.doctoralCandidates == rhs.doctoralCandidates
    }

    var body: some View {
        PublicationCompactPanel(title: language.text("Doctoral candidates", "Doktorander"), usesInnerSurface: false) {
            AppCompactReferenceList(isEmpty: doctoralCandidates.isEmpty, emptyTitle: language.text("No records", "Inga poster"), rowSpacing: 0) {
                ForEach(doctoralCandidates) { row in
                    Button(action: { store.openRoute(for: row.candidate) }) {
                        AppLinkedStatusRow(
                            fill: doctoralStatusShadeColor(for: row.candidate),
                            help: doctoralStatusText(for: row.candidate)
                        ) {
                            AppLinkedTitleTrailingRow(
                                title: row.title,
                                trailingText: doctoralYearRangeText(for: row.candidate)
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    if row.id != doctoralCandidates.last?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func doctoralStatusShadeColor(for candidate: DoctoralCandidateRecord) -> Color? {
        // Round 16: the shared doctoral phases (ended early grey).
        AppPalette.statusRowFill(AppStatusTones.doctoral(AppStatusTones.doctoralPhase(candidate)))
    }

    private func doctoralStatusText(for candidate: DoctoralCandidateRecord) -> String {
        if doctoralMilestoneOutcome(candidate.plannedDisputationOutcomeRaw) == .endedBefore ||
            doctoralMilestoneOutcome(candidate.halftimeOutcomeRaw) == .endedBefore {
            return language.text("Ended before completion", "Avslutad innan slutförande")
        }
        if doctoralMilestoneOutcome(candidate.plannedDisputationOutcomeRaw) == .completed ||
            doctoralDateIsPastOrToday(candidate.disputationDate) {
            return language.text("Completed", "Genomförd")
        }
        return language.text("Active or planned", "Aktiv eller planerad")
    }

    private func doctoralYearRangeText(for candidate: DoctoralCandidateRecord) -> String {
        let start = doctoralYearText(candidate.admissionDate)
        let end = doctoralYearText(candidate.disputationDate) ?? doctoralYearText(candidate.plannedDisputationDate)

        switch (start, end) {
        case let (.some(start), .some(end)):
            return "\(start)-\(end)"
        case let (.some(start), .none):
            return "\(start)-"
        case let (.none, .some(end)):
            return end
        case (.none, .none):
            return "—"
        }
    }

    private func doctoralYearText(_ rawDate: String) -> String? {
        guard let value = rawDate.nonEmpty, value.count >= 4 else { return nil }
        return String(value.prefix(4))
    }

    private func doctoralMilestoneOutcome(_ raw: String?) -> DoctoralMilestoneOutcome? {
        raw.flatMap(DoctoralMilestoneOutcome.init(rawValue:))
    }

    private func doctoralDateIsPastOrToday(_ raw: String) -> Bool {
        guard let date = DateParsers.isoDay.date(from: raw) else { return false }
        return Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: Date())
    }
}

@MainActor
private struct AuthorLinkedCalendarEventsPanel: View, Equatable {
    let store: GrantDataStore
    let language: AppLanguage
    let rows: [CalendarLinkedEventRow]

    nonisolated static func == (lhs: AuthorLinkedCalendarEventsPanel, rhs: AuthorLinkedCalendarEventsPanel) -> Bool {
        lhs.language == rhs.language && lhs.rows == rhs.rows
    }

    var body: some View {
        PublicationCompactPanel(title: language.text("Calendar events", "Kalenderhändelser"), usesInnerSurface: false) {
            CalendarLinkedEventList(
                store: store,
                language: language,
                rows: rows,
                usesSingleLineRows: true,
                usesCompactResearcherRows: true
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

@MainActor
private struct AuthorLinkedCongressParticipationPanel: View, Equatable {
    let store: GrantDataStore
    let language: AppLanguage
    let rows: [PublicationAuthorLinkedCongressParticipationRow]

    nonisolated static func == (lhs: AuthorLinkedCongressParticipationPanel, rhs: AuthorLinkedCongressParticipationPanel) -> Bool {
        lhs.language == rhs.language && lhs.rows == rhs.rows
    }

    var body: some View {
        PublicationCompactPanel(title: language.text("Congress participation", "Kongressdeltagande"), usesInnerSurface: false) {
            AppCompactReferenceList(isEmpty: rows.isEmpty, emptyTitle: language.text("No records", "Inga poster"), rowSpacing: 0) {
                ForEach(rows) { row in
                        Button(action: {
                            store.openRouteToCongress(organizationID: row.organizationID, congressID: row.congress.id)
                        }) {
                            AppLinkedStatusRow(fill: nil) {
                                AuthorLinkedTitleDateRow(title: row.title, dateText: row.dateText)
                            }
                        }
                        .buttonStyle(.plain)
                        if row.id != rows.last?.id {
                            Divider()
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

@MainActor
private struct AuthorLinkedAbstractsPanel: View, Equatable {
    let store: GrantDataStore
    let language: AppLanguage
    let rows: [PublicationAuthorLinkedAbstractRow]

    nonisolated static func == (lhs: AuthorLinkedAbstractsPanel, rhs: AuthorLinkedAbstractsPanel) -> Bool {
        lhs.language == rhs.language && lhs.rows == rhs.rows
    }

    var body: some View {
        PublicationCompactPanel(title: language.text("Abstracts", "Abstracts"), usesInnerSurface: false) {
            AppCompactReferenceList(isEmpty: rows.isEmpty, emptyTitle: language.text("No records", "Inga poster"), rowSpacing: 0) {
                ForEach(rows) { row in
                        Button(action: { store.openRoute(for: row.contribution) }) {
                            AppLinkedStatusRow(
                                fill: authorLinkedAbstractStatusFill(for: row.contribution),
                                help: authorLinkedAbstractStatusHelp(for: row.contribution, language: language)
                            ) {
                                AuthorLinkedTitleDateRow(title: row.title, dateText: row.dateText)
                            }
                        }
                        .buttonStyle(.plain)
                        if row.id != rows.last?.id {
                            Divider()
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct AuthorPersonalResumePanel: View {
    @ObservedObject var store: GrantDataStore

    @State private var draft: CVPersonalResume
    @State private var autosaveTask: DispatchWorkItem?
    @StateObject private var editorController = CVRichTextEditorController()

    init(store: GrantDataStore) {
        self.store = store
        _draft = State(initialValue: store.cvPersonalResume)
    }

    private var language: AppLanguage { store.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                CVRichTextFormatButton(title: "B") { editorController.toggleBold() }
                CVRichTextFormatButton(title: "I") { editorController.toggleItalic() }
                CVRichTextFormatButton(title: "U") { editorController.toggleUnderline() }
                Spacer()
                Text(language == .swedish ? "Svensk version" : "English version")
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
            }

            CVRichTextEditorRepresentable(
                document: localizedDocumentBinding,
                controller: editorController
            )
            .frame(minHeight: 180)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppPalette.fieldSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppPalette.subtleBorder, lineWidth: 1)
            )
        }
        .onReceive(store.$cvPersonalResume.removeDuplicates().dropFirst()) { newValue in
            autosaveTask?.cancel()
            draft = newValue
        }
    }

    private var localizedDocumentBinding: Binding<CVRichTextDocument> {
        Binding(
            get: { draft.localizedContent(language: language) },
            set: { newValue in
                draft.setLocalizedContent(newValue, language: language)
                scheduleAutosave()
            }
        )
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let snapshot = draft
        let task = DispatchWorkItem {
            store.autosaveCVPersonalResume(snapshot)
        }
        autosaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: task)
    }
}

private struct AuthorDoctoralThesisPanel: View {
    @ObservedObject var store: GrantDataStore

    @State private var draft: CVOtherPublicationEntry
    @State private var autosaveTask: DispatchWorkItem?

    init(store: GrantDataStore) {
        self.store = store
        _draft = State(initialValue: Self.initialDraft(from: store))
    }

    private var language: AppLanguage { store.language }
    private var researcherOptions: [String] {
        store.coauthors
            .map(\.name)
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private var currentUserName: String? {
        store.currentUserAuthor()?.name.nonEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                compactField(language.text("Year", "År"), width: 110) {
                    AppYearField(text: binding(\.date), language: language, width: 110)
                }
                compactField(language.text("Language", "Språk"), width: 160) {
                    TextField(language.text("Language", "Språk"), text: localizedLanguageBinding)
                        .appTextInputChrome()
                }
                compactField("DOI", width: 320) {
                    AppIdentifierField(kind: .doi, text: binding(\.doi), language: language)
                }
                if let doiURL = draft.doiURL {
                    Link("DOI", destination: doiURL)
                        .appTypography(.tableHeader)
                        .foregroundStyle(AppPalette.linkAction)
                        .padding(.top, 24)
                }
                Spacer(minLength: 0)
            }

            compactField(language.text("Title", "Titel")) {
                TextField(language == .swedish ? "Titel (svenska)" : "Title (English)", text: localizedTitleBinding)
                    .appTextInputChrome()
            }

            HStack(alignment: .top, spacing: 10) {
                compactField(language.text("Publisher / series", "Förlag / serie")) {
                    TextField(language == .swedish ? "Publikation / outlet (svenska)" : "Publication / outlet (English)", text: localizedOutletBinding)
                        .appTextInputChrome()
                }
                compactField(language.text("Short name", "Kortnamn"), width: 160) {
                    TextField(language.text("Short name", "Kortnamn"), text: binding(\.publisherShortName))
                        .appTextInputChrome()
                }
                compactField(language.text("City", "Stad"), width: 160) {
                    TextField(language.text("City", "Stad"), text: binding(\.city))
                        .appTextInputChrome()
                }
            }

            HStack(alignment: .top, spacing: 10) {
                compactField(language.text("Main supervisor", "Huvudhandledare")) {
                    AutocompleteSelectionField(
                        text: binding(\.mainSupervisor),
                        options: researcherOptions,
                        placeholder: language.text("Main supervisor", "Huvudhandledare"),
                        addNewTitle: language.text("Add new", "Lägg till ny"),
                        display: { $0 },
                        onCommit: {}
                    )
                }
                compactField(language.text("Co-supervisor", "Bihandledare")) {
                    AutocompleteSelectionField(
                        text: binding(\.coSupervisor),
                        options: researcherOptions,
                        placeholder: language.text("Co-supervisor", "Bihandledare"),
                        addNewTitle: language.text("Add new", "Lägg till ny"),
                        display: { $0 },
                        onCommit: {}
                    )
                }
            }
        }
        .onAppear {
            refreshFromStore()
        }
        .onReceive(store.$cvOtherPublications.removeDuplicates().dropFirst()) { _ in
            // Deferred: @Published emits at willSet and refreshFromStore
            // reads the store's committed state.
            DispatchQueue.main.async {
                refreshFromStore()
            }
        }
        .onChange(of: draft) { _, _ in
            scheduleAutosave()
        }
    }

    private static func initialDraft(from store: GrantDataStore) -> CVOtherPublicationEntry {
        store.cvOtherPublications.first(where: \.isDoctoralThesis)
        ?? CVOtherPublicationEntry(category: "Doktorsavhandling")
    }

    private var localizedTitleBinding: Binding<String> {
        Binding(get: { draft.localizedTitle(language: language) }, set: { draft.setLocalizedTitle($0, language: language) })
    }

    private var localizedOutletBinding: Binding<String> {
        Binding(get: { draft.localizedOutlet(language: language) }, set: { draft.setLocalizedOutlet($0, language: language) })
    }

    private var localizedLanguageBinding: Binding<String> {
        Binding(get: { draft.localizedLanguage(language: language) }, set: { draft.setLocalizedLanguage($0, language: language) })
    }

    private func binding(_ keyPath: WritableKeyPath<CVOtherPublicationEntry, String>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { draft[keyPath: keyPath] = $0 }
        )
    }

    private func refreshFromStore() {
        guard let thesis = store.cvOtherPublications.first(where: \.isDoctoralThesis) else { return }
        if thesis != draft {
            autosaveTask?.cancel()
            draft = thesis
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        var snapshot = draft
        snapshot.categorySv = "Doktorsavhandling"
        snapshot.categoryEn = "Doctoral thesis"
        if let currentUserName {
            snapshot.authors = currentUserName
        }
        let task = DispatchWorkItem {
            store.autosaveCVOtherPublication(snapshot)
        }
        autosaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
    }
}

private struct AffiliationDropModifier: ViewModifier {
    let enabled: Bool
    let targetID: String
    @Binding var items: [PublicationAffiliation]
    @Binding var draggedItemID: String?

    func body(content: Content) -> some View {
        content.onDrop(
            of: [UTType.plainText],
            delegate: AffiliationReorderDropDelegate(
                enabled: enabled,
                targetID: targetID,
                items: $items,
                draggedItemID: $draggedItemID
            )
        )
    }
}

private struct PlainDateField: View {
    @Binding var text: String
    var isDisabled: Bool = false
    var isIllogical: Bool = false

    var body: some View {
        AppDateField(
            placeholder: "YYYY-MM-DD",
            text: $text,
            width: 104,
            state: isIllogical ? .invalid("Ologisk datumkombination") : .normal,
            isDisabled: isDisabled,
            horizontalPadding: 8,
            verticalPadding: 4
        )
    }
}

private extension ProjectLifecycleStatus {
    func displayName(language: AppLanguage) -> String {
        switch self {
        case .planned:
            return fixedDropdownText("projectLifecycle.planned", language: language, english: "Planned", swedish: "Planerat")
        case .ongoing:
            return fixedDropdownText("projectLifecycle.ongoing", language: language, english: "Ongoing", swedish: "Pågående")
        case .completed:
            return fixedDropdownText("projectLifecycle.completed", language: language, english: "Completed", swedish: "Avslutat")
        }
    }
}
