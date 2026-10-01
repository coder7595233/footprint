import AppKit
import SwiftUI

func applicationMatchesCurrentUserFirstApplicantFilter(
    _ application: ApplicationRowSnapshot,
    roleFilter: ApplicationRoleFilter
) -> Bool {
    switch roleFilter {
    case .all:
        return true
    case .currentUserFirst:
        return application.isCurrentUserFirstApplicant
    case .othersFirst:
        return !application.isCurrentUserFirstApplicant
    }
}

func applicationMatchesCurrentUserFirstApplicantFilter(
    _ application: ApplicationRowSnapshot,
    showsOnlyCurrentUserFirstApplicant: Bool
) -> Bool {
    applicationMatchesCurrentUserFirstApplicantFilter(
        application,
        roleFilter: showsOnlyCurrentUserFirstApplicant ? .currentUserFirst : .all
    )
}

enum ApplicationRoleFilter: String, Codable, Hashable {
    case all
    case currentUserFirst
    case othersFirst
}

struct ApplicationsView: View {
    private struct FilterCacheKey: Hashable {
        let generation: Int
        let nonSearchSignature: String
        let includedTerms: [String]
        let excludedTerms: [String]
    }

    private enum ApplicationListSortColumn: String, Hashable {
        case funder
        case grant
        case closes
        case project
        case grantNumber
        case maximumAmount

        var defaultAscending: Bool {
            switch self {
            case .maximumAmount:
                return false
            case .closes:
                return true
            case .funder, .grant, .project, .grantNumber:
                return true
            }
        }
    }

    private struct ApplicationListSortCriterion: AppListSortCriterion {
        let column: ApplicationListSortColumn
        var ascending: Bool
    }

    private enum QuickApplicationView {
        case all
        case active
        case findNew
        case own
        case others
    }

    let store: GrantDataStore
    @Binding var exportApplicationIDs: [String]?
    @Binding var preset: ApplicationListPreset?
    @Binding var pendingDirectSelectionID: String?
    let isActive: Bool
    let newRecordTrigger: Int
    @WorkspaceFilterState("Applications.Filter.Search") private var searchText = ""
    @WorkspaceFilterState("Applications.Filter.Status") private var selectedStatusFilters: Set<String> = []
    @WorkspaceFilterState("Applications.Filter.Projects") private var selectedProjectFilters: Set<String> = []
    @WorkspaceFilterState("Applications.Filter.Role") private var applicationRoleFilter: ApplicationRoleFilter = .all
    @WorkspaceFilterState("Applications.Filter.ActiveFirst") private var prioritizesActiveApplications = false
    @WorkspaceFilterState("Applications.Filter.FutureOnly") private var showsOnlyFutureApplications = false
    @WorkspaceFilterState("Applications.Filter.MinimumYear") private var minimumYearValue: Double = 0
    @WorkspaceFilterState("Applications.Filter.MaximumYear") private var maximumYearValue: Double = 0
    @WorkspaceFilterState("Applications.Filter.MinimumAmount") private var minimumAmountValue: Double = 0
    @WorkspaceFilterState("Applications.Filter.MaximumAmount") private var maximumAmountValue: Double = 20_000_000
    @State private var sortHistory = ListSortPersistence.load(
        defaultsKey: "ApplicationsListSort",
        defaultValue: [ApplicationListSortCriterion(column: .closes, ascending: true)]
    )
    @State private var selectedApplicationID: String?
    @State private var applicationRows: [ApplicationRowSnapshot] = []
    @State private var baseFilteredApplicationRows: [ApplicationRowSnapshot] = []
    @State private var filteredApplicationRows: [ApplicationRowSnapshot] = []
    @State private var searchRebuildTask: DispatchWorkItem?
    @State private var pendingSelectionMeasurementID: String?
    @State private var pendingSelectionStartedAt: CFAbsoluteTime?
    @State private var applicationSelectionCoordinator = AppSelectionCoordinator<String>()
    @State private var isApplyingDirectApplicationRoute = false
    @State private var applicationsViewHasAppeared = false
    @State private var hasResolvedInitialApplicationSelection = false
    @State private var lastApplicationSearchQuery = SearchFilterQuery(raw: "")
    @State private var lastApplicationNonSearchFilterSignature = ""
    @State private var applicationRowsAppliedGeneration = 0
    @State private var pendingDirectSelectionTimeoutTask: DispatchWorkItem?
    @State private var directRouteFailsafeTask: DispatchWorkItem?
    @State private var needsApplicationRowsRefreshWhenActive = false
    @State private var needsFilteredRebuildWhenActive = false
    @State private var directRouteGeneration: UInt = 0
    @State private var idleWarmupTask: DispatchWorkItem?
    @State private var nonSearchFilteredRowsCache: [String: [ApplicationRowSnapshot]] = [:]
    @State private var filteredRowsCache: [FilterCacheKey: [ApplicationRowSnapshot]] = [:]
    @State private var grantPipelineExpanded = false

    init(
        store: GrantDataStore,
        exportApplicationIDs: Binding<[String]?>,
        preset: Binding<ApplicationListPreset?>,
        pendingDirectSelectionID: Binding<String?>,
        isActive: Bool,
        newRecordTrigger: Int
    ) {
        self.store = store
        _exportApplicationIDs = exportApplicationIDs
        _preset = preset
        _pendingDirectSelectionID = pendingDirectSelectionID
        self.isActive = isActive
        self.newRecordTrigger = newRecordTrigger

        // A direct route is already authoritative. Starting with it prevents an
        // empty/remembered editor from being laid out before onAppear applies it.
        let routedID = store.route?.destination == .applications ? store.route?.recordID : nil
        _selectedApplicationID = State(
            initialValue: pendingDirectSelectionID.wrappedValue
                ?? routedID
                ?? store.lastSelectedRecordID(for: .applications)
        )
    }

    private var sortOrder: [KeyPathComparator<ApplicationRowSnapshot>] {
        var columns = sortHistory.map(\.column)
        for fallbackColumn in [ApplicationListSortColumn.closes, .funder, .grant] where !columns.contains(fallbackColumn) {
            columns.append(fallbackColumn)
        }
        return columns.flatMap { column -> [KeyPathComparator<ApplicationRowSnapshot>] in
            let ascending = sortHistory.first(where: { $0.column == column })?.ascending ?? column.defaultAscending
            let order: SortOrder = ascending ? .forward : .reverse
            switch column {
            case .funder:
                return [
                    KeyPathComparator(\.sortOrganization, order: order),
                    KeyPathComparator(\.sortGrantName, order: .forward)
                ]
            case .grant:
                return [
                    KeyPathComparator(\.sortGrantName, order: order),
                    KeyPathComparator(\.sortOrganization, order: .forward)
                ]
            case .closes:
                return [
                    KeyPathComparator(\.sortClosesOn, order: order),
                    KeyPathComparator(\.sortOrganization, order: .forward)
                ]
            case .project:
                return [
                    KeyPathComparator(\.sortProject, order: order),
                    KeyPathComparator(\.sortGrantName, order: .forward)
                ]
            case .grantNumber:
                return [
                    KeyPathComparator(\.sortAppliedCaseNumber, order: order),
                    KeyPathComparator(\.sortGrantName, order: .forward)
                ]
            case .maximumAmount:
                return [
                    KeyPathComparator(\.sortMaximumAmount, order: order),
                    KeyPathComparator(\.sortGrantName, order: .forward)
                ]
            }
        }
    }

    private var sortSignature: String {
        sortHistory
            .map { "\(String(describing: $0.column)):\($0.ascending ? "asc" : "desc")" }
            .joined(separator: "|")
    }

    private var projectOptions: [String] {
        store.projectTypes
    }

    private var yearValues: [Int] {
        Array(Set(applicationRows.map(\.applicationYear))).sorted()
    }

    private var yearBounds: ClosedRange<Double> {
        let years = yearValues
        let fallbackYear = Double(Calendar.current.component(.year, from: Date()))
        let lower = Double(years.first ?? Int(fallbackYear))
        let upper = Double(years.last ?? Int(fallbackYear))
        return lower...upper
    }

    private var hasActiveApplicationFilters: Bool {
        searchText.nonEmpty != nil
            || !selectedStatusFilters.isEmpty
            || !selectedProjectFilters.isEmpty
            || minimumYearValue != yearBounds.lowerBound
            || maximumYearValue != yearBounds.upperBound
            || minimumAmountValue != 0
            || maximumAmountValue != 20_000_000
            || preset != nil
            || applicationRoleFilter != .all
            || showsOnlyFutureApplications
    }

    private var nonSearchMatchingApplications: [ApplicationRowSnapshot] {
        let projectFilter = store.applicationProjectFilter(selectedProjects: selectedProjectFilters)
        return applicationRows.filter { application in
            let matchesCurrentUserRole = applicationMatchesCurrentUserFirstApplicantFilter(
                application,
                roleFilter: applicationRoleFilter
            )
            let matchesStatus = matchesStatusFilter(application.resultLabel)
            let matchesFuture = matchesFutureApplicationFilter(application)
            let matchesProject = projectFilter.matches(projectID: application.projectID, projectName: application.projectName)
            let applicationYear = Double(application.applicationYear)
            let matchesYear = applicationYear >= min(minimumYearValue, maximumYearValue) && applicationYear <= max(minimumYearValue, maximumYearValue)
            let amount = application.budgetAmount
            let lowerAmount = min(minimumAmountValue, maximumAmountValue)
            let upperAmount = max(minimumAmountValue, maximumAmountValue)
            let matchesSum = amount >= lowerAmount && (upperAmount >= 20_000_000 || amount <= upperAmount)
            return matchesCurrentUserRole
                && matchesStatus
                && matchesFuture
                && matchesProject
                && matchesYear
                && matchesSum
        }
    }

    private var applicationSelectionBinding: Binding<String?> {
        Binding(
            get: { selectedApplicationID },
            set: { newValue in
                handleApplicationSelectionCandidate(newValue)
            }
        )
    }

    var body: some View {
        let language = store.language

        GeometryReader { geometry in
            VStack(spacing: 0) {
                grantPipelineChromeBar(language: language)
                    .zIndex(2)

                ZStack(alignment: .top) {
                    applicationsSplitView(language: language)
                        .zIndex(0)

                    if grantPipelineExpanded {
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                collapseGrantPipeline()
                            }
                            .zIndex(1)

                        GrantPipelineCurtainPanel(
                            store: store,
                            maxHeight: grantPipelinePanelHeight(for: geometry.size.height - grantPipelineChromeReservedHeight),
                            onSelectApplication: { applicationID in
                                openApplicationFromPipeline(applicationID)
                            }
                        )
                        .zIndex(2)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.spring(response: 0.34, dampingFraction: 0.88), value: grantPipelineExpanded)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDeleteCommand {
            guard let selectedApplicationID,
                  let selected = store.application(selectionID: selectedApplicationID) else { return }
            store.requestKeyboardDeletion(recordTitle: selected.displayTitle, isLocked: selected.isEditingLocked) {
                store.deleteApplication(id: selected.id)
            }
        }
        .onEscapeKey(isEnabled: grantPipelineExpanded, perform: collapseGrantPipeline)
    }

    private var grantPipelineChromeReservedHeight: CGFloat {
        62
    }

    private func applicationsSplitView(language: AppLanguage) -> some View {
        PersistentSplitView(layout: .applications) {
            AppWorkspaceSidebar(padding: 12) {
                applicationsSidebarContent(language: language)
            }
            .onAppear { handleApplicationsAppear() }
            .onReceive(store.$applicationRowSnapshotGeneration.dropFirst()) { _ in handleApplicationRowsSnapshotChange() }
            .onChange(of: preset) { _, _ in handleApplicationPresetChange() }
            .onChange(of: searchText) { _, _ in handleApplicationSearchChange() }
            .onChange(of: applicationFilterSignature) { _, _ in handleApplicationFilterChange() }
            .onChange(of: sortHistory) { _, _ in handleApplicationSortChange() }
            .onChange(of: store.route) { _, route in handleApplicationRouteChange(route) }
            .onChange(of: pendingDirectSelectionID) { _, pendingID in handlePendingDirectApplicationSelectionChange(pendingID) }
            .onChange(of: isActive) { _, active in handleApplicationsActiveChange(active) }
            .onChange(of: filteredApplicationRows.map(\.selectionID)) { _, ids in handleFilteredApplicationSelectionIDsChange(ids) }
            .onChange(of: selectedApplicationID) { _, id in handleSelectedApplicationIDChange(id) }
            .onDisappear { handleApplicationsDisappear() }
            .onChange(of: newRecordTrigger) { _, _ in handleNewApplicationTrigger() }
        } detail: {
            applicationDetailContent(language: language)
        }
    }

    @ViewBuilder
    private func applicationDetailContent(language: AppLanguage) -> some View {
        if !hasResolvedInitialApplicationSelection {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let selected = store.application(selectionID: selectedApplicationID) {
            ApplicationEditorView(
                store: store,
                application: selected,
                selectionID: selectedApplicationID,
                isActive: isActive
            )
            .undoRevealPulse(
                triggerID: store.undoRevealRequest?.id,
                isActive: store.undoRevealRequest?.target.matchesWholeRecord(routeDestination: .applications, recordID: selected.id) == true
            )
            .performanceScopeProbe(store: store, scope: "applications-detail", identifier: selected.id)
            .background(
                PerformanceReadyReporter {
                    guard let selectedApplicationID,
                          pendingSelectionMeasurementID == selectedApplicationID,
                          let pendingSelectionStartedAt else { return }
                    let duration = (CFAbsoluteTimeGetCurrent() - pendingSelectionStartedAt) * 1000
                    store.appendPerformanceDiagnostic(
                        String(
                            format: "application-selection-ready application=%@ ready_ms=%.2f",
                            selected.grantName,
                            duration
                        )
                    )
                    releaseApplicationSelectionLock(for: selectedApplicationID)
                    self.pendingSelectionMeasurementID = nil
                    self.pendingSelectionStartedAt = nil
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            AppWorkspaceEmptyStateView(
                title: language.text("No applications match the current filters", "Inga ansökningar matchar filtret"),
                subtitle: language.text("Try a broader search or reset the filters.", "Prova en bredare sökning eller återställ filtren."),
                kind: .applications,
                actionTitle: language.text("Reset filters", "Återställ filter"),
                action: {
                    resetFiltersToDefault()
                    rebuildFilteredApplications()
                }
            )
        }
    }

    private func handleApplicationsAppear() {
        applicationsViewHasAppeared = true
        store.appendPerformanceDiagnostic(
            String(
                format: "applications-view-onAppear active=%@ pending=%@ route=%@ selected=%@",
                isActive ? "yes" : "no",
                pendingDirectSelectionID ?? "-",
                store.route?.recordID ?? "-",
                selectedApplicationID ?? "-"
            )
        )
        if isActive {
            ensureFilterRangesInitialized()
            refreshApplicationRows()
            rebuildFilteredApplications()
            if let pendingDirectSelectionID {
                consumePendingDirectSelection(pendingDirectSelectionID)
            } else if let route = store.route, route.destination == .applications {
                applyDirectApplicationRoute(route.recordID)
                consumeApplicationRouteIfSelectionMatches(route.recordID)
            } else if selectedApplicationID == nil {
                let candidateIDs = filteredApplicationRows.map(\.selectionID)
                let fallbackID = preferredInitialApplicationSelection(from: candidateIDs)
                store.appendPerformanceDiagnostic(
                    String(
                        format: "applications-view-autoselect-fallback id=%@",
                        fallbackID ?? "-"
                    )
                )
                setSelectedApplicationID(fallbackID)
            }
            applyPresetIfNeeded()
            exportApplicationIDs = filteredApplicationRows.map(\.id)
            schedulePendingDirectSelectionTimeoutIfNeeded()
            scheduleApplicationIdleWarmup()
            hasResolvedInitialApplicationSelection = true
        } else {
            needsApplicationRowsRefreshWhenActive = true
            needsFilteredRebuildWhenActive = true
        }
    }

    private func handleApplicationRowsSnapshotChange() {
        guard isActive else {
            needsApplicationRowsRefreshWhenActive = true
            needsFilteredRebuildWhenActive = true
            return
        }
        ensureFilterRangesInitialized()
        refreshApplicationRows()
        rebuildFilteredApplications()
    }

    private func handleApplicationPresetChange() {
        guard !isApplyingDirectApplicationRoute else { return }
        guard isActive else {
            needsFilteredRebuildWhenActive = true
            return
        }
        applyPresetIfNeeded()
        rebuildFilteredApplications()
    }

    private func handleApplicationSearchChange() {
        guard !isApplyingDirectApplicationRoute else { return }
        guard isActive else {
            needsFilteredRebuildWhenActive = true
            return
        }
        scheduleFilteredApplicationsRebuild()
    }

    private func handleApplicationFilterChange() {
        guard !isApplyingDirectApplicationRoute else { return }
        guard isActive else {
            needsFilteredRebuildWhenActive = true
            return
        }
        rebuildFilteredApplications()
    }

    private func handleApplicationSortChange() {
        guard !isApplyingDirectApplicationRoute else { return }
        guard isActive else {
            needsFilteredRebuildWhenActive = true
            return
        }
        rebuildFilteredApplications()
    }

    private func handleApplicationRouteChange(_ route: AppRoute?) {
        guard let route, route.destination == .applications else { return }
        if grantPipelineExpanded {
            collapseGrantPipeline()
        }
        guard isActive else {
            store.appendPerformanceDiagnostic(
                String(
                    format: "application-route-deferred id=%@",
                    route.recordID
                )
            )
            return
        }
        applyDirectApplicationRoute(route.recordID)
        consumeApplicationRouteIfSelectionMatches(route.recordID)
    }

    private func handlePendingDirectApplicationSelectionChange(_ pendingID: String?) {
        store.appendPerformanceDiagnostic(
            String(
                format: "applications-pending-direct-selection-changed id=%@ active=%@",
                pendingID ?? "-",
                isActive ? "yes" : "no"
            )
        )
        schedulePendingDirectSelectionTimeoutIfNeeded()
        guard isActive, let pendingID else { return }
        consumePendingDirectSelection(pendingID)
    }

    private func handleApplicationsActiveChange(_ active: Bool) {
        store.appendPerformanceDiagnostic(
            String(
                format: "applications-active-changed active=%@ pending=%@",
                active ? "yes" : "no",
                pendingDirectSelectionID ?? "-"
            )
        )
        if active {
            if needsApplicationRowsRefreshWhenActive {
                ensureFilterRangesInitialized()
                refreshApplicationRows()
                needsApplicationRowsRefreshWhenActive = false
            }
            if needsFilteredRebuildWhenActive {
                rebuildFilteredApplications()
                needsFilteredRebuildWhenActive = false
            }
            if let route = store.route, route.destination == .applications {
                applyDirectApplicationRoute(route.recordID)
                consumeApplicationRouteIfSelectionMatches(route.recordID)
            }
        } else {
            applicationsViewHasAppeared = false
            clearApplicationFiltersForDeactivationIfNeeded()
            cancelInactiveRouteWork()
            idleWarmupTask?.cancel()
        }
        schedulePendingDirectSelectionTimeoutIfNeeded()
        guard active, let pendingDirectSelectionID else { return }
        consumePendingDirectSelection(pendingDirectSelectionID)
    }

    private func handleFilteredApplicationSelectionIDsChange(_ ids: [String]) {
        exportApplicationIDs = filteredApplicationRows.map(\.id)
        if isActive {
            scheduleApplicationIdleWarmup()
        }
        guard !isApplyingDirectApplicationRoute else { return }
        if let lockID = applicationSelectionCoordinator.lockedID,
           selectedApplicationID == lockID,
           !ids.contains(lockID) {
            return
        }
        guard let selectedApplicationID else {
            setSelectedApplicationID(ids.first, resignFirstResponder: false)
            return
        }
        if !ids.contains(selectedApplicationID) {
            setSelectedApplicationID(ids.first, resignFirstResponder: false)
        }
    }

    private func handleSelectedApplicationIDChange(_ id: String?) {
        store.handlePendingSelectionReturnIfNeeded(for: id, in: .applications)
        store.rememberSelection(id: id, for: .applications)
        pendingSelectionMeasurementID = id
        pendingSelectionStartedAt = CFAbsoluteTimeGetCurrent()
        store.appendPerformanceDiagnostic(
            String(
                format: "application-selection-start id=%@",
                id ?? "-"
            )
        )
    }

    private func handleApplicationsDisappear() {
        applicationsViewHasAppeared = false
        hasResolvedInitialApplicationSelection = false
        cancelInactiveRouteWork()
        exportApplicationIDs = nil
        applicationSelectionCoordinator.clear()
        idleWarmupTask?.cancel()
    }

    private func handleNewApplicationTrigger() {
        guard isActive else { return }
        applicationRoleFilter = .all
        setSelectedApplicationID(store.addApplication(), armLock: true)
    }

    private func applicationsSidebarContent(language: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            AppWorkspaceSidebarHeader(
                title: language.text("Calls and grants", "Utlysningar och anslag"),
                actionTitle: language.text("New call", "Ny utlysning")
            ) {
                applicationRoleFilter = .all
                selectedApplicationID = store.addApplication()
            }

            AppFilterCard {
                VStack(alignment: .leading, spacing: 8) {
                    AppFilterRow(
                        showsClearButton: searchText.nonEmpty != nil,
                        clearAction: { searchText = "" }
                    ) {
                        AppSidebarSearchField(
                            placeholder: language.text("Search applications", "Sök ansökningar"),
                            text: $searchText
                        )
                    }

                    applicationQuickFilterRow(language: language)
                    applicationStatusFilterRow(language: language)
                    applicationRangeFilterRow(language: language)
                    applicationProjectFilterRow(language: language)

                    AppFilterClearAllRow(isVisible: hasActiveApplicationFilters) {
                        resetFiltersToDefault()
                        rebuildFilteredApplications()
                    }
                }
            }

            activeApplicationFilterStrip(language: language)
            applicationResultsTable(language: language)
            applicationListCountFootnote(language: language)
        }
    }

    private func applicationQuickFilterRow(language: AppLanguage) -> some View {
        AppFilterRow(
            showsClearButton: !selectedStatusFilters.isEmpty || applicationRoleFilter != .all || showsOnlyFutureApplications,
            clearAction: {
                resetFiltersToDefault()
                rebuildFilteredApplications()
            }
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    AppFilterChip(label: language.text("All", "Alla"), isSelected: applicationQuickViewIsActive(.all)) {
                        applyQuickApplicationView(.all)
                    }
                    AppFilterChip(label: language.text("Active", "Aktiva"), isSelected: applicationQuickViewIsActive(.active)) {
                        applyQuickApplicationView(.active)
                    }
                    AppFilterChip(label: language.text("Find new", "Hitta nya"), isSelected: applicationQuickViewIsActive(.findNew)) {
                        applyQuickApplicationView(.findNew)
                    }
                    AppFilterChip(label: language.text("Only own", "Endast egna"), isSelected: applicationQuickViewIsActive(.own)) {
                        applyQuickApplicationView(.own)
                    }
                    AppFilterChip(label: language.text("Only others", "Endast andras"), isSelected: applicationQuickViewIsActive(.others)) {
                        applyQuickApplicationView(.others)
                    }
                }
            }
        }
    }

    private func applicationRangeFilterRow(language: AppLanguage) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            AppFilterRangeControl(
                title: yearRangeLabel(language: language),
                lowerValue: minimumYearSliderBinding,
                upperValue: maximumYearSliderBinding,
                bounds: yearBounds
            )

            if minimumYearValue != yearBounds.lowerBound || maximumYearValue != yearBounds.upperBound {
                FilterClearButton {
                    minimumYearValue = yearBounds.lowerBound
                    maximumYearValue = yearBounds.upperBound
                }
                .padding(.bottom, 2)
            }

            AppFilterRangeControl(
                title: sumRangeLabel(language: language),
                lowerValue: minimumAmountSliderBinding,
                upperValue: maximumAmountSliderBinding,
                bounds: 0...20_000_000,
                step: 100_000
            )

            if minimumAmountValue != 0 || maximumAmountValue != 20_000_000 {
                FilterClearButton {
                    minimumAmountValue = 0
                    maximumAmountValue = 20_000_000
                }
                .padding(.bottom, 2)
            }
            Spacer()
        }
    }

    private func grantPipelinePanelHeight(for availableHeight: CGFloat) -> CGFloat {
        max(0, availableHeight - 58)
    }

    private func grantPipelineChromeBar(language: AppLanguage) -> some View {
        let usesDarkAppearance = currentVisualModePreference()?.usesDarkAppearance == true
        return Button {
            toggleGrantPipeline()
        } label: {
            HStack {
                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    Text(language.text("Grant pipeline", "Anslagsflöde"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    Image(systemName: grantPipelineExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color(red: 0.33, green: 0.33, blue: 0.36))
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .background(alignment: .bottom) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [AppPalette.sidebarPanelSurface, AppPalette.sidebarPanelSurface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(AppPalette.border)
                        .frame(height: 1)
                }
                .overlay(alignment: .bottom) {
                    if !grantPipelineExpanded {
                        LinearGradient(
                            colors: [
                                Color.black.opacity(usesDarkAppearance ? 0.18 : 0.08),
                                Color.black.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 12)
                        .offset(y: 12)
                    }
                }
        }
        .accessibilityLabel(language.text("Show or hide the grant pipeline", "Visa eller dölj Anslagsflöde"))
    }

    private func toggleGrantPipeline() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            grantPipelineExpanded.toggle()
        }
    }

    private func collapseGrantPipeline() {
        guard grantPipelineExpanded else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            grantPipelineExpanded = false
        }
    }

    private func openApplicationFromPipeline(_ applicationID: String) {
        resetFiltersForDirectNavigation()
        rebuildFilteredApplications()
        setSelectedApplicationID(applicationID, armLock: true)
        collapseGrantPipeline()
    }

    private func matchesStatusFilter(_ result: String?) -> Bool {
        if selectedStatusFilters.isEmpty {
            return true
        }
        let normalized = normalizedStatus(result)
        return selectedStatusFilters.contains(normalized)
    }

    private func matchesFutureApplicationFilter(_ application: ApplicationRowSnapshot) -> Bool {
        guard showsOnlyFutureApplications else { return true }
        guard let closeDate = application.closeDate else { return false }
        // A call still marked "Att söka" after its closing date is kept: it
        // has not been answered yet ("Sökt" or "Ej sökt") and must not drop
        // out of sight.
        if application.isToApplyStatus { return true }
        let calendar = Calendar.current
        return calendar.startOfDay(for: closeDate) >= calendar.startOfDay(for: Date())
    }

    private func applyPresetIfNeeded() {
        guard let preset else { return }
        switch preset {
        case .all:
            selectedStatusFilters.removeAll()
        case .granted:
            selectedStatusFilters = ["Beviljat"]
        case .pending:
            selectedStatusFilters = ["Att söka", "Väntar svar"]
        }
        self.preset = nil
    }

    private func resetFiltersForDirectNavigation() {
        searchText = ""
        selectedStatusFilters.removeAll()
        selectedProjectFilters.removeAll()
        resetNumericFilters()
        applicationRoleFilter = .all
        prioritizesActiveApplications = false
        showsOnlyFutureApplications = false
        preset = nil
    }

    private func resetFiltersToDefault() {
        searchText = ""
        selectedStatusFilters.removeAll()
        selectedProjectFilters.removeAll()
        resetNumericFilters()
        applicationRoleFilter = .all
        prioritizesActiveApplications = false
        showsOnlyFutureApplications = false
        preset = nil
    }

    private func resetNumericFilters() {
        let bounds = yearBounds
        minimumYearValue = bounds.lowerBound
        maximumYearValue = bounds.upperBound
        minimumAmountValue = 0
        maximumAmountValue = 20_000_000
    }

    private func clearApplicationFiltersForDeactivationIfNeeded() {
        guard !store.shouldRetainListFilters(for: .applications) else { return }
        guard hasActiveApplicationFilters else { return }
        resetFiltersToDefault()
        filteredRowsCache.removeAll()
        nonSearchFilteredRowsCache.removeAll()
        needsFilteredRebuildWhenActive = true
    }

    private var minimumYearSliderBinding: Binding<Double> {
        Binding(
            get: { minimumYearValue },
            set: { newValue in
                minimumYearValue = min(newValue, maximumYearValue)
            }
        )
    }

    private var maximumYearSliderBinding: Binding<Double> {
        Binding(
            get: { maximumYearValue },
            set: { newValue in
                maximumYearValue = max(newValue, minimumYearValue)
            }
        )
    }

    private var minimumAmountSliderBinding: Binding<Double> {
        Binding(
            get: { minimumAmountValue },
            set: { newValue in
                minimumAmountValue = min(newValue, maximumAmountValue)
            }
        )
    }

    private var maximumAmountSliderBinding: Binding<Double> {
        Binding(
            get: { maximumAmountValue },
            set: { newValue in
                maximumAmountValue = max(newValue, minimumAmountValue)
            }
        )
    }

    private func ensureFilterRangesInitialized() {
        let bounds = yearBounds
        if minimumYearValue == 0 && maximumYearValue == 0 {
            minimumYearValue = bounds.lowerBound
            maximumYearValue = bounds.upperBound
        } else {
            minimumYearValue = min(max(minimumYearValue, bounds.lowerBound), bounds.upperBound)
            maximumYearValue = min(max(maximumYearValue, bounds.lowerBound), bounds.upperBound)
        }
    }

    private func normalizedStatus(_ result: String?) -> String {
        let trimmed = result?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Att söka" : trimmed
    }

    private func toggleStatusFilter(_ status: String) {
        if selectedStatusFilters.contains(status) {
            selectedStatusFilters.remove(status)
        } else {
            selectedStatusFilters.insert(status)
        }
    }

    private func applyQuickApplicationView(_ view: QuickApplicationView) {
        searchText = ""
        selectedProjectFilters.removeAll()
        resetNumericFilters()
        applicationRoleFilter = .all
        prioritizesActiveApplications = false
        showsOnlyFutureApplications = false
        switch view {
        case .all:
            selectedStatusFilters.removeAll()
        case .active:
            selectedStatusFilters = ["Att söka", "Väntar svar"]
        case .findNew:
            selectedStatusFilters.removeAll()
            showsOnlyFutureApplications = true
        case .own:
            selectedStatusFilters.removeAll()
            applicationRoleFilter = .currentUserFirst
        case .others:
            selectedStatusFilters.removeAll()
            applicationRoleFilter = .othersFirst
        }
        rebuildFilteredApplications()
    }

    private func sumRangeLabel(language: AppLanguage) -> String {
        let lower = formattedAmountInMillions(min(minimumAmountValue, maximumAmountValue), language: language)
        let upper = max(minimumAmountValue, maximumAmountValue)
        let upperText = upper >= 20_000_000
            ? language.text(">20 million SEK", ">20 miljoner SEK")
            : "\(formattedAmountInMillions(upper, language: language)) \(language.text("million SEK", "miljoner SEK"))"
        return "\(language.text("SEK", "SEK")): \(lower) – \(upperText)"
    }

    private func yearRangeLabel(language: AppLanguage) -> String {
        let lower = Int(min(minimumYearValue, maximumYearValue))
        let upper = Int(max(minimumYearValue, maximumYearValue))
        return "\(language.text("Year", "År")): \(lower)–\(upper)"
    }

    private var applicationFilterSignature: String {
        [
            selectedStatusFilters.sorted().joined(separator: "|"),
            selectedProjectFilters.sorted().joined(separator: "|"),
            String(format: "%.0f", minimumYearValue),
            String(format: "%.0f", maximumYearValue),
            String(format: "%.0f", minimumAmountValue),
            String(format: "%.0f", maximumAmountValue),
            applicationRoleFilter.rawValue,
            prioritizesActiveApplications ? "active-first" : "plain-sort",
            showsOnlyFutureApplications ? "future-only" : "all-dates",
            String(applicationRowsAppliedGeneration),
            sortSignature
        ].joined(separator: "||")
    }

    private func formattedAmountInMillions(_ value: Double, language: AppLanguage) -> String {
        let millions = max(0, value) / 1_000_000
        let formatter = NumberFormatter()
        formatter.locale = language == .swedish ? Locale(identifier: "sv_SE") : Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = millions.rounded() == millions ? 0 : 1
        formatter.maximumFractionDigits = 1
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: millions)) ?? "\(millions)"
    }

    @ViewBuilder
    private func activeApplicationFilterStrip(language: AppLanguage) -> some View {
        if hasActiveApplicationFilters {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let search = searchText.nonEmpty {
                        AppActiveFilterChip(
                            title: language.text("Search: \(search)", "Sökning: \(search)"),
                            systemImage: "magnifyingglass",
                            clearAction: { searchText = "" }
                        )
                    }
                    if applicationRoleFilter != .all {
                        AppActiveFilterChip(
                            title: applicationRoleFilter == .currentUserFirst
                                ? language.text("Only own", "Endast egna")
                                : language.text("Only others", "Endast andras"),
                            systemImage: "person.2",
                            clearAction: { applicationRoleFilter = .all }
                        )
                    }
                    if showsOnlyFutureApplications {
                        AppActiveFilterChip(
                            title: language.text("Future grants", "Framtida anslag"),
                            systemImage: "calendar.badge.clock",
                            clearAction: { showsOnlyFutureApplications = false }
                        )
                    }
                    ForEach(selectedStatusFilters.sorted(), id: \.self) { status in
                        AppActiveFilterChip(
                            title: applicationStatusFilterLabel(status, language: language),
                            systemImage: "circle.lefthalf.filled",
                            clearAction: { selectedStatusFilters.remove(status) }
                        )
                    }
                    ForEach(selectedProjectFilters.sorted(), id: \.self) { project in
                        AppActiveFilterChip(
                            title: store.projectLabel(for: project, language: language),
                            systemImage: "folder",
                            clearAction: { selectedProjectFilters.remove(project) }
                        )
                    }
                    if minimumYearValue != yearBounds.lowerBound || maximumYearValue != yearBounds.upperBound {
                        AppActiveFilterChip(
                            title: yearRangeLabel(language: language),
                            systemImage: "calendar",
                            clearAction: {
                                minimumYearValue = yearBounds.lowerBound
                                maximumYearValue = yearBounds.upperBound
                            }
                        )
                    }
                    if minimumAmountValue != 0 || maximumAmountValue != 20_000_000 {
                        AppActiveFilterChip(
                            title: sumRangeLabel(language: language),
                            systemImage: "banknote",
                            clearAction: {
                                minimumAmountValue = 0
                                maximumAmountValue = 20_000_000
                            }
                        )
                    }
                    AppFilterResetButton(
                        help: language.text("Reset all filters", "Återställ alla filter")
                    ) {
                        resetFiltersToDefault()
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func applicationStatusFilterBox(_ status: String, language: AppLanguage) -> some View {
        AppFilterChip(
            label: applicationStatusFilterLabel(status, language: language),
            isSelected: selectedStatusFilters.contains(status)
        ) {
            toggleStatusFilter(status)
        }
    }

    private func applicationStatusFilterRow(language: AppLanguage) -> some View {
        AppFilterRow(
            showsClearButton: !selectedStatusFilters.isEmpty,
            clearAction: { selectedStatusFilters.removeAll() }
        ) {
            applicationStatusFilterBox("Att söka", language: language)
            applicationStatusFilterBox("Väntar svar", language: language)
            applicationStatusFilterBox("Beviljat", language: language)
            applicationStatusFilterBox("Tillbakadragen", language: language)
            applicationStatusFilterBox("Avslag", language: language)
            applicationStatusFilterBox("Ej sökt", language: language)
        }
    }

    private func applicationProjectFilterRow(language: AppLanguage) -> some View {
        AppFilterRow(
            showsClearButton: !selectedProjectFilters.isEmpty,
            clearAction: { selectedProjectFilters.removeAll() }
        ) {
            MultiSelectFilterMenu(
                title: language.text("Remove filter", "Ta bort filter"),
                emptyLabel: language.text("All projects", "Alla projekt"),
                options: projectOptions,
                selectedOptions: $selectedProjectFilters,
                display: { store.projectLabel(for: $0, language: language) }
            )
            .frame(width: 260)
        }
    }

    private func applicationStatusFilterLabel(_ status: String, language: AppLanguage) -> String {
        switch status {
        case "Beviljat":
            return language.text("Awarded", "Beviljade")
        case "Tillbakadragen":
            return language.text("Withdrawn", "Tillbakadragna")
        case "Avslag":
            return language.text("Declined", "Avslagna")
        case "Ej sökt":
            return language.text("Not applied", "Ej sökta")
        default:
            return language.localizedStatus(status)
        }
    }

    private func applicationQuickViewIsActive(_ view: QuickApplicationView) -> Bool {
        guard searchText.nonEmpty == nil,
              selectedProjectFilters.isEmpty,
              numericFiltersAreDefault,
              preset == nil else {
            return false
        }

        switch view {
        case .all:
            return selectedStatusFilters.isEmpty
                && applicationRoleFilter == .all
                && !showsOnlyFutureApplications
        case .active:
            return selectedStatusFilters == ["Att söka", "Väntar svar"]
                && applicationRoleFilter == .all
                && !showsOnlyFutureApplications
        case .findNew:
            return selectedStatusFilters.isEmpty
                && applicationRoleFilter == .all
                && showsOnlyFutureApplications
        case .own:
            return selectedStatusFilters.isEmpty
                && applicationRoleFilter == .currentUserFirst
                && !showsOnlyFutureApplications
        case .others:
            return selectedStatusFilters.isEmpty
                && applicationRoleFilter == .othersFirst
                && !showsOnlyFutureApplications
        }
    }

    private var numericFiltersAreDefault: Bool {
        minimumYearValue == yearBounds.lowerBound
            && maximumYearValue == yearBounds.upperBound
            && minimumAmountValue == 0
            && maximumAmountValue == 20_000_000
    }

    private func applicationResultsTable(language: AppLanguage) -> some View {
        let funderWidth: CGFloat = 150
        let grantWidth: CGFloat = 190
        let closesWidth: CGFloat = 92
        let projectWidth: CGFloat = 72
        let grantNumberWidth: CGFloat = 118
        let maxWidth: CGFloat = 88
        let tableContentWidth: CGFloat = funderWidth + grantWidth + closesWidth + projectWidth + grantNumberWidth + maxWidth
        let orderedIDs = filteredApplicationRows.map(\.selectionID)
        let reminderCounts = calendarTaskReminderBadgeCounts(entries: store.calendarTaskReminderBadgeEntries)

        return AppListTable(contentWidth: tableContentWidth) {
            HStack(spacing: 0) {
                applicationListHeader(language.text("Funder", "Anslagsgivare"), width: funderWidth, column: .funder)
                applicationListHeader(language.text("Grant", "Anslag"), width: grantWidth, column: .grant)
                applicationListHeader(language.text("Closes", "Stänger"), width: closesWidth, column: .closes)
                applicationListHeader(language.text("Project", "Projekt"), width: projectWidth, column: .project)
                applicationListHeader(language.text("Grant number", "Ansökningsnummer"), width: grantNumberWidth, column: .grantNumber)
                applicationListHeader(language.text("Max", "Max"), width: maxWidth, column: .maximumAmount)
            }
        } rowsWithProxy: { proxy in
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(filteredApplicationRows, id: \.selectionID) { app in
                    let isNotApplied = normalizedStatus(app.resultLabel) == "Ej sökt"
                    let reminderCount = reminderCounts.applicationCounts[app.id] ?? 0
                    let reminderHelp = calendarTaskReminderBadgeHelp(entries: reminderCounts.entries, language: language) {
                        $0.badgeTargets.contains(.application(app.id))
                    }
                    AppListRowButton(
                        width: tableContentWidth,
                        action: { handleApplicationSelectionCandidate(app.selectionID) },
                        background: { applicationListRowBackground(for: app) }
                    ) {
                        HStack(spacing: 0) {
                            applicationListPlainTextCell(
                                text: app.organizationLabel,
                                dimmed: app.isBeforeOpening,
                                deemphasized: !app.isCurrentUserFirstApplicant || isNotApplied
                            )
                                .padding(.trailing, reminderCount > 0 ? 34 : 0)
                                .frame(width: funderWidth, alignment: .leading)
                                .appReminderListBadge(reminderCount, help: reminderHelp)
                            applicationListPlainTextCell(
                                text: app.grantNameLabel,
                                dimmed: app.isBeforeOpening,
                                deemphasized: !app.isCurrentUserFirstApplicant || isNotApplied
                            )
                                .frame(width: grantWidth, alignment: .leading)
                            applicationListPlainTextCell(
                                text: app.closesText,
                                dimmed: app.isBeforeOpening,
                                deemphasized: !app.isCurrentUserFirstApplicant || isNotApplied
                            )
                                .frame(width: closesWidth, alignment: .leading)
                            applicationListPlainTextCell(
                                text: isNotApplied ? language.text("Not applied", "Ej sökt") : app.projectLabel,
                                dimmed: app.isBeforeOpening,
                                deemphasized: !app.isCurrentUserFirstApplicant || isNotApplied
                            )
                                .frame(width: projectWidth, alignment: .leading)
                            applicationListPlainTextCell(
                                text: app.appliedCaseNumber,
                                dimmed: app.isBeforeOpening,
                                deemphasized: !app.isCurrentUserFirstApplicant || isNotApplied
                            )
                                .frame(width: grantNumberWidth, alignment: .leading)
                            applicationListPlainTextCell(
                                text: app.maximumAmountText,
                                dimmed: app.isBeforeOpening,
                                deemphasized: !app.isCurrentUserFirstApplicant || isNotApplied
                            )
                                .frame(width: maxWidth, alignment: .leading)
                        }
                    }
                    .id(app.selectionID)

                    if app.selectionID != filteredApplicationRows.last?.selectionID {
                        Divider()
                    }
                }
            }
            .onAppear {
                centerApplicationListAroundCurrentFocus(using: proxy)
            }
            .onChange(of: filteredApplicationRows.map(\.selectionID)) { _, _ in
                centerApplicationListAroundCurrentFocus(using: proxy)
            }
        }
        .appListKeyboardNavigation(
            store: store,
            destination: .applications,
            isEnabled: isActive,
            orderedIDs: orderedIDs,
            selectedID: selectedApplicationID,
            onSelect: handleApplicationSelectionCandidate
        )
    }

    private func applicationListCountFootnote(language: AppLanguage) -> some View {
        ListCountFootnote(
            displayedCount: filteredApplicationRows.count,
            totalCount: store.applications.count,
            language: language
        )
    }

    private func applicationListHeader(_ title: String, width: CGFloat? = nil, column: ApplicationListSortColumn) -> some View {
        let showsColumnSort = !prioritizesActiveApplications || sortHistory.first?.column == .closes
        let criterion = showsColumnSort ? sortCriterion(for: column) : nil
        let sortIndex = showsColumnSort ? sortIndex(for: column) : nil
        return AppSortableListHeader(
            title: title,
            ascending: criterion?.ascending,
            sortIndex: sortIndex,
            width: width,
            resetTitle: store.language.text("Reset", "Återställ"),
            onToggle: { toggleSort(column) },
            onReset: resetSort
        )
    }

    private func toggleSort(_ column: ApplicationListSortColumn) {
        prioritizesActiveApplications = false
        if column == .closes {
            sortHistory.removeAll { $0.column == .closes }
            sortHistory.insert(ApplicationListSortCriterion(column: .closes, ascending: true), at: 0)
            ListSortPersistence.save(sortHistory, defaultsKey: "ApplicationsListSort")
            return
        }
        if let existingIndex = sortHistory.firstIndex(where: { $0.column == column }) {
            if existingIndex == 0 {
                sortHistory[0].ascending.toggle()
            } else {
                let criterion = sortHistory.remove(at: existingIndex)
                sortHistory.insert(criterion, at: 0)
            }
        } else {
            sortHistory.insert(ApplicationListSortCriterion(column: column, ascending: column.defaultAscending), at: 0)
        }
        ListSortPersistence.save(sortHistory, defaultsKey: "ApplicationsListSort")
    }

    private func resetSort() {
        prioritizesActiveApplications = false
        sortHistory = [
            ApplicationListSortCriterion(column: .closes, ascending: true)
        ]
        ListSortPersistence.save(sortHistory, defaultsKey: "ApplicationsListSort")
    }

    private func sortCriterion(for column: ApplicationListSortColumn) -> ApplicationListSortCriterion? {
        sortHistory.first(where: { $0.column == column })
    }

    private func sortIndex(for column: ApplicationListSortColumn) -> Int? {
        sortHistory.firstIndex(where: { $0.column == column })
    }

    @ViewBuilder
    private func applicationListPlainTextCell(text: String, dimmed: Bool, deemphasized: Bool = false) -> some View {
        let foregroundColor: Color = dimmed ? .secondary : (deemphasized ? Color.primary.opacity(0.72) : .primary)
        let content = Text(text)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .foregroundStyle(foregroundColor)

        if deemphasized {
            content.italic()
        } else {
            content
        }
    }

    private func applicationListRowBackground(for row: ApplicationRowSnapshot) -> some View {
        AppListRowBackground(
            isSelected: row.selectionID == selectedApplicationID,
            toneFill: applicationRowToneFillColor(for: row)
        )
    }

    private func applicationRowToneFillColor(for row: ApplicationRowSnapshot) -> Color? {
        if row.isFullySpent {
            return AppPalette.shadeGreen
        }

        let result = normalizedStatus(row.resultLabel)
        if result == "Ej sökt" {
            return nil
        }
        if result == "Beviljat" {
            return AppPalette.shadeGreen
        }
        if result.localizedCaseInsensitiveContains("Avslag") || result == "Tillbakadragen" {
            return AppPalette.shadeRed
        }
        if result == "Att söka" {
            return nil
        }
        return AppPalette.shadeYellow
    }

    private func rowMatchesSelection(row: ApplicationRowSnapshot, selectionID: String) -> Bool {
        if row.selectionID == selectionID {
            return true
        }
        if store.applicationSelectionIDIsScoped(selectionID) {
            return false
        }
        return row.id == selectionID
    }

    private func preferredInitialApplicationSelection(from candidateIDs: [String]) -> String? {
        guard !candidateIDs.isEmpty else { return nil }
        if let closestID = applicationIDClosestToToday(in: filteredApplicationRows),
           candidateIDs.contains(closestID) {
            return closestID
        }
        if let rememberedID = store.lastSelectedRecordID(for: .applications),
           candidateIDs.contains(rememberedID) {
            return rememberedID
        }
        if let rememberedID = store.lastSelectedRecordID(for: .applications),
           let rememberedRow = filteredApplicationRows.first(where: { rowMatchesSelection(row: $0, selectionID: rememberedID) }) {
            return rememberedRow.selectionID
        }
        return candidateIDs.first
    }

    private func centerApplicationListAroundCurrentFocus(using proxy: ScrollViewProxy) {
        let focusID = selectedApplicationID
            ?? applicationIDClosestToToday(in: filteredApplicationRows)
            ?? filteredApplicationRows.first?.selectionID
        guard let focusID else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(focusID, anchor: .center)
        }
    }

    private func applicationIDClosestToToday(in rows: [ApplicationRowSnapshot]) -> String? {
        let today = Calendar.current.startOfDay(for: Date())
        return rows
            .filter { $0.closeDate != nil }
            .min { lhs, rhs in
                let leftDistance = abs((lhs.closeDate ?? today).timeIntervalSince(today))
                let rightDistance = abs((rhs.closeDate ?? today).timeIntervalSince(today))
                if leftDistance != rightDistance {
                    return leftDistance < rightDistance
                }
                if let leftDate = lhs.closeDate,
                   let rightDate = rhs.closeDate,
                   leftDate != rightDate {
                    return leftDate < rightDate
                }
                return lhs.grantNameLabel.localizedStandardCompare(rhs.grantNameLabel) == .orderedAscending
            }?
            .selectionID
    }

    private func refreshApplicationRows() {
        applicationRows = store.applicationRowSnapshots()
        applicationRowsAppliedGeneration &+= 1
        nonSearchFilteredRowsCache.removeAll(keepingCapacity: true)
        filteredRowsCache.removeAll(keepingCapacity: true)
    }

    private func rebuildFilteredApplications() {
        searchRebuildTask?.cancel()
        let searchQuery = SearchFilterQuery(raw: searchText)
        let nonSearchSignature = applicationFilterSignature
        let exactCacheKey = FilterCacheKey(
            generation: applicationRowsAppliedGeneration,
            nonSearchSignature: nonSearchSignature,
            includedTerms: searchQuery.includedTerms,
            excludedTerms: searchQuery.excludedTerms
        )

        if let cachedRows = filteredRowsCache[exactCacheKey] {
            filteredApplicationRows = cachedRows
            if searchQuery.isEmpty {
                baseFilteredApplicationRows = cachedRows
            }
            lastApplicationSearchQuery = searchQuery
            lastApplicationNonSearchFilterSignature = nonSearchSignature
            return
        }

        let canReusePreviousSearchBase =
            nonSearchSignature == lastApplicationNonSearchFilterSignature
            && searchQuery.isNarrowing(over: lastApplicationSearchQuery)

        let baseRows: [ApplicationRowSnapshot]
        if let cachedBaseRows = nonSearchFilteredRowsCache[nonSearchSignature] {
            baseRows = cachedBaseRows
            baseFilteredApplicationRows = cachedBaseRows
        } else if canReusePreviousSearchBase {
            baseRows = baseFilteredApplicationRows
        } else {
            baseRows = sortedApplicationRows(nonSearchMatchingApplications)
            baseFilteredApplicationRows = baseRows
            nonSearchFilteredRowsCache[nonSearchSignature] = baseRows
        }

        let candidateRows = canReusePreviousSearchBase ? filteredApplicationRows : baseRows
        let filteredRows = searchQuery.isEmpty
            ? baseRows
            : candidateRows.filter { searchQuery.matches(normalizedHaystack: $0.normalizedSearchBlob) }
        filteredApplicationRows = filteredRows
        filteredRowsCache[exactCacheKey] = filteredRows
        trimFilterCachesIfNeeded()
        lastApplicationSearchQuery = searchQuery
        lastApplicationNonSearchFilterSignature = nonSearchSignature
    }

    private func sortedApplicationRows(_ rows: [ApplicationRowSnapshot]) -> [ApplicationRowSnapshot] {
        let sorted = rows.sorted(using: sortOrder)
        guard prioritizesActiveApplications, sortHistory.first?.column != .closes else { return sorted }
        return sorted
            .enumerated()
            .sorted { left, right in
                let leftPriority = applicationAttentionPriority(left.element)
                let rightPriority = applicationAttentionPriority(right.element)
                if leftPriority != rightPriority {
                    return leftPriority < rightPriority
                }
                return left.offset < right.offset
            }
            .map(\.element)
    }

    private func applicationAttentionPriority(_ row: ApplicationRowSnapshot) -> Int {
        let result = normalizedStatus(row.resultLabel)
        if result == "Väntar svar" {
            return 0
        }
        if row.isToApplyStatus && !row.isBeforeOpening {
            return 1
        }
        if row.isGranted && !row.isFullySpent {
            return 2
        }
        if row.isBeforeOpening {
            return 3
        }
        if row.isGranted {
            return 4
        }
        if result.localizedCaseInsensitiveContains("Avslag") || result == "Tillbakadragen" {
            return 5
        }
        return 6
    }

    private func trimFilterCachesIfNeeded() {
        if nonSearchFilteredRowsCache.count > 24 {
            nonSearchFilteredRowsCache.removeAll(keepingCapacity: true)
        }
        if filteredRowsCache.count > 48 {
            filteredRowsCache.removeAll(keepingCapacity: true)
        }
    }

    private func scheduleFilteredApplicationsRebuild() {
        searchRebuildTask?.cancel()
        let task = DispatchWorkItem {
            rebuildFilteredApplications()
        }
        searchRebuildTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
    }

    private func applyDirectApplicationRoute(_ recordID: String) {
        directRouteGeneration &+= 1
        let generation = directRouteGeneration
        let routeStartedAt = CFAbsoluteTimeGetCurrent()
        searchRebuildTask?.cancel()
        pendingDirectSelectionTimeoutTask?.cancel()
        pendingDirectSelectionTimeoutTask = nil
        isApplyingDirectApplicationRoute = true
        scheduleDirectRouteFailsafe(for: recordID, generation: generation)
        store.appendPerformanceDiagnostic(
            String(
                format: "application-direct-route-start id=%@",
                recordID
            )
        )
        guard isActive, generation == directRouteGeneration else {
            isApplyingDirectApplicationRoute = false
            return
        }
        resetFiltersForDirectNavigation()
        refreshApplicationRows()
        let resetDuration = (CFAbsoluteTimeGetCurrent() - routeStartedAt) * 1000
        store.appendPerformanceDiagnostic(
            String(
                format: "application-direct-route-step id=%@ phase=reset_filters ms=%.2f",
                recordID,
                resetDuration
            )
        )
        guard isActive, generation == directRouteGeneration else {
            isApplyingDirectApplicationRoute = false
            return
        }
        rebuildFilteredApplications()
        if !filteredApplicationRows.contains(where: { rowMatchesSelection(row: $0, selectionID: recordID) }) {
            refreshApplicationRows()
            rebuildFilteredApplications()
        }
        if !filteredApplicationRows.contains(where: { rowMatchesSelection(row: $0, selectionID: recordID) }),
           let targetRow = applicationRows.first(where: { rowMatchesSelection(row: $0, selectionID: recordID) }) {
            filteredApplicationRows = sortedApplicationRows(filteredApplicationRows + [targetRow])
        }
        let rebuildDuration = (CFAbsoluteTimeGetCurrent() - routeStartedAt) * 1000
        store.appendPerformanceDiagnostic(
            String(
                format: "application-direct-route-step id=%@ phase=rebuild_filtered ms=%.2f rows=%ld contains_target=%@",
                recordID,
                rebuildDuration,
                filteredApplicationRows.count,
                filteredApplicationRows.contains(where: { rowMatchesSelection(row: $0, selectionID: recordID) }) ? "yes" : "no"
            )
        )
        guard isActive, generation == directRouteGeneration else {
            isApplyingDirectApplicationRoute = false
            return
        }
        let resolvedSelectionID = filteredApplicationRows.first(where: { rowMatchesSelection(row: $0, selectionID: recordID) })?.selectionID ?? recordID
        setSelectedApplicationID(resolvedSelectionID, armLock: true)
        let selectionDuration = (CFAbsoluteTimeGetCurrent() - routeStartedAt) * 1000
        store.appendPerformanceDiagnostic(
            String(
                format: "application-direct-route-step id=%@ phase=set_selection ms=%.2f selected=%@",
                recordID,
                selectionDuration,
                selectedApplicationID ?? "-"
            )
        )
        DispatchQueue.main.async {
            guard generation == directRouteGeneration else { return }
            directRouteFailsafeTask?.cancel()
            directRouteFailsafeTask = nil
            isApplyingDirectApplicationRoute = false
            let totalDuration = (CFAbsoluteTimeGetCurrent() - routeStartedAt) * 1000
            store.appendPerformanceDiagnostic(
                String(
                    format: "application-direct-route-end id=%@ selected=%@ rows=%ld total_ms=%.2f",
                    recordID,
                    selectedApplicationID ?? "-",
                    filteredApplicationRows.count,
                    totalDuration
                )
            )
        }
    }

    private func consumeApplicationRouteIfSelectionMatches(_ recordID: String) {
        guard applicationsViewHasAppeared else { return }
        guard let route = store.route,
              route.destination == .applications,
              route.recordID == recordID else { return }
        guard let selectedApplicationID else { return }
        let selectedRowMatches = applicationRows.contains { row in
            row.selectionID == selectedApplicationID && rowMatchesSelection(row: row, selectionID: recordID)
        } || filteredApplicationRows.contains { row in
            row.selectionID == selectedApplicationID && rowMatchesSelection(row: row, selectionID: recordID)
        }
        guard selectedApplicationID == recordID || selectedRowMatches else {
            store.appendPerformanceDiagnostic(
                String(
                    format: "application-route-consume-waiting id=%@ selected=%@",
                    recordID,
                    selectedApplicationID
                )
            )
            return
        }
        store.appendPerformanceDiagnostic(
            String(
                format: "application-route-consumed-after-visible-selection id=%@ selected=%@",
                recordID,
                selectedApplicationID
            )
        )
        store.consumeRoute()
    }

    private func consumePendingDirectSelection(_ recordID: String) {
        pendingDirectSelectionTimeoutTask?.cancel()
        pendingDirectSelectionTimeoutTask = nil
        store.appendPerformanceDiagnostic(
            String(
                format: "application-pending-direct-selection-consume id=%@ active=%@",
                recordID,
                isActive ? "yes" : "no"
            )
        )
        pendingDirectSelectionID = nil
        applyDirectApplicationRoute(recordID)
    }

    private func schedulePendingDirectSelectionTimeoutIfNeeded() {
        pendingDirectSelectionTimeoutTask?.cancel()
        guard let pendingID = pendingDirectSelectionID, !isActive else {
            pendingDirectSelectionTimeoutTask = nil
            return
        }
        let task = DispatchWorkItem {
            guard pendingDirectSelectionID == pendingID else { return }
            store.appendPerformanceDiagnostic(
                String(
                    format: "application-pending-direct-selection-timeout id=%@",
                    pendingID
                )
            )
            pendingDirectSelectionID = nil
            isApplyingDirectApplicationRoute = false
        }
        pendingDirectSelectionTimeoutTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: task)
    }

    private func scheduleDirectRouteFailsafe(for recordID: String, generation: UInt) {
        directRouteFailsafeTask?.cancel()
        let task = DispatchWorkItem {
            guard generation == directRouteGeneration, isApplyingDirectApplicationRoute else { return }
            store.appendPerformanceDiagnostic(
                String(
                    format: "application-direct-route-timeout id=%@",
                    recordID
                )
            )
            isApplyingDirectApplicationRoute = false
        }
        directRouteFailsafeTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: task)
    }

    private func cancelInactiveRouteWork() {
        searchRebuildTask?.cancel()
        pendingDirectSelectionTimeoutTask?.cancel()
        pendingDirectSelectionTimeoutTask = nil
        directRouteFailsafeTask?.cancel()
        directRouteFailsafeTask = nil
        directRouteGeneration &+= 1
        isApplyingDirectApplicationRoute = false
    }

    private func scheduleApplicationIdleWarmup() {
        idleWarmupTask?.cancel()
        guard isActive else { return }
        let ids = Array(filteredApplicationRows.prefix(24).map(\.selectionID))
        guard !ids.isEmpty else { return }
        let task = DispatchWorkItem {
            guard isActive else { return }
            for id in ids {
                _ = store.application(selectionID: id)
            }
            store.appendPerformanceDiagnostic(
                String(
                    format: "applications-idle-warm rows=%ld",
                    ids.count
                )
            )
        }
        idleWarmupTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: task)
    }

    private func handleApplicationSelectionCandidate(_ newValue: String?) {
        guard applicationSelectionCoordinator.accepts(candidate: newValue) else { return }
        store.prioritizeUserInteraction()
        setSelectedApplicationID(newValue, armLock: newValue != nil)
    }

    private func setSelectedApplicationID(_ newValue: String?, armLock: Bool = false, resignFirstResponder: Bool = true) {
        guard selectedApplicationID != newValue else {
            if armLock, let newValue {
                armApplicationSelectionLock(for: newValue)
            }
            return
        }
        if resignFirstResponder {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        let previousID = selectedApplicationID
        selectedApplicationID = newValue
        if armLock, let newValue {
            applicationSelectionCoordinator.arm(newValue, previousID: previousID)
        } else if newValue == nil {
            applicationSelectionCoordinator.clear()
        }
    }

    private func armApplicationSelectionLock(for id: String) {
        applicationSelectionCoordinator.arm(
            id,
            previousID: applicationSelectionCoordinator.previousID
        )
    }

    private func releaseApplicationSelectionLock(for id: String) {
        applicationSelectionCoordinator.release(ifMatching: id)
    }
}

private struct GrantPipelineCurtainPanel: View {
    @ObservedObject var store: GrantDataStore
    let maxHeight: CGFloat
    let onSelectApplication: (String) -> Void
    @State private var measuredContentHeight: CGFloat = 0

    private var language: AppLanguage { store.language }
    private var neutralStepColor: Color { Color(red: 0.33, green: 0.33, blue: 0.36) }
    private var neutralStepLineColor: Color { Color(red: 0.58, green: 0.58, blue: 0.60) }
    private var effectiveMaxHeight: CGFloat { max(maxHeight, 0) }
    private var usesDarkAppearance: Bool { currentVisualModePreference()?.usesDarkAppearance == true }
    private var curtainChromeBackground: LinearGradient {
        LinearGradient(
            colors: [AppPalette.sidebarPanelSurface, AppPalette.sidebarPanelSurface],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var entries: [GrantPipelineCurtainEntry] {
        let sortedEntries = store.applications
            .compactMap(grantPipelineEntry(for:))
            .sorted(by: grantPipelineEntrySort)

        let grouped = Dictionary(grouping: sortedEntries, by: \.lane)
        return GrantPipelineCurtainLane.allCases.flatMap { lane in
            let laneEntries = grouped[lane, default: []]
            if lane == .toApply {
                return Array(laneEntries.prefix(9))
            }
            return laneEntries
        }
    }

    private var laneContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(GrantPipelineCurtainLane.allCases, id: \.id) { lane in
                    grantPipelineLaneHeader(lane)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }

            // An HStack adopts the height of its tallest column. Keeping all
            // principal-applicant cards in one shared row makes the divider
            // below it continuous and aligned across every status lane.
            HStack(alignment: .top, spacing: 12) {
                ForEach(GrantPipelineCurtainLane.allCases, id: \.id) { lane in
                    grantPipelineLeadApplicantContent(lane)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }

            if entries.contains(where: { !$0.isLeadApplicant }) {
                GrantPipelineSectionDivider(title: language.text("Not principal applicant", "Ej huvudsökande"))
            }

            HStack(alignment: .top, spacing: 12) {
                ForEach(GrantPipelineCurtainLane.allCases, id: \.id) { lane in
                    grantPipelineNonLeadApplicantContent(lane)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 30)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var measuredLaneContent: some View {
        laneContent
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: GrantPipelineCurtainContentHeightPreferenceKey.self,
                        value: geometry.size.height
                    )
                }
            )
    }

    private var usesScrolling: Bool {
        measuredContentHeight > effectiveMaxHeight
    }

    private var resolvedPanelHeight: CGFloat? {
        guard measuredContentHeight > 0 else { return nil }
        return min(measuredContentHeight, effectiveMaxHeight)
    }

    var body: some View {
        Group {
            if usesScrolling {
                ScrollView(.vertical, showsIndicators: true) {
                    measuredLaneContent
                }
                .frame(height: resolvedPanelHeight ?? effectiveMaxHeight)
            } else {
                measuredLaneContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(curtainChromeBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppPalette.subtleBorder)
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppPalette.subtleBorder)
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color.black.opacity(usesDarkAppearance ? 0.18 : 0.08),
                    Color.black.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 14)
            .offset(y: 14)
        }
        .onPreferenceChange(GrantPipelineCurtainContentHeightPreferenceKey.self) { newHeight in
            guard abs(newHeight - measuredContentHeight) > 0.5 else { return }
            measuredContentHeight = newHeight
        }
    }

    private func grantPipelineLaneHeader(_ lane: GrantPipelineCurtainLane) -> some View {
        let laneEntries = entries.filter { $0.lane == lane }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(lane.title(language: language))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                AppMetadataLabel(text: "\(laneEntries.count)")
            }

            Capsule(style: .continuous)
                .fill(neutralStepLineColor.opacity(0.45))
                .frame(height: 2)
        }
    }

    @ViewBuilder
    private func grantPipelineLeadApplicantContent(_ lane: GrantPipelineCurtainLane) -> some View {
        let leadApplicantEntries = entries.filter { $0.lane == lane && $0.isLeadApplicant }
        if !leadApplicantEntries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(leadApplicantEntries) { entry in
                    grantPipelineItem(entry)
                }
            }
        } else {
            Color.clear.frame(height: 0)
        }
    }

    @ViewBuilder
    private func grantPipelineNonLeadApplicantContent(_ lane: GrantPipelineCurtainLane) -> some View {
        let laneEntries = entries.filter { $0.lane == lane }
        let nonLeadApplicantEntries = laneEntries.filter { !$0.isLeadApplicant }
        if laneEntries.isEmpty {
            Text(language.text("No grants", "Inga anslag"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        } else if !nonLeadApplicantEntries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(nonLeadApplicantEntries) { entry in
                    grantPipelineItem(entry, isDimmed: true)
                }
            }
        } else {
            Color.clear.frame(height: 0)
        }
    }

    private func grantPipelineItem(_ entry: GrantPipelineCurtainEntry, isDimmed: Bool = false) -> some View {
        Button {
            onSelectApplication(entry.applicationID)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(neutralStepColor)
                    .frame(width: 5)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 8)

                        if let amountText = entry.amountText {
                            AppMetadataLabel(text: amountText, style: .micro)
                                .lineLimit(1)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }

                    HStack(alignment: .center, spacing: 8) {
                        Text(entry.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 8)

                        AppToneBadge(
                            text: entry.badgeText,
                            size: .compact,
                            foreground: grantPipelineBadgeStyle(for: entry.badgeDate).foreground,
                            background: grantPipelineBadgeStyle(for: entry.badgeDate).background,
                            stroke: AppPalette.subtleBorder,
                            horizontalPadding: 8,
                            verticalPadding: 4
                        )
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appInnerPanelChrome(padding: 0, fill: AppPalette.fieldSurface, stroke: AppPalette.subtleBorder)
            .opacity(isDimmed ? 0.62 : 1)
        }
        .buttonStyle(.plain)
    }

    private func grantPipelineEntry(for application: GrantApplication) -> GrantPipelineCurtainEntry? {
        let title = application.localizedGrantName(language: language).nonEmpty
            ?? application.applicationTitle?.nonEmpty
            ?? language.text("Untitled grant", "Namnlöst anslag")
        let organization = application.organization.nonEmpty
            ?? application.projectType?.nonEmpty
            ?? language.text("No grant provider", "Ingen anslagsgivare")
        let project = application.projectType?.nonEmpty

        if isCurrentlyOpenToApply(application) {
            return GrantPipelineCurtainEntry(
                applicationID: application.id,
                title: title,
                subtitle: [organization, project].compactMap { $0 }.joined(separator: " · "),
                amountText: grantPipelineAmountText(for: application, lane: .toApply),
                badgeText: grantPipelineCloseBadge(for: application.closeDate),
                badgeDate: application.closeDate,
                lane: .toApply,
                sortDate: application.closeDate,
                isLeadApplicant: store.isCurrentUserFirstApplicant(application)
            )
        }

        // Closed but still "Att söka": stays under "Att söka" until it is
        // answered, instead of dropping out of every lane.
        if application.awaitsAppliedAnswer() {
            return GrantPipelineCurtainEntry(
                applicationID: application.id,
                title: title,
                subtitle: [organization, project].compactMap { $0 }.joined(separator: " · "),
                amountText: grantPipelineAmountText(for: application, lane: .toApply),
                badgeText: language.text("Closed – applied?", "Stängd – sökt?"),
                badgeDate: application.closeDate,
                lane: .toApply,
                sortDate: application.closeDate,
                isLeadApplicant: store.isCurrentUserFirstApplicant(application)
            )
        }

        let normalizedStatus = application.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedStatus == "Väntar svar" {
            let daysUntilDecision = grantPipelineDaysUntil(application.decisionExpectedDate)
            let lane: GrantPipelineCurtainLane
            if let daysUntilDecision, daysUntilDecision <= 30 {
                lane = .pendingSoon
            } else {
                lane = .pendingYear
            }

            return GrantPipelineCurtainEntry(
                applicationID: application.id,
                title: title,
                subtitle: [organization, project].compactMap { $0 }.joined(separator: " · "),
                amountText: grantPipelineAmountText(for: application, lane: lane),
                badgeText: grantPipelineDecisionBadge(for: application.decisionExpectedDate),
                badgeDate: application.decisionExpectedDate,
                lane: lane,
                sortDate: application.decisionExpectedDate ?? application.applicationDate ?? application.closeDate,
                isLeadApplicant: store.isCurrentUserFirstApplicant(application)
            )
        }

        if application.isGranted,
           let remaining = store.effectiveRemainingGrantedAmountValue(for: application),
           remaining > 0 {
            let usageEndDate = grantPipelineUsageEndDate(for: application)
            return GrantPipelineCurtainEntry(
                applicationID: application.id,
                title: title,
                subtitle: [organization, project].compactMap { $0 }.joined(separator: " · "),
                amountText: grantPipelineAmountText(for: application, lane: .grantedRemaining),
                badgeText: grantPipelineGrantedBadge(for: application),
                badgeDate: usageEndDate,
                lane: .grantedRemaining,
                sortDate: usageEndDate ?? application.firstDispositionDate ?? application.grantedDate ?? application.applicationDate,
                isLeadApplicant: store.isCurrentUserFirstApplicant(application)
            )
        }

        return nil
    }

    private func isCurrentlyOpenToApply(_ application: GrantApplication) -> Bool {
        guard application.isToApplyStatus,
              let closeDate = application.closeDate else {
            return false
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard calendar.startOfDay(for: closeDate) >= today else {
            return false
        }

        if let openDate = application.openDate {
            return calendar.startOfDay(for: openDate) <= today
        }

        return true
    }

    private func grantPipelineEntrySort(_ lhs: GrantPipelineCurtainEntry, _ rhs: GrantPipelineCurtainEntry) -> Bool {
        if lhs.lane.sortRank != rhs.lane.sortRank {
            return lhs.lane.sortRank < rhs.lane.sortRank
        }

        switch (lhs.sortDate, rhs.sortDate) {
        case let (left?, right?):
            if left != right {
                return left < right
            }
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            break
        }

        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private func grantPipelineCloseBadge(for date: Date?) -> String {
        guard let days = grantPipelineDaysUntil(date) else {
            return language.text("Deadline missing", "Saknar deadline")
        }
        return language.text(
            "Closes in \(days) d",
            "Stänger om \(days) d"
        )
    }

    private func grantPipelineDecisionBadge(for date: Date?) -> String {
        guard let days = grantPipelineDaysUntil(date) else {
            return language.text("Decision date missing", "Saknar beslutsdatum")
        }
        return language.text(
            "Decision in \(days) d",
            "Besked om \(days) d"
        )
    }

    private func grantPipelineGrantedBadge(for application: GrantApplication) -> String {
        guard let days = grantPipelineDaysUntil(grantPipelineUsageEndDate(for: application)) else {
            return language.text("Usage end missing", "Saknar dispositionsslut")
        }

        return language.text(
            "\(days) d left",
            "\(days) d kvar"
        )
    }

    private func grantPipelineAmountText(for application: GrantApplication, lane: GrantPipelineCurtainLane) -> String? {
        switch lane {
        case .grantedRemaining:
            guard let remaining = store.effectiveRemainingGrantedAmountValue(for: application),
                  remaining > 0 else { return nil }
            let formatted = grantPipelineCurrencyLabel(remaining, for: application)
            return language.text("Remaining \(formatted)", "Återstår \(formatted)")
        case .pendingYear, .pendingSoon:
            guard let amount = grantPipelineRequestedAmount(for: application) else { return nil }
            let formatted = grantPipelineCurrencyLabel(amount, for: application)
            return language.text("Applied \(formatted)", "Sökt \(formatted)")
        case .toApply:
            guard let amount = grantPipelineRequestedAmount(for: application) else { return nil }
            let formatted = grantPipelineCurrencyLabel(amount, for: application)
            return language.text("To seek \(formatted)", "Söks \(formatted)")
        }
    }

    private func grantPipelineRequestedAmount(for application: GrantApplication) -> Double? {
        if let applied = application.appliedAmountValue, applied > 0 {
            return applied
        }
        if let preferred = application.preferredBudgetAmountValue, preferred > 0 {
            return preferred
        }
        if let granted = application.grantedAmountValue, granted > 0 {
            return granted
        }
        return nil
    }

    private func grantPipelineCurrencyLabel(_ value: Double, for application: GrantApplication) -> String {
        let formatted = store.formattedGrantAmountWithSEKApproximation(value, for: application)
        guard application.currencyCode == "SEK" else { return formatted }
        return formatted.replacingOccurrences(of: " SEK", with: " kr")
    }

    private func grantPipelineDaysUntil(_ date: Date?) -> Int? {
        guard let date else { return nil }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: date)
        ).day
        return max(days ?? 0, 0)
    }

    private func grantPipelineUsageEndDate(for application: GrantApplication) -> Date? {
        application.lastDispositionDate
            ?? application.receivedUsageTo.flatMap(DateParsers.isoDay.date(from:))
    }

    private func grantPipelineBadgeStyle(for date: Date?) -> (foreground: Color, background: Color) {
        guard let days = grantPipelineDaysUntil(date) else {
            return (Color.primary, AppPalette.subtleBorder.opacity(0.45))
        }

        if days < 30 {
            return (AppPalette.semanticOnColor, AppPalette.vividRed)
        }
        if days < 90 {
            return (AppPalette.semanticOnColor, AppPalette.vividYellow)
        }
        return (AppPalette.semanticOnColor, AppPalette.vividGreen)
    }
}

private struct GrantPipelineCurtainEntry: Identifiable {
    let applicationID: String
    let title: String
    let subtitle: String
    let amountText: String?
    let badgeText: String
    let badgeDate: Date?
    let lane: GrantPipelineCurtainLane
    let sortDate: Date?
    let isLeadApplicant: Bool

    var id: String {
        "\(applicationID)|\(lane.rawValue)"
    }
}

private struct GrantPipelineSectionDivider: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(AppPalette.subtleBorder.opacity(0.85))
                .frame(height: 1)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Rectangle()
                .fill(AppPalette.subtleBorder.opacity(0.85))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 3)
    }
}

private enum GrantPipelineCurtainLane: String, CaseIterable, Identifiable {
    case toApply
    case pendingYear
    case pendingSoon
    case grantedRemaining

    var id: String { rawValue }

    var sortRank: Int {
        switch self {
        case .toApply:
            return 0
        case .pendingYear:
            return 1
        case .pendingSoon:
            return 2
        case .grantedRemaining:
            return 3
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .toApply:
            return language.text("To apply", "Att söka")
        case .pendingYear:
            return language.text("Applied, waiting within 1 year", "Sökta, väntar svar inom 1 år")
        case .pendingSoon:
            return language.text("Applied, waiting within 30 days", "Sökta, väntar svar inom 30 dagar")
        case .grantedRemaining:
            return language.text("Granted, funds remaining", "Beviljade, medel kvar")
        }
    }
}

private struct GrantPipelineCurtainContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
