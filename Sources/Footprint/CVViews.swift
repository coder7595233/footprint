import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct CVListRow: Identifiable {
    let id: String
    let kind: CVItemKind
    let categoryLabel: String
    let title: String
    let contextLabel: String
    let dateLabel: String
    let sortCategory: Int
    let sortStatus: Int
    let sortTitle: String
    let sortContext: String
    let sortDate: String
    let normalizedSearchBlob: String
    let reviewWorkflowStatus: CVReviewWorkflowStatus?
    let reviewCategory: CVReviewCategory?
    /// Raw values of ExpertAssignmentStatusKey (expert-assignment chips).
    let reviewStatusKeys: Set<String>

    init(
        id: String,
        kind: CVItemKind,
        categoryLabel: String,
        title: String,
        contextLabel: String = "",
        dateLabel: String,
        sortCategory: Int,
        sortStatus: Int = 0,
        sortTitle: String,
        sortContext: String = "",
        sortDate: String,
        normalizedSearchBlob: String,
        reviewWorkflowStatus: CVReviewWorkflowStatus? = nil,
        reviewCategory: CVReviewCategory? = nil,
        reviewStatusKeys: Set<String> = []
    ) {
        self.id = id
        self.kind = kind
        self.categoryLabel = categoryLabel
        self.title = title
        self.contextLabel = contextLabel
        self.dateLabel = dateLabel
        self.sortCategory = sortCategory
        self.sortStatus = sortStatus
        self.sortTitle = sortTitle
        self.sortContext = sortContext
        self.sortDate = sortDate
        self.normalizedSearchBlob = normalizedSearchBlob
        self.reviewWorkflowStatus = reviewWorkflowStatus
        self.reviewCategory = reviewCategory
        self.reviewStatusKeys = reviewStatusKeys
    }
}

private enum CVListSortColumn: String, Hashable {
    case status
    case category
    case title
    case context
    case date

    var defaultAscending: Bool {
        switch self {
        case .status, .category, .title, .context:
            return true
        case .date:
            return false
        }
    }
}

private struct CVListSortCriterion: AppListSortCriterion {
    let column: CVListSortColumn
    var ascending: Bool
}

private func cvListSortOrder(from history: [CVListSortCriterion]) -> [KeyPathComparator<CVListRow>] {
    var columns = history.map(\.column)
    for fallbackColumn in [CVListSortColumn.date, .title] where !columns.contains(fallbackColumn) {
        columns.append(fallbackColumn)
    }
    return columns.flatMap { column -> [KeyPathComparator<CVListRow>] in
        let ascending = history.first(where: { $0.column == column })?.ascending ?? column.defaultAscending
        let order: SortOrder = ascending ? .forward : .reverse
        switch column {
        case .status:
            return [
                KeyPathComparator(\.sortStatus, order: order),
                KeyPathComparator(\.sortTitle, order: .forward)
            ]
        case .category:
            return [
                KeyPathComparator(\.sortCategory, order: order),
                KeyPathComparator(\.sortTitle, order: .forward)
            ]
        case .title:
            return [
                KeyPathComparator(\.sortTitle, order: order),
                KeyPathComparator(\.sortDate, order: .reverse)
            ]
        case .context:
            return [
                KeyPathComparator(\.sortContext, order: order),
                KeyPathComparator(\.sortTitle, order: .forward)
            ]
        case .date:
            return [
                KeyPathComparator(\.sortDate, order: order),
                KeyPathComparator(\.sortTitle, order: .forward)
            ]
        }
    }
}

private func cvToken(for kind: CVItemKind, id: String) -> String {
    "\(kind.rawValue):\(id)"
}

private func cvConferenceListTitle(_ item: CVConferenceContribution, language: AppLanguage) -> String {
    if let title = item.localizedTitle(language: language).nonEmpty {
        return title
    }
    if item.isEmpty {
        return language.text("New conference contribution", "Nytt konferensbidrag")
    }
    return item.displayTitle
}

private func cvMediaListTitle(_ item: CVMediaAppearance, language: AppLanguage) -> String {
    if let title = item.localizedTitle(language: language).nonEmpty {
        return title
    }
    if item.isEmpty {
        return language.text("New media appearance", "Ny medverkan i media")
    }
    return item.displayTitle
}

func cvMediaLanguageListText(
    codes: [String],
    options: [MediaLanguageOption],
    language: AppLanguage
) -> String {
    codes
        .map { code in
            let normalized = MediaLanguageOption.canonicalCode(for: code, options: options) ?? code
            return options.first(where: { $0.id == normalized })?.localizedName(language: language) ?? code
        }
        .compactMap(\.trimmedOrNil)
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        .joined(separator: ", ")
}

private func cvReviewListTitle(_ item: CVReviewEntry, language: AppLanguage) -> String {
    if let title = item.listTitle.nonEmpty {
        return title
    }
    return language.text("New expert assignment", "Nytt sakkunniguppdrag")
}

private func cvReviewAssignmentListTitle(_ item: CVReviewEntry, language: AppLanguage) -> String {
    let candidate: String? = {
        switch item.category {
        case .journalReview:
            return item.subjectTitle.nonEmpty ?? item.reference.nonEmpty
        case .grantProposalReview:
            return item.programName.nonEmpty ?? item.reference.nonEmpty
        case .doctoralExamination:
            return item.subjectTitle.nonEmpty ?? item.roleName.nonEmpty ?? item.personName.nonEmpty ?? item.reference.nonEmpty
        case .otherExpertAssignment:
            return item.subjectTitle.nonEmpty ?? item.roleName.nonEmpty ?? item.personName.nonEmpty ?? item.reference.nonEmpty
        }
    }()
    return candidate ?? language.text("Untitled assignment", "Namnlöst uppdrag")
}

private func cvReviewListContext(_ item: CVReviewEntry) -> String {
    switch item.category {
    case .journalReview:
        return item.journalName.nonEmpty ?? ""
    case .grantProposalReview, .doctoralExamination, .otherExpertAssignment:
        return item.organizationName.nonEmpty ?? ""
    }
}

private func cvReviewListDateLabel(_ item: CVReviewEntry, language: AppLanguage) -> String {
    cvReviewListSortDate(item)
}

private func cvReviewListSortDate(_ item: CVReviewEntry) -> String {
    item.date.trimmedOrNil
        ?? item.acceptedDate.trimmedOrNil
        ?? item.deadlineDate.trimmedOrNil
        ?? ""
}

private func cvReviewListStatusSortValue(_ status: CVReviewWorkflowStatus?) -> Int {
    switch status {
    case .overdue:
        return 0
    case .accepted:
        return 1
    case .completed:
        return 2
    case nil:
        return 3
    }
}

private func expertAssignmentsPageTitle(language: AppLanguage) -> String {
    language.text("Expert assignments", "Sakkunnig\u{00AD}uppdrag")
}

func cvAutocompleteOptions(
    preferredValues: [String],
    additionalValues: [String] = [],
    selectedValue: String? = nil
) -> [String] {
    var valuesByKey: [String: String] = [:]

    func add(_ value: String?) {
        guard let trimmed = value?.trimmedOrNil else { return }
        let key = PublicationDerivation.normalizedName(trimmed)
        if valuesByKey[key] == nil {
            valuesByKey[key] = trimmed
        }
    }

    preferredValues.forEach(add)
    additionalValues.forEach(add)
    add(selectedValue)

    return valuesByKey.values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}

func cvReviewProgramAutocompleteOptions(
    reviewEntries: [CVReviewEntry],
    selectedValue: String? = nil
) -> [String] {
    cvAutocompleteOptions(
        preferredValues: reviewEntries
            .filter { $0.category == .grantProposalReview }
            .map(\.programName),
        selectedValue: selectedValue
    )
}

func cvReviewRoleAutocompleteOptions(
    category: CVReviewCategory,
    reviewEntries: [CVReviewEntry],
    selectedValue: String? = nil
) -> [String] {
    cvAutocompleteOptions(
        preferredValues: reviewEntries
            .filter { $0.category == category }
            .map(\.roleName),
        selectedValue: selectedValue
    )
}

func cvReviewPersonAutocompleteOptions(
    category: CVReviewCategory,
    reviewEntries: [CVReviewEntry],
    doctoralCandidates: [DoctoralCandidateRecord] = [],
    publicationAuthors: [PublicationAuthor] = [],
    selectedValue: String? = nil
) -> [String] {
    switch category {
    case .doctoralExamination:
        return cvAutocompleteOptions(
            preferredValues: doctoralCandidates.map(\.candidateName),
            additionalValues: reviewEntries
                .filter { $0.category == .doctoralExamination }
                .map(\.personName),
            selectedValue: selectedValue
        )
    case .otherExpertAssignment:
        return cvAutocompleteOptions(
            preferredValues: publicationAuthors.map(\.name),
            additionalValues: reviewEntries
                .filter { $0.category == .otherExpertAssignment }
                .map(\.personName),
            selectedValue: selectedValue
        )
    default:
        return cvAutocompleteOptions(
            preferredValues: reviewEntries
                .filter { $0.category == category }
                .map(\.personName),
            selectedValue: selectedValue
        )
    }
}

struct DisseminationWorkspaceView: View {
    let store: GrantDataStore
    let newRecordTrigger: Int
    let isActive: Bool

    @State private var selectedItemID: String?
    @State private var sortHistory = ListSortPersistence.load(
        defaultsKey: "MediaListSortV2",
        defaultValue: [CVListSortCriterion(column: .date, ascending: false)]
    )
    @WorkspaceFilterState("Dissemination.Filter.Search") private var searchText = ""
    @State private var pendingSelectionMeasurementID: String?
    @State private var pendingSelectionStartedAt: CFAbsoluteTime?

    private var language: AppLanguage { store.language }

    private var sortOrder: [KeyPathComparator<CVListRow>] {
        cvListSortOrder(from: sortHistory)
    }

    private var mediaRows: [CVListRow] {
        let authorNamesByID = Dictionary(firstWinsKeysWithValues: store.publicationAuthors.map { ($0.id, $0.name) })
        // Round 17: one lookup table instead of a search through every
        // project for each row.
        let projectNamesByID = Dictionary(firstWinsKeysWithValues: store.projects.map { ($0.id, $0.displayName(for: language)) })
        return store.cvMediaAppearances.map {
            let title = cvMediaListTitle($0, language: language)
            let authorNames = ([$0.authorID].compactMap { $0 } + $0.authorIDs)
                .compactMap { authorNamesByID[$0] }
                .joined(separator: " ")
            let categoryLabel = language.text("Media appearance", "Medverkan i media")
            let projectLabel = $0.projectIDs.compactMap { projectNamesByID[$0] }.joined(separator: ", ")
            return CVListRow(
                id: cvToken(for: .mediaAppearance, id: $0.id),
                kind: .mediaAppearance,
                categoryLabel: categoryLabel,
                title: title,
                contextLabel: projectLabel,
                dateLabel: $0.date,
                sortCategory: 1,
                sortTitle: title,
                sortContext: projectLabel,
                sortDate: $0.date,
                normalizedSearchBlob: normalizedSearchFilterText(
                    [
                        categoryLabel,
                        projectLabel,
                        title,
                        $0.date,
                        $0.publicationDate,
                        $0.meetingMode,
                        $0.place,
                        $0.country,
                        // Round 16: both languages, description, comment and
                        // the people involved are searchable too.
                        $0.titleSv,
                        $0.titleEn,
                        $0.descriptionSv,
                        $0.descriptionEn,
                        $0.comment,
                        authorNames,
                    ].joined(separator: " ")
                )
            )
        }
    }

    private var otherPublicationRows: [CVListRow] {
        store.cvOtherPublications.filter { !$0.isDoctoralThesis }.map {
            let title = $0.localizedTitle(language: language).nonEmpty ?? $0.displayTitle
            let categoryLabel = language.text("Other publication", "Övrig publikation")
            return CVListRow(
                id: cvToken(for: .otherPublication, id: $0.id),
                kind: .otherPublication,
                categoryLabel: categoryLabel,
                title: title,
                dateLabel: $0.date,
                sortCategory: 2,
                sortTitle: title,
                sortDate: $0.date,
                normalizedSearchBlob: normalizedSearchFilterText([
                    categoryLabel,
                    title,
                    $0.localizedOutlet(language: language),
                    $0.date
                ].joined(separator: " "))
            )
        }
    }

    private var allRows: [CVListRow] {
        mediaRows + otherPublicationRows
    }

    /// Round 17: the ids of all rows, in list order, without building the
    /// rows (read on every redraw).
    private var allRowIDs: [String] {
        store.cvMediaAppearances.map { cvToken(for: .mediaAppearance, id: $0.id) }
            + store.cvOtherPublications.filter { !$0.isDoctoralThesis }.map { cvToken(for: .otherPublication, id: $0.id) }
    }

    private var filteredRows: [CVListRow] {
        let searchQuery = SearchFilterQuery(raw: searchText)
        return allRows
            .filter { row in
                searchQuery.isEmpty || searchQuery.matches(normalizedHaystack: row.normalizedSearchBlob)
            }
            .sorted(using: sortOrder)
    }

    private var firstAvailableSelection: String? { filteredRows.first?.id }

    private var hasActiveDisseminationFilters: Bool {
        searchText.nonEmpty != nil
    }

    /// Round 17: only a row the search shows can be selected, also at
    /// launch (a remembered item hidden by a saved search is not shown).
    private func selectableDisseminationID(preferred: String?) -> String? {
        let visibleIDs = filteredRows.map(\.id)
        return ListSelectionPolicy.selectionAfterFilterChange(
            selected: preferred ?? visibleIDs.first,
            visibleIDs: visibleIDs
        )
    }

    private func shouldHandleDisseminationRoute(_ route: AppRoute) -> Bool {
        route.destination == .cv
            && !route.recordID.hasPrefix("conferenceContribution:")
            && !route.recordID.hasPrefix("organizationCongress:")
            // Review routes belong to the expert-assignments workspace;
            // consuming them here silently reset this list's selection.
            && !route.recordID.hasPrefix("review:")
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 400, idealWidth: 500, maxWidth: 620)
            detail
                .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            // Round 17: with "keep filters" off in Settings, a search saved
            // by an earlier run is cleared the first time the list is shown.
            if ListFilterLaunchPolicy.shouldClearSavedFilters(
                for: .dissemination,
                retainsFilters: store.shouldRetainListFilters(for: .dissemination)
            ) {
                searchText = ""
                RestoredListFilters.forget(workspace: "Dissemination")
            }
            if let route = store.route, shouldHandleDisseminationRoute(route) {
                revealDisseminationRowForDirectNavigation(route.recordID)
                setSelectedItemID(selectableDisseminationID(preferred: route.recordID))
                store.consumeRoute()
            } else {
                setSelectedItemID(selectableDisseminationID(preferred: selectedItemID ?? store.lastSelectedRecordID(for: .cv)))
            }
        }
        .onChange(of: store.route) { _, route in
            guard let route, shouldHandleDisseminationRoute(route) else { return }
            revealDisseminationRowForDirectNavigation(route.recordID)
            setSelectedItemID(selectableDisseminationID(preferred: route.recordID))
            store.consumeRoute()
        }
        // A search that hides the selected item moves the selection to the
        // first visible row.
        .onChange(of: searchText) { _, _ in
            let next = ListSelectionPolicy.selectionAfterFilterChange(
                selected: selectedItemID,
                visibleIDs: filteredRows.map(\.id)
            )
            if next != selectedItemID {
                setSelectedItemID(next)
            }
        }
        .onChange(of: selectedItemID) { _, newValue in
            store.rememberSelection(id: newValue, for: .cv)
            pendingSelectionMeasurementID = newValue
            pendingSelectionStartedAt = CFAbsoluteTimeGetCurrent()
            store.appendPerformanceDiagnostic(
                String(
                    format: "dissemination-selection-start id=%@",
                    newValue ?? "-"
                )
            )
        }
        .onChange(of: newRecordTrigger) { _, _ in
            guard isActive else { return }
            createMediaAppearanceRevealingIt()
        }
        .onChange(of: allRowIDs) { _, allIDs in
            guard let selectedItemID else {
                setSelectedItemID(firstAvailableSelection)
                return
            }
            if !Set(allIDs).contains(selectedItemID) {
                setSelectedItemID(firstAvailableSelection)
            }
        }
        .onChange(of: isActive) { _, active in
            guard !active else { return }
            clearDisseminationFiltersForDeactivationIfNeeded()
        }
    }

    private var sidebar: some View {
        // Round 17: built once per redraw (banner, list and empty state).
        let visibleRows = filteredRows
        let totalCount = allRowIDs.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(language.text("Media", "Media"))
                    .appTypography(.pageTitle)
                Spacer()
                cvCreateButton(language.text("New media appearance", "Ny medverkan i media")) {
                    createMediaAppearanceRevealingIt()
                }
            }

            AppFilterCard {
                VStack(alignment: .leading, spacing: 8) {
                    AppFilterRow(
                        showsClearButton: searchText.nonEmpty != nil,
                        clearAction: { searchText = "" }
                    ) {
                        AppSidebarSearchField(
                            placeholder: language.text("Search media", "Sök media"),
                            text: $searchText
                        )
                    }
                    // Round 17: "clear all" is the banner's "Rensa filter".
                }
            }

            if hasActiveDisseminationFilters {
                AppFilteredListBanner(
                    displayedCount: visibleRows.count,
                    totalCount: totalCount,
                    activeFilters: [ListFilterLabels.search(searchText, language: language)].compactMap { $0 },
                    restoredFromLastSession: RestoredListFilters.wasRestored(workspace: "Dissemination.Filter"),
                    language: language,
                    clearAction: clearAllDisseminationFilters
                )
            }

            if visibleRows.isEmpty && hasActiveDisseminationFilters && totalCount > 0 {
                disseminationFilterEmptyState(hiddenCount: totalCount, isCompact: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                disseminationList(rows: visibleRows)
            }
        }
        .padding(14)
        .background(AppPalette.sidebarPanelSurface)
    }

    private func clearAllDisseminationFilters() {
        searchText = ""
        RestoredListFilters.forget(workspace: "Dissemination")
    }

    /// Round 17: items exist but the search hides them all.
    private func disseminationFilterEmptyState(hiddenCount: Int, isCompact: Bool) -> some View {
        AppWorkspaceEmptyStateView(
            title: language.text("No records match the filters", "Inga poster matchar filtren"),
            subtitle: ListFilterLabels.hiddenByFilters(count: hiddenCount, language: language),
            kind: .dissemination,
            actionTitle: language.text("Clear filters", "Rensa filter"),
            action: clearAllDisseminationFilters,
            isCompact: isCompact
        )
    }

    /// Direct navigation to an item the search hides clears the search (the
    /// only filter here).
    private func revealDisseminationRowForDirectNavigation(_ token: String) {
        guard searchText.nonEmpty != nil,
              allRows.contains(where: { $0.id == token }),
              !filteredRows.contains(where: { $0.id == token }) else { return }
        searchText = ""
    }

    /// A new media appearance has no title yet, so any search would hide it.
    private func createMediaAppearanceRevealingIt() {
        if hasActiveDisseminationFilters {
            searchText = ""
        }
        let id = store.addCVMediaAppearance()
        setSelectedItemID(cvToken(for: .mediaAppearance, id: id))
    }

    private func cvCreateButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .appAddButtonStyle()
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func disseminationList(rows: [CVListRow]) -> some View {
        let titleMinWidth: CGFloat = 130
        let projectWidth: CGFloat = 170
        let dateWidth: CGFloat = 110
        let tableMinWidth: CGFloat = dateWidth + projectWidth + titleMinWidth + 20
        let orderedIDs = rows.map(\.id)

        AppListTable(contentMinWidth: tableMinWidth) {
            HStack(spacing: 0) {
                disseminationListHeader(language.text("Date", "Datum"), width: dateWidth, column: .date)
                    .frame(width: dateWidth, alignment: .leading)
                disseminationListHeader(language.text("Project", "Projekt"), width: projectWidth, column: .context)
                    .frame(width: projectWidth, alignment: .leading)
                disseminationListHeader(language.text("Title", "Rubrik"), column: .title)
                    .frame(minWidth: titleMinWidth, maxWidth: .infinity, alignment: .leading)
            }
        } rows: {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows, id: \.id) { row in
                    AppListRowButton(
                        minWidth: tableMinWidth,
                        action: { setSelectedItemID(row.id) },
                        background: { disseminationListRowBackground(for: row) }
                    ) {
                        HStack(spacing: 0) {
                            disseminationDateLink(for: row)
                            Text(row.contextLabel)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: projectWidth, alignment: .leading)
                            Text(row.title)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(minWidth: titleMinWidth, maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if row.id != rows.last?.id {
                        Divider()
                    }
                }
            }
        }
        .appListKeyboardNavigation(
            store: store,
            destination: .cv,
            isEnabled: isActive,
            orderedIDs: orderedIDs,
            selectedID: selectedItemID,
            onSelect: { setSelectedItemID($0) }
        )
    }

    @ViewBuilder
    private func disseminationDateLink(for row: CVListRow) -> some View {
        let date = disseminationCalendarDate(for: row)
        Text(row.dateLabel)
            .monospacedDigit()
            .foregroundStyle(date == nil ? Color.secondary : AppPalette.appText)
            .lineLimit(1)
            .frame(width: 110, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                guard let date else { return }
                store.revealCalendarWorkspace(on: date)
            }
            .help(
                date == nil
                    ? ""
                    : language.text("Show this date in the calendar", "Visa datumet i kalendern")
            )
            .accessibilityAddTraits(date == nil ? [] : .isButton)
    }

    private func disseminationCalendarDate(for row: CVListRow) -> Date? {
        guard row.dateLabel.trimmedOrNil != nil else { return nil }
        return DateParsers.isoDay.date(from: DateParsers.canonicalizedDayInput(row.dateLabel))
    }

    private func disseminationListRowBackground(for row: CVListRow) -> some View {
        let fill = disseminationDateShadeFill(for: row)
        return Group {
            if row.id == selectedItemID {
                SelectedListRowBackground(indicatorFill: fill)
            } else {
                StatusIndicatorListRowBackground(fill: fill)
            }
        }
    }

    private func disseminationDateShadeFill(for row: CVListRow) -> Color {
        AppPalette.statusFill(row.dateLabel.trimmedOrNil == nil ? .pending : .done)
    }

    private func disseminationListHeader(_ title: String, width: CGFloat? = nil, column: CVListSortColumn) -> some View {
        let criterion = sortCriterion(for: column)
        let sortIndex = sortIndex(for: column)
        return AppSortableListHeader(
            title: title,
            ascending: criterion?.ascending,
            sortIndex: sortIndex,
            width: width,
            resetTitle: language.text("Reset", "Återställ"),
            onToggle: { toggleSort(column) },
            onReset: resetSort
        )
    }

    private func toggleSort(_ column: CVListSortColumn) {
        if let existingIndex = sortHistory.firstIndex(where: { $0.column == column }) {
            if existingIndex == 0 {
                sortHistory[0].ascending.toggle()
            } else {
                let criterion = sortHistory.remove(at: existingIndex)
                sortHistory.insert(criterion, at: 0)
            }
        } else {
            sortHistory.insert(CVListSortCriterion(column: column, ascending: column.defaultAscending), at: 0)
        }
        ListSortPersistence.save(sortHistory, defaultsKey: "MediaListSortV2")
    }

    private func resetSort() {
        sortHistory = [
            CVListSortCriterion(column: .date, ascending: false)
        ]
        ListSortPersistence.save(sortHistory, defaultsKey: "MediaListSortV2")
    }

    private func sortCriterion(for column: CVListSortColumn) -> CVListSortCriterion? {
        sortHistory.first(where: { $0.column == column })
    }

    private func sortIndex(for column: CVListSortColumn) -> Int? {
        sortHistory.firstIndex(where: { $0.column == column })
    }

    private func setSelectedItemID(_ newValue: String?) {
        guard selectedItemID != newValue else { return }
        // Commit active field edits before switching records to avoid value bleed.
        NSApp.keyWindow?.makeFirstResponder(nil)
        selectedItemID = newValue
    }

    private func clearDisseminationFiltersForDeactivationIfNeeded() {
        guard !store.shouldRetainListFilters(for: .dissemination) else { return }
        searchText = ""
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedItemID,
           let resolved = resolvedSelection(from: selectedItemID) {
            switch resolved {
            case .conference(let item):
                CVConferenceContributionDetailView(store: store, contribution: item)
                    .id(item.id)
                    .undoRevealPulse(
                        triggerID: store.undoRevealRequest?.id,
                        isActive: store.undoRevealRequest?.target.matchesWholeRecord(routeDestination: .cv, recordID: cvToken(for: .conferenceContribution, id: item.id)) == true
                    )
                    .performanceScopeProbe(store: store, scope: "dissemination-detail", identifier: item.id)
                    .background(
                        PerformanceReadyReporter {
                            guard pendingSelectionMeasurementID == cvToken(for: .conferenceContribution, id: item.id),
                                  let pendingSelectionStartedAt else { return }
                            let duration = (CFAbsoluteTimeGetCurrent() - pendingSelectionStartedAt) * 1000
                            store.appendPerformanceDiagnostic(
                                String(
                                    format: "dissemination-selection-ready item=%@ ready_ms=%.2f",
                                    cvConferenceListTitle(item, language: language),
                                    duration
                                )
                            )
                            self.pendingSelectionMeasurementID = nil
                            self.pendingSelectionStartedAt = nil
                        }
                    )
            case .media(let item):
                CVMediaAppearanceDetailView(store: store, appearance: item)
                    .id(item.id)
                    .undoRevealPulse(
                        triggerID: store.undoRevealRequest?.id,
                        isActive: store.undoRevealRequest?.target.matchesWholeRecord(routeDestination: .cv, recordID: cvToken(for: .mediaAppearance, id: item.id)) == true
                    )
                    .performanceScopeProbe(store: store, scope: "dissemination-detail", identifier: item.id)
                    .background(
                        PerformanceReadyReporter {
                            guard pendingSelectionMeasurementID == cvToken(for: .mediaAppearance, id: item.id),
                                  let pendingSelectionStartedAt else { return }
                            let duration = (CFAbsoluteTimeGetCurrent() - pendingSelectionStartedAt) * 1000
                            store.appendPerformanceDiagnostic(
                                String(
                                    format: "dissemination-selection-ready item=%@ ready_ms=%.2f",
                                    cvMediaListTitle(item, language: language),
                                    duration
                                )
                            )
                            self.pendingSelectionMeasurementID = nil
                            self.pendingSelectionStartedAt = nil
                        }
                    )
            case .review:
                AppWorkspaceEmptyStateView(
                    title: language.text("No dissemination item selected", "Ingen spridningspost vald"),
                    subtitle: language.text("Select a media appearance or other publication.", "Välj medverkan i media eller en övrig publikation."),
                    kind: .dissemination
                )
            case .otherPublication(let item):
                CVOtherPublicationDetailView(store: store, item: item)
                    .id(item.id)
                    .undoRevealPulse(
                        triggerID: store.undoRevealRequest?.id,
                        isActive: store.undoRevealRequest?.target.matchesWholeRecord(routeDestination: .cv, recordID: cvToken(for: .otherPublication, id: item.id)) == true
                    )
                    .performanceScopeProbe(store: store, scope: "dissemination-detail", identifier: item.id)
            }
        } else if hasActiveDisseminationFilters, !allRowIDs.isEmpty, filteredRows.isEmpty {
            disseminationFilterEmptyState(hiddenCount: allRowIDs.count, isCompact: false)
        } else {
            AppWorkspaceEmptyStateView(
                title: language.text("No dissemination items yet", "Inga spridningsposter ännu"),
                subtitle: language.text("Create a media appearance or other publication.", "Skapa medverkan i media eller en övrig publikation."),
                kind: .dissemination
            )
        }
    }

    private enum ResolvedSelection {
        case conference(CVConferenceContribution)
        case media(CVMediaAppearance)
        case review(CVReviewEntry)
        case otherPublication(CVOtherPublicationEntry)
    }

    private func resolvedSelection(from token: String) -> ResolvedSelection? {
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = CVItemKind(rawValue: parts[0]) else { return nil }
        let id = parts[1]
        switch kind {
        case .conferenceContribution:
            return store.cvConferenceContributions.first(where: { $0.id == id }).map(ResolvedSelection.conference)
        case .mediaAppearance:
            return store.cvMediaAppearances.first(where: { $0.id == id }).map(ResolvedSelection.media)
        case .review:
            return store.cvReviewEntries.first(where: { $0.id == id }).map(ResolvedSelection.review)
        case .otherPublication:
            return store.cvOtherPublications
                .first(where: { $0.id == id && !$0.isDoctoralThesis })
                .map(ResolvedSelection.otherPublication)
        }
    }

}

struct ExpertAssignmentsWorkspaceView: View {
    /// Round 16 (user decision): status chips Pågående, Försenade, Klara,
    /// Avböjda, Utan status. The duplicate "Accepterade" is gone; a filter
    /// saved with it is read as no status filter.
    private typealias ExpertStatusFilter = ExpertAssignmentStatusKey

    /// One chip per expert-assignment category. Raw values are the
    /// CVReviewCategory raw values, so filters saved earlier still apply.
    private enum ExpertCategoryFilter: String, Codable, CaseIterable, Hashable, Identifiable {
        case journalReview
        case grantProposalReview
        case doctoralExamination
        case otherExpertAssignment

        var id: String { rawValue }

        func label(language: AppLanguage) -> String {
            CVReviewCategory(rawValue: rawValue)?.localizedTitle(language) ?? rawValue
        }
    }

    let store: GrantDataStore
    let newRecordTrigger: Int
    let isActive: Bool

    @State private var selectedItemID: String?
    @State private var sortHistory = ListSortPersistence.load(
        defaultsKey: "ExpertAssignmentsListSort",
        defaultValue: [CVListSortCriterion(column: .date, ascending: false)]
    )
    @WorkspaceFilterState("ExpertAssignments.Filter.Search") private var searchText = ""
    @WorkspaceFilterState("ExpertAssignments.Filter.Status") private var selectedExpertStatusFilters: Set<ExpertStatusFilter> = []
    @WorkspaceFilterState("ExpertAssignments.Filter.Category") private var selectedExpertCategoryFilters: Set<ExpertCategoryFilter> = []
    @State private var pendingSelectionMeasurementID: String?
    @State private var pendingSelectionStartedAt: CFAbsoluteTime?

    private var language: AppLanguage { store.language }

    private var sortOrder: [KeyPathComparator<CVListRow>] {
        cvListSortOrder(from: sortHistory)
    }

    private var rows: [CVListRow] {
        let searchQuery = SearchFilterQuery(raw: searchText)
        return allExpertRows
            .filter { row in
                matchesExpertSearch(row, query: searchQuery)
                    && matchesExpertChipFilters(row)
            }
            .sorted(using: sortOrder)
    }

    private var allExpertRows: [CVListRow] {
        store.cvReviewEntries
            .map {
                let category = $0.category
                let categoryLabel = category.localizedTitle(language)
                let title = cvReviewAssignmentListTitle($0, language: language)
                let context = cvReviewListContext($0)
                let dateLabel = cvReviewListDateLabel($0, language: language)
                let sortDate = cvReviewListSortDate($0)
                let workflowStatus = $0.workflowStatus()
                return CVListRow(
                    id: cvToken(for: .review, id: $0.id),
                    kind: .review,
                    categoryLabel: categoryLabel,
                    title: title,
                    contextLabel: context,
                    dateLabel: dateLabel,
                    sortCategory: CVReviewCategory.allCases.firstIndex(of: category) ?? 0,
                    sortStatus: cvReviewListStatusSortValue(workflowStatus),
                    sortTitle: title,
                    sortContext: context,
                    sortDate: sortDate,
                    normalizedSearchBlob: normalizedSearchFilterText([
                        categoryLabel,
                        title,
                        context,
                        $0.acceptedDate,
                        $0.deadlineDate,
                        $0.date,
                        workflowStatus?.localizedTitle(language) ?? ""
                    ].joined(separator: " ")),
                    reviewWorkflowStatus: workflowStatus,
                    reviewCategory: category,
                    reviewStatusKeys: Set(ExpertAssignmentStatusKey.keys(for: $0).map(\.rawValue))
                )
            }
    }

    private func matchesExpertSearch(_ row: CVListRow, query: SearchFilterQuery) -> Bool {
        query.isEmpty || query.matches(normalizedHaystack: row.normalizedSearchBlob)
    }

    /// OR within the status chips and within the category chips, AND between
    /// the two groups.
    private func matchesExpertChipFilters(_ row: CVListRow) -> Bool {
        matchesFilterChipGroups([
            (selected: Set(selectedExpertStatusFilters.map(\.rawValue)), values: row.reviewStatusKeys),
            (selected: Set(selectedExpertCategoryFilters.map(\.rawValue)), values: Set([row.reviewCategory?.rawValue].compactMap { $0 })),
        ])
    }

    /// Changes when the user changes a filter (not when data changes).
    private var expertFilterSignature: String {
        [
            searchText,
            selectedExpertStatusFilters.map(\.rawValue).sorted().joined(separator: ","),
            selectedExpertCategoryFilters.map(\.rawValue).sorted().joined(separator: ","),
        ].joined(separator: "|")
    }

    private func clearAllExpertAssignmentFilters() {
        searchText = ""
        selectedExpertStatusFilters.removeAll()
        selectedExpertCategoryFilters.removeAll()
        RestoredListFilters.forget(workspace: "ExpertAssignments")
    }

    /// Direct navigation and new records: clears only the filters that hide
    /// the assignment.
    private func revealExpertAssignmentRow(_ token: String) {
        guard let row = allExpertRows.first(where: { $0.id == token }) else { return }
        if !matchesExpertSearch(row, query: SearchFilterQuery(raw: searchText)) {
            searchText = ""
        }
        if !selectedExpertStatusFilters.isEmpty,
           !matchesFilterChipGroups([(selected: Set(selectedExpertStatusFilters.map(\.rawValue)), values: row.reviewStatusKeys)]) {
            selectedExpertStatusFilters.removeAll()
        }
        if let category = row.reviewCategory,
           !selectedExpertCategoryFilters.isEmpty,
           !selectedExpertCategoryFilters.contains(where: { $0.rawValue == category.rawValue }) {
            selectedExpertCategoryFilters.removeAll()
        }
    }

    private func createExpertAssignmentRevealingIt() {
        let token = cvToken(for: .review, id: store.addCVReviewEntry())
        revealExpertAssignmentRow(token)
        setSelectedItemID(token)
    }

    private var activeExpertFilterDescriptions: [String] {
        [
            ListFilterLabels.search(searchText, language: language),
            ListFilterLabels.chips(
                ExpertStatusFilter.allCases
                    .filter { selectedExpertStatusFilters.contains($0) }
                    .map { $0.title(language: language) }
            ),
            ListFilterLabels.chips(
                ExpertCategoryFilter.allCases
                    .filter { selectedExpertCategoryFilters.contains($0) }
                    .map { $0.label(language: language) }
            ),
        ].compactMap { $0 }
    }

    private var hasActiveExpertAssignmentFilters: Bool {
        searchText.nonEmpty != nil
            || !selectedExpertStatusFilters.isEmpty
            || !selectedExpertCategoryFilters.isEmpty
    }

    /// Assignments exist, but the filters hide every one of them.
    private func expertFiltersHideEverything(visibleRows: [CVListRow]) -> Bool {
        hasActiveExpertAssignmentFilters && visibleRows.isEmpty && !store.cvReviewEntries.isEmpty
    }

    /// Round 17: the same empty state as the other lists.
    private func expertFilterEmptyState(isCompact: Bool) -> some View {
        AppWorkspaceEmptyStateView(
            title: language.text("No expert assignments match the filters", "Inga sakkunniguppdrag matchar filtren"),
            subtitle: ListFilterLabels.hiddenByFilters(count: store.cvReviewEntries.count, language: language),
            kind: .expertAssignments,
            actionTitle: language.text("Clear filters", "Rensa filter"),
            action: clearAllExpertAssignmentFilters,
            isCompact: isCompact
        )
    }

    var body: some View {
        // Round 17: filtered and sorted once per redraw, not once per use.
        let visibleRows = rows
        let filtersHideEverything = expertFiltersHideEverything(visibleRows: visibleRows)
        PersistentSplitView(layout: .expertAssignments) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(expertAssignmentsPageTitle(language: language))
                        .appTypography(.pageTitle)
                    Spacer()
                    Button(language.text("Add", "Lägg till")) {
                        createExpertAssignmentRevealingIt()
                    }
                    .appAddButtonStyle()
                }

                AppFilterCard {
                    VStack(alignment: .leading, spacing: 8) {
                        AppFilterRow(
                            showsClearButton: searchText.nonEmpty != nil,
                            clearAction: { searchText = "" }
                        ) {
                            AppSidebarSearchField(
                                placeholder: language.text("Search expert assignments", "Sök sakkunniguppdrag"),
                                text: $searchText
                            )
                        }

                        expertFilterRows(language: language)
                        // Round 17: "clear all" is the banner's "Rensa filter".
                    }
                }

                if hasActiveExpertAssignmentFilters {
                    AppFilteredListBanner(
                        displayedCount: visibleRows.count,
                        totalCount: store.cvReviewEntries.count,
                        activeFilters: activeExpertFilterDescriptions,
                        restoredFromLastSession: RestoredListFilters.wasRestored(workspace: "ExpertAssignments.Filter"),
                        language: language,
                        clearAction: clearAllExpertAssignmentFilters
                    )
                }

                if filtersHideEverything {
                    expertFilterEmptyState(isCompact: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    expertList(rows: visibleRows)
                }

                // Round 17: the banner already gives the count while a
                // filter is on.
                if !hasActiveExpertAssignmentFilters {
                    ListCountFootnote(displayedCount: visibleRows.count, totalCount: store.cvReviewEntries.count, language: language)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AppPalette.sidebarPanelSurface)
        } detail: {
            Group {
                if let selectedItemID,
                   let review = resolvedReviewSelection(from: selectedItemID) {
                    CVReviewEntryDetailView(store: store, review: review)
                        .id(review.id)
                        .undoRevealPulse(
                            triggerID: store.undoRevealRequest?.id,
                            isActive: store.undoRevealRequest?.target.matchesWholeRecord(routeDestination: .expertAssignments, recordID: cvToken(for: .review, id: review.id)) == true
                        )
                        .performanceScopeProbe(store: store, scope: "expert-detail", identifier: review.id)
                        .background(
                            PerformanceReadyReporter {
                                guard pendingSelectionMeasurementID == cvToken(for: .review, id: review.id),
                                      let pendingSelectionStartedAt else { return }
                                let duration = (CFAbsoluteTimeGetCurrent() - pendingSelectionStartedAt) * 1000
                                store.appendPerformanceDiagnostic(
                                    String(
                                        format: "expert-selection-ready item=%@ ready_ms=%.2f",
                                        cvReviewListTitle(review, language: language),
                                        duration
                                    )
                                )
                                self.pendingSelectionMeasurementID = nil
                                self.pendingSelectionStartedAt = nil
                            }
                        )
                } else if filtersHideEverything {
                    expertFilterEmptyState(isCompact: false)
                } else {
                    AppWorkspaceEmptyStateView(
                        title: language.text("No expert assignments yet", "Inga sakkunniguppdrag ännu"),
                        subtitle: language.text("Create or select an expert assignment.", "Skapa eller välj ett sakkunniguppdrag."),
                        kind: .expertAssignments
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            clearSavedExpertFiltersAtLaunchIfNeeded()
            if let route = store.route,
               isExpertAssignmentRoute(route),
               route.recordID.hasPrefix("\(CVItemKind.review.rawValue):") {
                revealExpertAssignmentRow(route.recordID)
                setSelectedItemID(route.recordID)
                store.consumeRoute()
            } else {
                // Round 17: a remembered assignment that a saved filter hides
                // is replaced by the first visible row.
                let visibleIDs = rows.map(\.id)
                setSelectedItemID(ListSelectionPolicy.selectionAfterFilterChange(
                    selected: selectedItemID ?? store.lastSelectedRecordID(for: .expertAssignments) ?? visibleIDs.first,
                    visibleIDs: visibleIDs
                ))
            }
        }
        .onChange(of: store.route) { _, route in
            guard let route,
                  isExpertAssignmentRoute(route),
                  route.recordID.hasPrefix("\(CVItemKind.review.rawValue):")
            else { return }
            revealExpertAssignmentRow(route.recordID)
            setSelectedItemID(route.recordID)
            store.consumeRoute()
        }
        // A filter change that hides the selected assignment moves the
        // selection to the first visible row.
        .onChange(of: expertFilterSignature) { _, _ in
            let next = ListSelectionPolicy.selectionAfterFilterChange(
                selected: selectedItemID,
                visibleIDs: rows.map(\.id)
            )
            if next != selectedItemID {
                setSelectedItemID(next)
            }
        }
        .onChange(of: selectedItemID) { _, newValue in
            store.rememberSelection(id: newValue, for: .expertAssignments)
            pendingSelectionMeasurementID = newValue
            pendingSelectionStartedAt = CFAbsoluteTimeGetCurrent()
            store.appendPerformanceDiagnostic(
                String(
                    format: "expert-selection-start id=%@",
                    newValue ?? "-"
                )
            )
        }
        .onChange(of: newRecordTrigger) { _, _ in
            guard isActive else { return }
            createExpertAssignmentRevealingIt()
        }
        .onReceive(
            store.$cvReviewEntries.map { $0.map { cvToken(for: .review, id: $0.id) } }.removeDuplicates().dropFirst()
        ) { ids in
            // Deferred: @Published emits at willSet and the selection
            // resolution reads the store's committed state.
            DispatchQueue.main.async {
                guard let selectedItemID else {
                    setSelectedItemID(ids.first)
                    return
                }
                if resolvedReviewSelection(from: selectedItemID) == nil {
                    setSelectedItemID(ids.first)
                }
            }
        }
        .onChange(of: isActive) { _, active in
            guard !active else { return }
            clearExpertAssignmentFiltersForDeactivationIfNeeded()
        }
    }

    private func isExpertAssignmentRoute(_ route: AppRoute) -> Bool {
        route.destination == .expertAssignments
            || (route.destination == .cv && route.recordID.hasPrefix("\(CVItemKind.review.rawValue):"))
    }

    private func expertFilterRows(language: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AppFilterRow(
                showsClearButton: !selectedExpertStatusFilters.isEmpty,
                clearAction: { selectedExpertStatusFilters.removeAll() }
            ) {
                ForEach(ExpertStatusFilter.allCases, id: \.self) { filter in
                    AppFilterChip(
                        label: filter.title(language: language),
                        isSelected: selectedExpertStatusFilters.contains(filter)
                    ) {
                        toggleExpertStatusFilter(filter)
                    }
                }
            }
            AppFilterRow(
                showsClearButton: !selectedExpertCategoryFilters.isEmpty,
                clearAction: { selectedExpertCategoryFilters.removeAll() }
            ) {
                ForEach(ExpertCategoryFilter.allCases) { filter in
                    AppFilterChip(
                        label: filter.label(language: language),
                        isSelected: selectedExpertCategoryFilters.contains(filter)
                    ) {
                        toggleExpertCategoryFilter(filter)
                    }
                }
            }
        }
    }

    private func toggleExpertStatusFilter(_ filter: ExpertStatusFilter) {
        if selectedExpertStatusFilters.contains(filter) {
            selectedExpertStatusFilters.remove(filter)
        } else {
            selectedExpertStatusFilters.insert(filter)
        }
    }

    private func toggleExpertCategoryFilter(_ filter: ExpertCategoryFilter) {
        if selectedExpertCategoryFilters.contains(filter) {
            selectedExpertCategoryFilters.remove(filter)
        } else {
            selectedExpertCategoryFilters.insert(filter)
        }
    }

    private func resolvedReviewSelection(from token: String) -> CVReviewEntry? {
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == CVItemKind.review.rawValue else { return nil }
        return store.cvReviewEntries.first(where: { $0.id == parts[1] })
    }

    @ViewBuilder
    private func disseminationList(rows: [CVListRow]) -> some View {
        cvList(
            rows: rows,
            columns: [
                (language.text("Category", "Kategori"), 140, CVListSortColumn.category),
                (language.text("Title", "Rubrik"), nil, CVListSortColumn.title),
                (language.text("Date", "Datum"), 110, CVListSortColumn.date)
            ]
        ) { row in
            HStack(spacing: 0) {
                Text(row.categoryLabel)
                    .appTypography(.tableHeader)
                    .frame(width: 140, alignment: .leading)
                Text(row.title)
                    .appTypography(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(row.dateLabel)
                    .appTypography(.secondary)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func expertList(rows: [CVListRow]) -> some View {
        cvList(
            rows: rows,
            columns: [
                (language.text("Category", "Kategori"), 138, CVListSortColumn.category),
                (language.text("Assignment", "Uppdrag"), nil, CVListSortColumn.title),
                (language.text("Journal / organization", "Tidskrift / organisation"), 178, CVListSortColumn.context),
                (language.text("Updated", "Uppdaterad"), 106, CVListSortColumn.date)
            ],
            routeDestination: .expertAssignments
        ) { row in
            HStack(spacing: 0) {
                Text(row.categoryLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 138, alignment: .leading)
                Text(row.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 220, alignment: .leading)
                Text(row.contextLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 178, alignment: .leading)
                Text(row.dateLabel)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 106, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func reviewWorkflowStatusIndicator(_ status: CVReviewWorkflowStatus?) -> some View {
        let colors = reviewWorkflowStatusColors(status)
        let title = status?.localizedTitle(language) ?? language.text("No status", "Ingen status")
        AppStatusDot(fill: colors.fill, stroke: colors.stroke, help: title)
    }

    private func reviewWorkflowStatusColors(_ status: CVReviewWorkflowStatus?) -> (fill: Color, stroke: Color) {
        // Round 16: the shared expert assignment tones (overdue orange).
        let tone = AppStatusTones.review(status)
        guard tone.hasFill else {
            return (.clear, AppPalette.border.opacity(0.95))
        }
        return (AppPalette.statusFill(tone), AppPalette.statusText(tone).opacity(0.45))
    }

    @ViewBuilder
    private func cvList<RowContent: View>(
        rows: [CVListRow],
        columns: [(String, CGFloat?, CVListSortColumn)],
        minimumFlexibleColumnWidth: CGFloat = 220,
        routeDestination: AppRoute.Destination = .cv,
        @ViewBuilder rowContent: @escaping (CVListRow) -> RowContent
    ) -> some View {
        let fixedWidth = columns.compactMap(\.1).reduce(0, +)
        let flexibleCount = columns.filter { $0.1 == nil }.count
        let tableContentWidth = fixedWidth + (CGFloat(flexibleCount) * minimumFlexibleColumnWidth) + 20
        let orderedIDs = rows.map(\.id)

        AppListTable(contentWidth: tableContentWidth) {
            HStack(spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    cvListHeader(column.0, width: column.1, sortColumn: column.2)
                        .frame(width: column.1 ?? minimumFlexibleColumnWidth, alignment: .leading)
                }
            }
        } rows: {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows, id: \.id) { row in
                    AppListRowButton(
                        width: tableContentWidth,
                        action: { setSelectedItemID(row.id) },
                        background: { cvListRowBackground(for: row) }
                    ) {
                        rowContent(row)
                    }

                    if row.id != rows.last?.id {
                        Divider()
                    }
                }
            }
        }
        .appListKeyboardNavigation(
            store: store,
            destination: routeDestination,
            isEnabled: isActive,
            orderedIDs: orderedIDs,
            selectedID: selectedItemID,
            onSelect: { setSelectedItemID($0) }
        )
    }

    private func cvListRowBackground(for row: CVListRow) -> some View {
        Group {
            if row.id == selectedItemID {
                SelectedListRowBackground(indicatorFill: reviewWorkflowStatusShadeFill(row.reviewWorkflowStatus))
            } else if let fill = reviewWorkflowStatusShadeFill(row.reviewWorkflowStatus) {
                StatusIndicatorListRowBackground(fill: fill)
            } else {
                Color.clear
            }
        }
    }

    private func reviewWorkflowStatusShadeFill(_ status: CVReviewWorkflowStatus?) -> Color? {
        AppPalette.statusRowFill(AppStatusTones.review(status))
    }

    private func setSelectedItemID(_ newValue: String?) {
        guard selectedItemID != newValue else { return }
        // Commit active field edits before switching records to avoid value bleed.
        NSApp.keyWindow?.makeFirstResponder(nil)
        selectedItemID = newValue
    }

    private func clearExpertAssignmentFiltersForDeactivationIfNeeded() {
        guard !store.shouldRetainListFilters(for: .expertAssignments) else { return }
        searchText = ""
        selectedExpertStatusFilters.removeAll()
        selectedExpertCategoryFilters.removeAll()
    }

    /// Round 17: with "keep filters" off in Settings, filters saved by an
    /// earlier run are cleared the first time the list is shown.
    private func clearSavedExpertFiltersAtLaunchIfNeeded() {
        guard ListFilterLaunchPolicy.shouldClearSavedFilters(
            for: .expertAssignments,
            retainsFilters: store.shouldRetainListFilters(for: .expertAssignments)
        ) else { return }
        clearAllExpertAssignmentFilters()
    }

    private func cvListHeader(_ title: String, width: CGFloat?, sortColumn: CVListSortColumn) -> some View {
        let criterion = sortCriterion(for: sortColumn)
        let sortIndex = sortIndex(for: sortColumn)
        return AppSortableListHeader(
            title: title,
            ascending: criterion?.ascending,
            sortIndex: sortIndex,
            width: width,
            resetTitle: language.text("Reset", "Återställ"),
            onToggle: { toggleSort(sortColumn) },
            onReset: resetSort
        )
    }

    private func toggleSort(_ column: CVListSortColumn) {
        if let existingIndex = sortHistory.firstIndex(where: { $0.column == column }) {
            if existingIndex == 0 {
                sortHistory[0].ascending.toggle()
            } else {
                let criterion = sortHistory.remove(at: existingIndex)
                sortHistory.insert(criterion, at: 0)
            }
        } else {
            sortHistory.insert(CVListSortCriterion(column: column, ascending: column.defaultAscending), at: 0)
        }
        ListSortPersistence.save(sortHistory, defaultsKey: "ExpertAssignmentsListSort")
    }

    private func resetSort() {
        sortHistory = [
            CVListSortCriterion(column: .date, ascending: false)
        ]
        ListSortPersistence.save(sortHistory, defaultsKey: "ExpertAssignmentsListSort")
    }

    private func sortCriterion(for column: CVListSortColumn) -> CVListSortCriterion? {
        sortHistory.first(where: { $0.column == column })
    }

    private func sortIndex(for column: CVListSortColumn) -> Int? {
        sortHistory.firstIndex(where: { $0.column == column })
    }
}

final class CVRichTextEditorController: ObservableObject {
    weak var textView: NSTextView?

    @MainActor
    func toggleBold() {
        toggleFontTrait(.boldFontMask)
    }

    @MainActor
    func toggleItalic() {
        toggleFontTrait(.italicFontMask)
    }

    @MainActor
    func toggleUnderline() {
        guard let textView else { return }
        let range = textView.selectedRange()
        guard range.location != NSNotFound else { return }
        let storage = textView.textStorage ?? NSTextStorage()
        let effectiveRange = range.length == 0 ? NSRange(location: 0, length: storage.length) : range
        guard effectiveRange.location + effectiveRange.length <= storage.length else { return }
        var hasUnderline = false
        storage.enumerateAttribute(.underlineStyle, in: effectiveRange) { value, _, stop in
            if let number = value as? NSNumber, number.intValue != 0 {
                hasUnderline = true
                stop.pointee = true
            }
        }
        storage.addAttribute(
            .underlineStyle,
            value: hasUnderline ? 0 : NSUnderlineStyle.single.rawValue,
            range: effectiveRange
        )
        NotificationCenter.default.post(name: NSText.didChangeNotification, object: textView)
    }

    /// Adds or removes a literal bullet prefix on every line touched by the
    /// selection. Bullets are plain text, so they survive any storage format.
    @MainActor
    func toggleBulletList() {
        guard let textView, let storage = textView.textStorage else { return }
        let text = storage.string as NSString
        let lineStarts = selectedLineStarts(in: textView)
        guard !lineStarts.isEmpty else { return }

        func lineLevel(_ start: Int) -> Int? {
            bulletLevel(atLineStart: start, in: text)
        }

        let removeBullets = lineStarts.allSatisfy { lineLevel($0) != nil }
        for start in lineStarts.reversed() {
            if removeBullets {
                guard let level = lineLevel(start) else { continue }
                let prefix = ProtocolMarkup.bulletPrefix(forLevel: level)
                replacePrefix(oldLength: prefix.count, with: "", atLineStart: start, in: textView)
            } else if lineLevel(start) == nil {
                replacePrefix(oldLength: 0, with: ProtocolMarkup.bulletPrefix, atLineStart: start, in: textView)
            }
        }
    }

    /// Moves every bulleted line in the selection one list level in or out.
    /// Indenting a non-bulleted line starts a level-1 bullet; outdenting a
    /// level-1 bullet removes it.
    @MainActor
    func changeBulletLevel(by delta: Int) {
        guard delta != 0, let textView, let storage = textView.textStorage else { return }
        let text = storage.string as NSString
        for start in selectedLineStarts(in: textView).reversed() {
            let level = bulletLevel(atLineStart: start, in: text)
            if let level {
                let prefix = ProtocolMarkup.bulletPrefix(forLevel: level)
                let newLevel = level + delta
                if newLevel < 1 {
                    replacePrefix(oldLength: prefix.count, with: "", atLineStart: start, in: textView)
                } else if newLevel <= ProtocolMarkup.maxBulletLevel {
                    let newPrefix = ProtocolMarkup.bulletPrefix(forLevel: newLevel)
                    replacePrefix(oldLength: prefix.count, with: newPrefix, atLineStart: start, in: textView)
                }
            } else if delta > 0 {
                replacePrefix(oldLength: 0, with: ProtocolMarkup.bulletPrefix, atLineStart: start, in: textView)
            }
        }
    }

    @MainActor
    private func selectedLineStarts(in textView: NSTextView) -> [Int] {
        let selection = textView.selectedRange()
        guard selection.location != NSNotFound, let storage = textView.textStorage else { return [] }
        let text = storage.string as NSString
        let selectionLineRange = text.lineRange(for: selection)

        var lineStarts: [Int] = []
        var location = selectionLineRange.location
        repeat {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            lineStarts.append(lineRange.location)
            guard lineRange.length > 0 else { break }
            location = NSMaxRange(lineRange)
        } while location < NSMaxRange(selectionLineRange)
        return lineStarts
    }

    private func bulletLevel(atLineStart start: Int, in text: NSString) -> Int? {
        let lineRange = text.lineRange(for: NSRange(location: start, length: 0))
        return ProtocolMarkup.bulletLevel(ofLine: text.substring(with: lineRange))
    }

    @MainActor
    private func replacePrefix(oldLength: Int, with newPrefix: String, atLineStart start: Int, in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let range = NSRange(location: start, length: oldLength)
        guard textView.shouldChangeText(in: range, replacementString: newPrefix) else { return }
        storage.replaceCharacters(
            in: range,
            with: NSAttributedString(
                string: newPrefix,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.labelColor,
                ]
            )
        )
        textView.didChangeText()
    }

    @MainActor
    private func toggleFontTrait(_ trait: NSFontTraitMask) {
        guard let textView else { return }
        let range = textView.selectedRange()
        guard range.location != NSNotFound else { return }
        let storage = textView.textStorage ?? NSTextStorage()
        let effectiveRange = range.length == 0 ? NSRange(location: 0, length: storage.length) : range
        guard effectiveRange.location + effectiveRange.length <= storage.length else { return }

        let manager = NSFontManager.shared
        storage.enumerateAttribute(.font, in: effectiveRange) { value, subrange, _ in
            let baseFont = (value as? NSFont) ?? NSFont.systemFont(ofSize: 13)
            let currentTraits = manager.traits(of: baseFont)
            let updatedFont: NSFont
            if currentTraits.contains(trait) {
                updatedFont = manager.convert(baseFont, toNotHaveTrait: trait)
            } else {
                updatedFont = manager.convert(baseFont, toHaveTrait: trait)
            }
            storage.addAttribute(.font, value: updatedFont, range: subrange)
        }
        NotificationCenter.default.post(name: NSText.didChangeNotification, object: textView)
    }
}

struct CVRichTextEditorRepresentable: NSViewRepresentable {
    @Binding var document: CVRichTextDocument
    @ObservedObject var controller: CVRichTextEditorController

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // F32: a bare NSTextView() has zero size and never grows with its
        // scroll view, so the text was loaded but had no room to draw, and
        // clicks and Tab passed it by. AppKit's own factory gives a sized one.
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = (scrollView.documentView as? NSTextView) ?? NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.font = .systemFont(ofSize: 13)
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.drawsBackground = !AppRuntime.usesRenewedChrome
        textView.backgroundColor = AppRuntime.usesRenewedChrome ? .clear : .textBackgroundColor
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textStorage?.setAttributedString(document.attributedString(baseFontSize: 13))

        scrollView.documentView = textView
        controller.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        controller.textView = textView
        let desired = document.attributedString(baseFontSize: 13)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.drawsBackground = !AppRuntime.usesRenewedChrome
        textView.backgroundColor = AppRuntime.usesRenewedChrome ? .clear : .textBackgroundColor
        if !textView.attributedString().isEqual(to: desired) {
            let previousSelection = textView.selectedRange()
            context.coordinator.isApplying = true
            textView.textStorage?.setAttributedString(desired)
            let clampedLocation = min(previousSelection.location, textView.string.count)
            let clampedLength = min(previousSelection.length, max(0, textView.string.count - clampedLocation))
            textView.setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
            context.coordinator.isApplying = false
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CVRichTextEditorRepresentable
        var isApplying = false

        init(_ parent: CVRichTextEditorRepresentable) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplying,
                  let textView = notification.object as? NSTextView else { return }
            if let storage = textView.textStorage {
                RichTextBulletLayout.applyParagraphStyles(to: storage)
            }
            parent.document = CVRichTextDocument.from(textView.attributedString())
        }

        func textDidBeginEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let scrollView = textView.enclosingScrollView else { return }
            AppFocusPulse.setFocused(true, on: scrollView, cornerRadius: 8)
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let scrollView = textView.enclosingScrollView else { return }
            AppFocusPulse.setFocused(false, on: scrollView, cornerRadius: 8)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)),
               handleBulletContinuation(in: textView) {
                return true
            }
            switch AppFormKeyboardRouting.focusDirection(for: commandSelector) {
            case .forward:
                textView.window?.selectNextKeyView(textView)
                return true
            case .backward:
                textView.window?.selectPreviousKeyView(textView)
                return true
            case nil:
                return false
            }
        }

        /// Return inside a bulleted line continues the list; return on an
        /// empty bullet ends it (removes the dangling "• ").
        @MainActor
        private func handleBulletContinuation(in textView: NSTextView) -> Bool {
            let selection = textView.selectedRange()
            guard selection.length == 0 else { return false }
            let text = textView.string as NSString
            guard selection.location <= text.length else { return false }
            let lineRange = text.lineRange(for: NSRange(location: selection.location, length: 0))
            let line = text.substring(with: lineRange).trimmingCharacters(in: .newlines)
            let bareGlyphs = ProtocolMarkup.bulletPrefixes.map { $0.trimmingCharacters(in: .whitespaces) }
            guard bareGlyphs.contains(where: { line.hasPrefix($0) }) else { return false }
            if ProtocolMarkup.bulletPrefixes.contains(line) || bareGlyphs.contains(line) {
                let bulletRange = NSRange(location: lineRange.location, length: (line as NSString).length)
                guard textView.shouldChangeText(in: bulletRange, replacementString: "") else { return false }
                textView.textStorage?.replaceCharacters(in: bulletRange, with: "")
                textView.didChangeText()
                return true
            }
            guard let level = ProtocolMarkup.bulletLevel(ofLine: line) else { return false }
            textView.insertText("\n\(ProtocolMarkup.bulletPrefix(forLevel: level))", replacementRange: selection)
            return true
        }
    }
}

struct CVRichTextFormatButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }
}


struct CVConferenceContributionDetailView: View {
    @ObservedObject var store: GrantDataStore
    let contribution: CVConferenceContribution
    let showsCongressField: Bool
    let showsTaskList: Bool
    let usesAbstractTerminology: Bool
    let isEditingLocked: Bool
    @Environment(\.scenePhase) private var scenePhase

    @State private var draft: CVConferenceContribution
    @State private var taskRows: [PublicationTaskItem]
    @State private var autosaveTask: DispatchWorkItem?
    @State private var forcedPersistTask: DispatchWorkItem?
    @State private var pendingContributorName: String = ""
    @State private var draggedContributorName: String?
    @State private var contributorIdentity: StableStringDraftListState
    @State private var editingContributorOriginalName: String?
    @State private var editingContributorText = ""
    private let contributorNameFieldWidth: CGFloat = ResearcherNameFieldMetrics.compactWidth
    private let contributorLinkColumnWidth: CGFloat = 34
    private let contributorTrashColumnWidth: CGFloat = 28

    init(
        store: GrantDataStore,
        contribution: CVConferenceContribution,
        showsCongressField: Bool = true,
        showsTaskList: Bool = true,
        usesAbstractTerminology: Bool = false,
        isEditingLocked: Bool = false
    ) {
        self.store = store
        self.contribution = contribution
        self.showsCongressField = showsCongressField
        self.showsTaskList = showsTaskList
        self.usesAbstractTerminology = usesAbstractTerminology
        self.isEditingLocked = isEditingLocked
        _draft = State(initialValue: contribution)
        _contributorIdentity = State(initialValue: StableStringDraftListState(values: contribution.contributorNames))
        _taskRows = State(initialValue: Self.normalizedTasks(contribution.tasks))
    }

    private var language: AppLanguage { store.language }

    private var projectOptions: [String] {
        store.projects
            .map { store.projectLabel(for: $0.nameSv, language: language) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var authorOptions: [String] {
        store.coauthors
            .map(\.displayName)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var journalOptions: [String] {
        store.journals
            .map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var associationOptions: [OrganizationRecord] {
        store.organizations
            .filter { $0.roles.contains(.association) }
            .sorted { localizedAssociationName($0).localizedStandardCompare(localizedAssociationName($1)) == .orderedAscending }
    }

    private var congressOptions: [ConferenceCongressSelection] {
        associationOptions.flatMap { association in
            association.congresses.map { congress in
                ConferenceCongressSelection(
                    associationID: association.id,
                    associationName: localizedAssociationName(association),
                    congress: congress
                )
            }
        }
        .sorted { $0.menuLabel.localizedStandardCompare($1.menuLabel) == .orderedAscending }
    }

    private var congressMenuOptions: [(label: String, value: String)] {
        [(language.text("Select congress", "Välj kongress"), "")]
            + congressOptions.map { ($0.menuLabel, $0.selectionID) }
    }

    private var selectedJournal: PublicationJournal? {
        if let journalID = draft.journalID, let journal = store.publicationJournal(id: journalID) {
            return journal
        }
        return draft.journalName.nonEmpty.flatMap { store.publicationJournal(named: $0) }
    }

    private var resolvedPublicationJournalName: String {
        selectedJournal?.name ?? draft.journalName
    }

    private var hasPublicationData: Bool {
        [
            resolvedPublicationJournalName,
            draft.publicationYear,
            draft.journalVolume,
            draft.journalIssue,
            draft.journalPages,
            draft.journalArticleNumber,
            draft.journalDOI,
            draft.journalPMID,
            draft.pdfFilename ?? "",
            draft.pdfPath ?? ""
        ].contains { $0.trimmedOrNil != nil }
    }

    private var showsPublicationPanel: Bool {
        guard !draft.isRejected else { return false }
        return !isEditingLocked || hasPublicationData
    }

    private var showsContributionPDFControls: Bool {
        !draft.isRejected && (draft.isAcceptedOrPresented || hasContributionPDFAttachment)
    }

    private var showsPublicationCoreRow: Bool {
        shouldShowPublicationField(resolvedPublicationJournalName) ||
            shouldShowPublicationField(draft.publicationYear)
    }

    private var showsPublicationBibliographyRow: Bool {
        shouldShowPublicationField(draft.journalVolume) ||
            shouldShowPublicationField(draft.journalIssue) ||
            shouldShowPublicationField(draft.journalPages) ||
            shouldShowPublicationField(draft.journalArticleNumber)
    }

    private var showsPublicationIdentifierRow: Bool {
        shouldShowPublicationField(draft.journalDOI) ||
            shouldShowPublicationField(draft.journalPMID)
    }

    private var selectedCongress: ConferenceCongressSelection? {
        congressOptions.first {
            $0.associationID == draft.congressOrganizationID && $0.congress.id == draft.congressID
        }
    }

    private var selectedCongressOrganization: OrganizationRecord? {
        store.organization(id: draft.congressOrganizationID)
    }

    private var selectedProject: ProjectRecord? {
        store.linkedProject(of: draft)
    }

    private var localizedContributionTitle: String {
        draft.localizedTitle(language: language).trimmedOrNil ?? draft.displayTitle
    }

    private var localizedProjectDisplayName: String {
        draft.localizedProjectName(language: language)
    }

    private var localizedCommentsText: String {
        draft.localizedComments(language: language)
    }

    private var lockedCongressDisplayName: String {
        selectedCongress?.menuLabel
            ?? draft.localizedMeeting(language: language).trimmedOrNil
            ?? draft.congressLink.trimmedOrNil
            ?? ""
    }

    private var shouldShowCongressOverviewField: Bool {
        guard showsCongressField else { return false }
        return !isEditingLocked || lockedCongressDisplayName.trimmedOrNil != nil
    }

    private var shouldShowProjectOverviewField: Bool {
        AppLockedFieldVisibility.shouldShow(isLocked: isEditingLocked, value: localizedProjectDisplayName)
    }

    private var shouldShowContributorsOverviewField: Bool {
        !isEditingLocked || !draft.contributorNames.isEmpty
    }

    private var shouldShowOverviewPanel: Bool {
        !isEditingLocked || shouldShowCongressOverviewField || shouldShowProjectOverviewField || shouldShowContributorsOverviewField
    }

    private var hasSubmissionProcessData: Bool {
        [
            draft.submissionAppliedOn,
            draft.submissionClosesOn,
            draft.submissionDecisionExpectedOn,
            draft.submissionDecisionOn
        ].contains { $0.trimmedOrNil != nil } || draft.submissionOutcome != nil
    }

    private var shouldShowSubmissionProcessPanel: Bool {
        !isEditingLocked || hasSubmissionProcessData
    }

    private var shouldShowCommentsPanel: Bool {
        AppLockedFieldVisibility.shouldShow(isLocked: isEditingLocked, value: localizedCommentsText)
    }

    private var lockedFieldSpacing: CGFloat {
        isEditingLocked ? 8 : 14
    }

    private var lockedContributorSpacing: CGFloat {
        isEditingLocked ? 3 : AutocompleteSelectionMetrics.rowSpacing
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        if isEditingLocked {
                            Text(localizedContributionTitle)
                                .appTypography(.pageTitle)
                                .foregroundStyle(AppPalette.appText)
                                .lineLimit(1...3)
                        } else {
                            TextField(language.text("Title", "Titel"), text: localizedTitleBinding, axis: .vertical)
                                .textFieldStyle(.plain)
                                .appTypography(.pageTitle)
                                .lineLimit(1...3)
                        }
                        Text(usesAbstractTerminology ? "Abstract" : language.text("Conference contribution", "Konferensbidrag"))
                            .appTypography(.secondary)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    if !isEditingLocked {
                        AppDestructiveActionButton(
                            title: usesAbstractTerminology ? language.text("Delete abstract", "Ta bort abstract") : language.text("Delete conference contribution", "Ta bort konferensbidrag"),
                            help: usesAbstractTerminology ? language.text("Delete this abstract", "Ta bort detta abstract") : language.text("Delete this conference contribution", "Ta bort detta konferensbidrag"),
                            cancelTitle: language.text("Cancel", "Avbryt"),
                            confirmationTitle: usesAbstractTerminology ? language.text("Delete abstract?", "Ta bort abstract?") : language.text("Delete conference contribution?", "Ta bort konferensbidrag?"),
                            confirmationMessage: language.text("The deletion can be undone.", "Borttagningen kan ångras.")
                        ) {
                            store.deleteCVConferenceContribution(id: contribution.id)
                        }
                    }
                }

                if shouldShowOverviewPanel {
                    CVPanel(title: language.text("Overview", "Översikt")) {
                        VStack(alignment: .leading, spacing: lockedFieldSpacing) {
                            if shouldShowCongressOverviewField {
                                CVLabeledField(title: language.text("Congress", "Kongress"), compact: isEditingLocked) {
                                    HStack(spacing: 8) {
                                        if isEditingLocked {
                                            AppLockedFieldValueText(text: lockedCongressDisplayName)
                                                .frame(maxWidth: 460, alignment: .leading)
                                        } else {
                                            AppMenuSelectionField(
                                                selection: congressSelectionBinding,
                                                options: congressMenuOptions,
                                                placeholder: language.text("Select congress", "Välj kongress")
                                            )
                                            .frame(maxWidth: 460, alignment: .leading)
                                        }

                                        if let selectedCongressOrganization {
                                            AppDestinationActionButton(
                                                kind: .app,
                                                language: language,
                                                title: language.text("Open organization", "Öppna organisation"),
                                                fontSize: 12
                                            ) {
                                                openSelectedCongressOrganization(selectedCongressOrganization)
                                            }
                                        }
                                    }
                                }
                            }

                            if shouldShowProjectOverviewField {
                                CVLabeledField(title: language.text("Project", "Projekt"), compact: isEditingLocked) {
                                    HStack(spacing: 8) {
                                        if isEditingLocked {
                                            AppLockedFieldValueText(text: localizedProjectDisplayName)
                                                .frame(maxWidth: 460, alignment: .leading)
                                        } else {
                                            AutocompleteSelectionField(
                                                text: projectBinding,
                                                options: projectOptions,
                                                placeholder: language.text("Project", "Projekt"),
                                                onCommit: {}
                                            )
                                            .frame(maxWidth: 460, alignment: .leading)
                                        }

                                        if let selectedProject {
                                            AppDestinationActionButton(
                                                kind: .app,
                                                language: language,
                                                title: language.text("Open project", "Öppna projekt"),
                                                fontSize: 12
                                            ) {
                                                store.openRoute(for: selectedProject)
                                            }
                                        }
                                    }
                                }
                            }

                            if shouldShowContributorsOverviewField {
                                CVLabeledField(title: language.text("Contributors", "Medverkande"), compact: isEditingLocked) {
                                    VStack(alignment: .leading, spacing: lockedContributorSpacing) {
                                        if isEditingLocked {
                                            lockedContributorsContent
                                        } else if draft.contributorNames.isEmpty {
                                            Text(language.text("No contributors added yet", "Inga medverkande tillagda ännu"))
                                                .appTypography(.secondary)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            editableContributorsContent
                                        }

                                        if !isEditingLocked {
                                            addContributorRow
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if shouldShowSubmissionProcessPanel {
                    CVPanel(title: language.text("Submission process", "Submissionprocess")) {
                        VStack(alignment: .leading, spacing: 16) {
                            ConferenceSubmissionTimelineStepper(
                                contribution: $draft,
                                language: language,
                                usesAbstractTerminology: usesAbstractTerminology,
                                isReadOnly: isEditingLocked,
                                onMutate: scheduleAutosave
                            )
                            .padding(.horizontal, 18)
                        }
                    }
                }

                if showsPublicationPanel {
                    CVPanel(title: usesAbstractTerminology ? language.text("Abstract publication", "Publikation av abstract") : language.text("Publication", "Publikation")) {
                        VStack(alignment: .leading, spacing: 14) {
                            if showsPublicationCoreRow {
                                HStack(alignment: .top, spacing: 12) {
                                    if shouldShowPublicationField(resolvedPublicationJournalName) {
                                        CVLabeledField(title: language.text("Journal", "Tidskrift"), compact: isEditingLocked) {
                                            publicationJournalField()
                                        }
                                    }
                                    if shouldShowPublicationField(draft.publicationYear) {
                                        CVLabeledField(title: language.text("Year", "År"), compact: isEditingLocked) {
                                            publicationValueField(
                                                placeholder: language.text("Year", "År"),
                                                value: draft.publicationYear,
                                                text: binding(\.publicationYear)
                                            )
                                        }
                                    }
                                }
                            }

                            if showsPublicationBibliographyRow {
                                HStack(alignment: .top, spacing: 12) {
                                    if shouldShowPublicationField(draft.journalVolume) {
                                        CVLabeledField(title: language.text("Volume", "Volym"), compact: isEditingLocked) {
                                            publicationValueField(
                                                placeholder: language.text("Volume", "Volym"),
                                                value: draft.journalVolume,
                                                text: binding(\.journalVolume)
                                            )
                                        }
                                    }
                                    if shouldShowPublicationField(draft.journalIssue) {
                                        CVLabeledField(title: language.text("Issue", "Nummer"), compact: isEditingLocked) {
                                            publicationValueField(
                                                placeholder: language.text("Issue", "Nummer"),
                                                value: draft.journalIssue,
                                                text: binding(\.journalIssue)
                                            )
                                        }
                                    }
                                    if shouldShowPublicationField(draft.journalPages) {
                                        CVLabeledField(title: language.text("Pages", "Sidor"), compact: isEditingLocked) {
                                            publicationValueField(
                                                placeholder: language.text("Pages", "Sidor"),
                                                value: draft.journalPages,
                                                text: binding(\.journalPages)
                                            )
                                        }
                                    }
                                    if shouldShowPublicationField(draft.journalArticleNumber) {
                                        CVLabeledField(title: language.text("Article no.", "Artikelnummer"), compact: isEditingLocked) {
                                            publicationValueField(
                                                placeholder: language.text("Article no.", "Artikelnummer"),
                                                value: draft.journalArticleNumber,
                                                text: binding(\.journalArticleNumber)
                                            )
                                        }
                                    }
                                }
                            }

                            if showsPublicationIdentifierRow {
                                HStack(alignment: .top, spacing: 12) {
                                    if shouldShowPublicationField(draft.journalDOI) {
                                        CVLabeledField(title: "DOI", compact: isEditingLocked) {
                                            publicationValueField(
                                                placeholder: "DOI",
                                                value: draft.journalDOI,
                                                text: binding(\.journalDOI)
                                            )
                                        }
                                    }
                                    if shouldShowPublicationField(draft.journalPMID) {
                                        CVLabeledField(title: "PMID", compact: isEditingLocked) {
                                            publicationValueField(
                                                placeholder: "PMID",
                                                value: draft.journalPMID,
                                                text: binding(\.journalPMID)
                                            )
                                        }
                                    }
                                }
                            }

                            if showsContributionPDFControls {
                                CVLabeledField(title: "PDF", compact: isEditingLocked) {
                                    contributionPDFControls
                                }
                            }
                        }
                    }
                }

                if shouldShowCommentsPanel {
                    CVPanel(title: language.text("Comments", "Kommentarer")) {
                        VStack(alignment: .leading, spacing: 14) {
                            CVLabeledField(title: language.text("Comments", "Kommentarer"), compact: isEditingLocked) {
                                if isEditingLocked {
                                    AppLockedFieldValueText(text: localizedCommentsText, lineLimit: nil)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    CVMultilineTextEditor(text: localizedCommentsBinding)
                                }
                            }
                        }
                    }
                }

                if showsTaskList && (
                    !isEditingLocked || CentralTaskListSection.hasIncompleteTasks(
                        store: store,
                        linkKind: .conferenceContribution,
                        targetID: draft.id
                    )
                ) {
                    CVPanel(
                        title: language.text("Task list", "Uppgiftslista"),
                        titleActionTitle: isEditingLocked ? nil : language.text("Add task", "Lägg till uppgift"),
                        titleAction: {
                            CentralTaskListSection.addTask(store: store, linkKind: .conferenceContribution, targetID: draft.id)
                        }
                    ) {
                        CentralTaskListSection(
                            store: store,
                            linkKind: .conferenceContribution,
                            targetID: draft.id,
                            language: language,
                            reminderOptions: ProjectTaskReminder.allCases,
                            isReadOnly: isEditingLocked,
                            showsAddButton: false
                        )
                    }
                }
            }
            .padding(14)
        }
        .background(AppPalette.detailPanelSurface)
        .flushPendingAutosaveOnTextEnd(requestImmediateAutosave)
        .onDisappear {
            autosaveTask?.cancel()
            forcedPersistTask?.cancel()
            persistAutosaveIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                requestImmediateAutosave()
            }
        }
        .onChange(of: taskRows) { _, newValue in
            let normalized = Self.normalizedTasks(newValue)
            if newValue != normalized {
                taskRows = normalized
                return
            }
            let filtered = normalized.filter { !$0.isEmpty }
            if draft.tasks != filtered {
                draft.tasks = filtered
                scheduleAutosave()
            }
        }
        .onChange(of: contribution) { oldValue, newValue in
            if oldValue.id != newValue.id {
                autosaveTask?.cancel()
                forcedPersistTask?.cancel()
                persistAutosaveIfNeeded(baseline: oldValue)
            }
            autosaveTask?.cancel()
            contributorIdentity.reconcileExternal(newValue.contributorNames)
            draft = newValue
            taskRows = Self.normalizedTasks(newValue.tasks)
            clearContributorEditingState()
        }
        .onChange(of: draft.contributorNames) { _, _ in
            scheduleAutosave()
        }
    }

    @ViewBuilder
    private var editableContributorsContent: some View {
        ForEach(contributorIdentity.rows(for: draft.contributorNames)) { row in
            let index = row.index
            let name = draft.contributorNames[index]
            HStack(spacing: 8) {
                ReorderHandle(itemID: row.id, draggedItemID: $draggedContributorName, language: language)
                contributorNameField(at: index)
                Toggle(
                    language.text("Presenter", "Presenterar"),
                    isOn: presenterBinding(for: index)
                )
                .appCheckboxStyle()
                .fixedSize()
                contributorLinkButton(for: name, width: contributorLinkColumnWidth)
                AppInlineDeleteButton(
                    title: language.text("Delete contributor", "Ta bort medverkande"),
                    width: contributorTrashColumnWidth
                ) {
                    removeContributor(at: index)
                }
            }
            .frame(minHeight: AutocompleteSelectionMetrics.fieldMinHeight, alignment: .center)
            .onDrop(of: [UTType.plainText], delegate: StableStringReorderDropDelegate(
                targetID: row.id,
                items: $draft.contributorNames,
                identity: contributorIdentity,
                draggedItemID: $draggedContributorName,
                onReorder: {
                    clearContributorEditingState()
                    scheduleAutosave()
                }
            ))
        }
    }

    @ViewBuilder
    private var lockedContributorsContent: some View {
        ForEach(Array(draft.contributorNames.indices), id: \.self) { index in
            let name = draft.contributorNames[index]
            HStack(spacing: 8) {
                AppLockedInlineValueText(text: lockedContributorDisplayName(for: name))
                    .frame(width: contributorNameFieldWidth, alignment: .leading)

                contributorLinkButton(for: name, width: contributorLinkColumnWidth)
            }
            .frame(minHeight: isEditingLocked ? 22 : AutocompleteSelectionMetrics.fieldMinHeight, alignment: .center)
        }
    }

    @ViewBuilder
    private var addContributorRow: some View {
        HStack(spacing: 8) {
            Color.clear
                .frame(width: 20, height: 20)
            AutocompleteSelectionField(
                text: $pendingContributorName,
                options: authorOptions,
                placeholder: language.text("Add contributor", "Lägg till medverkande"),
                onCommit: addPendingContributor,
                onSelect: { selectedName in
                    pendingContributorName = selectedName
                    addPendingContributor()
                },
                showsSuggestionsWithoutQuery: true
            )
            .frame(width: contributorNameFieldWidth, alignment: .leading)
            Color.clear.frame(width: contributorLinkColumnWidth, height: 20)
            Color.clear.frame(width: contributorTrashColumnWidth, height: 20)
        }
    }

    @ViewBuilder
    private func contributorNameField(at index: Int) -> some View {
        AutocompleteSelectionField(
            text: contributorBinding(at: index),
            options: authorOptions,
            excludedOptions: Set(draft.contributorNames.enumerated().compactMap { offset, name in
                offset == index ? nil : name
            }),
            placeholder: language.text("Contributor", "Medverkande"),
            onCommit: {
                scheduleAutosave()
            },
            showsSuggestionsWithoutQuery: true
        )
        .frame(width: contributorNameFieldWidth, alignment: .leading)
    }

    @ViewBuilder
    private func contributorLinkButton(for name: String, width: CGFloat) -> some View {
        if let author = store.publicationAuthor(matchingPresentedName: name) {
            AppRouteLinkButton(
                title: language.text("Open researcher", "Öppna forskare"),
                language: language,
                width: width
            ) {
                store.openRoute(for: author)
            }
        } else {
            Color.clear.frame(width: width, height: 20)
        }
    }

    private func shouldShowPublicationField(_ value: String?) -> Bool {
        AppLockedFieldVisibility.shouldShow(isLocked: isEditingLocked, value: value)
    }

    @ViewBuilder
    private var contributionPDFControls: some View {
        AppPDFAttachmentControl(
            language: language,
            filename: contributionPDFFilename,
            displayLabel: AttachmentLabels.conferenceContribution(draft, language: language),
            placeholder: language.text("No PDF selected", "Ingen PDF vald"),
            hasAttachment: hasContributionPDFAttachment,
            isAvailable: resolvedContributionPDFURL != nil,
            isEditingLocked: isEditingLocked,
            chooseAction: chooseContributionPDF,
            openAction: openContributionPDF,
            removeAction: {
                draft.pdfFilename = nil
                draft.pdfPath = nil
                scheduleAutosave()
            }
        )
    }

    private func lockedContributorDisplayName(for name: String) -> String {
        guard Self.sameContributorText(draft.presentedBy, name) else { return name }
        return "\(name) (\(language.text("presenter", "presenterar")))"
    }

    @ViewBuilder
    private func publicationJournalField() -> some View {
        if isEditingLocked {
            HStack(spacing: 8) {
                AppLockedFieldValueText(text: resolvedPublicationJournalName)
                if let journal = selectedJournal {
                    AppDestinationActionButton(
                        kind: .app,
                        language: language,
                        title: language.text("Open journal", "Öppna tidskrift"),
                        fontSize: 12
                    ) {
                        store.openRoute(for: journal)
                    }
                }
            }
        } else {
            HStack(spacing: 8) {
                AutocompleteSelectionField(
                    text: journalBinding,
                    options: journalOptions,
                    placeholder: language.text("Journal", "Tidskrift"),
                    onCommit: {}
                )
                if let journal = selectedJournal {
                    AppDestinationActionButton(
                        kind: .app,
                        language: language,
                        title: language.text("Open journal", "Öppna tidskrift"),
                        fontSize: 12
                    ) {
                        store.openRoute(for: journal)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func publicationValueField(
        placeholder: String,
        value: String,
        text: Binding<String>
    ) -> some View {
        if isEditingLocked {
            AppLockedFieldValueText(text: value)
        } else {
            TextField(placeholder, text: text)
                .appTextInputChrome()
        }
    }

    private func binding(_ keyPath: WritableKeyPath<CVConferenceContribution, String>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { newValue in
                draft[keyPath: keyPath] = newValue
                scheduleAutosave()
            }
        )
    }

    private var localizedTitleBinding: Binding<String> {
        Binding(
            get: { language == .swedish ? draft.titleSv : draft.titleEn },
            set: {
                draft.setLocalizedTitle($0, language: language)
                scheduleAutosave()
            }
        )
    }

    private var localizedPublicationDataBinding: Binding<String> {
        Binding(
            get: { language == .swedish ? draft.commentsSv : draft.commentsEn },
            set: {
                draft.setLocalizedComments($0, language: language)
                scheduleAutosave()
            }
        )
    }

    private var localizedCommentsBinding: Binding<String> {
        localizedPublicationDataBinding
    }

    private var congressSelectionBinding: Binding<String> {
        Binding(
            get: {
                selectedCongress?.selectionID ?? ""
            },
            set: { newValue in
                let match = congressOptions.first(where: { $0.selectionID == newValue })
                applyCongressSelection(match)
                scheduleAutosave()
            }
        )
    }

    private var submissionOutcomeBinding: Binding<String> {
        Binding(
            get: { draft.submissionOutcome?.rawValue ?? "" },
            set: { newValue in
                draft.submissionOutcome = CVConferenceSubmissionOutcome(rawValue: newValue)
                scheduleAutosave()
            }
        )
    }

    private var projectBinding: Binding<String> {
        Binding(
            get: { language == .swedish ? draft.projectNameSv : draft.projectNameEn },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if let match = store.projects.first(where: {
                    store.projectLabel(for: $0.nameSv, language: language) == trimmed || $0.nameSv == trimmed || $0.nameEn == trimmed
                }) {
                    draft.projectID = match.id
                    draft.projectNameSv = match.nameSv
                    draft.projectNameEn = match.nameEn.nonEmpty ?? match.nameSv
                } else {
                    draft.projectID = nil
                    draft.setLocalizedProjectName(trimmed, language: language)
                }
                scheduleAutosave()
            }
        )
    }

    private var journalBinding: Binding<String> {
        Binding(
            get: { draft.journalName },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if let match = store.publicationJournal(named: trimmed) {
                    draft.journalID = match.id
                    draft.journalName = match.name
                } else {
                    draft.journalID = nil
                    draft.journalName = trimmed
                }
                scheduleAutosave()
            }
        )
    }

    private func scheduleAutosave() {
        let snapshot = currentSnapshot()
        AutosaveCoordinator.schedule(&autosaveTask, after: 0.5) {
            store.autosaveCVConferenceContribution(snapshot)
        }
    }

    private func isEditingContributor(_ name: String) -> Bool {
        guard let editingContributorOriginalName else { return false }
        return Self.sameContributorText(editingContributorOriginalName, name)
    }

    private func startEditingContributor(_ name: String) {
        editingContributorOriginalName = name
        editingContributorText = name
    }

    private func commitContributorEdit(replacing originalName: String) {
        let trimmed = editingContributorText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            removeContributor(named: originalName)
            clearContributorEditingState()
            return
        }
        let resolved = store.publicationAuthor(matchingPresentedName: trimmed)?.displayName ?? trimmed
        guard let index = draft.contributorNames.firstIndex(where: { Self.sameContributorText($0, originalName) }) else {
            clearContributorEditingState()
            return
        }
        let alreadyExists = draft.contributorNames.enumerated().contains { offset, name in
            offset != index && Self.sameContributorText(name, resolved)
        }
        if alreadyExists {
            contributorIdentity.remove(at: index)
            draft.contributorNames.remove(at: index)
        } else {
            contributorIdentity.updateValue(at: index, to: resolved)
            draft.contributorNames[index] = resolved
        }
        if draft.presentedBy == originalName {
            draft.presentedBy = alreadyExists ? "" : resolved
        }
        clearContributorEditingState()
        scheduleAutosave()
    }

    private func removeContributor(named name: String) {
        guard let index = draft.contributorNames.firstIndex(where: { Self.sameContributorText($0, name) }) else {
            return
        }
        removeContributor(at: index)
    }

    private func removeContributor(at index: Int) {
        guard draft.contributorNames.indices.contains(index) else { return }
        contributorIdentity.remove(at: index)
        let name = draft.contributorNames.remove(at: index)
        if Self.sameContributorText(draft.presentedBy, name),
           !draft.contributorNames.contains(where: { Self.sameContributorText($0, name) }) {
            draft.presentedBy = ""
        }
        clearContributorEditingState()
        scheduleAutosave()
    }

    private func clearContributorEditingState() {
        editingContributorOriginalName = nil
        editingContributorText = ""
    }

    private static func sameContributorText(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        == rhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func presenterBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: {
                guard draft.contributorNames.indices.contains(index) else { return false }
                return draft.presentedBy == draft.contributorNames[index]
            },
            set: { isOn in
                guard draft.contributorNames.indices.contains(index) else { return }
                draft.presentedBy = isOn ? draft.contributorNames[index] : (draft.presentedBy == draft.contributorNames[index] ? "" : draft.presentedBy)
                scheduleAutosave()
            }
        )
    }

    private func applyCongressSelection(_ selection: ConferenceCongressSelection?) {
        draft.congressOrganizationID = selection?.associationID
        draft.congressID = selection?.congress.id
        draft.congressLink = selection?.congress.link ?? ""
        draft.from = selection?.congress.from ?? ""
        draft.to = selection?.congress.to ?? ""
        if let congress = selection?.congress {
            let preferredSubmissionDeadline = congress.lateAbstractSubmissionDeadline.nonEmpty ?? congress.abstractSubmissionDeadline
            if draft.submissionClosesOn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.submissionClosesOn = preferredSubmissionDeadline
            }
        } else if draft.submissionClosesOn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.submissionClosesOn = ""
        }
        draft.meetingCity = selection?.congress.city ?? ""
        draft.meetingCountry = selection?.congress.country ?? ""
        let title = selection?.congress.title ?? ""
        draft.meetingSv = title
        draft.meetingEn = title
    }

    private func localizedAssociationName(_ option: OrganizationRecord) -> String {
        language == .swedish ? option.nameSv : (option.nameEn.nonEmpty ?? option.nameSv)
    }

    private func openSelectedCongressOrganization(_ option: OrganizationRecord) {
        let resolvedOrganization =
            store.organization(id: option.id) ??
            store.organizations.first(where: { $0.nameSv == option.nameSv }) ??
            option

        store.route = AppRoute(
            recordID: resolvedOrganization.id,
            destination: .organizations
        )
    }

    private func localizedCountryDisplayName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return language.localizedCountry(trimmed)
    }

    private func addPendingContributor() {
        let trimmed = pendingContributorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let resolved = store.publicationAuthor(matchingPresentedName: trimmed)?.displayName ?? trimmed
        if !draft.contributorNames.contains(where: { Self.sameContributorText($0, resolved) }) {
            contributorIdentity.append(value: resolved)
            draft.contributorNames.append(resolved)
            scheduleAutosave()
        }
        pendingContributorName = ""
    }

    private func contributorBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard draft.contributorNames.indices.contains(index) else { return "" }
                return draft.contributorNames[index]
            },
            set: { newValue in
                guard draft.contributorNames.indices.contains(index) else { return }
                let previousValue = draft.contributorNames[index]
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    contributorIdentity.remove(at: index)
                    draft.contributorNames.remove(at: index)
                    if Self.sameContributorText(draft.presentedBy, previousValue) {
                        draft.presentedBy = ""
                    }
                } else {
                    let resolved = store.publicationAuthor(matchingPresentedName: trimmed)?.displayName ?? trimmed
                    let alreadyExists = draft.contributorNames.enumerated().contains { offset, name in
                        offset != index && Self.sameContributorText(name, resolved)
                    }
                    if alreadyExists {
                        contributorIdentity.remove(at: index)
                        draft.contributorNames.remove(at: index)
                    } else {
                        contributorIdentity.updateValue(at: index, to: resolved)
                        draft.contributorNames[index] = resolved
                    }
                    if Self.sameContributorText(draft.presentedBy, previousValue) {
                        draft.presentedBy = alreadyExists ? "" : resolved
                    }
                }
            }
        )
    }

    private func uniquedContributorNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.compactMap(\.trimmedOrNil).filter { name in
            let normalized = name
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !normalized.isEmpty else { return false }
            return seen.insert(normalized).inserted
        }
    }

    private static func normalizedTasks(_ tasks: [PublicationTaskItem]) -> [PublicationTaskItem] {
        normalizedPublicationTaskItems(tasks)
    }

    private func currentSnapshot() -> CVConferenceContribution {
        var snapshot = draft
        snapshot.tasks = taskRows.filter { !$0.isEmpty }
        return snapshot
    }

    private func persistAutosaveIfNeeded(baseline: CVConferenceContribution? = nil) {
        autosaveTask?.cancel()
        let snapshot = currentSnapshot()
        let current = baseline ?? contribution
        guard snapshot != current else { return }
        store.autosaveCVConferenceContribution(snapshot)
    }

    private func requestImmediateAutosave() {
        AutosaveCoordinator.requestImmediate(&forcedPersistTask, after: 0.05) {
            persistAutosaveIfNeeded()
        }
    }

    private var resolvedContributionPDFURL: URL? {
        GrantDataStore.resolveCVConferenceContributionPDFURL(
            contributionID: draft.id,
            pdfPath: draft.pdfPath,
            pdfFilename: draft.pdfFilename
        )
    }

    private var contributionPDFFilename: String? {
        draft.pdfFilename?.trimmedOrNil ?? draft.pdfPath?.trimmedOrNil.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    private var hasContributionPDFAttachment: Bool {
        draft.pdfFilename?.trimmedOrNil != nil || draft.pdfPath?.trimmedOrNil != nil
    }

    private func chooseContributionPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = language.text("Choose PDF", "Välj PDF")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try loadPDFDataForUserAction(from: url)
            let managedURL = try GrantDataStore.persistManagedCVConferenceContributionPDF(
                data: data,
                forContributionID: draft.id
            )
            draft.pdfFilename = url.lastPathComponent
            draft.pdfPath = GrantDataStore.portableAttachmentPath(for: managedURL)
            scheduleAutosave()
        } catch {
            store.reportFileActionFailure(
                language.text("Could not attach the conference contribution PDF.", "Kunde inte bifoga PDF-filen till konferensbidraget."),
                error: error
            )
        }
    }

    private func openContributionPDF() {
        guard let resolvedContributionPDFURL else {
            store.reportFileActionFailure(
                language.text("Could not open the conference contribution PDF.", "Kunde inte öppna PDF-filen för konferensbidraget."),
                error: CocoaError(.fileNoSuchFile)
            )
            return
        }
        store.openFileForUserAction(
            resolvedContributionPDFURL,
            failureMessage: language.text("Could not open the conference contribution PDF.", "Kunde inte öppna PDF-filen för konferensbidraget.")
        )
    }
}

private struct ConferenceCongressSelection: Identifiable, Hashable {
    let associationID: String
    let associationName: String
    let congress: OrganizationCongress

    var id: String { selectionID }
    var selectionID: String { "\(associationID)|\(congress.id)" }
    var menuLabel: String { "\(congress.title) · \(associationName)" }
}


private enum ConferenceSubmissionStep: Int, CaseIterable {
    case applied
    case closes
    case decision
    case decisionExpected

    var index: Int { rawValue }

    func title(language: AppLanguage, usesAbstractTerminology: Bool = false) -> String {
        switch self {
        case .applied:
            if usesAbstractTerminology {
                return language.text("Submitted", "Inskickad")
            }
            return language.text("Applied", "Ansökt")
        case .closes:
            if usesAbstractTerminology {
                return language.text("Submission deadline", "Deadline för inskick")
            }
            return language.text("Closes", "Stänger")
        case .decision:
            if usesAbstractTerminology {
                return language.text("Accepted / rejected", "Accepterat / refuserat")
            }
            return language.text("Accepted / rejected", "Antaget / refuserat")
        case .decisionExpected:
            return language.text("Decision expected", "Beslut väntas")
        }
    }

    var validationFieldKey: String {
        switch self {
        case .applied:
            return ConferenceContributionDateValidationFieldKey.submissionAppliedOn
        case .closes:
            return ConferenceContributionDateValidationFieldKey.submissionClosesOn
        case .decision:
            return ConferenceContributionDateValidationFieldKey.submissionDecisionOn
        case .decisionExpected:
            return ConferenceContributionDateValidationFieldKey.submissionDecisionExpectedOn
        }
    }
}

private struct ConferenceSubmissionTimelineStepper: View {
    @Binding var contribution: CVConferenceContribution
    let language: AppLanguage
    var usesAbstractTerminology = false
    var isReadOnly = false
    let onMutate: () -> Void

    private let horizontalInset: CGFloat = 62
    // Round 17: circles about 17 % larger (24 → 28) with thinner edges.
    private let circleSize: CGFloat = 28
    private let timelineHeight: CGFloat = 160
    private let markerCenterY: CGFloat = 20
    private let inactiveGray = AppTimelineStrip<ConferenceSubmissionStep, EmptyView>.inactiveGray
    private let futureGray = AppTimelineStrip<ConferenceSubmissionStep, EmptyView>.futureGray

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var illogicalDateFieldKeys: Set<String> {
        illogicalConferenceContributionDateFieldKeys(for: contribution)
    }

    var body: some View {
        GeometryReader { geometry in
            let centers = circleCenters(width: geometry.size.width)

            ZStack(alignment: .topLeading) {
                ForEach(0..<(allSteps.count - 1), id: \.self) { index in
                    segmentView(index: index, centers: centers)
                }

                ForEach(allSteps, id: \.self) { step in
                    stepView(step, centerX: centers[step.index], width: stepWidth)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: timelineHeight)
    }

    private var allSteps: [ConferenceSubmissionStep] {
        ConferenceSubmissionStep.allCases
    }

    private var stepWidth: CGFloat {
        140
    }

    private func circleCenters(width: CGFloat) -> [CGFloat] {
        let leadingInset = max(horizontalInset, stepWidth / 2)
        let trailingInset = max(horizontalInset, stepWidth / 2)
        let usableWidth = max(width - leadingInset - trailingInset, 1)
        let lastIndex = max(allSteps.count - 1, 1)
        return allSteps.map { step in
            leadingInset + (usableWidth * CGFloat(step.index) / CGFloat(lastIndex))
        }
    }

    @ViewBuilder
    private func segmentView(index: Int, centers: [CGFloat]) -> some View {
        let startX = centers[index]
        let endX = centers[index + 1]
        let leftStep = allSteps[index]
        let rightStep = allSteps[index + 1]
        let hasDefinedDate = stepHasDefinedDate(leftStep) || stepHasDefinedDate(rightStep)

        if hasDefinedDate {
            timelineGradientLine(
                startX: startX,
                endX: endX,
                lineWidth: 2,
                colors: [segmentEndpointColor(for: leftStep), segmentEndpointColor(for: rightStep)]
            )
        } else {
            Path { path in
                path.move(to: CGPoint(x: startX, y: markerCenterY))
                path.addLine(to: CGPoint(x: endX, y: markerCenterY))
            }
            .stroke(
                inactiveGray,
                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [7, 5])
            )
        }
    }

    private func timelineGradientLine(
        startX: CGFloat,
        endX: CGFloat,
        lineWidth: CGFloat,
        colors: [Color]
    ) -> some View {
        let width = max(endX - startX, 1)
        return Capsule(style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            .frame(width: width, height: lineWidth)
            .position(x: startX + (width / 2), y: markerCenterY)
    }

    private func segmentEndpointColor(for step: ConferenceSubmissionStep) -> Color {
        if isStepDeemphasized(step) {
            return inactiveGray
        }
        if isStepCompleted(step) {
            return completedStrokeColor(for: step)
        }
        if stepHasDefinedDate(step) {
            return futureGray
        }
        return inactiveGray
    }

    @ViewBuilder
    private func stepView(_ step: ConferenceSubmissionStep, centerX: CGFloat, width: CGFloat) -> some View {
        Group {
            if isReadOnly {
                stepContent(step, width: width)
            } else {
                stepContent(step, width: width)
                    .contextMenu {
                        stepContextMenu(for: step)
                    }
            }
        }
        .position(x: centerX, y: timelineHeight / 2)
    }

    private func stepContent(_ step: ConferenceSubmissionStep, width: CGFloat) -> some View {
        VStack(spacing: 9) {
            markerView(for: step)
            labelBlock(for: step)
        }
        .padding(.top, markerCenterY - (circleSize / 2))
        .frame(width: width, height: timelineHeight, alignment: .top)
    }

    private func markerView(for step: ConferenceSubmissionStep) -> some View {
        let completed = isStepCompleted(step)
        let deemphasized = isStepDeemphasized(step)
        let fillColor = deemphasized ? AppPalette.fieldSurface : completedFillColor(for: step)
        let strokeColor = deemphasized ? inactiveGray : completedStrokeColor(for: step)
        return ZStack {
            Circle()
                .fill(completed ? fillColor : AppPalette.fieldSurface)
            Circle()
                .stroke(completed || deemphasized ? strokeColor : (stepHasDefinedDate(step) ? futureGray : inactiveGray), lineWidth: completed ? 1.6 : 1.5)

            if completed && !deemphasized {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(submissionStepTone(for: step) == nil ? strokeColor : AppPalette.statusOnFill)
            }
        }
        .frame(width: circleSize, height: circleSize)
    }

    @ViewBuilder
    private func labelBlock(for step: ConferenceSubmissionStep) -> some View {
        if isReadOnly {
            readOnlyLabelBlock(for: step)
        } else if step == .decision {
            decisionBlock
        } else {
            let deemphasized = isStepDeemphasized(step)
            VStack(spacing: 5) {
                AppTimelineStepText(
                    text: step.title(language: language, usesAbstractTerminology: usesAbstractTerminology),
                    foreground: deemphasized ? .secondary : AppPalette.appText
                )

                ConferenceTimelineDateEditor(
                    text: dateBinding(for: step),
                    isIllogical: illogicalDateFieldKeys.contains(step.validationFieldKey),
                    language: language,
                    onMutate: onMutate
                )
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func readOnlyLabelBlock(for step: ConferenceSubmissionStep) -> some View {
        let value = readOnlyValue(for: step)
        let deemphasized = isStepDeemphasized(step)
        return VStack(spacing: 5) {
            AppTimelineStepText(
                text: readOnlyTitle(for: step),
                lineLimit: 2,
                foreground: deemphasized ? .secondary : AppPalette.appText
            )

            Text(value ?? "-")
                .appTypography(.secondary)
                .foregroundStyle(value == nil || deemphasized ? .secondary : AppPalette.appText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var decisionBlock: some View {
        VStack(spacing: 6) {
            if let outcome = contribution.submissionOutcome {
                AppTimelineStepText(text: submissionOutcomeTitle(outcome), lineLimit: 2)
                ConferenceTimelineDateEditor(
                    text: Binding(
                        get: { contribution.submissionDecisionOn },
                        set: {
                            contribution.submissionDecisionOn = DateParsers.canonicalizedDayInput($0)
                            onMutate()
                        }
                    ),
                    isIllogical: illogicalDateFieldKeys.contains(ConferenceContributionDateValidationFieldKey.submissionDecisionOn),
                    language: language,
                    onMutate: onMutate
                )
            } else {
                HStack(spacing: 8) {
                    Button(acceptedSubmissionTitle) {
                        contribution.submissionOutcome = .granted
                        onMutate()
                    }
                    .buttonStyle(.plain)
                    .appTypography(.tableHeader)
                    .foregroundStyle(.primary)

                    Text("/")
                        .foregroundStyle(.secondary)

                    Button(rejectedSubmissionTitle) {
                        contribution.submissionOutcome = .declined
                        onMutate()
                    }
                    .buttonStyle(.plain)
                    .appTypography(.tableHeader)
                    .foregroundStyle(.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func stepContextMenu(for step: ConferenceSubmissionStep) -> some View {
        Button(language.text("Today", "Idag")) {
            dateBinding(for: step).wrappedValue = DateParsers.isoDay.string(from: today)
            onMutate()
        }

        if step == .decision {
            Divider()

            Button(acceptedSubmissionTitle) {
                contribution.submissionOutcome = .granted
                onMutate()
            }

            Button(rejectedSubmissionTitle) {
                contribution.submissionOutcome = .declined
                onMutate()
            }

            if contribution.submissionOutcome != nil {
                Divider()
                Button(language.text("Clear decision", "Rensa beslut"), role: .destructive) {
                    contribution.submissionOutcome = nil
                    contribution.submissionDecisionOn = ""
                    onMutate()
                }
            }
        }
    }

    private func dateBinding(for step: ConferenceSubmissionStep) -> Binding<String> {
        switch step {
        case .applied:
            return Binding(
                get: { contribution.submissionAppliedOn },
                set: {
                    contribution.submissionAppliedOn = DateParsers.canonicalizedDayInput($0)
                    onMutate()
                }
            )
        case .closes:
            return Binding(
                get: { contribution.submissionClosesOn },
                set: {
                    contribution.submissionClosesOn = DateParsers.canonicalizedDayInput($0)
                    onMutate()
                }
            )
        case .decision:
            return Binding(
                get: { contribution.submissionDecisionOn },
                set: {
                    contribution.submissionDecisionOn = DateParsers.canonicalizedDayInput($0)
                    onMutate()
                }
            )
        case .decisionExpected:
            return Binding(
                get: { contribution.submissionDecisionExpectedOn },
                set: {
                    contribution.submissionDecisionExpectedOn = DateParsers.canonicalizedDayInput($0)
                    onMutate()
                }
            )
        }
    }

    private func readOnlyTitle(for step: ConferenceSubmissionStep) -> String {
        guard step == .decision, let outcome = contribution.submissionOutcome else {
            return step.title(language: language, usesAbstractTerminology: usesAbstractTerminology)
        }
        return submissionOutcomeTitle(outcome)
    }

    private func readOnlyValue(for step: ConferenceSubmissionStep) -> String? {
        switch step {
        case .applied:
            return contribution.submissionAppliedOn.trimmedOrNil
        case .closes:
            return contribution.submissionClosesOn.trimmedOrNil
        case .decision:
            return contribution.submissionDecisionOn.trimmedOrNil
                ?? contribution.submissionOutcome.map(submissionOutcomeTitle)
        case .decisionExpected:
            return contribution.submissionDecisionExpectedOn.trimmedOrNil
        }
    }

    private var acceptedSubmissionTitle: String {
        usesAbstractTerminology ? language.text("Accepted", "Accepterat") : language.text("Accepted", "Accepterad")
    }

    private var rejectedSubmissionTitle: String {
        usesAbstractTerminology ? language.text("Rejected", "Refuserat") : language.text("Rejected", "Refuserad")
    }

    private func submissionOutcomeTitle(_ outcome: CVConferenceSubmissionOutcome) -> String {
        switch outcome {
        case .granted:
            return acceptedSubmissionTitle
        case .declined:
            return rejectedSubmissionTitle
        }
    }

    /// Round 16: status tones instead of blue. Steps before the decision are
    /// "in progress" (yellow); the decision takes the contribution's tone
    /// (accepted yellow, presented green, rejected red). nil = grey.
    private func submissionStepTone(for step: ConferenceSubmissionStep) -> AppStatusTone? {
        let overall = AppStatusTones.conferenceContribution(AppConferenceContributionBadgeStatus(contribution: contribution))
        switch step {
        case .decision:
            return contribution.submissionOutcome == nil ? nil : overall
        case .decisionExpected, .applied, .closes:
            if contribution.submissionOutcome == .declined { return .inactive }
            return contribution.submissionOutcome == nil ? .pending : overall
        }
    }

    private func completedFillColor(for step: ConferenceSubmissionStep) -> Color {
        submissionStepTone(for: step).map(AppPalette.statusFill) ?? inactiveGray
    }

    private func completedStrokeColor(for step: ConferenceSubmissionStep) -> Color {
        submissionStepTone(for: step).map(AppPalette.statusEdge) ?? inactiveGray
    }

    private func isStepCompleted(_ step: ConferenceSubmissionStep) -> Bool {
        switch step {
        case .applied:
            return dateHasPassed(contribution.submissionAppliedOn)
        case .closes:
            return dateHasPassed(contribution.submissionClosesOn)
        case .decision:
            return contribution.submissionOutcome != nil
        case .decisionExpected:
            return false
        }
    }

    private func isStepDeemphasized(_ step: ConferenceSubmissionStep) -> Bool {
        step == .decisionExpected && contribution.submissionOutcome != nil
    }

    private func stepHasDefinedDate(_ step: ConferenceSubmissionStep) -> Bool {
        if isStepDeemphasized(step) {
            return false
        }
        switch step {
        case .applied:
            return contribution.submissionAppliedOn.nonEmpty != nil
        case .closes:
            return contribution.submissionClosesOn.nonEmpty != nil
        case .decision:
            return contribution.submissionDecisionOn.nonEmpty != nil || contribution.submissionOutcome != nil
        case .decisionExpected:
            return contribution.submissionDecisionExpectedOn.nonEmpty != nil
        }
    }

    private func dateHasPassed(_ value: String) -> Bool {
        guard let date = DateParsers.isoDay.date(from: value) else { return false }
        return Calendar.current.startOfDay(for: date) <= today
    }
}

private struct ConferenceTimelineDateEditor: View {
    @Binding var text: String
    var isIllogical: Bool = false
    let language: AppLanguage
    let onMutate: () -> Void

    private var todayString: String {
        DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date()))
    }

    var body: some View {
        VStack(spacing: 5) {
            CVDateField(text: Binding(
                get: { text },
                set: {
                    text = DateParsers.canonicalizedDayInput($0)
                    onMutate()
                }
            ), textAlignment: .center, isIllogical: isIllogical)
            .frame(width: 118)
            .help(isIllogical ? language.text("Illogical date combination", "Ologisk datumkombination") : "")

            AppTodayDateButton(title: language.text("Today", "Idag"), fill: AppPalette.fieldSurface) {
                text = todayString
                onMutate()
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}



private struct CVMediaAppearanceDetailView: View {
    @ObservedObject var store: GrantDataStore
    let appearance: CVMediaAppearance
    @Environment(\.scenePhase) private var scenePhase

    @State private var draft: CVMediaAppearance
    @State private var autosaveTask: DispatchWorkItem?
    @State private var forcedPersistTask: DispatchWorkItem?
    @State private var languageInput = ""
    @State private var projectAssociationInput = ""
    @State private var publicationAssociationInput = ""
    @State private var applicationAssociationInput = ""
    @State private var authorAssociationInput = ""
    @State private var mediaAuthorEditingTextByID: [String: String] = [:]
    @State private var draggedMediaAuthorID: String?
    @State private var showsPDFPreview = false
    @State private var countryText = ""

    init(store: GrantDataStore, appearance: CVMediaAppearance) {
        self.store = store
        self.appearance = appearance
        _draft = State(initialValue: appearance)
    }

    private var language: AppLanguage { store.language }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    if isEditingLocked {
                        Text(localizedTitle)
                            .appTypography(.pageTitle)
                            .lineLimit(2)
                    } else {
                        TextField(
                            language.text("Title", "Titel"),
                            text: localizedTitleBinding,
                            axis: .vertical
                        )
                        .appTypography(.pageTitle)
                        .lineLimit(2, reservesSpace: false)
                        .textFieldStyle(.plain)
                    }

                    Text(language.text("Media appearance", "Medverkan i media"))
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)

                    AppEditorLockButton(isLocked: draft.isEditingLocked, language: language) {
                        if !draft.isEditingLocked {
                            NSApp.keyWindow?.makeFirstResponder(nil)
                        }
                        draft.isEditingLocked.toggle()
                        requestImmediateAutosave()
                    }
                }

                CVPanel(title: language.text("Details", "Detaljer")) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 16) {
                            CVLabeledField(title: language.text("Completion date", "Genomförandedatum")) {
                                HStack(spacing: 8) {
                                    if isEditingLocked {
                                        AppLockedFieldValueText(text: draft.date)
                                    } else {
                                        CVDateField(text: binding(\.date))
                                    }

                                    AppDestinationActionButton(
                                        kind: .app,
                                        language: language,
                                        title: language.text("Show in calendar", "Visa i kalendern"),
                                        fontSize: 12
                                    ) {
                                        openDateInCalendar()
                                    }
                                    .disabled(mediaCalendarDate == nil)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            CVLabeledField(title: language.text("Start time", "Starttid")) {
                                if isEditingLocked {
                                    AppLockedFieldValueText(text: draft.startTime)
                                } else {
                                    CalendarTimeInputField(
                                        placeholder: "HH:MM",
                                        text: binding(\.startTime)
                                    )
                                }
                            }
                            .frame(width: 130, alignment: .leading)

                            CVLabeledField(title: language.text("End time", "Sluttid")) {
                                if isEditingLocked {
                                    AppLockedFieldValueText(text: draft.endTime)
                                } else {
                                    CalendarTimeInputField(
                                        placeholder: "HH:MM",
                                        text: binding(\.endTime)
                                    )
                                }
                            }
                            .frame(width: 130, alignment: .leading)
                        }
                        HStack(alignment: .top, spacing: 16) {
                            CVLabeledField(title: language.text("Format", "Genomförande")) {
                                if isEditingLocked {
                                    AppLockedFieldValueText(text: mediaMeetingModeLabel)
                                } else {
                                    AppMenuSelectionField(
                                        selection: binding(\.meetingMode),
                                        options: CalendarMeetingMode.allCases.map {
                                            ($0.localizedName(language: language), $0.rawValue)
                                        },
                                        placeholder: language.text("Choose format", "Välj genomförande"),
                                        clearValue: ""
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if draft.meetingMode != CalendarMeetingMode.online.rawValue {
                                CVLabeledField(title: language.text("Place", "Plats")) {
                                    if isEditingLocked {
                                        AppLockedFieldValueText(text: draft.place)
                                    } else {
                                        TextField(language.text("Place", "Plats"), text: binding(\.place))
                                            .appTextInputChrome()
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                CVLabeledField(title: language.text("Country", "Land")) {
                                    if isEditingLocked {
                                        AppLockedFieldValueText(text: localizedMediaCountryName(draft.country))
                                    } else {
                                        mediaCountryAutocompleteField
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        CVLabeledField(title: language.text("Publication date", "Publiceringsdatum")) {
                            if isEditingLocked {
                                AppLockedFieldValueText(text: draft.publicationDate)
                            } else {
                                CVDateField(text: binding(\.publicationDate))
                            }
                        }
                        CVLabeledField(title: language.text("Language", "Språk")) {
                            if isEditingLocked {
                                AppLockedFieldValueText(
                                    text: cvMediaLanguageListText(
                                        codes: draft.languages,
                                        options: store.mediaLanguageOptions,
                                        language: language
                                    ),
                                    lineLimit: 1
                                )
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(draft.languages.enumerated()), id: \.offset) { index, item in
                                        HStack {
                                            Text(languageName(item))
                                            Spacer()
                                            AppIconDeleteButton(
                                                title: language.text("Delete language", "Ta bort språk")
                                            ) {
                                                guard draft.languages.indices.contains(index) else { return }
                                                draft.languages.remove(at: index)
                                                scheduleAutosave()
                                            }
                                                .buttonStyle(.borderless)
                                        }
                                    }
                                    AutocompleteSelectionField(
                                        text: $languageInput,
                                        options: store.mediaLanguageOptions.map { $0.localizedName(language: language) },
                                        placeholder: language.text("Type a language", "Skriv ett språk"),
                                        onCommit: addTypedLanguage,
                                        onSelect: { _ in addTypedLanguage() },
                                        updatesTextContinuously: true
                                    )
                                }
                            }
                        }
                        mediaAssociationField(
                            title: language.text("Projects", "Projekt"),
                            keyPath: \.projectIDs,
                            options: store.projects.map { ($0.id, $0.displayName(for: language)) },
                            input: $projectAssociationInput
                        )
                        mediaAssociationField(
                            title: language.text("Publications", "Publikationer"),
                            keyPath: \.publicationIDs,
                            options: store.publicationRecords.map { ($0.id, $0.title.nonEmpty ?? $0.id) },
                            input: $publicationAssociationInput
                        )
                        mediaAssociationField(
                            title: language.text("Grants", "Anslag"),
                            keyPath: \.applicationIDs,
                            options: store.applications.map {
                                (
                                    $0.id,
                                    store.localizedGrantName(for: $0, language: language).nonEmpty
                                        ?? $0.displayTitle
                                )
                            },
                            input: $applicationAssociationInput
                        )
                        mediaResearcherAssociationField
                        CVLabeledField(title: language.text("Comment", "Kommentar")) {
                            if isEditingLocked {
                                AppLockedFieldValueText(text: draft.comment, lineLimit: nil)
                            } else {
                                AppTextEditorField(
                                    title: nil,
                                    text: binding(\.comment),
                                    placeholder: language.text("Comment", "Kommentar"),
                                    minimumHeight: 72
                                )
                            }
                        }
                        CVLabeledField(title: language.text("Link", "Länk")) {
                            HStack(spacing: 8) {
                                if isEditingLocked {
                                    AppLockedFieldValueText(text: draft.link)
                                } else {
                                    TextField(language.text("Link", "Länk"), text: binding(\.link))
                                        .appTextInputChrome()
                                }

                                AppDestinationActionButton(
                                    kind: .web,
                                    language: language,
                                    title: language.text("Open link", "Öppna länk"),
                                    fontSize: 12
                                ) { openLink() }
                                .disabled(draft.link.trimmedOrNil == nil)
                            }
                        }
                        CVLabeledField(title: "PDF") {
                            mediaPDFControls
                        }
                    }
                }
                if !isEditingLocked {
                    HStack {
                        Spacer()
                        AppDestructiveActionButton(
                            title: language.text("Delete", "Ta bort"),
                            help: language.text("Delete media appearance", "Ta bort medverkan i media"),
                            cancelTitle: language.text("Cancel", "Avbryt"),
                            confirmationTitle: language.text("Delete media appearance?", "Ta bort medverkan i media?"),
                            confirmationMessage: language.text("The deletion can be undone.", "Borttagningen kan ångras.")
                        ) {
                            store.deleteCVMediaAppearance(id: appearance.id)
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(AppPalette.detailPanelSurface)
        .flushPendingAutosaveOnTextEnd(requestImmediateAutosave)
        .onAppear {
            countryText = localizedMediaCountryName(draft.country)
        }
        .onChange(of: draft.meetingMode) { _, newValue in
            if newValue == CalendarMeetingMode.online.rawValue {
                draft.place = ""
                draft.country = ""
                countryText = ""
                scheduleAutosave()
            }
        }
        .onDisappear {
            autosaveTask?.cancel()
            forcedPersistTask?.cancel()
            persistAutosaveIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                requestImmediateAutosave()
            }
        }
        .onChange(of: appearance) { oldValue, newValue in
            // Same record changed elsewhere while typed text is unsaved: the
            // typed text is saved on top and stays on screen (it used to be
            // replaced on screen and then written back later).
            if oldValue.id == newValue.id, draft != oldValue, draft != newValue {
                persistAutosaveIfNeeded(baseline: newValue)
                return
            }
            autosaveTask?.cancel()
            forcedPersistTask?.cancel()
            if oldValue.id != newValue.id {
                persistAutosaveIfNeeded(baseline: oldValue)
            }
            draft = newValue
            projectAssociationInput = ""
            publicationAssociationInput = ""
            applicationAssociationInput = ""
            authorAssociationInput = ""
            mediaAuthorEditingTextByID = [:]
            draggedMediaAuthorID = nil
            countryText = localizedMediaCountryName(newValue.country)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<CVMediaAppearance, String>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { newValue in
                guard !isEditingLocked else { return }
                draft[keyPath: keyPath] = newValue
                scheduleAutosave()
            }
        )
    }

    private var mediaMeetingModeLabel: String {
        CalendarMeetingMode.allCases.first {
            $0.rawValue.caseInsensitiveCompare(draft.meetingMode) == .orderedSame
        }?
        .localizedName(language: language) ?? ""
    }

    private var localizedMediaCountryOptions: [String] {
        GrantParsing.countryOptions
            .map { language.localizedCountry($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func canonicalMediaCountryName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let exact = GrantParsing.countryOptions.first(where: {
            $0.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return exact
        }
        if let localized = GrantParsing.countryOptions.first(where: {
            language.localizedCountry($0).caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return localized
        }
        let heuristic = GrantParsing.canonicalCountryName(trimmed)
        return GrantParsing.countryOptions.first(where: {
            $0.caseInsensitiveCompare(heuristic) == .orderedSame
        }) ?? trimmed
    }

    private func localizedMediaCountryName(_ raw: String) -> String {
        let canonical = canonicalMediaCountryName(raw)
        guard !canonical.isEmpty else { return "" }
        return GrantParsing.countryOptions.contains(canonical)
            ? language.localizedCountry(canonical)
            : canonical
    }

    private var mediaCountryAutocompleteField: some View {
        AutocompleteSelectionField(
            text: $countryText,
            options: localizedMediaCountryOptions,
            placeholder: language.text("Country", "Land"),
            onCommit: {
                let canonical = canonicalMediaCountryName(countryText)
                binding(\.country).wrappedValue = canonical
                countryText = localizedMediaCountryName(canonical)
            },
            onSelect: { selected in
                let canonical = canonicalMediaCountryName(selected)
                binding(\.country).wrappedValue = canonical
                countryText = localizedMediaCountryName(canonical)
            },
            showsSuggestionsWithoutQuery: true
        )
    }

    @ViewBuilder
    private func mediaAssociationField(
        title: String,
        keyPath: WritableKeyPath<CVMediaAppearance, [String]>,
        options: [(id: String, label: String)],
        input: Binding<String>
    ) -> some View {
        let labelsByID = Dictionary(firstWinsKeysWithValues: options.map { ($0.id, $0.label) })
        let selectedIDs = draft[keyPath: keyPath]
        let selectedOptions = selectedIDs
            .map { (id: $0, label: labelsByID[$0] ?? $0) }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        let availableOptions = options
            .filter { !selectedIDs.contains($0.id) }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }

        CVLabeledField(title: title) {
            if isEditingLocked {
                AppLockedFieldValueText(
                    text: selectedOptions.map(\.label).joined(separator: ", "),
                    lineLimit: nil
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(selectedOptions, id: \.id) { option in
                        HStack(spacing: 8) {
                            Text(option.label)
                                .lineLimit(2)
                            Spacer()
                            Button("×") {
                                draft[keyPath: keyPath].removeAll { $0 == option.id }
                                scheduleAutosave()
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    AutocompleteSelectionField(
                        text: input,
                        options: availableOptions.map(\.label),
                        placeholder: language.text("Type to search", "Skriv för att söka"),
                        onCommit: {
                            addMediaAssociation(
                                input.wrappedValue,
                                keyPath: keyPath,
                                options: availableOptions,
                                input: input
                            )
                        },
                        onSelect: { selected in
                            input.wrappedValue = selected
                            addMediaAssociation(
                                selected,
                                keyPath: keyPath,
                                options: availableOptions,
                                input: input
                            )
                        },
                        showsSuggestionsWithoutQuery: true
                    )
                    .disabled(availableOptions.isEmpty)
                }
            }
        }
    }

    private func addMediaAssociation(
        _ selectedLabel: String,
        keyPath: WritableKeyPath<CVMediaAppearance, [String]>,
        options: [(id: String, label: String)],
        input: Binding<String>
    ) {
        guard let selected = options.first(where: {
            $0.label.compare(
                selectedLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }) else { return }
        guard !draft[keyPath: keyPath].contains(selected.id) else {
            input.wrappedValue = ""
            return
        }
        draft[keyPath: keyPath].append(selected.id)
        input.wrappedValue = ""
        scheduleAutosave()
    }

    @ViewBuilder
    private var mediaResearcherAssociationField: some View {
        let options = store.publicationAuthors.map { (id: $0.id, label: $0.displayName) }
        let labelsByID = Dictionary(firstWinsKeysWithValues: options.map { ($0.id, $0.label) })
        let selectedIDs = draft.authorIDs
        let selectedLabels = selectedIDs.map { labelsByID[$0] ?? $0 }
        let availableOptions = options
            .filter { !selectedIDs.contains($0.id) }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }

        CVLabeledField(title: language.text("Researchers", "Forskare")) {
            if isEditingLocked {
                AppLockedFieldValueText(
                    text: selectedLabels.joined(separator: ", "),
                    lineLimit: nil
                )
            } else {
                VStack(alignment: .leading, spacing: AutocompleteSelectionMetrics.rowSpacing) {
                    ForEach(Array(selectedIDs.enumerated()), id: \.element) { index, authorID in
                        HStack(spacing: 8) {
                            ReorderHandle(itemID: authorID, draggedItemID: $draggedMediaAuthorID, language: language)

                            AutocompleteSelectionField(
                                text: mediaAuthorTextBinding(
                                    authorID: authorID,
                                    fallback: labelsByID[authorID] ?? authorID
                                ),
                                options: options.map(\.label),
                                excludedOptions: Set(selectedIDs.enumerated().compactMap { offset, id in
                                    offset == index ? nil : labelsByID[id]
                                }),
                                placeholder: language.text("Researcher", "Forskare"),
                                onCommit: {
                                    commitMediaAuthorEdit(
                                        at: index,
                                        authorID: authorID,
                                        options: options
                                    )
                                },
                                onSelect: { selected in
                                    replaceMediaAuthor(
                                        at: index,
                                        authorID: authorID,
                                        with: selected,
                                        options: options
                                    )
                                },
                                showsSuggestionsWithoutQuery: true
                            )

                            if let author = store.publicationAuthor(id: authorID) {
                                AppRouteLinkButton(
                                    title: language.text("Open researcher", "Öppna forskare"),
                                    language: language,
                                    width: 34
                                ) {
                                    store.openRoute(for: author)
                                }
                            } else {
                                Color.clear.frame(width: 34, height: 20)
                            }

                            AppInlineDeleteButton(
                                title: language.text("Delete researcher", "Ta bort forskare"),
                                width: 28
                            ) {
                                draft.authorIDs.removeAll { $0 == authorID }
                                mediaAuthorEditingTextByID[authorID] = nil
                                scheduleAutosave()
                            }
                        }
                        .frame(minHeight: AutocompleteSelectionMetrics.fieldMinHeight, alignment: .center)
                        .onDrop(of: [UTType.plainText], delegate: StringReorderDropDelegate(
                            targetID: authorID,
                            items: $draft.authorIDs,
                            draggedItemID: $draggedMediaAuthorID,
                            onReorder: {
                                scheduleAutosave()
                            }
                        ))
                    }

                    HStack(spacing: 8) {
                        Color.clear.frame(width: 20, height: 20)
                        AutocompleteSelectionField(
                            text: $authorAssociationInput,
                            options: availableOptions.map(\.label),
                            placeholder: language.text("Add researcher", "Lägg till forskare"),
                            onCommit: {
                                addMediaAssociation(
                                    authorAssociationInput,
                                    keyPath: \.authorIDs,
                                    options: availableOptions,
                                    input: $authorAssociationInput
                                )
                            },
                            onSelect: { selected in
                                authorAssociationInput = selected
                                addMediaAssociation(
                                    selected,
                                    keyPath: \.authorIDs,
                                    options: availableOptions,
                                    input: $authorAssociationInput
                                )
                            },
                            showsSuggestionsWithoutQuery: true
                        )
                        .disabled(availableOptions.isEmpty)
                        Color.clear.frame(width: 34, height: 20)
                        Color.clear.frame(width: 28, height: 20)
                    }
                }
            }
        }
    }

    private func mediaAuthorTextBinding(authorID: String, fallback: String) -> Binding<String> {
        Binding(
            get: { mediaAuthorEditingTextByID[authorID] ?? fallback },
            set: { mediaAuthorEditingTextByID[authorID] = $0 }
        )
    }

    private func commitMediaAuthorEdit(
        at index: Int,
        authorID: String,
        options: [(id: String, label: String)]
    ) {
        let value = mediaAuthorEditingTextByID[authorID] ?? options.first(where: { $0.id == authorID })?.label ?? ""
        replaceMediaAuthor(at: index, authorID: authorID, with: value, options: options)
    }

    private func replaceMediaAuthor(
        at index: Int,
        authorID: String,
        with selectedLabel: String,
        options: [(id: String, label: String)]
    ) {
        guard draft.authorIDs.indices.contains(index) else { return }
        guard let selected = options.first(where: {
            $0.label.compare(
                selectedLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }) else {
            mediaAuthorEditingTextByID[authorID] = nil
            return
        }
        guard selected.id == authorID || !draft.authorIDs.contains(selected.id) else {
            mediaAuthorEditingTextByID[authorID] = nil
            return
        }
        draft.authorIDs[index] = selected.id
        mediaAuthorEditingTextByID[authorID] = nil
        scheduleAutosave()
    }

    private var localizedDescriptionBinding: Binding<String> {
        Binding(
            get: { language == .swedish ? draft.descriptionSv : draft.descriptionEn },
            set: { newValue in
                draft.setLocalizedDescription(newValue, language: language)
                scheduleAutosave()
            }
        )
    }

    private var localizedTitleBinding: Binding<String> {
        Binding(
            get: { language == .swedish ? draft.titleSv : draft.titleEn },
            set: { newValue in
                draft.setLocalizedTitle(newValue, language: language)
                scheduleAutosave()
            }
        )
    }

    private var localizedTitle: String {
        language == .swedish ? draft.titleSv : draft.titleEn
    }

    private var isEditingLocked: Bool { draft.isEditingLocked }

    private var localizedLanguageBinding: Binding<String> {
        Binding(
            get: { language == .swedish ? draft.languageSv : draft.languageEn },
            set: { newValue in
                draft.setLocalizedLanguage(newValue, language: language)
                scheduleAutosave()
            }
        )
    }

    private func scheduleAutosave() {
        let snapshot = draft
        AutosaveCoordinator.schedule(&autosaveTask, after: 0.5) {
            store.autosaveCVMediaAppearance(snapshot)
        }
    }

    private func persistAutosaveIfNeeded(baseline: CVMediaAppearance? = nil) {
        autosaveTask?.cancel()
        let current = baseline ?? appearance
        guard draft != current else { return }
        store.autosaveCVMediaAppearance(draft)
    }

    private func requestImmediateAutosave() {
        AutosaveCoordinator.requestImmediate(&forcedPersistTask, after: 0.05) {
            persistAutosaveIfNeeded()
        }
    }

    private var resolvedPDFURL: URL? {
        GrantDataStore.resolveCVMediaAppearancePDFURL(
            mediaAppearanceID: draft.id,
            pdfPath: draft.pdfPath,
            pdfFilename: draft.pdfFilename,
            legacyStoredFilenames: GrantDataStore.legacyMediaPDFCandidateNames(draft.attachments)
        )
    }

    private var hasPDFAttachment: Bool {
        draft.pdfFilename?.trimmedOrNil != nil || draft.pdfPath?.trimmedOrNil != nil
    }

    /// Files added by the earlier Media attachment UI remain readable here.
    /// New and replaced PDFs use the canonical single-PDF fields above.
    private var legacyGenericPDFAttachment: CVMediaAttachment? {
        guard !hasPDFAttachment else { return nil }
        return draft.attachments.first { $0.filename.lowercased().hasSuffix(".pdf") }
    }

    private var displayedPDFFilename: String? {
        draft.pdfFilename?.trimmedOrNil ?? legacyGenericPDFAttachment?.filename
    }

    private var displayedPDFURL: URL? {
        if let legacyGenericPDFAttachment,
           let legacyURL = GrantDataStore.resolveLegacyMediaAppearanceAttachmentURL(legacyGenericPDFAttachment) {
            return legacyURL
        }
        // F49: also looks under the record's id and in the older folder.
        return resolvedPDFURL
    }

    private var hasDisplayedPDFAttachment: Bool {
        hasPDFAttachment || legacyGenericPDFAttachment != nil
    }

    @ViewBuilder
    private var mediaPDFControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppPDFAttachmentControl(
                language: language,
                filename: displayedPDFFilename,
                displayLabel: AttachmentLabels.mediaAppearance(draft, language: language),
                placeholder: language.text("Drop PDF here", "Släpp PDF här"),
                hasAttachment: hasDisplayedPDFAttachment,
                isAvailable: displayedPDFURL != nil,
                isEditingLocked: isEditingLocked,
                style: .prominent,
                showsLeadingIcon: true,
                removeTitle: language.text("Remove media PDF", "Ta bort media-PDF"),
                previewTitle: showsPDFPreview ? language.text("Hide preview", "Dölj förhandsvisning") : language.text("Show preview", "Visa förhandsvisning"),
                isPreviewDisabled: displayedPDFURL == nil,
                chooseAction: choosePDF,
                openAction: openPDF,
                removeAction: {
                    if let attachment = legacyGenericPDFAttachment {
                        draft.attachments.removeAll { $0.id == attachment.id }
                    } else {
                        draft.pdfFilename = nil
                        draft.pdfPath = nil
                    }
                    showsPDFPreview = false
                    scheduleAutosave()
                },
                previewAction: {
                    showsPDFPreview.toggle()
                }
            )

            if showsPDFPreview, let displayedPDFURL {
                AppPDFDocumentView(pdfURL: displayedPDFURL, pdfData: nil)
                    .frame(minHeight: 540)
                    .background(
                        RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                            .fill(AppPalette.fieldSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }

        }
    }

    private func choosePDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = language.text("Choose PDF", "Välj PDF")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try loadPDFDataForUserAction(from: url)
            let managedURL = try GrantDataStore.persistManagedCVMediaAppearancePDF(
                data: data,
                forMediaAppearanceID: draft.id
            )
            if let attachment = legacyGenericPDFAttachment {
                draft.attachments.removeAll { $0.id == attachment.id }
            }
            draft.pdfFilename = url.lastPathComponent
            draft.pdfPath = GrantDataStore.portableAttachmentPath(for: managedURL)
            scheduleAutosave()
        } catch {
            store.reportFileActionFailure(
                language.text("Could not attach the media PDF.", "Kunde inte bifoga media-PDF-filen."),
                error: error
            )
        }
    }

    private func openPDF() {
        guard let displayedPDFURL else {
            store.reportFileActionFailure(
                language.text("Could not open the media PDF.", "Kunde inte öppna media-PDF-filen."),
                error: CocoaError(.fileNoSuchFile)
            )
            return
        }
        store.openFileForUserAction(
            displayedPDFURL,
            failureMessage: language.text("Could not open the media PDF.", "Kunde inte öppna media-PDF-filen.")
        )
    }

    private func openLink() {
        guard let url = normalizedWebLinkURL(draft.link) else { return }
        NSWorkspace.shared.open(url)
    }

    private var mediaCalendarDate: Date? {
        guard draft.date.trimmedOrNil != nil else { return nil }
        return DateParsers.isoDay.date(from: DateParsers.canonicalizedDayInput(draft.date))
    }

    private func openDateInCalendar() {
        guard let mediaCalendarDate else { return }
        store.revealCalendarWorkspace(on: mediaCalendarDate)
    }

    private func languageName(_ code: String) -> String {
        let options = store.mediaLanguageOptions
        let normalized = MediaLanguageOption.canonicalCode(for: code, options: options) ?? code
        return options.first(where: { $0.id == normalized })?.localizedName(language: language) ?? code
    }

    private func addTypedLanguage() {
        let input = languageInput.trimmedOrNil ?? ""
        let value = MediaLanguageOption.canonicalCode(for: input, options: store.mediaLanguageOptions) ?? input
        guard !value.isEmpty else { return }
        if !draft.languages.contains(value) { draft.languages.append(value); scheduleAutosave() }
        languageInput = ""
    }

}

private enum CVReviewWorkflowStep: Int, CaseIterable, Hashable {
    case accepted
    case deadline
    case completed

    func title(language: AppLanguage) -> String {
        switch self {
        case .accepted:
            return language.text("Accepted", "Accepterat")
        case .deadline:
            return language.text("Deadline", "Tidsfrist")
        case .completed:
            return language.text("Completed", "Slutfört")
        }
    }
}

private struct CVReviewWorkflowTimeline: View {
    @Binding var acceptedDate: String
    @Binding var deadlineDate: String
    @Binding var completedDate: String
    let isEditingLocked: Bool
    let language: AppLanguage

    private let horizontalInset: CGFloat = 68
    // Round 17: circles about 17 % larger (24 → 28).
    private let circleSize: CGFloat = 28
    private var markerCenterY: CGFloat { isEditingLocked ? 16 : 20 }
    private var stepWidth: CGFloat { isEditingLocked ? 150 : 190 }
    private var timelineHeight: CGFloat { isEditingLocked ? 76 : 132 }
    private let inactiveGray = AppTimelineStrip<CVReviewWorkflowStep, EmptyView>.inactiveGray

    private var visibleSteps: [CVReviewWorkflowStep] {
        let steps: [CVReviewWorkflowStep] = [.accepted, .completed, .deadline]
        guard isEditingLocked else { return steps }
        return steps.filter(stepHasDefinedDate)
    }

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var deadlineIsOverdue: Bool {
        guard completedDate.trimmedOrNil == nil,
              acceptedDate.trimmedOrNil != nil,
              let deadline = deadlineDate.trimmedOrNil.flatMap(DateParsers.isoDay.date(from:)) else {
            return false
        }
        return Calendar.current.startOfDay(for: deadline) < today
    }

    var body: some View {
        if visibleSteps.isEmpty {
            EmptyView()
        } else {
            AppTimelineStrip(
                nodes: timelineNodes,
                horizontalInset: horizontalInset,
                markerSize: circleSize,
                markerCenterY: markerCenterY,
                height: timelineHeight,
                nodeSpacing: isEditingLocked ? 5 : 9,
                showsTodayMarker: false,
                segmentProgressColor: { index in segmentProgressColor(index: index) }
            ) { node in
                Group {
                    if let step = visibleSteps.first(where: { $0 == node.id }) {
                        stepContent(for: step)
                    }
                }
            }
            .padding(.horizontal, isEditingLocked ? 0 : 18)
        }
    }

    private var timelineNodes: [AppTimelineNodeModel<CVReviewWorkflowStep>] {
        visibleSteps.map { step in
            AppTimelineNodeModel(
                id: step,
                width: stepWidth,
                anchorDate: parsedDate(for: step),
                hasDefinedDate: stepHasDefinedDate(step),
                isCompleted: stepIsActive(step),
                isDeemphasized: isStepDeemphasized(step),
                completedColor: stepColor(step),
                completedStrokeColor: stepIconColor(step),
                completedIconColor: AppPalette.statusOnFill
            )
        }
    }

    private func stepContent(for step: CVReviewWorkflowStep) -> some View {
        let isDeemphasized = isStepDeemphasized(step)
        return VStack(spacing: isEditingLocked ? 1 : 5) {
            if isEditingLocked {
                AppTimelineStepText(
                    text: step.title(language: language),
                    foreground: isDeemphasized ? inactiveGray : AppPalette.appText
                )
                .frame(maxWidth: stepWidth, alignment: .center)

                AppLockedInlineValueText(text: dateText(for: step), alignsWithFieldLabel: false)
                    .foregroundStyle(isDeemphasized ? inactiveGray : AppPalette.appText)
                    .frame(maxWidth: stepWidth, alignment: .center)
            } else {
                Button {
                    setTodayDate(for: step)
                } label: {
                    AppTimelineStepText(
                        text: step.title(language: language),
                        foreground: isDeemphasized ? inactiveGray : AppPalette.appText
                    )
                    .frame(maxWidth: stepWidth, alignment: .center)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(language.text("Set today's date", "Fyll i dagens datum"))

                AppTimelineDateEditor(
                    text: dateBinding(for: step),
                    uncertain: .constant(false),
                    isHiddenFromCalendar: false,
                    showsCountdown: false,
                    mutedColor: isDeemphasized ? inactiveGray : nil,
                    hiddenCalendarMenuTitle: nil,
                    toggleHiddenCalendarVisibility: nil,
                    language: language
                )
                .frame(maxWidth: stepWidth, alignment: .center)
            }
        }
    }

    // Round 16: the shared expert assignment tones (accepted yellow,
    // overdue orange, completed green); no blue.
    private func stepTone(_ step: CVReviewWorkflowStep) -> AppStatusTone {
        switch step {
        case .accepted:
            return .pending
        case .deadline:
            return deadlineIsOverdue ? .warning : .pending
        case .completed:
            return .done
        }
    }

    private func stepColor(_ step: CVReviewWorkflowStep) -> Color {
        AppPalette.statusFill(stepTone(step))
    }

    private func stepIconColor(_ step: CVReviewWorkflowStep) -> Color {
        AppPalette.statusEdge(stepTone(step))
    }

    private func segmentProgressColor(index: Int) -> Color {
        guard visibleSteps.indices.contains(index) else { return AppPalette.statusEdge(.pending) }
        if stepHasDefinedDate(.completed) {
            return AppPalette.statusEdge(.done)
        }
        if deadlineIsOverdue {
            return AppPalette.statusEdge(.warning)
        }
        return AppPalette.statusEdge(.pending)
    }

    private func stepIsActive(_ step: CVReviewWorkflowStep) -> Bool {
        switch step {
        case .accepted:
            return stepHasDefinedDate(.accepted) || stepHasDefinedDate(.completed)
        case .completed:
            return stepHasDefinedDate(.completed)
        case .deadline:
            return stepHasDefinedDate(.deadline)
        }
    }

    private func isStepDeemphasized(_ step: CVReviewWorkflowStep) -> Bool {
        step == .deadline && stepHasDefinedDate(.completed)
    }

    private func stepHasDefinedDate(_ step: CVReviewWorkflowStep) -> Bool {
        dateText(for: step).trimmedOrNil != nil
    }

    private func parsedDate(for step: CVReviewWorkflowStep) -> Date? {
        dateText(for: step)
            .trimmedOrNil
            .flatMap(DateParsers.isoDay.date(from:))
            .map { Calendar.current.startOfDay(for: $0) }
    }

    private func dateText(for step: CVReviewWorkflowStep) -> String {
        switch step {
        case .accepted:
            return acceptedDate
        case .deadline:
            return deadlineDate
        case .completed:
            return completedDate
        }
    }

    private func dateBinding(for step: CVReviewWorkflowStep) -> Binding<String> {
        switch step {
        case .accepted:
            return $acceptedDate
        case .deadline:
            return $deadlineDate
        case .completed:
            return $completedDate
        }
    }

    private func setTodayDate(for step: CVReviewWorkflowStep) {
        dateBinding(for: step).wrappedValue = DateParsers.isoDay.string(from: today)
    }
}

private struct CVReviewEntryDetailView: View {
    @ObservedObject var store: GrantDataStore
    let review: CVReviewEntry
    @Environment(\.scenePhase) private var scenePhase

    @State private var draft: CVReviewEntry
    @State private var autosaveTask: DispatchWorkItem?
    @State private var forcedPersistTask: DispatchWorkItem?
    @State private var showsCertificatePDFPreview = false
    @State private var exportedCertificatePDFURL: URL?

    init(store: GrantDataStore, review: CVReviewEntry) {
        self.store = store
        self.review = review
        _draft = State(initialValue: review)
    }

    private var language: AppLanguage { store.language }
    private var isEditingLocked: Bool { draft.isEditingLocked }

    private var journalOptions: [String] {
        store.publicationJournals
            .map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var organizationOptions: [String] {
        store.organizations
            .map { language == .swedish ? $0.nameSv : ($0.nameEn.nonEmpty ?? $0.nameSv) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var grantProgramOptions: [String] {
        cvReviewProgramAutocompleteOptions(
            reviewEntries: store.cvReviewEntries,
            selectedValue: draft.programName
        )
    }

    private var doctoralRoleOptions: [String] {
        cvReviewRoleAutocompleteOptions(
            category: .doctoralExamination,
            reviewEntries: store.cvReviewEntries,
            selectedValue: draft.roleName
        )
    }

    private var doctoralCandidateOptions: [String] {
        cvReviewPersonAutocompleteOptions(
            category: .doctoralExamination,
            reviewEntries: store.cvReviewEntries,
            doctoralCandidates: store.doctoralCandidates,
            selectedValue: draft.personName
        )
    }

    private var expertAssignmentTypeOptions: [String] {
        cvReviewRoleAutocompleteOptions(
            category: .otherExpertAssignment,
            reviewEntries: store.cvReviewEntries,
            selectedValue: draft.roleName
        )
    }

    private var expertAssignmentPersonOptions: [String] {
        cvReviewPersonAutocompleteOptions(
            category: .otherExpertAssignment,
            reviewEntries: store.cvReviewEntries,
            publicationAuthors: store.publicationAuthors,
            selectedValue: draft.personName
        )
    }

    private var selectedJournal: PublicationJournal? {
        store.linkedJournal(of: draft)
    }

    private var selectedOrganization: OrganizationRecord? {
        store.linkedOrganization(of: draft)
    }

    private var categoryOptions: [(String, CVReviewCategory)] {
        CVReviewCategory.allCases.map { ($0.localizedTitle(language), $0) }
    }

    private var researcherOptions: [String] {
        store.publicationAuthors
            .map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var selectedResearcher: PublicationAuthor? {
        store.publicationAuthor(id: draft.authorID)
    }

    private var resolvedResearcherName: String {
        selectedResearcher?.name
            ?? draft.authorID.flatMap { store.publicationAuthor(id: $0)?.name }
            ?? ""
    }

    private var resolvedJournalName: String {
        selectedJournal?.name ?? draft.journalName
    }

    private var resolvedOrganizationName: String {
        selectedOrganization.map(localizedOrganizationName) ?? draft.organizationName
    }

    private var localizedCommentText: String {
        draft.localizedComment(language: language)
    }

    private var certificateDisplayName: String {
        draft.certificateFilename?.nonEmpty
            ?? draft.certificatePath.flatMap { URL(fileURLWithPath: $0).lastPathComponent.nonEmpty }
            ?? language.text("No file selected", "Ingen fil vald")
    }

    private var resolvedCertificatePDFURL: URL? {
        GrantDataStore.resolveCVReviewCertificatePDFURL(
            reviewEntryID: draft.id,
            certificatePath: draft.certificatePath,
            certificateFilename: draft.certificateFilename
        )
    }

    private var hasCertificatePDFAttachment: Bool {
        draft.certificatePDFData != nil
            || draft.certificatePath?.trimmedOrNil != nil
            || draft.certificateFilename?.nonEmpty != nil
    }

    private var certificatePDFPreviewIsAvailable: Bool {
        draft.certificatePDFData != nil || resolvedCertificatePDFURL != nil
    }

    private var shouldShowReviewTaskList: Bool {
        draft.workflowStatus() != .completed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    CVHeaderView(
                        title: draft.displayTitle,
                        subtitle: draft.category.localizedTitle(language)
                    )
                    Spacer(minLength: 12)
                    reviewEditorLockButton
                    if !isEditingLocked {
                        AppDestructiveActionButton(
                            title: language.text("Delete", "Ta bort"),
                            help: language.text("Delete this expert assignment", "Ta bort detta sakkunniguppdrag"),
                            cancelTitle: language.text("Cancel", "Avbryt"),
                            confirmationTitle: language.text("Delete expert assignment?", "Ta bort sakkunniguppdrag?"),
                            confirmationMessage: language.text("The deletion can be undone.", "Borttagningen kan ångras.")
                        ) {
                            store.deleteCVReviewEntry(id: review.id)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: isEditingLocked ? 10 : 14) {
                    reviewWorkflowTimeline
                    if !isEditingLocked {
                        categoryField
                    }
                    reviewCategoryFields
                    referenceField
                    reviewRoundField
                    commentField
                    reviewCertificateField
                }

                if shouldShowReviewTaskList {
                    CVPanel(
                        title: language.text("Task list", "Uppgiftslista"),
                        titleActionTitle: isEditingLocked ? nil : language.text("Add task", "Lägg till uppgift"),
                        titleAction: {
                            CentralTaskListSection.addTask(store: store, linkKind: .review, targetID: draft.id)
                        }
                    ) {
                        CentralTaskListSection(
                            store: store,
                            linkKind: .review,
                            targetID: draft.id,
                            language: language,
                            reminderOptions: ProjectTaskReminder.allCases,
                            isReadOnly: isEditingLocked,
                            showsAddButton: false
                        )
                    }
                }
            }
            .padding(14)
        }
        .background(AppPalette.detailPanelSurface)
        .flushPendingAutosaveOnTextEnd(requestImmediateAutosave)
        .onDisappear {
            autosaveTask?.cancel()
            forcedPersistTask?.cancel()
            persistAutosaveIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                requestImmediateAutosave()
            }
        }
        .onChange(of: review) { oldValue, newValue in
            // See the media editor: keep and save unsaved typing.
            if oldValue.id == newValue.id, draft != oldValue, draft != newValue {
                persistAutosaveIfNeeded(baseline: newValue)
                return
            }
            autosaveTask?.cancel()
            forcedPersistTask?.cancel()
            if oldValue.id != newValue.id {
                persistAutosaveIfNeeded(baseline: oldValue)
            }
            draft = newValue
            showsCertificatePDFPreview = false
        }
    }

    private var shouldShowReviewWorkflowTimeline: Bool {
        !isEditingLocked ||
            draft.acceptedDate.trimmedOrNil != nil ||
            draft.deadlineDate.trimmedOrNil != nil ||
            draft.date.trimmedOrNil != nil
    }

    @ViewBuilder
    private var reviewWorkflowTimeline: some View {
        if shouldShowReviewWorkflowTimeline {
            CVReviewWorkflowTimeline(
                acceptedDate: binding(\.acceptedDate),
                deadlineDate: binding(\.deadlineDate),
                completedDate: binding(\.date),
                isEditingLocked: isEditingLocked,
                language: language
            )
        }
    }

    private var reviewEditorLockButton: some View {
        AppEditorLockButton(isLocked: isEditingLocked, language: language) {
            let nextValue = !isEditingLocked
            if nextValue {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
            draft.isEditingLocked = nextValue
            requestImmediateAutosave()
        }
    }

    @ViewBuilder
    private var researcherField: some View {
        if shouldShowReviewField(resolvedResearcherName) {
            CVLabeledField(title: language.text("Researcher", "Forskare")) {
                HStack(spacing: 8) {
                    if isEditingLocked {
                        lockedReviewValueText(resolvedResearcherName)
                    } else {
                        AutocompleteSelectionField(
                            text: researcherBinding,
                            options: researcherOptions,
                            placeholder: language.text("Researcher", "Forskare"),
                            onCommit: {},
                            onSelect: { selected in
                                researcherBinding.wrappedValue = selected
                            },
                            updatesTextContinuously: true
                        )
                    }

                    if let selectedResearcher {
                        AppDestinationActionButton(
                            kind: .app,
                            language: language,
                            title: language.text("Open researcher", "Öppna forskare"),
                            fontSize: 12
                        ) {
                            store.openRoute(for: selectedResearcher)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var categoryField: some View {
        CVLabeledField(title: language.text("Category", "Kategori")) {
            if isEditingLocked {
                lockedReviewValueText(draft.category.localizedTitle(language))
            } else {
                AppMenuSelectionField(
                    selection: Binding(
                        get: { draft.category },
                        set: {
                            guard !isEditingLocked else { return }
                            draft.category = $0
                            scheduleAutosave()
                        }
                    ),
                    options: categoryOptions,
                    placeholder: nil
                )
            }
        }
    }

    @ViewBuilder
    private var dateField: some View {
        if shouldShowReviewField(draft.date) {
            CVLabeledField(title: language.text("Date", "Datum")) {
                if isEditingLocked {
                    lockedReviewValueText(draft.date)
                } else {
                    CVDateField(text: binding(\.date), showsTodayButton: draft.category == .journalReview, language: language)
                }
            }
        }
    }

    @ViewBuilder
    private var reviewRoundField: some View {
        if draft.category == .journalReview, shouldShowReviewField(draft.reviewRound) {
            CVLabeledField(title: language.text("Review round", "Granskningsomgång")) {
                if isEditingLocked {
                    lockedReviewValueText(reviewRoundLabel(draft.reviewRound))
                } else {
                    AppMenuSelectionField(
                        selection: Binding(
                            get: { draft.reviewRound },
                            set: { newValue in
                                guard !isEditingLocked else { return }
                                draft.reviewRound = newValue
                                scheduleAutosave()
                            }
                        ),
                        options: reviewRoundOptions,
                        placeholder: language.text("Not stated", "Ej angiven"),
                        clearValue: ""
                    )
                }
            }
        }
    }

    // F8: first review and R1–R9; the stored value is the short form ("R1").
    private var reviewRoundOptions: [(label: String, value: String)] {
        var options: [(label: String, value: String)] = [
            (language.text("First review", "Första granskning"), "Första granskning")
        ]
        options.append(contentsOf: (1...9).map { ("R\($0)", "R\($0)") })
        let stored = draft.reviewRound.trimmedOrNil
        if let stored, !options.contains(where: { $0.value == stored }) {
            options.append((stored, stored))
        }
        return options
    }

    private func reviewRoundLabel(_ value: String) -> String {
        guard let stored = value.trimmedOrNil else { return "" }
        return reviewRoundOptions.first(where: { $0.value == stored })?.label ?? stored
    }

    @ViewBuilder
    private var referenceField: some View {
        if shouldShowReviewField(draft.reference) {
            CVLabeledField(title: language.text("Reference", "Referens")) {
                if isEditingLocked {
                    lockedReviewValueText(draft.reference)
                } else {
                    AppCommitTextField(
                        placeholder: language.text("Reference", "Referens"),
                        text: binding(\.reference)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var commentField: some View {
        if shouldShowReviewField(localizedCommentText) {
            CVLabeledField(title: language.text("Comment", "Kommentar")) {
                if isEditingLocked {
                    lockedReviewValueText(localizedCommentText, lineLimit: nil)
                } else {
                    CVMultilineTextEditor(text: localizedCommentBinding)
                }
            }
        }
    }

    @ViewBuilder
    private var reviewCertificateField: some View {
        if !isEditingLocked || hasCertificatePDFAttachment {
            CVLabeledField(title: language.text("Review certificate", "Sakkunnigintyg")) {
                VStack(alignment: .leading, spacing: 12) {
                    AppPDFAttachmentControl(
                        language: language,
                        filename: hasCertificatePDFAttachment ? certificateDisplayName : nil,
                        displayLabel: AttachmentLabels.reviewCertificate(draft, language: language),
                        placeholder: language.text("No file selected", "Ingen fil vald"),
                        hasAttachment: hasCertificatePDFAttachment,
                        isAvailable: certificatePDFPreviewIsAvailable != false,
                        isEditingLocked: isEditingLocked,
                        style: .prominent,
                        showsLeadingIcon: true,
                        removeTitle: language.text("Remove review certificate PDF", "Ta bort PDF"),
                        previewTitle: showsCertificatePDFPreview ? language.text("Hide preview", "Dölj förhandsvisning") : language.text("Show preview", "Visa förhandsvisning"),
                        isPreviewDisabled: certificatePDFPreviewIsAvailable == false,
                        chooseAction: chooseCertificate,
                        openAction: openCertificatePDF,
                        removeAction: {
                            draft.certificateFilename = nil
                            draft.certificatePDFData = nil
                            draft.certificatePath = nil
                            showsCertificatePDFPreview = false
                            scheduleAutosave()
                        },
                        previewAction: {
                            showsCertificatePDFPreview.toggle()
                        }
                    )

                    if showsCertificatePDFPreview, certificatePDFPreviewIsAvailable {
                        AppPDFDocumentView(pdfURL: resolvedCertificatePDFURL, pdfData: draft.certificatePDFData)
                            .frame(minHeight: 420)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(AppPalette.fieldSurface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    } else if hasCertificatePDFAttachment && certificatePDFPreviewIsAvailable == false {
                        Text(language.text("The old file reference could not be imported automatically. Choose the PDF again to store it in the database.", "Den gamla filreferensen kunde inte importeras automatiskt. Välj PDF-filen igen för att lagra den i databasen."))
                            .appTypography(.secondary)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func localizedOrganizationName(_ organization: OrganizationRecord) -> String {
        language == .swedish ? organization.nameSv : (organization.nameEn.nonEmpty ?? organization.nameSv)
    }

    private func shouldShowReviewField(_ value: String?) -> Bool {
        AppLockedFieldVisibility.shouldShow(isLocked: isEditingLocked, value: value)
    }

    private func lockedReviewValueText(_ value: String?, lineLimit: Int? = 2) -> some View {
        AppLockedFieldValueText(text: value, lineLimit: lineLimit)
    }

    private var researcherBinding: Binding<String> {
        Binding(
            get: {
                resolvedResearcherName
            },
            set: { newValue in
                guard !isEditingLocked else { return }
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if let matched = store.publicationAuthor(matchingPresentedName: trimmed) {
                    draft.authorID = matched.id
                } else {
                    draft.authorID = nil
                }
                scheduleAutosave()
            }
        )
    }

    @ViewBuilder
    private var reviewCategoryFields: some View {
        switch draft.category {
        case .journalReview:
            if shouldShowReviewField(resolvedJournalName) {
                CVLabeledField(title: language.text("Journal", "Tidskrift")) {
                    HStack(spacing: 8) {
                        if isEditingLocked {
                            lockedReviewValueText(resolvedJournalName)
                        } else {
                            AutocompleteSelectionField(
                                text: journalBinding,
                                options: journalOptions,
                                placeholder: language.text("Journal", "Tidskrift"),
                                onCommit: {}
                            )
                        }

                        if let selectedJournal {
                            AppDestinationActionButton(
                                kind: .app,
                                language: language,
                                title: language.text("Open journal", "Öppna tidskrift"),
                                fontSize: 12
                            ) {
                                store.openRoute(for: selectedJournal)
                            }
                        }
                    }
                }
            }
            if shouldShowReviewField(draft.subjectTitle) {
                CVLabeledField(title: language.text("Article title", "Titel på artikel")) {
                    if isEditingLocked {
                        lockedReviewValueText(draft.subjectTitle, lineLimit: 3)
                    } else {
                        AppTextEditorField(
                            title: nil,
                            text: binding(\.subjectTitle),
                            placeholder: language.text("Article title", "Titel på artikel"),
                            minimumHeight: 54,
                            maximumHeight: 96
                        )
                    }
                }
            }
        case .grantProposalReview:
            organizationField(title: language.text("Organization", "Organisation"))
            if shouldShowReviewField(draft.programName) {
                CVLabeledField(title: language.text("Programme or call", "Program eller utlysning")) {
                    if isEditingLocked {
                        lockedReviewValueText(draft.programName)
                    } else {
                        AutocompleteSelectionField(
                            text: binding(\.programName),
                            options: grantProgramOptions,
                            placeholder: language.text("Programme or call", "Program eller utlysning"),
                            onCommit: {}
                        )
                    }
                }
            }
        case .doctoralExamination:
            organizationField(title: language.text("Institution", "Lärosäte"))
            if shouldShowReviewField(draft.roleName) {
                CVLabeledField(title: language.text("Role", "Roll")) {
                    if isEditingLocked {
                        lockedReviewValueText(draft.roleName)
                    } else {
                        AutocompleteSelectionField(
                            text: binding(\.roleName),
                            options: doctoralRoleOptions,
                            placeholder: language.text("Role", "Roll"),
                            onCommit: {}
                        )
                    }
                }
            }
            if shouldShowReviewField(draft.personName) {
                CVLabeledField(title: language.text("Doctoral candidate", "Doktorand")) {
                    if isEditingLocked {
                        lockedReviewValueText(draft.personName)
                    } else {
                        AutocompleteSelectionField(
                            text: binding(\.personName),
                            options: doctoralCandidateOptions,
                            placeholder: language.text("Doctoral candidate", "Doktorand"),
                            onCommit: {}
                        )
                    }
                }
            }
            if shouldShowReviewField(draft.subjectTitle) {
                CVLabeledField(title: language.text("Thesis title", "Avhandlingstitel")) {
                    if isEditingLocked {
                        lockedReviewValueText(draft.subjectTitle, lineLimit: 3)
                    } else {
                        AppCommitTextField(
                            placeholder: language.text("Thesis title", "Avhandlingstitel"),
                            text: binding(\.subjectTitle)
                        )
                    }
                }
            }
        case .otherExpertAssignment:
            organizationField(title: language.text("Organization", "Organisation"))
            if shouldShowReviewField(draft.roleName) {
                CVLabeledField(title: language.text("Assignment type", "Uppdragstyp")) {
                    if isEditingLocked {
                        lockedReviewValueText(draft.roleName)
                    } else {
                        AutocompleteSelectionField(
                            text: binding(\.roleName),
                            options: expertAssignmentTypeOptions,
                            placeholder: language.text("Assignment type", "Uppdragstyp"),
                            onCommit: {}
                        )
                    }
                }
            }
            if shouldShowReviewField(draft.subjectTitle) {
                CVLabeledField(title: language.text("Title or description", "Titel eller beskrivning")) {
                    if isEditingLocked {
                        lockedReviewValueText(draft.subjectTitle, lineLimit: 3)
                    } else {
                        AppCommitTextField(
                            placeholder: language.text("Title or description", "Titel eller beskrivning"),
                            text: binding(\.subjectTitle)
                        )
                    }
                }
            }
            if shouldShowReviewField(draft.personName) {
                CVLabeledField(title: language.text("Person", "Person")) {
                    if isEditingLocked {
                        lockedReviewValueText(draft.personName)
                    } else {
                        AutocompleteSelectionField(
                            text: binding(\.personName),
                            options: expertAssignmentPersonOptions,
                            placeholder: language.text("Person", "Person"),
                            onCommit: {}
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func organizationField(title: String) -> some View {
        if shouldShowReviewField(resolvedOrganizationName) {
            CVLabeledField(title: title) {
                HStack(spacing: 8) {
                    if isEditingLocked {
                        lockedReviewValueText(resolvedOrganizationName)
                    } else {
                        AutocompleteSelectionField(
                            text: organizationBinding,
                            options: organizationOptions,
                            placeholder: title,
                            onCommit: {}
                        )
                    }

                    if let selectedOrganization {
                        AppDestinationActionButton(
                            kind: .app,
                            language: language,
                            title: language.text("Open organization", "Öppna organisation"),
                            fontSize: 12
                        ) {
                            store.openRoute(for: selectedOrganization)
                        }
                    }
                }
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<CVReviewEntry, String>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { newValue in
                guard !isEditingLocked else { return }
                draft[keyPath: keyPath] = newValue
                scheduleAutosave()
            }
        )
    }

    private var localizedCommentBinding: Binding<String> {
        Binding(
            get: { language == .swedish ? draft.commentSv : draft.commentEn },
            set: {
                guard !isEditingLocked else { return }
                draft.setLocalizedComment($0, language: language)
                scheduleAutosave()
            }
        )
    }

    /// The journal is linked by id when the text names a journal in the
    /// list; free text keeps no link.
    private var journalBinding: Binding<String> {
        Binding(
            get: { draft.journalName },
            set: { newValue in
                guard !isEditingLocked else { return }
                draft.journalName = newValue
                draft.journalID = newValue.trimmedOrNil.flatMap { store.publicationJournal(named: $0)?.id }
                scheduleAutosave()
            }
        )
    }

    /// The organization is linked by id when the text names an organization
    /// in the list; free text keeps no link.
    private var organizationBinding: Binding<String> {
        Binding(
            get: { draft.organizationName },
            set: { newValue in
                guard !isEditingLocked else { return }
                draft.organizationName = newValue
                draft.organizationID = newValue.trimmedOrNil.flatMap { store.organization(matchingName: $0)?.id }
                scheduleAutosave()
            }
        )
    }

    private func scheduleAutosave() {
        let snapshot = draft
        AutosaveCoordinator.schedule(&autosaveTask, after: 0.5) {
            store.autosaveCVReviewEntry(snapshot)
        }
    }

    private func persistAutosaveIfNeeded(baseline: CVReviewEntry? = nil) {
        autosaveTask?.cancel()
        let current = baseline ?? review
        guard draft != current else { return }
        store.autosaveCVReviewEntry(draft)
    }

    private func requestImmediateAutosave() {
        AutosaveCoordinator.requestImmediate(&forcedPersistTask, after: 0.05) {
            persistAutosaveIfNeeded()
        }
    }

    private func chooseCertificate() {
        guard !isEditingLocked else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = language.text("Choose", "Välj")
        panel.title = language.text("Choose review certificate", "Välj reviewintyg")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let pdfData = try loadPDFDataForUserAction(from: url)
            let managedURL = try GrantDataStore.persistManagedCVReviewCertificatePDF(
                data: pdfData,
                forReviewEntryID: draft.id
            )
            draft.certificateFilename = url.lastPathComponent
            draft.certificatePath = GrantDataStore.portableAttachmentPath(for: managedURL)
            draft.certificatePDFData = nil
            scheduleAutosave()
        } catch {
            store.reportFileActionFailure(
                language.text("Could not attach the review certificate PDF.", "Kunde inte bifoga PDF-filen med reviewintyget."),
                error: error
            )
        }
    }

    private func openCertificatePDF() {
        if let resolvedCertificatePDFURL {
            store.openFileForUserAction(
                resolvedCertificatePDFURL,
                failureMessage: language.text("Could not open the review certificate PDF.", "Kunde inte öppna PDF-filen med reviewintyget.")
            )
            return
        }
        guard let pdfData = draft.certificatePDFData else {
            store.reportFileActionFailure(
                language.text("Could not open the review certificate PDF.", "Kunde inte öppna PDF-filen med reviewintyget."),
                error: CocoaError(.fileNoSuchFile)
            )
            return
        }
        let filename = safeTemporaryPDFFilename(draft.certificateFilename, fallback: "review-certificate.pdf")
        let targetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try pdfData.write(to: targetURL, options: .atomic)
            exportedCertificatePDFURL = targetURL
            store.openFileForUserAction(
                targetURL,
                failureMessage: language.text("Could not open the review certificate PDF.", "Kunde inte öppna PDF-filen med reviewintyget.")
            )
        } catch {
            store.reportFileActionFailure(
                language.text("Could not open the review certificate PDF.", "Kunde inte öppna PDF-filen med reviewintyget."),
                error: error
            )
        }
    }
}

struct CVOtherPublicationDetailView: View {
    @ObservedObject var store: GrantDataStore
    let item: CVOtherPublicationEntry
    @Environment(\.scenePhase) private var scenePhase

    @State private var draft: CVOtherPublicationEntry
    @State private var autosaveTask: DispatchWorkItem?
    @State private var forcedPersistTask: DispatchWorkItem?

    private var language: AppLanguage { store.language }
    private var isDoctoralThesis: Bool { draft.isDoctoralThesis }
    private var currentUserName: String? {
        store.currentUserAuthor()?.name.nonEmpty
    }
    private var researcherOptions: [String] {
        store.coauthors
            .map(\.name)
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    init(store: GrantDataStore, item: CVOtherPublicationEntry) {
        self.store = store
        self.item = item
        _draft = State(initialValue: item)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CVHeaderView(
                    title: draft.localizedTitle(language: language).nonEmpty ?? draft.displayTitle,
                    subtitle: isDoctoralThesis
                        ? language.text("Doctoral thesis", "Doktorsavhandling")
                        : language.text("Other publication", "Övrig publikation")
                )

                if isDoctoralThesis {
                            CVPanel(title: language.text("Doctoral thesis", "Doktorsavhandling")) {
                        VStack(alignment: .leading, spacing: 12) {
                            CVLabeledField(title: language.text("Year", "År")) {
                                AppYearField(text: binding(\.date), language: language, width: 120)
                            }

                            HStack(alignment: .bottom, spacing: 12) {
                                CVLabeledField(title: language.text("Title", "Titel")) {
                                    TextField(language == .swedish ? "Titel (svenska)" : "Title (English)", text: localizedTitleBinding)
                                        .appTextInputChrome()
                                }
                                if let doiURL = draft.doiURL {
                                    Link("DOI", destination: doiURL)
                                        .appTypography(.fieldLabel)
                                        .foregroundStyle(AppPalette.linkAction)
                                        .padding(.bottom, 4)
                                }
                            }

                            HStack(alignment: .top, spacing: 12) {
                                CVLabeledField(title: language.text("Publisher / series", "Förlag / serie")) {
                                    TextField(language == .swedish ? "Publikation / outlet (svenska)" : "Publication / outlet (English)", text: localizedOutletBinding)
                                        .appTextInputChrome()
                                }
                                CVLabeledField(title: language.text("Publisher short name", "Kortnamn för förlag")) {
                                    TextField(language.text("Short name", "Kortnamn"), text: binding(\.publisherShortName))
                                        .appTextInputChrome()
                                        .frame(width: 170)
                                }
                                CVLabeledField(title: language.text("City", "Stad")) {
                                    TextField(language.text("City", "Stad"), text: binding(\.city))
                                        .appTextInputChrome()
                                        .frame(width: 160)
                                }
                            }

                            HStack(alignment: .top, spacing: 12) {
                                CVLabeledField(title: "DOI") {
                                    AppIdentifierField(kind: .doi, text: binding(\.doi), language: language)
                                }
                                CVLabeledField(title: language.text("Language", "Språk")) {
                                    TextField(language.text("Language", "Språk"), text: localizedLanguageBinding)
                                        .appTextInputChrome()
                                        .frame(width: 180)
                                }
                            }

                            HStack(alignment: .top, spacing: 12) {
                                CVLabeledField(title: language.text("Main supervisor", "Huvudhandledare")) {
                                    AutocompleteSelectionField(
                                        text: binding(\.mainSupervisor),
                                        options: researcherOptions,
                                        placeholder: language.text("Main supervisor", "Huvudhandledare"),
                                        addNewTitle: language.text("Add new", "Lägg till ny"),
                                        display: { $0 },
                                        onCommit: {}
                                    )
                                }
                                CVLabeledField(title: language.text("Co-supervisor", "Bihandledare")) {
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
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            TextField(language.text("Date", "Datum"), text: binding(\.date))
                                .appTextInputChrome()
                                .frame(width: 160)
                            TextField(language == .swedish ? "Kategori (svenska)" : "Category (English)", text: localizedCategoryBinding)
                                .appTextInputChrome()
                        }
                        TextField("Authors", text: binding(\.authors))
                            .appTextInputChrome()
                        TextField(language == .swedish ? "Titel (svenska)" : "Title (English)", text: localizedTitleBinding)
                            .appTextInputChrome()
                        TextField(language == .swedish ? "Publikation / outlet (svenska)" : "Publication / outlet (English)", text: localizedOutletBinding)
                            .appTextInputChrome()
                        TextField(language == .swedish ? "Publikationsdata (svenska)" : "Publication data (English)", text: localizedPublicationDataBinding, axis: .vertical)
                            .appTextInputChrome()
                            .lineLimit(2...6)
                    }
                }

                if !isDoctoralThesis {
                    HStack {
                        Spacer()
                        AppDestructiveActionButton(
                            title: language.text("Delete", "Ta bort"),
                            help: language.text("Delete other publication", "Ta bort övrig publikation"),
                            cancelTitle: language.text("Cancel", "Avbryt"),
                            confirmationTitle: language.text("Delete other publication?", "Ta bort övrig publikation?"),
                            confirmationMessage: language.text("The deletion can be undone.", "Borttagningen kan ångras.")
                        ) {
                            store.deleteCVOtherPublication(id: item.id)
                        }
                    }
                }
            }
            .padding(18)
        }
        .flushPendingAutosaveOnTextEnd(requestImmediateAutosave)
        .onDisappear {
            autosaveTask?.cancel()
            forcedPersistTask?.cancel()
            persistAutosaveIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                requestImmediateAutosave()
            }
        }
        .onChange(of: draft) { _, _ in scheduleAutosave() }
        .onChange(of: item) { oldValue, newValue in
            if oldValue.id != newValue.id {
                autosaveTask?.cancel()
                forcedPersistTask?.cancel()
                persistAutosaveIfNeeded(baseline: oldValue)
            }
            draft = newValue
            syncDoctoralThesisAuthor()
        }
        .onAppear {
            syncDoctoralThesisAuthor()
        }
    }

    private var localizedCategoryBinding: Binding<String> {
        Binding(get: { draft.localizedCategory(language: language) }, set: { draft.setLocalizedCategory($0, language: language) })
    }

    private var localizedTitleBinding: Binding<String> {
        Binding(get: { draft.localizedTitle(language: language) }, set: { draft.setLocalizedTitle($0, language: language) })
    }

    private var localizedOutletBinding: Binding<String> {
        Binding(get: { draft.localizedOutlet(language: language) }, set: { draft.setLocalizedOutlet($0, language: language) })
    }

    private var localizedPublicationDataBinding: Binding<String> {
        Binding(get: { draft.localizedPublicationData(language: language) }, set: { draft.setLocalizedPublicationData($0, language: language) })
    }

    private var localizedLanguageBinding: Binding<String> {
        Binding(get: { draft.localizedLanguage(language: language) }, set: { draft.setLocalizedLanguage($0, language: language) })
    }

    private func binding(_ keyPath: WritableKeyPath<CVOtherPublicationEntry, String>) -> Binding<String> {
        Binding(get: { draft[keyPath: keyPath] }, set: { draft[keyPath: keyPath] = $0 })
    }

    private func syncDoctoralThesisAuthor() {
        guard isDoctoralThesis, let currentUserName, draft.authors != currentUserName else { return }
        draft.authors = currentUserName
    }

    private func scheduleAutosave() {
        let snapshot = currentSnapshot()
        AutosaveCoordinator.schedule(&autosaveTask, after: 0.35) { store.autosaveCVOtherPublication(snapshot) }
    }

    private func currentSnapshot() -> CVOtherPublicationEntry {
        var snapshot = draft
        if isDoctoralThesis, let currentUserName {
            snapshot.authors = currentUserName
        }
        return snapshot
    }

    private func persistAutosaveIfNeeded(baseline: CVOtherPublicationEntry? = nil) {
        autosaveTask?.cancel()
        let snapshot = currentSnapshot()
        let current = baseline ?? item
        guard snapshot != current else { return }
        store.autosaveCVOtherPublication(snapshot)
    }

    private func requestImmediateAutosave() {
        AutosaveCoordinator.requestImmediate(&forcedPersistTask, after: 0.05) {
            persistAutosaveIfNeeded()
        }
    }
}

private struct CVHeaderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.nonEmpty ?? "—")
                .appTypography(.pageTitle)
            Text(subtitle)
                .appTypography(.secondary)
                .foregroundStyle(.secondary)
        }
    }
}

private typealias CVPanel<Content: View> = AppWorkspacePanel<Content>
private typealias CVLabeledField<Content: View> = AppLabeledField<Content, EmptyView>

private struct CVDateField: View {
    @Binding var text: String
    var textAlignment: TextAlignment = .leading
    var showsTodayButton = false
    var language: AppLanguage = .english
    var isIllogical = false

    private var fieldAlignment: Alignment {
        switch textAlignment {
        case .center:
            return .center
        case .trailing:
            return .trailing
        default:
            return .leading
        }
    }

    private var nsTextAlignment: NSTextAlignment {
        switch textAlignment {
        case .center:
            return .center
        case .trailing:
            return .right
        default:
            return .left
        }
    }

    private var visualState: AppFieldVisualState {
        isIllogical
            ? .invalid(language.text("Illogical date combination", "Ologisk datumkombination"))
            : .normal
    }

    var body: some View {
        AppDateField(
            placeholder: language.datePlaceholder,
            text: $text,
            width: 120,
            showsTodayButton: showsTodayButton,
            language: language,
            state: visualState,
            textAlignment: nsTextAlignment
        )
        .frame(minWidth: 120, alignment: fieldAlignment)
    }
}

private struct CVMultilineTextEditor: View {
    @Binding var text: String

    var body: some View {
        AppTextEditorField(title: nil, text: $text, minimumHeight: 72)
    }
}
