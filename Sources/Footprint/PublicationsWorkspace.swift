import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers




private struct PublicationListRow: Identifiable {
    enum SourceKind {
        case publication
        case otherPublication
    }

    let id: String
    let sourceKind: SourceKind
    let publication: PublicationRecord?
    let otherPublication: CVOtherPublicationEntry?
    let searchBlob: String
    let normalizedSearchBlob: String
    let statusLabel: String
    let workflowStatus: PublicationWorkflowStatus?
    let publicationType: String
    let title: String
    let journal: String
    let sortYear: Int
    let statusSortRank: Int
    let norwegianSortableValue: Double
    let jifSortableValue: Double
    let jifQuartileSortRank: Int
    let position: String
    let independence: String
    let geography: String
    let jifMetric: PublicationMetricValue?
    let jifBackgroundColor: Color?
    let norwegianMetric: PublicationMetricValue?
    let norwegianBackgroundColor: Color?
    let isPeerReviewed: Bool
    let peerReviewLabel: String

    var titleSortKey: String {
        Self.sortKey(title)
    }

    var journalSortKey: String {
        Self.sortKey(journal)
    }

    var peerReviewSortRank: Int {
        isPeerReviewed ? 0 : 1
    }

    var positionSortRank: Int {
        switch position {
        case "Single":
            return 0
        case "First":
            return 1
        case "Last":
            return 2
        case "Middle":
            return 3
        default:
            return 9
        }
    }

    var independenceSortRank: Int {
        switch independence {
        case "Yes":
            return 0
        case "No":
            return 1
        default:
            return 9
        }
    }

    private static func sortKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

struct PublicationsWorkspaceView: View {
    private enum PublicationStatusFilterOption: String, CaseIterable, Identifiable {
        case inPreparation
        case submitted
        case publishedAccepted
        case rejected

        var id: String { rawValue }

        var statusRawValues: Set<String> {
            switch self {
            case .inPreparation:
                return [PublicationStatus.inPreparation.rawValue]
            case .submitted:
                return [PublicationStatus.submitted.rawValue]
            case .publishedAccepted:
                return [PublicationStatus.published.rawValue, PublicationStatus.accepted.rawValue]
            case .rejected:
                return [PublicationStatus.rejected.rawValue]
            }
        }

        func displayName(language: AppLanguage) -> String {
            switch self {
            case .inPreparation:
                return PublicationStatus.inPreparation.displayName(language: language)
            case .submitted:
                return PublicationStatus.submitted.displayName(language: language)
            case .publishedAccepted:
                return language.text("Published/accepted", "Publicerad/accepterad")
            case .rejected:
                return PublicationStatus.rejected.displayName(language: language)
            }
        }
    }

    private enum PublicationTypeFilterOption: String, CaseIterable, Identifiable {
        case original
        case other

        var id: String { rawValue }

        func displayName(language: AppLanguage) -> String {
            switch self {
            case .original:
                return language.text("Original", "Original")
            case .other:
                return language.text("Other", "Övrigt")
            }
        }
    }

    private enum PublicationListSortColumn: String, CaseIterable, Hashable {
        case status
        case title
        case peerReview
        case year
        case journal
        case jif
        case quartile
        case norwegian
        case position
        case independent

        var defaultAscending: Bool {
            switch self {
            case .status, .title, .peerReview, .quartile, .journal, .position, .independent:
                return true
            case .year, .jif, .norwegian:
                return false
            }
        }
    }

    private struct PublicationListSortCriterion: AppListSortCriterion {
        let column: PublicationListSortColumn
        var ascending: Bool
    }

    let store: GrantDataStore
    @Binding var preset: PublicationListPreset?
    let newRecordTrigger: Int
    let isActive: Bool
    @WorkspaceFilterState("Publications.Filter.Search") private var searchText = ""
    @WorkspaceFilterState("Publications.Filter.Status") private var selectedStatusFilters: Set<String> = []
    @WorkspaceFilterState("Publications.Filter.Type") private var selectedTypeFilters: Set<String> = []
    @WorkspaceFilterState("Publications.Filter.PeerReview") private var selectedPeerReviewFilters: Set<String> = []
    @WorkspaceFilterState("Publications.Filter.IndependentLead") private var showsOnlyIndependentLeadAfterPhD = false
    @State private var selectedPublicationID: String?
    @State private var publicationRows: [PublicationListRow] = []
    @State private var baseFilteredPublicationRows: [PublicationListRow] = []
    @State private var filteredPublicationRows: [PublicationListRow] = []
    @State private var publicationRowCache: [String: PublicationListRow] = [:]
    @State private var publicationRowSignatures: [String: String] = [:]
    @State private var searchRebuildTask: DispatchWorkItem?
    @State private var rowsRebuildTask: DispatchWorkItem?
    @State private var publicationMetricDistributionCache = PublicationMetricDistributionCache()
    @State private var pendingSelectionMeasurementID: String?
    @State private var pendingSelectionStartedAt: CFAbsoluteTime?
    @State private var publicationSelectionCoordinator = AppSelectionCoordinator<String>()
    @State private var lastPublicationSearchQuery = SearchFilterQuery(raw: "")
    @State private var lastPublicationNonSearchFilterSignature = ""
    @State private var publicationRowsAppliedGeneration = 0
    @State private var publicationRowsBuildToken: UInt = 0
    @State private var publicationSortHistory: [PublicationListSortCriterion] = ListSortPersistence.load(
        defaultsKey: "PublicationsListSort",
        defaultValue: [PublicationListSortCriterion(column: .status, ascending: true)]
    )
    @State private var needsPublicationRowsRefreshWhenActive = false
    @State private var needsPublicationFilterRebuildWhenActive = false
    @State private var pendingRoutePublicationID: String?
    @State private var publicationIdleWarmupTask: DispatchWorkItem?
    @State private var publicationPipelineExpanded = false

    private var nonSearchMatchingPublicationRows: [PublicationListRow] {
        publicationRows.filter { row in
            guard let publication = row.publication else { return false }
            let matchesStatus = matchesStatusFilter(publication)
            let matchesType = matchesTypeFilter(publicationType: row.publicationType)
            let matchesSelectedPreset = matchesPublicationPreset(publication)
            let matchesPeerReview = selectedPeerReviewFilters.isEmpty || selectedPeerReviewFilters.contains(row.isPeerReviewed ? "peer" : "nonPeer")
            let matchesIndependentLeadAfterPhD = !showsOnlyIndependentLeadAfterPhD || isIndependentLeadAfterPhD(publication)
            return matchesStatus
                && matchesType
                && matchesSelectedPreset
                && matchesPeerReview
                && matchesIndependentLeadAfterPhD
        }
    }

    private var selectedPublication: PublicationRecord? {
        guard let selectedPublicationID else { return nil }
        return store.publication(id: selectedPublicationID)
    }

    private var sortOrder: [KeyPathComparator<PublicationListRow>] {
        var columns = publicationSortHistory.map(\.column)
        for fallbackColumn in [PublicationListSortColumn.status, .year, .norwegian, .jif, .title] where !columns.contains(fallbackColumn) {
            columns.append(fallbackColumn)
        }

        return columns.flatMap { column in
            let ascending = publicationSortHistory.first(where: { $0.column == column })?.ascending ?? column.defaultAscending
            return publicationPrimarySortComparators(for: column, ascending: ascending)
        }
    }

    private var publicationSortSignature: String {
        publicationSortHistory
            .map { "\($0.column.rawValue):\($0.ascending ? "asc" : "desc")" }
            .joined(separator: "|")
    }

    private var publicationSelectionBinding: Binding<String?> {
        Binding(
            get: { selectedPublicationID },
            set: { newValue in
                handlePublicationSelectionCandidate(newValue)
            }
        )
    }

    private var hasActivePublicationFilters: Bool {
        searchText.nonEmpty != nil
            || !selectedStatusFilters.isEmpty
            || !selectedTypeFilters.isEmpty
            || !selectedPeerReviewFilters.isEmpty
            || showsOnlyIndependentLeadAfterPhD
            || preset != nil
    }

    var body: some View {
        let language = store.language

        GeometryReader { geometry in
            VStack(spacing: 0) {
                publicationPipelineChromeBar(language: language)
                    .zIndex(2)

                ZStack(alignment: .top) {
                    PersistentSplitView(layout: .publications) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(language.text("Publications", "Publikationer"))
                                    .appTypography(.pageTitle)
                                Spacer()
                                Button(language.text("New publication", "Ny publikation")) {
                                    createPublicationRevealingIt()
                                }
                                .appAddButtonStyle()
                            }
                            .frame(minHeight: 42)

                            AppFilterCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    AppFilterRow(
                                        showsClearButton: searchText.nonEmpty != nil,
                                        clearAction: { searchText = "" }
                                    ) {
                                        AppSidebarSearchField(
                                            placeholder: language.text("Search publications", "Sök publikationer"),
                                            text: $searchText
                                        )
                                    }

                                    publicationFilterMatrix(language: language)
                                }
                            }

                            publicationFilteredListBanner(language: language)

                            publicationTable(language: language)

                            ListCountFootnote(displayedCount: filteredPublicationRows.count, totalCount: store.publications.count, language: language)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(AppPalette.sidebarPanelSurface)
                        .onAppear {
                            guard isActive else {
                                needsPublicationRowsRefreshWhenActive = true
                                needsPublicationFilterRebuildWhenActive = true
                                return
                            }
                            publicationMetricDistributionCache = PublicationMetricDistributionCache(journals: store.journals)
                            rebuildPublicationRows()
                            if let route = store.route, route.destination == .publications {
                                resetFiltersForDirectNavigation()
                                rebuildFilteredPublicationRows()
                                setSelectedPublicationID(route.recordID, armLock: true)
                                store.consumeRoute()
                            } else if selectedPublicationID == nil {
                                setSelectedPublicationID(store.lastSelectedRecordID(for: .publications) ?? filteredPublicationRows.first?.id)
                            }
                            applyPresetIfNeeded()
                            schedulePublicationIdleWarmup()
                        }
                        // onReceive, not onChange: onChange only fires when the
                        // body happens to re-evaluate around the mutation, and
                        // a deletion committed from the detail editor left the
                        // list stale until the workspace was re-entered. The
                        // subscription delivers every publish regardless.
                        .onReceive(store.$publicationRecords.dropFirst()) { _ in
                            guard isActive else {
                                needsPublicationRowsRefreshWhenActive = true
                                needsPublicationFilterRebuildWhenActive = true
                                return
                            }
                            schedulePublicationRowsRebuild()
                        }
                        .onReceive(store.$publicationJournals.dropFirst()) { journals in
                            guard isActive else {
                                needsPublicationRowsRefreshWhenActive = true
                                needsPublicationFilterRebuildWhenActive = true
                                return
                            }
                            // The publisher emits at willSet; use the received
                            // value, store.journals still holds the old array.
                            publicationMetricDistributionCache = PublicationMetricDistributionCache(journals: journals)
                            publicationRowCache.removeAll()
                            publicationRowSignatures.removeAll()
                            schedulePublicationRowsRebuild()
                        }
                        .onChange(of: preset) { _, _ in
                            guard isActive else {
                                needsPublicationFilterRebuildWhenActive = true
                                return
                            }
                            applyPresetIfNeeded()
                            rebuildFilteredPublicationRows()
                        }
                        .onChange(of: searchText) { _, _ in
                            guard isActive else {
                                needsPublicationFilterRebuildWhenActive = true
                                return
                            }
                            scheduleFilteredPublicationRowsRebuild()
                        }
                        .onChange(of: selectedStatusFilters) { _, _ in
                            guard isActive else {
                                needsPublicationFilterRebuildWhenActive = true
                                return
                            }
                            rebuildFilteredPublicationRows()
                        }
                        .onChange(of: selectedTypeFilters) { _, _ in
                            guard isActive else {
                                needsPublicationFilterRebuildWhenActive = true
                                return
                            }
                            rebuildFilteredPublicationRows()
                        }
                        .onChange(of: selectedPeerReviewFilters) { _, _ in
                            guard isActive else {
                                needsPublicationFilterRebuildWhenActive = true
                                return
                            }
                            rebuildFilteredPublicationRows()
                        }
                        .onChange(of: showsOnlyIndependentLeadAfterPhD) { _, _ in
                            guard isActive else {
                                needsPublicationFilterRebuildWhenActive = true
                                return
                            }
                            rebuildFilteredPublicationRows()
                        }
                        .onChange(of: publicationSortSignature) { _, _ in
                            guard isActive else {
                                needsPublicationFilterRebuildWhenActive = true
                                return
                            }
                            rebuildFilteredPublicationRows()
                        }
                        .onChange(of: store.route) { _, route in
                            guard let route, route.destination == .publications else { return }
                            if publicationPipelineExpanded {
                                collapsePublicationPipeline()
                            }
                            guard isActive else {
                                pendingRoutePublicationID = route.recordID
                                store.appendPerformanceDiagnostic("publication-route-deferred id=\(route.recordID)")
                                return
                            }
                            resetFiltersForDirectNavigation()
                            rebuildFilteredPublicationRows()
                            setSelectedPublicationID(route.recordID, armLock: true)
                            store.consumeRoute()
                        }
                        .onChange(of: selectedPublicationID) { _, id in
                            guard isActive else { return }
                            store.handlePendingSelectionReturnIfNeeded(for: id, in: .publications)
                            store.rememberSelection(id: id, for: .publications)
                            pendingSelectionMeasurementID = id
                            pendingSelectionStartedAt = CFAbsoluteTimeGetCurrent()
                        }
                        .onChange(of: filteredPublicationRows.map(\.id)) { _, _ in
                            guard isActive else { return }
                            schedulePublicationIdleWarmup()
                        }
                        .onChange(of: newRecordTrigger) { _, _ in
                            guard isActive else { return }
                            createPublicationRevealingIt()
                        }
                        .onChange(of: isActive) { _, active in
                            if active {
                                if needsPublicationRowsRefreshWhenActive {
                                    publicationMetricDistributionCache = PublicationMetricDistributionCache(journals: store.journals)
                                    rebuildPublicationRows()
                                    needsPublicationRowsRefreshWhenActive = false
                                }
                                if needsPublicationFilterRebuildWhenActive {
                                    rebuildFilteredPublicationRows()
                                    needsPublicationFilterRebuildWhenActive = false
                                }
                                if let pendingRoutePublicationID {
                                    resetFiltersForDirectNavigation()
                                    rebuildFilteredPublicationRows()
                                    setSelectedPublicationID(pendingRoutePublicationID, armLock: true)
                                    store.consumeRoute()
                                    self.pendingRoutePublicationID = nil
                                } else if let route = store.route, route.destination == .publications {
                                    resetFiltersForDirectNavigation()
                                    rebuildFilteredPublicationRows()
                                    setSelectedPublicationID(route.recordID, armLock: true)
                                    store.consumeRoute()
                                }
                            } else {
                                clearPublicationFiltersForDeactivationIfNeeded()
                                searchRebuildTask?.cancel()
                                rowsRebuildTask?.cancel()
                                publicationIdleWarmupTask?.cancel()
                                publicationRowsBuildToken &+= 1
                            }
                        }
                        .onDisappear {
                            searchRebuildTask?.cancel()
                            rowsRebuildTask?.cancel()
                            publicationSelectionCoordinator.clear()
                            publicationIdleWarmupTask?.cancel()
                            publicationRowsBuildToken &+= 1
                        }
                    } detail: {
                        if let publication = selectedPublication {
                            PublicationEditorView(
                                store: store,
                                publication: publication,
                                metricDistributionCache: publicationMetricDistributionCache,
                                isActive: isActive,
                                onEditorAppear: { publicationID in
                                    guard pendingSelectionMeasurementID == publicationID,
                                          let pendingSelectionStartedAt else { return }
                                    let duration = (CFAbsoluteTimeGetCurrent() - pendingSelectionStartedAt) * 1000
                                    store.appendPerformanceDiagnostic(
                                        String(
                                            format: "publication-selection-appear publication=%@ appear_ms=%.2f",
                                            publication.title,
                                            duration
                                        )
                                    )
                                },
                                onEditorReady: { publicationID in
                                    guard pendingSelectionMeasurementID == publicationID,
                                          let pendingSelectionStartedAt else { return }
                                    let duration = (CFAbsoluteTimeGetCurrent() - pendingSelectionStartedAt) * 1000
                                    store.appendPerformanceDiagnostic(
                                        String(
                                            format: "publication-selection publication=%@ selection_ms=%.2f",
                                            publication.title,
                                            duration
                                        )
                                    )
                                    releasePublicationSelectionLock(for: publicationID)
                                    self.pendingSelectionMeasurementID = nil
                                    self.pendingSelectionStartedAt = nil
                                }
                            )
                            .id(publication.id)
                            .undoRevealPulse(
                                triggerID: store.undoRevealRequest?.id,
                                isActive: store.undoRevealRequest?.target.matchesWholeRecord(routeDestination: .publications, recordID: publication.id) == true
                            )
                        } else {
                            AppWorkspaceEmptyStateView(
                                title: language.text("No publications found", "Inga publikationer hittades"),
                                subtitle: language.text("Add or search for a publication.", "Lägg till eller sök fram en publikation."),
                                kind: .publications,
                                fillsBackground: true
                            )
                        }
                    }
                    .zIndex(0)

                    if publicationPipelineExpanded {
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                collapsePublicationPipeline()
                            }
                            .zIndex(1)

                        PublicationPipelineCurtainPanel(
                            store: store,
                            maxHeight: publicationPipelinePanelHeight(for: geometry.size.height - publicationPipelineChromeReservedHeight)
                        ) {
                            collapsePublicationPipeline()
                        }
                        .zIndex(2)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.spring(response: 0.34, dampingFraction: 0.88), value: publicationPipelineExpanded)
            }
        }
        .onDeleteCommand {
            guard let selectedPublicationID, let publication = store.publication(id: selectedPublicationID) else { return }
            store.requestKeyboardDeletion(recordTitle: publication.title, isLocked: publication.isEditingLocked) {
                store.deletePublication(id: publication.id)
            }
        }
        .onEscapeKey(isEnabled: publicationPipelineExpanded, perform: collapsePublicationPipeline)
    }

    private var publicationPipelineChromeReservedHeight: CGFloat {
        62
    }

    private func publicationPipelinePanelHeight(for availableHeight: CGFloat) -> CGFloat {
        max(0, availableHeight - 58)
    }

    private func publicationPipelineChromeBar(language: AppLanguage) -> some View {
        let usesDarkAppearance = currentVisualModePreference()?.usesDarkAppearance == true
        return Button {
            togglePublicationPipeline()
        } label: {
            HStack {
                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    AppPanelHeadingText(text: language.text("Publication pipeline", "Publikationsflöde"))

                    Image(systemName: publicationPipelineExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
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
                    if !publicationPipelineExpanded {
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
        .accessibilityLabel(language.text("Show or hide the publication pipeline", "Visa eller dölj Publikationsflöde"))
    }

    private func togglePublicationPipeline() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            publicationPipelineExpanded.toggle()
        }
    }

    private func collapsePublicationPipeline() {
        guard publicationPipelineExpanded else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            publicationPipelineExpanded = false
        }
    }

    private func rebuildFilteredPublicationRows(reason: String = "manual") {
        searchRebuildTask?.cancel()
        let searchQuery = SearchFilterQuery(raw: searchText)
        let nonSearchSignature = publicationNonSearchFilterSignature
        let canReusePreviousSearchBase =
            reason == "debounced-search"
            && nonSearchSignature == lastPublicationNonSearchFilterSignature
            && searchQuery.isNarrowing(over: lastPublicationSearchQuery)

        let baseRows: [PublicationListRow]
        if canReusePreviousSearchBase {
            baseRows = baseFilteredPublicationRows
        } else {
            baseRows = nonSearchMatchingPublicationRows.sorted(using: sortOrder)
            baseFilteredPublicationRows = baseRows
        }

        let candidateRows = canReusePreviousSearchBase ? filteredPublicationRows : baseRows
        let rows = searchQuery.isEmpty
            ? baseRows
            : candidateRows.filter { searchQuery.matches(normalizedHaystack: $0.normalizedSearchBlob) }

        filteredPublicationRows = rows
        lastPublicationSearchQuery = searchQuery
        lastPublicationNonSearchFilterSignature = nonSearchSignature
        // A filter change that hides the selected publication moves the
        // selection to the first visible row. Data changes ("rows") do not,
        // so editing a publication out of the filter does not jump away.
        if reason != "rows",
           let selectedPublicationID,
           !rows.contains(where: { $0.id == selectedPublicationID }),
           publicationRows.contains(where: { $0.id == selectedPublicationID }) {
            setSelectedPublicationID(rows.first?.id, resignFirstResponder: false)
        } else if selectedPublicationID == nil {
            setSelectedPublicationID(rows.first?.id, resignFirstResponder: false)
        } else if store.publication(id: selectedPublicationID) == nil {
            setSelectedPublicationID(rows.first?.id, resignFirstResponder: false)
        }
    }

    private func scheduleFilteredPublicationRowsRebuild() {
        searchRebuildTask?.cancel()
        let task = DispatchWorkItem {
            rebuildFilteredPublicationRows(reason: "debounced-search")
        }
        searchRebuildTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: task)
    }

    private func schedulePublicationRowsRebuild() {
        rowsRebuildTask?.cancel()
        let task = DispatchWorkItem {
            rebuildPublicationRows()
        }
        rowsRebuildTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: task)
    }

    private var publicationNonSearchFilterSignature: String {
        [
            selectedStatusFilters.sorted().joined(separator: "|"),
            selectedTypeFilters.sorted().joined(separator: "|"),
            selectedPeerReviewFilters.sorted().joined(separator: "|"),
            showsOnlyIndependentLeadAfterPhD ? "independentLeadAfterPhD" : "",
            publicationPresetSignature(preset),
            String(publicationRowsAppliedGeneration),
            publicationSortSignature
        ].joined(separator: "||")
    }

    private func publicationPrimarySortComparators(
        for column: PublicationListSortColumn,
        ascending: Bool
    ) -> [KeyPathComparator<PublicationListRow>] {
        let order: SortOrder = ascending ? .forward : .reverse

        switch column {
        case .status:
            return [
                KeyPathComparator(\PublicationListRow.statusSortRank, order: order),
            ]
        case .title:
            return [
                KeyPathComparator(\PublicationListRow.titleSortKey, order: order),
            ]
        case .peerReview:
            return [
                KeyPathComparator(\PublicationListRow.peerReviewSortRank, order: order),
            ]
        case .year:
            return [
                KeyPathComparator(\PublicationListRow.sortYear, order: order),
            ]
        case .journal:
            return [
                KeyPathComparator(\PublicationListRow.journalSortKey, order: order),
            ]
        case .jif:
            return [
                KeyPathComparator(\PublicationListRow.jifSortableValue, order: order),
            ]
        case .quartile:
            return [
                KeyPathComparator(\PublicationListRow.jifQuartileSortRank, order: order),
            ]
        case .norwegian:
            return [
                KeyPathComparator(\PublicationListRow.norwegianSortableValue, order: order),
            ]
        case .position:
            return [
                KeyPathComparator(\PublicationListRow.positionSortRank, order: order),
            ]
        case .independent:
            return [
                KeyPathComparator(\PublicationListRow.independenceSortRank, order: order),
            ]
        }
    }

    private func publicationPresetSignature(_ preset: PublicationListPreset?) -> String {
        switch preset {
        case .none:
            return "none"
        case .some(.all):
            return "all"
        case .some(.originalPublished):
            return "originalPublished"
        case .some(.originalSubmitted):
            return "originalSubmitted"
        case .some(.originalPublishedIndependentLeadAfterPhD):
            return "originalPublishedIndependentLeadAfterPhD"
        case .some(.originalSubmittedIndependentLeadAfterPhD):
            return "originalSubmittedIndependentLeadAfterPhD"
        }
    }

    private var publicationTypeOptions: [String] {
        ["Original", "Brief report", "Research letter", "Systematic review", "Narrative review", "Protocol"]
    }

    private func localizedPublicationType(_ value: String, language: AppLanguage) -> String {
        switch value {
        case "Original":
            return language.text("Original", "Original")
        case "Brief report":
            return language.text("Brief report", "Kort rapport")
        case "Research letter":
            return language.text("Research letter", "Forskningsbrev")
        case "Systematic review":
            return language.text("Systematic review", "Systematisk översikt")
        case "Narrative review":
            return language.text("Narrative review", "Narrativ översikt")
        case "Protocol":
            return language.text("Protocol article", "Protokollartikel")
        default:
            return value
        }
    }

    private func localizedPosition(_ value: String, language: AppLanguage) -> String {
        switch value {
        case "Single":
            language.text("Single", "Ensam")
        case "First":
            language.text("First", "Först")
        case "Last":
            language.text("Last", "Sist")
        case "Middle":
            language.text("Middle", "Mitten")
        default:
            "–"
        }
    }

    private func localizedYesNo(_ value: String, language: AppLanguage) -> String {
        switch value {
        case "Yes":
            language.text("Yes", "Ja")
        case "No":
            language.text("No", "Nej")
        default:
            "–"
        }
    }

    private func localizedGeography(_ value: String, language: AppLanguage) -> String {
        switch value {
        case "International":
            language.text("International", "Internationell")
        case "National":
            language.text("National", "Nationell")
        default:
            "–"
        }
    }

    private func localizedPhD(_ value: String, language: AppLanguage) -> String {
        switch value {
        case "After":
            language.text("After", "Efter")
        case "Before":
            language.text("Before", "Före")
        default:
            "–"
        }
    }

    private func positionTone(for value: String) -> PublicationBadgeTone {
        switch value {
        case "Single", "First", "Last":
            .good
        case "Middle":
            .warning
        default:
            .neutral
        }
    }

    private func yesNoTone(for value: String) -> PublicationBadgeTone {
        switch value {
        case "Yes":
            .good
        case "No":
            .warning
        default:
            .neutral
        }
    }

    private func geographyTone(for value: String) -> PublicationBadgeTone {
        switch value {
        case "International":
            .good
        case "National":
            .warning
        default:
            .neutral
        }
    }

    private func phdTone(for value: String) -> PublicationBadgeTone {
        switch value {
        case "After":
            .good
        case "Before":
            .warning
        default:
            .neutral
        }
    }

    private func matchesStatusFilter(_ publication: PublicationRecord) -> Bool {
        if selectedStatusFilters.isEmpty {
            return true
        }
        return selectedStatusFilters.contains(PublicationStatus.fromStored(publication.statusLabel).rawValue)
    }

    private func matchesPublicationPreset(_ publication: PublicationRecord) -> Bool {
        guard let preset else { return true }
        switch preset {
        case .all:
            return true
        case .originalPublished:
            return isOriginal(publication) && publication.statusLabel == PublicationStatus.published.rawValue
        case .originalSubmitted:
            return isOriginal(publication) && (PublicationStatus.fromStored(publication.statusLabel)).isSubmittedFamily
        case .originalPublishedIndependentLeadAfterPhD:
            return isOriginal(publication)
                && publication.statusLabel == PublicationStatus.published.rawValue
                && isIndependentLeadAfterPhD(publication)
        case .originalSubmittedIndependentLeadAfterPhD:
            return isOriginal(publication)
                && (PublicationStatus.fromStored(publication.statusLabel)).isSubmittedFamily
                && isIndependentLeadAfterPhD(publication)
        }
    }

    private func isStatusFilterOptionSelected(_ option: PublicationStatusFilterOption) -> Bool {
        !selectedStatusFilters.isDisjoint(with: option.statusRawValues)
    }

    private func toggleStatusFilterOption(_ option: PublicationStatusFilterOption) {
        if isStatusFilterOptionSelected(option) {
            selectedStatusFilters.subtract(option.statusRawValues)
        } else {
            selectedStatusFilters.formUnion(option.statusRawValues)
        }
    }

    private func toggleTypeFilter(_ option: PublicationTypeFilterOption) {
        if selectedTypeFilters.contains(option.rawValue) {
            selectedTypeFilters.remove(option.rawValue)
        } else {
            selectedTypeFilters.insert(option.rawValue)
        }
    }

    private func togglePeerReviewFilter(_ id: String) {
        if selectedPeerReviewFilters.contains(id) {
            selectedPeerReviewFilters.remove(id)
        } else {
            selectedPeerReviewFilters.insert(id)
        }
    }

    private func handlePublicationSelectionCandidate(_ newValue: String?) {
        guard publicationSelectionCoordinator.accepts(candidate: newValue) else { return }
        setSelectedPublicationID(newValue, armLock: newValue != nil)
    }

    private func setSelectedPublicationID(_ newValue: String?, armLock: Bool = false, resignFirstResponder: Bool = true) {
        guard selectedPublicationID != newValue else {
            if armLock, let newValue {
                armPublicationSelectionLock(for: newValue)
            }
            return
        }
        if resignFirstResponder {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        let previousID = selectedPublicationID
        selectedPublicationID = newValue
        if armLock, let newValue {
            publicationSelectionCoordinator.arm(newValue, previousID: previousID)
        } else if newValue == nil {
            publicationSelectionCoordinator.clear()
        }
    }

    private func armPublicationSelectionLock(for id: String) {
        publicationSelectionCoordinator.arm(
            id,
            previousID: publicationSelectionCoordinator.previousID
        )
    }

    private func releasePublicationSelectionLock(for id: String) {
        publicationSelectionCoordinator.release(ifMatching: id)
    }

    private func localizedPeerReviewLabel(_ isPeerReviewed: Bool, language: AppLanguage) -> String {
        isPeerReviewed
            ? language.text("Peer reviewed", "Expertgranskad")
            : language.text("Not peer reviewed", "Ej expertgranskad")
    }

    private func peerReviewTone(_ isPeerReviewed: Bool) -> PublicationBadgeTone {
        isPeerReviewed ? .good : .warning
    }

    private func publicationFilterMatrix(language: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AppFilterRow(
                showsClearButton: !selectedStatusFilters.isEmpty,
                clearAction: { selectedStatusFilters.removeAll() }
            ) {
                AppFilterChip(
                    label: PublicationStatusFilterOption.inPreparation.displayName(language: language),
                    isSelected: isStatusFilterOptionSelected(.inPreparation)
                ) {
                    toggleStatusFilterOption(.inPreparation)
                }
                AppFilterChip(
                    label: PublicationStatusFilterOption.submitted.displayName(language: language),
                    isSelected: isStatusFilterOptionSelected(.submitted)
                ) {
                    toggleStatusFilterOption(.submitted)
                }
                AppFilterChip(
                    label: PublicationStatusFilterOption.publishedAccepted.displayName(language: language),
                    isSelected: isStatusFilterOptionSelected(.publishedAccepted)
                ) {
                    toggleStatusFilterOption(.publishedAccepted)
                }
                AppFilterChip(
                    label: PublicationStatusFilterOption.rejected.displayName(language: language),
                    isSelected: isStatusFilterOptionSelected(.rejected)
                ) {
                    toggleStatusFilterOption(.rejected)
                }
            }

            AppFilterRow(
                showsClearButton: !selectedTypeFilters.isEmpty || showsOnlyIndependentLeadAfterPhD,
                clearAction: {
                    selectedTypeFilters.removeAll()
                    showsOnlyIndependentLeadAfterPhD = false
                }
            ) {
                AppFilterChip(
                    label: PublicationTypeFilterOption.original.displayName(language: language),
                    isSelected: selectedTypeFilters.contains(PublicationTypeFilterOption.original.rawValue)
                ) {
                    toggleTypeFilter(.original)
                }
                AppFilterChip(
                    label: PublicationTypeFilterOption.other.displayName(language: language),
                    isSelected: selectedTypeFilters.contains(PublicationTypeFilterOption.other.rawValue)
                ) {
                    toggleTypeFilter(.other)
                }
                AppFilterChip(
                    label: language.text("Independent lead after PhD", "Oberoende efter disputation"),
                    isSelected: showsOnlyIndependentLeadAfterPhD
                ) {
                    showsOnlyIndependentLeadAfterPhD.toggle()
                }
            }

            AppFilterRow(
                showsClearButton: !selectedPeerReviewFilters.isEmpty,
                clearAction: { selectedPeerReviewFilters.removeAll() }
            ) {
                AppFilterChip(
                    label: language.text("Peer reviewed", "Expertgranskad"),
                    isSelected: selectedPeerReviewFilters.contains("peer")
                ) {
                    togglePeerReviewFilter("peer")
                }
                AppFilterChip(
                    label: language.text("Not peer reviewed", "Ej expertgranskad"),
                    isSelected: selectedPeerReviewFilters.contains("nonPeer")
                ) {
                    togglePeerReviewFilter("nonPeer")
                }
            }

            AppFilterClearAllRow(isVisible: hasActivePublicationFilters) {
                resetFiltersForDirectNavigation()
                rebuildFilteredPublicationRows()
            }
        }
    }

    private func matchesTypeFilter(publicationType: String) -> Bool {
        if selectedTypeFilters.isEmpty {
            return true
        }

        let selectedOriginal = selectedTypeFilters.contains(PublicationTypeFilterOption.original.rawValue)
        let selectedOther = selectedTypeFilters.contains(PublicationTypeFilterOption.other.rawValue)
        let isOriginalType = isOriginalPublicationType(publicationType)

        if selectedOriginal && selectedOther {
            return true
        }
        if selectedOriginal {
            return isOriginalType
        }
        if selectedOther {
            return !isOriginalType
        }
        return true
    }

    private func isOriginalPublicationType(_ publicationType: String) -> Bool {
        let type = publicationType.trimmingCharacters(in: .whitespacesAndNewlines)
        return type.isEmpty || type == "Original" || type == "Brief report"
    }

    private func isOriginal(_ publication: PublicationRecord) -> Bool {
        isOriginalPublicationType(publication.publicationType)
    }

    private func isIndependentLeadAfterPhD(_ publication: PublicationRecord) -> Bool {
        let lead = publication.position == "First" || publication.position == "Last" || publication.position == "Single"
        return lead && publication.independence == "Yes" && publication.phdStage == "After"
    }

    // The type chips store their own raw values ("original"/"other"); the
    // presets used to write publication type names that no chip matched.
    private func applyPresetIfNeeded() {
        guard let preset else { return }
        switch preset {
        case .all:
            selectedStatusFilters.removeAll()
            selectedTypeFilters.removeAll()
            showsOnlyIndependentLeadAfterPhD = false
        case .originalPublished:
            selectedStatusFilters = [PublicationStatus.published.rawValue]
            selectedTypeFilters = [PublicationTypeFilterOption.original.rawValue]
            showsOnlyIndependentLeadAfterPhD = false
        case .originalSubmitted:
            selectedStatusFilters = [PublicationStatus.submitted.rawValue]
            selectedTypeFilters = [PublicationTypeFilterOption.original.rawValue]
            showsOnlyIndependentLeadAfterPhD = false
        case .originalPublishedIndependentLeadAfterPhD:
            selectedStatusFilters = [PublicationStatus.published.rawValue]
            selectedTypeFilters = [PublicationTypeFilterOption.original.rawValue]
            showsOnlyIndependentLeadAfterPhD = true
        case .originalSubmittedIndependentLeadAfterPhD:
            selectedStatusFilters = [PublicationStatus.submitted.rawValue]
            selectedTypeFilters = [PublicationTypeFilterOption.original.rawValue]
            showsOnlyIndependentLeadAfterPhD = true
        }
        self.preset = nil
    }

    /// A new publication has no title, type or status yet, so most filters
    /// would hide it; they are cleared so the new record is visible.
    private func createPublicationRevealingIt() {
        if hasActivePublicationFilters {
            resetFiltersForDirectNavigation()
            rebuildFilteredPublicationRows()
        }
        setSelectedPublicationID(store.addPublication(), armLock: true)
    }

    private func activePublicationFilterDescriptions(language: AppLanguage) -> [String] {
        var parts: [String] = []
        if let search = ListFilterLabels.search(searchText, language: language) {
            parts.append(search)
        }
        if let statuses = ListFilterLabels.chips(
            PublicationStatusFilterOption.allCases
                .filter(isStatusFilterOptionSelected)
                .map { $0.displayName(language: language) }
        ) {
            parts.append(statuses)
        }
        if let types = ListFilterLabels.chips(
            PublicationTypeFilterOption.allCases
                .filter { selectedTypeFilters.contains($0.rawValue) }
                .map { $0.displayName(language: language) }
        ) {
            parts.append(types)
        }
        if showsOnlyIndependentLeadAfterPhD {
            parts.append(language.text("Independent lead after PhD", "Oberoende efter disputation"))
        }
        var peerReview: [String] = []
        if selectedPeerReviewFilters.contains("peer") {
            peerReview.append(language.text("Peer reviewed", "Expertgranskad"))
        }
        if selectedPeerReviewFilters.contains("nonPeer") {
            peerReview.append(language.text("Not peer reviewed", "Ej expertgranskad"))
        }
        if let peer = ListFilterLabels.chips(peerReview) {
            parts.append(peer)
        }
        return parts
    }

    /// "Filtrerad lista: 12 av 116 visas" above the list while a filter is on.
    @ViewBuilder
    private func publicationFilteredListBanner(language: AppLanguage) -> some View {
        if hasActivePublicationFilters {
            AppFilteredListBanner(
                displayedCount: filteredPublicationRows.count,
                totalCount: store.publications.count,
                activeFilters: activePublicationFilterDescriptions(language: language),
                restoredFromLastSession: RestoredListFilters.wasRestored(workspace: "Publications.Filter"),
                language: language,
                clearAction: {
                    resetFiltersForDirectNavigation()
                    rebuildFilteredPublicationRows()
                    RestoredListFilters.forget(workspace: "Publications")
                }
            )
        }
    }

    private func resetFiltersForDirectNavigation() {
        searchText = ""
        selectedStatusFilters.removeAll()
        selectedTypeFilters.removeAll()
        selectedPeerReviewFilters.removeAll()
        showsOnlyIndependentLeadAfterPhD = false
        preset = nil
    }

    private func clearPublicationFiltersForDeactivationIfNeeded() {
        guard !store.shouldRetainListFilters(for: .publications) else { return }
        guard hasActivePublicationFilters else { return }
        resetFiltersForDirectNavigation()
        needsPublicationFilterRebuildWhenActive = true
    }

    private func togglePublicationSort(_ column: PublicationListSortColumn) {
        if let existingIndex = publicationSortHistory.firstIndex(where: { $0.column == column }) {
            if existingIndex == 0 {
                publicationSortHistory[0].ascending.toggle()
            } else {
                let criterion = publicationSortHistory.remove(at: existingIndex)
                publicationSortHistory.insert(criterion, at: 0)
            }
        } else {
            publicationSortHistory.insert(
                PublicationListSortCriterion(column: column, ascending: column.defaultAscending),
                at: 0
            )
        }
        ListSortPersistence.save(publicationSortHistory, defaultsKey: "PublicationsListSort")
    }

    private func resetPublicationSort() {
        publicationSortHistory = [
            PublicationListSortCriterion(column: .status, ascending: true)
        ]
        ListSortPersistence.save(publicationSortHistory, defaultsKey: "PublicationsListSort")
    }

    private func publicationSortCriterion(for column: PublicationListSortColumn) -> PublicationListSortCriterion? {
        publicationSortHistory.first(where: { $0.column == column })
    }

    private func publicationSortIndex(for column: PublicationListSortColumn) -> Int? {
        publicationSortHistory.firstIndex(where: { $0.column == column })
    }

    @ViewBuilder
    private func publicationTable(language: AppLanguage) -> some View {
        let titleWidth: CGFloat = 280
        let peerReviewWidth: CGFloat = 104
        let yearWidth: CGFloat = 52
        let journalWidth: CGFloat = 138
        let jifWidth: CGFloat = 58
        let quartileWidth: CGFloat = 68
        let norwWidth: CGFloat = 64
        let positionWidth: CGFloat = 78
        let independentWidth: CGFloat = 82
        let tableContentWidth = titleWidth
            + peerReviewWidth
            + yearWidth
            + journalWidth
            + jifWidth
            + quartileWidth
            + norwWidth
            + positionWidth
            + independentWidth
            + 20
        let orderedIDs = filteredPublicationRows.map(\.id)
        let reminderCounts = calendarTaskReminderBadgeCounts(entries: store.calendarTaskReminderBadgeEntries)

        AppListTable(contentWidth: tableContentWidth) {
            HStack(spacing: 0) {
                publicationListHeader(language.text("Title", "Titel"), width: titleWidth, column: .title)
                publicationListHeader(language.text("Peer review", "Granskning"), width: peerReviewWidth, column: .peerReview)
                publicationListHeader(language.text("Year", "År"), width: yearWidth, column: .year)
                publicationListHeader(language.text("Journal", "Tidskrift"), width: journalWidth, column: .journal)
                publicationListHeader("JIF", width: jifWidth, column: .jif)
                publicationListHeader(language.text("JIF quartile", "JIF-kvartil"), width: quartileWidth, column: .quartile)
                publicationListHeader(language.text("Norw list", "Norw list"), width: norwWidth, column: .norwegian)
                publicationListHeader(language.text("Position", "Placering"), width: positionWidth, column: .position)
                publicationListHeader(language.text("Independent", "Oberoende"), width: independentWidth, column: .independent)
            }
        } rows: {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(filteredPublicationRows, id: \.id) { row in
                    let reminderCount = reminderCounts.publicationCounts[row.id] ?? 0
                    let reminderHelp = calendarTaskReminderBadgeHelp(entries: reminderCounts.entries, language: language) {
                        $0.badgeTargets.contains(.publication(row.id))
                    }
                    Button {
                        handlePublicationSelectionCandidate(row.id)
                    } label: {
                        ZStack(alignment: .leading) {
                            publicationListRowBackground(for: row)

                            HStack(spacing: 0) {
                                Text(row.title)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .padding(.trailing, reminderCount > 0 ? 34 : 0)
                                    .frame(width: titleWidth, alignment: .leading)
                                    .appReminderListBadge(reminderCount, help: reminderHelp)

                                PublicationDerivedBadge(
                                    text: localizedPeerReviewLabel(row.isPeerReviewed, language: language),
                                    tone: peerReviewTone(row.isPeerReviewed),
                                    isCompact: true
                                )
                                .frame(width: peerReviewWidth, alignment: .leading)

                                Text(row.sortYear > 0 ? String(row.sortYear) : "–")
                                    .frame(width: yearWidth, alignment: .leading)

                                Text(row.journal)
                                    .lineLimit(1)
                                    .frame(width: journalWidth, alignment: .leading)

                                Group {
                                    if row.publication != nil {
                                        PublicationMetricValueBadge(
                                            metric: row.jifMetric,
                                            backgroundColor: row.jifBackgroundColor,
                                            isCompact: true
                                        )
                                    } else {
                                        Text("—")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: jifWidth, alignment: .leading)

                                Group {
                                    if row.publication != nil {
                                        PublicationQuartileBadge(metric: row.jifMetric, isCompact: true)
                                    } else {
                                        Text("—")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: quartileWidth, alignment: .leading)

                                Group {
                                    if row.publication != nil {
                                        PublicationMetricValueBadge(
                                            metric: row.norwegianMetric,
                                            backgroundColor: row.norwegianBackgroundColor,
                                            isCompact: true
                                        )
                                    } else {
                                        Text("—")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: norwWidth, alignment: .leading)

                                Group {
                                    if row.publication != nil {
                                        PublicationDerivedBadge(
                                            text: localizedPosition(row.position, language: language),
                                            tone: positionTone(for: row.position),
                                            isCompact: true
                                        )
                                    } else {
                                        Text("—")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: positionWidth, alignment: .leading)

                                Group {
                                    if row.publication != nil {
                                        PublicationDerivedBadge(
                                            text: localizedYesNo(row.independence, language: language),
                                            tone: yesNoTone(for: row.independence),
                                            isCompact: true
                                        )
                                    } else {
                                        Text("—")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: independentWidth, alignment: .leading)
                            }
                            .appTypography(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                        }
                        .frame(width: tableContentWidth, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if row.id != filteredPublicationRows.last?.id {
                        Divider()
                    }
                }
            }
        }
        .appListKeyboardNavigation(
            store: store,
            destination: .publications,
            isEnabled: isActive,
            orderedIDs: orderedIDs,
            selectedID: selectedPublicationID,
            onSelect: handlePublicationSelectionCandidate
        )
    }

    private func publicationListHeader(
        _ title: String,
        width: CGFloat,
        column: PublicationListSortColumn
    ) -> some View {
        let criterion = publicationSortCriterion(for: column)
        let sortIndex = publicationSortIndex(for: column)
        return AppSortableListHeader(
            title: title,
            ascending: criterion?.ascending,
            sortIndex: sortIndex,
            width: width,
            resetTitle: store.language.text("Reset", "Återställ"),
            onToggle: { togglePublicationSort(column) },
            onReset: resetPublicationSort
        )
    }

    private func publicationListRowBackground(for row: PublicationListRow) -> some View {
        Group {
            if row.id == selectedPublicationID {
                SelectedListRowBackground(indicatorFill: publicationListStatusFill(for: row))
            } else if let fill = publicationListStatusFill(for: row) {
                StatusIndicatorListRowBackground(fill: fill)
            } else {
                Color.clear
            }
        }
    }

    private func publicationListStatusFill(for row: PublicationListRow) -> Color? {
        guard row.sourceKind == .publication else { return nil }
        switch PublicationStatus.fromStored(row.statusLabel) {
        case .published, .accepted:
            return AppPalette.vividGreen
        case .submitted:
            return AppPalette.vividYellow
        case .rejected:
            return AppPalette.vividRed
        case .planned, .inPreparation:
            return nil
        }
    }

    private func rebuildPublicationRows() {
        publicationRowsBuildToken &+= 1
        let token = publicationRowsBuildToken
        let publications = store.publications
        let journals = store.journals
        let previousCache = publicationRowCache
        let previousSignatures = publicationRowSignatures
        let distributionCache = publicationMetricDistributionCache

        DispatchQueue.global(qos: .userInitiated).async {
            var journalsByKey = Dictionary(firstWinsKeysWithValues: journals.map {
                (Self.normalizedJournalLookupKey($0.name), $0)
            })
            // "Alla kopplingar via id": journals are also found by id.
            for journal in journals {
                journalsByKey[Self.journalIDLookupKey(journal.id)] = journal
            }

            var nextRows: [PublicationListRow] = []
            nextRows.reserveCapacity(publications.count)
            var nextCache = previousCache
            var nextSignatures: [String: String] = [:]
            nextSignatures.reserveCapacity(publications.count)

            for publication in publications {
                let signature = Self.publicationRowSignature(for: publication)
                let row: PublicationListRow
                if previousSignatures[publication.id] == signature,
                   let cached = previousCache[publication.id] {
                    row = cached
                } else {
                    row = Self.buildPublicationRow(
                        for: publication,
                        journalsByKey: journalsByKey,
                        metricDistributionCache: distributionCache
                    )
                }
                nextRows.append(row)
                nextCache[publication.id] = row
                nextSignatures[publication.id] = signature
            }

            let liveIDs = Set(publications.map(\.id))
            nextCache = nextCache.filter { liveIDs.contains($0.key) }
            nextSignatures = nextSignatures.filter { liveIDs.contains($0.key) }

            DispatchQueue.main.async {
                guard publicationRowsBuildToken == token else { return }
                publicationRows = nextRows
                publicationRowCache = nextCache
                publicationRowSignatures = nextSignatures
                publicationRowsAppliedGeneration &+= 1
                rebuildFilteredPublicationRows(reason: "rows")
            }
        }
    }

    nonisolated private static func publicationRowSignature(for publication: PublicationRecord) -> String {
        [
            publication.title,
            publication.journal,
            publication.journalID ?? "",
            publication.authorNames.joined(separator: "|"),
            publication.projectName ?? "",
            publication.statusLabel,
            publication.workflowStatus?.rawValue ?? "",
            publication.publicationType,
            publication.year,
            publication.position,
            publication.independence,
            publication.geography,
            publication.isPeerReviewed ? "1" : "0",
            publication.doi,
            publication.pmid,
            publication.projectName ?? "",
            publication.statusTimeline.map { "\($0.status)|\($0.journal)|\($0.date ?? "")" }.joined(separator: "|"),
        ].joined(separator: "||")
    }

    /// Status words for search in both languages. Plain strings: the row
    /// builder runs off the main thread, away from the translation registry.
    nonisolated private static func publicationStatusSearchTerms(_ status: PublicationStatus) -> String {
        switch status {
        case .planned:
            return "Planned Planerad"
        case .inPreparation:
            return "In preparation Under arbete"
        case .submitted:
            return "Submitted Inskickad"
        case .accepted:
            return "Accepted Accepterad"
        case .rejected:
            return "Rejected Refuserad"
        case .published:
            return "Published Publicerad"
        }
    }

    nonisolated private static func normalizedJournalLookupKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// "Alla kopplingar via id": the key a journal is also stored under by id
    /// in the row builder's lookup table.
    nonisolated private static func journalIDLookupKey(_ id: String) -> String {
        "\u{1F}journal-id:\(id)"
    }

    private func schedulePublicationIdleWarmup() {
        publicationIdleWarmupTask?.cancel()
        guard isActive else { return }
        let ids = Array(filteredPublicationRows.prefix(20).map(\.id))
        guard !ids.isEmpty else { return }
        let task = DispatchWorkItem {
            guard isActive else { return }
            for id in ids {
                _ = store.publication(id: id)
            }
            store.appendPerformanceDiagnostic(
                String(
                    format: "publications-idle-warm rows=%ld",
                    ids.count
                )
            )
        }
        publicationIdleWarmupTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: task)
    }

    nonisolated private static func buildPublicationRow(
        for publication: PublicationRecord,
        journalsByKey: [String: PublicationJournal],
        metricDistributionCache: PublicationMetricDistributionCache
    ) -> PublicationListRow {
        let journal = publication.journalID.flatMap { journalsByKey[journalIDLookupKey($0)] }
            ?? journalsByKey[normalizedJournalLookupKey(publication.journal)]
        let jifMetric = journal?.preferredMetric(for: [.clarivateScieJIF, .clarivateEsciJIF], publicationYear: publication.yearValue)
        let norwegianMetric = journal?.preferredMetric(for: [.norwegianList], publicationYear: publication.yearValue)
        // Year, DOI, PMID and status (both languages) are searchable too.
        let searchBlob = [
            publication.title,
            publication.journal,
            publication.authorNames.joined(separator: " "),
            publication.projectName ?? "",
            publication.year,
            publication.doi,
            publication.pmid,
            publicationStatusSearchTerms(PublicationStatus.fromStored(publication.statusLabel)),
        ].joined(separator: " ")
        return PublicationListRow(
            id: publication.id,
            sourceKind: .publication,
            publication: publication,
            otherPublication: nil,
            searchBlob: searchBlob,
            normalizedSearchBlob: normalizedSearchFilterText(searchBlob),
            statusLabel: publication.statusLabel,
            workflowStatus: publication.workflowStatus,
            publicationType: publication.publicationType,
            title: publication.title,
            journal: publication.journal,
            sortYear: publication.sortYear,
            statusSortRank: publication.statusSortRank,
            norwegianSortableValue: publication.norwegianSortableValue,
            jifSortableValue: publication.jifSortableValue,
            jifQuartileSortRank: publication.jifQuartileSortRank,
            position: publication.position,
            independence: publication.independence,
            geography: publication.geography,
            jifMetric: jifMetric,
            jifBackgroundColor: metricDistributionCache.backgroundColor(for: jifMetric, publicationYear: publication.yearValue),
            norwegianMetric: norwegianMetric,
            norwegianBackgroundColor: metricDistributionCache.backgroundColor(for: norwegianMetric, publicationYear: publication.yearValue),
            isPeerReviewed: publication.isPeerReviewed,
            peerReviewLabel: publication.isPeerReviewed ? "peer" : "nonPeer"
        )
    }
}

private struct PublicationDerivedBadge: View {
    let text: String
    let tone: PublicationBadgeTone
    var isCompact = false

    var body: some View {
        AppToneBadge(
            text: text,
            size: isCompact ? .compact : .normal,
            foreground: tone.foreground,
            background: tone.background,
            stroke: tone.stroke,
            horizontalPadding: isCompact ? 6 : 8,
            verticalPadding: isCompact ? 1 : 4
        )
    }
}

private struct PublicationPipelineCurtainPanel: View {
    @ObservedObject var store: GrantDataStore
    let maxHeight: CGFloat
    let onClose: () -> Void
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

    private var entries: [PublicationPipelineCurtainEntry] {
        store.publications
            .compactMap(publicationPipelineEntry(for:))
            .sorted(by: publicationPipelineEntrySort)
    }

    private var laneContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(PublicationPipelineCurtainLane.allCases, id: \.id) { lane in
                    publicationPipelineLaneHeader(lane)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                ForEach(PublicationPipelineCurtainLane.allCases, id: \.id) { lane in
                    publicationPipelinePrimaryAuthorContent(lane)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }

            if entries.contains(where: { !$0.isCurrentUserPrimaryAuthor }) {
                PipelineSectionDivider(title: language.text("Middle author", "Mellanförfattare"))
            }

            HStack(alignment: .top, spacing: 12) {
                ForEach(PublicationPipelineCurtainLane.allCases, id: \.id) { lane in
                    publicationPipelineMiddleAuthorContent(lane)
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
                        key: PublicationPipelineCurtainContentHeightPreferenceKey.self,
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
        .onPreferenceChange(PublicationPipelineCurtainContentHeightPreferenceKey.self) { newHeight in
            guard abs(newHeight - measuredContentHeight) > 0.5 else { return }
            measuredContentHeight = newHeight
        }
    }

    private func publicationPipelineLaneHeader(_ lane: PublicationPipelineCurtainLane) -> some View {
        let laneEntries = entries.filter { $0.lane == lane }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(lane.title(language: language))
                    .appTypography(.panelTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text("\(laneEntries.count)")
                    .appTypography(.tableHeader)
                    .foregroundStyle(.secondary)
            }

            Capsule(style: .continuous)
                .fill(neutralStepLineColor.opacity(0.45))
                .frame(height: 2)
        }
    }

    @ViewBuilder
    private func publicationPipelinePrimaryAuthorContent(_ lane: PublicationPipelineCurtainLane) -> some View {
        let primaryEntries = entries.filter { $0.lane == lane && $0.isCurrentUserPrimaryAuthor }
        if !primaryEntries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(primaryEntries) { entry in
                    publicationPipelineItem(entry, tint: neutralStepColor)
                }
            }
        } else {
            Color.clear.frame(height: 0)
        }
    }

    @ViewBuilder
    private func publicationPipelineMiddleAuthorContent(_ lane: PublicationPipelineCurtainLane) -> some View {
        let laneEntries = entries.filter { $0.lane == lane }
        let middleAuthorEntries = laneEntries.filter { !$0.isCurrentUserPrimaryAuthor }
        if laneEntries.isEmpty {
            Text(language.text("No articles", "Inga artiklar"))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
        } else if !middleAuthorEntries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(middleAuthorEntries) { entry in
                    publicationPipelineItem(entry, tint: neutralStepColor, isDimmed: true)
                }
            }
        } else {
            Color.clear.frame(height: 0)
        }
    }

    private func publicationPipelineItem(_ entry: PublicationPipelineCurtainEntry, tint: Color, isDimmed: Bool = false) -> some View {
        let ageStyle = publicationPipelineAgeStyle(for: entry.enteredDate)

        return Button {
            if let publication = store.publication(id: entry.publicationID) {
                store.openRoute(for: publication)
            } else {
                store.route = AppRoute(recordID: entry.publicationID, destination: .publications)
            }
            onClose()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(tint)
                    .frame(width: 5)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(entry.title)
                            .appTypography(.tableHeader)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer(minLength: 8)

                        AppToneBadge(
                            text: publicationPipelineAgeLabel(for: entry.enteredDate),
                            size: .compact,
                            foreground: ageStyle.foreground,
                            background: ageStyle.background,
                            stroke: AppPalette.subtleBorder,
                            horizontalPadding: 8,
                            verticalPadding: 4
                        )
                        .padding(.top, 1)
                    }

                    Text(entry.subtitle)
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(AppPalette.fieldSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(AppPalette.subtleBorder, lineWidth: 1)
            )
            .opacity(isDimmed ? 0.62 : 1)
        }
        .buttonStyle(.plain)
    }

    private func publicationPipelineEntry(for publication: PublicationRecord) -> PublicationPipelineCurtainEntry? {
        let status = PublicationStatus.fromStored(publication.statusLabel)
        let title = publication.title.nonEmpty ?? language.text("Untitled", "Utan titel")

        if status.isSubmittedFamily {
            return PublicationPipelineCurtainEntry(
                publicationID: publication.id,
                title: title,
                subtitle: publication.journal.nonEmpty
                    ?? publication.projectName.nonEmpty
                    ?? language.text("No journal selected", "Ingen tidskrift vald"),
                lane: .submitted,
                enteredDate: submittedDate(for: publication),
                isCurrentUserPrimaryAuthor: isCurrentUserPrimaryAuthor(publication)
            )
        }

        guard status == .inPreparation,
              let workflowStatus = publication.workflowStatus,
              let lane = PublicationPipelineCurtainLane(workflowStatus: workflowStatus) else {
            return nil
        }

        return PublicationPipelineCurtainEntry(
            publicationID: publication.id,
            title: title,
            subtitle: publication.projectName.nonEmpty
                ?? publication.journal.nonEmpty
                ?? language.text("No project", "Inget projekt"),
            lane: lane,
            enteredDate: DateParsers.isoDay.date(from: publication.workflowStatusDate ?? ""),
            isCurrentUserPrimaryAuthor: isCurrentUserPrimaryAuthor(publication)
        )
    }

    private func isCurrentUserPrimaryAuthor(_ publication: PublicationRecord) -> Bool {
        guard let index = store.currentUserPersonIndex(ids: publication.authorIDs, names: publication.authorNames) else {
            return false
        }
        if publication.authorNames.count == 1 { return true }
        if index == 0 || (publication.sharedFirstAuthorship && index == 1) { return true }
        return index == publication.authorNames.count - 1
            || (publication.sharedLastAuthorship && index == publication.authorNames.count - 2)
    }

    private func publicationPipelineEntrySort(_ lhs: PublicationPipelineCurtainEntry, _ rhs: PublicationPipelineCurtainEntry) -> Bool {
        if lhs.lane.sortRank != rhs.lane.sortRank {
            return lhs.lane.sortRank < rhs.lane.sortRank
        }

        switch (lhs.enteredDate, rhs.enteredDate) {
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

    private func submittedDate(for publication: PublicationRecord) -> Date? {
        if let latestSubmitted = publication.statusTimeline
            .filter({ PublicationStatus.fromStored($0.status).isSubmittedFamily })
            .compactMap({ $0.date.flatMap(DateParsers.isoDay.date(from:)) })
            .max() {
            return latestSubmitted
        }

        if let currentSubmissionDate = publication.currentSubmissionDate.flatMap(DateParsers.isoDay.date(from:)) {
            return currentSubmissionDate
        }

        return publication.statusDate.flatMap(DateParsers.isoDay.date(from:))
    }

    private func publicationPipelineAgeLabel(for date: Date?) -> String {
        guard let date else {
            return language.text("Entered date missing", "Saknar statusdatum")
        }

        let days = max(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: Date())).day ?? 0, 0)
        return language.text("For \(days) d", "Sedan \(days) d")
    }

    private func publicationPipelineAgeStyle(for date: Date?) -> (foreground: Color, background: Color) {
        guard let date else {
            return (Color.primary, AppPalette.subtleBorder.opacity(0.45))
        }

        let days = max(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: Date())).day ?? 0, 0)
        if days >= 90 {
            return (AppPalette.semanticOnColor, AppPalette.vividRed)
        }
        if days >= 30 {
            return (AppPalette.semanticOnColor, AppPalette.vividYellow)
        }
        return (AppPalette.semanticOnColor, AppPalette.vividGreen)
    }
}

private struct PublicationPipelineCurtainContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct PublicationPipelineCurtainEntry: Identifiable {
    let publicationID: String
    let title: String
    let subtitle: String
    let lane: PublicationPipelineCurtainLane
    let enteredDate: Date?
    let isCurrentUserPrimaryAuthor: Bool

    var id: String {
        "\(publicationID)|\(lane.rawValue)"
    }
}

private struct PipelineSectionDivider: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(AppPalette.subtleBorder.opacity(0.85))
                .frame(height: 1)
            Text(title)
                .appTypography(.tableHeader)
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

private enum PublicationPipelineCurtainLane: String, CaseIterable, Identifiable {
    case dataCollection
    case dataAnalysis
    case writing
    case withCoauthors
    case submitted

    var id: String { rawValue }

    init?(workflowStatus: PublicationWorkflowStatus) {
        switch workflowStatus {
        case .dataCollection:
            self = .dataCollection
        case .dataProcessing:
            self = .dataAnalysis
        case .manuscriptWriting:
            self = .writing
        case .withCoauthors:
            self = .withCoauthors
        }
    }

    var sortRank: Int {
        switch self {
        case .dataCollection:
            return 0
        case .dataAnalysis:
            return 1
        case .writing:
            return 2
        case .withCoauthors:
            return 3
        case .submitted:
            return 4
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .dataCollection:
            return language.text("In data collection", "I datainsamling")
        case .dataAnalysis:
            return language.text("In data analysis", "I dataanalys")
        case .writing:
            return language.text("In writing", "I skrivande")
        case .withCoauthors:
            return language.text("With co-authors", "Hos medförfattare")
        case .submitted:
            return language.text("Submitted", "Inskickade")
        }
    }

    var tint: Color {
        switch self {
        case .dataCollection:
            return AppPalette.vividBlue
        case .dataAnalysis:
            return AppPalette.shadeBlue
        case .writing:
            return AppPalette.vividOrange
        case .withCoauthors:
            return AppPalette.chartYellow
        case .submitted:
            return AppPalette.vividGreen
        }
    }
}
