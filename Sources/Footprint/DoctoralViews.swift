import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DoctoralCandidatesWorkspaceView: View {
    private enum DoctoralListSortColumn: String, Hashable {
        case name
        case institution
        case admissionYear
        case dissertationYear
        case role

        var defaultAscending: Bool { true }
    }

    private struct DoctoralListSortCriterion: AppListSortCriterion {
        let column: DoctoralListSortColumn
        var ascending: Bool
    }

    let store: GrantDataStore
    let newRecordTrigger: Int
    let isActive: Bool

    @State private var selectedCandidateID: String?
    @WorkspaceFilterState("DoctoralCandidates.Filter.Search") private var searchText = ""
    @WorkspaceFilterState("DoctoralCandidates.Filter.MainSupervisor") private var showsMainSupervisorCandidates = false
    @WorkspaceFilterState("DoctoralCandidates.Filter.CoSupervisor") private var showsCoSupervisorCandidates = false
    @WorkspaceFilterState("DoctoralCandidates.Filter.ActiveOnly") private var showsOnlyActiveCandidates = false
    @WorkspaceFilterState("DoctoralCandidates.Filter.MinimumAdmissionYear") private var minimumAdmissionYearValue: Double = 0
    @WorkspaceFilterState("DoctoralCandidates.Filter.MaximumAdmissionYear") private var maximumAdmissionYearValue: Double = 0
    @WorkspaceFilterState("DoctoralCandidates.Filter.MinimumDissertationYear") private var minimumDissertationYearValue: Double = 0
    @WorkspaceFilterState("DoctoralCandidates.Filter.MaximumDissertationYear") private var maximumDissertationYearValue: Double = 0
    @State private var sortHistory = ListSortPersistence.load(
        defaultsKey: "DoctoralCandidatesListSort",
        defaultValue: [
            DoctoralListSortCriterion(column: .role, ascending: true),
            DoctoralListSortCriterion(column: .name, ascending: true),
        ]
    )
    @StateObject private var columnWidths = AppListColumnWidthModel(listKey: "DoctoralCandidates")

    private enum SupervisorBucket {
        case main
        case co
        case none
    }

    private var language: AppLanguage { store.language }

    private var currentUserNormalizedName: String? {
        store.currentUserAuthor().map { PublicationDerivation.normalizedName($0.name) }
    }

    private var searchableCandidates: [DoctoralCandidateRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.doctoralCandidates }
        let normalizedQuery = PublicationDerivation.normalizedName(query)
        return store.doctoralCandidates.filter { candidate in
            let parts = [
                candidate.candidateName,
                candidate.institution,
                candidate.supervisors.map(\.name).joined(separator: " "),
                candidate.notes,
            ]
                .joined(separator: " ")
            return PublicationDerivation.normalizedName(parts).contains(normalizedQuery)
        }
    }

    private var filteredCandidates: [DoctoralCandidateRecord] {
        searchableCandidates.filter { candidate in
            matchesDoctoralRoleFilter(candidate)
                && matchesDoctoralActiveFilter(candidate)
                && matchesDoctoralYearFilters(candidate)
        }
    }

    private var selectedCandidate: DoctoralCandidateRecord? {
        guard let selectedCandidateID else { return nil }
        return store.doctoralCandidates.first(where: { $0.id == selectedCandidateID })
    }

    private var workspaceDestination: AppRoute.Destination {
        .doctoralCandidates
    }

    private var displayCandidates: [DoctoralCandidateRecord] {
        filteredCandidates.sorted(by: doctoralCandidateSortOrder)
    }

    private var admissionYearBounds: ClosedRange<Double> {
        doctoralYearBounds(for: store.doctoralCandidates.compactMap { doctoralYearValue($0.admissionDate) })
    }

    private var dissertationYearBounds: ClosedRange<Double> {
        doctoralYearBounds(for: store.doctoralCandidates.compactMap { doctoralYearValue($0.plannedDisputationDate) })
    }

    private var hasActiveDoctoralFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || showsMainSupervisorCandidates
            || showsCoSupervisorCandidates
            || showsOnlyActiveCandidates
            || minimumAdmissionYearValue != admissionYearBounds.lowerBound
            || maximumAdmissionYearValue != admissionYearBounds.upperBound
            || minimumDissertationYearValue != dissertationYearBounds.lowerBound
            || maximumDissertationYearValue != dissertationYearBounds.upperBound
    }

    private func doctoralCandidateSortOrder(_ lhs: DoctoralCandidateRecord, _ rhs: DoctoralCandidateRecord) -> Bool {
        var columns = sortHistory.map(\.column)
        for fallbackColumn in [DoctoralListSortColumn.role, .name] where !columns.contains(fallbackColumn) {
            columns.append(fallbackColumn)
        }
        for column in columns {
            let ascending = sortHistory.first(where: { $0.column == column })?.ascending ?? column.defaultAscending
            let comparison: ComparisonResult
            switch column {
            case .name:
                comparison = (lhs.candidateName.nonEmpty ?? "").localizedStandardCompare(rhs.candidateName.nonEmpty ?? "")
            case .institution:
                comparison = (lhs.institution.nonEmpty ?? "").localizedStandardCompare(rhs.institution.nonEmpty ?? "")
            case .admissionYear:
                comparison = doctoralYearText(lhs.admissionDate).localizedStandardCompare(doctoralYearText(rhs.admissionDate))
            case .dissertationYear:
                comparison = doctoralYearText(lhs.plannedDisputationDate).localizedStandardCompare(doctoralYearText(rhs.plannedDisputationDate))
            case .role:
                let leftRank = supervisorBucketSortRank(supervisorBucket(for: lhs))
                let rightRank = supervisorBucketSortRank(supervisorBucket(for: rhs))
                comparison = leftRank == rightRank ? .orderedSame : (leftRank < rightRank ? .orderedAscending : .orderedDescending)
            }
            if comparison != .orderedSame {
                return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
            }
        }
        return lhs.id < rhs.id
    }

    var body: some View {
        PersistentSplitView(layout: .doctoralCandidates) {
            AppWorkspaceSidebar {
                VStack(alignment: .leading, spacing: 12) {
                    AppWorkspaceSidebarHeader(
                        title: language.text("Doctoral candidates", "Doktorander"),
                        actionTitle: language.text("New doctoral candidate", "Ny doktorand")
                    ) {
                        let id = store.addDoctoralCandidate()
                        setSelectedCandidateID(id)
                    }

                    doctoralFilters(language: language)

                    doctoralList(language: language)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    ListCountFootnote(
                        displayedCount: displayCandidates.count,
                        totalCount: store.doctoralCandidates.count,
                        language: language
                    )
                }
            }
        } detail: {
            if let selectedCandidate {
                DoctoralCandidateDetailView(
                    store: store,
                    candidate: selectedCandidate
                )
                .id(selectedCandidate.id)
                .undoRevealPulse(
                    triggerID: store.undoRevealRequest?.id,
                    isActive: store.undoRevealRequest?.target.matchesWholeRecord(routeDestination: .doctoralCandidates, recordID: selectedCandidate.id) == true
                )
                .performanceScopeProbe(store: store, scope: "doctoral-detail", identifier: selectedCandidate.id)
                .background(AppPalette.detailPanelSurface)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    AppPanelHeadingText(text: language.text("No doctoral candidates", "Inga doktorander"))
                    AppRecordSubtitleText(text: language.text("Add or select a doctoral candidate.", "Lägg till eller välj en doktorand."))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
                .background(AppPalette.detailPanelSurface)
            }
        }
        .onAppear {
            resetDoctoralYearBoundsIfNeeded()
            if let route = store.route, route.destination == workspaceDestination {
                setSelectedCandidateID(route.recordID)
                store.consumeRoute()
            } else if selectedCandidateID == nil {
                let firstCandidate = displayCandidates.first
                    ?? store.doctoralCandidates.first
                setSelectedCandidateID(
                    store.lastSelectedRecordID(for: workspaceDestination)
                        ?? firstCandidate?.id
                )
            }
        }
        .onChange(of: newRecordTrigger) { _, _ in
            guard isActive else { return }
            let id = store.addDoctoralCandidate()
            setSelectedCandidateID(id)
        }
        .onReceive(
            store.$doctoralCandidates.map { $0.map(\.id) }.removeDuplicates().dropFirst()
        ) { ids in
            // Deferred: @Published emits at willSet and the handlers read
            // the store's committed state.
            DispatchQueue.main.async {
                resetDoctoralYearBoundsIfNeeded()
                if let selectedCandidateID, ids.contains(selectedCandidateID) {
                    return
                }
                setSelectedCandidateID(
                    store.lastSelectedRecordID(for: workspaceDestination)
                        ?? ids.first
                )
            }
        }
        .onChange(of: store.route) { _, route in
            guard isActive, let route, route.destination == workspaceDestination else { return }
            setSelectedCandidateID(route.recordID)
            store.consumeRoute()
        }
        .onChange(of: isActive) { _, active in
            if active {
                if let route = store.route, route.destination == workspaceDestination {
                    setSelectedCandidateID(route.recordID)
                    store.consumeRoute()
                }
            } else {
                clearDoctoralFiltersForDeactivationIfNeeded()
            }
        }
        .onChange(of: selectedCandidateID) { _, id in
            store.handlePendingSelectionReturnIfNeeded(for: id, in: workspaceDestination)
            store.rememberSelection(id: id, for: workspaceDestination)
        }
    }

    private func supervisorBucketSortRank(_ bucket: SupervisorBucket) -> Int {
        switch bucket {
        case .main:
            return 0
        case .co:
            return 1
        case .none:
            return 2
        }
    }

    private func doctoralFilters(language: AppLanguage) -> some View {
        AppFilterCard {
            VStack(alignment: .leading, spacing: 8) {
                AppFilterRow(
                    showsClearButton: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                    clearAction: { searchText = "" }
                ) {
                    AppSidebarSearchField(
                        placeholder: language.text("Search doctoral candidates", "Sök doktorander"),
                        text: $searchText
                    )
                }

                AppFilterRow(
                    showsClearButton: showsMainSupervisorCandidates || showsCoSupervisorCandidates || showsOnlyActiveCandidates,
                    clearAction: {
                        showsMainSupervisorCandidates = false
                        showsCoSupervisorCandidates = false
                        showsOnlyActiveCandidates = false
                    }
                ) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            AppFilterChip(
                                label: language.text("Main supervisor", "Huvudhandledare"),
                                isSelected: showsMainSupervisorCandidates
                            ) {
                                showsMainSupervisorCandidates.toggle()
                            }
                            AppFilterChip(
                                label: language.text("Co-supervisor", "Bihandledare"),
                                isSelected: showsCoSupervisorCandidates
                            ) {
                                showsCoSupervisorCandidates.toggle()
                            }
                            AppFilterChip(
                                label: language.text("Active", "Aktiva"),
                                isSelected: showsOnlyActiveCandidates
                            ) {
                                showsOnlyActiveCandidates.toggle()
                            }
                        }
                    }
                }

                AppFilterRow(
                    showsClearButton: minimumAdmissionYearValue != admissionYearBounds.lowerBound
                        || maximumAdmissionYearValue != admissionYearBounds.upperBound
                        || minimumDissertationYearValue != dissertationYearBounds.lowerBound
                        || maximumDissertationYearValue != dissertationYearBounds.upperBound,
                    clearAction: {
                        minimumAdmissionYearValue = admissionYearBounds.lowerBound
                        maximumAdmissionYearValue = admissionYearBounds.upperBound
                        minimumDissertationYearValue = dissertationYearBounds.lowerBound
                        maximumDissertationYearValue = dissertationYearBounds.upperBound
                    }
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        doctoralYearSlider(
                            title: language.text("Admission year", "Antagningsår"),
                            lower: $minimumAdmissionYearValue,
                            upper: $maximumAdmissionYearValue,
                            bounds: admissionYearBounds,
                            language: language
                        )
                        doctoralYearSlider(
                            title: language.text("Dissertation year", "Disputationsår"),
                            lower: $minimumDissertationYearValue,
                            upper: $maximumDissertationYearValue,
                            bounds: dissertationYearBounds,
                            language: language
                        )
                    }
                }

                AppFilterClearAllRow(isVisible: hasActiveDoctoralFilters) {
                    searchText = ""
                    showsMainSupervisorCandidates = false
                    showsCoSupervisorCandidates = false
                    showsOnlyActiveCandidates = false
                    minimumAdmissionYearValue = admissionYearBounds.lowerBound
                    maximumAdmissionYearValue = admissionYearBounds.upperBound
                    minimumDissertationYearValue = dissertationYearBounds.lowerBound
                    maximumDissertationYearValue = dissertationYearBounds.upperBound
                }
            }
        }
    }

    private func doctoralYearSlider(
        title: String,
        lower: Binding<Double>,
        upper: Binding<Double>,
        bounds: ClosedRange<Double>,
        language: AppLanguage
    ) -> some View {
        let lowerYear = String(Int(min(lower.wrappedValue, upper.wrappedValue)))
        let upperYear = String(Int(max(lower.wrappedValue, upper.wrappedValue)))

        return AppFilterRangeControl(
            title: "\(title): \(lowerYear)–\(upperYear)",
            lowerValue: lower,
            upperValue: upper,
            bounds: bounds,
            unavailableText: language.text("Only one year available", "Endast ett år tillgängligt")
        )
    }

    private func doctoralYearBounds(for years: [Int]) -> ClosedRange<Double> {
        let fallback = Calendar.current.component(.year, from: Date())
        let sorted = years.sorted()
        let lower = Double(sorted.first ?? fallback)
        let upper = Double(sorted.last ?? fallback)
        return lower...upper
    }

    private func resetDoctoralYearBoundsIfNeeded() {
        let admissionBounds = admissionYearBounds
        if minimumAdmissionYearValue == 0 && maximumAdmissionYearValue == 0 {
            minimumAdmissionYearValue = admissionBounds.lowerBound
            maximumAdmissionYearValue = admissionBounds.upperBound
        } else {
            minimumAdmissionYearValue = min(max(minimumAdmissionYearValue, admissionBounds.lowerBound), admissionBounds.upperBound)
            maximumAdmissionYearValue = min(max(maximumAdmissionYearValue, admissionBounds.lowerBound), admissionBounds.upperBound)
        }

        let dissertationBounds = dissertationYearBounds
        if minimumDissertationYearValue == 0 && maximumDissertationYearValue == 0 {
            minimumDissertationYearValue = dissertationBounds.lowerBound
            maximumDissertationYearValue = dissertationBounds.upperBound
        } else {
            minimumDissertationYearValue = min(max(minimumDissertationYearValue, dissertationBounds.lowerBound), dissertationBounds.upperBound)
            maximumDissertationYearValue = min(max(maximumDissertationYearValue, dissertationBounds.lowerBound), dissertationBounds.upperBound)
        }
    }

    private func matchesDoctoralRoleFilter(_ candidate: DoctoralCandidateRecord) -> Bool {
        guard showsMainSupervisorCandidates || showsCoSupervisorCandidates else { return true }
        let bucket = supervisorBucket(for: candidate)
        return (showsMainSupervisorCandidates && bucket == .main)
            || (showsCoSupervisorCandidates && bucket == .co)
    }

    private func matchesDoctoralActiveFilter(_ candidate: DoctoralCandidateRecord) -> Bool {
        guard showsOnlyActiveCandidates else { return true }
        guard let date = DateParsers.isoDay.date(from: candidate.plannedDisputationDate) else { return true }
        return Calendar.current.startOfDay(for: date) >= Calendar.current.startOfDay(for: Date())
    }

    private func matchesDoctoralYearFilters(_ candidate: DoctoralCandidateRecord) -> Bool {
        matchesDoctoralYear(
            doctoralYearValue(candidate.admissionDate),
            lower: minimumAdmissionYearValue,
            upper: maximumAdmissionYearValue,
            bounds: admissionYearBounds
        )
        && matchesDoctoralYear(
            doctoralYearValue(candidate.plannedDisputationDate),
            lower: minimumDissertationYearValue,
            upper: maximumDissertationYearValue,
            bounds: dissertationYearBounds
        )
    }

    private func matchesDoctoralYear(
        _ year: Int?,
        lower: Double,
        upper: Double,
        bounds: ClosedRange<Double>
    ) -> Bool {
        let filterIsFullRange = lower == bounds.lowerBound && upper == bounds.upperBound
        guard let year else { return filterIsFullRange }
        return Double(year) >= min(lower, upper) && Double(year) <= max(lower, upper)
    }

    private func supervisorBucket(for candidate: DoctoralCandidateRecord) -> SupervisorBucket {
        guard let currentUserNormalizedName else { return .none }
        if let index = candidate.supervisors.firstIndex(where: {
            PublicationDerivation.normalizedName($0.name) == currentUserNormalizedName
        }) {
            return index == 0 ? .main : .co
        }
        return .none
    }

    /// Resolved column widths: auto-fit to the longest content (capped) unless
    /// the user has dragged a manual width, which is persisted.
    private var doctoralColumnWidths: [DoctoralListSortColumn: CGFloat] {
        let candidates = store.doctoralCandidates
        let unnamed = language.text("Unnamed doctoral candidate", "Namnlös doktorand")
        let auto: [DoctoralListSortColumn: CGFloat] = [
            .name: AppListColumnAutoWidth.width(
                header: language.text("Name", "Namn"),
                values: candidates.map { $0.candidateName.nonEmpty ?? unnamed }
            ),
            .role: AppListColumnAutoWidth.width(
                header: language.text("Role", "Roll"),
                values: candidates.map { roleLabel(for: $0, language: language) }
            ),
            .institution: AppListColumnAutoWidth.width(
                header: language.text("Institution", "Lärosäte"),
                values: candidates.map { $0.institution.nonEmpty ?? "—" }
            ),
            .admissionYear: AppListColumnAutoWidth.width(
                header: language.text("Admission year", "Antagningsår"),
                values: candidates.map { doctoralYearText($0.admissionDate) }
            ),
            .dissertationYear: AppListColumnAutoWidth.width(
                header: language.text("Dissertation year", "Disputationsår"),
                values: candidates.map { doctoralYearText($0.plannedDisputationDate) }
            ),
        ]
        return auto.reduce(into: [:]) { result, entry in
            result[entry.key] = columnWidths.width(for: entry.key.rawValue, auto: entry.value)
        }
    }

    private func doctoralColumnHandle(
        _ column: DoctoralListSortColumn,
        widths: [DoctoralListSortColumn: CGFloat]
    ) -> some View {
        AppListColumnResizeHandle(
            model: columnWidths,
            column: column.rawValue,
            currentWidth: widths[column] ?? 120
        )
    }

    private func doctoralList(language: AppLanguage) -> some View {
        let widths = doctoralColumnWidths
        let columnOrder: [DoctoralListSortColumn] = [.name, .role, .institution, .admissionYear, .dissertationYear]
        let handleWidth = AppListColumnResizeHandle.width
        let tableContentWidth: CGFloat = columnOrder.compactMap { widths[$0] }.reduce(0, +)
            + CGFloat(columnOrder.count) * handleWidth + 20
        let orderedIDs = displayCandidates.map(\.id)

        return AppListTable(contentWidth: tableContentWidth) {
            HStack(spacing: 0) {
                doctoralListHeader(language.text("Name", "Namn"), width: widths[.name], column: .name)
                doctoralColumnHandle(.name, widths: widths)
                doctoralListHeader(language.text("Role", "Roll"), width: widths[.role], column: .role)
                doctoralColumnHandle(.role, widths: widths)
                doctoralListHeader(language.text("Institution", "Lärosäte"), width: widths[.institution], column: .institution)
                doctoralColumnHandle(.institution, widths: widths)
                doctoralListHeader(language.text("Admission year", "Antagningsår"), width: widths[.admissionYear], column: .admissionYear)
                doctoralColumnHandle(.admissionYear, widths: widths)
                doctoralListHeader(language.text("Dissertation year", "Disputationsår"), width: widths[.dissertationYear], column: .dissertationYear)
                doctoralColumnHandle(.dissertationYear, widths: widths)
            }
        } rows: {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(displayCandidates) { candidate in
                    AppListRowButton(
                        width: tableContentWidth,
                        action: { setSelectedCandidateID(candidate.id) },
                        background: { doctoralListRowBackground(for: candidate) }
                    ) {
                        HStack(spacing: 0) {
                            doctoralListCell(candidate.candidateName.nonEmpty ?? language.text("Unnamed doctoral candidate", "Namnlös doktorand"), width: widths[.name])
                            Color.clear.frame(width: handleWidth)
                            doctoralListCell(roleLabel(for: candidate, language: language), width: widths[.role])
                            Color.clear.frame(width: handleWidth)
                            doctoralListCell(candidate.institution.nonEmpty ?? "—", width: widths[.institution])
                            Color.clear.frame(width: handleWidth)
                            doctoralListCell(doctoralYearText(candidate.admissionDate), width: widths[.admissionYear])
                            Color.clear.frame(width: handleWidth)
                            doctoralListCell(doctoralYearText(candidate.plannedDisputationDate), width: widths[.dissertationYear])
                            Color.clear.frame(width: handleWidth)
                        }
                    }
                    .id(candidate.id)

                    if candidate.id != displayCandidates.last?.id {
                        Divider()
                    }
                }
            }
        }
        .appListKeyboardNavigation(
            store: store,
            destination: workspaceDestination,
            isEnabled: isActive,
            orderedIDs: orderedIDs,
            selectedID: selectedCandidateID,
            onSelect: { setSelectedCandidateID($0) }
        )
    }

    private func doctoralYearText(_ rawDate: String) -> String {
        guard let value = rawDate.nonEmpty, value.count >= 4 else { return "—" }
        return String(value.prefix(4))
    }

    private func doctoralYearValue(_ rawDate: String) -> Int? {
        guard let value = rawDate.nonEmpty, value.count >= 4 else { return nil }
        return Int(value.prefix(4))
    }

    private func roleLabel(for candidate: DoctoralCandidateRecord, language: AppLanguage) -> String {
        switch supervisorBucket(for: candidate) {
        case .main:
            return language.text("Main supervisor", "Huvudhandledare")
        case .co:
            return language.text("Co-supervisor", "Bihandledare")
        case .none:
            return "—"
        }
    }

    private func clearDoctoralFiltersForDeactivationIfNeeded() {
        guard !store.shouldRetainListFilters(for: .doctoralCandidates) else { return }
        searchText = ""
        showsMainSupervisorCandidates = false
        showsCoSupervisorCandidates = false
        showsOnlyActiveCandidates = false
        minimumAdmissionYearValue = admissionYearBounds.lowerBound
        maximumAdmissionYearValue = admissionYearBounds.upperBound
        minimumDissertationYearValue = dissertationYearBounds.lowerBound
        maximumDissertationYearValue = dissertationYearBounds.upperBound
    }

    private func doctoralListHeader(_ title: String, width: CGFloat? = nil, column: DoctoralListSortColumn) -> some View {
        let criterion = sortHistory.first(where: { $0.column == column })
        let sortIndex = sortHistory.firstIndex(where: { $0.column == column })
        return AppSortableListHeader(
            title: title,
            ascending: criterion?.ascending,
            sortIndex: sortIndex,
            width: width,
            resetTitle: language.text("Reset", "Återställ"),
            onToggle: { toggleDoctoralSort(column) },
            onReset: resetDoctoralSort
        )
    }

    private func toggleDoctoralSort(_ column: DoctoralListSortColumn) {
        if let existingIndex = sortHistory.firstIndex(where: { $0.column == column }) {
            if existingIndex == 0 {
                sortHistory[0].ascending.toggle()
            } else {
                let criterion = sortHistory.remove(at: existingIndex)
                sortHistory.insert(criterion, at: 0)
            }
        } else {
            sortHistory.insert(DoctoralListSortCriterion(column: column, ascending: column.defaultAscending), at: 0)
        }
        ListSortPersistence.save(sortHistory, defaultsKey: "DoctoralCandidatesListSort")
    }

    private func resetDoctoralSort() {
        sortHistory = [
            DoctoralListSortCriterion(column: .role, ascending: true),
            DoctoralListSortCriterion(column: .name, ascending: true),
        ]
        ListSortPersistence.save(sortHistory, defaultsKey: "DoctoralCandidatesListSort")
    }

    private func doctoralListCell(_ text: String, width: CGFloat? = nil) -> some View {
        Text(text)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: .leading)
    }

    private func doctoralListRowBackground(for candidate: DoctoralCandidateRecord) -> some View {
        AppListRowBackground(
            isSelected: candidate.id == selectedCandidateID,
            toneFill: doctoralCandidateStatusColor(candidate)
        )
    }

    private func doctoralCandidateStatusColor(_ candidate: DoctoralCandidateRecord) -> Color {
        // Round 12: supervision not confirmed in Retendo is marked red, as in
        // the teaching list.
        if candidate.supervisionPeriods.contains(where: \.needsRetendoConfirmation) {
            return AppPalette.vividRed
        }
        if DoctoralMilestoneOutcome(rawValue: candidate.halftimeOutcomeRaw ?? "") == .endedBefore ||
            DoctoralMilestoneOutcome(rawValue: candidate.plannedDisputationOutcomeRaw ?? "") == .endedBefore {
            return AppPalette.shadeRed
        }
        if DoctoralMilestoneOutcome(rawValue: candidate.plannedDisputationOutcomeRaw ?? "") == .completed ||
            doctoralDateIsPastOrToday(candidate.disputationDate) {
            return Color.gray.opacity(0.58)
        }
        if doctoralDateIsPastOrToday(candidate.admissionDate) {
            return AppPalette.shadeYellow
        }
        return Color.white
    }

    private func doctoralDateIsPastOrToday(_ rawDate: String) -> Bool {
        guard let date = rawDate.trimmedOrNil.flatMap(DateParsers.isoDay.date(from:)) else { return false }
        return Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: Date())
    }

    private func setSelectedCandidateID(_ id: String?) {
        guard selectedCandidateID != id else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
        selectedCandidateID = id
    }
}

private struct DoctoralCandidateCongressRow: Identifiable {
    let organizationID: String
    let organizationName: String
    let congress: OrganizationCongress

    var id: String { StoredCongressRecord.recordID(organizationID: organizationID, congressID: congress.id) }
}

private struct DoctoralCandidateDetailView: View {
    private enum SupervisorRowStatus {
        case planned
        case ongoing
        case endedWithoutDisputation
        case endedWithDisputation
    }

    @ObservedObject var store: GrantDataStore
    let candidate: DoctoralCandidateRecord

    @State private var draft: DoctoralCandidateRecord
    @State private var autosaveTask: DispatchWorkItem?
    @State private var forcedPersistTask: DispatchWorkItem?
    @State private var hasPendingLocalEdits = false
    @State private var needsDerivedLinkRefresh = false
    @State private var provisionalCourseIDs: Set<String> = []
    @State private var draggedSupervisorID: String?
    @State private var cachedEligiblePublicationChoices: [PublicationRecord] = []
    @State private var showsMilestoneSetup = false
    @State private var hasOfferedMilestoneSetup = false

    init(store: GrantDataStore, candidate: DoctoralCandidateRecord) {
        self.store = store
        self.candidate = candidate
        _draft = State(initialValue: candidate)
    }

    private var language: AppLanguage { store.language }

    private var eligiblePublicationChoices: [PublicationRecord] {
        cachedEligiblePublicationChoices
    }

    private var linkedPublications: [PublicationRecord] {
        let eligibleByID = Dictionary(firstWinsKeysWithValues: eligiblePublicationChoices.map { ($0.id, $0) })
        return draft.linkedPublicationIDs
            .compactMap { eligibleByID[$0] }
            .sorted(by: doctoralPublicationSortOrder)
    }

    private var availablePublicationChoices: [PublicationRecord] {
        let selectedIDs = Set(draft.linkedPublicationIDs)
        return eligiblePublicationChoices.filter { !selectedIDs.contains($0.id) }
    }

    private var candidateAuthor: PublicationAuthor? {
        draft.candidateAuthorID.flatMap(store.publicationAuthor(id:))
            ?? store.publicationAuthor(matchingPresentedName: draft.candidateName)
    }

    private var doctoralGroupMailAddresses: [String] {
        let authorIDs = [candidateAuthor?.id, draft.candidateAuthorID]
            .compactMap { $0 }
            + draft.supervisors.compactMap(\.authorID)
        let presentedNames = [draft.candidateName] + draft.supervisors.map(\.name)
        return store.groupMailAddresses(authorIDs: authorIDs, presentedNames: presentedNames)
    }

    private var eISPURL: URL? {
        normalizedWebLinkURL(draft.eISPLink)
    }

    private var eISPFieldState: AppFieldVisualState {
        AppFieldValidators.optionalURL(draft.eISPLink, language: language).state
    }

    private var visibleDocumentRows: [DoctoralCandidateDocument] {
        draft.documents.filter { !$0.isEmpty }
    }

    private var visibleCourseRows: [DoctoralCandidateCourse] {
        let rows = draft.isEditingLocked ? draft.courses.filter { !$0.isEmpty } : draft.courses
        return rows.sorted(by: doctoralCandidateCourseSortOrder)
    }

    private var linkedCongresses: [DoctoralCandidateCongressRow] {
        let startedAt = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            if duration >= 8 {
                store.appendPerformanceDiagnostic(
                    String(format: "doctoral-linked-congresses total_ms=%.2f", duration)
                )
            }
        }
        let normalizedCandidateName = PublicationDerivation.normalizedName(draft.candidateName)
        let authorID = candidateAuthor?.id ?? draft.candidateAuthorID
        return store.organizations.flatMap { organization in
            organization.congresses.compactMap { congress -> DoctoralCandidateCongressRow? in
                let matchesID = authorID.map(congress.participantAuthorIDs.contains) ?? false
                let matchesName = congress.participantNames.contains {
                    PublicationDerivation.normalizedName($0) == normalizedCandidateName
                }
                guard matchesID || (!normalizedCandidateName.isEmpty && matchesName) else { return nil }
                return DoctoralCandidateCongressRow(
                    organizationID: organization.id,
                    organizationName: localizedOrganizationName(organization),
                    congress: congress
                )
            }
        }
        .sorted {
            let leftDate = $0.congress.from.trimmedOrNil ?? $0.congress.to.trimmedOrNil ?? ""
            let rightDate = $1.congress.from.trimmedOrNil ?? $1.congress.to.trimmedOrNil ?? ""
            if leftDate != rightDate { return leftDate > rightDate }
            return $0.congress.title.localizedStandardCompare($1.congress.title) == .orderedAscending
        }
    }

    private var visibleSupervisorRows: [DoctoralSupervisorLink] {
        AppLockedFieldVisibility.visibleItems(
            draft.supervisors,
            isLocked: draft.isEditingLocked,
            isEmpty: { $0.isEmpty }
        )
    }

    private var visibleSupervisionPeriodRows: [DoctoralSupervisionPeriod] {
        AppLockedFieldVisibility.visibleItems(
            draft.supervisionPeriods,
            isLocked: draft.isEditingLocked,
            isEmpty: { $0.isEmpty }
        )
    }

    private var supervisionCalendarActivityMinutesByPeriodID: [String: Int] {
        // Kept in the store until the periods or the calendar change.
        store.doctoralSupervisionCalendarActivityMinutes(for: draft)
    }

    private var institutionDisplayName: String? {
        selectedInstitution.map(localizedOrganizationName) ?? draft.institution.trimmedOrNil
    }

    /// Brand-new candidates (no dates and no content yet) get a dialog to set
    /// the three key milestone dates right away.
    private func offerMilestoneSetupIfNeeded() {
        guard !hasOfferedMilestoneSetup else { return }
        hasOfferedMilestoneSetup = true
        guard !draft.isEditingLocked else { return }
        let hasAnyMilestoneDate = [
            draft.admissionDate,
            draft.planningSeminarDate,
            draft.halftimeDate,
            draft.estimatedHalftimeDate,
            draft.disputationDate,
            draft.plannedDisputationDate,
        ].contains { $0.trimmedOrNil != nil }
        let hasContent = !draft.courses.filter { !$0.isEmpty }.isEmpty
            || !draft.supervisors.filter { !$0.isEmpty }.isEmpty
            || !draft.linkedPublicationIDs.isEmpty
        guard !hasAnyMilestoneDate, !hasContent else { return }
        showsMilestoneSetup = true
    }

    private var shouldShowDoctoralProjectNameField: Bool {
        AppLockedFieldVisibility.shouldShow(isLocked: draft.isEditingLocked, value: draft.doctoralProjectName)
    }

    private var shouldShowInstitutionField: Bool {
        AppLockedFieldVisibility.shouldShow(isLocked: draft.isEditingLocked, value: institutionDisplayName)
    }

    private var shouldShowDoctoralCandidatePanel: Bool {
        !draft.isEditingLocked || shouldShowDoctoralProjectNameField || shouldShowInstitutionField
    }

    private var shouldShowSupervisorsPanel: Bool {
        AppLockedFieldVisibility.shouldShow(isLocked: draft.isEditingLocked, isRelevant: !visibleSupervisorRows.isEmpty)
    }

    private var shouldShowSupervisionPeriodsPanel: Bool {
        AppLockedFieldVisibility.shouldShow(isLocked: draft.isEditingLocked, isRelevant: !visibleSupervisionPeriodRows.isEmpty)
    }

    private var shouldShowLinkedPublicationsPanel: Bool {
        AppLockedFieldVisibility.shouldShow(
            isLocked: draft.isEditingLocked,
            isRelevant: !linkedPublications.isEmpty || !linkedCongresses.isEmpty
        )
    }

    private var shouldShowDocumentsPanel: Bool {
        !draft.isEditingLocked || !visibleDocumentRows.isEmpty
    }

    private var shouldShowCoursesPanel: Bool {
        !draft.isEditingLocked || !visibleCourseRows.isEmpty
    }

    private var shouldShowNotesPanel: Bool {
        AppLockedFieldVisibility.shouldShow(isLocked: draft.isEditingLocked, value: draft.notes)
    }

    private var shouldShowDoctoralTaskList: Bool {
        !draft.isEditingLocked || CentralTaskListSection.hasIncompleteTasks(
            store: store,
            linkKind: .doctoralCandidate,
            targetID: draft.id
        )
    }

    private var institutionChoices: [OrganizationRecord] {
        store.organizations
            .filter { $0.roles.contains(.institution) }
            .sorted { lhs, rhs in
                localizedOrganizationName(lhs).localizedStandardCompare(localizedOrganizationName(rhs)) == .orderedAscending
            }
    }

    private var candidateNameOptions: [String] {
        let names = store.publicationAuthors.map(\.name) + store.doctoralCandidates.map(\.candidateName)
        return Array(Set(names.compactMap(\.trimmedOrNil)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var supervisorNameOptions: [String] {
        candidateNameOptions
    }

    private var institutionNameOptions: [String] {
        institutionChoices.map(localizedOrganizationName)
    }

    private var doctoralStatisticsContributorNames: [String] {
        let candidateName = candidateAuthor?.displayName.nonEmpty ?? draft.candidateName.nonEmpty
        let supervisorNames = draft.supervisors.compactMap { supervisor -> String? in
            guard !supervisor.isEmpty else { return nil }
            return supervisor.authorID
                .flatMap(store.publicationAuthor(id:))?
                .displayName
                .nonEmpty
                ?? store.publicationAuthor(matchingPresentedName: supervisor.name)?.displayName.nonEmpty
                ?? supervisor.name.nonEmpty
        }
        var seen = Set<String>()
        return ([candidateName].compactMap { $0 } + supervisorNames).filter { name in
            seen.insert(PublicationDerivation.normalizedName(name)).inserted
        }
    }

    private var doctoralStatisticsPublications: [PublicationRecord] {
        draft.linkedPublicationIDs.compactMap(store.publication(id:))
    }

    private var doctoralStatisticsYearlyRows: [DoctoralStatisticsYearRow] {
        doctoralStatisticsYearRows(
            candidate: draft,
            publications: doctoralStatisticsPublications,
            journalForPublication: { store.linkedJournal(of: $0) }
        )
    }

    private var doctoralStatisticRows: [ContributorStatisticRow] {
        let completedCredits = doctoralStatisticsYearlyRows.map(\.completedCourseCredits).reduce(0, +)
        let plannedCredits = doctoralStatisticsYearlyRows.map(\.plannedCourseCredits).reduce(0, +)
        let completedHours = doctoralStatisticsYearlyRows.map(\.completedSupervisionHours).reduce(0, +)
        let plannedHours = doctoralStatisticsYearlyRows.map(\.plannedSupervisionHours).reduce(0, +)
        let jifTotal = doctoralStatisticsYearlyRows.map(\.impactFactorTotal).reduce(0, +)
        let jifCount = doctoralStatisticsYearlyRows.map(\.impactFactorCount).reduce(0, +)
        let norwegianLevel1 = doctoralStatisticsYearlyRows.map(\.norwegianLevel1Count).reduce(0, +)
        let norwegianLevel2 = doctoralStatisticsYearlyRows.map(\.norwegianLevel2Count).reduce(0, +)

        return [
            ContributorStatisticRow(
                label: language.text("Course credits", "Högskolepoäng"),
                value: "\(doctoralStatisticsNumber(completedCredits)) hp",
                detail: language.text(
                    "completed · \(doctoralStatisticsNumber(plannedCredits)) credits planned",
                    "genomförda · \(doctoralStatisticsNumber(plannedCredits)) hp planerade"
                )
            ),
            ContributorStatisticRow(
                label: language.text("Publications", "Publikationer"),
                value: "\(doctoralStatisticsPublications.count)"
            ),
            ContributorStatisticRow(
                label: "JIF",
                value: jifCount > 0 ? doctoralStatisticsNumber(jifTotal / Double(jifCount)) : "—",
                detail: jifCount > 0
                    ? language.text("mean · \(doctoralStatisticsNumber(jifTotal)) total", "medel · \(doctoralStatisticsNumber(jifTotal)) totalt")
                    : language.text("No registered values", "Inga registrerade värden")
            ),
            ContributorStatisticRow(
                label: language.text("Norwegian list", "Norska listan"),
                value: "\(norwegianLevel2)",
                detail: language.text("level 2 · \(norwegianLevel1) level 1", "nivå 2 · \(norwegianLevel1) nivå 1")
            ),
            ContributorStatisticRow(
                label: language.text("Supervision effort", "Handledarinsats"),
                value: "\(doctoralStatisticsNumber(completedHours)) h",
                detail: language.text(
                    "completed · \(doctoralStatisticsNumber(plannedHours)) h planned",
                    "genomförda · \(doctoralStatisticsNumber(plannedHours)) h planerade"
                )
            ),
        ]
    }

    private var doctoralStatisticsTable: ContributorStatisticsTable? {
        let rows = doctoralStatisticsYearlyRows.map { row in
            ContributorStatisticsTable.Row(
                year: "\(row.year)",
                values: [
                    "\(doctoralStatisticsNumber(row.completedCourseCredits)) / \(doctoralStatisticsNumber(row.plannedCourseCredits))",
                    "\(row.publicationCount)",
                    row.averageImpactFactor.map(doctoralStatisticsNumber) ?? "—",
                    "\(row.norwegianLevel1Count) / \(row.norwegianLevel2Count)",
                    "\(doctoralStatisticsNumber(row.completedSupervisionHours)) / \(doctoralStatisticsNumber(row.plannedSupervisionHours))",
                ]
            )
        }
        guard !rows.isEmpty else { return nil }
        return ContributorStatisticsTable(
            title: language.text("Year by year", "År för år"),
            columnTitles: [
                language.text("Year", "År"),
                language.text("Credits done / planned", "Hp genomf. / plan."),
                language.text("Publications", "Publ."),
                language.text("Mean JIF", "JIF medel"),
                language.text("Norwegian 1 / 2", "Norska 1 / 2"),
                language.text("Hours done / planned", "Timmar genomf. / plan."),
            ],
            rows: rows
        )
    }

    private func doctoralStatisticsNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = language == .english ? "." : ","
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 1
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    if draft.isEditingLocked {
                        Text(draft.candidateName.trimmedOrNil ?? language.text("Doctoral candidate", "Doktorand"))
                            .font(appFont(.pageTitle))
                            .foregroundStyle(AppPalette.appText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        AutocompleteSelectionField(
                            text: binding(\.candidateName),
                            options: candidateNameOptions,
                            placeholder: language.text("Doctoral candidate", "Doktorand"),
                            onCommit: {
                                requestImmediatePersist()
                            },
                            onSelect: { selected in
                                draft.candidateName = selected
                                requestImmediatePersist()
                            },
                            usesTransparentFieldStyle: false,
                            showsSuggestionsWithoutQuery: true,
                            appliesChrome: false,
                            textFont: appNSFont(.pageTitle)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let eISPURL {
                        Button {
                            NSWorkspace.shared.open(eISPURL)
                        } label: {
                            Label("eISP", systemImage: "link")
                                .font(appFont(.secondary).weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(AppPalette.linkAction)
                        .help(language.text("Open eISP", "Öppna eISP"))
                    }

                    if let candidateAuthor {
                        Button {
                            store.openRoute(for: candidateAuthor)
                        } label: {
                            Label(language.text("Person card", "Personkort"), systemImage: "person.crop.rectangle")
                                .font(appFont(.secondary).weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(AppPalette.linkAction)
                        .help(language.text("Open person card in the app", "Öppna personkort i appen"))
                    }

                    Spacer(minLength: 0)

                    doctoralEditorLockButton(language: language)

                    if !draft.isEditingLocked {
                        // Round 16: ask before deleting, like the other record views.
                        DeleteActionButton(
                            title: language.text("Delete", "Ta bort"),
                            confirmationTitle: language.text("Delete doctoral candidate?", "Ta bort doktorand?"),
                            confirmationMessage: language.text("The deletion can be undone.", "Borttagningen kan ångras."),
                            cancelTitle: language.text("Cancel", "Avbryt")
                        ) {
                            store.deleteDoctoralCandidate(id: draft.id)
                        }
                    }
                }

                DoctoralRecordHeroView(
                    store: store,
                    candidate: draft,
                    isLocked: draft.isEditingLocked,
                    language: language,
                    admissionDate: dateBinding(\.admissionDate),
                    admissionPreliminary: boolBinding(\.admissionDatePreliminary),
                    admissionOutcomeRaw: optionalBinding(\.admissionOutcomeRaw),
                    planningSeminarDate: dateBinding(\.planningSeminarDate),
                    planningSeminarPreliminary: boolBinding(\.planningSeminarDatePreliminary),
                    planningSeminarOutcomeRaw: optionalBinding(\.planningSeminarOutcomeRaw),
                    halftimeDate: dateBinding(\.halftimeDate),
                    halftimePreliminary: boolBinding(\.halftimeDatePreliminary),
                    halftimeOutcomeRaw: optionalBinding(\.halftimeOutcomeRaw),
                    estimatedHalftimeDate: dateBinding(\.estimatedHalftimeDate),
                    disputationDate: dateBinding(\.disputationDate),
                    disputationPreliminary: boolBinding(\.disputationDatePreliminary),
                    disputationOutcomeRaw: optionalBinding(\.plannedDisputationOutcomeRaw),
                    plannedDisputationDate: dateBinding(\.plannedDisputationDate)
                )
                .padding(.top, 2)
                .sheet(isPresented: $showsMilestoneSetup) {
                    DoctoralMilestoneSetupSheet(
                        admissionDate: dateBinding(\.admissionDate),
                        estimatedHalftimeDate: dateBinding(\.estimatedHalftimeDate),
                        plannedDisputationDate: dateBinding(\.plannedDisputationDate),
                        language: language,
                        onDone: { showsMilestoneSetup = false }
                    )
                }
                .onAppear {
                    offerMilestoneSetupIfNeeded()
                }

                if shouldShowDoctoralCandidatePanel {
                    VStack(alignment: .leading, spacing: 10) {
                        AppSectionDividerHeading(text: language.text("Doctoral candidate", "Doktorand"))
                        HStack(alignment: .top, spacing: 10) {
                            doctoralProjectNameField
                        }
                        institutionField
                        if !draft.isEditingLocked || draft.eISPLink.trimmedOrNil != nil {
                            VStack(alignment: .leading, spacing: 6) {
                                AppFieldLabelText(text: "eISP")
                                if draft.isEditingLocked {
                                    lockedDoctoralValueText(draft.eISPLink)
                                } else {
                                    eISPInputField
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.clear)
                    )
                }

                if shouldShowSupervisorsPanel {
                    VStack(alignment: .leading, spacing: 6) {
                        AppSectionDividerHeading(text: language.text("Supervisors (top row is main supervisor)", "Handledare (överst är huvudhandledare)"))

                        ForEach(Array(visibleSupervisorRows.enumerated()), id: \.element.id) { index, supervisor in
                            let rowIsPlaceholder = supervisor.isEmpty
                            let rowIsExpired = supervisorRowIsExpired(supervisor)
                            let rowHasIllogicalDateRange = validationDateRangeIsIllogical(from: supervisor.from, to: supervisor.to)
                            let rowStatus = supervisorRowStatus(supervisor)
                            HStack(spacing: 4) {
                                if draft.isEditingLocked {
                                    EmptyView()
                                } else if rowIsPlaceholder {
                                    Color.clear
                                        .frame(width: 20, height: 20)
                                } else {
                                    ReorderHandle(itemID: supervisor.id, draggedItemID: $draggedSupervisorID, language: language)
                                }

                                if draft.isEditingLocked {
                                    lockedDoctoralValueText(supervisor.name)
                                        .frame(width: 220, alignment: .leading)
                                } else {
                                    supervisorNameField(index: index, usesAlertBackground: rowIsExpired)
                                        .frame(width: 220)
                                }

                                if draft.isEditingLocked {
                                    lockedDoctoralValueText(supervisor.from, isInvalid: rowHasIllogicalDateRange)
                                        .frame(width: 120, alignment: .leading)
                                    lockedDoctoralValueText(supervisor.to, isInvalid: rowHasIllogicalDateRange)
                                        .frame(width: 120, alignment: .leading)
                                } else {
                                    AppDateField(
                                        placeholder: language.text("From", "Från"),
                                        text: supervisorDateBinding(index, \.from),
                                        width: 120,
                                        language: language,
                                        state: rowHasIllogicalDateRange ? doctoralIllogicalDateState : .normal
                                    )

                                    AppDateField(
                                        placeholder: language.text("To", "Till"),
                                        text: supervisorDateBinding(index, \.to),
                                        width: 120,
                                        language: language,
                                        state: rowHasIllogicalDateRange ? doctoralIllogicalDateState : .normal
                                    )
                                }

                                if rowIsPlaceholder || (draft.isEditingLocked && index == visibleSupervisorRows.indices.last) {
                                    GroupMailButton(addresses: doctoralGroupMailAddresses, language: language)
                                }

                                if let supervisor = store.publicationAuthor(matchingPresentedName: supervisor.name) {
                                    doctoralRecordLinkButton(
                                        help: language.text("Open supervisor", "Öppna handledare")
                                    ) {
                                        store.openRoute(for: supervisor)
                                    }
                                } else {
                                    Color.clear.frame(width: 28, height: 28)
                                }

                                Spacer(minLength: 8)
                                if !rowIsPlaceholder {
                                    Text(supervisorStatusText(rowStatus))
                                        .font(appFont(.secondary).weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(width: 176, alignment: .trailing)
                                }

                                if !rowIsPlaceholder && !draft.isEditingLocked {
                                    AppInlineDeleteButton(
                                        title: language.text("Delete supervisor", "Ta bort handledare"),
                                        width: 34
                                    ) {
                                        removeSupervisor(at: index)
                                    }
                                } else {
                                    Color.clear.frame(width: 34, height: 1)
                                }
                            }
                            .padding(.leading, rowIsPlaceholder ? 0 : 10)
                            .padding(.vertical, 0)
                            .background(
                                Group {
                                    if rowIsPlaceholder {
                                        Color.clear
                                    } else {
                                        StatusIndicatorListRowBackground(
                                            fill: supervisorStatusColor(rowStatus),
                                            indicatorWidth: 6,
                                            cornerRadius: 8
                                        )
                                    }
                                }
                            )
                            .onDrop(of: [UTType.plainText], delegate: IdentifiedReorderDropDelegate(
                                targetID: supervisor.id,
                                items: $draft.supervisors,
                                draggedItemID: $draggedSupervisorID,
                                onReorder: {
                                    ensureSupervisorPlaceholder()
                                    scheduleAutosave()
                                }
                            ))
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.clear)
                    )
                }

                if shouldShowSupervisionPeriodsPanel {
                    VStack(alignment: .leading, spacing: 6) {
                        AppPanelHeadingText(text: language.text("Your supervision effort per period (hours per semester)", "Din handledarinsats per tidsperiod (timmar per termin)"))

                        ForEach(Array(visibleSupervisionPeriodRows.enumerated()), id: \.element.id) { index, period in
                            let placeholder = period.isEmpty
                            let periodHasIllogicalDateRange = validationDateRangeIsIllogical(from: period.from, to: period.to)
                            HStack(spacing: 8) {
                                // Round 12: red bar while not confirmed in Retendo.
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(period.needsRetendoConfirmation ? AppPalette.vividRed : Color.clear)
                                    .frame(width: 3, height: 22)
                                    .help(period.needsRetendoConfirmation ? language.text("Not confirmed in Retendo", "Inte bekräftad i Retendo") : "")
                                if draft.isEditingLocked {
                                    lockedDoctoralValueText(period.from, isInvalid: periodHasIllogicalDateRange)
                                        .frame(width: 120, alignment: .leading)
                                    lockedDoctoralValueText(period.to, isInvalid: periodHasIllogicalDateRange)
                                        .frame(width: 120, alignment: .leading)
                                    lockedDoctoralValueText(period.hoursPerSemester)
                                        .frame(width: 100, alignment: .leading)
                                    lockedDoctoralValueText(supervisionCalendarActivityHoursText(for: period))
                                        .frame(width: 110, alignment: .leading)
                                    lockedDoctoralValueText(supervisionAccruedHoursText(for: period))
                                        .frame(width: 110, alignment: .leading)
                                    if period.confirmedInRetendo {
                                        lockedDoctoralValueText(language.text("Retendo", "Retendo"))
                                    }
                                } else {
                                    AppDateField(
                                        placeholder: language.text("From", "Från"),
                                        text: supervisionPeriodDateBinding(index, \.from),
                                        width: 120,
                                        language: language,
                                        state: periodHasIllogicalDateRange ? doctoralIllogicalDateState : .normal
                                    )
                                    AppDateField(
                                        placeholder: language.text("To", "Till"),
                                        text: supervisionPeriodDateBinding(index, \.to),
                                        width: 120,
                                        language: language,
                                        state: periodHasIllogicalDateRange ? doctoralIllogicalDateState : .normal
                                    )
                                    AppCommitTextField(
                                        placeholder: language.text("Hours", "Timmar"),
                                        text: supervisionPeriodBinding(index, \.hoursPerSemester),
                                        formatter: AppFieldParsers.canonicalHours,
                                        width: 100,
                                        state: AppFieldValidators.optionalNumeric(supervisionPeriodBinding(index, \.hoursPerSemester).wrappedValue, language: language).state,
                                        liveVisualState: { AppFieldValidators.optionalNumeric($0, language: language).state },
                                        horizontalPadding: 8,
                                        verticalPadding: 4
                                    )
                                    VStack(alignment: .leading, spacing: 2) {
                                        if index == 0 {
                                            AppTableHeaderText(text: language.text("Activity hours", "Aktivitetstimmar"))
                                        }
                                        Text(supervisionCalendarActivityHoursText(for: period))
                                            .font(appFont(.body).weight(.medium))
                                            .foregroundStyle(supervisionCalendarActivityMinutesByPeriodID[period.id, default: 0] > 0 ? AppPalette.appText : .secondary)
                                            .frame(height: AppPalette.fieldMinHeight, alignment: .center)
                                    }
                                    .frame(width: 110, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 2) {
                                        if index == 0 {
                                            AppTableHeaderText(text: language.text("Total so far", "Summa hittills"))
                                        }
                                        Text(supervisionAccruedHoursText(for: period))
                                            .font(appFont(.body).weight(.medium))
                                            .foregroundStyle((period.accruedSupervisionHours() ?? 0) > 0 ? AppPalette.appText : .secondary)
                                            .frame(height: AppPalette.fieldMinHeight, alignment: .center)
                                    }
                                    .frame(width: 110, alignment: .leading)
                                    Toggle(language.text("Retendo", "Retendo"), isOn: supervisionRetendoBinding(index))
                                        .appCheckboxStyle()
                                }
                                Spacer(minLength: 0)
                                if !placeholder && !draft.isEditingLocked {
                                    Button(role: .destructive) {
                                        removeSupervisionPeriod(at: index)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(AppPalette.actionDelete)
                                    }
                                    .buttonStyle(.bordered)
                                } else {
                                    Color.clear.frame(width: 34, height: 1)
                                }
                            }
                        }
                        if let totalText = supervisionAccruedTotalText {
                            Text(totalText)
                                .font(appFont(.body).weight(.semibold))
                                .foregroundStyle(AppPalette.appText)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.clear)
                    )
                }

                if shouldShowDocumentsPanel {
                    doctoralDocumentsPanel
                }

                if shouldShowCoursesPanel {
                    doctoralCoursesPanel
                }

                if shouldShowLinkedPublicationsPanel {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Text(language.text("Linked publications", "Kopplade publikationer"))
                                .appTypography(.sectionTitle)
                                .foregroundStyle(AppPalette.appText)
                            if !draft.isEditingLocked {
                                Menu {
                                    ForEach(availablePublicationChoices) { publication in
                                        Button(publication.title) {
                                            addPublicationLink(publication.id)
                                        }
                                    }
                                } label: {
                                    Text(language.text("Add publication", "Lägg till publikation"))
                                }
                                .menuStyle(.borderlessButton)
                                .disabled(availablePublicationChoices.isEmpty)
                            }
                            Rectangle()
                                .fill(AppPalette.subtleBorder.opacity(AppRuntime.usesRenewedChrome ? 0.9 : 1))
                                .frame(height: 1)
                        }

                        if !draft.isEditingLocked {
                            if draft.candidateName.trimmedOrNil == nil {
                                Text(language.text("Enter the doctoral candidate name to choose matching publications.", "Fyll i doktorandens namn för att kunna välja matchande publikationer."))
                                    .font(appFont(.secondary))
                                    .foregroundStyle(.secondary)
                            } else if eligiblePublicationChoices.isEmpty {
                                Text(language.text("No publications with this doctoral candidate in the author list were found.", "Inga publikationer med denna doktorand i författarlistan hittades."))
                                    .font(appFont(.secondary))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !linkedPublications.isEmpty {
                            HStack(spacing: 8) {
                                AppTableHeaderText(text: language.text("Status", "Status"))
                                    .frame(width: 112, alignment: .leading)
                                AppTableHeaderText(text: language.text("Title", "Titel"))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                AppTableHeaderText(text: language.text("Year", "År"))
                                    .frame(width: 48, alignment: .leading)
                                AppTableHeaderText(text: language.text("Journal", "Tidskrift"))
                                    .frame(width: 130, alignment: .leading)
                                AppTableHeaderText(text: "IF")
                                    .frame(width: 50, alignment: .leading)
                                AppTableHeaderText(text: language.text("Norwegian list", "Norska listan"))
                                    .frame(width: 82, alignment: .leading)
                                Color.clear.frame(width: 16, height: 1)
                                if !draft.isEditingLocked {
                                    Color.clear.frame(width: 34, height: 1)
                                }
                            }
                            .padding(.horizontal, 10)
                        }

                        ForEach(linkedPublications) { publication in
                            HStack(alignment: .center, spacing: 8) {
                                Button {
                                    store.route = AppRoute(recordID: publication.id, destination: .publications)
                                } label: {
                                    HStack(alignment: .center, spacing: 8) {
                                        DoctoralPublicationStatusBadge(status: publication.statusLabel, language: language)
                                            .frame(width: 112, alignment: .leading)
                                        Text(publication.title)
                                            .font(appFont(.body))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(publication.year.nonEmpty ?? "—")
                                            .frame(width: 48, alignment: .leading)
                                        Text(publication.journal.nonEmpty ?? "—")
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .frame(width: 130, alignment: .leading)
                                        Text(doctoralPublicationImpactFactor(publication))
                                            .frame(width: 50, alignment: .leading)
                                        Text(doctoralPublicationNorwegianLevel(publication))
                                            .frame(width: 82, alignment: .leading)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 16)
                                    }
                                }
                                .buttonStyle(.plain)

                                if !draft.isEditingLocked {
                                    Button(role: .destructive) {
                                        removePublicationLink(publication.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(AppPalette.actionDelete)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.clear)
                    )
                }

                if !linkedCongresses.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        AppSectionDividerHeading(text: language.text("Conference participation", "Konferensmedverkan"))
                        ForEach(linkedCongresses) { row in
                            Button {
                                store.openRouteToCongress(
                                    organizationID: row.organizationID,
                                    congressID: row.congress.id
                                )
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.congress.title)
                                            .font(appFont(.body).weight(.medium))
                                            .foregroundStyle(AppPalette.appText)
                                        Text(congressSubtitle(row))
                                            .font(appFont(.secondary))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Text(congressDateText(row.congress))
                                        .font(appFont(.secondary))
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                }

                if shouldShowNotesPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        AppSectionDividerHeading(text: language.text("Notes", "Notering"))
                        if draft.isEditingLocked {
                            lockedDoctoralValueText(draft.notes)
                                .lineLimit(nil)
                                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                        } else {
                            AppTextEditorField(
                                title: nil,
                                text: binding(\.notes),
                                minimumHeight: 100
                            )
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.clear)
                    )
                }

                if shouldShowDoctoralTaskList {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            AppPanelHeadingText(text: language.text("Task list", "Uppgiftslista"))
                            if !draft.isEditingLocked {
                                AppIconAddButton(title: language.text("Add task", "Lägg till uppgift")) {
                                    CentralTaskListSection.addTask(store: store, linkKind: .doctoralCandidate, targetID: draft.id)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        CentralTaskListSection(
                            store: store,
                            linkKind: .doctoralCandidate,
                            targetID: draft.id,
                            language: language,
                            reminderOptions: ProjectTaskReminder.allCases,
                            isReadOnly: draft.isEditingLocked,
                            showsAddButton: false
                        )
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.clear)
                    )
                }

                // Round 7: every activity and task linked to the candidate by id.
                VStack(alignment: .leading, spacing: 10) {
                    AppPanelHeadingText(text: language.text("Linked activities and tasks", "Kopplade aktiviteter och uppgifter"))
                    CalendarLinkedActivitiesAndTasksList(
                        store: store,
                        language: language,
                        scope: .doctoralCandidate(draft.id)
                    )
                }
                .padding(12)
            }
            .padding(14)
        }
        .onAppear {
            syncDraft(from: candidate, force: true)
            refreshEligiblePublicationChoices()
        }
        .flushPendingAutosaveOnTextEnd(requestImmediatePersist)
        .onChange(of: candidate) { _, newCandidate in
            syncDraft(from: newCandidate, force: false)
        }
        .onChange(of: store.publicationRecords.map(\.id)) { _, _ in
            refreshEligiblePublicationChoices()
        }
        .onDisappear {
            NSApp.keyWindow?.makeFirstResponder(nil)
            autosaveTask?.cancel()
            forcedPersistTask?.cancel()
            flushAutosaveNow()
        }
    }

    private var candidateNameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            AppFieldLabelText(text: language.text("Doctoral candidate", "Doktorand"))
            AutocompleteSelectionField(
                text: binding(\.candidateName),
                options: candidateNameOptions,
                placeholder: language.text("Name", "Namn"),
                onCommit: {
                    scheduleAutosave()
                },
                onSelect: { _ in
                    scheduleAutosave()
                }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var institutionField: some View {
        if shouldShowInstitutionField {
            VStack(alignment: .leading, spacing: 6) {
                AppFieldLabelText(text: language.text("Institution", "Lärosäte"))
                HStack(spacing: 8) {
                    if draft.isEditingLocked {
                        lockedDoctoralValueText(institutionDisplayName)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        AutocompleteSelectionField(
                            text: binding(\.institution),
                            options: institutionNameOptions,
                            placeholder: language.text("Institution", "Lärosäte"),
                            onCommit: {
                                draft.institutionID = institutionMatchingName(draft.institution)?.id
                                scheduleAutosave()
                            },
                            onSelect: { selected in
                                draft.institution = selected
                                draft.institutionID = institutionMatchingName(selected)?.id
                                scheduleAutosave()
                            }
                        )
                    }

                    if let institution = selectedInstitution {
                        doctoralRecordLinkButton(
                            help: language.text("Open institution", "Öppna lärosäte")
                        ) {
                            store.openRoute(for: institution)
                        }
                    } else if !draft.isEditingLocked {
                        Color.clear.frame(width: 28, height: 28)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var doctoralProjectNameField: some View {
        if shouldShowDoctoralProjectNameField {
            VStack(alignment: .leading, spacing: 6) {
                AppFieldLabelText(text: language.text("Doctoral project name", "Doktorandprojekt"))
                if draft.isEditingLocked {
                    lockedDoctoralValueText(draft.doctoralProjectName)
                } else {
                    TextField(
                        language.text("Doctoral project name", "Doktorandprojekt"),
                        text: binding(\.doctoralProjectName)
                    )
                    .appTextInputChrome()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var eISPInputField: some View {
        TextField(
            language.text("Link to eISP", "Länk till eISP"),
            text: Binding(
                get: { draft.eISPLink },
                set: { value in
                    draft.eISPLink = value
                    scheduleAutosave()
                }
            )
        )
        .appTextInputChrome(fill: eISPFieldState.fill, stroke: eISPFieldState.stroke)
        .help(eISPFieldState.helpText ?? "")
    }

    /// F1b: the document is shown under a name built from the candidate and
    /// the document row; the original file name is the tooltip.
    private func doctoralDocumentDisplayLabel(_ document: DoctoralCandidateDocument) -> String {
        AttachmentLabels.doctoralDocument(document, candidateName: draft.candidateName, language: language)
            ?? document.filename?.trimmedOrNil
            ?? "PDF"
    }

    private func doctoralDocumentOriginalFilenameHelp(_ document: DoctoralCandidateDocument) -> String {
        guard let original = document.filename?.trimmedOrNil else { return "" }
        return language.text("Original file name: \(original)", "Ursprungligt filnamn: \(original)")
    }

    private var doctoralDocumentsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AppSectionDividerHeading(text: language.text("Documents", "Dokument"))
                if !draft.isEditingLocked {
                    AppIconAddButton(title: language.text("Upload PDFs", "Ladda upp PDF:er")) {
                        chooseDoctoralCandidatePDFs()
                    }
                }
            }

            ForEach(Array(visibleDocumentRows.enumerated()), id: \.element.id) { _, document in
                if let index = draft.documents.firstIndex(where: { $0.id == document.id }) {
                    HStack(spacing: 8) {
                        if draft.isEditingLocked {
                            lockedDoctoralValueText(document.date)
                                .frame(width: 120, alignment: .leading)
                            lockedDoctoralValueText(document.title)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            AppDateField(
                                placeholder: language.text("Date", "Datum"),
                                text: doctoralDocumentDateBinding(index),
                                width: 120,
                                language: language
                            )
                            TextField(language.text("Title", "Titel"), text: doctoralDocumentBinding(index, \.title))
                                .appTextInputChrome()
                        }

                        Button {
                            openDoctoralCandidatePDF(document)
                        } label: {
                            Label(
                                doctoralDocumentDisplayLabel(document),
                                systemImage: "doc.richtext"
                            )
                            .font(appFont(.secondary).weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        }
                        .help(doctoralDocumentOriginalFilenameHelp(document))
                        .buttonStyle(.borderless)
                        .foregroundStyle(AppPalette.linkAction)
                        .disabled(GrantDataStore.resolveDoctoralCandidatePDFURL(document: document) == nil)
                        .frame(maxWidth: 190, alignment: .trailing)

                        if !draft.isEditingLocked {
                            AppInlineDeleteButton(
                                title: language.text("Delete document", "Ta bort dokument"),
                                width: 34
                            ) {
                                removeDoctoralDocument(id: document.id)
                            }
                        }
                    }
                }
            }

            if visibleDocumentRows.isEmpty {
                Text(language.text("No documents uploaded.", "Inga dokument uppladdade."))
                    .font(appFont(.secondary))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private var doctoralCoursesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AppSectionDividerHeading(text: language.text("Courses", "Kurser"))
                if !draft.isEditingLocked {
                    AppIconAddButton(title: language.text("Add course", "Lägg till kurs")) {
                        addDoctoralCourse()
                    }
                }
            }

            if !visibleCourseRows.isEmpty {
                HStack(spacing: 8) {
                    AppTableHeaderText(text: language.text("Year", "År"))
                        .frame(width: 90, alignment: .leading)
                    AppTableHeaderText(text: language.text("Course", "Kurs"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    AppTableHeaderText(text: language.text("Credits", "hp"))
                        .frame(width: 100, alignment: .leading)
                    AppTableHeaderText(text: language.text("Completed on", "Datum genomförd"))
                        .frame(width: 130, alignment: .leading)
                    if !draft.isEditingLocked {
                        Color.clear.frame(width: 34, height: 1)
                    }
                }
                .padding(.leading, 10)
            }

            ForEach(Array(visibleCourseRows.enumerated()), id: \.element.id) { _, course in
                if let index = draft.courses.firstIndex(where: { $0.id == course.id }) {
                    HStack(spacing: 8) {
                        if draft.isEditingLocked {
                            lockedDoctoralValueText(course.year)
                                .frame(width: 90, alignment: .leading)
                            lockedDoctoralValueText(course.title)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            lockedDoctoralValueText(course.credits)
                                .frame(width: 100, alignment: .leading)
                            lockedDoctoralValueText(course.completedOn)
                                .frame(width: 130, alignment: .leading)
                        } else {
                            AppYearField(
                                text: doctoralCourseBinding(index, \.year),
                                language: language,
                                width: 90
                            )
                            TextField(language.text("Course title", "Kurstitel"), text: doctoralCourseBinding(index, \.title))
                                .appTextInputChrome()
                            AppCommitTextField(
                                placeholder: language.text("Credits", "hp"),
                                text: doctoralCourseBinding(index, \.credits),
                                formatter: { AppFieldParsers.canonicalDecimal($0) },
                                width: 100,
                                state: AppFieldValidators.optionalNumeric(course.credits, language: language).state,
                                liveVisualState: { AppFieldValidators.optionalNumeric($0, language: language).state }
                            )
                            AppDateField(
                                placeholder: language.text("Completed on", "Datum genomförd"),
                                text: doctoralCourseCompletionDateBinding(index),
                                width: 130,
                                language: language
                            )
                            AppInlineDeleteButton(
                                title: language.text("Delete course", "Ta bort kurs"),
                                width: 34
                            ) {
                                removeDoctoralCourse(id: course.id)
                            }
                        }
                    }
                    .padding(.leading, 10)
                    .background {
                        StatusIndicatorListRowBackground(
                            fill: doctoralCourseStatusColor(course),
                            indicatorWidth: 6,
                            cornerRadius: 8
                        )
                    }
                }
            }

            if visibleCourseRows.isEmpty {
                Text(language.text("No courses added.", "Inga kurser tillagda."))
                    .font(appFont(.secondary))
                    .foregroundStyle(.secondary)
            }

            if !visibleCourseRows.isEmpty {
                Text(doctoralCourseCreditsSummary)
                    .font(appFont(.secondary).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 2)
            }
        }
        .padding(12)
    }

    private func doctoralEditorLockButton(language: AppLanguage) -> some View {
        AppEditorLockButton(isLocked: draft.isEditingLocked, language: language) {
            let nextValue = !draft.isEditingLocked
            if nextValue {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
            draft.isEditingLocked = nextValue
            requestImmediatePersist()
        }
    }

    private func lockedDoctoralValueText(_ value: String?, isInvalid: Bool = false) -> some View {
        AppLockedFieldValueText(text: value, isInvalid: isInvalid)
            .help(isInvalid ? language.text("Illogical date combination", "Ologisk datumkombination") : "")
    }

    private var doctoralIllogicalDateState: AppFieldVisualState {
        .invalid(language.text("Illogical date combination", "Ologisk datumkombination"))
    }

    private func binding(_ keyPath: WritableKeyPath<DoctoralCandidateRecord, String>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { newValue in
                draft[keyPath: keyPath] = newValue
                scheduleAutosave()
            }
        )
    }

    private func dateBinding(_ keyPath: WritableKeyPath<DoctoralCandidateRecord, String>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { newValue in
                draft[keyPath: keyPath] = DateParsers.canonicalizedDayInput(newValue)
                scheduleAutosave()
            }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<DoctoralCandidateRecord, Bool>) -> Binding<Bool> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { newValue in
                draft[keyPath: keyPath] = newValue
                scheduleAutosave()
            }
        )
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<DoctoralCandidateRecord, String?>) -> Binding<String?> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { newValue in
                draft[keyPath: keyPath] = newValue?.trimmedOrNil
                scheduleAutosave()
            }
        )
    }

    private func supervisorNameBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard draft.supervisors.indices.contains(index) else { return "" }
                return draft.supervisors[index].name
            },
            set: { newName in
                guard draft.supervisors.indices.contains(index) else { return }
                draft.supervisors[index].name = newName
                ensureSupervisorPlaceholder()
                scheduleAutosave()
            }
        )
    }

    private func supervisorNameField(index: Int, usesAlertBackground: Bool) -> some View {
        AutocompleteSelectionField(
            text: supervisorNameBinding(index),
            options: supervisorNameOptions,
            excludedOptions: supervisorExcludedOptions(for: index),
            placeholder: language.text("Supervisor name", "Handledarnamn"),
            onCommit: {
                ensureSupervisorPlaceholder()
                scheduleAutosave()
            },
            onSelect: { _ in
                ensureSupervisorPlaceholder()
                scheduleAutosave()
            },
            usesTransparentFieldStyle: false
        )
    }

    private var selectedInstitution: OrganizationRecord? {
        draft.institutionID.flatMap { store.organization(id: $0) }
            ?? institutionMatchingName(draft.institution)
    }

    private func institutionMatchingName(_ name: String) -> OrganizationRecord? {
        store.organization(matchingName: name)
            ?? institutionChoices.first {
                localizedOrganizationName($0).localizedCaseInsensitiveCompare(name) == .orderedSame
            }
    }

    private func supervisorAuthor(at index: Int) -> PublicationAuthor? {
        guard draft.supervisors.indices.contains(index),
              let name = draft.supervisors[index].name.trimmedOrNil else {
            return nil
        }
        return store.publicationAuthor(matchingPresentedName: name)
    }

    private func doctoralRecordLinkButton(help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            AppLinkDestinationLabel(kind: .app, language: language, fontSize: 12)
                .frame(width: 42, height: 28)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func supervisorExcludedOptions(for index: Int) -> Set<String> {
        Set(draft.supervisors.enumerated().compactMap { offset, supervisor in
            guard offset != index else { return nil }
            return supervisor.name.trimmedOrNil
        })
    }

    private func supervisorDateBinding(
        _ index: Int,
        _ keyPath: WritableKeyPath<DoctoralSupervisorLink, String>
    ) -> Binding<String> {
        Binding(
            get: {
                guard draft.supervisors.indices.contains(index) else { return "" }
                return draft.supervisors[index][keyPath: keyPath]
            },
            set: { value in
                guard draft.supervisors.indices.contains(index) else { return }
                let normalizedValue = DateParsers.canonicalizedDayInput(value)
                let previousFrom = draft.supervisors[index].from
                draft.supervisors[index][keyPath: keyPath] = normalizedValue
                if keyPath == \DoctoralSupervisorLink.from,
                   let shiftedTo = shiftedDateRangeEnd(
                       previousStart: previousFrom,
                       newStart: normalizedValue,
                       currentEnd: draft.supervisors[index].to
                   ) {
                    draft.supervisors[index].to = shiftedTo
                }
                ensureSupervisorPlaceholder()
                scheduleAutosave()
            }
        )
    }

    private func supervisionPeriodBinding(
        _ index: Int,
        _ keyPath: WritableKeyPath<DoctoralSupervisionPeriod, String>
    ) -> Binding<String> {
        Binding(
            get: {
                guard draft.supervisionPeriods.indices.contains(index) else { return "" }
                return draft.supervisionPeriods[index][keyPath: keyPath]
            },
            set: { value in
                guard draft.supervisionPeriods.indices.contains(index) else { return }
                draft.supervisionPeriods[index][keyPath: keyPath] = value
                scheduleAutosave()
            }
        )
    }

    private func supervisionPeriodDateBinding(
        _ index: Int,
        _ keyPath: WritableKeyPath<DoctoralSupervisionPeriod, String>
    ) -> Binding<String> {
        Binding(
            get: {
                guard draft.supervisionPeriods.indices.contains(index) else { return "" }
                return draft.supervisionPeriods[index][keyPath: keyPath]
            },
            set: { value in
                guard draft.supervisionPeriods.indices.contains(index) else { return }
                let normalizedValue = DateParsers.canonicalizedDayInput(value)
                let previousFrom = draft.supervisionPeriods[index].from
                draft.supervisionPeriods[index][keyPath: keyPath] = normalizedValue
                if keyPath == \DoctoralSupervisionPeriod.from,
                   let shiftedTo = shiftedDateRangeEnd(
                       previousStart: previousFrom,
                       newStart: normalizedValue,
                       currentEnd: draft.supervisionPeriods[index].to
                   ) {
                    draft.supervisionPeriods[index].to = shiftedTo
                }
                scheduleAutosave()
            }
        )
    }

    private func supervisionRetendoBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: {
                guard draft.supervisionPeriods.indices.contains(index) else { return false }
                return draft.supervisionPeriods[index].confirmedInRetendo
            },
            set: { value in
                guard draft.supervisionPeriods.indices.contains(index) else { return }
                draft.supervisionPeriods[index].confirmedInRetendo = value
                scheduleAutosave()
            }
        )
    }

    private func removeSupervisionPeriod(at index: Int) {
        guard draft.supervisionPeriods.indices.contains(index) else { return }
        guard !draft.supervisionPeriods[index].isEmpty else { return }
        draft.supervisionPeriods.remove(at: index)
        ensureSupervisionPeriodPlaceholder()
        scheduleAutosave()
    }

    /// Hours so far for one period: hours per term times the terms from the
    /// start date to the end date (or today). A dash when no hours per term
    /// or no start date is entered.
    private func supervisionAccruedHoursText(for period: DoctoralSupervisionPeriod) -> String {
        guard !period.isEmpty,
              period.from.trimmedOrNil != nil,
              let hours = period.accruedSupervisionHours() else {
            return "–"
        }
        return "\(Int(hours)) h"
    }

    /// "Totalt hittills: N h (till idag)" below the periods, or nil when no
    /// period has hours per term.
    private var supervisionAccruedTotalText: String? {
        let referenceDate = Date()
        guard let total = draft.accruedSupervisionHours(referenceDate: referenceDate) else { return nil }
        let countsToToday = draft.supervisionPeriods.contains { period in
            !period.isEmpty && period.hoursPerTermValue != nil && period.accruesUntilReferenceDate(referenceDate)
        }
        let until = countsToToday
            ? language.text("until today", "till idag")
            : language.text("until the end date", "till slutdatum")
        return language.text("Total so far: \(Int(total)) h (\(until))", "Totalt hittills: \(Int(total)) h (\(until))")
    }

    private func supervisionCalendarActivityHoursText(for period: DoctoralSupervisionPeriod) -> String {
        guard !period.isEmpty,
              let minutes = supervisionCalendarActivityMinutesByPeriodID[period.id],
              minutes > 0 else {
            return "-"
        }
        let hours = Double(minutes) / 60.0
        if hours.rounded() == hours {
            return "\(Int(hours)) h"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.decimalSeparator = language == .english ? "." : ","
        return "\(formatter.string(from: NSNumber(value: hours)) ?? String(format: "%.1f", hours)) h"
    }

    private func ensureSupervisionPeriodPlaceholder() {
        let preservedPlaceholder = draft.supervisionPeriods.first(where: { $0.isEmpty }) ?? DoctoralSupervisionPeriod()
        var rows = draft.supervisionPeriods.filter { !$0.isEmpty }
        rows.append(preservedPlaceholder)
        if rows != draft.supervisionPeriods {
            draft.supervisionPeriods = rows
        }
    }

    private func moveSupervisor(from index: Int, direction: Int) {
        guard draft.supervisors.indices.contains(index) else { return }
        guard !draft.supervisors[index].isEmpty else { return }
        let target = index + direction
        guard draft.supervisors.indices.contains(target) else { return }
        guard !draft.supervisors[target].isEmpty else { return }
        let item = draft.supervisors.remove(at: index)
        draft.supervisors.insert(item, at: target)
        ensureSupervisorPlaceholder()
        scheduleAutosave()
    }

    private func removeSupervisor(at index: Int) {
        guard draft.supervisors.indices.contains(index) else { return }
        guard !draft.supervisors[index].isEmpty else { return }
        draft.supervisors.remove(at: index)
        ensureSupervisorPlaceholder()
        scheduleAutosave()
    }

    private func ensureSupervisorPlaceholder() {
        let preservedPlaceholder = draft.supervisors.first(where: { $0.isEmpty }) ?? DoctoralSupervisorLink()
        var rows = draft.supervisors.filter { !$0.isEmpty }
        rows.append(preservedPlaceholder)
        if rows != draft.supervisors {
            draft.supervisors = rows
        }
    }

    private func doctoralDocumentBinding(
        _ index: Int,
        _ keyPath: WritableKeyPath<DoctoralCandidateDocument, String>
    ) -> Binding<String> {
        Binding(
            get: {
                guard draft.documents.indices.contains(index) else { return "" }
                return draft.documents[index][keyPath: keyPath]
            },
            set: { value in
                guard draft.documents.indices.contains(index) else { return }
                draft.documents[index][keyPath: keyPath] = value
                scheduleAutosave()
            }
        )
    }

    private func doctoralDocumentDateBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard draft.documents.indices.contains(index) else { return "" }
                return draft.documents[index].date
            },
            set: { value in
                guard draft.documents.indices.contains(index) else { return }
                draft.documents[index].date = DateParsers.canonicalizedDayInput(value)
                scheduleAutosave()
            }
        )
    }

    private func doctoralCourseBinding(
        _ index: Int,
        _ keyPath: WritableKeyPath<DoctoralCandidateCourse, String>
    ) -> Binding<String> {
        Binding(
            get: {
                guard draft.courses.indices.contains(index) else { return "" }
                return draft.courses[index][keyPath: keyPath]
            },
            set: { value in
                guard draft.courses.indices.contains(index) else { return }
                draft.courses[index][keyPath: keyPath] = value
                if !draft.courses[index].isEmpty {
                    provisionalCourseIDs.remove(draft.courses[index].id)
                }
                scheduleAutosave()
            }
        )
    }

    private func doctoralCourseCompletionDateBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard draft.courses.indices.contains(index) else { return "" }
                return draft.courses[index].completedOn ?? ""
            },
            set: { value in
                guard draft.courses.indices.contains(index) else { return }
                draft.courses[index].completedOn = DateParsers.canonicalizedDayInput(value).trimmedOrNil
                if !draft.courses[index].isEmpty {
                    provisionalCourseIDs.remove(draft.courses[index].id)
                }
                scheduleAutosave()
            }
        )
    }

    private func chooseDoctoralCandidatePDFs() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.title = language.text("Choose PDF documents", "Välj PDF-dokument")
        guard panel.runModal() == .OK else { return }

        let today = DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date()))
        var addedDocuments: [DoctoralCandidateDocument] = []
        var firstImportError: Error?
        var failedImportCount = 0
        for sourceURL in panel.urls where sourceURL.pathExtension.lowercased() == "pdf" {
            do {
                let data = try loadPDFDataForUserAction(from: sourceURL)
                var document = DoctoralCandidateDocument(
                    title: sourceURL.deletingPathExtension().lastPathComponent,
                    date: today,
                    filename: sourceURL.lastPathComponent
                )
                let managedURL = try GrantDataStore.persistManagedDoctoralCandidatePDF(
                    data: data,
                    forDocumentID: document.id
                )
                document.path = managedURL.path
                addedDocuments.append(document)
            } catch {
                failedImportCount += 1
                firstImportError = firstImportError ?? error
            }
        }
        if !addedDocuments.isEmpty {
            draft.documents.append(contentsOf: addedDocuments)
            requestImmediatePersist()
        }
        if let firstImportError {
            store.reportFileActionFailure(
                language.text(
                    "Could not import \(failedImportCount) of the selected PDF documents.",
                    "Kunde inte importera \(failedImportCount) av de valda PDF-dokumenten."
                ),
                error: firstImportError
            )
        }
    }

    private func openDoctoralCandidatePDF(_ document: DoctoralCandidateDocument) {
        guard let url = GrantDataStore.resolveDoctoralCandidatePDFURL(document: document) else {
            store.reportFileActionFailure(
                language.text("Could not open the doctoral document.", "Kunde inte öppna doktoranddokumentet."),
                error: CocoaError(.fileNoSuchFile)
            )
            return
        }
        store.openFileForUserAction(
            url,
            failureMessage: language.text("Could not open the doctoral document.", "Kunde inte öppna doktoranddokumentet.")
        )
    }

    private func removeDoctoralDocument(id: String) {
        draft.documents.removeAll { $0.id == id }
        scheduleAutosave()
    }

    private func removeDoctoralCourse(id: String) {
        provisionalCourseIDs.remove(id)
        draft.courses.removeAll { $0.id == id }
        scheduleAutosave()
    }

    private func addDoctoralCourse() {
        forcedPersistTask?.cancel()
        forcedPersistTask = nil
        flushAutosaveNow()

        let course = DoctoralCandidateCourse()
        provisionalCourseIDs.insert(course.id)
        draft.courses.append(course)
    }

    private func congressSubtitle(_ row: DoctoralCandidateCongressRow) -> String {
        let place = [row.congress.city.trimmedOrNil, row.congress.country.trimmedOrNil]
            .compactMap { $0 }
            .joined(separator: ", ")
        return [row.organizationName.trimmedOrNil, place.trimmedOrNil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func congressDateText(_ congress: OrganizationCongress) -> String {
        let from = congress.from.trimmedOrNil
        let to = congress.to.trimmedOrNil
        if let from, let to, from != to {
            return "\(from)–\(to)"
        }
        return from ?? to ?? "—"
    }

    private func addPublicationLink(_ publicationID: String) {
        guard !draft.linkedPublicationIDs.contains(publicationID) else { return }
        draft.linkedPublicationIDs.append(publicationID)
        scheduleAutosave()
    }

    private func removePublicationLink(_ publicationID: String) {
        draft.linkedPublicationIDs.removeAll { $0 == publicationID }
        scheduleAutosave()
    }

    private func publicationMatchesCandidate(_ publication: PublicationRecord) -> Bool {
        guard let candidateName = draft.candidateName.trimmedOrNil else { return false }
        let normalizedCandidateName = PublicationDerivation.normalizedName(candidateName)
        let matchedAuthor = store.publicationAuthor(matchingPresentedName: candidateName)

        return publication.authorNames.contains { authorName in
            if let matchedAuthor,
               let publicationAuthor = store.publicationAuthor(matchingPresentedName: authorName),
               publicationAuthor.id == matchedAuthor.id {
                return true
            }
            return PublicationDerivation.normalizedName(authorName) == normalizedCandidateName
        }
    }

    private func doctoralPublicationSortOrder(_ lhs: PublicationRecord, _ rhs: PublicationRecord) -> Bool {
        let lhsIsPublished = PublicationStatus.fromStored(lhs.statusLabel) == .published
        let rhsIsPublished = PublicationStatus.fromStored(rhs.statusLabel) == .published
        if lhsIsPublished != rhsIsPublished {
            return lhsIsPublished
        }
        if lhs.sortYear != rhs.sortYear {
            return lhs.sortYear > rhs.sortYear
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private func doctoralPublicationImpactFactor(_ publication: PublicationRecord) -> String {
        let metric = store.linkedJournal(of: publication)?
            .preferredMetric(
                for: [.clarivateScieJIF, .clarivateEsciJIF],
                publicationYear: publication.yearValue
            )?
            .value
        return metric?.trimmedOrNil ?? publication.jifCurrent.trimmedOrNil ?? "—"
    }

    private func doctoralPublicationNorwegianLevel(_ publication: PublicationRecord) -> String {
        let metric = store.linkedJournal(of: publication)?
            .preferredMetric(for: [.norwegianList], publicationYear: publication.yearValue)?
            .value
        return metric?.trimmedOrNil ?? publication.norwegianCurrent.trimmedOrNil ?? "—"
    }

    private func refreshEligiblePublicationChoices() {
        cachedEligiblePublicationChoices = store.publicationRecords
            .filter(publicationMatchesCandidate(_:))
            .sorted(by: doctoralPublicationSortOrder)
    }

    private func supervisorRowIsExpired(_ supervisor: DoctoralSupervisorLink) -> Bool {
        guard let endDate = supervisor.to.trimmedOrNil.flatMap(DateParsers.isoDay.date(from:)) else { return false }
        return Calendar.current.startOfDay(for: endDate) < Calendar.current.startOfDay(for: Date())
    }

    private func supervisorRowStatus(_ supervisor: DoctoralSupervisorLink) -> SupervisorRowStatus {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        if let endDate = supervisor.to.trimmedOrNil.flatMap(DateParsers.isoDay.date(from:)) {
            let doctoralDisputation = doctoralCandidateCompletedDisputationDate
            if let doctoralDisputation,
               calendar.startOfDay(for: endDate) >= calendar.startOfDay(for: doctoralDisputation) {
                return .endedWithDisputation
            }
            return .endedWithoutDisputation
        }
        if let startDate = supervisor.from.trimmedOrNil.flatMap(DateParsers.isoDay.date(from:)),
           calendar.startOfDay(for: startDate) <= today {
            return .ongoing
        }
        return .planned
    }

    private var doctoralCandidateCompletedDisputationDate: Date? {
        guard DoctoralMilestoneOutcome(rawValue: draft.plannedDisputationOutcomeRaw ?? "") != .endedBefore else {
            return nil
        }
        return draft.disputationDate.trimmedOrNil.flatMap(DateParsers.isoDay.date(from:))
    }

    private func supervisorStatusText(_ status: SupervisorRowStatus) -> String {
        switch status {
        case .planned:
            return language.text("Planned", "Planerad")
        case .ongoing:
            return language.text("Ongoing", "Pågående")
        case .endedWithoutDisputation:
            return language.text("Ended without dissertation", "Avslutad utan disputation")
        case .endedWithDisputation:
            return language.text("Ended with dissertation", "Avslutad med disputation")
        }
    }

    private func supervisorStatusColor(_ status: SupervisorRowStatus) -> Color {
        switch status {
        case .planned:
            return Color.white
        case .ongoing:
            return AppPalette.shadeYellow
        case .endedWithoutDisputation:
            return AppPalette.shadeRed
        case .endedWithDisputation:
            return AppPalette.shadeGreen
        }
    }

    private func doctoralCourseStatusColor(_ course: DoctoralCandidateCourse) -> Color {
        if course.completedOn?.trimmedOrNil != nil {
            return AppPalette.shadeGreen
        }
        if let year = Int(course.year.trimmingCharacters(in: .whitespacesAndNewlines)),
           year <= Calendar.current.component(.year, from: Date()) {
            return AppPalette.shadeYellow
        }
        return Color.white
    }

    private var doctoralCourseCreditsSummary: String {
        let total = visibleCourseRows.reduce(0.0) {
            $0 + (GrantParsing.numericValue(from: $1.credits) ?? 0)
        }
        let completed = visibleCourseRows.reduce(0.0) {
            guard $1.completedOn?.trimmedOrNil != nil else { return $0 }
            return $0 + (GrantParsing.numericValue(from: $1.credits) ?? 0)
        }
        return language.text(
            "\(AppFieldParsers.canonicalDecimal(String(completed))) of \(AppFieldParsers.canonicalDecimal(String(total))) credits completed",
            "\(AppFieldParsers.canonicalDecimal(String(completed))) av \(AppFieldParsers.canonicalDecimal(String(total))) hp genomförda"
        )
    }

    private func ensureTaskPlaceholder() {
        let preservedPlaceholder = draft.tasks.first(where: { $0.isEmpty }) ?? ProjectTaskItem()
        var rows = draft.tasks.filter { !$0.isEmpty }
        rows.append(preservedPlaceholder)
        if rows != draft.tasks {
            draft.tasks = rows
        }
    }

    private func localizedOrganizationName(_ organization: OrganizationRecord) -> String {
        if language == .swedish {
            return organization.nameSv
        }
        return organization.nameEn.nonEmpty ?? organization.nameSv
    }

    private func syncDraft(from newCandidate: DoctoralCandidateRecord, force: Bool) {
        if newCandidate.id != draft.id {
            flushAutosaveNow()
            autosaveTask?.cancel()
            draft = newCandidate
            provisionalCourseIDs.removeAll()
            hasPendingLocalEdits = false
            needsDerivedLinkRefresh = false
            ensureSupervisorPlaceholder()
            ensureSupervisionPeriodPlaceholder()
            ensureTaskPlaceholder()
            return
        }

        if force {
            autosaveTask?.cancel()
            draft = newCandidate
            provisionalCourseIDs.removeAll()
            hasPendingLocalEdits = false
            needsDerivedLinkRefresh = false
            ensureSupervisorPlaceholder()
            ensureSupervisionPeriodPlaceholder()
            ensureTaskPlaceholder()
            return
        }

        var normalizedDraft = draft
        normalizedDraft.normalize()
        if hasPendingLocalEdits {
            if normalizedDraft == newCandidate {
                hasPendingLocalEdits = false
            } else {
                return
            }
        }
        guard normalizedDraft != newCandidate else { return }
        autosaveTask?.cancel()
        draft = newCandidate
        hasPendingLocalEdits = false
        ensureEditingPlaceholders()
    }

    private func persistCurrentDraft(
        resolveDerivedLinks: Bool,
        updateDraftFromNormalized: Bool,
        ensurePlaceholders: Bool
    ) {
        var normalized = draft
        normalized.normalize()
        var normalizedCandidate = candidate
        normalizedCandidate.normalize()
        if normalized == normalizedCandidate,
           !hasPendingLocalEdits,
           (!resolveDerivedLinks || !needsDerivedLinkRefresh) {
            return
        }
        store.autosaveDoctoralCandidate(normalized, resolveDerivedLinks: resolveDerivedLinks)
        if updateDraftFromNormalized {
            normalized.courses = doctoralCandidateCoursesRestoringProvisionalRows(
                normalizedCourses: normalized.courses,
                draftCourses: draft.courses,
                provisionalCourseIDs: provisionalCourseIDs
            )
            draft = normalized
        }
        if ensurePlaceholders {
            ensureEditingPlaceholders()
        }
        if resolveDerivedLinks {
            refreshEligiblePublicationChoices()
            needsDerivedLinkRefresh = false
        }
        hasPendingLocalEdits = false
    }

    private func ensureEditingPlaceholders() {
        ensureSupervisorPlaceholder()
        ensureSupervisionPeriodPlaceholder()
        ensureTaskPlaceholder()
    }

    private func scheduleAutosave() {
        hasPendingLocalEdits = true
        needsDerivedLinkRefresh = true
        AutosaveCoordinator.schedule(&autosaveTask, after: 1.0) {
            persistCurrentDraft(
                resolveDerivedLinks: false,
                updateDraftFromNormalized: false,
                ensurePlaceholders: false
            )
        }
    }

    private func flushAutosaveNow() {
        AutosaveCoordinator.flush(&autosaveTask) {
            persistCurrentDraft(
                resolveDerivedLinks: true,
                updateDraftFromNormalized: true,
                ensurePlaceholders: true
            )
        }
    }

    private func requestImmediatePersist() {
        AutosaveCoordinator.requestImmediate(&forcedPersistTask) {
            flushAutosaveNow()
        }
    }
}

private struct DoctoralPublicationStatusBadge: View {
    let status: String
    let language: AppLanguage

    var body: some View {
        AppPublicationStatusTextBadge(status: status, language: language)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
