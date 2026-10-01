import AppKit
import SwiftUI
import UniformTypeIdentifiers

func salaryCoveragePeriodPassesVisibleFromFilter(
    _ period: SalaryCoveragePeriod,
    visibleFromDate: Date?,
    forceVisiblePeriodIDs: Set<String> = []
) -> Bool {
    if forceVisiblePeriodIDs.contains(period.id) {
        return true
    }
    guard let visibleFromDate else {
        return true
    }

    let normalizedFrom = normalizeSalaryDateInput(period.from)
    let normalizedTo = normalizeSalaryDateInput(period.to)
    let isComplete = period.sourceReference.trimmedOrNil != nil
        && normalizedFrom.trimmedOrNil != nil
        && normalizedTo.trimmedOrNil != nil
        && period.percentage.trimmedOrNil != nil
    guard isComplete else {
        return true
    }

    let from = DateParsers.isoDay.date(from: normalizedFrom)
    let to = DateParsers.isoDay.date(from: normalizedTo)
    return (to ?? from ?? .distantFuture) >= visibleFromDate
}

func salaryCoveragePeriodIsComplete(_ period: SalaryCoveragePeriod) -> Bool {
    period.sourceReference.trimmedOrNil != nil
        && normalizeSalaryDateInput(period.from).trimmedOrNil != nil
        && normalizeSalaryDateInput(period.to).trimmedOrNil != nil
        && period.percentage.trimmedOrNil != nil
}

enum SalaryCalendarColorTarget: Equatable {
    case clinicMeetingCategory
    case activity2
    case activity3
}

/// The calendar colour a salary source follows, from the colour chosen in
/// the salary source editor (round 7: the source's name no longer matters).
func salaryCalendarColorTarget(for source: SalarySource) -> SalaryCalendarColorTarget? {
    switch source.effectiveColor {
    case .clinicCalendarCategory:
        return .clinicMeetingCategory
    case .calendarActivity2:
        return .activity2
    case .calendarActivity3:
        return .activity3
    case .blue, .red:
        return nil
    }
}

func salaryCalendarColorTarget(forSourceReference reference: String) -> SalaryCalendarColorTarget? {
    reference.hasPrefix("grant:") ? .activity3 : nil
}

func salaryTimelineLabelIsLeave(_ label: String) -> Bool {
    let normalized = label
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "sv_SE"))
        .lowercased()
    return normalized == "tjanstledighet" || normalized == "on leave"
}

struct SalaryTimelineStackPriority {
    let isLeave: Bool
    let duration: TimeInterval
    let from: Date
    let to: Date
    let percentage: Double
    let rowOrder: Int
    let rowKey: String
    let id: String
}

func salaryTimelineStackPriorityComesBefore(
    _ lhs: SalaryTimelineStackPriority,
    _ rhs: SalaryTimelineStackPriority
) -> Bool {
    if lhs.isLeave != rhs.isLeave { return !lhs.isLeave }
    if lhs.duration != rhs.duration { return lhs.duration > rhs.duration }
    if lhs.percentage != rhs.percentage { return lhs.percentage > rhs.percentage }
    if lhs.from != rhs.from { return lhs.from < rhs.from }
    if lhs.to != rhs.to { return lhs.to > rhs.to }
    if lhs.rowOrder != rhs.rowOrder { return lhs.rowOrder < rhs.rowOrder }
    let rowKeyComparison = lhs.rowKey.localizedStandardCompare(rhs.rowKey)
    if rowKeyComparison != .orderedSame { return rowKeyComparison == .orderedAscending }
    return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
}

struct SalaryWorkspaceView: View {
    private enum SalarySourceListSortColumn: String, Hashable {
        case category
        case project
        case projectNumber

        var defaultAscending: Bool { true }
    }

    private struct SalarySourceListSortCriterion: AppListSortCriterion {
        let column: SalarySourceListSortColumn
        var ascending: Bool
    }

    private enum SalaryPeriodListSortColumn: String, Hashable {
        case source
        case from
        case to
        case percentage

        var defaultAscending: Bool {
            switch self {
            case .source:
                return true
            case .from, .to, .percentage:
                return false
            }
        }
    }

    private struct SalaryPeriodListSortCriterion: AppListSortCriterion {
        let column: SalaryPeriodListSortColumn
        var ascending: Bool
    }

    @ObservedObject var store: GrantDataStore
    let isActive: Bool
    let openApplicationAction: (String) -> Void
    @State private var sourcesDraft: [SalarySource]
    @State private var periodsDraft: [SalaryCoveragePeriod]
    @State private var sourceSearchText = ""
    @State private var periodSearchText = ""
    @State private var selectedSourceCategoryFilters: Set<SalarySourceCategory> = []
    @State private var selectedSourceProjectFilters: Set<String> = []
    @State private var minimumPeriodYearValue: Double = 0
    @State private var maximumPeriodYearValue: Double = 0
    @State private var selectedSalarySourceID: String?
    @State private var selectedSalaryPeriodID: String?
    @State private var sourceSortHistory = ListSortPersistence.load(
        defaultsKey: "SalarySourcesListSort",
        defaultValue: [SalarySourceListSortCriterion(column: .category, ascending: true)]
    )
    @State private var periodSortHistory = ListSortPersistence.load(
        defaultsKey: "SalaryPeriodsListSort",
        defaultValue: SalaryWorkspaceView.defaultSalaryPeriodSortHistory
    )
    @State private var autosaveTask: DispatchWorkItem?
    @State private var derivedDataRefreshTask: DispatchWorkItem?
    @State private var pendingAppearStartedAt: CFAbsoluteTime?
    @State private var sourceChoicesCache: [SourceChoice]
    @State private var filteredSortedPeriodIDsCache: [String]
    @State private var timelineEntriesCache: [TimelineEntry]
    @State private var timelineYearsCache: [Int]
    @State private var needsDerivedDataRefreshWhenActive = false
    @State private var forceVisiblePeriodIDs: Set<String> = []

    init(store: GrantDataStore, isActive: Bool, openApplicationAction: @escaping (String) -> Void) {
        self.store = store
        self.isActive = isActive
        self.openApplicationAction = openApplicationAction
        _sourcesDraft = State(initialValue: Self.makeEditableSources(store.salarySources))
        _periodsDraft = State(initialValue: Self.makeEditablePeriods(store.salaryCoveragePeriods))
        _selectedSalarySourceID = State(initialValue: store.salarySources.first?.id)
        _selectedSalaryPeriodID = State(initialValue: store.salaryCoveragePeriods.first?.id)
        _sourceChoicesCache = State(initialValue: [])
        _filteredSortedPeriodIDsCache = State(initialValue: [])
        _timelineEntriesCache = State(initialValue: [])
        _timelineYearsCache = State(initialValue: [])
    }

    struct SourceChoice: Identifiable {
        let id: String
        let label: String
        let subtitle: String?
        let tint: Color
    }

    struct TimelineEntry: Identifiable {
        let id: String
        let label: String
        let helpText: String
        let from: Date
        let to: Date
        let percentage: Double
        let percentageText: String
        let tint: Color
        let rowKey: String
        let rowOrder: Int
        let sourceReference: String
        let applicationID: String?
    }

    var body: some View {
        let language = store.language

        PersistentSplitView(layout: .salary) {
            salarySidebar(language: language)
        } detail: {
            salaryDetailPane(language: language)
        }
        .background(
            PerformanceReadyReporter {
                guard let pendingAppearStartedAt else { return }
                let duration = (CFAbsoluteTimeGetCurrent() - pendingAppearStartedAt) * 1000
                store.appendPerformanceDiagnostic(
                    String(format: "salary-view-ready ready_ms=%.2f", duration)
                )
            }
        )
        .onChange(of: sourcesDraft) { _, _ in
            normalizeEditableSources()
            ensureSalaryDetailSelection()
            scheduleDerivedDataRefreshIfActive(language: store.language)
            if isActive {
                scheduleAutosave()
            }
        }
        .onChange(of: periodsDraft) { _, _ in
            ensureSalaryDetailSelection()
            scheduleDerivedDataRefreshIfActive(language: store.language)
            if isActive {
                scheduleAutosave()
            }
        }
        .onChange(of: sourceSearchText) { _, _ in
            ensureSalaryDetailSelection()
        }
        .onChange(of: periodSearchText) { _, _ in
            ensureSalaryDetailSelection()
        }
        .onChange(of: store.metadata) { _, _ in
            let storeSources = store.salarySources
            let storePeriods = store.salaryCoveragePeriods
            let editableStoreSources = makeEditableSourcesPreservingPlaceholder(storeSources)
            if editableStoreSources != sourcesDraft {
                sourcesDraft = editableStoreSources
            }
            let editableStorePeriods = makeEditablePeriodsPreservingPlaceholder(storePeriods)
            if editableStorePeriods != periodsDraft {
                periodsDraft = editableStorePeriods
            }
            ensureSalaryDetailSelection()
            scheduleDerivedDataRefreshIfActive(language: store.language)
        }
        .onChange(of: store.applications) { _, _ in
            scheduleDerivedDataRefreshIfActive(language: store.language)
        }
        .onChange(of: store.language) { _, newLanguage in
            scheduleDerivedDataRefreshIfActive(language: newLanguage)
        }
        .onChange(of: isActive) { _, active in
            store.appendPerformanceDiagnostic(
                String(
                    format: "salary-active-changed active=%@ pending_refresh=%@",
                    active ? "yes" : "no",
                    needsDerivedDataRefreshWhenActive ? "yes" : "no"
                )
            )
            if active {
                guard needsDerivedDataRefreshWhenActive else { return }
                needsDerivedDataRefreshWhenActive = false
                scheduleDerivedDataRefresh(language: store.language)
                return
            }
            derivedDataRefreshTask?.cancel()
            persistChanges()
        }
        .onAppear {
            pendingAppearStartedAt = CFAbsoluteTimeGetCurrent()
            store.appendPerformanceDiagnostic("salary-view appear")
            ensureSalaryDetailSelection()
            if isActive {
                refreshDerivedData(language: store.language)
                normalizeDefaultSalaryPeriodSortIfNeeded()
            } else {
                needsDerivedDataRefreshWhenActive = true
            }
        }
        .onDisappear {
            derivedDataRefreshTask?.cancel()
            autosaveTask?.cancel()
            persistChanges()
        }
    }

    @ViewBuilder
    private func salarySidebar(language: AppLanguage) -> some View {
        let sourceRows = filteredSalarySources(language: language)
        let periodRows = filteredSalaryPeriods(language: language)

        AppWorkspaceSidebar {
            VStack(alignment: .leading, spacing: 12) {
                AppWorkspaceSidebarHeader(title: language.text("Salary planning", "Löneplanering"))
                    .frame(minHeight: 42)

                VStack(alignment: .leading, spacing: 14) {
                    salarySidebarSection(
                        title: language.text("Salary sources", "Lönekällor"),
                        searchPlaceholder: language.text("Search salary sources", "Sök lönekällor"),
                        searchText: $sourceSearchText,
                        displayedCount: sourceRows.count,
                        totalCount: sourcesDraft.filter { !Self.isEmpty($0) }.count,
                        addAction: selectNewSalarySource,
                        language: language
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            salarySourceFilterRows(language: language)
                            salarySourceListTable(sourceRows, language: language)
                        }
                    }

                    salarySidebarSection(
                        title: language.text("Salary periods", "Löneperioder"),
                        searchPlaceholder: language.text("Search salary periods", "Sök löneperioder"),
                        searchText: $periodSearchText,
                        displayedCount: periodRows.count,
                        totalCount: periodsDraft.filter { !Self.isEmpty($0) }.count,
                        addAction: selectNewSalaryPeriod,
                        language: language
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            salaryPeriodFilterRows(language: language)
                            salaryPeriodListTable(periodRows, language: language)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private func salarySidebarSection<Rows: View>(
        title: String,
        searchPlaceholder: String,
        searchText: Binding<String>,
        displayedCount: Int,
        totalCount: Int,
        addAction: @escaping () -> Void,
        language: AppLanguage,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .appTypography(.panelTitle)
                Spacer(minLength: 0)
                Button(language.text("Add", "Lägg till")) {
                    addAction()
                }
                .appAddButtonStyle()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }

            AppFilterCard {
                AppFilterRow(
                    showsClearButton: searchText.wrappedValue.nonEmpty != nil,
                    clearAction: { searchText.wrappedValue = "" }
                ) {
                    AppSidebarSearchField(placeholder: searchPlaceholder, text: searchText)
                }
            }

            rows()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            ListCountFootnote(displayedCount: displayedCount, totalCount: totalCount, language: language)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func salarySourceListTable(_ sources: [SalarySource], language: AppLanguage) -> some View {
        let categoryWidth: CGFloat = 88
        let projectWidth: CGFloat = 178
        let numberWidth: CGFloat = 94
        let tableMinWidth = categoryWidth + projectWidth + numberWidth

        AppListTable(contentMinWidth: tableMinWidth) {
            HStack(spacing: 0) {
                salarySourceListHeader(language.text("Category", "Kategori"), width: categoryWidth, column: .category)
                salarySourceListHeader(language.text("Project", "Projekt"), width: projectWidth, column: .project)
                salarySourceListHeader(language.text("No.", "Nr"), width: numberWidth, column: .projectNumber)
            }
        } rows: {
            SalarySourceResultsTable(
                sources: sources,
                selectedID: selectedSalarySourceID,
                language: language,
                tableMinWidth: tableMinWidth,
                categoryWidth: categoryWidth,
                projectWidth: projectWidth,
                numberWidth: numberWidth,
                localizedCategory: { language.localizedSalarySourceCategory($0) },
                localizedProject: { localizedProjectName(for: $0, language: language) },
                onSelect: { selectedSalarySourceID = $0 }
            )
        }
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    @ViewBuilder
    private func salarySourceFilterRows(language: AppLanguage) -> some View {
        AppFilterCard {
            VStack(alignment: .leading, spacing: 8) {
                AppFilterRow(
                    showsClearButton: !selectedSourceCategoryFilters.isEmpty,
                    clearAction: { selectedSourceCategoryFilters.removeAll() }
                ) {
                    MultiSelectFilterMenu(
                        title: language.text("Remove filter", "Ta bort filter"),
                        emptyLabel: language.text("All categories", "Alla kategorier"),
                        options: SalarySourceCategory.allCases.map(\.rawValue),
                        selectedOptions: Binding(
                            get: { Set(selectedSourceCategoryFilters.map(\.rawValue)) },
                            set: { selectedSourceCategoryFilters = Set($0.compactMap(SalarySourceCategory.init(rawValue:))) }
                        ),
                        display: { raw in
                            SalarySourceCategory(rawValue: raw).map { language.localizedSalarySourceCategory($0) } ?? raw
                        },
                        popoverWidth: 220
                    )
                }

                AppFilterRow(
                    showsClearButton: !selectedSourceProjectFilters.isEmpty,
                    clearAction: { selectedSourceProjectFilters.removeAll() }
                ) {
                    MultiSelectFilterMenu(
                        title: language.text("Remove filter", "Ta bort filter"),
                        emptyLabel: language.text("All projects", "Alla projekt"),
                        options: sourceProjectFilterOptions(language: language),
                        selectedOptions: $selectedSourceProjectFilters,
                        popoverWidth: 280
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func salaryPeriodFilterRows(language: AppLanguage) -> some View {
        let bounds = periodYearBounds
        AppFilterCard {
            VStack(alignment: .leading, spacing: 8) {
                AppFilterRow(
                    showsClearButton: periodYearFilterIsActive,
                    clearAction: { resetPeriodYearFilter() }
                ) {
                    AppFilterRangeControl(
                        title: periodYearRangeText(language: language),
                        lowerValue: periodMinimumYearBinding,
                        upperValue: periodMaximumYearBinding,
                        bounds: bounds,
                        unavailableText: language.text("Only one year available", "Endast ett år tillgängligt")
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func salaryPeriodListTable(_ periods: [SalaryCoveragePeriod], language: AppLanguage) -> some View {
        let sourceWidth: CGFloat = 160
        let fromWidth: CGFloat = 78
        let toWidth: CGFloat = 78
        let percentageWidth: CGFloat = 44
        let tableMinWidth = sourceWidth + fromWidth + toWidth + percentageWidth

        AppListTable(contentMinWidth: tableMinWidth) {
            HStack(spacing: 0) {
                salaryPeriodListHeader(language.text("Source", "Källa"), width: sourceWidth, column: .source)
                salaryPeriodListHeader(language.text("From", "Från"), width: fromWidth, column: .from)
                salaryPeriodListHeader(language.text("To", "Till"), width: toWidth, column: .to)
                salaryPeriodListHeader(language.text("Share", "Andel"), width: percentageWidth, column: .percentage)
            }
        } rows: {
            SalaryPeriodResultsTable(
                periods: periods,
                selectedID: selectedSalaryPeriodID,
                tableMinWidth: tableMinWidth,
                sourceWidth: sourceWidth,
                fromWidth: fromWidth,
                toWidth: toWidth,
                percentageWidth: percentageWidth,
                sourceLabel: { sourceLabel(for: $0.sourceReference, language: language) },
                onSelect: { selectedSalaryPeriodID = $0 }
            )
        }
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private func salarySourceListHeader(_ title: String, width: CGFloat, column: SalarySourceListSortColumn) -> some View {
        let criterion = sourceSortHistory.first(where: { $0.column == column })
        let sortIndex = sourceSortHistory.firstIndex(where: { $0.column == column })
        return AppSortableListHeader(
            title: title,
            ascending: criterion?.ascending,
            sortIndex: sortIndex,
            width: width,
            resetTitle: store.language.text("Reset", "Återställ"),
            onToggle: { toggleSalarySourceSort(column) },
            onReset: resetSalarySourceSort
        )
    }

    private func salaryPeriodListHeader(_ title: String, width: CGFloat, column: SalaryPeriodListSortColumn) -> some View {
        let criterion = periodSortHistory.first(where: { $0.column == column })
        let sortIndex = periodSortHistory.firstIndex(where: { $0.column == column })
        return AppSortableListHeader(
            title: title,
            ascending: criterion?.ascending,
            sortIndex: sortIndex,
            width: width,
            resetTitle: store.language.text("Reset", "Återställ"),
            onToggle: { toggleSalaryPeriodSort(column) },
            onReset: resetSalaryPeriodSort
        )
    }

    private func salarySidebarListCell(_ text: String, width: CGFloat) -> some View {
        Text(text.isEmpty ? "–" : text)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private func salaryDetailPane(language: AppLanguage) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(language.text("Salary planning", "Löneplanering"))
                            .appTypography(.pageTitle)
                        Spacer()
                        Button(language.text("Export Excel", "Exportera Excel")) {
                            store.exportSalaryCoverageWorkbookToDefaultLocation()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    salarySelectedDetailForm(language: language)
                    Spacer(minLength: 24)
                    timelineSection(language: language)
                }
                .padding(14)
                .frame(minHeight: max(0, geometry.size.height - 28), alignment: .top)
            }
        }
    }

    @ViewBuilder
    private func salarySelectedDetailForm(language: AppLanguage) -> some View {
        HStack(alignment: .top, spacing: 24) {
            Group {
                if let selectedSalarySourceID {
                    salarySourceDetailForm(source: sourceBinding(for: selectedSalarySourceID), language: language)
                } else {
                    DetailGroup(title: language.text("Salary source", "Lönekälla"), showsSurface: false) {
                        Text(language.text("Select a salary source.", "Markera en lönekälla."))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Group {
                if let selectedSalaryPeriodID {
                    salaryPeriodDetailForm(period: periodBinding(for: selectedSalaryPeriodID), language: language)
                } else {
                    DetailGroup(title: language.text("Salary period", "Löneperiod"), showsSurface: false) {
                        Text(language.text("Select a salary period.", "Markera en löneperiod."))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func salarySourceDetailForm(source: Binding<SalarySource>, language: AppLanguage) -> some View {
        let isNew = Self.isEmpty(source.wrappedValue)
        DetailGroup(title: isNew ? language.text("New salary source", "Ny lönekälla") : language.text("Salary source", "Lönekälla"), showsSurface: false) {
            VStack(alignment: .leading, spacing: 12) {
                salaryFormRow(language.text("Category", "Kategori")) {
                    AppMenuSelectionField(
                        selection: source.category,
                        options: SalarySourceCategory.allCases.map { (language.localizedSalarySourceCategory($0), $0) },
                        placeholder: nil
                    )
                    .frame(width: 240)
                }

                // Round 7: the colour in the salary plan is chosen here
                // instead of being decided by the source's name.
                salaryFormRow(language.text("Color", "Färg")) {
                    AppMenuSelectionField(
                        selection: Binding(
                            get: { source.wrappedValue.effectiveColor },
                            set: { source.wrappedValue.color = $0.rawValue }
                        ),
                        options: SalarySourceColor.allCases.map { ($0.localizedName(language: language), $0) },
                        placeholder: nil
                    )
                    .frame(width: 240)
                }

                salaryFormRow(language.text("Project", "Projekt")) {
                    CommitFormattingTextField(
                        placeholder: language.text("Project", "Projekt"),
                        text: localizedProjectBinding(for: source, language: language),
                        formatter: { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
                        updatesContinuously: false
                    )
                    .appTextInputChrome()
                }

                salaryFormRow(language.text("Project number", "Projektnummer")) {
                    CommitFormattingTextField(
                        placeholder: language.text("Project number", "Projektnummer"),
                        text: Binding(
                            get: { source.wrappedValue.projectNumber ?? "" },
                            set: { source.wrappedValue.projectNumber = $0.trimmedOrNil }
                        ),
                        formatter: { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
                        updatesContinuously: false
                    )
                    .appTextInputChrome()
                }

                salaryFormRow("PEOE") {
                    CommitFormattingTextField(
                        placeholder: "PEOE",
                        text: Binding(
                            get: { source.wrappedValue.peoe ?? "" },
                            set: { source.wrappedValue.peoe = $0.trimmedOrNil }
                        ),
                        formatter: { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
                        updatesContinuously: false
                    )
                    .appTextInputChrome()
                }

                if !isNew {
                    HStack {
                        Spacer()
                        inlineSalaryTrashButton {
                            sourcesDraft.removeAll { $0.id == source.wrappedValue.id }
                            ensureSalaryDetailSelection()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func salaryPeriodDetailForm(period: Binding<SalaryCoveragePeriod>, language: AppLanguage) -> some View {
        let isNew = Self.isEmpty(period.wrappedValue)
        DetailGroup(title: isNew ? language.text("New salary period", "Ny löneperiod") : language.text("Salary period", "Löneperiod"), showsSurface: false) {
            VStack(alignment: .leading, spacing: 12) {
                salaryFormRow(language.text("Salary source", "Lönekälla")) {
                    HStack(spacing: 8) {
                        AutocompleteSelectionField(
                            text: sourceReferenceTextBinding(for: period, language: language),
                            options: sourceChoicesCache.map(\.id),
                            placeholder: language.text("Select source", "Välj lönekälla"),
                            display: { sourceChoiceLabel(for: $0, language: language) },
                            onCommit: {},
                            onSelect: { selectedID in
                                period.wrappedValue.sourceReference = selectedID
                            },
                            showsSuggestionsWithoutQuery: true
                        )
                        salaryPeriodSourceLink(period: period.wrappedValue, language: language)
                    }
                }

                salaryFormRow(language.text("From", "Från")) {
                    CommitDateFieldWithTodayButton(
                        placeholder: language.datePlaceholder,
                        text: Binding(
                            get: { period.wrappedValue.from },
                            set: { newValue in
                                let previousFrom = period.wrappedValue.from
                                period.wrappedValue.from = newValue
                                if let shiftedTo = shiftedDateRangeEnd(
                                    previousStart: previousFrom,
                                    newStart: newValue,
                                    currentEnd: period.wrappedValue.to
                                ) {
                                    period.wrappedValue.to = shiftedTo
                                }
                            }
                        ),
                        formatter: normalizeSalaryDateInput,
                        updatesContinuously: false,
                        width: 140,
                        showsCalendarPicker: true,
                        language: language
                    )
                }

                salaryFormRow(language.text("To", "Till")) {
                    CommitDateFieldWithTodayButton(
                        placeholder: language.datePlaceholder,
                        text: Binding(
                            get: { period.wrappedValue.to },
                            set: { period.wrappedValue.to = $0 }
                        ),
                        formatter: normalizeSalaryDateInput,
                        updatesContinuously: false,
                        width: 140,
                        showsCalendarPicker: true,
                        language: language
                    )
                }

                salaryFormRow(language.text("Share", "Andel")) {
                    CommitFormattingTextField(
                        placeholder: "%",
                        text: Binding(
                            get: { period.wrappedValue.percentage },
                            set: { period.wrappedValue.percentage = $0 }
                        ),
                        formatter: formatPercentageInput,
                        showsRenewedSurface: false,
                        isBordered: false
                    )
                    .appTextInputChrome(fillsWidth: false)
                    .frame(width: 120)
                }

                if !isNew {
                    HStack {
                        Spacer()
                        inlineSalaryTrashButton {
                            forceVisiblePeriodIDs.remove(period.wrappedValue.id)
                            periodsDraft.removeAll { $0.id == period.wrappedValue.id }
                            ensureSalaryDetailSelection()
                        }
                    }
                }
            }
        }
    }

    private func salaryFormField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            AppFieldLabelText(text: title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func salaryFormRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            AppFieldLabelText(text: title)
                .frame(width: 150, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func sourcesSection(language: AppLanguage) -> some View {
        DetailGroup(title: language.text("Salary sources", "Lönekällor"), showsSurface: false) {
            VStack(alignment: .leading, spacing: 6) {
                salarySourceHeader(language: language)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach($sourcesDraft) { $source in
                            salarySourceRow(source: $source, language: language)
                        }
                    }
                }
                .frame(height: 260)
            }
        }
    }

    @ViewBuilder
    private func periodsSection(language: AppLanguage) -> some View {
        DetailGroup(title: language.text("Salary periods", "Löneperioder"), showsSurface: false) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    headerLabel(language.text("Source", "Lönekälla"), width: 320)
                    headerLabel(language.text("From", "Från"), width: 120)
                    headerLabel(language.text("To", "Till"), width: 120)
                    headerLabel(language.text("Share", "Andel"), width: 90)
                    Spacer()
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(filteredSortedPeriodIDsCache, id: \.self) { id in
                            salaryPeriodRow(period: periodBinding(for: id), language: language)
                        }
                    }
                }
                .frame(height: 320)
            }
        }
    }

    @ViewBuilder
    private func timelineSection(language: AppLanguage) -> some View {
        DetailGroup(title: language.text("Salary plan", "Löneplan"), showsSurface: false) {
            SalaryCoverageTimelineView(
                entries: timelineEntriesCache,
                years: timelineYearsCache,
                language: language,
                onPeriodSelect: { periodID in
                    selectedSalaryPeriodID = periodID
                }
            )
        }
    }

    @ViewBuilder
    private func salarySourceRow(source: Binding<SalarySource>, language: AppLanguage) -> some View {
        let isPlaceholder = Self.isEmpty(source.wrappedValue)

        HStack(spacing: 10) {
            if AppRuntime.usesRenewedChrome {
                AppMenuSelectionField(
                    selection: source.category,
                    options: SalarySourceCategory.allCases.map { (language.localizedSalarySourceCategory($0), $0) },
                    placeholder: nil
                )
                .frame(width: 150)
            } else {
                Picker("", selection: source.category) {
                    ForEach(SalarySourceCategory.allCases, id: \.self) { category in
                        Text(language.localizedSalarySourceCategory(category)).tag(category)
                    }
                }
                .pickerStyle(.menu)
                .formKeyboardNavigable()
                .frame(width: 150)
            }

            Group {
                CommitFormattingTextField(
                    placeholder: language.text("Project", "Projekt"),
                    text: localizedProjectBinding(for: source, language: language),
                    formatter: { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
                    updatesContinuously: false
                )
                .appTextInputChrome()
            }
            .frame(width: 150)

            Group {
                CommitFormattingTextField(
                    placeholder: language.text("Project number", "Projektnummer"),
                    text: Binding(
                        get: { source.wrappedValue.projectNumber ?? "" },
                        set: { source.wrappedValue.projectNumber = $0.trimmedOrNil }
                    ),
                    formatter: { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
                    updatesContinuously: false
                )
                .appTextInputChrome()
            }
            .frame(width: 150)

            Group {
                CommitFormattingTextField(
                    placeholder: "PEOE",
                    text: Binding(
                        get: { source.wrappedValue.peoe ?? "" },
                        set: { source.wrappedValue.peoe = $0.trimmedOrNil }
                    ),
                    formatter: { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
                    updatesContinuously: false
                )
                .appTextInputChrome()
            }
            .frame(width: 150)

            if isPlaceholder {
                Color.clear.frame(width: 28, height: 18)
            } else {
                inlineSalaryTrashButton {
                    sourcesDraft.removeAll { $0.id == source.wrappedValue.id }
                }
            }
        }
    }

    @ViewBuilder
    private func salaryPeriodRow(period: Binding<SalaryCoveragePeriod>, language: AppLanguage) -> some View {
        let isPlaceholder = Self.isEmpty(period.wrappedValue)

        HStack(spacing: 10) {
            AppMenuSelectionField(
                selection: Binding(
                    get: { period.wrappedValue.sourceReference },
                    set: { period.wrappedValue.sourceReference = $0 }
                ),
                options: sourceChoicesCache.map { ($0.label, $0.id) },
                placeholder: language.text("Select source", "Välj lönekälla")
            )
            .frame(width: 320)

            CommitDateFieldWithTodayButton(
                placeholder: language.datePlaceholder,
                text: Binding(
                    get: { period.wrappedValue.from },
                    set: { newValue in
                        let previousFrom = period.wrappedValue.from
                        period.wrappedValue.from = newValue
                        if let shiftedTo = shiftedDateRangeEnd(
                            previousStart: previousFrom,
                            newStart: newValue,
                            currentEnd: period.wrappedValue.to
                        ) {
                            period.wrappedValue.to = shiftedTo
                        }
                    }
                ),
                formatter: normalizeSalaryDateInput,
                updatesContinuously: false,
                width: 120
            )

            CommitDateFieldWithTodayButton(
                placeholder: language.datePlaceholder,
                text: Binding(
                    get: { period.wrappedValue.to },
                    set: { period.wrappedValue.to = $0 }
                ),
                formatter: normalizeSalaryDateInput,
                updatesContinuously: false,
                width: 120
            )

            CommitFormattingTextField(
                placeholder: "%",
                text: Binding(
                    get: { period.wrappedValue.percentage },
                    set: { period.wrappedValue.percentage = $0 }
                ),
                formatter: formatPercentageInput,
                showsRenewedSurface: false,
                isBordered: false
            )
            .frame(minHeight: 18)
            .appTextInputChrome(fillsWidth: false)
            .frame(width: 90)

            if isPlaceholder {
                Color.clear.frame(width: 28, height: 18)
            } else {
                inlineSalaryTrashButton {
                    forceVisiblePeriodIDs.remove(period.wrappedValue.id)
                    periodsDraft.removeAll { $0.id == period.wrappedValue.id }
                }
            }
        }
    }

    private func salarySourceHeader(language: AppLanguage) -> some View {
        HStack(spacing: 10) {
            headerLabel(language.text("Category", "Kategori"), width: 150)
            headerLabel(language.text("Project", "Projekt"), width: 150)
            headerLabel(language.text("Project number", "Projektnummer"), width: 150)
            headerLabel("PEOE", width: 150)
            Spacer()
        }
    }

    private func headerLabel(_ text: String, width: CGFloat?) -> some View {
        AppTableHeaderText(text: text)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : width, alignment: .leading)
    }

    private func inlineSalaryTrashButton(action: @escaping () -> Void) -> some View {
        AppIconDeleteButton(
            title: store.language.text("Delete", "Ta bort"),
            font: .system(size: 12, weight: .semibold),
            width: 28,
            action: action
        )
    }

    private func persistChanges() {
        autosaveTask?.cancel()
        let realDraftSources = sourcesDraft.filter { !Self.isEmpty($0) }
        let editableSources = makeEditableSourcesPreservingPlaceholder(realDraftSources)
        if sourcesDraft != editableSources {
            sourcesDraft = editableSources
        }
        let realDraftPeriods = periodsDraft.filter { !Self.isEmpty($0) }
        let sortedDraftPeriods = sortedPeriods(realDraftPeriods, language: store.language)
        let editablePeriods = makeEditablePeriodsPreservingPlaceholder(sortedDraftPeriods)
        if periodsDraft != editablePeriods {
            periodsDraft = editablePeriods
        }
        let normalizedSources = realDraftSources
            .map { source in
                var normalized = SalarySource(
                    id: source.id,
                    category: source.category,
                    project: source.project.trimmingCharacters(in: .whitespacesAndNewlines),
                    projectSv: source.projectSv?.trimmedOrNil,
                    projectEn: source.projectEn?.trimmedOrNil,
                    projectNumber: source.projectNumber?.trimmedOrNil,
                    peoe: source.peoe?.trimmedOrNil
                )
                // Round 7: the chosen colour is kept as stored.
                normalized.color = source.color?.trimmedOrNil
                return normalized
            }
            .filter { !$0.project.isEmpty }

        let normalizedPeriods = sortedDraftPeriods
            .map {
                SalaryCoveragePeriod(
                    id: $0.id,
                    sourceReference: $0.sourceReference.trimmingCharacters(in: .whitespacesAndNewlines),
                    from: normalizeSalaryDateInput($0.from),
                    to: normalizeSalaryDateInput($0.to),
                    percentage: formatPercentageInput($0.percentage)
                )
            }
            .filter { $0.sourceReference.nonEmpty != nil || $0.from.nonEmpty != nil || $0.to.nonEmpty != nil || $0.percentage.nonEmpty != nil }

        guard normalizedSources != store.salarySources || normalizedPeriods != store.salaryCoveragePeriods else { return }
        store.updateSalaryWorkspace(sources: normalizedSources, periods: normalizedPeriods)
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard isActive else { return }
        let task = DispatchWorkItem { persistChanges() }
        autosaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: task)
    }

    private func scheduleDerivedDataRefreshIfActive(language: AppLanguage) {
        guard isActive else {
            needsDerivedDataRefreshWhenActive = true
            return
        }
        scheduleDerivedDataRefresh(language: language)
    }

    private func scheduleDerivedDataRefresh(language: AppLanguage) {
        derivedDataRefreshTask?.cancel()
        guard isActive else {
            needsDerivedDataRefreshWhenActive = true
            return
        }
        let task = DispatchWorkItem {
            refreshDerivedData(language: language)
        }
        derivedDataRefreshTask = task
        DispatchQueue.main.async(execute: task)
    }

    private func refreshDerivedData(language: AppLanguage) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        sourceChoicesCache = sourceChoices(language: language)
        filteredSortedPeriodIDsCache = filteredSortedPeriodIDs
        let entries = timelineEntries(language: language)
        timelineEntriesCache = entries
        let currentYear = Calendar.current.component(.year, from: Date())
        let minYear = entries.map { Calendar.current.component(.year, from: $0.from) }.min() ?? currentYear
        let maxYear = entries.map { Calendar.current.component(.year, from: $0.to) }.max() ?? currentYear
        timelineYearsCache = Array(minYear...max(maxYear, currentYear))
        let refreshDuration = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        store.appendPerformanceDiagnostic(
            String(
                format: "salary-derived-ready rows=%ld entries=%ld years=%ld refresh_ms=%.2f",
                filteredSortedPeriodIDsCache.count,
                timelineEntriesCache.count,
                timelineYearsCache.count,
                refreshDuration
            )
        )
    }

    private var sortedPeriodIDs: [String] {
        sortedPeriods(periodsDraft, language: store.language).map(\.id)
    }

    private var filteredSortedPeriodIDs: [String] {
        let realPeriods = periodsDraft.filter { !Self.isEmpty($0) }
        let visiblePeriods = realPeriods.filter { period in
            salaryCoveragePeriodOverlapsCurrentYearOrLater(period)
                || forceVisiblePeriodIDs.contains(period.id)
        }
        let pinnedPeriodIDs = realPeriods
            .filter { period in
                visiblePeriods.contains(where: { $0.id == period.id })
                    && !salaryCoveragePeriodIsComplete(period)
            }
            .map(\.id)
        let pinnedIDSet = Set(pinnedPeriodIDs)
        let sortedVisibleIDs = sortedPeriods(
            visiblePeriods.filter { !pinnedIDSet.contains($0.id) },
            language: store.language
        )
        .map(\.id)
        let placeholderID = periodsDraft.first(where: { Self.isEmpty($0) })?.id ?? SalaryCoveragePeriod().id
        return sortedVisibleIDs + pinnedPeriodIDs + [placeholderID]
    }

    private func filteredSalarySources(language: AppLanguage) -> [SalarySource] {
        let query = sourceSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = sourcesDraft
            .filter { !Self.isEmpty($0) }
            .filter { source in
                guard query.nonEmpty != nil else { return true }
                return salaryMatches(
                    query: query,
                    fields: [
                        localizedProjectName(for: source, language: language),
                        language.localizedSalarySourceCategory(source.category),
                        source.project,
                        source.projectSv,
                        source.projectEn,
                        source.projectNumber,
                        source.peoe
                    ]
                )
            }
            .filter { selectedSourceCategoryFilters.isEmpty || selectedSourceCategoryFilters.contains($0.category) }
            .filter {
                selectedSourceProjectFilters.isEmpty
                    || selectedSourceProjectFilters.contains(localizedProjectName(for: $0, language: language))
            }
        return sortedSalarySources(filtered, language: language)
    }

    private func filteredSalaryPeriods(language: AppLanguage) -> [SalaryCoveragePeriod] {
        let query = periodSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let yearBounds = normalizedPeriodYearFilterBounds
        let filtered = filteredSortedPeriodIDsCache
            .compactMap { id in periodsDraft.first(where: { $0.id == id }) }
            .filter { !Self.isEmpty($0) }
            .filter { period in
                guard query.nonEmpty != nil else { return true }
                return salaryMatches(
                    query: query,
                    fields: [
                        sourceLabel(for: period.sourceReference, language: language),
                        period.from,
                        period.to,
                        period.percentage
                    ]
                )
            }
            .filter { salaryPeriod($0, overlapsYearBounds: yearBounds) }
        return sortedSalaryPeriodsForList(filtered, language: language)
    }

    private func sourceProjectFilterOptions(language: AppLanguage) -> [String] {
        Array(
            Set(
                sourcesDraft
                    .filter { !Self.isEmpty($0) }
                    .map { localizedProjectName(for: $0, language: language) }
                    .filter { $0.trimmedOrNil != nil }
            )
        )
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var periodYearBounds: ClosedRange<Double> {
        let years = periodsDraft
            .filter { !Self.isEmpty($0) }
            .flatMap { period -> [Int] in
                [
                    DateParsers.isoDay.date(from: normalizeSalaryDateInput(period.from)),
                    DateParsers.isoDay.date(from: normalizeSalaryDateInput(period.to))
                ]
                .compactMap { $0 }
                .map { Calendar.current.component(.year, from: $0) }
            }
        guard let minYear = years.min(), let maxYear = years.max() else {
            let current = Calendar.current.component(.year, from: Date())
            return Double(current)...Double(current)
        }
        return Double(minYear)...Double(maxYear)
    }

    private var normalizedPeriodYearFilterBounds: ClosedRange<Double> {
        let bounds = periodYearBounds
        let defaultBounds = defaultPeriodYearFilterBounds
        let lower = minimumPeriodYearValue == 0 ? defaultBounds.lowerBound : min(max(minimumPeriodYearValue, bounds.lowerBound), bounds.upperBound)
        let upper = maximumPeriodYearValue == 0 ? bounds.upperBound : min(max(maximumPeriodYearValue, bounds.lowerBound), bounds.upperBound)
        return min(lower, upper)...max(lower, upper)
    }

    private var periodYearFilterIsActive: Bool {
        let bounds = defaultPeriodYearFilterBounds
        let active = normalizedPeriodYearFilterBounds
        return active.lowerBound != bounds.lowerBound || active.upperBound != bounds.upperBound
    }

    private var periodMinimumYearBinding: Binding<Double> {
        Binding(
            get: { normalizedPeriodYearFilterBounds.lowerBound },
            set: { minimumPeriodYearValue = min($0, normalizedPeriodYearFilterBounds.upperBound) }
        )
    }

    private var periodMaximumYearBinding: Binding<Double> {
        Binding(
            get: { normalizedPeriodYearFilterBounds.upperBound },
            set: { maximumPeriodYearValue = max($0, normalizedPeriodYearFilterBounds.lowerBound) }
        )
    }

    private func periodYearRangeText(language: AppLanguage) -> String {
        let active = normalizedPeriodYearFilterBounds
        let lower = Int(active.lowerBound.rounded())
        let upper = Int(active.upperBound.rounded())
        return "\(language.text("Year", "År")): \(lower)–\(upper)"
    }

    private func resetPeriodYearFilter() {
        let bounds = defaultPeriodYearFilterBounds
        minimumPeriodYearValue = bounds.lowerBound
        maximumPeriodYearValue = bounds.upperBound
    }

    private var defaultPeriodYearFilterBounds: ClosedRange<Double> {
        let bounds = periodYearBounds
        let currentYear = Double(Calendar.current.component(.year, from: Date()))
        let lower = min(max(currentYear, bounds.lowerBound), bounds.upperBound)
        return lower...bounds.upperBound
    }

    private func salaryCoveragePeriodOverlapsCurrentYearOrLater(_ period: SalaryCoveragePeriod) -> Bool {
        guard salaryCoveragePeriodIsComplete(period) else {
            return true
        }
        let currentYear = Calendar.current.component(.year, from: Date())
        guard let currentYearStart = Calendar.current.date(from: DateComponents(year: currentYear, month: 1, day: 1)) else {
            return true
        }
        let from = DateParsers.isoDay.date(from: normalizeSalaryDateInput(period.from))
        let to = DateParsers.isoDay.date(from: normalizeSalaryDateInput(period.to))
        return (to ?? from ?? .distantFuture) >= currentYearStart
    }

    private func salaryPeriod(_ period: SalaryCoveragePeriod, overlapsYearBounds bounds: ClosedRange<Double>) -> Bool {
        let calendar = Calendar.current
        let fromYear = DateParsers.isoDay
            .date(from: normalizeSalaryDateInput(period.from))
            .map { Double(calendar.component(.year, from: $0)) }
        let toYear = DateParsers.isoDay
            .date(from: normalizeSalaryDateInput(period.to))
            .map { Double(calendar.component(.year, from: $0)) }
        let lower = fromYear ?? toYear ?? bounds.lowerBound
        let upper = toYear ?? fromYear ?? bounds.upperBound
        return min(lower, upper) <= bounds.upperBound && max(lower, upper) >= bounds.lowerBound
    }

    private func sortedSalarySources(_ sources: [SalarySource], language: AppLanguage) -> [SalarySource] {
        sources.sorted { lhs, rhs in
            for criterion in sourceSortHistory {
                let comparison = compareSalarySources(lhs, rhs, column: criterion.column, language: language)
                if comparison != .orderedSame {
                    return criterion.ascending ? comparison == .orderedAscending : comparison == .orderedDescending
                }
            }

            return localizedProjectName(for: lhs, language: language).localizedStandardCompare(localizedProjectName(for: rhs, language: language)) == .orderedAscending
        }
    }

    private func compareSalarySources(
        _ lhs: SalarySource,
        _ rhs: SalarySource,
        column: SalarySourceListSortColumn,
        language: AppLanguage
    ) -> ComparisonResult {
        switch column {
        case .category:
            let lhsOrder = sourceOrder(forCategory: lhs.category)
            let rhsOrder = sourceOrder(forCategory: rhs.category)
            if lhsOrder < rhsOrder { return .orderedAscending }
            if lhsOrder > rhsOrder { return .orderedDescending }
            return localizedProjectName(for: lhs, language: language).localizedStandardCompare(localizedProjectName(for: rhs, language: language))
        case .project:
            return localizedProjectName(for: lhs, language: language).localizedStandardCompare(localizedProjectName(for: rhs, language: language))
        case .projectNumber:
            return (lhs.projectNumber ?? "").localizedStandardCompare(rhs.projectNumber ?? "")
        }
    }

    private func sortedSalaryPeriodsForList(_ periods: [SalaryCoveragePeriod], language: AppLanguage) -> [SalaryCoveragePeriod] {
        periods.sorted { lhs, rhs in
            for criterion in periodSortHistory {
                let comparison = compareSalaryPeriods(lhs, rhs, column: criterion.column, language: language)
                if comparison != .orderedSame {
                    return criterion.ascending ? comparison == .orderedAscending : comparison == .orderedDescending
                }
            }

            return sortedPeriods([lhs, rhs], language: language).first?.id == lhs.id
        }
    }

    private func compareSalaryPeriods(
        _ lhs: SalaryCoveragePeriod,
        _ rhs: SalaryCoveragePeriod,
        column: SalaryPeriodListSortColumn,
        language: AppLanguage
    ) -> ComparisonResult {
        switch column {
        case .source:
            return sourceLabel(for: lhs.sourceReference, language: language).localizedStandardCompare(sourceLabel(for: rhs.sourceReference, language: language))
        case .from:
            return compareSalaryDateStrings(lhs.from, rhs.from)
        case .to:
            return compareSalaryDateStrings(lhs.to, rhs.to)
        case .percentage:
            let lhsPercent = GrantParsing.numericValue(from: lhs.percentage) ?? 0
            let rhsPercent = GrantParsing.numericValue(from: rhs.percentage) ?? 0
            if lhsPercent < rhsPercent { return .orderedAscending }
            if lhsPercent > rhsPercent { return .orderedDescending }
            return .orderedSame
        }
    }

    private func compareSalaryDateStrings(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsDate = DateParsers.isoDay.date(from: normalizeSalaryDateInput(lhs)) ?? .distantFuture
        let rhsDate = DateParsers.isoDay.date(from: normalizeSalaryDateInput(rhs)) ?? .distantFuture
        if lhsDate < rhsDate { return .orderedAscending }
        if lhsDate > rhsDate { return .orderedDescending }
        return .orderedSame
    }

    private func toggleSalarySourceSort(_ column: SalarySourceListSortColumn) {
        if let existingIndex = sourceSortHistory.firstIndex(where: { $0.column == column }) {
            if existingIndex == 0 {
                sourceSortHistory[0].ascending.toggle()
            } else {
                let criterion = sourceSortHistory.remove(at: existingIndex)
                sourceSortHistory.insert(criterion, at: 0)
            }
        } else {
            sourceSortHistory.insert(SalarySourceListSortCriterion(column: column, ascending: column.defaultAscending), at: 0)
        }
        ListSortPersistence.save(sourceSortHistory, defaultsKey: "SalarySourcesListSort")
    }

    private func resetSalarySourceSort() {
        sourceSortHistory = [SalarySourceListSortCriterion(column: .category, ascending: true)]
        ListSortPersistence.save(sourceSortHistory, defaultsKey: "SalarySourcesListSort")
    }

    private func toggleSalaryPeriodSort(_ column: SalaryPeriodListSortColumn) {
        if let existingIndex = periodSortHistory.firstIndex(where: { $0.column == column }) {
            if existingIndex == 0 {
                periodSortHistory[0].ascending.toggle()
            } else {
                let criterion = periodSortHistory.remove(at: existingIndex)
                periodSortHistory.insert(criterion, at: 0)
            }
        } else {
            periodSortHistory.insert(SalaryPeriodListSortCriterion(column: column, ascending: column.defaultAscending), at: 0)
        }
        ListSortPersistence.save(periodSortHistory, defaultsKey: "SalaryPeriodsListSort")
    }

    private func resetSalaryPeriodSort() {
        periodSortHistory = Self.defaultSalaryPeriodSortHistory
        ListSortPersistence.save(periodSortHistory, defaultsKey: "SalaryPeriodsListSort")
    }

    private static var defaultSalaryPeriodSortHistory: [SalaryPeriodListSortCriterion] {
        [
            SalaryPeriodListSortCriterion(column: .from, ascending: false),
            SalaryPeriodListSortCriterion(column: .to, ascending: false)
        ]
    }

    private func normalizeDefaultSalaryPeriodSortIfNeeded() {
        guard periodSortHistory == [SalaryPeriodListSortCriterion(column: .from, ascending: true)] else { return }
        periodSortHistory = Self.defaultSalaryPeriodSortHistory
        ListSortPersistence.save(periodSortHistory, defaultsKey: "SalaryPeriodsListSort")
    }

    private func salaryMatches(query: String, fields: [String?]) -> Bool {
        let normalizedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return fields.contains { field in
            field?
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .contains(normalizedQuery) == true
        }
    }

    private func selectNewSalarySource() {
        let id: String
        if let placeholderID = sourcesDraft.first(where: { Self.isEmpty($0) })?.id {
            id = placeholderID
        } else {
            let source = SalarySource(category: .research, project: "")
            sourcesDraft.append(source)
            id = source.id
        }
        selectedSalarySourceID = id
    }

    private func selectNewSalaryPeriod() {
        let id: String
        if let placeholderID = periodsDraft.first(where: { Self.isEmpty($0) })?.id {
            id = placeholderID
        } else {
            let period = SalaryCoveragePeriod()
            periodsDraft.append(period)
            id = period.id
        }
        selectedSalaryPeriodID = id
    }

    private func ensureSalaryDetailSelection() {
        if let selectedSalarySourceID,
           !sourcesDraft.contains(where: { $0.id == selectedSalarySourceID }) {
            self.selectedSalarySourceID = nil
        }
        let language = store.language
        if selectedSalarySourceID == nil {
            selectedSalarySourceID = filteredSalarySources(language: language).first?.id
                ?? sourcesDraft.first(where: { Self.isEmpty($0) })?.id
        }

        if let selectedSalaryPeriodID,
           !periodsDraft.contains(where: { $0.id == selectedSalaryPeriodID }) {
            self.selectedSalaryPeriodID = nil
        }
        if selectedSalaryPeriodID == nil {
            selectedSalaryPeriodID = filteredSalaryPeriods(language: language).first?.id
                ?? periodsDraft.first(where: { Self.isEmpty($0) })?.id
        }
    }

    private func sourceBinding(for id: String) -> Binding<SalarySource> {
        Binding(
            get: {
                sourcesDraft.first(where: { $0.id == id }) ?? SalarySource(id: id, category: .research, project: "")
            },
            set: { updated in
                if let index = sourcesDraft.firstIndex(where: { $0.id == id }) {
                    sourcesDraft[index] = updated
                } else {
                    sourcesDraft.append(updated)
                }
            }
        )
    }

    private func periodBinding(for id: String) -> Binding<SalaryCoveragePeriod> {
        Binding(
            get: {
                periodsDraft.first(where: { $0.id == id }) ?? SalaryCoveragePeriod(id: id)
            },
            set: { updated in
                let wasPlaceholder = periodsDraft
                    .first(where: { $0.id == id })
                    .map(Self.isEmpty) ?? true
                if let index = periodsDraft.firstIndex(where: { $0.id == id }) {
                    periodsDraft[index] = updated
                } else {
                    periodsDraft.append(updated)
                }
                if Self.isEmpty(updated) {
                    forceVisiblePeriodIDs.remove(updated.id)
                } else if wasPlaceholder {
                    forceVisiblePeriodIDs.insert(updated.id)
                }
                periodsDraft = makeEditablePeriodsPreservingPlaceholder(periodsDraft.filter { !Self.isEmpty($0) })
            }
        )
    }

    private func sortedPeriods(_ periods: [SalaryCoveragePeriod], language: AppLanguage) -> [SalaryCoveragePeriod] {
        periods.sorted { lhs, rhs in
            let lhsStart = DateParsers.isoDay.date(from: normalizeSalaryDateInput(lhs.from)) ?? .distantFuture
            let rhsStart = DateParsers.isoDay.date(from: normalizeSalaryDateInput(rhs.from)) ?? .distantFuture
            if lhsStart != rhsStart { return lhsStart < rhsStart }

            let lhsEnd = DateParsers.isoDay.date(from: normalizeSalaryDateInput(lhs.to)) ?? .distantFuture
            let rhsEnd = DateParsers.isoDay.date(from: normalizeSalaryDateInput(rhs.to)) ?? .distantFuture
            if lhsEnd != rhsEnd { return lhsEnd < rhsEnd }

            let lhsPercent = GrantParsing.numericValue(from: lhs.percentage) ?? 0
            let rhsPercent = GrantParsing.numericValue(from: rhs.percentage) ?? 0
            if lhsPercent != rhsPercent { return lhsPercent > rhsPercent }

            return sourceLabel(for: lhs.sourceReference, language: language).localizedStandardCompare(sourceLabel(for: rhs.sourceReference, language: language)) == .orderedAscending
        }
    }

    private func makeEditablePeriodsPreservingPlaceholder(_ periods: [SalaryCoveragePeriod]) -> [SalaryCoveragePeriod] {
        Self.makeEditablePeriods(
            periods,
            placeholderID: periodsDraft.first(where: { Self.isEmpty($0) })?.id
        )
    }

    private static func makeEditablePeriods(_ periods: [SalaryCoveragePeriod], placeholderID: String? = nil) -> [SalaryCoveragePeriod] {
        let retainedPlaceholderID = periods.first(where: { isEmpty($0) })?.id ?? placeholderID ?? UUID().uuidString
        return periods.filter { !isEmpty($0) } + [SalaryCoveragePeriod(id: retainedPlaceholderID)]
    }

    private static func isEmpty(_ period: SalaryCoveragePeriod) -> Bool {
        period.sourceReference.trimmedOrNil == nil &&
        period.from.trimmedOrNil == nil &&
        period.to.trimmedOrNil == nil &&
        period.percentage.trimmedOrNil == nil
    }

    private func sourceChoices(language: AppLanguage) -> [SourceChoice] {
        let custom = sourcesDraft
            .filter { !Self.isEmpty($0) }
            .sorted {
                if sourceOrder(forCategory: $0.category) != sourceOrder(forCategory: $1.category) {
                    return sourceOrder(forCategory: $0.category) < sourceOrder(forCategory: $1.category)
                }
                return localizedProjectName(for: $0, language: language).localizedStandardCompare(localizedProjectName(for: $1, language: language)) == .orderedAscending
            }
            .map { source in
            SourceChoice(
                id: "custom:\(source.id)",
                label: localizedProjectName(for: source, language: language),
                subtitle: source.projectNumber,
                tint: tint(for: source)
            )
        }
        let grants = store.applications
            .filter(\.isGranted)
            .sorted { grantSourceLabel(for: $0, language: language).localizedStandardCompare(grantSourceLabel(for: $1, language: language)) == .orderedAscending }
            .map { application in
                SourceChoice(
                    id: "grant:\(application.id)",
                    label: grantSourceLabel(for: application, language: language),
                    subtitle: application.appliedCaseNumber,
                    tint: calendarLinkedSalaryTint(for: .activity3)
                )
            }
        return custom + grants
    }

    private func sourceLabel(for reference: String, language: AppLanguage) -> String {
        if reference.hasPrefix("custom:") {
            let id = String(reference.dropFirst("custom:".count))
            guard let source = sourcesDraft.first(where: { $0.id == id }) else {
                return language.text("Unknown source", "Okänd källa")
            }
            return localizedProjectName(for: source, language: language)
        }
        if reference.hasPrefix("grant:") {
            let id = String(reference.dropFirst("grant:".count))
            if let application = store.application(id: id) {
                return grantSourceLabel(for: application, language: language)
            }
        }
        return language.text("Unknown source", "Okänd källa")
    }

    private func sourceChoiceLabel(for id: String, language: AppLanguage) -> String {
        sourceChoicesCache.first(where: { $0.id == id })?.label ?? sourceLabel(for: id, language: language)
    }

    private func sourceReferenceTextBinding(for period: Binding<SalaryCoveragePeriod>, language: AppLanguage) -> Binding<String> {
        Binding(
            get: {
                period.wrappedValue.sourceReference.trimmedOrNil.map { sourceLabel(for: $0, language: language) } ?? ""
            },
            set: { newText in
                if let resolved = resolveSalarySourceReference(from: newText, language: language) {
                    period.wrappedValue.sourceReference = resolved
                } else if newText.trimmedOrNil == nil {
                    period.wrappedValue.sourceReference = ""
                }
            }
        )
    }

    private func resolveSalarySourceReference(from text: String, language: AppLanguage) -> String? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !normalized.isEmpty else { return nil }
        if let exact = sourceChoicesCache.first(where: {
            $0.label.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == normalized
        }) {
            return exact.id
        }
        if let exactID = sourceChoicesCache.first(where: { $0.id == text }) {
            return exactID.id
        }
        return sourceChoices(language: language).first(where: {
            $0.label.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == normalized
        })?.id
    }

    @ViewBuilder
    private func salaryPeriodSourceLink(period: SalaryCoveragePeriod, language: AppLanguage) -> some View {
        if period.sourceReference.hasPrefix("custom:") {
            let id = String(period.sourceReference.dropFirst("custom:".count))
            if sourcesDraft.contains(where: { $0.id == id }) {
                Button {
                    selectedSalarySourceID = id
                } label: {
                    AppLinkDestinationLabel(kind: .app, language: language, fontSize: 12, showsTitle: false)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppPalette.linkAction)
                .help(language.text("Open salary source", "Öppna lönekälla"))
            }
        } else if period.sourceReference.hasPrefix("grant:") {
            let id = String(period.sourceReference.dropFirst("grant:".count))
            if store.application(id: id) != nil {
                Button {
                    openApplicationAction(id)
                } label: {
                    AppLinkDestinationLabel(kind: .app, language: language, fontSize: 12, showsTitle: false)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppPalette.linkAction)
                .help(language.text("Open grant", "Öppna anslag"))
            }
        }
    }

    private func localizedProjectBinding(for source: Binding<SalarySource>, language: AppLanguage) -> Binding<String> {
        Binding(
            get: { localizedProjectName(for: source.wrappedValue, language: language) },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                source.wrappedValue.project = trimmed
                switch language {
                case .swedish:
                    source.wrappedValue.projectSv = trimmed
                case .english:
                    source.wrappedValue.projectEn = trimmed
                }
            }
        )
    }

    private func localizedProjectName(for source: SalarySource, language: AppLanguage) -> String {
        switch language {
        case .swedish:
            return source.projectSv?.nonEmpty
                ?? source.projectEn?.nonEmpty
                ?? source.project
        case .english:
            return source.projectEn?.nonEmpty
                ?? source.projectSv?.nonEmpty
                ?? source.project
        }
    }

    private func normalizeEditableSources() {
        let editableSources = makeEditableSourcesPreservingPlaceholder(sourcesDraft.filter { !Self.isEmpty($0) })
        guard editableSources != sourcesDraft else { return }
        sourcesDraft = editableSources
    }

    private func makeEditableSourcesPreservingPlaceholder(_ sources: [SalarySource]) -> [SalarySource] {
        Self.makeEditableSources(
            sources,
            placeholderID: sourcesDraft.first(where: { Self.isEmpty($0) })?.id
        )
    }

    private static func makeEditableSources(_ sources: [SalarySource], placeholderID: String? = nil) -> [SalarySource] {
        let retainedPlaceholderID = sources.first(where: { isEmpty($0) })?.id ?? placeholderID ?? UUID().uuidString
        return sources.filter { !isEmpty($0) } + [SalarySource(id: retainedPlaceholderID, category: .research, project: "")]
    }

    private static func isEmpty(_ source: SalarySource) -> Bool {
        source.project.trimmedOrNil == nil &&
        source.projectSv?.trimmedOrNil == nil &&
        source.projectEn?.trimmedOrNil == nil &&
        source.projectNumber?.trimmedOrNil == nil &&
        source.peoe?.trimmedOrNil == nil
    }

    private func grantSourceLabel(for application: GrantApplication, language: AppLanguage) -> String {
        let funder = store.organizationLabel(for: application, language: language)
        let project = application.projectType?.nonEmpty ?? language.text("No project", "Saknar projekt")
        let grantNumber = application.appliedCaseNumber?.nonEmpty ?? language.text("No number", "Saknar nummer")
        return "\(funder), \(project), \(grantNumber)"
    }

    private func sourceTint(for reference: String) -> Color {
        if reference.hasPrefix("custom:") {
            let id = String(reference.dropFirst("custom:".count))
            if let source = sourcesDraft.first(where: { $0.id == id }) {
                return tint(for: source)
            }
        }
        if let target = salaryCalendarColorTarget(forSourceReference: reference) {
            return calendarLinkedSalaryTint(for: target)
        }
        return AppPalette.chartGreen
    }

    private func sourceOrder(for reference: String) -> Int {
        if reference.hasPrefix("custom:") {
            let id = String(reference.dropFirst("custom:".count))
            if let source = sourcesDraft.first(where: { $0.id == id }) {
                return sourceOrder(forCategory: source.category)
            }
        }
        if reference.hasPrefix("grant:") {
            return 2
        }
        return 9
    }

    private func sourceOrder(forCategory category: SalarySourceCategory) -> Int {
        switch category {
        case .clinic: return 0
        case .teaching: return 1
        case .research: return 2
        case .other: return 3
        }
    }

    /// The source's colour in the salary plan: the colour chosen in the
    /// salary source editor (the calendar colours follow the settings).
    private func tint(for source: SalarySource) -> Color {
        if let target = salaryCalendarColorTarget(for: source) {
            return calendarLinkedSalaryTint(for: target)
        }
        switch source.effectiveColor {
        case .blue:
            return dynamicColor(
                light: NSColor(calibratedRed: 0.63, green: 0.82, blue: 0.93, alpha: 1),
                dark: NSColor(calibratedRed: 0.00, green: 0.31, blue: 0.59, alpha: 1),
                darkNew: NSColor(calibratedWhite: 102.0 / 255.0, alpha: 1)
            )
        case .red:
            return AppPalette.vividRed
        case .clinicCalendarCategory, .calendarActivity2, .calendarActivity3:
            return AppPalette.vividOrange
        }
    }

    private func calendarLinkedSalaryTint(for target: SalaryCalendarColorTarget) -> Color {
        switch target {
        case .clinicMeetingCategory:
            return calendarLinkedSalaryTint(
                lightHex: store.firstClinicalCalendarCategoryName.flatMap { store.calendarMeetingCategoryColorHex(named: $0, usesDarkAppearance: false) },
                darkHex: store.firstClinicalCalendarCategoryName.flatMap { store.calendarMeetingCategoryColorHex(named: $0, usesDarkAppearance: true) },
                fallback: AppPalette.vividOrange
            )
        case .activity2:
            return calendarLinkedSalaryTint(
                lightHex: store.calendarActivityColorHex(.activity2, usesDarkAppearance: false),
                darkHex: store.calendarActivityColorHex(.activity2, usesDarkAppearance: true),
                fallback: AppPalette.vividGreen
            )
        case .activity3:
            return calendarLinkedSalaryTint(
                lightHex: store.calendarActivityColorHex(.activity3, usesDarkAppearance: false),
                darkHex: store.calendarActivityColorHex(.activity3, usesDarkAppearance: true),
                fallback: AppPalette.vividOrange
            )
        }
    }

    private func calendarLinkedSalaryTint(lightHex: String?, darkHex: String?, fallback: Color) -> Color {
        guard let light = salaryPlanningNSColor(hex: lightHex),
              let dark = salaryPlanningNSColor(hex: darkHex ?? lightHex) else {
            return fallback
        }
        return dynamicColor(light: light, dark: dark)
    }

    private func salaryPlanningNSColor(hex: String?) -> NSColor? {
        guard let hex, hex.trimmedOrNil != nil else { return nil }
        let normalized = normalizedCalendarCategoryHexColor(hex)
        guard let value = Int(normalized.dropFirst(), radix: 16) else { return nil }
        return NSColor(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private func timelineEntries(language: AppLanguage) -> [TimelineEntry] {
        periodsDraft.compactMap { period in
            guard let from = DateParsers.isoDay.date(from: normalizeSalaryDateInput(period.from)),
                  let to = DateParsers.isoDay.date(from: normalizeSalaryDateInput(period.to)),
                  let percentage = GrantParsing.numericValue(from: period.percentage),
                  percentage > 0,
                  period.sourceReference.nonEmpty != nil else {
                return nil
            }
            let label = sourceLabel(for: period.sourceReference, language: language)
            let percentageText = formatPercentageInput(period.percentage)
            return TimelineEntry(
                id: period.id,
                label: label,
                helpText: "\(label), \(percentageText)\n\(normalizeSalaryDateInput(period.from)) – \(normalizeSalaryDateInput(period.to))",
                from: min(from, to),
                to: max(from, to),
                percentage: percentage,
                percentageText: percentageText,
                tint: sourceTint(for: period.sourceReference),
                rowKey: period.sourceReference,
                rowOrder: sourceOrder(for: period.sourceReference),
                sourceReference: period.sourceReference,
                applicationID: period.sourceReference.hasPrefix("grant:") ? String(period.sourceReference.dropFirst("grant:".count)) : nil
            )
        }
        .sorted { lhs, rhs in
            if lhs.rowOrder != rhs.rowOrder { return lhs.rowOrder < rhs.rowOrder }
            if lhs.rowKey != rhs.rowKey { return lhs.rowKey.localizedStandardCompare(rhs.rowKey) == .orderedAscending }
            if lhs.from != rhs.from { return lhs.from < rhs.from }
            return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
        }
    }

    private var timelineYears: [Int] {
        let entries = timelineEntries(language: store.language)
        let currentYear = Calendar.current.component(.year, from: Date())
        let minYear = entries.map { Calendar.current.component(.year, from: $0.from) }.min() ?? currentYear
        let maxYear = entries.map { Calendar.current.component(.year, from: $0.to) }.max() ?? currentYear
        return Array(minYear...max(maxYear, currentYear))
    }

}

private struct SalarySourceResultsTable: View {
    let sources: [SalarySource]
    let selectedID: String?
    let language: AppLanguage
    let tableMinWidth: CGFloat
    let categoryWidth: CGFloat
    let projectWidth: CGFloat
    let numberWidth: CGFloat
    let localizedCategory: (SalarySourceCategory) -> String
    let localizedProject: (SalarySource) -> String
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                    // Preformatted strings, not closures: the row's Equatable
                    // must see localization changes or a language switch
                    // leaves stale labels behind.
                    SalarySourceResultsRow(
                        sourceID: source.id,
                        categoryText: localizedCategory(source.category),
                        projectText: localizedProject(source),
                        numberText: source.projectNumber?.nonEmpty ?? "–",
                        isSelected: source.id == selectedID,
                        showsDivider: index < sources.count - 1,
                        tableMinWidth: tableMinWidth,
                        categoryWidth: categoryWidth,
                        projectWidth: projectWidth,
                        numberWidth: numberWidth,
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

private struct SalarySourceResultsRow: View, Equatable {
    let sourceID: String
    let categoryText: String
    let projectText: String
    let numberText: String
    let isSelected: Bool
    let showsDivider: Bool
    let tableMinWidth: CGFloat
    let categoryWidth: CGFloat
    let projectWidth: CGFloat
    let numberWidth: CGFloat
    let onSelect: (String) -> Void

    nonisolated static func == (lhs: SalarySourceResultsRow, rhs: SalarySourceResultsRow) -> Bool {
        lhs.sourceID == rhs.sourceID
            && lhs.categoryText == rhs.categoryText
            && lhs.projectText == rhs.projectText
            && lhs.numberText == rhs.numberText
            && lhs.isSelected == rhs.isSelected
            && lhs.showsDivider == rhs.showsDivider
            && lhs.tableMinWidth == rhs.tableMinWidth
            && lhs.categoryWidth == rhs.categoryWidth
            && lhs.projectWidth == rhs.projectWidth
            && lhs.numberWidth == rhs.numberWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppListRowButton(
                minWidth: tableMinWidth,
                action: { onSelect(sourceID) },
                background: { AppListRowBackground(isSelected: isSelected) }
            ) {
                HStack(spacing: 0) {
                    SalarySidebarTableCell(text: categoryText)
                        .frame(width: categoryWidth, alignment: .leading)
                    SalarySidebarTableCell(text: projectText)
                        .frame(width: projectWidth, alignment: .leading)
                    SalarySidebarTableCell(text: numberText)
                        .frame(width: numberWidth, alignment: .leading)
                }
            }

            if showsDivider {
                Divider()
            }
        }
    }
}

private struct SalaryPeriodResultsTable: View {
    let periods: [SalaryCoveragePeriod]
    let selectedID: String?
    let tableMinWidth: CGFloat
    let sourceWidth: CGFloat
    let fromWidth: CGFloat
    let toWidth: CGFloat
    let percentageWidth: CGFloat
    let sourceLabel: (SalaryCoveragePeriod) -> String
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(periods.enumerated()), id: \.element.id) { index, period in
                    SalaryPeriodResultsRow(
                        period: period,
                        sourceText: sourceLabel(period),
                        isSelected: period.id == selectedID,
                        showsDivider: index < periods.count - 1,
                        tableMinWidth: tableMinWidth,
                        sourceWidth: sourceWidth,
                        fromWidth: fromWidth,
                        toWidth: toWidth,
                        percentageWidth: percentageWidth,
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

private struct SalaryPeriodResultsRow: View, Equatable {
    let period: SalaryCoveragePeriod
    let sourceText: String
    let isSelected: Bool
    let showsDivider: Bool
    let tableMinWidth: CGFloat
    let sourceWidth: CGFloat
    let fromWidth: CGFloat
    let toWidth: CGFloat
    let percentageWidth: CGFloat
    let onSelect: (String) -> Void

    nonisolated static func == (lhs: SalaryPeriodResultsRow, rhs: SalaryPeriodResultsRow) -> Bool {
        lhs.period == rhs.period
            && lhs.sourceText == rhs.sourceText
            && lhs.isSelected == rhs.isSelected
            && lhs.showsDivider == rhs.showsDivider
            && lhs.tableMinWidth == rhs.tableMinWidth
            && lhs.sourceWidth == rhs.sourceWidth
            && lhs.fromWidth == rhs.fromWidth
            && lhs.toWidth == rhs.toWidth
            && lhs.percentageWidth == rhs.percentageWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppListRowButton(
                minWidth: tableMinWidth,
                action: { onSelect(period.id) },
                background: { AppListRowBackground(isSelected: isSelected) }
            ) {
                HStack(spacing: 0) {
                    SalarySidebarTableCell(text: sourceText)
                        .frame(width: sourceWidth, alignment: .leading)
                    SalarySidebarTableCell(text: normalizeSalaryDateInput(period.from))
                        .frame(width: fromWidth, alignment: .leading)
                    SalarySidebarTableCell(text: normalizeSalaryDateInput(period.to))
                        .frame(width: toWidth, alignment: .leading)
                    SalarySidebarTableCell(text: formatPercentageInput(period.percentage))
                        .frame(width: percentageWidth, alignment: .leading)
                }
            }

            if showsDivider {
                Divider()
            }
        }
    }
}

private struct SalarySidebarTableCell: View {
    let text: String

    var body: some View {
        Text(text.isEmpty ? "–" : text)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            // Narrow columns clip silently; the tooltip recovers the value.
            .help(text)
    }
}

func salaryTimelineMonthScaledPositionX(
    for date: Date,
    monthStarts: [Date],
    timelineEndExclusive: Date,
    monthWidth: CGFloat
) -> CGFloat {
    guard let firstMonthStart = monthStarts.first, !monthStarts.isEmpty else { return 0 }
    let totalWidth = monthWidth * CGFloat(monthStarts.count)
    if date <= firstMonthStart { return 0 }
    if date >= timelineEndExclusive { return totalWidth }

    let monthIndex = monthStarts.lastIndex(where: { $0 <= date }) ?? 0
    let monthStart = monthStarts[monthIndex]
    let nextMonthStart = monthIndex + 1 < monthStarts.count
        ? monthStarts[monthIndex + 1]
        : timelineEndExclusive
    let monthDuration = nextMonthStart.timeIntervalSince(monthStart)
    guard monthDuration > 0 else { return CGFloat(monthIndex) * monthWidth }

    let fraction = min(max(date.timeIntervalSince(monthStart) / monthDuration, 0), 1)
    return (CGFloat(monthIndex) + CGFloat(fraction)) * monthWidth
}

private struct SalaryCoverageTimelineView: View {
    let entries: [SalaryWorkspaceView.TimelineEntry]
    let years: [Int]
    let language: AppLanguage
    let onPeriodSelect: (String) -> Void
    private let months: [TimelineMonth]
    private let timelineStart: Date
    private let timelineEndExclusive: Date
    private let intervalSegments: [IntervalSegment]
    private let timelineRuns: [TimelineRun]
    private let maxStackRows: Int
    @Environment(\.colorScheme) private var colorScheme

    private struct TimelineMonth: Identifiable {
        let id: String
        let year: Int
        let month: Int
        let start: Date
        let end: Date
    }

    private struct IntervalSegment: Identifiable {
        let id: String
        let entryID: String
        let label: String
        let percentageText: String
        let helpText: String
        let tint: Color
        let percentage: Double
        let rows: Int
        let start: Date
        let end: Date
        let topRow: Int
        let sourceReference: String
        let applicationID: String?
    }

    private struct TimelineRun: Identifiable {
        let id: String
        let entryID: String
        let mergeKey: String
        let start: Date
        let end: Date
        let label: String
        let percentageText: String
        let helpText: String
        let tint: Color
        let percentage: Double
        let rows: Int
        let topRow: Int
        let applicationID: String?
    }

    init(
        entries: [SalaryWorkspaceView.TimelineEntry],
        years: [Int],
        language: AppLanguage,
        onPeriodSelect: @escaping (String) -> Void
    ) {
        self.entries = entries
        self.years = years
        self.language = language
        self.onPeriodSelect = onPeriodSelect

        let months = Self.buildMonths(years: years)
        let timelineStart = months.first?.start ?? Date()
        let timelineEndExclusive = Self.nextDay(after: months.last?.end ?? Date())
        let boundaries = Self.buildTimeBoundaries(
            months: months,
            entries: entries,
            timelineStart: timelineStart,
            timelineEndExclusive: timelineEndExclusive
        )
        let segments = Self.buildIntervalSegments(entries: entries, timeBoundaries: boundaries)
        let runs = Self.buildTimelineRuns(from: segments)

        self.months = months
        self.timelineStart = timelineStart
        self.timelineEndExclusive = timelineEndExclusive
        self.intervalSegments = segments
        self.timelineRuns = runs
        self.maxStackRows = max(1, segments.map { $0.topRow + $0.rows }.max() ?? 1)
    }

    private static func buildMonths(years: [Int]) -> [TimelineMonth] {
        let calendar = Calendar.current
        guard let firstYear = years.first, let lastYear = years.last else { return [] }
        var result: [TimelineMonth] = []
        for year in firstYear...lastYear {
            for month in 1...12 {
                guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                      let interval = calendar.dateInterval(of: .month, for: start) else { continue }
                let end = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? start
                result.append(
                    TimelineMonth(
                        id: "\(year)-\(month)",
                        year: year,
                        month: month,
                        start: start,
                        end: end
                    )
                )
            }
        }
        return result
    }

    private static func buildTimeBoundaries(
        months: [TimelineMonth],
        entries: [SalaryWorkspaceView.TimelineEntry],
        timelineStart: Date,
        timelineEndExclusive: Date
    ) -> [Date] {
        let boundaries = ([timelineStart, timelineEndExclusive]
            + months.map(\.start)
            + entries.map(\.from)
            + entries.map { nextDay(after: $0.to) })
            .filter { $0 >= timelineStart && $0 <= timelineEndExclusive }
        return Array(Set(boundaries)).sorted()
    }

    private static func buildIntervalSegments(
        entries: [SalaryWorkspaceView.TimelineEntry],
        timeBoundaries: [Date]
    ) -> [IntervalSegment] {
        guard timeBoundaries.count > 1 else { return [] }
        let stackOrderedEntries = entries.sorted {
            salaryTimelineStackPriorityComesBefore(
                stackPriority(for: $0),
                stackPriority(for: $1)
            )
        }
        var result: [IntervalSegment] = []
        for (index, start) in timeBoundaries.dropLast().enumerated() {
            let end = timeBoundaries[index + 1]
            let activeEntries = stackOrderedEntries
                .filter { $0.from < end && nextDay(after: $0.to) > start }
            var rowsAbove = 0
            for entry in activeEntries {
                let rows = max(1, Int((entry.percentage / 5).rounded()))
                result.append(
                    IntervalSegment(
                        id: "\(entry.id)-\(index)",
                        entryID: entry.id,
                        label: entry.label,
                        percentageText: entry.percentageText,
                        helpText: entry.helpText,
                        tint: entry.tint,
                        percentage: entry.percentage,
                        rows: rows,
                        start: start,
                        end: end,
                        topRow: rowsAbove,
                        sourceReference: entry.sourceReference,
                        applicationID: entry.applicationID
                    )
                )
                rowsAbove += rows
            }
        }
        return result
    }

    private static func stackPriority(
        for entry: SalaryWorkspaceView.TimelineEntry
    ) -> SalaryTimelineStackPriority {
        SalaryTimelineStackPriority(
            isLeave: salaryTimelineLabelIsLeave(entry.label),
            duration: max(0, nextDay(after: entry.to).timeIntervalSince(entry.from)),
            from: entry.from,
            to: entry.to,
            percentage: entry.percentage,
            rowOrder: entry.rowOrder,
            rowKey: entry.rowKey,
            id: entry.id
        )
    }

    private static func buildTimelineRuns(from intervalSegments: [IntervalSegment]) -> [TimelineRun] {
        var runs: [TimelineRun] = []
        for segment in intervalSegments.sorted(by: {
            if $0.topRow != $1.topRow { return $0.topRow < $1.topRow }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }) {
            let mergeKey = segment.entryID + "|" + segment.label + "|" + segment.percentageText + "|" + segment.sourceReference + "|\(segment.topRow)|\(segment.rows)|\(segment.applicationID ?? "")"
            if let lastIndex = runs.lastIndex(where: {
                $0.mergeKey == mergeKey &&
                $0.end == segment.start
            }) {
                runs[lastIndex] = TimelineRun(
                    id: runs[lastIndex].id,
                    entryID: runs[lastIndex].entryID,
                    mergeKey: runs[lastIndex].mergeKey,
                    start: runs[lastIndex].start,
                    end: segment.end,
                    label: runs[lastIndex].label,
                    percentageText: runs[lastIndex].percentageText,
                    helpText: runs[lastIndex].helpText,
                    tint: runs[lastIndex].tint,
                    percentage: runs[lastIndex].percentage,
                    rows: runs[lastIndex].rows,
                    topRow: runs[lastIndex].topRow,
                    applicationID: runs[lastIndex].applicationID
                )
            } else {
                runs.append(
                    TimelineRun(
                        id: mergeKey + "|\(DateParsers.isoDay.string(from: segment.start))",
                        entryID: segment.entryID,
                        mergeKey: mergeKey,
                        start: segment.start,
                        end: segment.end,
                        label: segment.label,
                        percentageText: segment.percentageText,
                        helpText: segment.helpText,
                        tint: segment.tint,
                        percentage: segment.percentage,
                        rows: segment.rows,
                        topRow: segment.topRow,
                        applicationID: segment.applicationID
                    )
                )
            }
        }
        return runs.flatMap(splitTimelineRunByYear)
    }

    private static func splitTimelineRunByYear(_ run: TimelineRun) -> [TimelineRun] {
        let calendar = Calendar.current
        var result: [TimelineRun] = []
        var start = run.start

        while start < run.end {
            let year = calendar.component(.year, from: start)
            let nextYear = calendar.date(
                from: DateComponents(year: year + 1, month: 1, day: 1)
            ) ?? run.end
            let end = min(run.end, nextYear)
            result.append(
                TimelineRun(
                    id: "\(run.id)|year:\(year)",
                    entryID: run.entryID,
                    mergeKey: run.mergeKey,
                    start: start,
                    end: end,
                    label: run.label,
                    percentageText: run.percentageText,
                    helpText: run.helpText,
                    tint: run.tint,
                    percentage: run.percentage,
                    rows: run.rows,
                    topRow: run.topRow,
                    applicationID: run.applicationID
                )
            )
            start = end
        }

        return result
    }

    var body: some View {
        if entries.isEmpty || years.isEmpty || months.isEmpty {
            Text(language.text("No periods", "Inga perioder"))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            compactTimelineBody
            .frame(height: headerSectionHeight + timelineBodyHeight)
        }
    }

    private var compactMonthWidth: CGFloat {
        let baseWidth: CGFloat = switch months.count {
        case ...18:
            108
        case ...24:
            84
        case ...36:
            68
        default:
            56
        }
        return baseWidth * 1.3
    }

    private var compactTimelineBody: some View {
        timelineBody(monthWidth: compactMonthWidth)
    }

    private func timelineBody(monthWidth: CGFloat) -> some View {
        let headerHeight: CGFloat = 48
        let unitHeight = timelineUnitHeight
        let contentWidth = monthWidth * CGFloat(months.count)
        let bodyHeight = timelineBodyHeight

        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    monthlyGrid(
                        months: months,
                        monthWidth: monthWidth,
                        bodyHeight: bodyHeight,
                        headerHeight: headerHeight
                    )
                    VStack(alignment: .leading, spacing: 0) {
                        yearHeader(months: months, monthWidth: monthWidth, headerHeight: headerHeight)
                        ZStack(alignment: .topLeading) {
                            ForEach(timelineRuns) { run in
                                timelineRunView(
                                    run: run,
                                    monthWidth: monthWidth,
                                    unitHeight: unitHeight
                                )
                            }

                            currentDateMarker(monthWidth: monthWidth, height: bodyHeight)

                            ForEach(timelineRuns) { run in
                                timelineRunLabelOverlay(
                                    run: run,
                                    monthWidth: monthWidth,
                                    unitHeight: unitHeight
                                )
                            }
                        }
                        .frame(width: contentWidth, height: bodyHeight, alignment: .topLeading)
                    }
                }
                .frame(width: contentWidth, height: headerHeight + bodyHeight, alignment: .topLeading)
                .overlay(alignment: .topLeading) {
                    currentDateScrollAnchor(monthWidth: monthWidth)
                }
            }
            .onAppear {
                scrollToCurrentDate(using: proxy)
            }
        }
    }

    private var headerSectionHeight: CGFloat { 48 }
    private var timelineUnitHeight: CGFloat { 30 }
    private var timelineBodyHeight: CGFloat {
        CGFloat(stackRowsAtCurrentDate) * timelineUnitHeight
    }

    private var stackRowsAtCurrentDate: Int {
        let today = Date()
        guard today >= timelineStart && today < timelineEndExclusive else {
            return maxStackRows
        }
        return max(
            1,
            intervalSegments
                .filter { $0.start <= today && today < $0.end }
                .map { $0.topRow + $0.rows }
                .max() ?? 1
        )
    }

    @ViewBuilder
    private func yearHeader(months: [TimelineMonth], monthWidth: CGFloat, headerHeight: CGFloat) -> some View {
        let yearGroups = Dictionary(grouping: months, by: \.year)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(years, id: \.self) { year in
                    Text(String(year))
                        .appTypography(.panelTitle)
                        .frame(width: monthWidth * CGFloat(yearGroups[year]?.count ?? 12), height: 20)
                }
            }
            HStack(spacing: 0) {
                ForEach(months) { month in
                    Text(monthShortLabel(month.month))
                        .appTypography(.body)
                        .foregroundStyle(AppPalette.appText)
                        .frame(width: monthWidth, height: headerHeight - 20)
                }
            }
        }
    }

    @ViewBuilder
    private func monthlyGrid(months: [TimelineMonth], monthWidth: CGFloat, bodyHeight: CGFloat, headerHeight: CGFloat) -> some View {
        let totalHeight = headerHeight + bodyHeight
        ForEach(Array(months.enumerated()), id: \.offset) { index, month in
            if month.month == 1 {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 4, height: totalHeight)
                    .offset(x: monthWidth * CGFloat(index) - 2)
            } else {
                Rectangle()
                    .fill(AppPalette.border.opacity(0.48))
                    .frame(width: 1.15, height: totalHeight)
                    .offset(x: monthWidth * CGFloat(index))
            }
        }
    }

    @ViewBuilder
    private func currentDateScrollAnchor(monthWidth: CGFloat) -> some View {
        let today = Date()
        if today >= timelineStart && today <= timelineEndExclusive {
            let anchorX = positionX(for: today, monthWidth: monthWidth)
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: max(0, anchorX - 0.5), height: 1)
                Color.clear
                    .frame(width: 1, height: 1)
                    .id("salary-current-date")
                Spacer(minLength: 0)
            }
            .frame(width: monthWidth * CGFloat(months.count), height: 1, alignment: .leading)
        }
    }

    private func scrollToCurrentDate(using proxy: ScrollViewProxy) {
        let today = Date()
        guard today >= timelineStart && today <= timelineEndExclusive else { return }
        DispatchQueue.main.async {
            proxy.scrollTo("salary-current-date", anchor: .center)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            proxy.scrollTo("salary-current-date", anchor: .center)
        }
    }

    private func monthShortLabel(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = language == .swedish ? Locale(identifier: "sv_SE") : Locale(identifier: "en_US")
        let symbol = formatter.shortMonthSymbols[max(0, min(month - 1, 11))]
        return symbol.replacingOccurrences(of: ".", with: "")
    }

    @ViewBuilder
    private func timelineRunView(
        run: TimelineRun,
        monthWidth: CGFloat,
        unitHeight: CGFloat
    ) -> some View {
        let yearGap: CGFloat = 8
        let startsAtYearBoundary = isYearBoundary(run.start)
        let endsAtYearBoundary = isYearBoundary(run.end)
        let x = positionX(for: run.start, monthWidth: monthWidth)
            + (startsAtYearBoundary ? yearGap / 2 : 0)
        let y = CGFloat(run.topRow) * unitHeight
        let barHeight = CGFloat(run.rows) * unitHeight
        let width = max(
            2,
            positionX(for: run.end, monthWidth: monthWidth)
                - x
                - (endsAtYearBoundary ? yearGap / 2 : 0)
        )

        Button(action: { onPeriodSelect(run.entryID) }) {
            timelineRunBar(run: run, width: width, height: barHeight)
        }
        .buttonStyle(.plain)
        .help(run.helpText)
        .offset(x: x, y: y)
    }

    @ViewBuilder
    private func timelineRunBar(run: TimelineRun, width: CGFloat, height: CGFloat) -> some View {
        let cornerRadius: CGFloat = 2.5
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if salaryTimelineLabelIsLeave(run.label) {
            shape
                .fill(Color.clear)
                .overlay {
                    Canvas { context, size in
                        var stripes = Path()
                        let spacing: CGFloat = 10
                        var topX: CGFloat = 0
                        while topX <= size.width + size.height {
                            stripes.move(to: CGPoint(x: topX, y: 0))
                            stripes.addLine(to: CGPoint(x: topX - size.height, y: size.height))
                            topX += spacing
                        }
                        context.stroke(
                            stripes,
                            with: .color(AppPalette.appText.opacity(colorScheme == .dark ? 0.15 : 0.11)),
                            lineWidth: 0.8
                        )
                    }
                }
                .overlay(
                    shape
                        .stroke(AppPalette.border.opacity(0.72), lineWidth: 0.8)
                )
                .clipShape(shape)
                .frame(width: width, height: height)
        } else {
            shape
                .fill(AppPalette.fieldSurface)
                .overlay(
                    shape
                        .stroke(AppPalette.border.opacity(0.72), lineWidth: 0.8)
                )
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(run.tint)
                        .frame(width: 6)
                        .padding(.vertical, 1)
                }
                .clipShape(shape)
                .frame(width: width, height: height)
        }
    }

    @ViewBuilder
    private func currentDateMarker(monthWidth: CGFloat, height: CGFloat) -> some View {
        let today = Date()
        if today >= timelineStart && today <= timelineEndExclusive {
            let markerWidth: CGFloat = 3
            Rectangle()
                .fill(AppPalette.todayMarker)
                .frame(width: markerWidth, height: height)
                .offset(x: positionX(for: today, monthWidth: monthWidth) - markerWidth / 2)
                .allowsHitTesting(false)
        }
    }

    private func timelineRunLabelOverlay(
        run: TimelineRun,
        monthWidth: CGFloat,
        unitHeight: CGFloat
    ) -> some View {
        let yearGap: CGFloat = 8
        let startsAtYearBoundary = isYearBoundary(run.start)
        let endsAtYearBoundary = isYearBoundary(run.end)
        let x = positionX(for: run.start, monthWidth: monthWidth)
            + (startsAtYearBoundary ? yearGap / 2 : 0)
        let y = CGFloat(run.topRow) * unitHeight
        let height = CGFloat(run.rows) * unitHeight
        let width = max(
            2,
            positionX(for: run.end, monthWidth: monthWidth)
                - x
                - (endsAtYearBoundary ? yearGap / 2 : 0)
        )

        return timelineRunLabel(run: run)
            .frame(width: width, height: height)
            .offset(x: x, y: y)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func timelineRunLabel(run: TimelineRun) -> some View {
        let textColor = AppPalette.appText
        if run.percentage <= 5.5 {
            Text("\(run.label), \(run.percentageText)")
                .appTypography(.tableHeader)
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            VStack(alignment: .center, spacing: 2) {
                Text(run.label)
                    .appTypography(.tableHeader)
                    .lineLimit(max(1, min(run.rows - 1, 5)))
                    .truncationMode(.tail)
                Text(run.percentageText)
                    .appTypography(.tableHeader)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(textColor)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func isYearBoundary(_ date: Date) -> Bool {
        let calendar = Calendar.current
        return calendar.component(.month, from: date) == 1
            && calendar.component(.day, from: date) == 1
    }

    private static func nextDay(after date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
    }

    private func positionX(for date: Date, monthWidth: CGFloat) -> CGFloat {
        salaryTimelineMonthScaledPositionX(
            for: date,
            monthStarts: months.map(\.start),
            timelineEndExclusive: timelineEndExclusive,
            monthWidth: monthWidth
        )
    }
}

private extension Color {
    init(hex: Int) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}
