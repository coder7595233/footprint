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
                // Round 16: it also keeps planned projects, so the label
                // says what it does: completed ones are hidden.
                return language.text("Not completed", "Ej avslutade")
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
    /// Round 16: a new or routed project that must be shown even if a filter
    /// would hide it; handled as soon as its row exists.
    @State private var pendingRevealProjectID: String?
    @State private var hasAppliedLaunchFilterPolicy = false

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

    /// The current filter choices, so a chip can ask "would this match
    /// anything?" with one setting changed.
    private struct ProjectFilterSettings {
        var searchQuery: SearchFilterQuery
        var researcherKey: String
        var ownOngoing: Bool
        var remainingFunds: Bool
        var activeTasks: Bool
        var completion: ProjectCompletionFilter
        var leader: ProjectLeaderFilter
    }

    private var currentProjectFilterSettings: ProjectFilterSettings {
        ProjectFilterSettings(
            searchQuery: SearchFilterQuery(raw: searchText),
            researcherKey: normalizedSearchFilterText(projectResearcherFilter),
            ownOngoing: showsOnlyOwnOngoingProjects,
            remainingFunds: showsOnlyProjectsWithRemainingFunds,
            activeTasks: showsOnlyProjectsWithActiveTasks,
            completion: projectCompletionFilter,
            leader: projectLeaderFilter
        )
    }

    private func projectMatchesLeader(_ row: ProjectDirectoryRow, _ leader: ProjectLeaderFilter) -> Bool {
        switch leader {
        case .all:
            return true
        case .you:
            return row.isLedByCurrentUser
        case .others:
            return !row.isLedByCurrentUser
        }
    }

    /// Round 16: the researcher menu matches like the search (case and
    /// accents ignored).
    private func projectMatchesResearcher(_ row: ProjectDirectoryRow, researcherKey: String) -> Bool {
        researcherKey.isEmpty || row.collaboratorNames.contains { normalizedSearchFilterText($0) == researcherKey }
    }

    private func projectMatches(_ row: ProjectDirectoryRow, _ settings: ProjectFilterSettings) -> Bool {
        projectMatchesLeader(row, settings.leader)
            && (settings.completion == .includeCompleted || row.status != .completed)
            && projectMatchesResearcher(row, researcherKey: settings.researcherKey)
            && (!settings.ownOngoing || row.isLedByCurrentUser && row.status == .ongoing)
            && (!settings.remainingFunds || row.hasRemainingGrantedFunds)
            && (!settings.activeTasks || row.hasActiveTasks)
            && (settings.searchQuery.isEmpty || settings.searchQuery.matches(normalizedHaystack: row.normalizedSearchBlob))
    }

    private var allProjectRows: [ProjectDirectoryRow] {
        projectSnapshots.map(projectRow(for:))
    }

    private var filteredProjects: [ProjectDirectoryRow] {
        let settings = currentProjectFilterSettings
        return allProjectRows
            .filter { projectMatches($0, settings) }
            .sorted(using: projectSortOrder(from: projectSortHistory))
    }

    /// Round 16: a chip that would leave the list empty is shown disabled
    /// (it stays usable while it is on, so it can be switched off).
    private func projectFilterHasMatches(in rows: [ProjectDirectoryRow], _ change: (inout ProjectFilterSettings) -> Void) -> Bool {
        var settings = currentProjectFilterSettings
        change(&settings)
        return rows.contains { projectMatches($0, settings) }
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
                applyLaunchFilterPolicyIfNeeded()
                if isActive {
                    refreshProjectSnapshots()
                    if let route = store.route, route.destination == .projects {
                        openRoutedProject(route.recordID)
                        store.consumeRoute()
                    } else if selectedProjectID == nil {
                        // Round 16: the remembered project only when the
                        // filters show it.
                        setSelectedProjectID(rememberedVisibleProjectID() ?? filteredProjects.first?.id)
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
                ensureSelectedProjectMatchesFilters()
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
                openRoutedProject(route.recordID)
                store.consumeRoute()
            }
            .onChange(of: selectedProjectID) { _, id in
                store.handlePendingSelectionReturnIfNeeded(for: id, in: .projects)
                store.rememberSelection(id: id, for: .projects)
            }
            .onChange(of: newRecordTrigger) { _, _ in
                guard isActive else { return }
                createNewProject()
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
                    ensureSelectedProjectMatchesFilters()
                }
                if let route = store.route, route.destination == .projects {
                    openRoutedProject(route.recordID)
                    store.consumeRoute()
                } else if selectedProjectID == nil {
                    setSelectedProjectID(rememberedVisibleProjectID() ?? filteredProjects.first?.id)
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
            } else if store.projects.isEmpty {
                AppWorkspaceEmptyStateView(
                    title: language.text("No projects yet", "Inga projekt ännu"),
                    subtitle: language.text("Add a project to track its totals and related applications.", "Lägg till ett projekt för att följa totaler och relaterade ansökningar."),
                    kind: .projects
                )
            } else if hasActiveProjectFilters && filteredProjects.isEmpty {
                // Round 16: projects exist but the filters hide them all.
                AppWorkspaceEmptyStateView(
                    title: language.text("No records match the filters", "Inga poster matchar filtren"),
                    subtitle: language.text("Try a broader search or clear the filters.", "Prova en bredare sökning eller rensa filtren."),
                    kind: .projects,
                    actionTitle: language.text("Clear filters", "Rensa filter"),
                    action: clearAllProjectFilters
                )
            } else {
                AppWorkspaceEmptyStateView(
                    title: language.text("No project selected", "Inget projekt valt"),
                    subtitle: language.text("Select a project in the list.", "Välj ett projekt i listan."),
                    kind: .projects
                )
            }
        }
        .onDeleteCommand {
            guard let selectedProjectID, let project = store.projects.first(where: { $0.id == selectedProjectID }) else { return }
            store.requestKeyboardDeletion(recordTitle: project.nameSv, isLocked: project.isEditingLocked) {
                store.deleteProject(id: project.id)
            }
        }
    }

    private func refreshProjectSnapshots() {
        projectSnapshots = store.projectRowSnapshots()
        validateResearcherFilter()
        revealPendingProjectIfPossible()
    }

    /// Round 16: the one way to add a project (menu command and button). The
    /// new project is selected with the lock armed, and only the filters that
    /// would hide it are cleared.
    private func createNewProject() {
        let newID = store.addProject()
        pendingRevealProjectID = newID
        refreshProjectSnapshots()
        setSelectedProjectID(newID, armLock: true)
    }

    /// Round 16: a routed project is shown even when the filters hide it, by
    /// clearing only the filters that hide it.
    private func openRoutedProject(_ projectID: String) {
        pendingRevealProjectID = projectID
        revealPendingProjectIfPossible()
        setSelectedProjectID(projectID, armLock: true)
    }

    private func revealPendingProjectIfPossible() {
        guard let pendingID = pendingRevealProjectID,
              let snapshot = projectSnapshots.first(where: { $0.id == pendingID }) else { return }
        pendingRevealProjectID = nil
        resetFiltersHiding(projectRow(for: snapshot))
    }

    private func resetFiltersHiding(_ row: ProjectDirectoryRow) {
        let settings = currentProjectFilterSettings
        if !settings.searchQuery.isEmpty && !settings.searchQuery.matches(normalizedHaystack: row.normalizedSearchBlob) {
            searchText = ""
        }
        if !projectMatchesResearcher(row, researcherKey: settings.researcherKey) {
            projectResearcherFilter = ""
        }
        if settings.ownOngoing && !(row.isLedByCurrentUser && row.status == .ongoing) {
            showsOnlyOwnOngoingProjects = false
        }
        if settings.remainingFunds && !row.hasRemainingGrantedFunds {
            showsOnlyProjectsWithRemainingFunds = false
        }
        if settings.activeTasks && !row.hasActiveTasks {
            showsOnlyProjectsWithActiveTasks = false
        }
        if settings.completion != .includeCompleted && row.status == .completed {
            projectCompletionFilter = .includeCompleted
        }
        if !projectMatchesLeader(row, settings.leader) {
            projectLeaderFilter = .all
        }
    }

    /// Round 16: a researcher saved earlier must exist in the menu, otherwise
    /// the filter would be on while the menu says "All researchers".
    private func validateResearcherFilter() {
        guard projectResearcherFilter.nonEmpty != nil else { return }
        // Not loaded yet: keep the saved choice until there are rows.
        guard !projectSnapshots.isEmpty else { return }
        let match = ListFilterTextMatch.matchingOption(for: projectResearcherFilter, in: projectResearcherOptions)
        if match != projectResearcherFilter {
            projectResearcherFilter = match ?? ""
        }
    }

    private func rememberedVisibleProjectID() -> String? {
        guard let rememberedID = store.lastSelectedRecordID(for: .projects),
              filteredProjects.contains(where: { $0.id == rememberedID }) else { return nil }
        return rememberedID
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
        let allRows = allProjectRows
        let rows = filteredProjects
        let orderedProjectIDs = rows.map(\.id)

        VStack(alignment: .leading, spacing: 12) {
            AppWorkspaceSidebarHeader(
                title: language.text("Projects", "Projekt"),
                actionTitle: language.text("New project", "Nytt projekt")
            ) {
                createNewProject()
            }

            projectFilters(language: language, allRows: allRows)

            if hasActiveProjectFilters {
                AppFilteredListBanner(
                    displayedCount: rows.count,
                    totalCount: projectSnapshots.count,
                    activeFilters: activeProjectFilterDescriptions(language: language),
                    restoredFromLastSession: RestoredListFilters.wasRestored(workspace: "Projects"),
                    language: language,
                    clearAction: clearAllProjectFilters
                )
            }

            projectsTable(rows: rows, language: language)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if !hasActiveProjectFilters {
                ListCountFootnote(
                    displayedCount: rows.count,
                    totalCount: projectSnapshots.count,
                    language: language
                )
            }
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
        .onChange(of: projectResearcherFilter) { _, _ in
            validateResearcherFilter()
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
        // Round 16: a project that was just created or opened keeps the
        // selection while it is locked (its filters are cleared separately).
        if let lockedID = projectSelectionCoordinator.lockedID,
           selectedProjectID == lockedID,
           store.projects.contains(where: { $0.id == lockedID }) {
            return
        }
        let ids = filteredProjects.map(\.id)
        if !ids.contains(selectedProjectID ?? "") {
            setSelectedProjectID(ids.first, resignFirstResponder: false)
        }
    }

    private func resetProjectFilters() {
        searchText = ""
        projectResearcherFilter = ""
        showsOnlyOwnOngoingProjects = false
        showsOnlyProjectsWithRemainingFunds = false
        showsOnlyProjectsWithActiveTasks = false
        projectCompletionFilter = .includeCompleted
        projectLeaderFilter = .all
    }

    /// Round 16: clears every filter of this list (banner, empty list).
    private func clearAllProjectFilters() {
        resetProjectFilters()
        RestoredListFilters.forget(workspace: "Projects")
    }

    private func clearProjectFiltersForDeactivationIfNeeded() {
        guard !store.shouldRetainListFilters(for: .projects) else { return }
        guard hasActiveProjectFilters else { return }
        clearAllProjectFilters()
    }

    /// Round 16: with "keep filters" off in Settings, filters saved by an
    /// earlier run are cleared when the list is first shown.
    private func applyLaunchFilterPolicyIfNeeded() {
        guard !hasAppliedLaunchFilterPolicy else { return }
        hasAppliedLaunchFilterPolicy = true
        guard !store.shouldRetainListFilters(for: .projects) else { return }
        clearAllProjectFilters()
    }

    private func activeProjectFilterDescriptions(language: AppLanguage) -> [String] {
        var descriptions: [String] = []
        if let search = searchText.nonEmpty {
            descriptions.append(language.text("Search “\(search)”", "Sökning ”\(search)”"))
        }
        if let researcher = projectResearcherFilter.nonEmpty {
            descriptions.append(language.text("Researcher \(researcher)", "Forskare \(researcher)"))
        }
        if showsOnlyOwnOngoingProjects {
            descriptions.append(language.text("Own ongoing", "Egna pågående"))
        }
        if showsOnlyProjectsWithRemainingFunds {
            descriptions.append(language.text("Remaining funds", "Kvarvarande medel"))
        }
        if showsOnlyProjectsWithActiveTasks {
            descriptions.append(language.text("Active tasks", "Aktiva uppgifter"))
        }
        if projectCompletionFilter != .includeCompleted {
            descriptions.append(projectCompletionFilter.title(language: language))
        }
        if projectLeaderFilter != .all {
            descriptions.append(projectLeaderFilter.title(language: language))
        }
        return descriptions
    }

    private func projectFilters(language: AppLanguage, allRows: [ProjectDirectoryRow]) -> some View {
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
                        isSelected: showsOnlyOwnOngoingProjects,
                        isEnabled: showsOnlyOwnOngoingProjects || projectFilterHasMatches(in: allRows) { $0.ownOngoing = true }
                    ) {
                        showsOnlyOwnOngoingProjects.toggle()
                    }
                    AppFilterChip(
                        label: language.text("Remaining funds", "Kvarvarande medel"),
                        isSelected: showsOnlyProjectsWithRemainingFunds,
                        isEnabled: showsOnlyProjectsWithRemainingFunds || projectFilterHasMatches(in: allRows) { $0.remainingFunds = true }
                    ) {
                        showsOnlyProjectsWithRemainingFunds.toggle()
                    }
                    AppFilterChip(
                        label: language.text("Active tasks", "Aktiva uppgifter"),
                        isSelected: showsOnlyProjectsWithActiveTasks,
                        isEnabled: showsOnlyProjectsWithActiveTasks || projectFilterHasMatches(in: allRows) { $0.activeTasks = true }
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
                            isSelected: projectCompletionFilter == filter,
                            isEnabled: projectCompletionFilter == filter || projectFilterHasMatches(in: allRows) { $0.completion = filter }
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
                            isSelected: projectLeaderFilter == filter,
                            isEnabled: projectLeaderFilter == filter || projectFilterHasMatches(in: allRows) { $0.leader = filter }
                        ) {
                            projectLeaderFilter = filter
                        }
                    }
                }
                // Round 16: "clear all" now lives in the filtered-list banner.
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
        row.isLedByCurrentUser ? CurrencyFormatter.format(row.grantedAmount, language: store.language) : AmountFormatter.missing
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
                    .font(appFont(.secondary))
            }
        }
    }
}
