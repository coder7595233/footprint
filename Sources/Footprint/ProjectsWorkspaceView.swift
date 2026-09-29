import AppKit
import SwiftUI

struct ProjectsWorkspaceView: View {
    private enum ProjectListSortColumn: String, Hashable {
        case status
        case title
        case granted
        case publications
        case leader

        var defaultAscending: Bool {
            switch self {
            case .status, .title, .leader:
                return true
            case .granted, .publications:
                return false
            }
        }
    }

    private struct ProjectListSortCriterion: AppListSortCriterion {
        let column: ProjectListSortColumn
        var ascending: Bool
    }

    private enum ProjectLeaderFilter: String, Codable, CaseIterable, Identifiable {
        case all
        case you
        case others

        var id: String { rawValue }

        func title(language: AppLanguage) -> String {
            switch self {
            case .all:
                return language.text("All projects", "Alla projekt")
            case .you:
                return language.text("Own projects", "Egna projekt")
            case .others:
                return language.text("Others' projects", "Andras projekt")
            }
        }
    }

    private enum ProjectCompletionFilter: String, Codable, CaseIterable, Identifiable {
        case ongoingOnly
        case includeCompleted

        var id: String { rawValue }

        func title(language: AppLanguage) -> String {
            switch self {
            case .ongoingOnly:
                return language.text("Ongoing only", "Bara pågående")
            case .includeCompleted:
                return language.text("Include completed", "Även avslutade")
            }
        }
    }

    let store: GrantDataStore
    let newRecordTrigger: Int
    let isActive: Bool
    @State private var selectedProjectID: String?
    @State private var hasResolvedInitialSelection = false
    @State private var pendingSelectionMeasurementID: String?
    @State private var pendingSelectionStartedAt: CFAbsoluteTime?
    @State private var projectSelectionCoordinator = AppSelectionCoordinator<String>()
    @State private var projectSortHistory = ListSortPersistence.load(
        defaultsKey: "ProjectsListSort",
        defaultValue: [
            ProjectListSortCriterion(column: .status, ascending: true),
            ProjectListSortCriterion(column: .leader, ascending: true),
            ProjectListSortCriterion(column: .title, ascending: true),
        ]
    )
    @WorkspaceFilterState("Projects.Filter.Search") private var searchText = ""
    @WorkspaceFilterState("Projects.Filter.OwnOngoing") private var showsOnlyOwnOngoingProjects = false
    @WorkspaceFilterState("Projects.Filter.RemainingFunds") private var showsOnlyProjectsWithRemainingFunds = false
    @WorkspaceFilterState("Projects.Filter.ActiveTasks") private var showsOnlyProjectsWithActiveTasks = false
    @WorkspaceFilterState("Projects.Filter.Leader") private var projectLeaderFilter: ProjectLeaderFilter = .all
    @WorkspaceFilterState("Projects.Filter.Researcher") private var projectResearcherFilter = ""
    @WorkspaceFilterState("Projects.Filter.Completion") private var projectCompletionFilter: ProjectCompletionFilter = .includeCompleted
    @State private var projectSnapshots: [ProjectRowSnapshot] = []
    @State private var needsSnapshotRefreshWhenActive = false

    init(store: GrantDataStore, newRecordTrigger: Int, isActive: Bool) {
        self.store = store
        self.newRecordTrigger = newRecordTrigger
        self.isActive = isActive
        // Resolve the final selection after persisted filters and the current
        // route are available. Mounting the remembered project here caused an
        // expensive, invisible editor build before a routed project replaced it.
        _selectedProjectID = State(initialValue: nil)
        _projectSnapshots = State(initialValue: store.projectRowSnapshots())
    }

    private var projectSelectionBinding: Binding<String?> {
        Binding(
            get: { selectedProjectID },
            set: { newValue in
                handleProjectSelectionCandidate(newValue)
            }
        )
    }

    private var hasActiveProjectFilters: Bool {
        searchText.nonEmpty != nil
            || projectResearcherFilter.nonEmpty != nil
            || showsOnlyOwnOngoingProjects
            || showsOnlyProjectsWithRemainingFunds
            || showsOnlyProjectsWithActiveTasks
            || projectCompletionFilter != .includeCompleted
            || projectLeaderFilter != .all
    }

    private var filteredProjects: [ProjectDirectoryRow] {
        projectSnapshots
            .map(projectRow(for:))
            .filter { row in
                let matchesLeader: Bool
                switch projectLeaderFilter {
                case .all:
                    matchesLeader = true
                case .you:
                    matchesLeader = row.isLedByCurrentUser
                case .others:
                    matchesLeader = !row.isLedByCurrentUser
                }
                let matchesCompletion = projectCompletionFilter == .includeCompleted || row.status != .completed
                let matchesResearcher = projectResearcherFilter.isEmpty || row.collaboratorNames.contains(projectResearcherFilter)
                let matchesOwnOngoing = !showsOnlyOwnOngoingProjects || row.isLedByCurrentUser && row.status == .ongoing
                let matchesRemainingFunds = !showsOnlyProjectsWithRemainingFunds || row.hasRemainingGrantedFunds
                let matchesActiveTasks = !showsOnlyProjectsWithActiveTasks || row.hasActiveTasks
                let searchQuery = SearchFilterQuery(raw: searchText)
                let matchesSearch = searchQuery.isEmpty || searchQuery.matches(normalizedHaystack: row.normalizedSearchBlob)
                return matchesLeader
                    && matchesCompletion
                    && matchesResearcher
                    && matchesOwnOngoing
                    && matchesRemainingFunds
                    && matchesActiveTasks
                    && matchesSearch
            }
            .sorted(using: projectSortOrder(from: projectSortHistory))
    }

    private var projectResearcherOptions: [String] {
        Array(
            Set(
                projectSnapshots.flatMap { $0.collaboratorNames }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        let language = store.language

        PersistentSplitView(layout: .projects) {
            AppWorkspaceSidebar {
                projectsSidebar(language: language)
            }
            .onAppear {
                store.appendPerformanceDiagnostic(
                    String(
                        format: "projects-view-onAppear active=%@",
                        isActive ? "yes" : "no"
                    )
                )
                if isActive {
                    refreshProjectSnapshots()
                    if let route = store.route, route.destination == .projects {
                        setSelectedProjectID(route.recordID, armLock: true)
                        store.consumeRoute()
                    } else if selectedProjectID == nil {
                        setSelectedProjectID(store.lastSelectedRecordID(for: .projects) ?? filteredProjects.first?.id)
                    } else {
                        ensureSelectedProjectMatchesFilters()
                    }
                    hasResolvedInitialSelection = true
                } else {
                    needsSnapshotRefreshWhenActive = true
                }
            }
            // onReceive, not onChange: the subscription delivers every
            // generation bump even when the body does not happen to
            // re-evaluate around the mutation (the stale-list-after-delete
            // class of bug).
            .onReceive(store.$projectRowSnapshotGeneration.dropFirst()) { _ in
                guard isActive else {
                    needsSnapshotRefreshWhenActive = true
                    return
                }
                refreshProjectSnapshots()
                let ids = filteredProjects.map(\.id)
                if !ids.contains(selectedProjectID ?? "") {
                    setSelectedProjectID(ids.first)
                }
            }
            .onChange(of: store.route) { _, route in
                guard let route, route.destination == .projects else { return }
                guard isActive else {
                    store.appendPerformanceDiagnostic(
                        String(
                            format: "project-route-deferred id=%@",
                            route.recordID
                        )
                    )
                    return
                }
                setSelectedProjectID(route.recordID, armLock: true)
                store.consumeRoute()
            }
            .onChange(of: selectedProjectID) { _, id in
                store.handlePendingSelectionReturnIfNeeded(for: id, in: .projects)
                store.rememberSelection(id: id, for: .projects)
            }
            .onChange(of: newRecordTrigger) { _, _ in
                guard isActive else { return }
                setSelectedProjectID(store.addProject(), armLock: true)
            }
            .onChange(of: isActive) { _, active in
                store.appendPerformanceDiagnostic(
                    String(
                        format: "projects-active-changed active=%@ pending_snapshots=%@",
                        active ? "yes" : "no",
                        needsSnapshotRefreshWhenActive ? "yes" : "no"
                    )
                )
                guard active else {
                    clearProjectFiltersForDeactivationIfNeeded()
                    return
                }
                if needsSnapshotRefreshWhenActive {
                    refreshProjectSnapshots()
                    needsSnapshotRefreshWhenActive = false
                    let ids = filteredProjects.map(\.id)
                    if !ids.contains(selectedProjectID ?? "") {
                        setSelectedProjectID(ids.first)
                    }
                }
                if let route = store.route, route.destination == .projects {
                    setSelectedProjectID(route.recordID, armLock: true)
                    store.consumeRoute()
                } else if selectedProjectID == nil {
                    setSelectedProjectID(store.lastSelectedRecordID(for: .projects) ?? filteredProjects.first?.id)
                }
            }
        } detail: {
            if !hasResolvedInitialSelection {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let project = store.projects.first(where: { $0.id == selectedProjectID }) {
                ProjectDetailView(
                    store: store,
                    project: project,
                    isActive: isActive
                )
                // ProjectDetailView synchronizes its complete editor state when
                // the project changes. Keeping its identity preserves the AppKit
                // control tree instead of constructing the whole form twice.
                .undoRevealPulse(
                    triggerID: store.undoRevealRequest?.id,
                    isActive: store.undoRevealRequest?.target.matchesWholeRecord(routeDestination: .projects, recordID: project.id) == true
                )
                .performanceScopeProbe(store: store, scope: "projects-detail", identifier: project.id)
                .background(
                    PerformanceReadyTriggerReporter(trigger: project.id) {
                        DispatchQueue.main.async {
                            guard pendingSelectionMeasurementID == project.id,
                                  let pendingSelectionStartedAt else { return }
                            let duration = (CFAbsoluteTimeGetCurrent() - pendingSelectionStartedAt) * 1000
                            store.appendPerformanceDiagnostic(
                                String(
                                    format: "project-view-complete project=%@ total_ms=%.2f",
                                    project.nameSv,
                                    duration
                                )
                            )
                            releaseProjectSelectionLock(for: project.id)
                            self.pendingSelectionMeasurementID = nil
                            self.pendingSelectionStartedAt = nil
                        }
                    }
                )
            } else {
                AppWorkspaceEmptyStateView(
                    title: language.text("No projects yet", "Inga projekt ännu"),
                    subtitle: language.text("Add a project to track its totals and related applications.", "Lägg till ett projekt för att följa totaler och relaterade ansökningar."),
                    kind: .projects
                )
            }
        }
        .onDeleteCommand {
            guard let selectedProjectID, let project = store.projects.first(where: { $0.id == selectedProjectID }) else { return }
            store.deleteProject(id: project.id)
        }
    }

    private func refreshProjectSnapshots() {
        projectSnapshots = store.projectRowSnapshots()
    }

    private func handleProjectSelectionCandidate(_ newValue: String?) {
        guard projectSelectionCoordinator.accepts(candidate: newValue) else { return }
        store.prioritizeUserInteraction()
        setSelectedProjectID(newValue, armLock: newValue != nil)
    }

    private func setSelectedProjectID(_ newValue: String?, armLock: Bool = false, resignFirstResponder: Bool = true) {
        guard selectedProjectID != newValue else {
            if armLock, let newValue {
                armProjectSelectionLock(for: newValue)
            }
            return
        }
        if resignFirstResponder {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        let previousID = selectedProjectID
        pendingSelectionMeasurementID = newValue
        pendingSelectionStartedAt = newValue == nil ? nil : CFAbsoluteTimeGetCurrent()
        store.appendPerformanceDiagnostic(
            String(
                format: "project-selection-start id=%@",
                newValue ?? "-"
            )
        )
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            selectedProjectID = newValue
        }
        if armLock, let newValue {
            projectSelectionCoordinator.arm(newValue, previousID: previousID)
        } else if newValue == nil {
            projectSelectionCoordinator.clear()
        }
    }

    private func armProjectSelectionLock(for id: String) {
        projectSelectionCoordinator.arm(
            id,
            previousID: projectSelectionCoordinator.previousID
        )
    }

    private func releaseProjectSelectionLock(for id: String) {
        projectSelectionCoordinator.release(ifMatching: id)
    }

    private func projectRow(for project: ProjectRowSnapshot) -> ProjectDirectoryRow {
        ProjectDirectoryRow(
            id: project.id,
            title: project.title,
            status: project.status,
            applicationCount: project.applicationCount,
            grantedAmount: project.grantedAmount,
            hasRemainingGrantedFunds: project.hasRemainingGrantedFunds,
            publishedPublicationCount: project.publishedPublicationCount,
            leaderName: project.leaderName,
            isLedByCurrentUser: project.isLedByCurrentUser,
            hasDataCollection: project.hasDataCollection,
            hasActiveTasks: project.hasActiveTasks,
            collaboratorNames: project.collaboratorNames,
            collaboratorFlags: project.collaboratorFlags
        )
    }

    @ViewBuilder
    private func projectsSidebar(language: AppLanguage) -> some View {
        let rows = filteredProjects
        let orderedProjectIDs = rows.map(\.id)

        VStack(alignment: .leading, spacing: 12) {
            AppWorkspaceSidebarHeader(
                title: language.text("Projects", "Projekt"),
                actionTitle: language.text("New project", "Nytt projekt")
            ) {
                setSelectedProjectID(store.addProject(), armLock: true)
            }

            projectFilters(language: language)

            projectsTable(rows: rows, language: language)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            ListCountFootnote(
                displayedCount: rows.count,
                totalCount: projectSnapshots.count,
                language: language
            )
        }
        .appListKeyboardNavigation(
            store: store,
            destination: .projects,
            isEnabled: isActive,
            orderedIDs: orderedProjectIDs,
            selectedID: selectedProjectID,
            onSelect: handleProjectSelectionCandidate
        )
        .onChange(of: projectLeaderFilter) { _, _ in
            ensureSelectedProjectMatchesFilters()
        }
        .onChange(of: searchText) { _, _ in
            ensureSelectedProjectMatchesFilters()
        }
        .onChange(of: projectResearcherFilter) { _, newValue in
            if !newValue.isEmpty && !projectResearcherOptions.contains(newValue) {
                projectResearcherFilter = ""
            }
            ensureSelectedProjectMatchesFilters()
        }
        .onChange(of: projectCompletionFilter) { _, _ in
            ensureSelectedProjectMatchesFilters()
        }
        .onChange(of: showsOnlyOwnOngoingProjects) { _, _ in
            ensureSelectedProjectMatchesFilters()
        }
        .onChange(of: showsOnlyProjectsWithRemainingFunds) { _, _ in
            ensureSelectedProjectMatchesFilters()
        }
        .onChange(of: showsOnlyProjectsWithActiveTasks) { _, _ in
            ensureSelectedProjectMatchesFilters()
        }
    }

    private func ensureSelectedProjectMatchesFilters() {
        let ids = filteredProjects.map(\.id)
        if !ids.contains(selectedProjectID ?? "") {
            setSelectedProjectID(ids.first, resignFirstResponder: false)
        }
    }

    private func clearProjectFiltersForDeactivationIfNeeded() {
        guard !store.shouldRetainListFilters(for: .projects) else { return }
        guard hasActiveProjectFilters else { return }
        searchText = ""
        projectResearcherFilter = ""
        showsOnlyOwnOngoingProjects = false
        showsOnlyProjectsWithRemainingFunds = false
        showsOnlyProjectsWithActiveTasks = false
        projectCompletionFilter = .includeCompleted
        projectLeaderFilter = .all
    }

    private func projectFilters(language: AppLanguage) -> some View {
        AppFilterCard {
            VStack(alignment: .leading, spacing: 8) {
                AppFilterRow(
                    showsClearButton: searchText.nonEmpty != nil || projectResearcherFilter.nonEmpty != nil,
                    clearAction: {
                        searchText = ""
                        projectResearcherFilter = ""
                    }
                ) {
                    AppSidebarSearchField(
                        placeholder: language.text("Search projects", "Sök projekt"),
                        text: $searchText
                    )

                    AppMenuSelectionField(
                        selection: $projectResearcherFilter,
                        options: [(language.text("All researchers", "Alla forskare"), "")]
                            + projectResearcherOptions.map { ($0, $0) }
                    )
                    .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                }

                AppFilterRow(
                    showsClearButton: showsOnlyOwnOngoingProjects || showsOnlyProjectsWithRemainingFunds || showsOnlyProjectsWithActiveTasks,
                    clearAction: {
                        showsOnlyOwnOngoingProjects = false
                        showsOnlyProjectsWithRemainingFunds = false
                        showsOnlyProjectsWithActiveTasks = false
                    }
                ) {
                    AppFilterChip(
                        label: language.text("Own ongoing", "Egna pågående"),
                        isSelected: showsOnlyOwnOngoingProjects
                    ) {
                        showsOnlyOwnOngoingProjects.toggle()
                    }
                    AppFilterChip(
                        label: language.text("Remaining funds", "Kvarvarande medel"),
                        isSelected: showsOnlyProjectsWithRemainingFunds
                    ) {
                        showsOnlyProjectsWithRemainingFunds.toggle()
                    }
                    AppFilterChip(
                        label: language.text("Active tasks", "Aktiva uppgifter"),
                        isSelected: showsOnlyProjectsWithActiveTasks
                    ) {
                        showsOnlyProjectsWithActiveTasks.toggle()
                    }
                }

                AppFilterRow(
                    showsClearButton: projectCompletionFilter != .includeCompleted,
                    clearAction: { projectCompletionFilter = .includeCompleted }
                ) {
                    ForEach(ProjectCompletionFilter.allCases) { filter in
                        AppFilterChip(
                            label: filter.title(language: language),
                            isSelected: projectCompletionFilter == filter
                        ) {
                            projectCompletionFilter = filter
                        }
                    }
                }

                AppFilterRow(
                    showsClearButton: projectLeaderFilter != .all,
                    clearAction: { projectLeaderFilter = .all }
                ) {
                    ForEach(ProjectLeaderFilter.allCases) { filter in
                        AppFilterChip(
                            label: projectLeaderFilterLabel(filter, language: language),
                            isSelected: projectLeaderFilter == filter
                        ) {
                            projectLeaderFilter = filter
                        }
                    }
                }

                AppFilterClearAllRow(isVisible: hasActiveProjectFilters) {
                    searchText = ""
                    projectResearcherFilter = ""
                    showsOnlyOwnOngoingProjects = false
                    showsOnlyProjectsWithRemainingFunds = false
                    showsOnlyProjectsWithActiveTasks = false
                    projectCompletionFilter = .includeCompleted
                    projectLeaderFilter = .all
                }
            }
        }
    }

    private func projectLeaderFilterLabel(_ filter: ProjectLeaderFilter, language: AppLanguage) -> String {
        switch filter {
        case .all:
            return language.text("All", "Alla")
        case .you:
            return language.text("Own", "Egna")
        case .others:
            return language.text("Others", "Andras")
        }
    }

    @ViewBuilder
    private func projectsTable(
        rows: [ProjectDirectoryRow],
        language: AppLanguage
    ) -> some View {
        let titleWidth: CGFloat = 190
        let leaderWidth: CGFloat = 72
        let grantedWidth: CGFloat = 92
        let publicationsWidth: CGFloat = 66
        let tableContentWidth: CGFloat = titleWidth + leaderWidth + grantedWidth + publicationsWidth + 20
        let reminderCounts = calendarTaskReminderBadgeCounts(entries: store.calendarTaskReminderBadgeEntries)

        AppListTable(contentWidth: tableContentWidth) {
            HStack(spacing: 0) {
                projectListHeader(
                    language.text("Title", "Titel"),
                    width: titleWidth,
                    column: .title
                )
                projectListHeader(
                    language.text("Leader", "Ledare"),
                    width: leaderWidth,
                    column: .leader
                )
                projectListHeader(
                    language.text("Granted sums", "Beviljat"),
                    width: grantedWidth,
                    column: .granted
                )
                projectListHeader(
                    language.text("Published publications", "Publikationer"),
                    width: publicationsWidth,
                    column: .publications
                )
            }
        } rows: {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows, id: \.id) { row in
                    let reminderCount = reminderCounts.projectCounts[row.id] ?? 0
                    let reminderHelp = calendarTaskReminderBadgeHelp(entries: reminderCounts.entries, language: language) {
                        $0.badgeTargets.contains(.project(row.id))
                    }
                    AppListRowButton(
                        width: tableContentWidth,
                        action: { handleProjectSelectionCandidate(row.id) },
                        background: { projectListRowBackground(for: row) }
                    ) {
                        HStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Text(row.title)
                                    .lineLimit(1)
                                ProjectCollaboratorFlagsView(flags: row.collaboratorFlags)
                            }
                            .padding(.trailing, reminderCount > 0 ? 34 : 0)
                            .frame(width: titleWidth, alignment: .leading)
                            .appReminderListBadge(reminderCount, help: reminderHelp)
                            Text(projectLeaderLabel(for: row, language: language))
                                .lineLimit(1)
                                .frame(width: leaderWidth, alignment: .leading)
                            Text(projectGrantedLabel(for: row))
                                .frame(width: grantedWidth, alignment: .leading)
                            Text("\(row.publishedPublicationCount)")
                                .frame(width: publicationsWidth, alignment: .leading)
                        }
                    }
                    .id(row.id)

                    if row.id != rows.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func projectListHeader(
        _ title: String,
        width: CGFloat?,
        column: ProjectListSortColumn
    ) -> some View {
        let criterion = projectSortHistory.first(where: { $0.column == column })
        let sortIndex = projectSortHistory.firstIndex(where: { $0.column == column })
        return AppSortableListHeader(
            title: title,
            ascending: criterion?.ascending,
            sortIndex: sortIndex,
            width: width,
            resetTitle: store.language.text("Reset", "Återställ"),
            onToggle: { toggleProjectSort(column) },
            onReset: resetProjectSort
        )
    }

    private func toggleProjectSort(_ column: ProjectListSortColumn) {
        var history = projectSortHistory
        if let existingIndex = history.firstIndex(where: { $0.column == column }) {
            if existingIndex == 0 {
                history[0].ascending.toggle()
            } else {
                let criterion = history.remove(at: existingIndex)
                history.insert(criterion, at: 0)
            }
        } else {
            history.insert(ProjectListSortCriterion(column: column, ascending: column.defaultAscending), at: 0)
        }
        projectSortHistory = history
        ListSortPersistence.save(history, defaultsKey: "ProjectsListSort")
    }

    private func resetProjectSort() {
        projectSortHistory = [
            ProjectListSortCriterion(column: .status, ascending: true),
            ProjectListSortCriterion(column: .leader, ascending: true),
            ProjectListSortCriterion(column: .title, ascending: true),
        ]
        ListSortPersistence.save(projectSortHistory, defaultsKey: "ProjectsListSort")
    }

    private func projectSortOrder(from history: [ProjectListSortCriterion]) -> [KeyPathComparator<ProjectDirectoryRow>] {
        var columns = history.map(\.column)
        for fallbackColumn in [ProjectListSortColumn.title] where !columns.contains(fallbackColumn) {
            columns.append(fallbackColumn)
        }
        return columns.flatMap { column -> [KeyPathComparator<ProjectDirectoryRow>] in
            let ascending = history.first(where: { $0.column == column })?.ascending ?? column.defaultAscending
            let order: SortOrder = ascending ? .forward : .reverse
            switch column {
            case .status:
                return [
                    KeyPathComparator(\.statusSortValue, order: order),
                    KeyPathComparator(\.leaderSortValue, order: .forward),
                    KeyPathComparator(\.sortTitle, order: .forward)
                ]
            case .title:
                return [KeyPathComparator(\.sortTitle, order: order)]
            case .granted:
                return [
                    KeyPathComparator(\.visibleGrantedAmount, order: order),
                    KeyPathComparator(\.sortTitle, order: .forward)
                ]
            case .publications:
                return [
                    KeyPathComparator(\.publishedPublicationCount, order: order),
                    KeyPathComparator(\.sortTitle, order: .forward)
                ]
            case .leader:
                return [
                    KeyPathComparator(\.leaderSortValue, order: order),
                    KeyPathComparator(\.sortLeaderName, order: .forward),
                    KeyPathComparator(\.sortTitle, order: .forward)
                ]
            }
        }
    }

    private func projectListRowBackground(for row: ProjectDirectoryRow) -> some View {
        AppListRowBackground(
            isSelected: row.id == selectedProjectID,
            toneFill: projectStatusShadeColor(for: row)
        )
    }

    private func projectStatusShadeColor(for row: ProjectDirectoryRow) -> Color {
        if row.status == .completed {
            return AppPalette.shadeRed
        }
        if row.status == .ongoing && row.hasDataCollection {
            return AppPalette.shadeGreen
        }
        return AppPalette.shadeYellow
    }

    private func projectLeaderLabel(for row: ProjectDirectoryRow, language: AppLanguage) -> String {
        if row.isLedByCurrentUser {
            return language.text("You", "Du")
        }
        let leaderName = row.leaderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !leaderName.isEmpty {
            return leaderName
        }
        return "–"
    }

    private func projectGrantedLabel(for row: ProjectDirectoryRow) -> String {
        row.isLedByCurrentUser ? CurrencyFormatter.format(row.grantedAmount) : "–"
    }

}

struct ProjectDirectoryRow: Identifiable {
    let id: String
    let title: String
    let status: ProjectLifecycleStatus
    let applicationCount: Int
    let grantedAmount: Double
    let hasRemainingGrantedFunds: Bool
    let publishedPublicationCount: Int
    let leaderName: String
    let isLedByCurrentUser: Bool
    let hasDataCollection: Bool
    let hasActiveTasks: Bool
    let collaboratorNames: [String]
    let collaboratorFlags: [String]

    var sortTitle: String { title }
    var sortLeaderName: String { leaderName }
    var statusSortValue: Int { status == .completed ? 1 : 0 }
    var leaderSortValue: Int { isLedByCurrentUser ? 0 : 1 }
    var visibleGrantedAmount: Double { isLedByCurrentUser ? grantedAmount : -1 }
    var normalizedSearchBlob: String {
        normalizedSearchFilterText(([title, leaderName] + collaboratorNames).joined(separator: " "))
    }
}

struct ProjectCollaboratorFlagsView: View {
    let flags: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(flags, id: \.self) { flag in
                Text(flag)
                    .font(.system(size: 12))
            }
        }
    }
}
