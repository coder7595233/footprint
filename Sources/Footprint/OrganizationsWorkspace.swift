import AppKit
import SwiftUI
import UniformTypeIdentifiers


struct OrganizationsDirectoryView: View {
    private enum OrganizationListSortColumn: String, Hashable {
        case name
        case type
        case region
        case grantRate

        var defaultAscending: Bool {
            switch self {
            case .name, .type, .region:
                return true
            case .grantRate:
                return false
            }
        }
    }

    private struct OrganizationListSortCriterion: AppListSortCriterion {
        let column: OrganizationListSortColumn
        var ascending: Bool
    }

    let store: GrantDataStore
    let newRecordTrigger: Int
    let isActive: Bool
    @State private var selectedOrganizationID: String?
    @State private var pendingSelectionMeasurementID: String?
    @State private var pendingSelectionStartedAt: CFAbsoluteTime?
    @State private var organizationSelectionCoordinator = AppSelectionCoordinator<String>()
    @WorkspaceFilterState("Organizations.Filter.Search") private var organizationSearchText = ""
    @WorkspaceFilterState("Organizations.Filter.Categories") private var selectedCategoryFilters: Set<String> = []
    @WorkspaceFilterState("Organizations.Filter.Roles") private var selectedRoleFilters: Set<OrganizationRole> = []
    @WorkspaceFilterState("Organizations.Filter.LinkedOnly") private var onlyLinkedOrganizations = false
    @State private var organizationSortHistory = ListSortPersistence.load(
        defaultsKey: "OrganizationsListSort",
        defaultValue: [OrganizationListSortCriterion(column: .name, ascending: true)]
    )
    @State private var requestedSalaryCalculatorOrganizationID: String?
    @State private var filteredOrganizationRowsCache: [OrganizationDirectoryRow] = []
    @State private var organizationRowsRebuildTask: DispatchWorkItem?
    @State private var organizationRowsBuildGeneration = 0
    @State private var organizationRowsSignature = ""
    @State private var needsOrganizationRowsRefreshWhenActive = false

    private var organizationSelectionBinding: Binding<String?> {
        Binding(
            get: { selectedOrganizationID },
            set: { newValue in
                handleOrganizationSelectionCandidate(newValue)
            }
        )
    }

    private var categoryOptions: [String] {
        ["National", "Regional", "International"]
    }

    private var currentOrganizationRowsSignature: String {
        [
            String(store.organizationRowSnapshotGeneration),
            store.language.rawValue,
            "organizations",
            organizationSearchText,
            selectedCategoryFilters.sorted().joined(separator: "|"),
            selectedRoleFilters.map(\.rawValue).sorted().joined(separator: "|"),
            onlyLinkedOrganizations ? "linked" : "all",
            organizationSortHistory.map { "\(String(describing: $0.column)):\($0.ascending ? "1" : "0")" }.joined(separator: "|")
        ].joined(separator: "||")
    }

    private var hasActiveOrganizationFilters: Bool {
        organizationSearchText.nonEmpty != nil
            || !selectedCategoryFilters.isEmpty
            || !selectedRoleFilters.isEmpty
            || onlyLinkedOrganizations
    }

    private var workspaceDestination: AppRoute.Destination {
        .organizations
    }

    var body: some View {
        let language = store.language

        PersistentSplitView(layout: .organizations) {
            GeometryReader { geometry in
                let contentWidth = max(geometry.size.width - 28, 0)
                sidebarContent(language: language, contentWidth: contentWidth)
                    .frame(width: contentWidth, height: geometry.size.height, alignment: .topLeading)
                    .padding(14)
            }
            .background(AppPalette.sidebarPanelSurface)
            .onAppear {
                store.appendPerformanceDiagnostic(
                    String(
                        format: "organizations-view-onAppear mode=%@ active=%@",
                        "organizations",
                        isActive ? "yes" : "no"
                    )
                )
                if isActive {
                    rebuildOrganizationRows()
                    if let route = store.route,
                       route.destination == workspaceDestination {
                        setSelectedOrganizationID(route.recordID, armLock: true)
                        store.consumeRoute()
                    } else if selectedOrganizationID == nil {
                        setSelectedOrganizationID(
                            store.lastSelectedRecordID(for: workspaceDestination)
                                ?? filteredOrganizationRowsCache.first?.id
                        )
                    }
                } else {
                    needsOrganizationRowsRefreshWhenActive = true
                }
            }
            .onChange(of: store.organizationRowSnapshotGeneration) { _, _ in
                guard isActive else {
                    needsOrganizationRowsRefreshWhenActive = true
                    return
                }
                rebuildOrganizationRows()
                let ids = store.organizationRowSnapshots().map(\.id)
                if !ids.contains(selectedOrganizationID ?? "") {
                    setSelectedOrganizationID(
                        store.lastSelectedRecordID(for: workspaceDestination)
                            ?? filteredOrganizationRowsCache.first?.id
                    )
                }
            }
            .onChange(of: store.language) { _, _ in
                rebuildOrganizationRowsIfActive()
            }
            .onChange(of: organizationSearchText) { _, _ in
                rebuildOrganizationRowsIfActive()
            }
            .onChange(of: selectedCategoryFilters) { _, _ in
                rebuildOrganizationRowsIfActive()
            }
            .onChange(of: selectedRoleFilters) { _, _ in
                rebuildOrganizationRowsIfActive()
            }
            .onChange(of: onlyLinkedOrganizations) { _, _ in
                rebuildOrganizationRowsIfActive()
            }
            .onChange(of: organizationSortHistory) { _, _ in
                rebuildOrganizationRowsIfActive()
            }
            .onChange(of: store.route) { _, route in
                guard let route, route.destination == workspaceDestination else { return }
                guard isActive else {
                    store.appendPerformanceDiagnostic(
                        String(
                            format: "organization-route-deferred mode=%@ id=%@",
                            "organizations",
                            route.recordID
                        )
                    )
                    return
                }
                setSelectedOrganizationID(route.recordID, armLock: true)
                store.consumeRoute()
            }
            .onChange(of: selectedOrganizationID) { _, id in
                store.handlePendingSelectionReturnIfNeeded(for: id, in: workspaceDestination)
                store.rememberSelection(id: id, for: workspaceDestination)
                pendingSelectionMeasurementID = id
                pendingSelectionStartedAt = CFAbsoluteTimeGetCurrent()
                store.appendPerformanceDiagnostic(
                    String(
                        format: "organization-selection-start id=%@",
                        id ?? "-"
                    )
                )
            }
            .onChange(of: newRecordTrigger) { _, _ in
                guard isActive else { return }
                setSelectedOrganizationID(store.addOrganization(), armLock: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .footprintOpenSalaryCalculator)) { notification in
                guard isActive else { return }
                guard let organizationID = notification.object as? String else { return }
                setSelectedOrganizationID(organizationID, armLock: true)
                requestedSalaryCalculatorOrganizationID = organizationID
            }
            .onChange(of: isActive) { _, active in
                store.appendPerformanceDiagnostic(
                    String(
                        format: "organizations-active-changed mode=%@ active=%@ pending_rows=%@",
                        "organizations",
                        active ? "yes" : "no",
                        needsOrganizationRowsRefreshWhenActive ? "yes" : "no"
                    )
                )
                guard active else {
                    organizationRowsRebuildTask?.cancel()
                    clearOrganizationFiltersForDeactivationIfNeeded()
                    return
                }
                if needsOrganizationRowsRefreshWhenActive {
                    rebuildOrganizationRows()
                    needsOrganizationRowsRefreshWhenActive = false
                }
                if let route = store.route, route.destination == workspaceDestination {
                    setSelectedOrganizationID(route.recordID, armLock: true)
                    store.consumeRoute()
                } else if selectedOrganizationID == nil {
                    setSelectedOrganizationID(
                        store.lastSelectedRecordID(for: workspaceDestination)
                            ?? filteredOrganizationRowsCache.first?.id
                    )
                }
            }
        } detail: {
            if let organization = store.organization(id: selectedOrganizationID) {
                LocalizedOptionDetailView(
                    store: store,
                    title: organization.displayName(for: language),
                    option: organization,
                    applications: store.applications(forOrganization: organization),
                    managedApplications: store.managedApplications(forOrganization: organization),
                    openAction: { store.openRoute(for: $0) },
                    autosaveAction: { id, nameSv, nameEn, addressLine, postalCode, city, country, category, roles, note, websiteURL, phoneNumber, organizationNumber, vatNumber, employerContacts, flag, membershipFrom, membershipTo, congresses, projectTasks, salaryCalculator in
                        store.autosaveOrganization(
                            id: id,
                            nameSv: nameSv,
                            nameEn: nameEn,
                            addressLine: addressLine,
                            postalCode: postalCode,
                            city: city,
                            country: country,
                            category: category,
                            roles: roles,
                            note: note,
                            websiteURL: websiteURL,
                            phoneNumber: phoneNumber,
                            organizationNumber: organizationNumber,
                            vatNumber: vatNumber,
                            employerContacts: employerContacts,
                            flag: flag,
                            membershipFrom: membershipFrom,
                            membershipTo: membershipTo,
                            congresses: congresses,
                            projectTasks: projectTasks,
                            salaryCalculator: salaryCalculator
                        )
                    },
                    finalizeAction: {
                        store.finalizePendingOrganizationSelection(id: $0)
                        store.finalizePendingManagerSelection(id: $0)
                    },
                    deleteAction: { store.deleteOrganization(id: $0) },
                    requestedSalaryCalculatorOrganizationID: requestedSalaryCalculatorOrganizationID,
                    onSalaryRequestHandled: { requestedSalaryCalculatorOrganizationID = nil },
                    language: language,
                    isActive: isActive
                )
                .id(organization.id)
                .undoRevealPulse(
                    triggerID: store.undoRevealRequest?.id,
                    isActive: store.undoRevealRequest?.target.matchesWholeRecord(routeDestination: workspaceDestination, recordID: organization.id) == true
                )
                .performanceScopeProbe(store: store, scope: "organizations-detail", identifier: organization.id)
                .background(
                    PerformanceReadyReporter {
                        guard pendingSelectionMeasurementID == organization.id,
                              let pendingSelectionStartedAt else { return }
                        let duration = (CFAbsoluteTimeGetCurrent() - pendingSelectionStartedAt) * 1000
                        store.appendPerformanceDiagnostic(
                            String(
                                format: "organization-selection-ready organization=%@ ready_ms=%.2f",
                                organization.nameSv,
                                duration
                            )
                        )
                        releaseOrganizationSelectionLock(for: organization.id)
                        self.pendingSelectionMeasurementID = nil
                        self.pendingSelectionStartedAt = nil
                    }
                )
            } else {
                AppWorkspaceEmptyStateView(
                    title: language.text("No organizations yet", "Inga organisationer ännu"),
                    subtitle: language.text("Add an organization to use it in applications.", "Lägg till en organisation för att kunna använda den i ansökningar."),
                    kind: .organizations
                )
            }
        }
        .onDeleteCommand {
            guard let selectedOrganizationID, let organization = store.organizations.first(where: { $0.id == selectedOrganizationID }) else { return }
            store.deleteOrganization(id: organization.id)
        }
    }

    private func rebuildOrganizationRowsIfActive() {
        guard isActive else {
            needsOrganizationRowsRefreshWhenActive = true
            return
        }
        rebuildOrganizationRows()
    }

    @ViewBuilder
    private func sidebarContent(language: AppLanguage, contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text(language.text("Organizations", "Organisationer"))
                    .appTypography(.pageTitle)
                Spacer(minLength: 0)
                newOrganizationButton(language: language)
            }

            AppFilterCard {
                VStack(alignment: .leading, spacing: 8) {
                    AppFilterRow(
                        showsClearButton: organizationSearchText.nonEmpty != nil,
                        clearAction: { organizationSearchText = "" }
                    ) {
                        AppSidebarSearchField(
                            placeholder: language.text("Search organizations", "Sök organisationer"),
                            text: $organizationSearchText
                        )
                    }

                    AppFilterRow(
                        showsClearButton: !selectedCategoryFilters.isEmpty,
                        clearAction: { selectedCategoryFilters.removeAll() }
                    ) {
                        ForEach(categoryOptions, id: \.self) { category in
                            organizationFilterPill(
                                title: organizationCategoryFilterLabel(category, language: language),
                                isSelected: selectedCategoryFilters.contains(category),
                                isEnabled: isOrganizationCategoryFilterAvailable(category)
                            ) {
                                toggleCategoryFilter(category)
                            }
                        }
                    }

                    AppFilterRow(
                        showsClearButton: !selectedRoleFilters.isDisjoint(with: firstOrganizationRoleFilterRow),
                        clearAction: {
                            for role in firstOrganizationRoleFilterRow {
                                selectedRoleFilters.remove(role)
                            }
                        }
                    ) {
                        ForEach(firstOrganizationRoleFilterRow, id: \.self) { role in
                            organizationFilterPill(
                                title: localizedOrganizationRole(role, language: language),
                                symbolName: organizationRoleSymbolName(role),
                                isSelected: selectedRoleFilters.contains(role),
                                isEnabled: isOrganizationRoleFilterAvailable(role)
                            ) {
                                toggleRoleFilter(role)
                            }
                        }
                    }

                    AppFilterRow(
                        showsClearButton: !selectedRoleFilters.isDisjoint(with: secondOrganizationRoleFilterRow),
                        clearAction: {
                            for role in secondOrganizationRoleFilterRow {
                                selectedRoleFilters.remove(role)
                            }
                        }
                    ) {
                        ForEach(secondOrganizationRoleFilterRow, id: \.self) { role in
                            organizationFilterPill(
                                title: localizedOrganizationRole(role, language: language),
                                symbolName: organizationRoleSymbolName(role),
                                isSelected: selectedRoleFilters.contains(role),
                                isEnabled: isOrganizationRoleFilterAvailable(role)
                            ) {
                                toggleRoleFilter(role)
                            }
                        }
                    }

                    AppFilterRow(
                        showsClearButton: onlyLinkedOrganizations,
                        clearAction: { onlyLinkedOrganizations = false }
                    ) {
                        organizationFilterPill(
                            title: language.text("Linked records only", "Med kopplingar"),
                            isSelected: onlyLinkedOrganizations,
                            isEnabled: isOnlyLinkedOrganizationsFilterAvailable()
                        ) {
                            onlyLinkedOrganizations.toggle()
                        }
                        .help(
                            language.text(
                                "Shows only organizations that are linked elsewhere in the app, such as grant providers or fund managers, teaching institutions, researcher affiliations/employment/education, or congress organizations.",
                                "Visar bara organisationer som är kopplade någon annanstans i appen, till exempel som anslagsgivare eller medelsförvaltare, undervisningsinstitution, forskaraffiliering/anställning/utbildning eller kongressorganisation."
                            )
                        )
                    }

                    AppFilterClearAllRow(isVisible: hasActiveOrganizationFilters) {
                        clearOrganizationFilters()
                    }
                }
            }

            organizationList(rows: filteredOrganizationRowsCache, language: language, contentWidth: contentWidth)
                .frame(maxHeight: .infinity, alignment: .topLeading)

            ListCountFootnote(
                displayedCount: filteredOrganizationRowsCache.count,
                totalCount: store.organizations.count,
                language: language
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func newOrganizationButton(language: AppLanguage) -> some View {
        Button(language.text("New organization", "Ny organisation")) {
            setSelectedOrganizationID(store.addOrganization(), armLock: true)
        }
        .appAddButtonStyle()
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func organizationFilterPill(
        title: String,
        symbolName: String? = nil,
        isSelected: Bool,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        AppFilterChip(
            label: title,
            systemImage: symbolName,
            isSelected: isSelected,
            isEnabled: isEnabled || isSelected,
            action: action
        )
    }

    private func organizationCategoryFilterLabel(_ category: String, language: AppLanguage) -> String {
        if category == "International", language == .swedish {
            return "Internationell"
        }
        return language.localizedGrantCategory(category)
    }

    private func isOrganizationCategoryFilterAvailable(_ category: String) -> Bool {
        organizationFilterHasMatches(
            selectedCategoryFilters: [category],
            selectedRoleFilters: selectedRoleFilters,
            onlyLinkedOrganizations: onlyLinkedOrganizations
        )
    }

    private func isOrganizationRoleFilterAvailable(_ role: OrganizationRole) -> Bool {
        organizationFilterHasMatches(
            selectedCategoryFilters: selectedCategoryFilters,
            selectedRoleFilters: [role],
            onlyLinkedOrganizations: onlyLinkedOrganizations
        )
    }

    private func isOnlyLinkedOrganizationsFilterAvailable() -> Bool {
        organizationFilterHasMatches(
            selectedCategoryFilters: selectedCategoryFilters,
            selectedRoleFilters: selectedRoleFilters,
            onlyLinkedOrganizations: true
        )
    }

    private func organizationFilterHasMatches(
        selectedCategoryFilters: Set<String>,
        selectedRoleFilters: Set<OrganizationRole>,
        onlyLinkedOrganizations: Bool
    ) -> Bool {
        Self.organizationFilterHasMatches(
            in: store.organizationRowSnapshots(),
            searchText: organizationSearchText,
            selectedCategoryFilters: selectedCategoryFilters,
            selectedRoleFilters: selectedRoleFilters,
            onlyLinkedOrganizations: onlyLinkedOrganizations,
            language: store.language
        )
    }

    private var firstOrganizationRoleFilterRow: [OrganizationRole] {
        [.grantProvider, .fundManager, .employer]
    }

    private var secondOrganizationRoleFilterRow: [OrganizationRole] {
        [.institution, .association, .company]
    }

    @ViewBuilder
    private func organizationList(rows: [OrganizationDirectoryRow], language: AppLanguage, contentWidth: CGFloat) -> some View {
        let nameWidth: CGFloat = 240
        let typeWidth: CGFloat = 100
        let regionWidth: CGFloat = 64
        let grantWidth: CGFloat = 108
        let tableContentWidth: CGFloat = nameWidth + typeWidth + regionWidth + grantWidth + 20
        let orderedIDs = rows.map(\.id)
        let reminderCounts = calendarTaskReminderBadgeCounts(entries: store.calendarTaskReminderBadgeEntries)

        AppListTable(contentWidth: tableContentWidth) {
            HStack(spacing: 0) {
                organizationListHeader(language.text("Name", "Namn"), width: nameWidth, column: .name)
                organizationListHeader(language.text("Type", "Typ"), width: typeWidth, column: .type)
                organizationListHeader(language.text("Region", "Region"), width: regionWidth, column: .region)
                organizationListHeader(language.text("Grant rate", "Beviljandegrad"), width: grantWidth, column: .grantRate)
            }
        } rows: {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    let reminderCount = reminderCounts.organizationCounts[row.id] ?? 0
                    let reminderHelp = calendarTaskReminderBadgeHelp(entries: reminderCounts.entries, language: language) {
                        $0.badgeTargets.contains(.organization(row.id))
                    }
                    AppListRowButton(
                        width: tableContentWidth,
                        action: { handleOrganizationSelectionCandidate(row.id) },
                        background: { organizationListRowBackground(for: row) }
                    ) {
                        HStack(spacing: 0) {
                            Text(row.displayName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.trailing, reminderCount > 0 ? 34 : 0)
                                .frame(width: nameWidth, alignment: .leading)
                                .appReminderListBadge(reminderCount, help: reminderHelp)
                            HStack(spacing: 6) {
                                ForEach(row.icons, id: \.self) { icon in
                                    Image(systemName: icon)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(width: typeWidth, alignment: .leading)
                            organizationListCell(row.flag.isEmpty ? "—" : row.flag, width: regionWidth)
                            organizationListCell(row.isGrantProvider ? row.grantRateText : "–", width: grantWidth)
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
            destination: workspaceDestination,
            isEnabled: isActive,
            orderedIDs: orderedIDs,
            selectedID: selectedOrganizationID,
            onSelect: handleOrganizationSelectionCandidate
        )
    }

    private func handleOrganizationSelectionCandidate(_ newValue: String?) {
        guard organizationSelectionCoordinator.accepts(candidate: newValue) else { return }
        setSelectedOrganizationID(newValue, armLock: newValue != nil)
    }

    private func setSelectedOrganizationID(_ newValue: String?, armLock: Bool = false) {
        guard selectedOrganizationID != newValue else {
            if armLock, let newValue {
                armOrganizationSelectionLock(for: newValue)
            }
            return
        }
        NSApp.keyWindow?.makeFirstResponder(nil)
        let previousID = selectedOrganizationID
        selectedOrganizationID = newValue
        if armLock, let newValue {
            organizationSelectionCoordinator.arm(newValue, previousID: previousID)
        } else if newValue == nil {
            organizationSelectionCoordinator.clear()
        }
    }

    private func armOrganizationSelectionLock(for id: String) {
        organizationSelectionCoordinator.arm(
            id,
            previousID: organizationSelectionCoordinator.previousID
        )
    }

    private func releaseOrganizationSelectionLock(for id: String) {
        organizationSelectionCoordinator.release(ifMatching: id)
    }

    private func organizationListHeader(_ title: String, width: CGFloat, column: OrganizationListSortColumn) -> some View {
        let criterion = organizationSortHistory.first(where: { $0.column == column })
        let sortIndex = organizationSortHistory.firstIndex(where: { $0.column == column })
        return AppSortableListHeader(
            title: title,
            ascending: criterion?.ascending,
            sortIndex: sortIndex,
            width: width,
            resetTitle: store.language.text("Reset", "Återställ"),
            onToggle: { toggleOrganizationSort(column) },
            onReset: resetOrganizationSort
        )
    }

    private func toggleOrganizationSort(_ column: OrganizationListSortColumn) {
        if let existingIndex = organizationSortHistory.firstIndex(where: { $0.column == column }) {
            if existingIndex == 0 {
                organizationSortHistory[0].ascending.toggle()
            } else {
                let criterion = organizationSortHistory.remove(at: existingIndex)
                organizationSortHistory.insert(criterion, at: 0)
            }
        } else {
            organizationSortHistory.insert(OrganizationListSortCriterion(column: column, ascending: column.defaultAscending), at: 0)
        }
        ListSortPersistence.save(organizationSortHistory, defaultsKey: "OrganizationsListSort")
    }

    private func resetOrganizationSort() {
        organizationSortHistory = [
            OrganizationListSortCriterion(column: .name, ascending: true)
        ]
        ListSortPersistence.save(organizationSortHistory, defaultsKey: "OrganizationsListSort")
    }

    private func organizationListCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: .leading)
    }

    private func organizationListRowBackground(for row: OrganizationDirectoryRow) -> some View {
        Group {
            if row.id == selectedOrganizationID {
                SelectedListRowBackground()
            } else {
                Color.clear
            }
        }
    }

    private func rebuildOrganizationRows() {
        let signature = currentOrganizationRowsSignature
        guard signature != organizationRowsSignature || filteredOrganizationRowsCache.isEmpty else {
            return
        }

        organizationRowsRebuildTask?.cancel()
        organizationRowsBuildGeneration &+= 1
        let generation = organizationRowsBuildGeneration
        let startedAt = CFAbsoluteTimeGetCurrent()
        let snapshots = store.organizationRowSnapshots()
        let searchText = organizationSearchText
        let selectedCategoryFilters = selectedCategoryFilters
        let selectedRoleFilters = selectedRoleFilters
        let onlyLinkedOrganizations = onlyLinkedOrganizations
        let sortHistory = organizationSortHistory
        let language = store.language
        let store = store

        let task = Self.makeOrganizationRowsRebuildTask(
            snapshots: snapshots,
            searchText: searchText,
            selectedCategoryFilters: selectedCategoryFilters,
            selectedRoleFilters: selectedRoleFilters,
            onlyLinkedOrganizations: onlyLinkedOrganizations,
            sortHistory: sortHistory,
            language: language
        ) { rows in
            guard generation == organizationRowsBuildGeneration else { return }
            filteredOrganizationRowsCache = rows
            organizationRowsSignature = signature
            store.appendPerformanceDiagnostic(
                String(
                    format: "organizations-list-rebuild mode=%@ rows=%ld source_rows=%ld ms=%.2f",
                    "organizations",
                    rows.count,
                    snapshots.count,
                    (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
                )
            )
        }
        organizationRowsRebuildTask = task
        DispatchQueue.global(qos: .userInitiated).async(execute: task)
    }

    nonisolated private static func makeOrganizationRowsRebuildTask(
        snapshots: [OrganizationRowSnapshot],
        searchText: String,
        selectedCategoryFilters: Set<String>,
        selectedRoleFilters: Set<OrganizationRole>,
        onlyLinkedOrganizations: Bool,
        sortHistory: [OrganizationListSortCriterion],
        language: AppLanguage,
        completion: @escaping @MainActor ([OrganizationDirectoryRow]) -> Void
    ) -> DispatchWorkItem {
        DispatchWorkItem {
            let rows = Self.organizationRows(
                from: snapshots,
                searchText: searchText,
                selectedCategoryFilters: selectedCategoryFilters,
                selectedRoleFilters: selectedRoleFilters,
                onlyLinkedOrganizations: onlyLinkedOrganizations,
                sortHistory: sortHistory,
                language: language
            )
            DispatchQueue.main.async {
                completion(rows)
            }
        }
    }

    nonisolated private static func organizationRows(
        from snapshots: [OrganizationRowSnapshot],
        searchText: String,
        selectedCategoryFilters: Set<String>,
        selectedRoleFilters: Set<OrganizationRole>,
        onlyLinkedOrganizations: Bool,
        sortHistory: [OrganizationListSortCriterion],
        language: AppLanguage
    ) -> [OrganizationDirectoryRow] {
        snapshots
            .filter { matchesOrganizationSearch($0, searchText: searchText, language: language) }
            .filter { selectedCategoryFilters.isEmpty || selectedCategoryFilters.contains($0.category) }
            .filter { selectedRoleFilters.isEmpty || !Set($0.roles).isDisjoint(with: selectedRoleFilters) }
            .filter { !onlyLinkedOrganizations || $0.hasLinkedRecords }
            .map(organizationRow(for:))
            .sorted(using: organizationSortOrder(from: sortHistory))
    }

    nonisolated private static func organizationFilterHasMatches(
        in snapshots: [OrganizationRowSnapshot],
        searchText: String,
        selectedCategoryFilters: Set<String>,
        selectedRoleFilters: Set<OrganizationRole>,
        onlyLinkedOrganizations: Bool,
        language: AppLanguage
    ) -> Bool {
        snapshots.contains { row in
            matchesOrganizationSearch(row, searchText: searchText, language: language)
                && (selectedCategoryFilters.isEmpty || selectedCategoryFilters.contains(row.category))
                && (selectedRoleFilters.isEmpty || !Set(row.roles).isDisjoint(with: selectedRoleFilters))
                && (!onlyLinkedOrganizations || row.hasLinkedRecords)
        }
    }

    nonisolated private static func organizationRow(for snapshot: OrganizationRowSnapshot) -> OrganizationDirectoryRow {
        OrganizationDirectoryRow(
            id: snapshot.id,
            displayName: snapshot.displayName,
            flag: snapshot.flag,
            icons: snapshot.icons,
            category: snapshot.category,
            roles: snapshot.roles,
            roleSummary: snapshot.roleSummary,
            applicationCount: snapshot.applicationCount,
            waitingCount: snapshot.waitingCount,
            grantedCount: snapshot.grantedCount,
            rejectedCount: snapshot.rejectedCount,
            hasLinkedRecords: snapshot.hasLinkedRecords,
            isGrantProvider: snapshot.isGrantProvider,
            isStewardshipOrganization: snapshot.isStewardshipOrganization,
            isManagerOrganization: snapshot.isManagerOrganization
        )
    }

    nonisolated private static func matchesOrganizationSearch(_ row: OrganizationRowSnapshot, searchText: String, language: AppLanguage) -> Bool {
        let searchQuery = SearchFilterQuery(raw: searchText)
        guard !searchQuery.isEmpty else { return true }
        let haystack = [
            row.displayName,
            row.sortName,
            row.category.isEmpty ? "" : language.localizedGrantCategory(row.category),
            row.roleSummary
        ]
        .joined(separator: " ")
        return searchQuery.matches(haystack: haystack)
    }

    nonisolated private static func organizationSortOrder(
        from sortHistory: [OrganizationListSortCriterion]
    ) -> [KeyPathComparator<OrganizationDirectoryRow>] {
        var columns = sortHistory.map(\.column)
        for fallbackColumn in [OrganizationListSortColumn.name] where !columns.contains(fallbackColumn) {
            columns.append(fallbackColumn)
        }
        return columns.flatMap { column -> [KeyPathComparator<OrganizationDirectoryRow>] in
            let ascending = sortHistory.first(where: { $0.column == column })?.ascending ?? column.defaultAscending
            let order: SortOrder = ascending ? .forward : .reverse
            switch column {
            case .name:
                return [KeyPathComparator(\.sortName, order: order)]
            case .type:
                return [
                    KeyPathComparator(\.roleSummary, order: order),
                    KeyPathComparator(\.sortName, order: .forward)
                ]
            case .region:
                return [
                    KeyPathComparator(\.flag, order: order),
                    KeyPathComparator(\.sortName, order: .forward)
                ]
            case .grantRate:
                return [
                    KeyPathComparator(\.grantRateSortValue, order: order),
                    KeyPathComparator(\.sortName, order: .forward)
                ]
            }
        }
    }

    private func toggleCategoryFilter(_ category: String) {
        if selectedCategoryFilters.contains(category) {
            selectedCategoryFilters.remove(category)
        } else {
            selectedCategoryFilters.insert(category)
        }
    }

    private func toggleRoleFilter(_ role: OrganizationRole) {
        if selectedRoleFilters.contains(role) {
            selectedRoleFilters.remove(role)
        } else {
            selectedRoleFilters.insert(role)
        }
    }

    private func clearOrganizationFilters() {
        organizationSearchText = ""
        selectedCategoryFilters.removeAll()
        selectedRoleFilters.removeAll()
        onlyLinkedOrganizations = false
    }

    private func clearOrganizationFiltersForDeactivationIfNeeded() {
        guard !store.shouldRetainListFilters(for: .organizations) else { return }
        guard hasActiveOrganizationFilters else { return }
        clearOrganizationFilters()
        needsOrganizationRowsRefreshWhenActive = true
    }

    private func organizationRoleSymbolName(_ role: OrganizationRole) -> String {
        switch role {
        case .grantProvider:
            return "banknote.fill"
        case .fundManager, .employer:
            return "briefcase.fill"
        case .institution:
            return "graduationcap.fill"
        case .association:
            return "person.3.fill"
        case .company:
            return "building.2.fill"
        }
    }
}

private struct SalaryCalculationCacheSignature: Equatable {
    let subjectID: String
    let calculator: ManagerSalaryCalculator
}

private struct ResolvedSalaryCalculationPeriod {
    let start: Date
    let end: Date
    let value: Double
}

private struct SalaryCalculationContext {
    let signature: SalaryCalculationCacheSignature
    let years: [Int]
    let monthlySalaryPeriods: [ResolvedSalaryCalculationPeriod]
    let employerFeePeriods: [ResolvedSalaryCalculationPeriod]
    let regionalCostPeriods: [ResolvedSalaryCalculationPeriod]
    let overheadPeriods: [ResolvedSalaryCalculationPeriod]
    let annualIncreaseRate: Double
    let allocationFraction: Double
    let allocationMonths: Double
    let birthDate: Date?
}

func salaryCalculationHasKnownAge(_ calculator: ManagerSalaryCalculator) -> Bool {
    DateParsers.isoDay.date(from: calculator.birthDate) != nil
}

private func makeSalaryCalculationContext(subjectID: String, calculator: ManagerSalaryCalculator) -> SalaryCalculationContext {
    let currentYear = Calendar.current.component(.year, from: Date())
    let allPeriods = calculator.monthlySalaryPeriods
        + calculator.employerFeePeriods
        + calculator.regionalCostPeriods
        + calculator.overheadPeriods
    let earliestYear = allPeriods
        .compactMap { DateParsers.isoDay.date(from: normalizedSalaryCalculationDateInput($0.from)) }
        .map { Calendar.current.component(.year, from: $0) }
        .min() ?? currentYear

    return SalaryCalculationContext(
        signature: SalaryCalculationCacheSignature(subjectID: subjectID, calculator: calculator),
        years: Array(min(earliestYear, currentYear)...(currentYear + 5)),
        monthlySalaryPeriods: calculator.monthlySalaryPeriods.compactMap(resolvedSalaryCalculationPeriod(from:)).sorted { $0.start < $1.start },
        employerFeePeriods: calculator.employerFeePeriods.compactMap(resolvedSalaryCalculationPeriod(from:)).sorted { $0.start < $1.start },
        regionalCostPeriods: calculator.regionalCostPeriods.compactMap(resolvedSalaryCalculationPeriod(from:)).sorted { $0.start < $1.start },
        overheadPeriods: calculator.overheadPeriods.compactMap(resolvedSalaryCalculationPeriod(from:)).sorted { $0.start < $1.start },
        annualIncreaseRate: max(
            0,
            (GrantParsing.numericValue(from: calculator.annualIncreaseAfterCurrentYearPercent) ?? 3) / 100
        ),
        allocationFraction: max(0, min(1, (GrantParsing.numericValue(from: calculator.allocationPercent) ?? 0) / 100)),
        allocationMonths: max(0, GrantParsing.numericValue(from: calculator.allocationMonths) ?? 0),
        birthDate: DateParsers.isoDay.date(from: calculator.birthDate)
    )
}

private func calculateSalaryRows(using context: SalaryCalculationContext) -> [SalaryCalculationRow] {
    guard context.birthDate != nil else { return [] }
    return context.years.map { calculateSalaryRow(for: $0, using: context) }
}

private func calculateSalaryRow(for year: Int, using context: SalaryCalculationContext) -> SalaryCalculationRow {
    let vacationDays = salaryVacationDays(for: year, birthDate: context.birthDate, calculator: context.signature.calculator)
    var annualTotal = 0.0

    for month in 1...12 {
        guard let monthDate = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) else { continue }
        let monthlySalary = resolvedSalaryCalculationValue(
            on: monthDate,
            from: context.monthlySalaryPeriods,
            annualIncreaseRate: context.annualIncreaseRate,
            growFutureValues: true
        )
        let employerRate = resolvedSalaryCalculationValue(
            on: monthDate,
            from: context.employerFeePeriods,
            annualIncreaseRate: context.annualIncreaseRate,
            growFutureValues: false
        ) / 100
        let regionalRate = resolvedSalaryCalculationValue(
            on: monthDate,
            from: context.regionalCostPeriods,
            annualIncreaseRate: context.annualIncreaseRate,
            growFutureValues: false
        ) / 100
        let overheadRate = resolvedSalaryCalculationValue(
            on: monthDate,
            from: context.overheadPeriods,
            annualIncreaseRate: context.annualIncreaseRate,
            growFutureValues: false
        ) / 100

        let vacationSupplement = monthlySalary * context.signature.calculator.vacationSupplementRatePerDay * Double(vacationDays) / 12
        let salaryWithVacation = monthlySalary + vacationSupplement
        let salaryWithSocialCosts = salaryWithVacation * (1 + employerRate + regionalRate)
        annualTotal += salaryWithSocialCosts * (1 + overheadRate)
    }

    let annualSelectedCost = annualTotal * context.allocationFraction
    let totalSelectedCost = annualSelectedCost * (context.allocationMonths / 12)

    return SalaryCalculationRow(
        year: year,
        vacationDays: vacationDays,
        totalAnnualCost: annualTotal,
        annualSelectedCost: annualSelectedCost,
        totalSelectedCost: totalSelectedCost
    )
}

private func salaryVacationDays(for year: Int, birthDate: Date?, calculator: ManagerSalaryCalculator) -> Int {
    guard let birthDate,
          let yearEnd = Calendar.current.date(from: DateComponents(year: year, month: 12, day: 31)) else {
        return calculator.vacationDays(atAge: nil)
    }
    let age = Calendar.current.dateComponents([.year], from: birthDate, to: yearEnd).year ?? 0
    return calculator.vacationDays(atAge: age)
}

private func resolvedSalaryCalculationValue(
    on date: Date,
    from periods: [ResolvedSalaryCalculationPeriod],
    annualIncreaseRate: Double,
    growFutureValues: Bool
) -> Double {
    guard !periods.isEmpty else { return 0 }

    if let exact = periods.first(where: { $0.start <= date && date <= $0.end }) {
        return exact.value
    }

    if let latestPast = periods.filter({ $0.end < date }).max(by: { $0.end < $1.end }) {
        guard growFutureValues,
              let lastDefinedYear = Calendar.current.dateComponents([.year], from: latestPast.end).year,
              let currentYear = Calendar.current.dateComponents([.year], from: date).year,
              currentYear > lastDefinedYear else {
            return latestPast.value
        }
        return latestPast.value * pow(1 + annualIncreaseRate, Double(currentYear - lastDefinedYear))
    }

    return periods.first?.value ?? 0
}

private func resolvedSalaryCalculationPeriod(from period: SalaryCalculatorPeriod) -> ResolvedSalaryCalculationPeriod? {
    guard let value = GrantParsing.numericValue(from: period.value),
          let from = DateParsers.isoDay.date(from: period.from),
          let to = DateParsers.isoDay.date(from: period.to) else {
        return nil
    }
    let start = min(from, to)
    let end = max(from, to)
    return ResolvedSalaryCalculationPeriod(start: start, end: end, value: value)
}

private func normalizedSalaryCalculationDateInput(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let digits = trimmed.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
    if digits.count == 8 {
        let year = String(digits.prefix(4))
        let month = String(digits.dropFirst(4).prefix(2))
        let day = String(digits.suffix(2))
        return "\(year)-\(month)-\(day)"
    }
    return trimmed
}

func organizationTimelineExpandedByDefault(for roles: Set<OrganizationRole>) -> Bool {
    !roles.contains(.employer)
}

private struct LocalizedOptionDetailView: View {
    @ObservedObject var store: GrantDataStore
    let title: String
    let option: OrganizationRecord
    let applications: [GrantApplication]
    let managedApplications: [GrantApplication]
    let openAction: (GrantApplication) -> Void
    let autosaveAction: (String, String, String, String, String, String, String, String?, [OrganizationRole], String?, String, String, String, String, [OrganizationEmployerContact], String, String, String, [OrganizationCongress], [ProjectTaskItem], ManagerSalaryCalculator?) -> Void
    let finalizeAction: (String) -> Void
    let deleteAction: (String) -> Void
    let requestedSalaryCalculatorOrganizationID: String?
    let onSalaryRequestHandled: () -> Void
    let language: AppLanguage
    let isActive: Bool
    @Environment(\.scenePhase) private var scenePhase

    @State private var nameSv: String
    @State private var nameEn: String
    @State private var addressLine: String
    @State private var postalCode: String
    @State private var city: String
    @State private var country: String
    @State private var note: String
    @State private var websiteURL: String
    @State private var phoneNumber: String
    @State private var organizationNumber: String
    @State private var vatNumber: String
    @State private var employerContacts: [OrganizationEmployerContact]
    @State private var flag: String
    @State private var membershipFrom: String
    @State private var membershipTo: String
    @State private var congressRows: [OrganizationCongress]
    @State private var taskRows: [ProjectTaskItem]
    @State private var selectedRoles: Set<OrganizationRole>
    @State private var salaryCalculator: ManagerSalaryCalculator
    @State private var sharedCostPeriods: [SalarySharedCostPeriod]
    @State private var basicsExpanded = true
    @State private var employerExpanded = false
    @State private var managerExpanded = false
    @State private var funderExpanded = false
    @State private var timelineExpanded = false
    @State private var showOnlyOwnTimelineApplications = true
    @State private var hidePastOrganizationTimelineEvents = false
    @State private var hideRejectedOrganizationTimelineGrants = true
    @State private var tasksExpanded = true
    @State private var institutionTeachingExpanded = true
    @State private var showCompletedOrganizationTasks = false
    @State private var autosaveTask: DispatchWorkItem?
    @State private var forcedPersistTask: DispatchWorkItem?
    @State private var deferredPanelTask: DispatchWorkItem?
    @State private var salaryRowsRefreshTask: DispatchWorkItem?
    @State private var showDeferredAssociationContent = false
    @State private var showDeferredEmployerContent = false
    @State private var showDeferredManagedContent = false
    @State private var showDeferredFunderContent = false
    @State private var activeFunderSegmentFilter: GrantOutcomeSegmentKind? = nil
    @State private var activeManagedSegmentFilter: GrantOutcomeSegmentKind? = nil
    @State private var salaryRowsCache: [SalaryCalculationRow] = []
    @State private var salaryRowsSignature: SalaryCalculationCacheSignature?
    @State private var deferredPanelsPreparedForOptionID: String?
    /// Lists derived from the store, kept between redraws (see
    /// linkedInstitutionResearchers). A reference, so filling it while the
    /// page is drawn does not ask SwiftUI to draw again.
    @State private var derivedCache = OrganizationDetailDerivedCache()

    private var pendingAndRejectedApplications: [GrantApplication] {
        applications
            .filter(\.isNonGrantedForWorklists)
            .sorted {
                if $0.isToApplyStatus != $1.isToApplyStatus {
                    return $0.isToApplyStatus && !$1.isToApplyStatus
                }
                let leftDate = $0.applicationDate ?? .distantPast
                let rightDate = $1.applicationDate ?? .distantPast
                if leftDate != rightDate {
                    return leftDate > rightDate
                }
                return fundTitle(for: $0) < fundTitle(for: $1)
            }
    }

    private var managedGrantedApplications: [GrantApplication] {
        managedApplications
            .filter(\.isGranted)
            .sorted { fundTitle(for: $0) < fundTitle(for: $1) }
    }

    private var funderRejectedApplications: [GrantApplication] {
        applications.filter {
            let status = $0.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            return status == "Avslag" || status == "Tillbakadragen"
        }
    }

    private var funderWaitingApplications: [GrantApplication] {
        applications.filter { $0.resultLabel == "Väntar svar" }
    }

    private var managedRejectedApplications: [GrantApplication] {
        managedApplications.filter {
            let status = $0.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            return status == "Avslag" || status == "Tillbakadragen"
        }
    }

    private var managedWaitingApplications: [GrantApplication] {
        managedApplications.filter { $0.resultLabel == "Väntar svar" }
    }

    private var filteredFunderApplications: [GrantApplication] {
        guard let activeFunderSegmentFilter else { return applications }
        let relevant = applications.filter { !$0.isToApplyStatus }
        switch activeFunderSegmentFilter {
        case .waiting:
            return funderWaitingApplications
        case .rejected:
            return funderRejectedApplications
        case .granted:
            return relevant.filter(\.isGranted)
        }
    }

    private var funderApplicationsListTitle: String {
        guard let activeFunderSegmentFilter else {
            return language.text("Applications", "Ansökningar")
        }
        return activeFunderSegmentFilter.title(language: language)
    }

    private var filteredManagedApplications: [GrantApplication] {
        guard let activeManagedSegmentFilter else { return managedApplications }
        let relevant = managedApplications.filter { !$0.isToApplyStatus }
        switch activeManagedSegmentFilter {
        case .waiting:
            return managedWaitingApplications
        case .rejected:
            return managedRejectedApplications
        case .granted:
            return relevant.filter(\.isGranted)
        }
    }

    private var managedApplicationsListTitle: String {
        guard let activeManagedSegmentFilter else {
            return language.text("Applications", "Ansökningar")
        }
        return activeManagedSegmentFilter.title(language: language)
    }

    private var showsFunderStats: Bool {
        selectedRoles.contains(.grantProvider)
    }

    private var showsManagedStats: Bool {
        selectedRoles.contains(.fundManager)
    }

    private var showsSalaryCalculator: Bool {
        selectedRoles.contains(.employer)
    }

    private var showsInstitutionTeaching: Bool {
        selectedRoles.contains(.institution)
    }

    private var organizationTaskReminderOptions: [ProjectTaskReminder] {
        ProjectTaskReminder.organizationOptions(for: selectedRoles)
    }

    private var showsOrganizationTimeline: Bool {
        !selectedRoles.intersection([.association, .company, .grantProvider, .employer, .fundManager]).isEmpty
    }

    private var organizationTimelineSnapshot: GrantDataStore.OrganizationTimelineSnapshot {
        let startedAt = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            if duration >= 8 {
                store.appendPerformanceDiagnostic(
                    String(
                        format: "organization-timeline-snapshot organization=%@ applications=%ld managed=%ld total_ms=%.2f",
                        option.nameSv,
                        applications.count,
                        managedApplications.count,
                        duration
                    )
                )
            }
        }
        let timelineFunderApplications = organizationTimelineApplications(applications)
        let timelineManagedApplications = organizationTimelineApplications(managedApplications)
        return GrantDataStore.buildOrganizationTimelineSnapshot(
            organization: option,
            selectedRoles: selectedRoles,
            congresses: Self.persistedCongresses(from: congressRows),
            salaryCalculator: salaryCalculator,
            funderApplications: timelineFunderApplications,
            managedApplications: timelineManagedApplications,
            currentUserAuthor: store.currentUserAuthor(),
            language: language,
            hidePastEvents: hidePastOrganizationTimelineEvents,
            hideRejectedGrants: hideRejectedOrganizationTimelineGrants,
            effectiveFullySpentDatesByApplicationID: organizationTimelineEffectiveFullySpentDates(
                for: timelineFunderApplications + timelineManagedApplications
            )
        )
    }

    private var organizationTimelineHasApplicationRoles: Bool {
        !selectedRoles.intersection([.grantProvider, .fundManager]).isEmpty
    }

    private func organizationTimelineApplications(_ source: [GrantApplication]) -> [GrantApplication] {
        guard showOnlyOwnTimelineApplications else { return source }
        return source.filter { store.isCurrentUserFirstApplicant($0) }
    }

    private func organizationTimelineEffectiveFullySpentDates(for applications: [GrantApplication]) -> [String: Date] {
        applications.reduce(into: [String: Date]()) { result, application in
            guard store.isEffectivelyFullySpent(application),
                  !application.isFullySpent,
                  let lastDispositionDate = application.lastDispositionDate else { return }
            result[application.id] = lastDispositionDate
        }
    }

    private var linkedInstitutionResearchers: [OrganizationLinkedResearcherRow] {
        // Which researchers are linked (and how) is kept until a researcher
        // or this organization's names change: matching every researcher's
        // affiliation, employment and education rows by name was redone on
        // each redraw of the page, several times while its panels appear.
        // The counts are read fresh each time (cheap lookups that are
        // updated separately from the researcher list).
        let key = OrganizationDetailDerivedCache.LinkedResearchersKey(
            organizationID: option.id,
            nameSv: option.nameSv,
            nameEn: option.nameEn,
            language: language,
            researchersGeneration: store.publicationAuthorsContentGeneration
        )
        let entries: [OrganizationDetailDerivedCache.LinkedResearcherEntry]
        if derivedCache.linkedResearchersKey == key {
            entries = derivedCache.linkedResearchers
        } else {
            let startedAt = CFAbsoluteTimeGetCurrent()
            entries = store.publicationAuthors
                .compactMap { author -> OrganizationDetailDerivedCache.LinkedResearcherEntry? in
                    let categories = linkedResearcherCategories(for: author)
                    guard !categories.isEmpty else { return nil }
                    return OrganizationDetailDerivedCache.LinkedResearcherEntry(
                        author: author,
                        subtitle: categories.joined(separator: " · ")
                    )
                }
                .sorted {
                    $0.author.displayName.localizedStandardCompare($1.author.displayName) == .orderedAscending
                }
            derivedCache.linkedResearchersKey = key
            derivedCache.linkedResearchers = entries
            let duration = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            if duration >= 8 {
                store.appendPerformanceDiagnostic(
                    String(
                        format: "organization-linked-researchers-build organization=%@ rows=%ld total_ms=%.2f",
                        option.nameSv,
                        entries.count,
                        duration
                    )
                )
            }
        }
        return entries.map { entry in
            OrganizationLinkedResearcherRow(
                author: entry.author,
                subtitle: entry.subtitle,
                projectCount: store.projectCount(forAuthorID: entry.author.id),
                grantCount: store.grantCount(forAuthorID: entry.author.id),
                publicationCount: entry.author.publicationCount
            )
        }
    }

    private var currentUserBirthDate: String? {
        store.currentUserAuthor()?.birthDate.nonEmpty
    }

    private var derivedScopeCategory: String? {
        store.derivedOrganizationCategory(city: city, country: country, fallback: option.category)
    }

    private var derivedScopeLabel: String {
        guard let derivedScopeCategory else {
            return language.text("Determined automatically when city and country are set", "Bestäms automatiskt när ort och land är angivna")
        }
        return language.localizedGrantCategory(derivedScopeCategory)
    }

    private var websiteDestinationURL: URL? {
        normalizedWebLinkURL(websiteURL)
    }

    init(
        store: GrantDataStore,
        title: String,
        option: OrganizationRecord,
        applications: [GrantApplication],
        managedApplications: [GrantApplication],
        openAction: @escaping (GrantApplication) -> Void,
        autosaveAction: @escaping (String, String, String, String, String, String, String, String?, [OrganizationRole], String?, String, String, String, String, [OrganizationEmployerContact], String, String, String, [OrganizationCongress], [ProjectTaskItem], ManagerSalaryCalculator?) -> Void,
        finalizeAction: @escaping (String) -> Void,
        deleteAction: @escaping (String) -> Void,
        requestedSalaryCalculatorOrganizationID: String? = nil,
        onSalaryRequestHandled: @escaping () -> Void = {},
        language: AppLanguage,
        isActive: Bool = true
    ) {
        self.store = store
        self.title = title
        self.option = option
        self.applications = applications
        self.managedApplications = managedApplications
        self.openAction = openAction
        self.autosaveAction = autosaveAction
        self.finalizeAction = finalizeAction
        self.deleteAction = deleteAction
        self.requestedSalaryCalculatorOrganizationID = requestedSalaryCalculatorOrganizationID
        self.onSalaryRequestHandled = onSalaryRequestHandled
        self.language = language
        self.isActive = isActive
        _nameSv = State(initialValue: option.nameSv)
        _nameEn = State(initialValue: option.nameEn)
        _addressLine = State(initialValue: option.addressLine)
        _postalCode = State(initialValue: option.postalCode)
        _city = State(initialValue: option.city)
        _country = State(initialValue: option.country)
        _note = State(initialValue: option.note ?? "")
        _websiteURL = State(initialValue: option.websiteURL)
        _phoneNumber = State(initialValue: option.phoneNumber)
        _organizationNumber = State(initialValue: option.organizationNumber)
        _vatNumber = State(initialValue: option.vatNumber)
        _employerContacts = State(initialValue: Self.normalizedEmployerContacts(option.employerContacts))
        _flag = State(initialValue: option.flag)
        _membershipFrom = State(initialValue: option.membershipFrom)
        _membershipTo = State(initialValue: option.membershipTo)
        _congressRows = State(initialValue: Self.normalizedCongressRows(option.congresses))
        _taskRows = State(initialValue: Self.normalizedOrganizationTasks(option.projectTasks))
        _selectedRoles = State(initialValue: Set(option.roles))
        let calculator = Self.defaultSalaryCalculator(for: option)
        _salaryCalculator = State(initialValue: calculator)
        _sharedCostPeriods = State(initialValue: Self.mergedSharedCostPeriods(from: calculator))
        _timelineExpanded = State(initialValue: organizationTimelineExpandedByDefault(for: Set(option.roles)))
    }

    var body: some View {
        detailBody
    }

    private var detailBody: some View {
        let base = AnyView(
            ScrollView {
                detailContent
                    .padding(14)
            }
        )

        return applyDetailSyncModifiers(
            to: applyDetailAutosaveModifiers(
                to: applyDetailLifecycleModifiers(to: base)
            )
        )
    }

    private func applyDetailLifecycleModifiers<V: View>(to view: V) -> some View {
        view
            .onDisappear(perform: handleDetailDisappear)
            .onAppear(perform: handleDetailAppear)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active {
                    requestImmediatePersist()
                }
            }
            .onChange(of: isActive) { _, active in
                if active {
                    scheduleDeferredPanelRefresh()
                    scheduleSalaryRowsRefresh()
                } else {
                    deferredPanelTask?.cancel()
                    salaryRowsRefreshTask?.cancel()
                    showDeferredAssociationContent = false
                    showDeferredEmployerContent = false
                    showDeferredManagedContent = false
                    showDeferredFunderContent = false
                    salaryRowsCache = []
                    salaryRowsSignature = nil
                }
            }
    }

    private func applyDetailAutosaveModifiers<V: View>(to view: V) -> some View {
        let base = view
            .onChange(of: nameSv) { _, _ in scheduleAutosave() }
            .onChange(of: nameEn) { _, _ in scheduleAutosave() }
            .onChange(of: addressLine) { _, _ in scheduleAutosave() }
            .onChange(of: postalCode) { _, _ in scheduleAutosave() }
            .onChange(of: city) { _, _ in scheduleAutosave() }
            .onChange(of: country) { _, _ in scheduleAutosave() }
            .onChange(of: note) { _, _ in scheduleAutosave() }
            .onChange(of: websiteURL) { _, _ in scheduleAutosave() }
            .onChange(of: phoneNumber) { _, _ in scheduleAutosave() }
            .onChange(of: organizationNumber) { _, _ in scheduleAutosave() }
            .onChange(of: vatNumber) { _, _ in scheduleAutosave() }
            .onChange(of: flag) { _, _ in scheduleAutosave() }
            .onChange(of: membershipFrom) { _, _ in scheduleAutosave() }
            .onChange(of: membershipTo) { _, _ in scheduleAutosave() }

        let roleAware = base
            .onChange(of: selectedRoles) { _, _ in
                scheduleDeferredPanelRefresh()
                scheduleAutosave()
            }
            .onChange(of: congressRows) { oldValue, newValue in
                guard Self.persistedCongresses(from: oldValue) != Self.persistedCongresses(from: newValue) else { return }
                scheduleAutosave()
            }

        let taskAware = roleAware
            .onChange(of: taskRows) { _, newValue in
                let normalized = Self.normalizedOrganizationTasks(newValue)
                if normalized != newValue {
                    taskRows = normalized
                }
                scheduleAutosave()
            }
            .onChange(of: employerContacts) { _, newValue in
                let normalized = Self.normalizedEmployerContacts(newValue)
                if normalized != newValue {
                    employerContacts = normalized
                    return
                }
                scheduleAutosave()
            }

        return taskAware
            .onChange(of: salaryCalculator) { _, _ in
                scheduleSalaryRowsRefresh()
                scheduleAutosave()
            }
            .onChange(of: sharedCostPeriods) { _, _ in
                scheduleSalaryRowsRefresh()
                scheduleAutosave()
            }
    }

    private func applyDetailSyncModifiers<V: View>(to view: V) -> some View {
        view
            .onChange(of: store.publicationAuthors) { _, _ in
                syncSalaryBirthDateFromCurrentUser()
            }
            .onChange(of: option) { oldValue, newValue in
                guard oldValue.id != newValue.id else { return }
                autosaveTask?.cancel()
                persistAutosaveIfNeeded(baseline: oldValue)
                nameSv = newValue.nameSv
                nameEn = newValue.nameEn
                addressLine = newValue.addressLine
                postalCode = newValue.postalCode
                city = newValue.city
                country = newValue.country
                note = newValue.note ?? ""
                websiteURL = newValue.websiteURL
                phoneNumber = newValue.phoneNumber
                organizationNumber = newValue.organizationNumber
                vatNumber = newValue.vatNumber
                employerContacts = Self.normalizedEmployerContacts(newValue.employerContacts)
                flag = newValue.flag
                membershipFrom = newValue.membershipFrom
                membershipTo = newValue.membershipTo
                congressRows = Self.normalizedCongressRows(newValue.congresses)
                taskRows = Self.normalizedOrganizationTasks(newValue.projectTasks)
                selectedRoles = Set(newValue.roles)
                let calculator = Self.defaultSalaryCalculator(for: newValue)
                salaryCalculator = calculator
                sharedCostPeriods = Self.mergedSharedCostPeriods(from: calculator)
                salaryRowsCache = []
                salaryRowsSignature = nil
                resetSectionExpansionDefaults()
                resetDeferredPanels()
                scheduleDeferredPanelRefresh(reset: true)
                scheduleSalaryRowsRefresh()
            }
            .onChange(of: requestedSalaryCalculatorOrganizationID) { _, _ in
                handleSalaryCalculatorRequest()
            }
            .onChange(of: basicsExpanded) { _, isExpanded in
                if isExpanded {
                    scheduleDeferredPanelRefresh()
                }
            }
            .onChange(of: employerExpanded) { _, isExpanded in
                if isExpanded {
                    scheduleDeferredPanelRefresh()
                    scheduleSalaryRowsRefresh()
                }
            }
            .onChange(of: showDeferredEmployerContent) { _, isVisible in
                if isVisible {
                    scheduleSalaryRowsRefresh()
                }
            }
            .onChange(of: managerExpanded) { _, isExpanded in
                if isExpanded {
                    scheduleDeferredPanelRefresh()
                }
            }
            .onChange(of: funderExpanded) { _, isExpanded in
                if isExpanded {
                    scheduleDeferredPanelRefresh()
                }
            }
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            OrganizationDetailHeader(
                nameSv: $nameSv,
                nameEn: $nameEn,
                language: language,
                websiteDestinationURL: websiteDestinationURL,
                deleteAction: { deleteAction(option.id) }
            )
            rolesPanel

            OrganizationUnitsSection(store: store, organizationID: option.id, language: language)

            organizationTimelinePanel

            organizationTasksPanel

            if showsSalaryCalculator {
                employerPanel
            }

            if showsManagedStats {
                OrganizationGrantDashboardPanel(
                    store: store,
                    title: language.text("Fund manager", "Medelsförvaltare"),
                    mode: .fundManager,
                    isExpanded: $managerExpanded,
                    showDeferredContent: showDeferredManagedContent,
                    applications: managedApplications,
                    displayedApplications: filteredManagedApplications,
                    language: language,
                    dashboardTitle: managedApplicationsListTitle,
                    placeholderTitle: language.text("Preparing fund-manager data…", "Förbereder medelsförvaltardata…"),
                    segmentTapAction: { segment in
                        activeManagedSegmentFilter = segment
                    },
                    openApplication: { application in
                        openAction(application)
                    }
                )
            }

            if showsFunderStats {
                OrganizationGrantDashboardPanel(
                    store: store,
                    title: language.text("Grant provider", "Anslagsgivare"),
                    mode: .grantProvider,
                    isExpanded: $funderExpanded,
                    showDeferredContent: showDeferredFunderContent,
                    applications: applications,
                    displayedApplications: filteredFunderApplications,
                    language: language,
                    dashboardTitle: funderApplicationsListTitle,
                    placeholderTitle: language.text("Preparing grant-provider data…", "Förbereder anslagsgivardata…"),
                    scopeLabel: derivedScopeLabel,
                    segmentTapAction: { segment in
                        activeFunderSegmentFilter = segment
                    },
                    openApplication: { application in
                        openAction(application)
                    }
                )
            }

            if showsInstitutionTeaching {
                OrganizationLinkedResearchersPanel(
                    researchers: linkedInstitutionResearchers,
                    language: language,
                    openResearcher: { author in
                        store.openRoute(for: author)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var rolesPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            DetailGroup(title: "", showsSurface: false) {
                VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            AppFieldLabelText(text: language.text("Type", "Typ"))
                            HStack(alignment: .top, spacing: 18) {
                                roleToggle(.grantProvider, title: fixedDropdownText("organizationRole.grantProvider", language: language, english: "Grant provider", swedish: "Anslagsgivare"))
                                roleToggle(.fundManager, title: fixedDropdownText("organizationRole.fundManager", language: language, english: "Fund manager", swedish: "Medelsförvaltare"))
                                roleToggle(.employer, title: fixedDropdownText("organizationRole.employer", language: language, english: "Employer", swedish: "Arbetsgivare"))
                                roleToggle(.institution, title: fixedDropdownText("organizationRole.institution", language: language, english: "Higher education institution", swedish: "Lärosäte"))
                                roleToggle(.association, title: fixedDropdownText("organizationRole.association", language: language, english: "Association", swedish: "Förening"))
                                roleToggle(.company, title: fixedDropdownText("organizationRole.company", language: language, english: "Company", swedish: "Företag"))
                                Spacer()
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel(language.text("Type", "Typ"))
                        }

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                AppFieldLabelText(text: language.text("Address line", "Adressrad"))
                                TextField(language.text("Address line", "Adressrad"), text: $addressLine)
                                    .appTextInputChrome()
                            }
                            .frame(minWidth: 220, idealWidth: 280, maxWidth: 320, alignment: .leading)
                            VStack(alignment: .leading, spacing: 6) {
                                AppFieldLabelText(text: language.text("Postal code", "Postnummer"))
                                TextField(language.text("Postal code", "Postnummer"), text: $postalCode)
                                    .appTextInputChrome()
                            }
                            .frame(width: 120, alignment: .leading)
                            VStack(alignment: .leading, spacing: 6) {
                                AppFieldLabelText(text: language.text("City", "Ort"))
                                TextField(language.text("City", "Ort"), text: $city)
                                    .appTextInputChrome()
                            }
                            .frame(maxWidth: 220, alignment: .leading)
                            VStack(alignment: .leading, spacing: 6) {
                                AppFieldLabelText(text: language.text("Country", "Land"))
                                CountryPickerField(selection: $country, language: language, width: 180)
                            }
                            .frame(width: 180, alignment: .leading)
                            VStack(alignment: .leading, spacing: 6) {
                                AppFieldLabelText(text: language.text("Scope", "Nivå"))
                                Text(derivedScopeLabel)
                                    .appTypography(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, AppPalette.textFieldHorizontalPadding)
                                    .padding(.vertical, AppPalette.textFieldVerticalPadding)
                                    .frame(minHeight: AppPalette.fieldMinHeight, alignment: .leading)
                            }
                            .frame(minWidth: 220, maxWidth: 320, alignment: .leading)
                            Spacer(minLength: 0)
                        }

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                AppFieldLabelText(text: language.text("Website", "Hemsida"))
                                TextField(language.text("Website", "Hemsida"), text: $websiteURL)
                                    .appTextInputChrome()
                            }
                            .frame(minWidth: 280, idealWidth: 320, maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .leading, spacing: 6) {
                                AppFieldLabelText(text: language.text("Phone", "Telefon"))
                                TextField(language.text("Phone", "Telefon"), text: $phoneNumber)
                                    .appTextInputChrome()
                            }
                            .frame(width: 190, alignment: .leading)

                            if selectedRoles.contains(.employer) {
                                VStack(alignment: .leading, spacing: 6) {
                                    AppFieldLabelText(text: language.text("Organization number", "Organisationsnummer"))
                                    TextField(language.text("Organization number", "Organisationsnummer"), text: $organizationNumber)
                                        .appTextInputChrome()
                                }
                                .frame(width: 210, alignment: .leading)

                                VStack(alignment: .leading, spacing: 6) {
                                    AppFieldLabelText(text: language.text("VAT number", "VAT-nummer"))
                                    TextField(language.text("VAT number", "VAT-nummer"), text: $vatNumber)
                                        .appTextInputChrome()
                                }
                                .frame(width: 190, alignment: .leading)
                            }
                        }

                        OrganizationPublicationAddressFields(store: store, organizationID: option.id, language: language)

                        if selectedRoles.contains(.grantProvider) {
                            OrganizationMaxOverheadField(store: store, organizationID: option.id, language: language)
                        }

                        EditableTextArea(
                            title: language.text("Note", "Notering"),
                            text: $note,
                            minimumHeight: 72
                        )

                        OrganizationContactPersonsSection(
                            contacts: $employerContacts,
                            language: language
                        )

                        if selectedRoles.contains(.association) {
                            if showDeferredAssociationContent {
                                OrganizationAssociationSection(
                                    store: store,
                                    organizationID: option.id,
                                    membershipFrom: $membershipFrom,
                                    membershipTo: $membershipTo,
                                    congressRows: $congressRows,
                                    linkedContributions: linkedAssociationConferenceContributions,
                                    language: language,
                                    openContribution: { contribution in
                                        store.openRoute(for: contribution)
                                    }
                                )
                            } else {
                                OrganizationDeferredPanelPlaceholder(title: language.text("Preparing association details…", "Förbereder föreningsdetaljer…"))
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var organizationTimelinePanel: some View {
        if showsOrganizationTimeline {
            VStack(alignment: .leading, spacing: 14) {
                CollapsibleSectionHeader(
                    title: language.text("Timeline", "Tidslinje"),
                    isExpanded: $timelineExpanded
                )
                if timelineExpanded {
                    HStack(spacing: 14) {
                        Toggle(
                            language.text("Hide past events", "Dölj tidigare händelser"),
                            isOn: $hidePastOrganizationTimelineEvents
                        )
                        .appCheckboxStyle()
                        .fixedSize(horizontal: true, vertical: false)

                        if organizationTimelineHasApplicationRoles {
                            Toggle(
                                language.text("Show only my applications", "Visa endast egna ansökningar"),
                                isOn: $showOnlyOwnTimelineApplications
                            )
                            .appCheckboxStyle()
                            .fixedSize(horizontal: true, vertical: false)

                            Toggle(
                                language.text("Hide declined grants", "Dölj nekade anslag"),
                                isOn: $hideRejectedOrganizationTimelineGrants
                            )
                            .appCheckboxStyle()
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    OrganizationTimelineView(
                        snapshot: organizationTimelineSnapshot,
                        style: store.projectTimelineStyle,
                        language: language,
                        openApplicationAction: { applicationID in
                            if let application = store.application(id: applicationID) {
                                openAction(application)
                            }
                        },
                        openCongressAction: { congressID in
                            openCongressInWorkspace(congressID: congressID)
                        }
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    organizationTimelineCongressList
                }
            }
        }
    }

    @ViewBuilder
    private var organizationTimelineCongressList: some View {
        let congresses = visibleOrganizationTimelineCongresses
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AppTableHeaderText(text: language.text("Congresses", "Kongresser"))

                Spacer()

                Button {
                    addCongressFromTimeline()
                } label: {
                    Text(language.text("Add congress", "Lägg till kongress"))
                }
                .appAddButtonStyle()
            }

            if !congresses.isEmpty {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(congresses) { congress in
                        Button {
                            openCongressInWorkspace(congressID: congress.id)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(congress.title.nonEmpty ?? language.text("Congress", "Kongress"))
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(AppPalette.appText)
                                        .lineLimit(1)
                                    Text(organizationCongressPlaceText(congress).nonEmpty ?? option.displayName(for: language))
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(organizationCongressDateText(congress))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                if CongressesWorkspaceView.congressCurrentUserParticipates(
                                    congress,
                                    currentUserAuthor: store.currentUserAuthor()
                                ) {
                                    Text(language.text("Attend", "Medverkar"))
                                        .font(.system(size: 12, weight: .semibold))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(AppPalette.shadeGreen, in: Capsule(style: .continuous))
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .stroke(AppPalette.vividGreen.opacity(0.75), lineWidth: 1)
                                        )
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if congress.id != congresses.last?.id {
                            Divider()
                        }
                    }
                }
                .background(AppPalette.cardSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppPalette.border.opacity(0.65), lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private var employerPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            CollapsibleSectionHeader(
                title: language.text("Employer: salary basis", "Arbetsgivare: löneunderlag"),
                isExpanded: $employerExpanded
            )
            if employerExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(
                        language.text("Use as salary calculator for applications", "Använd som lönekalkyl för ansökningar"),
                        isOn: Binding(
                            get: {
                                store.organization(id: option.id)?.usesAsApplicationSalaryCalculator
                                    ?? option.usesAsApplicationSalaryCalculator
                            },
                            set: { enabled in
                                store.setOrganizationUsesAsApplicationSalaryCalculator(
                                    organizationID: option.id,
                                    enabled: enabled
                                )
                                if enabled, let currentUserBirthDate,
                                   salaryCalculator.birthDate != currentUserBirthDate {
                                    salaryCalculator.birthDate = currentUserBirthDate
                                }
                            }
                        )
                    )
                    .appCheckboxStyle()
                    Text(language.text(
                        "This organization's salary calculator is then used for salary budgets in applications and follows your date of birth. Only one organization can be chosen.",
                        "Organisationens lönekalkyl används då för lönebudgetar i ansökningar och följer ditt födelsedatum. Bara en organisation kan vara vald."
                    ))
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
                }
                if showDeferredEmployerContent {
                    salaryCalculatorPanel(language: language)
                } else {
                    OrganizationDeferredPanelPlaceholder(title: language.text("Preparing employer details…", "Förbereder arbetsgivardetaljer…"))
                }
            }
        }
    }

    @ViewBuilder
    private var organizationTasksPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            CollapsibleSectionHeader(
                title: language.text("Task list", "Uppgiftslista"),
                isExpanded: $tasksExpanded,
                trailingActionTitle: language.text("Add task", "Lägg till uppgift"),
                trailingAction: {
                    CentralTaskListSection.addTask(store: store, linkKind: .organization, targetID: option.id)
                }
            )
            if tasksExpanded {
                CentralTaskListSection(
                    store: store,
                    linkKind: .organization,
                    targetID: option.id,
                    language: language,
                    reminderOptions: organizationTaskReminderOptions,
                    isReadOnly: false,
                    showsAddButton: false
                )
            }
        }
    }

    private var visibleOrganizationTimelineCongresses: [OrganizationCongress] {
        let congresses = Self.persistedCongresses(from: congressRows)
        let filtered = hidePastOrganizationTimelineEvents
            ? congresses.filter { !organizationCongressIsPast($0) }
            : congresses
        return filtered.sorted(by: Self.congressSortOrder)
    }

    private func organizationCongressIsPast(_ congress: OrganizationCongress) -> Bool {
        let start = congress.from.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
        let end = congress.to.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
        guard let effectiveEnd = end ?? start else { return false }
        return Calendar.current.startOfDay(for: effectiveEnd) < Calendar.current.startOfDay(for: Date())
    }

    private func organizationCongressDateText(_ congress: OrganizationCongress) -> String {
        let start = congress.from.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
        let end = congress.to.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
        switch (start, end) {
        case let (start?, end?):
            return CongressMapModel.compactDateRangeText(start: start, end: end, language: language)
        case let (start?, nil):
            return CongressMapModel.compactDateRangeText(start: start, end: start, language: language)
        case let (nil, end?):
            return CongressMapModel.compactDateRangeText(start: end, end: end, language: language)
        default:
            return [congress.from.nonEmpty, congress.to.nonEmpty].compactMap { $0 }.joined(separator: " - ").nonEmpty ?? "-"
        }
    }

    private func organizationCongressPlaceText(_ congress: OrganizationCongress) -> String {
        [congress.venue.trimmedOrNil, congress.city.trimmedOrNil, congress.country.trimmedOrNil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private func openCongressInWorkspace(congressID: String) {
        store.openRouteToCongress(organizationID: option.id, congressID: congressID)
    }

    private func addCongressFromTimeline() {
        autosaveTask?.cancel()
        forcedPersistTask?.cancel()

        let newCongress = OrganizationCongress(title: language.text("New congress", "Ny kongress"))
        let congresses = Self.persistedCongresses(from: congressRows + [newCongress])
        congressRows = Self.normalizedCongressRows(congresses)

        autosaveAction(
            option.id,
            nameSv,
            nameEn,
            addressLine,
            postalCode,
            city,
            country,
            derivedScopeCategory,
            OrganizationRole.allCases.filter(selectedRoles.contains),
            note.nonEmpty,
            websiteURL,
            phoneNumber,
            organizationNumber,
            vatNumber,
            persistedEmployerContacts(),
            flag,
            membershipFrom,
            membershipTo,
            congresses,
            persistedOrganizationTasks(),
            showsSalaryCalculator ? calculatorForPersistence() : option.salaryCalculator
        )

        openCongressInWorkspace(congressID: newCongress.id)
    }

    private func amountSummary(for applications: [GrantApplication], value keyPath: KeyPath<GrantApplication, Double?>) -> String {
        store.formattedGrantAmountSummaryInSEK(for: applications, value: keyPath)
    }

    private func shortenedGrantTitle(for application: GrantApplication) -> String {
        store.localizedGrantName(for: application, language: language).nonEmpty ?? language.text("Untitled grant", "Namnlöst anslag")
    }

    private func fundTitle(for application: GrantApplication) -> String {
        let project = store.projectLabel(for: application, language: language).nonEmpty ?? language.text("No project", "Saknar projekt")
        return "\(project) (\(option.displayName(for: language)))"
    }

    private func amountDetail(for application: GrantApplication) -> String {
        let amount = application.isGranted ? application.grantedAmountValue : application.appliedAmountValue
        return store.formattedGrantAmountWithSEKApproximation(amount, for: application)
    }

    private func organizationGrantListItem(for application: GrantApplication) -> DashboardListItem {
        DashboardListItem(
            title: store.projectLabel(for: application, language: language).nonEmpty ?? language.text("No project", "Saknar projekt"),
            subtitle: "\(store.organizationLabel(for: application, language: language)) · \(shortenedGrantTitle(for: application))",
            detail: amountDetail(for: application),
            status: language.localizedStatus(application.resultLabel),
            tone: applicationTone(for: application),
            action: { openAction(application) }
        )
    }

    private func statisticsSummaryText(count: Int, countLabel: String, amountText: String) -> String {
        "\(count) \(countLabel), \(amountText)"
    }

    private func prefixedStatisticsSummaryText(prefix: String, count: Int, countLabel: String, amountText: String) -> String {
        "\(prefix) \(statisticsSummaryText(count: count, countLabel: countLabel, amountText: amountText))"
    }

    private func statisticsChipText(
        prefix: String,
        applications: [GrantApplication],
        amountKeyPath: KeyPath<GrantApplication, Double?>
    ) -> String {
        let count = applications.count
        let amountText = amountSummary(for: applications, value: amountKeyPath)
        return "\(prefix) \(count) \(language.text("grants", "anslag")), \(amountText)"
    }

    private func roleToggle(_ role: OrganizationRole, title: String) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { selectedRoles.contains(role) },
                set: { enabled in
                    if enabled {
                        selectedRoles.insert(role)
                    } else {
                        selectedRoles.remove(role)
                    }
                }
            )
        )
        .appCheckboxStyle()
    }

    private func linkedResearcherCategories(for author: PublicationAuthor) -> [String] {
        let hasAffiliation = author.affiliations.contains { affiliation in
            rowBelongsToSelectedOrganization(
                organizationID: affiliation.organizationID,
                names: [affiliation.organizationSv, affiliation.organizationEn, affiliation.organization]
            )
        }
        let hasEmployment = author.employments.contains { employment in
            rowBelongsToSelectedOrganization(
                organizationID: employment.organizationID,
                names: [employment.organizationSv, employment.organizationEn, employment.organization]
            )
        }
        let hasEducation = author.educationEntries.contains { education in
            rowBelongsToSelectedOrganization(
                organizationID: education.organizationID,
                names: [education.organizationSv, education.organizationEn, education.organization]
            )
        }

        return [
            hasAffiliation ? language.text("Affiliation", "Affiliering") : nil,
            hasEmployment ? language.text("Employment", "Anställning") : nil,
            hasEducation ? language.text("Education", "Utbildning") : nil
        ]
        .compactMap { $0 }
    }

    /// A row linked to an organization belongs to the organization it points
    /// to; only rows without a link are matched by their organization text.
    private func rowBelongsToSelectedOrganization(organizationID: String?, names: [String]) -> Bool {
        if let organizationID = organizationID?.trimmedOrNil {
            return organizationID == option.id
        }
        return organizationMatchesSelectedInstitution(names)
    }

    private func organizationMatchesSelectedInstitution(_ names: [String]) -> Bool {
        let selectedNames = Set([option.nameSv, option.nameEn]
            .compactMap { PublicationDerivation.normalizedName($0).nonEmpty })
        let candidateNames = Set(names
            .compactMap { PublicationDerivation.normalizedName($0).nonEmpty })
        return !selectedNames.isEmpty && !selectedNames.isDisjoint(with: candidateNames)
    }

    private func persistChanges(completePendingSelection: Bool = false) {
        autosaveTask?.cancel()
        let rolesChanged = option.roles != OrganizationRole.allCases.filter(selectedRoles.contains)
        // Only an employer's calculator is saved (see the call below); other
        // organizations pass their stored one on unchanged. Comparing the
        // editor's calculator instead made every organization without a
        // stored calculator look edited each time it was left.
        let persistedCalculator = showsSalaryCalculator ? calculatorForPersistence() : option.salaryCalculator
        let calculatorChanged = persistedCalculator != option.salaryCalculator
        let congresses = persistedCongresses()
        let projectTasks = persistedOrganizationTasks()
        let persistedEmployerContacts = persistedEmployerContacts()
        let congressesChanged = congresses != option.congresses
        let tasksChanged = projectTasks != option.projectTasks
        guard nameSv != option.nameSv
            || nameEn != option.nameEn
            || addressLine != option.addressLine
            || postalCode != option.postalCode
            || city != option.city
            || country != option.country
            || derivedScopeCategory != option.category
            || note != (option.note ?? "")
            || websiteURL != option.websiteURL
            || phoneNumber != option.phoneNumber
            || organizationNumber != option.organizationNumber
            || vatNumber != option.vatNumber
            || persistedEmployerContacts != option.employerContacts
            || flag != option.flag
            || membershipFrom != option.membershipFrom
            || membershipTo != option.membershipTo
            || congressesChanged
            || tasksChanged
            || rolesChanged
            || calculatorChanged
        else {
            if completePendingSelection {
                finalizeAction(option.id)
            }
            return
        }
        autosaveAction(
            option.id,
            nameSv,
            nameEn,
            addressLine,
            postalCode,
            city,
            country,
            derivedScopeCategory,
            OrganizationRole.allCases.filter(selectedRoles.contains),
            note.nonEmpty,
            websiteURL,
            phoneNumber,
            organizationNumber,
            vatNumber,
            persistedEmployerContacts,
            flag,
            membershipFrom,
            membershipTo,
            congresses,
            projectTasks,
            persistedCalculator
        )
        if completePendingSelection {
            finalizeAction(option.id)
        }
    }

    private func persistAutosaveIfNeeded(baseline: OrganizationRecord) {
        let roles = OrganizationRole.allCases.filter(selectedRoles.contains)
        let calculator = showsSalaryCalculator ? calculatorForPersistence() : baseline.salaryCalculator
        let rolesChanged = baseline.roles != roles
        let calculatorChanged = calculator != baseline.salaryCalculator
        let congresses = persistedCongresses()
        let projectTasks = persistedOrganizationTasks()
        let persistedEmployerContacts = persistedEmployerContacts()
        let congressesChanged = congresses != baseline.congresses
        let tasksChanged = projectTasks != baseline.projectTasks
        guard nameSv != baseline.nameSv
            || nameEn != baseline.nameEn
            || addressLine != baseline.addressLine
            || postalCode != baseline.postalCode
            || city != baseline.city
            || country != baseline.country
            || derivedScopeCategory != baseline.category
            || note != (baseline.note ?? "")
            || websiteURL != baseline.websiteURL
            || phoneNumber != baseline.phoneNumber
            || organizationNumber != baseline.organizationNumber
            || vatNumber != baseline.vatNumber
            || persistedEmployerContacts != baseline.employerContacts
            || flag != baseline.flag
            || membershipFrom != baseline.membershipFrom
            || membershipTo != baseline.membershipTo
            || congressesChanged
            || tasksChanged
            || rolesChanged
            || calculatorChanged
        else { return }
        autosaveAction(
            baseline.id,
            nameSv,
            nameEn,
            addressLine,
            postalCode,
            city,
            country,
            derivedScopeCategory,
            roles,
            note.nonEmpty,
            websiteURL,
            phoneNumber,
            organizationNumber,
            vatNumber,
            persistedEmployerContacts,
            flag,
            membershipFrom,
            membershipTo,
            congresses,
            projectTasks,
            calculator
        )
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let task = DispatchWorkItem { persistChanges() }
        autosaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: task)
    }

    private func requestImmediatePersist() {
        forcedPersistTask?.cancel()
        let task = DispatchWorkItem {
            persistChanges(completePendingSelection: true)
        }
        forcedPersistTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
    }

    private func persistedCongresses() -> [OrganizationCongress] {
        Self.persistedCongresses(from: congressRows)
    }

    private func persistedOrganizationTasks() -> [ProjectTaskItem] {
        taskRows.filter { !$0.isEmpty }
    }

    private func persistedEmployerContacts() -> [OrganizationEmployerContact] {
        Self.persistedEmployerContacts(from: employerContacts)
    }

    private static func normalizedCongressRows(_ congresses: [OrganizationCongress]) -> [OrganizationCongress] {
        normalizedOrganizationCongressRows(congresses)
    }

    private static func persistedCongresses(from congresses: [OrganizationCongress]) -> [OrganizationCongress] {
        persistedOrganizationCongresses(from: congresses)
    }

    private static func congressSortOrder(_ lhs: OrganizationCongress, _ rhs: OrganizationCongress) -> Bool {
        func primaryDate(for congress: OrganizationCongress) -> Date? {
            [
                congress.from,
                congress.to,
                congress.abstractSubmissionDeadline,
                congress.lateAbstractSubmissionDeadline
            ]
            .compactMap { DateParsers.isoDay.date(from: $0) }
            .first
        }

        let leftDate = primaryDate(for: lhs)
        let rightDate = primaryDate(for: rhs)
        switch (leftDate, rightDate) {
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

        let leftTitle = lhs.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let rightTitle = rhs.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let comparison = leftTitle.localizedStandardCompare(rightTitle)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return lhs.id < rhs.id
    }

    private static func normalizedOrganizationTasks(_ tasks: [ProjectTaskItem]) -> [ProjectTaskItem] {
        normalizedProjectTaskItems(tasks)
    }

    private static func normalizedEmployerContacts(_ contacts: [OrganizationEmployerContact]) -> [OrganizationEmployerContact] {
        var normalized = persistedEmployerContacts(from: contacts)
        // Keep trailing placeholder row id stable so TextField focus is not lost.
        let trailingPlaceholder = contacts.last(where: \.isEmpty) ?? OrganizationEmployerContact()
        normalized.append(trailingPlaceholder)
        return normalized
    }

    private static func persistedEmployerContacts(from contacts: [OrganizationEmployerContact]) -> [OrganizationEmployerContact] {
        contacts
            .map {
                OrganizationEmployerContact(
                    id: $0.id,
                    role: $0.role.trimmingCharacters(in: .whitespacesAndNewlines),
                    firstName: $0.firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                    lastName: $0.lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                    phone: $0.phone.trimmingCharacters(in: .whitespacesAndNewlines),
                    email: $0.email.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.isEmpty }
    }

    private func handleSalaryCalculatorRequest() {
        guard requestedSalaryCalculatorOrganizationID == option.id else { return }
        selectedRoles.insert(.employer)
        basicsExpanded = true
        employerExpanded = true
        scheduleDeferredPanelRefresh()
        scheduleSalaryRowsRefresh()
        onSalaryRequestHandled()
    }

    private func resetSectionExpansionDefaults() {
        employerExpanded = false
        managerExpanded = false
        funderExpanded = false
        timelineExpanded = organizationTimelineExpandedByDefault(for: Set(option.roles))
        tasksExpanded = true
    }

    private func calculatorForPersistence() -> ManagerSalaryCalculator {
        var calculator = salaryCalculator
        if option.usesAsApplicationSalaryCalculator, let currentUserBirthDate {
            calculator.birthDate = currentUserBirthDate
        }
        return OrganizationSalaryCostRows.calculator(calculator, applying: sharedCostPeriods)
    }

    @ViewBuilder
    private func salaryCalculatorPanel(language: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SalaryCalculatorSalaryMatrixSection(
                title: language.text("Monthly salary", "Månadslön"),
                language: language,
                periods: Binding(
                    get: { salaryCalculator.monthlySalaryPeriods },
                    set: { salaryCalculator.monthlySalaryPeriods = $0 }
                )
            )

            SalaryCalculatorSharedCostMatrixSection(
                title: language.text("Cost assumptions", "Kostnadsantaganden"),
                periods: $sharedCostPeriods,
                language: language
            )

            HStack(alignment: .top, spacing: 16) {
                SalaryCalculatorCompactField(title: language.text("Allocation %", "%-del"), width: 120) {
                    CommitFormattingTextField(
                        placeholder: "%",
                        text: Binding(
                            get: { salaryCalculator.allocationPercent },
                            set: { salaryCalculator.allocationPercent = $0 }
                        ),
                        formatter: formatPercentageInput,
                        showsRenewedSurface: false,
                        isBordered: false
                    )
                    .frame(minHeight: 18)
                    .appTextInputChrome(fillsWidth: true)
                }
                SalaryCalculatorCompactField(title: language.text("Months", "Antal månader"), width: 140) {
                    CommitFormattingTextField(
                        placeholder: language.text("Months", "Månader"),
                        text: Binding(
                            get: { salaryCalculator.allocationMonths },
                            set: { salaryCalculator.allocationMonths = $0 }
                        ),
                        formatter: formatCountInput,
                        showsRenewedSurface: false,
                        isBordered: false
                    )
                    .frame(minHeight: 18)
                    .appTextInputChrome(fillsWidth: true)
                }
                SalaryCalculatorCompactField(
                    title: language.text("Annual increase after current year", "Årligt tillägg efter i år"),
                    width: 220
                ) {
                    CommitFormattingTextField(
                        placeholder: "3 %",
                        text: Binding(
                            get: { salaryCalculator.annualIncreaseAfterCurrentYearPercent },
                            set: { salaryCalculator.annualIncreaseAfterCurrentYearPercent = $0 }
                        ),
                        formatter: formatPercentageInput,
                        showsRenewedSurface: false,
                        isBordered: false
                    )
                    .frame(minHeight: 18)
                    .appTextInputChrome(fillsWidth: true)
                }
                Spacer()
            }

            salaryVacationRulesSection(language: language)

            if !salaryCalculationHasKnownAge(salaryCalculator) {
                Text(language.text(
                    "A valid date of birth is required before age-dependent salary and leave costs can be calculated.",
                    "Ett giltigt födelsedatum krävs innan åldersberoende löne- och semesterkostnader kan beräknas."
                ))
                .appTypography(.body)
                .foregroundStyle(AppPalette.vividRed)
                .accessibilityLabel(language.text(
                    "Salary calculation unavailable: date of birth is missing or invalid.",
                    "Lönekalkylen är inte tillgänglig: födelsedatum saknas eller är ogiltigt."
                ))
            } else {
                SalaryCalculatorResultsSection(
                    rows: salaryRowsCache,
                    language: language,
                    allocationPercentText: salaryCalculator.allocationPercent,
                    allocationMonthsText: salaryCalculator.allocationMonths
                )
            }
        }
    }

    /// Vacation days by age and the vacation supplement used by this
    /// calculator (defaults 25/31/32 days from age 40/50 and 0,605 % per day).
    @ViewBuilder
    private func salaryVacationRulesSection(language: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text("Vacation", "Semester"))
                .appTypography(.tableHeader)
                .foregroundStyle(.primary)
            HStack(alignment: .top, spacing: 16) {
                salaryVacationField(
                    title: language.text("Vacation days", "Semesterdagar"),
                    keyPath: \.vacationDaysBase,
                    width: 130
                )
                salaryVacationField(
                    title: language.text("From age", "Från ålder"),
                    keyPath: \.vacationFirstAgeLimit,
                    width: 110
                )
                salaryVacationField(
                    title: language.text("Vacation days", "Semesterdagar"),
                    keyPath: \.vacationDaysFromFirstAge,
                    width: 130
                )
                salaryVacationField(
                    title: language.text("From age", "Från ålder"),
                    keyPath: \.vacationSecondAgeLimit,
                    width: 110
                )
                salaryVacationField(
                    title: language.text("Vacation days", "Semesterdagar"),
                    keyPath: \.vacationDaysFromSecondAge,
                    width: 130
                )
                salaryVacationField(
                    title: language.text("Vacation supplement % per day", "Semestertillägg % per dag"),
                    keyPath: \.vacationSupplementPercentPerDay,
                    width: 200
                )
                Spacer()
            }
        }
    }

    private func salaryVacationField(
        title: String,
        keyPath: WritableKeyPath<ManagerSalaryCalculator, String>,
        width: CGFloat
    ) -> some View {
        SalaryCalculatorCompactField(title: title, width: width) {
            TextField(
                title,
                text: Binding(
                    get: { salaryCalculator[keyPath: keyPath] },
                    set: { salaryCalculator[keyPath: keyPath] = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                )
            )
            .textFieldStyle(.plain)
            .frame(minHeight: 18)
            .appTextInputChrome(fillsWidth: true)
        }
    }

    private func handleDetailAppear() {
        guard isActive else {
            resetDeferredPanels()
            return
        }
        employerContacts = Self.normalizedEmployerContacts(employerContacts)
        syncSalaryBirthDateFromCurrentUser()
        resetDeferredPanels()
        handleSalaryCalculatorRequest()
        scheduleDeferredPanelRefresh(reset: true)
        scheduleSalaryRowsRefresh()
    }

    private func handleDetailDisappear() {
        autosaveTask?.cancel()
        forcedPersistTask?.cancel()
        deferredPanelTask?.cancel()
        salaryRowsRefreshTask?.cancel()
        persistChanges(completePendingSelection: true)
    }

    private func resetDeferredPanels() {
        deferredPanelTask?.cancel()
        deferredPanelsPreparedForOptionID = nil
        showDeferredAssociationContent = false
        showDeferredEmployerContent = false
        showDeferredManagedContent = false
        showDeferredFunderContent = false
    }

    private func scheduleDeferredPanelRefresh(reset: Bool = false) {
        deferredPanelTask?.cancel()
        guard isActive else {
            showDeferredAssociationContent = false
            showDeferredEmployerContent = false
            showDeferredManagedContent = false
            showDeferredFunderContent = false
            return
        }
        if reset || deferredPanelsPreparedForOptionID != option.id {
            deferredPanelsPreparedForOptionID = option.id
            showDeferredAssociationContent = false
            showDeferredEmployerContent = false
            showDeferredManagedContent = false
            showDeferredFunderContent = false
        } else {
            if !selectedRoles.contains(.association) || !basicsExpanded {
                showDeferredAssociationContent = false
            }
            if !showsSalaryCalculator || !employerExpanded {
                showDeferredEmployerContent = false
            }
            if !showsManagedStats || !managerExpanded {
                showDeferredManagedContent = false
            }
            if !showsFunderStats || !funderExpanded {
                showDeferredFunderContent = false
            }
        }

        let task = DispatchWorkItem {
            deferredPanelTask = nil
            if selectedRoles.contains(.association) && basicsExpanded && !showDeferredAssociationContent {
                showDeferredAssociationContent = true
                store.appendPerformanceDiagnostic("organization-association-panel-ready organization=\(option.nameSv)")
                scheduleDeferredPanelRefresh()
                return
            }
            if showsSalaryCalculator && employerExpanded && !showDeferredEmployerContent {
                showDeferredEmployerContent = true
                store.appendPerformanceDiagnostic("organization-employer-panel-ready organization=\(option.nameSv)")
                scheduleDeferredPanelRefresh()
                return
            }
            if showsManagedStats && managerExpanded && !showDeferredManagedContent {
                showDeferredManagedContent = true
                store.appendPerformanceDiagnostic("organization-managed-panel-ready organization=\(option.nameSv)")
                scheduleDeferredPanelRefresh()
                return
            }
            if showsFunderStats && funderExpanded && !showDeferredFunderContent {
                showDeferredFunderContent = true
                store.appendPerformanceDiagnostic("organization-funder-panel-ready organization=\(option.nameSv)")
            }
        }
        deferredPanelTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + (reset ? 0.12 : 0.08), execute: task)
    }

    private func scheduleSalaryRowsRefresh() {
        salaryRowsRefreshTask?.cancel()
        guard isActive else {
            salaryRowsCache = []
            salaryRowsSignature = nil
            return
        }
        guard showsSalaryCalculator else {
            salaryRowsCache = []
            salaryRowsSignature = nil
            return
        }
        guard employerExpanded, showDeferredEmployerContent else {
            return
        }
        let context = makeSalaryCalculationContext(subjectID: option.id, calculator: calculatorForPersistence())
        guard context.birthDate != nil else {
            salaryRowsCache = []
            salaryRowsSignature = context.signature
            return
        }
        guard salaryRowsSignature != context.signature || salaryRowsCache.count != context.years.count else {
            return
        }
        let task = DispatchWorkItem {
            let startedAt = CFAbsoluteTimeGetCurrent()
            let rows = calculateSalaryRows(using: context)
            salaryRowsCache = rows
            salaryRowsSignature = context.signature
            store.appendPerformanceDiagnostic(
                String(
                    format: "organization-salary-results-ready organization=%@ rows=%ld total_ms=%.2f",
                    option.nameSv,
                    rows.count,
                    (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
                )
            )
        }
        salaryRowsRefreshTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: task)
    }

    private var linkedAssociationConferenceContributions: [CVConferenceContribution] {
        let congressIDs = Set(option.congresses.map(\.id))
        return store.cvConferenceContributions
            .filter { contribution in
                if contribution.congressOrganizationID == option.id {
                    return true
                }
                if let congressID = contribution.congressID, congressIDs.contains(congressID) {
                    return true
                }
                return false
            }
            .sorted(by: associationContributionSortOrder)
    }

    private func associationContributionSortOrder(_ lhs: CVConferenceContribution, _ rhs: CVConferenceContribution) -> Bool {
        let left = DateParsers.isoDay.date(from: lhs.to.nonEmpty ?? lhs.from) ?? .distantPast
        let right = DateParsers.isoDay.date(from: rhs.to.nonEmpty ?? rhs.from) ?? .distantPast
        if left != right {
            return left > right
        }
        return (lhs.localizedTitle(language: language).nonEmpty ?? lhs.displayTitle)
            .localizedStandardCompare(rhs.localizedTitle(language: language).nonEmpty ?? rhs.displayTitle) == .orderedAscending
    }

    private func syncSalaryBirthDateFromCurrentUser() {
        guard option.usesAsApplicationSalaryCalculator,
              let currentUserBirthDate,
              salaryCalculator.birthDate != currentUserBirthDate else { return }
        salaryCalculator.birthDate = currentUserBirthDate
    }

    private static func defaultSalaryCalculator(for option: OrganizationRecord) -> ManagerSalaryCalculator {
        let baseCalculator: ManagerSalaryCalculator = {
            if let existing = option.salaryCalculator {
                return existing
            }
            var calculator = option.usesAsApplicationSalaryCalculator
                ? ManagerSalaryCalculator.defaultSalaryCalculatorTemplate
                : ManagerSalaryCalculator.empty
            calculator.birthDate = ""
            return calculator
        }()
        if option.usesAsApplicationSalaryCalculator {
            return formattedCalculator(mergedWithTemplateDefaults(baseCalculator))
        }
        return formattedCalculator(baseCalculator)
    }

    private static func mergedWithTemplateDefaults(_ current: ManagerSalaryCalculator) -> ManagerSalaryCalculator {
        let baseline = ManagerSalaryCalculator.defaultSalaryCalculatorTemplate
        var merged = current
        merged.birthDate = current.birthDate
        merged.annualIncreaseAfterCurrentYearPercent = current.annualIncreaseAfterCurrentYearPercent.nonEmpty ?? baseline.annualIncreaseAfterCurrentYearPercent
        merged.monthlySalaryPeriods = mergePeriods(current: current.monthlySalaryPeriods, defaults: baseline.monthlySalaryPeriods)
        merged.employerFeePeriods = mergePeriods(current: current.employerFeePeriods, defaults: baseline.employerFeePeriods)
        merged.regionalCostPeriods = mergePeriods(current: current.regionalCostPeriods, defaults: baseline.regionalCostPeriods)
        merged.overheadPeriods = mergePeriods(current: current.overheadPeriods, defaults: baseline.overheadPeriods)
        return merged
    }

    private static func mergePeriods(current: [SalaryCalculatorPeriod], defaults: [SalaryCalculatorPeriod]) -> [SalaryCalculatorPeriod] {
        var merged = current.filter {
            $0.value.nonEmpty != nil || $0.from.nonEmpty != nil || $0.to.nonEmpty != nil
        }
        if merged.isEmpty {
            return defaults
        }
        let existingByID = Dictionary(uniqueKeysWithValues: merged.map { ($0.id, $0) })
        let existingByKey = Dictionary(uniqueKeysWithValues: merged.map { ("\(normalizedDateInput($0.from))|\(normalizedDateInput($0.to))", $0) })
        for period in defaults {
            if let existing = existingByID[period.id] {
                if existing.value.nonEmpty == nil,
                   let index = merged.firstIndex(where: { $0.id == existing.id }) {
                    merged[index] = SalaryCalculatorPeriod(
                        id: existing.id,
                        value: period.value,
                        from: existing.from.nonEmpty ?? period.from,
                        to: existing.to.nonEmpty ?? period.to
                    )
                }
                continue
            }
            let key = "\(normalizedDateInput(period.from))|\(normalizedDateInput(period.to))"
            if let existing = existingByKey[key] {
                if existing.value.nonEmpty == nil,
                   let index = merged.firstIndex(where: { $0.id == existing.id }) {
                    merged[index] = SalaryCalculatorPeriod(
                        id: existing.id,
                        value: period.value,
                        from: existing.from.nonEmpty ?? period.from,
                        to: existing.to.nonEmpty ?? period.to
                    )
                }
            }
        }
        return merged.sorted {
            let left = DateParsers.isoDay.date(from: normalizedDateInput($0.from)) ?? .distantFuture
            let right = DateParsers.isoDay.date(from: normalizedDateInput($1.from)) ?? .distantFuture
            return left < right
        }
    }

    private static func formattedCalculator(_ calculator: ManagerSalaryCalculator) -> ManagerSalaryCalculator {
        var formatted = calculator
        formatted.monthlySalaryPeriods = calculator.monthlySalaryPeriods.map {
            SalaryCalculatorPeriod(id: $0.id, value: formatCurrencyInput($0.value), from: normalizedDateInput($0.from), to: normalizedDateInput($0.to))
        }
        formatted.employerFeePeriods = calculator.employerFeePeriods.map {
            SalaryCalculatorPeriod(id: $0.id, value: formatPercentageInput($0.value), from: normalizedDateInput($0.from), to: normalizedDateInput($0.to))
        }
        formatted.regionalCostPeriods = calculator.regionalCostPeriods.map {
            SalaryCalculatorPeriod(id: $0.id, value: formatPercentageInput($0.value), from: normalizedDateInput($0.from), to: normalizedDateInput($0.to))
        }
        formatted.overheadPeriods = calculator.overheadPeriods.map {
            SalaryCalculatorPeriod(id: $0.id, value: formatPercentageInput($0.value), from: normalizedDateInput($0.from), to: normalizedDateInput($0.to))
        }
        formatted.annualIncreaseAfterCurrentYearPercent = formatPercentageInput(calculator.annualIncreaseAfterCurrentYearPercent)
        formatted.allocationPercent = formatPercentageInput(calculator.allocationPercent)
        formatted.allocationMonths = formatCountInput(calculator.allocationMonths)
        formatted.itInfrastructureFeePeriods = []
        formatted.listedPatientCountPeriods = []
        return formatted
    }

    private static func mergedSharedCostPeriods(from calculator: ManagerSalaryCalculator) -> [SalarySharedCostPeriod] {
        OrganizationSalaryCostRows.mergedSharedCostPeriods(from: calculator)
    }

    private static func normalizedDateInput(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        if digits.count == 8 {
            let year = String(digits.prefix(4))
            let month = String(digits.dropFirst(4).prefix(2))
            let day = String(digits.suffix(2))
            return "\(year)-\(month)-\(day)"
        }
        return trimmed
    }
}

/// Results the organization page derives from the store, kept until their
/// inputs change (see LocalizedOptionDetailView.linkedInstitutionResearchers).
final class OrganizationDetailDerivedCache {
    struct LinkedResearchersKey: Equatable {
        let organizationID: String
        let nameSv: String
        let nameEn: String
        let language: AppLanguage
        let researchersGeneration: Int
    }

    struct LinkedResearcherEntry {
        let author: PublicationAuthor
        let subtitle: String
    }

    var linkedResearchersKey: LinkedResearchersKey?
    var linkedResearchers: [LinkedResearcherEntry] = []
}

private struct SalaryCalculationRow: Identifiable {
    let year: Int
    let vacationDays: Int
    let totalAnnualCost: Double
    let annualSelectedCost: Double
    let totalSelectedCost: Double

    var id: Int { year }
}

/// One column of the organization editor's cost matrix: the employer fee,
/// regional shared costs and overhead for one period.
struct SalarySharedCostPeriod: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var from: String = ""
    var to: String = ""
    var employerFee: String = ""
    var regionalCost: String = ""
    var itInfrastructureFee: String = ""
    var listedPatientCount: String = ""
    var overhead: String = ""
}

/// Turns a salary calculator's three cost lists into the editor's matrix
/// columns and back. Opening and leaving an organization without changes
/// must give back exactly the stored calculator: the columns keep the stored
/// periods' ids. They used to get new random ids each time, so every employer
/// looked edited and leaving it saved the whole organization list (seen in
/// the timing log as an organizations save on each click in the list).
enum OrganizationSalaryCostRows {
    static func mergedSharedCostPeriods(from calculator: ManagerSalaryCalculator) -> [SalarySharedCostPeriod] {
        var merged: [String: SalarySharedCostPeriod] = [:]

        func upsert(_ periods: [SalaryCalculatorPeriod], write: (inout SalarySharedCostPeriod, String) -> Void) {
            for period in periods {
                let key = "\(normalizedDateInput(period.from))|\(normalizedDateInput(period.to))"
                var row = merged[key] ?? SalarySharedCostPeriod(
                    id: period.id.isEmpty ? UUID().uuidString : period.id,
                    from: normalizedDateInput(period.from),
                    to: normalizedDateInput(period.to)
                )
                write(&row, period.value)
                merged[key] = row
            }
        }

        upsert(calculator.employerFeePeriods) { $0.employerFee = $1 }
        upsert(calculator.regionalCostPeriods) { $0.regionalCost = $1 }
        upsert(calculator.overheadPeriods) { $0.overhead = $1 }

        let rows = merged.values.sorted {
            let left = DateParsers.isoDay.date(from: $0.from) ?? .distantFuture
            let right = DateParsers.isoDay.date(from: $1.from) ?? .distantFuture
            if left != right {
                return left < right
            }
            // Equal start dates (or none) keep one fixed order instead of
            // the dictionary's, which differs between runs.
            if $0.to != $1.to {
                return $0.to < $1.to
            }
            return $0.id < $1.id
        }
        return rows.isEmpty ? [SalarySharedCostPeriod()] : rows
    }

    /// The calculator with its three cost lists taken from the matrix
    /// columns (one period per column and list, sharing the column's id).
    static func calculator(
        _ calculator: ManagerSalaryCalculator,
        applying periods: [SalarySharedCostPeriod]
    ) -> ManagerSalaryCalculator {
        var updated = calculator
        updated.employerFeePeriods = periods.map {
            SalaryCalculatorPeriod(id: $0.id, value: $0.employerFee, from: $0.from, to: $0.to)
        }
        updated.regionalCostPeriods = periods.map {
            SalaryCalculatorPeriod(id: $0.id, value: $0.regionalCost, from: $0.from, to: $0.to)
        }
        updated.itInfrastructureFeePeriods = []
        updated.listedPatientCountPeriods = []
        updated.overheadPeriods = periods.map {
            SalaryCalculatorPeriod(id: $0.id, value: $0.overhead, from: $0.from, to: $0.to)
        }
        return updated
    }

    static func normalizedDateInput(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        if digits.count == 8 {
            let year = String(digits.prefix(4))
            let month = String(digits.dropFirst(4).prefix(2))
            let day = String(digits.suffix(2))
            return "\(year)-\(month)-\(day)"
        }
        return trimmed
    }
}

private struct SalaryCalculatorCompactField<Content: View>: View {
    let title: String
    let width: CGFloat?
    @ViewBuilder let content: Content

    var body: some View {
        AppCompactField(title, width: width) {
            content
        }
    }
}


private struct SalaryCalculatorSalaryMatrixSection: View {
    let title: String
    let language: AppLanguage
    @Binding var periods: [SalaryCalculatorPeriod]
    @State private var editablePeriods: [SalaryCalculatorPeriod]

    private let dateColumnWidth: CGFloat = 110
    private let valueColumnWidth: CGFloat = 110
    private let rowHeight: CGFloat = AppPalette.fieldMinHeight
    private let leftLabelWidth: CGFloat = 104

    init(title: String, language: AppLanguage, periods: Binding<[SalaryCalculatorPeriod]>) {
        self.title = title
        self.language = language
        _periods = periods
        _editablePeriods = State(initialValue: Self.makeEditablePeriods(periods.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ContentSectionTitleView(title: title)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    matrixRowLabel(language.text("Start date", "Startdatum"))
                    matrixRowLabel(language.text("End date", "Slutdatum"))
                    matrixRowLabel(language.text("Monthly salary", "Månadslön"))
                    Color.clear.frame(height: rowHeight)
                }
                .frame(width: leftLabelWidth, alignment: .leading)

                ScrollToTrailingOnAppear(showsIndicators: false, targetID: "salary-matrix-end") {
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(Array(editablePeriods.enumerated()), id: \.element.id) { index, period in
                            let isPlaceholder = Self.isEmpty(period)
                            VStack(alignment: .leading, spacing: 6) {
                                CommitDateFieldWithTodayButton(
                                    placeholder: "YYYY-MM-DD",
                                    text: binding(for: index, keyPath: \.from),
                                    formatter: normalizeSalaryDateInput,
                                    width: dateColumnWidth,
                                    height: rowHeight,
                                    showsTodayButton: false
                                )

                                CommitDateFieldWithTodayButton(
                                    placeholder: "YYYY-MM-DD",
                                    text: binding(for: index, keyPath: \.to),
                                    formatter: normalizeSalaryDateInput,
                                    width: dateColumnWidth,
                                    height: rowHeight,
                                    showsTodayButton: false
                                )

                                CommitFormattingTextField(
                                    placeholder: "SEK",
                                    text: binding(for: index, keyPath: \.value),
                                    formatter: formatCurrencyInput,
                                    showsRenewedSurface: false,
                                    isBordered: false
                                )
                                .frame(minHeight: 18)
                                .appTextInputChrome(
                                    horizontalPadding: AppPalette.textFieldHorizontalPadding,
                                    verticalPadding: AppPalette.textFieldVerticalPadding,
                                    minHeight: rowHeight,
                                    fillsWidth: false
                                )
                                .frame(width: valueColumnWidth)

                                if isPlaceholder {
                                    Color.clear
                                        .frame(width: valueColumnWidth, height: rowHeight)
                                } else {
                                    Button(role: .destructive) {
                                        deletePeriod(id: period.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(AppPalette.actionDelete)
                                            .frame(width: valueColumnWidth, height: rowHeight, alignment: .center)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Color.clear
                            .frame(width: 1, height: 1)
                            .id("salary-matrix-end")
                    }
                }
            }
        }
        .onChange(of: periods) { _, newValue in
            let realEditablePeriods = editablePeriods.filter { !Self.isEmpty($0) }
            if realEditablePeriods != newValue {
                editablePeriods = makeEditablePeriodsPreservingPlaceholder(newValue)
            }
        }
    }

    private func binding(for index: Int, keyPath: WritableKeyPath<SalaryCalculatorPeriod, String>) -> Binding<String> {
        Binding(
            get: {
                guard editablePeriods.indices.contains(index) else { return "" }
                return editablePeriods[index][keyPath: keyPath]
            },
            set: { newValue in
                guard editablePeriods.indices.contains(index) else { return }
                let previousFrom = editablePeriods[index].from
                editablePeriods[index][keyPath: keyPath] = newValue
                if keyPath == \SalaryCalculatorPeriod.from,
                   let shiftedTo = shiftedDateRangeEnd(
                       previousStart: previousFrom,
                       newStart: newValue,
                       currentEnd: editablePeriods[index].to
                   ) {
                    editablePeriods[index].to = shiftedTo
                }
                syncPeriods()
            }
        )
    }

    private func deletePeriod(id: String) {
        editablePeriods.removeAll { $0.id == id }
        syncPeriods()
    }

    private func syncPeriods() {
        let realPeriods = editablePeriods.filter { !Self.isEmpty($0) }
        periods = realPeriods
        editablePeriods = makeEditablePeriodsPreservingPlaceholder(realPeriods)
    }

    private func makeEditablePeriodsPreservingPlaceholder(_ periods: [SalaryCalculatorPeriod]) -> [SalaryCalculatorPeriod] {
        Self.makeEditablePeriods(
            periods,
            placeholderID: editablePeriods.first(where: { Self.isEmpty($0) })?.id
        )
    }

    private static func makeEditablePeriods(_ periods: [SalaryCalculatorPeriod], placeholderID: String? = nil) -> [SalaryCalculatorPeriod] {
        let retainedPlaceholderID = periods.first(where: { isEmpty($0) })?.id ?? placeholderID ?? UUID().uuidString
        return periods.filter { !isEmpty($0) } + [SalaryCalculatorPeriod(id: retainedPlaceholderID)]
    }

    private static func isEmpty(_ period: SalaryCalculatorPeriod) -> Bool {
        period.value.trimmedOrNil == nil &&
        period.from.trimmedOrNil == nil &&
        period.to.trimmedOrNil == nil
    }

    private func matrixRowLabel(_ text: String) -> some View {
        Text(text)
            .appTypography(.tableHeader)
            .foregroundStyle(.primary)
            .offset(y: -1)
            .frame(width: leftLabelWidth, height: rowHeight, alignment: .leading)
    }
}

private struct SalaryCalculatorSharedCostMatrixSection: View {
    let title: String
    @Binding var periods: [SalarySharedCostPeriod]
    let language: AppLanguage
    @State private var editablePeriods: [SalarySharedCostPeriod]

    private let columnWidth: CGFloat = 110
    private let rowHeight: CGFloat = AppPalette.fieldMinHeight
    private let leftLabelWidth: CGFloat = 214

    init(title: String, periods: Binding<[SalarySharedCostPeriod]>, language: AppLanguage) {
        self.title = title
        _periods = periods
        self.language = language
        _editablePeriods = State(initialValue: Self.makeEditablePeriods(periods.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ContentSectionTitleView(title: title)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    matrixRowLabel(language.text("Period from", "Period från"))
                    matrixRowLabel(language.text("Period to", "Period till"))
                    matrixRowLabel(language.text("Employer fee", "Arbetsgivaravgift"))
                    matrixRowLabel(language.text("Regional shared costs", "Regiongemensamma kostnader"))
                    matrixRowLabel(language.text("Overhead", "Overhead"))
                    Color.clear.frame(height: rowHeight)
                }
                .frame(width: leftLabelWidth, alignment: .leading)

                ScrollToTrailingOnAppear(showsIndicators: true, targetID: "shared-cost-matrix-end") {
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(Array(editablePeriods.enumerated()), id: \.element.id) { index, period in
                            let isPlaceholder = Self.isEmpty(period)
                            VStack(alignment: .leading, spacing: 6) {
                                CommitDateFieldWithTodayButton(
                                    placeholder: "YYYY-MM-DD",
                                    text: binding(for: index, keyPath: \.from),
                                    formatter: normalizeSalaryDateInput,
                                    width: columnWidth,
                                    height: rowHeight,
                                    showsTodayButton: false
                                )

                                CommitDateFieldWithTodayButton(
                                    placeholder: "YYYY-MM-DD",
                                    text: binding(for: index, keyPath: \.to),
                                    formatter: normalizeSalaryDateInput,
                                    width: columnWidth,
                                    height: rowHeight,
                                    showsTodayButton: false
                                )

                                plainValueField(
                                    text: binding(for: index, keyPath: \.employerFee),
                                    formatter: formatPercentageInput
                                )
                                plainValueField(
                                    text: binding(for: index, keyPath: \.regionalCost),
                                    formatter: formatPercentageInput
                                )
                                plainValueField(
                                    text: binding(for: index, keyPath: \.overhead),
                                    formatter: formatPercentageInput
                                )

                                if isPlaceholder {
                                    Color.clear
                                        .frame(width: columnWidth, height: rowHeight)
                                } else {
                                    Button(role: .destructive) {
                                        deletePeriod(id: period.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(AppPalette.actionDelete)
                                            .frame(width: columnWidth, height: rowHeight, alignment: .center)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Color.clear
                            .frame(width: 1, height: 1)
                            .id("shared-cost-matrix-end")
                    }
                }
            }
        }
        .onChange(of: periods) { _, newValue in
            let realEditablePeriods = editablePeriods.filter { !Self.isEmpty($0) }
            if realEditablePeriods != newValue {
                editablePeriods = makeEditablePeriodsPreservingPlaceholder(newValue)
            }
        }
    }

    private func binding(for index: Int, keyPath: WritableKeyPath<SalarySharedCostPeriod, String>) -> Binding<String> {
        Binding(
            get: {
                guard editablePeriods.indices.contains(index) else { return "" }
                return editablePeriods[index][keyPath: keyPath]
            },
            set: { newValue in
                guard editablePeriods.indices.contains(index) else { return }
                let previousFrom = editablePeriods[index].from
                editablePeriods[index][keyPath: keyPath] = newValue
                if keyPath == \SalarySharedCostPeriod.from,
                   let shiftedTo = shiftedDateRangeEnd(
                       previousStart: previousFrom,
                       newStart: newValue,
                       currentEnd: editablePeriods[index].to
                   ) {
                    editablePeriods[index].to = shiftedTo
                }
                syncPeriods()
            }
        )
    }

    private func deletePeriod(id: String) {
        editablePeriods.removeAll { $0.id == id }
        syncPeriods()
    }

    private func syncPeriods() {
        let realPeriods = editablePeriods.filter { !Self.isEmpty($0) }
        periods = realPeriods
        editablePeriods = makeEditablePeriodsPreservingPlaceholder(realPeriods)
    }

    private func makeEditablePeriodsPreservingPlaceholder(_ periods: [SalarySharedCostPeriod]) -> [SalarySharedCostPeriod] {
        Self.makeEditablePeriods(
            periods,
            placeholderID: editablePeriods.first(where: { Self.isEmpty($0) })?.id
        )
    }

    private static func makeEditablePeriods(_ periods: [SalarySharedCostPeriod], placeholderID: String? = nil) -> [SalarySharedCostPeriod] {
        let retainedPlaceholderID = periods.first(where: { isEmpty($0) })?.id ?? placeholderID ?? UUID().uuidString
        return periods.filter { !isEmpty($0) } + [SalarySharedCostPeriod(id: retainedPlaceholderID)]
    }

    private static func isEmpty(_ period: SalarySharedCostPeriod) -> Bool {
        period.from.trimmedOrNil == nil &&
        period.to.trimmedOrNil == nil &&
        period.employerFee.trimmedOrNil == nil &&
        period.regionalCost.trimmedOrNil == nil &&
        period.overhead.trimmedOrNil == nil
    }

    @ViewBuilder
    private func plainValueField(text: Binding<String>, formatter: @escaping (String) -> String) -> some View {
        CommitFormattingTextField(
            placeholder: "",
            text: text,
            formatter: formatter,
            showsRenewedSurface: false,
            isBordered: false
        )
        .frame(minHeight: 18)
        .appTextInputChrome(
            horizontalPadding: AppPalette.textFieldHorizontalPadding,
            verticalPadding: AppPalette.textFieldVerticalPadding,
            minHeight: rowHeight,
            fillsWidth: false
        )
        .frame(width: columnWidth)
    }

    private func matrixRowLabel(_ text: String) -> some View {
        Text(text)
            .appTypography(.tableHeader)
            .foregroundStyle(.primary)
            .offset(y: -1)
            .frame(width: leftLabelWidth, height: rowHeight, alignment: .leading)
    }
}

private struct SalaryCalculatorResultsSection: View {
    let rows: [SalaryCalculationRow]
    let language: AppLanguage
    let allocationPercentText: String
    let allocationMonthsText: String

    private let headerRowHeight: CGFloat = 24
    private let valueRowHeight: CGFloat = 24
    private let bottomSafetyPadding: CGFloat = 26

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var sectionHeight: CGFloat {
        headerRowHeight + (valueRowHeight * 5) + bottomSafetyPadding
    }

    private var annualSelectedTitle: String {
        let fallback = language.text("selected unit", "vald enhet")
        let percent = allocationPercentText.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? fallback
        return language.text("Annual cost \(percent)", "Årskostnad \(percent)")
    }

    private var monthlySelectedTitle: String {
        let fallback = language.text("selected unit", "vald enhet")
        let percent = allocationPercentText.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? fallback
        return language.text("Monthly cost \(percent)", "Månadskostnad \(percent)")
    }

    private var totalSelectedTitle: String {
        let fallbackPercent = language.text("selected unit", "vald enhet")
        let fallbackMonths = language.text("selected months", "valda månader")
        let percent = allocationPercentText.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? fallbackPercent
        let months = allocationMonthsText.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? fallbackMonths
        return language.text("Total cost \(percent) for \(months) months", "Totalkostnad \(percent) i \(months) månader")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ContentSectionTitleView(title: language.text("Salary calculation", "Lönekalkyl"))
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    header("")
                        .frame(height: headerRowHeight)
                    metricLabel(language.text("Annual cost 100%", "Årskostnad 100 %"))
                    metricLabel(annualSelectedTitle)
                    metricLabel(language.text("Monthly cost 100%", "Månadskostnad 100 %"))
                    metricLabel(monthlySelectedTitle)
                    metricLabel(totalSelectedTitle)
                }
                .frame(width: 230, alignment: .leading)
                .frame(height: sectionHeight, alignment: .top)

                ScrollToTrailingOnAppear(showsIndicators: false, targetID: "salary-results-end") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 14) {
                            ForEach(rows) { row in
                                yearHeader(row.year)
                                    .frame(width: 120, alignment: .leading)
                            }
                        }
                        valueRow { row in
                            CurrencyFormatter.format(row.totalAnnualCost)
                        }
                        valueRow { row in
                            row.annualSelectedCost > 0 ? CurrencyFormatter.format(row.annualSelectedCost) : "—"
                        }
                        valueRow { row in
                            CurrencyFormatter.format(row.totalAnnualCost / 12)
                        }
                        valueRow { row in
                            row.annualSelectedCost > 0 ? CurrencyFormatter.format(row.annualSelectedCost / 12) : "—"
                        }
                        valueRow { row in
                            row.totalSelectedCost > 0 ? CurrencyFormatter.format(row.totalSelectedCost) : "—"
                        }
                        Color.clear
                            .frame(width: 1, height: 1)
                            .id("salary-results-end")
                    }
                    .padding(.bottom, bottomSafetyPadding)
                }
                .frame(height: sectionHeight, alignment: .top)
            }
            .padding(.bottom, 34)
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .appTypography(.fieldLabel)
            .foregroundStyle(AppPalette.appText)
    }

    private func yearHeader(_ year: Int) -> some View {
        Text(String(year))
            .appTypography(.tableHeader)
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(year == currentYear ? AppPalette.chartGreen : .clear, lineWidth: 1.8)
            )
    }

    private func metricLabel(_ title: String) -> some View {
        Text(title)
            .appTypography(.tableHeader)
            .frame(height: valueRowHeight, alignment: .leading)
    }

    private func valueRow(_ value: @escaping (SalaryCalculationRow) -> String) -> some View {
        HStack(spacing: 14) {
            ForEach(rows) { row in
                Text(value(row))
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 120, alignment: .leading)
            }
        }
        .frame(height: valueRowHeight, alignment: .leading)
    }
}

func normalizeSalaryDateInput(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let digits = trimmed.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
    if digits.count == 8 {
        let year = String(digits.prefix(4))
        let month = String(digits.dropFirst(4).prefix(2))
        let day = String(digits.suffix(2))
        return "\(year)-\(month)-\(day)"
    }
    return trimmed
}

private func formatCurrencyInput(_ raw: String) -> String {
    guard let value = GrantParsing.numericValue(from: raw) else { return raw.trimmingCharacters(in: .whitespacesAndNewlines) }
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "sv_SE")
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 0
    formatter.groupingSeparator = " "
    formatter.usesGroupingSeparator = true
    return "\(formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))") kr"
}

private func formatCurrencyInputAllowingDecimals(_ raw: String) -> String {
    guard let value = GrantParsing.numericValue(from: raw) else { return raw.trimmingCharacters(in: .whitespacesAndNewlines) }
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "sv_SE")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = value.rounded() == value ? 0 : 1
    formatter.maximumFractionDigits = 2
    formatter.groupingSeparator = " "
    formatter.usesGroupingSeparator = true
    return "\(formatter.string(from: NSNumber(value: value)) ?? "\(value)") kr"
}

func formatPercentageInput(_ raw: String) -> String {
    let formatted = AppFieldParsers.canonicalPercentage(raw)
    return formatted.isEmpty ? formatted : "\(formatted) %"
}

private func formatCountInput(_ raw: String) -> String {
    AppFieldParsers.canonicalDecimal(raw, maximumFractionDigits: 0)
}


private struct ScrollToTrailingOnAppear<Content: View>: View {
    let showsIndicators: Bool
    let targetID: String
    @ViewBuilder let content: Content

    @State private var hasScrolled = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: showsIndicators) {
                content
            }
            .onAppear {
                guard !hasScrolled else { return }
                hasScrolled = true
                DispatchQueue.main.async {
                    withAnimation(nil) {
                        proxy.scrollTo(targetID, anchor: .trailing)
                    }
                }
            }
        }
    }
}

private struct OrganizationDirectoryRow: Identifiable {
    let id: String
    let displayName: String
    let flag: String
    let icons: [String]
    let category: String
    let roles: [OrganizationRole]
    let roleSummary: String
    let applicationCount: Int
    let waitingCount: Int
    let grantedCount: Int
    let rejectedCount: Int
    let hasLinkedRecords: Bool
    let isGrantProvider: Bool
    let isStewardshipOrganization: Bool
    let isManagerOrganization: Bool

    var sortName: String { displayName }
    var scopeLabel: String { category.isEmpty ? "—" : category }
    var grantRateSortValue: Double {
        guard applicationCount > 0 else { return 0 }
        return Double(grantedCount) / Double(applicationCount)
    }
    var grantRateText: String {
        guard applicationCount > 0 else { return "0%" }
        return "\(Int((grantRateSortValue * 100).rounded()))%"
    }
}

private func localizedOrganizationRole(_ role: OrganizationRole, language: AppLanguage) -> String {
    switch role {
    case .grantProvider:
        return fixedDropdownText("organizationRole.grantProvider", language: language, english: "Grant provider", swedish: "Anslagsgivare")
    case .fundManager:
        return fixedDropdownText("organizationRole.fundManager", language: language, english: "Fund manager", swedish: "Medelsförvaltare")
    case .employer:
        return fixedDropdownText("organizationRole.employer", language: language, english: "Employer", swedish: "Arbetsgivare")
    case .institution:
        return fixedDropdownText("organizationRole.institution", language: language, english: "Higher education institution", swedish: "Lärosäte")
    case .association:
        return fixedDropdownText("organizationRole.association", language: language, english: "Association", swedish: "Förening")
    case .company:
        return fixedDropdownText("organizationRole.company", language: language, english: "Company", swedish: "Företag")
    }
}

extension OrganizationRecord {
    var isGrantProvider: Bool {
        roles.contains(.grantProvider)
    }

    var isStewardshipOrganization: Bool {
        roles.contains(.fundManager) || roles.contains(.employer) || roles.contains(.institution) || roles.contains(.association) || roles.contains(.company)
    }

    var isManagerOrganization: Bool {
        roles.contains(.fundManager) || roles.contains(.employer)
    }

    var organizationCategoryIcon: String? {
        switch category {
        case "National":
            return "🇸🇪"
        case "International":
            return "🌐"
        default:
            return nil
        }
    }

    func roleSummaryText(language: AppLanguage) -> String {
        let labels = roles.compactMap { role -> String? in
            switch role {
            case .grantProvider:
                return fixedDropdownText("organizationRole.grantProvider", language: language, english: "Grant provider", swedish: "Anslagsgivare")
            case .fundManager:
                return fixedDropdownText("organizationRole.fundManager", language: language, english: "Fund manager", swedish: "Medelsförvaltare")
            case .employer:
                return fixedDropdownText("organizationRole.employer", language: language, english: "Employer", swedish: "Arbetsgivare")
            case .institution:
                return fixedDropdownText("organizationRole.institution", language: language, english: "Higher education institution", swedish: "Lärosäte")
            case .association:
                return fixedDropdownText("organizationRole.association", language: language, english: "Association", swedish: "Förening")
            case .company:
                return fixedDropdownText("organizationRole.company", language: language, english: "Company", swedish: "Företag")
            }
        }
        return labels.joined(separator: " • ")
    }
}
