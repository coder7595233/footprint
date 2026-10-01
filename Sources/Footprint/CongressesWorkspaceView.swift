import AppKit
import CoreLocation
import MapKit
import SwiftUI
import UniformTypeIdentifiers

private enum CongressesWorkspaceMode: String, CaseIterable, Identifiable {
    case overview
    case plan

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .overview:
            return language.text("Overview", "Översikt")
        case .plan:
            return language.text("Plan (map)", "Planera (karta)")
        }
    }
}

private enum CongressWorkspaceRowSource: Hashable, Sendable {
    case organizationCongress
    case contribution(String)
    case draft
}

private enum CongressListSortColumn: String, Hashable {
    case from
    case abstractDeadline
    case lateAbstractDeadline
    case title
    case organization
    case place
    case abstracts

    var defaultAscending: Bool {
        switch self {
        case .from, .abstractDeadline, .lateAbstractDeadline, .title, .organization, .place:
            return true
        case .abstracts:
            return false
        }
    }
}

private struct CongressListSortCriterion: AppListSortCriterion {
    let column: CongressListSortColumn
    var ascending: Bool
}

private enum CongressWorkspaceStatusTone: String, Hashable, Sendable {
    case attending
    case attended
    case abstractOnly
    case rejected
    case missed
    case neutral

    init(_ status: AppStatusTones.CongressStatus) {
        switch status {
        case .attending: self = .attending
        case .attended: self = .attended
        case .rejected: self = .rejected
        case .notAttending: self = .missed
        case .contributionOnly: self = .abstractOnly
        case .planned: self = .neutral
        }
    }

    var congressStatus: AppStatusTones.CongressStatus {
        switch self {
        case .attending: return .attending
        case .attended: return .attended
        case .rejected: return .rejected
        case .missed: return .notAttending
        case .abstractOnly: return .contributionOnly
        case .neutral: return .planned
        }
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .attending:
            return language.text("Attend", "Medverkar")
        case .attended:
            return language.text("Attended", "Medverkade")
        case .abstractOnly:
            return language.text("Abstract", "Abstract")
        case .rejected:
            return language.text("Rejected", "Refuserad")
        case .missed:
            return language.text("Passed", "Passerad")
        case .neutral:
            return language.text("Planned", "Planerad")
        }
    }

    /// Round 17: the shared congress rule (attending = yellow, attended =
    /// green, not attending = grey, planned = no fill).
    var statusTone: AppStatusTone {
        AppStatusTones.congress(congressStatus)
    }

    var fill: Color {
        statusTone.hasFill ? AppPalette.statusFill(statusTone) : AppPalette.fieldSurface
    }

    var stroke: Color {
        statusTone.hasFill ? AppPalette.statusEdge(statusTone) : AppPalette.border
    }
}

private struct CongressWorkspaceRow: Identifiable, Hashable, @unchecked Sendable {
    let id: String
    let organizationID: String
    let congressID: String
    let source: CongressWorkspaceRowSource
    let title: String
    let organizationName: String
    // Whether organizationName is a real organization rather than the
    // localized "No organization" placeholder; comparing the display text
    // breaks as soon as the row was built under the other language.
    let hasOrganization: Bool
    let congress: OrganizationCongress
    let startDate: Date?
    let endDate: Date?
    let sortDate: Date?
    let isPast: Bool
    let dateText: String
    let placeText: String
    let abstractText: String
    let contributionCount: Int
    let primaryContributionID: String?
    let currentUserParticipates: Bool
    let statusTone: CongressWorkspaceStatusTone
    let normalizedSearchBlob: String

    var displayYear: Int? {
        let date = sortDate ?? startDate ?? endDate
        return date.map { Calendar.current.component(.year, from: $0) }
    }

    var hasPassedAbstractDeadline: Bool {
        congressHasPassedAbstractDeadline(congress)
    }
}

private struct CongressRowsBuildSnapshot: @unchecked Sendable {
    let organizations: [OrganizationRecord]
    let contributions: [CVConferenceContribution]
    let drafts: [OrganizationCongress]
    let currentUserAuthor: PublicationAuthor?
    let language: AppLanguage
    let today: Date
}

enum CongressRowsBuildGenerationPolicy {
    static func shouldPublish(
        completedGeneration: UInt,
        currentGeneration: UInt,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled && completedGeneration == currentGeneration
    }
}

struct CongressesWorkspaceView: View {
    let store: GrantDataStore
    let isActive: Bool

    @State private var mode: CongressesWorkspaceMode = .overview
    @WorkspaceFilterState("Congresses.Filter.Search") private var searchText = ""
    @State private var selectedCongressID: String?
    @State private var selectedContributionID: String?
    @WorkspaceFilterState("Congresses.Filter.HidePassed") private var hidesPassedCongresses = false
    @WorkspaceFilterState("Congresses.Filter.HidePassedDeadlines") private var hidesPassedAbstractDeadlines = false
    @WorkspaceFilterState("Congresses.Filter.MinimumYear") private var minimumYearValue = 0.0
    @WorkspaceFilterState("Congresses.Filter.MaximumYear") private var maximumYearValue = 0.0
    @WorkspaceFilterState("Congresses.Filter.FollowsRange") private var dateFiltersFollowAvailableRange = true
    @State private var draftCongresses: [OrganizationCongress] = []
    @State private var cachedRows: [CongressWorkspaceRow] = []
    @State private var cachedRowsSignature = ""
    @State private var congressRowsBuildGeneration: UInt = 0
    @State private var congressRowsBuildTask: Task<Void, Never>?
    @State private var congressTodayKey = CongressesWorkspaceView.todayKey()
    @State private var hasAppliedLaunchFilterPolicy = false
    @State private var sortHistory = ListSortPersistence.load(
        defaultsKey: "CongressesListSort",
        defaultValue: [CongressListSortCriterion(column: .from, ascending: true)]
    )

    private var language: AppLanguage { store.language }
    private var currentUserAuthor: PublicationAuthor? { store.currentUserAuthor() }

    private var rows: [CongressWorkspaceRow] {
        cachedRows
    }

    private var hasActiveCongressFilters: Bool {
        searchText.nonEmpty != nil
            || hidesPassedCongresses
            || hidesPassedAbstractDeadlines
            || yearFilterIsNarrowed
    }

    /// Round 16: while the rows are still being built the saved range is
    /// judged by its "follows" flag, not against the current year.
    private var yearFilterIsNarrowed: Bool {
        guard !availableYears.isEmpty else {
            return !dateFiltersFollowAvailableRange && !(minimumYearValue == 0 && maximumYearValue == 0)
        }
        return minimumYearValue != yearBounds.lowerBound || maximumYearValue != yearBounds.upperBound
    }

    nonisolated private static func buildRows(from snapshot: CongressRowsBuildSnapshot) -> [CongressWorkspaceRow] {
        let language = snapshot.language
        let currentUserAuthor = snapshot.currentUserAuthor
        let today = Calendar.current.startOfDay(for: snapshot.today)
        let organizationsByID = snapshot.organizations.reduce(into: [String: OrganizationRecord]()) { result, organization in
            if result[organization.id] == nil {
                result[organization.id] = organization
            }
        }
        let contributionsByCongress = Dictionary(grouping: snapshot.contributions) { contribution in
            Self.contributionLinkKey(
                organizationID: contribution.congressOrganizationID,
                congressID: contribution.congressID
            )
        }
        let organizationRows = snapshot.organizations.flatMap { organization in
            organization.congresses.compactMap { congress -> CongressWorkspaceRow? in
                guard !congress.isEmpty else { return nil }
                let startDate = congress.from.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
                let endDate = congress.to.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
                let effectiveEndDate = endDate ?? startDate
                let sortDate = startDate
                    ?? endDate
                    ?? congress.abstractSubmissionDeadline.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
                    ?? congress.lateAbstractSubmissionDeadline.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
                let linkedContributionCount = contributionsByCongress[
                    Self.contributionLinkKey(organizationID: organization.id, congressID: congress.id)
                ] ?? []
                let currentUserParticipates = Self.congressCurrentUserParticipates(
                    congress,
                    currentUserAuthor: currentUserAuthor
                )
                let statusTone = Self.statusTone(
                    currentUserParticipates: currentUserParticipates,
                    linkedContributions: linkedContributionCount,
                    isPast: effectiveEndDate.map { Calendar.current.startOfDay(for: $0) < today } ?? false
                )
                let title = congress.title.nonEmpty ?? organization.displayName(for: language)
                let organizationName = organization.displayName(for: language)
                let dateText = Self.dateText(for: congress, language: language)
                let placeText = Self.placeText(for: congress)
                let abstractText = Self.abstractText(for: congress, language: language)
                return CongressWorkspaceRow(
                    id: Self.rowID(organizationID: organization.id, congressID: congress.id),
                    organizationID: organization.id,
                    congressID: congress.id,
                    source: .organizationCongress,
                    title: title,
                    organizationName: organizationName,
                    hasOrganization: true,
                    congress: congress,
                    startDate: startDate,
                    endDate: endDate,
                    sortDate: sortDate,
                    isPast: effectiveEndDate.map { Calendar.current.startOfDay(for: $0) < today } ?? false,
                    dateText: dateText,
                    placeText: placeText,
                    abstractText: abstractText,
                    contributionCount: linkedContributionCount.count,
                    primaryContributionID: linkedContributionCount.first?.id,
                    currentUserParticipates: currentUserParticipates,
                    statusTone: statusTone,
                    normalizedSearchBlob: normalizedSearchFilterText([
                        title,
                        organizationName,
                        placeText,
                        dateText,
                        abstractText,
                        linkedContributionCount.map { $0.localizedTitle(language: language).nonEmpty ?? $0.displayTitle }.joined(separator: " ")
                    ].joined(separator: " "))
                )
            }
        }

        let existingCongressKeys = Set(organizationRows.map { Self.rowID(organizationID: $0.organizationID, congressID: $0.congressID) })
        let contributionRows = snapshot.contributions.compactMap { contribution -> CongressWorkspaceRow? in
            if let organizationID = contribution.congressOrganizationID,
               let congressID = contribution.congressID,
               existingCongressKeys.contains(Self.rowID(organizationID: organizationID, congressID: congressID)) {
                return nil
            }
            guard !contribution.isEmpty else { return nil }
            let congress = Self.syntheticCongress(from: contribution, language: language)
            let startDate = congress.from.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
            let endDate = congress.to.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
            let effectiveEndDate = endDate ?? startDate
            let sortDate = startDate
                ?? endDate
                ?? congress.abstractSubmissionDeadline.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
                ?? contribution.publicationYear.nonEmpty.flatMap { DateParsers.isoDay.date(from: "\($0)-01-01") }
            let isPast = effectiveEndDate.map { Calendar.current.startOfDay(for: $0) < today }
                ?? contribution.publicationYear.nonEmpty.flatMap(Int.init).map { $0 < Calendar.current.component(.year, from: today) }
                ?? false
            let resolvedOrganizationName = contribution.congressOrganizationID
                .flatMap { organizationsByID[$0]?.displayName(for: language) }
            let organizationName = resolvedOrganizationName
                ?? language.text("No organization", "Ingen organisation")
            let title = congress.title.nonEmpty
                ?? contribution.localizedMeeting(language: language).nonEmpty
                ?? contribution.displayTitle
            let dateText = Self.dateText(for: congress, language: language).nonEmpty ?? Self.contributionDateText(for: contribution)
            let placeText = Self.placeText(for: congress)
            let abstractText = Self.abstractText(for: congress, language: language)
            let currentUserParticipates = Self.congressCurrentUserParticipates(
                congress,
                currentUserAuthor: currentUserAuthor
            )
            let tone = Self.statusTone(
                currentUserParticipates: currentUserParticipates,
                linkedContributions: [contribution],
                isPast: isPast
            )
            return CongressWorkspaceRow(
                id: Self.contributionRowID(contribution.id),
                organizationID: contribution.congressOrganizationID ?? "",
                congressID: congress.id,
                source: .contribution(contribution.id),
                title: title,
                organizationName: organizationName,
                hasOrganization: resolvedOrganizationName != nil,
                congress: congress,
                startDate: startDate,
                endDate: endDate,
                sortDate: sortDate,
                isPast: isPast,
                dateText: dateText,
                placeText: placeText,
                abstractText: abstractText,
                contributionCount: 1,
                primaryContributionID: contribution.id,
                currentUserParticipates: currentUserParticipates,
                statusTone: tone,
                normalizedSearchBlob: normalizedSearchFilterText([
                    title,
                    organizationName,
                    placeText,
                    dateText,
                    abstractText,
                    contribution.localizedTitle(language: language),
                    contribution.localizedName(language: language)
                ].joined(separator: " "))
            )
        }

        let draftRows = snapshot.drafts.map { congress in
            CongressWorkspaceRow(
                id: Self.draftRowID(congressID: congress.id),
                organizationID: "",
                congressID: congress.id,
                source: .draft,
                title: congress.title.nonEmpty ?? language.text("New congress", "Ny kongress"),
                organizationName: language.text("No organization", "Ingen organisation"),
                hasOrganization: false,
                congress: congress,
                startDate: congress.from.nonEmpty.flatMap(DateParsers.isoDay.date(from:)),
                endDate: congress.to.nonEmpty.flatMap(DateParsers.isoDay.date(from:)),
                sortDate: congress.from.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
                    ?? congress.to.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
                    ?? congress.abstractSubmissionDeadline.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
                    ?? congress.lateAbstractSubmissionDeadline.nonEmpty.flatMap(DateParsers.isoDay.date(from:)),
                isPast: false,
                dateText: Self.dateText(for: congress, language: language),
                placeText: Self.placeText(for: congress),
                abstractText: Self.abstractText(for: congress, language: language),
                contributionCount: contributionsByCongress[
                    Self.contributionLinkKey(organizationID: nil, congressID: congress.id)
                ]?.count ?? 0,
                primaryContributionID: contributionsByCongress[
                    Self.contributionLinkKey(organizationID: nil, congressID: congress.id)
                ]?.first?.id,
                currentUserParticipates: Self.congressCurrentUserParticipates(
                    congress,
                    currentUserAuthor: currentUserAuthor
                ),
                statusTone: .neutral,
                normalizedSearchBlob: normalizedSearchFilterText([
                    congress.title,
                    language.text("New congress", "Ny kongress"),
                    language.text("No organization", "Ingen organisation")
                ].joined(separator: " "))
            )
        }

        return draftRows + (organizationRows + contributionRows).sorted(by: Self.sortRows)
    }

    private var filteredRows: [CongressWorkspaceRow] {
        let query = SearchFilterQuery(raw: searchText)
        let lowerYear = Int(min(minimumYearValue, maximumYearValue).rounded())
        let upperYear = Int(max(minimumYearValue, maximumYearValue).rounded())
        return rows.filter { row in
            if hidesPassedCongresses && row.isPast {
                return false
            }
            if hidesPassedAbstractDeadlines && row.hasPassedAbstractDeadline {
                return false
            }
            if let displayYear = row.displayYear,
               (displayYear < lowerYear || displayYear > upperYear) {
                return false
            }
            return query.isEmpty || query.matches(normalizedHaystack: row.normalizedSearchBlob)
        }
        .sorted(by: sortRowsUsingSortHistory)
    }

    private var selectedRow: CongressWorkspaceRow? {
        if let selectedCongressID,
           let row = filteredRows.first(where: { $0.id == selectedCongressID }) {
            return row
        }
        return filteredRows.first
    }

    private var availableYears: [Int] {
        Array(Set(rows.compactMap(\.displayYear))).sorted()
    }

    private var yearBounds: ClosedRange<Double> {
        let fallbackYear = Calendar.current.component(.year, from: Date())
        let lower = Double(availableYears.first ?? fallbackYear)
        let upper = Double(availableYears.last ?? fallbackYear)
        return lower...max(lower, upper)
    }

    private var hasAdjustableYearRange: Bool {
        yearBounds.lowerBound < yearBounds.upperBound
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch mode {
            case .overview:
                overview
            case .plan:
                CongressMapWorkspaceView(
                    store: store,
                    isActive: isActive && mode == .plan
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppPalette.canvasBottom)
        .onAppear {
            applyLaunchFilterPolicyIfNeeded()
            refreshCongressTodayKeyIfNeeded(reason: "appear")
            rebuildCongressRows(reason: "appear")
            clampYearFiltersToAvailableRows()
            consumePendingCongressRouteIfNeeded()
            consumeConferenceContributionRouteIfNeeded()
            reconcileSelection()
        }
        .task(id: congressTodayKey) {
            await refreshCongressRowsAfterOpenAndAtNextDay()
        }
        .onChange(of: rowsSignature) { _, _ in
            clampYearFiltersToAvailableRows()
            consumePendingCongressRouteIfNeeded()
            consumeConferenceContributionRouteIfNeeded()
            reconcileSelection()
        }
        .onReceive(store.$organizationRowSnapshotGeneration.dropFirst()) { _ in
            rebuildCongressRows(reason: "organizations")
        }
        .onReceive(store.$calendarContentGeneration.dropFirst()) { _ in
            rebuildCongressRows(reason: "calendar-content")
        }
        .onReceive(store.$cvConferenceContributions.dropFirst()) { _ in
            // @Published emits at willSet; defer so the rebuild snapshot
            // reads the updated collection.
            DispatchQueue.main.async {
                rebuildCongressRows(reason: "abstracts")
            }
        }
        .onChange(of: draftCongresses) { _, _ in
            rebuildCongressRows(reason: "drafts")
        }
        .onChange(of: store.language) { _, _ in
            rebuildCongressRows(reason: "language")
        }
        .onChange(of: store.route) { _, _ in
            consumeConferenceContributionRouteIfNeeded()
        }
        .onDisappear {
            congressRowsBuildTask?.cancel()
        }
        .onChange(of: store.pendingCongressRouteToken) { _, _ in
            consumePendingCongressRouteIfNeeded()
        }
        .onChange(of: selectedCongressID) { _, _ in
            selectedContributionID = nil
        }
        .onChange(of: isActive) { _, active in
            if active {
                clampYearFiltersToAvailableRows()
                consumePendingCongressRouteIfNeeded()
                consumeConferenceContributionRouteIfNeeded()
                reconcileSelection()
            } else {
                clearCongressFiltersForDeactivationIfNeeded()
            }
        }
    }

    private var header: some View {
        AppWorkspaceTitleBar(title: language.text("Congresses", "Kongresser")) {
            Picker("", selection: modeBinding) {
                ForEach(CongressesWorkspaceMode.allCases) { item in
                    Text(item.title(language: language)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            Spacer(minLength: 0)

            Button {
                addNewCongress()
            } label: {
                Text(language.text("New congress", "Ny kongress"))
            }
            .appAddButtonStyle()
        }
        .background(AppPalette.cardSurface.opacity(0.72))
    }

    private var overview: some View {
        PersistentSplitView(layout: .congresses) {
            AppWorkspaceSidebar(padding: 0) {
                sidebar
            }
        } detail: {
            detailPane
        }
    }

    private var modeBinding: Binding<CongressesWorkspaceMode> {
        Binding(
            get: { mode },
            set: { newValue in
                guard mode != newValue else { return }
                NSApp.keyWindow?.makeFirstResponder(nil)
                mode = newValue
            }
        )
    }

    private var sidebar: some View {
        // Round 16: filtered once per update; the row buttons used to filter
        // the whole list again for every row.
        let visibleRows = filteredRows
        let selectedID = selectedRowID(in: visibleRows)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                AppFilterCard {
                    VStack(alignment: .leading, spacing: 8) {
                        AppFilterRow(
                            showsClearButton: searchText.nonEmpty != nil,
                            clearAction: { searchText = "" }
                        ) {
                            AppSidebarSearchField(
                                placeholder: language.text("Search congresses", "Sök kongresser"),
                                text: $searchText
                            )
                        }

                        AppFilterRow(
                            showsClearButton: hidesPassedCongresses,
                            clearAction: { hidesPassedCongresses = false }
                        ) {
                            AppFilterChip(
                                label: language.text("Hide passed congress dates", "Dölj passerade kongressdatum"),
                                isSelected: hidesPassedCongresses
                            ) {
                                hidesPassedCongresses.toggle()
                            }
                        }

                        AppFilterRow(
                            showsClearButton: hidesPassedAbstractDeadlines,
                            clearAction: { hidesPassedAbstractDeadlines = false }
                        ) {
                            AppFilterChip(
                                label: language.text("Hide passed abstract deadlines", "Dölj passerade abstractdeadline"),
                                isSelected: hidesPassedAbstractDeadlines
                            ) {
                                hidesPassedAbstractDeadlines.toggle()
                            }
                        }

                        HStack(alignment: .bottom, spacing: 10) {
                            AppFilterRangeControl(
                                title: yearRangeText,
                                lowerValue: minimumYearSliderBinding,
                                upperValue: maximumYearSliderBinding,
                                bounds: yearBounds,
                                maxWidth: nil,
                                lowerLabel: "\(language.text("Date from", "Datum från")): \(Int(minimumYearValue.rounded()))",
                                upperLabel: "\(language.text("Date to", "Datum till")): \(Int(maximumYearValue.rounded()))"
                            )

                            if yearFilterIsNarrowed {
                                FilterClearButton {
                                    resetCongressYearRange()
                                }
                                .padding(.bottom, 2)
                            }
                        }
                        // Round 16: "clear all" now lives in the filtered-list
                        // banner above the list.
                    }
                }

                if hasActiveCongressFilters {
                    AppFilteredListBanner(
                        displayedCount: visibleRows.count,
                        totalCount: rows.count,
                        activeFilters: activeCongressFilterDescriptions,
                        restoredFromLastSession: RestoredListFilters.wasRestored(workspace: "Congresses"),
                        language: language,
                        clearAction: clearAllCongressFilters
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            if visibleRows.isEmpty {
                if !rows.isEmpty && hasActiveCongressFilters {
                    // Round 16: congresses exist but the filters hide them.
                    AppWorkspaceEmptyStateView(
                        title: language.text("No records match the filters", "Inga poster matchar filtren"),
                        subtitle: language.text("Try a broader search or clear the filters.", "Prova en bredare sökning eller rensa filtren."),
                        kind: .congresses,
                        actionTitle: language.text("Clear filters", "Rensa filter"),
                        action: clearAllCongressFilters
                    )
                    .padding(18)
                } else {
                    AppWorkspaceEmptyStateView(
                        title: language.text("No congresses found", "Inga kongresser hittades"),
                        subtitle: language.text("Adjust the search or add congresses to an organization.", "Ändra sökningen eller lägg till kongresser på en organisation."),
                        kind: .congresses
                    )
                    .padding(18)
                }
            } else {
                congressList(rows: visibleRows, selectedID: selectedID)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
    }

    private func selectedRowID(in visibleRows: [CongressWorkspaceRow]) -> String? {
        if let selectedCongressID, visibleRows.contains(where: { $0.id == selectedCongressID }) {
            return selectedCongressID
        }
        return visibleRows.first?.id
    }

    private var activeCongressFilterDescriptions: [String] {
        var descriptions: [String] = []
        if let search = searchText.nonEmpty {
            descriptions.append(language.text("Search “\(search)”", "Sökning ”\(search)”"))
        }
        if hidesPassedCongresses {
            descriptions.append(language.text("Passed congress dates hidden", "Passerade kongressdatum dolda"))
        }
        if hidesPassedAbstractDeadlines {
            descriptions.append(language.text("Passed abstract deadlines hidden", "Passerade abstractdeadline dolda"))
        }
        if yearFilterIsNarrowed {
            descriptions.append(yearRangeText)
        }
        return descriptions
    }

    private func congressList(rows: [CongressWorkspaceRow], selectedID: String?) -> some View {
        let fromWidth: CGFloat = 92
        let abstractWidth: CGFloat = 104
        let lateAbstractWidth: CGFloat = 118
        let titleWidth: CGFloat = 190
        let organizationWidth: CGFloat = 125
        let placeWidth: CGFloat = 120
        let abstractsWidth: CGFloat = 56
        let tableContentWidth: CGFloat = fromWidth + abstractWidth + lateAbstractWidth + titleWidth + organizationWidth + placeWidth + abstractsWidth + 20
        let orderedIDs = rows.map(\.id)

        return AppListTable(contentWidth: tableContentWidth) {
            HStack(spacing: 0) {
                congressListHeader(language.text("From", "Från"), width: fromWidth, column: .from)
                congressListHeader(language.text("Abstract", "Abstract"), width: abstractWidth, column: .abstractDeadline)
                congressListHeader(language.text("Late abstract", "Sen abstractfrist"), width: lateAbstractWidth, column: .lateAbstractDeadline)
                congressListHeader(language.text("Congress", "Kongress"), width: titleWidth, column: .title)
                congressListHeader(language.text("Organization", "Organisation"), width: organizationWidth, column: .organization)
                congressListHeader(language.text("Place", "Plats"), width: placeWidth, column: .place)
                congressListHeader("Abstract", width: abstractsWidth, column: .abstracts)
            }
        } rows: {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    congressRowButton(row, isSelected: row.id == selectedID, tableContentWidth: tableContentWidth)
                    if row.id != rows.last?.id {
                        Divider()
                    }
                }
            }
        }
        .appListKeyboardNavigation(
            store: store,
            destination: .congresses,
            isEnabled: isActive && mode == .overview,
            orderedIDs: orderedIDs,
            selectedID: selectedCongressID,
            onSelect: { setSelectedCongressID($0) }
        )
    }

    private func congressListHeader(_ title: String, width: CGFloat? = nil, column: CongressListSortColumn) -> some View {
        let criterion = sortHistory.first(where: { $0.column == column })
        let sortIndex = sortHistory.firstIndex(where: { $0.column == column })
        return AppSortableListHeader(
            title: title,
            ascending: criterion?.ascending,
            sortIndex: sortIndex,
            width: width,
            resetTitle: language.text("Reset", "Återställ"),
            onToggle: { toggleCongressSort(column) },
            onReset: resetCongressSort
        )
    }

    private func congressRowButton(_ row: CongressWorkspaceRow, isSelected: Bool, tableContentWidth: CGFloat) -> some View {
        AppListRowButton(
            width: tableContentWidth,
            action: { setSelectedCongressID(row.id) },
            background: { congressListRowBackground(row: row, isSelected: isSelected) }
        ) {
            HStack(alignment: .center, spacing: 0) {
                HStack(spacing: 4) {
                    Text(congressListDateText(row.congress.from))
                        .monospacedDigit()
                        .lineLimit(1)
                    if row.congress.fromUncertain || row.congress.toUncertain {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 92, alignment: .leading)

                Text(congressListDateText(row.congress.abstractSubmissionDeadline))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: 104, alignment: .leading)

                Text(congressListDateText(row.congress.lateAbstractSubmissionDeadline))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: 118, alignment: .leading)

                Text(row.title)
                    .foregroundStyle(AppPalette.appText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 190, alignment: .leading)

                Text(row.organizationName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 125, alignment: .leading)

                Text(row.placeText.nonEmpty ?? "-")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 120, alignment: .leading)

                Text(row.contributionCount > 0 ? "\(row.contributionCount)" : "-")
                    .foregroundStyle(row.contributionCount > 0 ? AppPalette.appText : .secondary)
                    .frame(width: 56, alignment: .leading)
            }
        }
        .id(row.id)
    }

    private func setSelectedCongressID(_ newValue: String?) {
        guard selectedCongressID != newValue else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
        selectedCongressID = newValue
    }

    private func congressListRowBackground(row: CongressWorkspaceRow, isSelected: Bool) -> some View {
        AppListRowBackground(
            isSelected: isSelected,
            toneFill: row.statusTone == .neutral ? nil : row.statusTone.fill
        )
    }

    @ViewBuilder
    private var detailPane: some View {
        if let selectedRow {
            CongressDetailPane(
                store: store,
                row: selectedRow,
                selectedCongressID: $selectedCongressID,
                selectedContributionID: $selectedContributionID,
                removeDraftCongress: removeDraftCongress
            )
            .id(selectedRow.id)
        } else {
            AppWorkspaceEmptyStateView(
                title: language.text("No congress selected", "Ingen kongress vald"),
                subtitle: language.text("Select a congress from the list.", "Välj en kongress i listan."),
                kind: .congresses
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppPalette.detailPanelSurface)
        }
    }

    private var rowsSignature: String {
        rows.map {
            [
                $0.id,
                $0.title,
                $0.organizationName,
                $0.congress.from,
                $0.congress.to,
                $0.congress.abstractSubmissionDeadline,
                $0.congress.lateAbstractSubmissionDeadline,
                $0.congress.venue,
                $0.congress.city,
                $0.congress.country,
                $0.congress.link,
                "\($0.congress.isEditingLocked)",
                "\($0.contributionCount)",
                "\($0.isPast)",
                $0.statusTone.rawValue
            ].joined(separator: "|")
        }
            .joined(separator: "||")
    }

    private func refreshCongressTodayKeyIfNeeded(reason: String) {
        let nextKey = Self.todayKey()
        guard nextKey != congressTodayKey else { return }
        congressTodayKey = nextKey
        rebuildCongressRows(reason: reason)
    }

    private func refreshCongressRowsAfterOpenAndAtNextDay() async {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guard !Task.isCancelled else { return }
        await MainActor.run {
            refreshCongressTodayKeyIfNeeded(reason: "open-delay")
        }

        try? await Task.sleep(nanoseconds: Self.nextDayRefreshDelay())
        guard !Task.isCancelled else { return }
        await MainActor.run {
            refreshCongressTodayKeyIfNeeded(reason: "day-boundary")
        }
    }

    private func rebuildCongressRows(reason: String) {
        congressRowsBuildGeneration &+= 1
        let generation = congressRowsBuildGeneration
        congressRowsBuildTask?.cancel()
        let snapshot = CongressRowsBuildSnapshot(
            organizations: store.organizationsForCongressRead,
            contributions: store.cvConferenceContributions,
            drafts: draftCongresses,
            currentUserAuthor: currentUserAuthor,
            language: language,
            today: Date()
        )
        let startedAt = CFAbsoluteTimeGetCurrent()
        congressRowsBuildTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                guard !Task.isCancelled else { return (rows: [CongressWorkspaceRow](), signature: "") }
                let rows = Self.buildRows(from: snapshot)
                guard !Task.isCancelled else { return (rows: [CongressWorkspaceRow](), signature: "") }
                return (rows, Self.rowsSignature(for: rows))
            }
            .value
            guard CongressRowsBuildGenerationPolicy.shouldPublish(
                    completedGeneration: generation,
                    currentGeneration: congressRowsBuildGeneration,
                    isCancelled: Task.isCancelled
                  ),
                  !result.signature.isEmpty else {
                return
            }
            if result.signature != cachedRowsSignature {
                cachedRows = result.rows
                cachedRowsSignature = result.signature
            }
            let duration = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            if duration >= 24 {
                store.appendPerformanceDiagnostic(
                    String(
                        format: "congress-rows-rebuild reason=%@ rows=%ld total_ms=%.2f",
                        reason,
                        result.rows.count,
                        duration
                    )
                )
            }
        }
    }

    nonisolated private static func rowsSignature(for rows: [CongressWorkspaceRow]) -> String {
        rows.map {
            [
                $0.id,
                $0.title,
                $0.organizationName,
                $0.congress.from,
                $0.congress.to,
                $0.congress.abstractSubmissionDeadline,
                $0.congress.lateAbstractSubmissionDeadline,
                $0.congress.venue,
                $0.congress.city,
                $0.congress.country,
                $0.congress.link,
                "\($0.congress.isEditingLocked)",
                "\($0.contributionCount)",
                "\($0.isPast)",
                $0.statusTone.rawValue
            ].joined(separator: "|")
        }
        .joined(separator: "||")
    }

    private static func todayKey() -> String {
        DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date()))
    }

    private static func nextDayRefreshDelay(now: Date = Date()) -> UInt64 {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(86_400)
        let seconds = max(1, nextDay.timeIntervalSince(now) + 5)
        return UInt64(seconds * 1_000_000_000)
    }

    private func congressListDateText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "-" }
        return DateParsers.canonicalizedDayInput(trimmed).nonEmpty ?? trimmed
    }

    private var yearRangeText: String {
        let lower = Int(min(minimumYearValue, maximumYearValue).rounded())
        let upper = Int(max(minimumYearValue, maximumYearValue).rounded())
        return "\(language.text("Date", "Datum")): \(lower)-\(upper)"
    }

    private var minimumYearSliderBinding: Binding<Double> {
        Binding(
            get: { minimumYearValue },
            set: { newValue in
                minimumYearValue = min(newValue, maximumYearValue)
                updateCongressRangeFollowingAfterUserEdit()
            }
        )
    }

    private var maximumYearSliderBinding: Binding<Double> {
        Binding(
            get: { maximumYearValue },
            set: { newValue in
                maximumYearValue = max(newValue, minimumYearValue)
                updateCongressRangeFollowingAfterUserEdit()
            }
        )
    }

    /// Round 16: a range dragged back to cover every year follows new years
    /// again; a narrowed range is kept as chosen.
    private func updateCongressRangeFollowingAfterUserEdit() {
        let follows = minimumYearValue <= yearBounds.lowerBound && maximumYearValue >= yearBounds.upperBound
        if dateFiltersFollowAvailableRange != follows {
            dateFiltersFollowAvailableRange = follows
        }
    }

    private func clampYearFiltersToAvailableRows() {
        // Round 16: the rows are built in the background. Before they exist
        // the bounds are just the current year, and clamping then collapsed a
        // saved range; it is fitted when the rows arrive instead.
        guard !availableYears.isEmpty else { return }
        let bounds = yearBounds
        if dateFiltersFollowAvailableRange || (minimumYearValue == 0 && maximumYearValue == 0) {
            if minimumYearValue != bounds.lowerBound { minimumYearValue = bounds.lowerBound }
            if maximumYearValue != bounds.upperBound { maximumYearValue = bounds.upperBound }
            if !dateFiltersFollowAvailableRange { dateFiltersFollowAvailableRange = true }
        } else {
            let lower = min(max(minimumYearValue, bounds.lowerBound), bounds.upperBound)
            let upper = min(max(maximumYearValue, bounds.lowerBound), bounds.upperBound)
            if minimumYearValue != lower { minimumYearValue = lower }
            if maximumYearValue != upper { maximumYearValue = upper }
        }
        if !yearFilterIsNarrowed {
            // A range covering every year is no filter, so it must not make
            // the list say "kept from last time".
            for key in ["MinimumYear", "MaximumYear", "FollowsRange"] {
                RestoredListFilters.markChanged(key: "Congresses.Filter.\(key)")
            }
        }
    }

    private func resetCongressYearRange() {
        dateFiltersFollowAvailableRange = true
        if availableYears.isEmpty {
            minimumYearValue = 0
            maximumYearValue = 0
        } else {
            minimumYearValue = yearBounds.lowerBound
            maximumYearValue = yearBounds.upperBound
        }
    }

    /// Round 16: clears every filter of this list (banner, empty list).
    private func clearAllCongressFilters() {
        searchText = ""
        hidesPassedCongresses = false
        hidesPassedAbstractDeadlines = false
        resetCongressYearRange()
        RestoredListFilters.forget(workspace: "Congresses")
    }

    private func clearCongressFiltersForDeactivationIfNeeded() {
        guard !store.shouldRetainListFilters(for: .congresses) else { return }
        guard hasActiveCongressFilters else { return }
        clearAllCongressFilters()
    }

    /// Round 16: with "keep filters" off in Settings, filters saved by an
    /// earlier run are cleared when the list is first shown.
    private func applyLaunchFilterPolicyIfNeeded() {
        guard !hasAppliedLaunchFilterPolicy else { return }
        hasAppliedLaunchFilterPolicy = true
        guard !store.shouldRetainListFilters(for: .congresses) else { return }
        clearAllCongressFilters()
    }

    private func reconcileSelection() {
        if let selectedCongressID,
           filteredRows.contains(where: { $0.id == selectedCongressID }) {
            return
        }
        selectedCongressID = filteredRows.first?.id
    }

    private func resetFiltersForDirectNavigation(toRevealRowID rowID: String) {
        guard !filteredRows.contains(where: { $0.id == rowID }) else { return }
        searchText = ""
        hidesPassedCongresses = false
        hidesPassedAbstractDeadlines = false
        dateFiltersFollowAvailableRange = true
        clampYearFiltersToAvailableRows()
    }

    private func consumeConferenceContributionRouteIfNeeded() {
        guard isActive else { return }
        guard let route = store.route,
              route.destination == .congresses || route.destination == .cv else { return }
        if route.recordID.hasPrefix("conferenceContribution:") {
            let contributionID = String(route.recordID.dropFirst("conferenceContribution:".count))
            guard let row = rows.first(where: { row in
                if row.primaryContributionID == contributionID {
                    return true
                }
                if case .contribution(let id) = row.source, id == contributionID {
                    return true
                }
                return false
            }) else { return }
            mode = .overview
            resetFiltersForDirectNavigation(toRevealRowID: row.id)
            selectedCongressID = row.id
            store.consumeRoute()
            DispatchQueue.main.async {
                selectedContributionID = contributionID
            }
        } else if route.recordID.hasPrefix("organizationCongress:") {
            let rowID = String(route.recordID.dropFirst("organizationCongress:".count))
            guard rows.contains(where: { $0.id == rowID }) else { return }
            mode = .overview
            resetFiltersForDirectNavigation(toRevealRowID: rowID)
            selectedCongressID = rowID
            selectedContributionID = nil
            store.consumeRoute()
        }
    }

    private func consumePendingCongressRouteIfNeeded() {
        guard isActive,
              let route = store.pendingCongressRoute,
              route.destination == .congresses else { return }
        let rowID = String(route.recordID.dropFirst("organizationCongress:".count))
        guard route.recordID.hasPrefix("organizationCongress:"),
              rows.contains(where: { $0.id == rowID }) else { return }

        mode = .overview
        resetFiltersForDirectNavigation(toRevealRowID: rowID)
        selectedCongressID = rowID
        selectedContributionID = nil
        store.consumePendingCongressRoute(route)
        if store.route?.requestID == route.requestID {
            store.consumeRoute()
        }
    }

    nonisolated fileprivate static func rowID(organizationID: String, congressID: String) -> String {
        "\(organizationID):\(congressID)"
    }

    nonisolated private static func contributionLinkKey(organizationID: String?, congressID: String?) -> String {
        "\(organizationID ?? "")\u{1F}\(congressID ?? "")"
    }

    nonisolated fileprivate static func draftRowID(congressID: String) -> String {
        "draft:\(congressID)"
    }

    nonisolated fileprivate static func contributionRowID(_ contributionID: String) -> String {
        "contribution:\(contributionID)"
    }

    private func addNewCongress() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        let congress = OrganizationCongress(title: language.text("New congress", "Ny kongress"))
        draftCongresses.insert(congress, at: 0)
        searchText = ""
        mode = .overview
        selectedContributionID = nil
        selectedCongressID = Self.draftRowID(congressID: congress.id)
    }

    private func removeDraftCongress(congressID: String) {
        draftCongresses.removeAll { $0.id == congressID }
    }

    private func toggleCongressSort(_ column: CongressListSortColumn) {
        if let existingIndex = sortHistory.firstIndex(where: { $0.column == column }) {
            if existingIndex == 0 {
                sortHistory[0].ascending.toggle()
            } else {
                let criterion = sortHistory.remove(at: existingIndex)
                sortHistory.insert(criterion, at: 0)
            }
        } else {
            sortHistory.insert(CongressListSortCriterion(column: column, ascending: column.defaultAscending), at: 0)
        }
        persistCongressSort()
    }

    private func resetCongressSort() {
        sortHistory = [
            CongressListSortCriterion(column: .from, ascending: true)
        ]
        persistCongressSort()
    }

    private func persistCongressSort() {
        ListSortPersistence.save(sortHistory, defaultsKey: "CongressesListSort")
    }

    private func sortRowsUsingSortHistory(_ lhs: CongressWorkspaceRow, _ rhs: CongressWorkspaceRow) -> Bool {
        var columns = sortHistory.map(\.column)
        for fallbackColumn in [CongressListSortColumn.from, .title, .organization] where !columns.contains(fallbackColumn) {
            columns.append(fallbackColumn)
        }
        for column in columns {
            let ascending = sortHistory.first(where: { $0.column == column })?.ascending ?? column.defaultAscending
            let comparison = compareCongressRows(lhs, rhs, column: column)
            if comparison != .orderedSame {
                return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
            }
        }
        return Self.sortRows(lhs, rhs)
    }

    private func compareCongressRows(
        _ lhs: CongressWorkspaceRow,
        _ rhs: CongressWorkspaceRow,
        column: CongressListSortColumn
    ) -> ComparisonResult {
        switch column {
        case .from:
            return Self.compareDates(lhs.startDate, rhs.startDate)
        case .abstractDeadline:
            return Self.compareDates(
                lhs.congress.abstractSubmissionDeadline.nonEmpty.flatMap(DateParsers.isoDay.date(from:)),
                rhs.congress.abstractSubmissionDeadline.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
            )
        case .lateAbstractDeadline:
            return Self.compareDates(
                lhs.congress.lateAbstractSubmissionDeadline.nonEmpty.flatMap(DateParsers.isoDay.date(from:)),
                rhs.congress.lateAbstractSubmissionDeadline.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
            )
        case .title:
            return lhs.title.localizedStandardCompare(rhs.title)
        case .organization:
            return lhs.organizationName.localizedStandardCompare(rhs.organizationName)
        case .place:
            return lhs.placeText.localizedStandardCompare(rhs.placeText)
        case .abstracts:
            if lhs.contributionCount == rhs.contributionCount { return .orderedSame }
            return lhs.contributionCount < rhs.contributionCount ? .orderedAscending : .orderedDescending
        }
    }

    nonisolated private static func compareDates(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (left?, right?) where left != right:
            return left < right ? .orderedAscending : .orderedDescending
        case (.some, nil):
            return .orderedAscending
        case (nil, .some):
            return .orderedDescending
        default:
            return .orderedSame
        }
    }

    nonisolated private static func sortRows(_ lhs: CongressWorkspaceRow, _ rhs: CongressWorkspaceRow) -> Bool {
        if lhs.isPast != rhs.isPast {
            return !lhs.isPast
        }
        switch (lhs.sortDate, rhs.sortDate) {
        case let (left?, right?) where left != right:
            return lhs.isPast ? left > right : left < right
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            break
        }
        if lhs.title != rhs.title {
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return lhs.organizationName.localizedStandardCompare(rhs.organizationName) == .orderedAscending
    }

    nonisolated fileprivate static func dateText(for congress: OrganizationCongress, language: AppLanguage) -> String {
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
            return [congress.from.nonEmpty, congress.to.nonEmpty].compactMap { $0 }.joined(separator: " - ")
        }
    }

    nonisolated fileprivate static func placeText(for congress: OrganizationCongress) -> String {
        [congress.venue.trimmedOrNil, congress.city.trimmedOrNil, congress.country.trimmedOrNil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    nonisolated fileprivate static func abstractText(for congress: OrganizationCongress, language: AppLanguage) -> String {
        let abstract = congress.abstractSubmissionDeadline.nonEmpty
        let late = congress.lateAbstractSubmissionDeadline.nonEmpty
        if let late {
            return language.text("Late abstract: \(late)", "Sen abstractfrist: \(late)")
        }
        if let abstract {
            return language.text("Abstract: \(abstract)", "Abstractfrist: \(abstract)")
        }
        return ""
    }

    nonisolated fileprivate static func syntheticCongress(from contribution: CVConferenceContribution, language: AppLanguage) -> OrganizationCongress {
        let title = contribution.localizedMeeting(language: language).nonEmpty
            ?? contribution.meetingSv.nonEmpty
            ?? contribution.meetingEn.nonEmpty
            ?? contribution.localizedTitle(language: language).nonEmpty
            ?? contribution.displayTitle
        let congressID = contribution.congressID?.trimmedOrNil ?? "contribution-\(contribution.id)"
        let deadline = contribution.submissionClosesOn.nonEmpty
            ?? contribution.submissionDecisionExpectedOn.nonEmpty
            ?? contribution.submissionAppliedOn.nonEmpty
            ?? ""
        return OrganizationCongress(
            id: congressID,
            title: title,
            from: contribution.from,
            to: contribution.to,
            abstractSubmissionDeadline: deadline,
            city: contribution.meetingCity,
            country: contribution.meetingCountry,
            link: contribution.congressLink
        )
    }

    nonisolated fileprivate static func statusTone(
        currentUserParticipates: Bool,
        linkedContributions: [CVConferenceContribution],
        isPast: Bool
    ) -> CongressWorkspaceStatusTone {
        CongressWorkspaceStatusTone(AppStatusTones.congressStatus(
            isAttending: currentUserParticipates,
            isPast: isPast,
            hasContribution: hasAbstractOrContributionData(linkedContributions: linkedContributions),
            hasRejectedContribution: linkedContributions.contains(where: \.isRejected)
        ))
    }

    nonisolated private static func hasAbstractOrContributionData(
        linkedContributions: [CVConferenceContribution]
    ) -> Bool {
        return linkedContributions.contains { contribution in
            contribution.localizedTitle(language: .swedish).trimmedOrNil != nil
                || contribution.localizedTitle(language: .english).trimmedOrNil != nil
                || contribution.localizedName(language: .swedish).trimmedOrNil != nil
                || contribution.localizedName(language: .english).trimmedOrNil != nil
                || contribution.contributorNames.contains(where: { $0.trimmedOrNil != nil })
                || contribution.submissionAppliedOn.trimmedOrNil != nil
                || contribution.submissionDecisionOn.trimmedOrNil != nil
                || contribution.submissionOutcome != nil
                || contribution.status == .presented
        }
    }

    nonisolated static func congressCurrentUserParticipates(
        _ congress: OrganizationCongress,
        currentUserAuthor: PublicationAuthor?
    ) -> Bool {
        guard let currentUserAuthor else { return false }
        if congress.participantAuthorIDs.contains(currentUserAuthor.id) {
            return true
        }
        return congressParticipantNames(congress, currentUserAuthor: currentUserAuthor)
            .contains(where: { congressSamePersonName($0, currentUserAuthor) })
    }

    nonisolated static func congressParticipantNames(
        _ congress: OrganizationCongress,
        currentUserAuthor: PublicationAuthor?
    ) -> [String] {
        let names = congress.participantNames.compactMap(\.trimmedOrNil)
        return Array(NSOrderedSet(array: names)) as? [String] ?? names
    }

    nonisolated static func congressSamePersonName(_ name: String, _ author: PublicationAuthor) -> Bool {
        let candidates = [author.displayName, author.name] + author.presentedNameCandidates
        return candidates.contains { congressSamePersonText(name, $0) }
    }

    nonisolated static func congressSamePersonText(_ lhs: String?, _ rhs: String?) -> Bool {
        let left = normalizedPublicationAuthorNameVariantKey(lhs ?? "")
        let right = normalizedPublicationAuthorNameVariantKey(rhs ?? "")
        return !left.isEmpty && left == right
    }

    nonisolated fileprivate static func contributionDateText(for contribution: CVConferenceContribution) -> String {
        switch (contribution.from.nonEmpty, contribution.to.nonEmpty) {
        case let (.some(from), .some(to)) where from != to:
            return "\(from)-\(to)"
        case let (.some(from), _):
            return from
        case let (_, .some(to)):
            return to
        default:
            return contribution.publicationYear.nonEmpty ?? "-"
        }
    }
}

private struct CongressDetailPane: View {
    @ObservedObject var store: GrantDataStore
    let row: CongressWorkspaceRow
    @Binding var selectedCongressID: String?
    @Binding var selectedContributionID: String?
    let removeDraftCongress: (String) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var draft: OrganizationCongress
    @State private var organizationText: String
    @State private var pendingParticipantText = ""
    @State private var participantFieldResetID = UUID()
    @State private var draggedParticipantName: String?
    @State private var editingParticipantOriginalName: String?
    @State private var editingParticipantText = ""
    @State private var pendingFundingApplicationText = ""
    @State private var showCompletedTasks = false
    @State private var detailFieldsHeight: CGFloat = 336
    @State private var showsDeferredMiniMap = false
    @State private var autosaveTask: DispatchWorkItem?
    @State private var forcedPersistTask: DispatchWorkItem?
    @State private var isDeletingCongress = false

    init(
        store: GrantDataStore,
        row: CongressWorkspaceRow,
        selectedCongressID: Binding<String?>,
        selectedContributionID: Binding<String?>,
        removeDraftCongress: @escaping (String) -> Void
    ) {
        self.store = store
        self.row = row
        self.removeDraftCongress = removeDraftCongress
        _selectedCongressID = selectedCongressID
        _selectedContributionID = selectedContributionID
        _draft = State(initialValue: row.congress)
        _organizationText = State(initialValue: row.hasOrganization ? row.organizationName : "")
    }

    private var language: AppLanguage { store.language }
    private var currentUserAuthor: PublicationAuthor? { store.currentUserAuthor() }
    private var isEditingLocked: Bool { draft.isEditingLocked }
    private static let detailDateFieldWidth: CGFloat = 190

    private var currentUserParticipatesInDraft: Bool {
        CongressesWorkspaceView.congressCurrentUserParticipates(draft, currentUserAuthor: currentUserAuthor)
    }

    private var displayedParticipantNames: [String] {
        CongressesWorkspaceView.congressParticipantNames(draft, currentUserAuthor: currentUserAuthor)
    }

    private var illogicalDateFieldKeys: Set<String> {
        illogicalCongressDateFieldKeys(for: draft)
    }

    private var undoRevealRouteRecordID: String {
        "organizationCongress:\(row.id)"
    }

    private func undoRevealIsActive(fieldKey: String) -> Bool {
        guard let target = store.undoRevealRequest?.target,
              (
                target.matches(routeDestination: .congresses, recordID: undoRevealRouteRecordID) ||
                target.matches(routeDestination: .cv, recordID: undoRevealRouteRecordID)
              ) else {
            return false
        }
        return target.fieldKey == fieldKey || (target.fieldKey == nil && fieldKey == "title")
    }

    private func syncDraftFromRow(_ congress: OrganizationCongress) {
        if draft.isEditingLocked, !congress.isEditingLocked {
            return
        }
        guard draft != congress else { return }
        draft = congress
        clearParticipantEditingState()
    }

    private var participantOptions: [String] {
        var names = store.publicationAuthors.map(\.displayName)
        names.append(contentsOf: store.organizationsForCongressRead.flatMap(\.congresses).flatMap(\.participantNames))
        names.append(contentsOf: store.calendarMeetingRecords.flatMap(\.participantNames))
        // Central tasks are the live source since the legacy-task migration;
        // the legacy arrays below only carry pre-migration stragglers.
        names.append(contentsOf: store.taskItems.flatMap(\.participantNames))
        names.append(contentsOf: store.teachingWorkspaceTasks.flatMap(\.participantNames))
        names.append(contentsOf: store.publications.flatMap(\.publicationTasks).flatMap(\.participantNames))
        names.append(contentsOf: store.projects.flatMap(\.projectTasks).flatMap(\.participantNames))
        return Array(Set(names))
        .compactMap(\.trimmedOrNil)
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var organization: OrganizationRecord? {
        store.organization(id: row.organizationID)
    }

    private var linkedContributions: [CVConferenceContribution] {
        switch row.source {
        case .organizationCongress:
            return store.cvConferenceContributions
                .filter { $0.congressOrganizationID == row.organizationID && $0.congressID == row.congressID }
                .sorted(by: contributionSort)
        case .contribution(let contributionID):
            return store.cvConferenceContributions
                .filter { $0.id == contributionID }
                .sorted(by: contributionSort)
        case .draft:
            return store.cvConferenceContributions
                .filter { $0.congressOrganizationID == nil && $0.congressID == row.congressID }
                .sorted(by: contributionSort)
        }
    }

    private var selectedContribution: CVConferenceContribution? {
        if let selectedContributionID,
           let contribution = linkedContributions.first(where: { $0.id == selectedContributionID }) {
            return contribution
        }
        return linkedContributions.first
    }

    private var selectedOrganizationFromText: OrganizationRecord? {
        organizationMatching(name: organizationText) ?? organization
    }

    private var calendarLinkedTravelFlights: [OrganizationCongressFlight] {
        guard case .organizationCongress = row.source else { return [] }
        return store.calendarTravelRecordsForRead.compactMap { record -> OrganizationCongressFlight? in
            var travel = record
            travel.normalize()
            guard travel.congressOrganizationID == row.organizationID,
                  travel.congressID == row.congressID else { return nil }
            var flight = OrganizationCongressFlight(
                id: travel.id,
                mode: travel.mode,
                fromCity: travel.fromCity,
                fromCountry: travel.fromCountry,
                toCity: travel.toCity,
                toCountry: travel.toCountry,
                fromDate: travel.date,
                fromTime: travel.departureTime,
                toDate: travel.resolvedArrivalDateString(),
                toTime: travel.arrivalTime
            )
            flight.normalize()
            return flight.isEmpty ? nil : flight
        }
        .sorted(by: travelFlightSortOrder)
    }

    private var calendarLinkedTravelHotels: [OrganizationCongressHotel] {
        guard case .organizationCongress = row.source else { return [] }
        return store.calendarAccommodationRecordsForRead.compactMap { record -> OrganizationCongressHotel? in
            var accommodation = record
            accommodation.normalize()
            guard accommodation.congressOrganizationID == row.organizationID,
                  accommodation.congressID == row.congressID else { return nil }
            var hotel = OrganizationCongressHotel(
                id: accommodation.id,
                hotelName: accommodation.hotelName,
                fromDate: accommodation.checkInDate,
                fromTime: accommodation.checkInTime,
                toDate: accommodation.checkOutDate,
                toTime: accommodation.checkOutTime
            )
            hotel.normalize()
            return hotel.isEmpty ? nil : hotel
        }
        .sorted { left, right in
            let leftKey = [left.fromDate, left.fromTime, left.toDate, left.toTime, left.hotelName].joined(separator: "|")
            let rightKey = [right.fromDate, right.fromTime, right.toDate, right.toTime, right.hotelName].joined(separator: "|")
            return leftKey.localizedStandardCompare(rightKey) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                titleBlock

                CongressPanel(title: language.text("Congress details", "Kongressdetaljer")) {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: isEditingLocked ? 9 : 14) {
                            organizationSelectionField
                                .frame(maxWidth: 520, alignment: .leading)

                            HStack(alignment: .top, spacing: 12) {
                                congressDateField(
                                    title: language.text("From", "Från"),
                                    text: binding(\.from),
                                    uncertain: boolBinding(\.fromUncertain),
                                    dateKeyPath: \.from,
                                    fieldKey: CongressDateValidationFieldKey.from,
                                    isIllogical: illogicalDateFieldKeys.contains(CongressDateValidationFieldKey.from),
                                    width: Self.detailDateFieldWidth
                                )
                                congressDateField(
                                    title: language.text("To", "Till"),
                                    text: binding(\.to),
                                    uncertain: boolBinding(\.toUncertain),
                                    dateKeyPath: \.to,
                                    fieldKey: CongressDateValidationFieldKey.to,
                                    isIllogical: illogicalDateFieldKeys.contains(CongressDateValidationFieldKey.to),
                                    width: Self.detailDateFieldWidth
                                )
                            }

                            HStack(alignment: .top, spacing: 12) {
                                congressDateField(
                                    title: language.text("Abstract deadline", "Abstractdeadline"),
                                    text: binding(\.abstractSubmissionDeadline),
                                    uncertain: boolBinding(\.abstractSubmissionDeadlineUncertain),
                                    dateKeyPath: \.abstractSubmissionDeadline,
                                    fieldKey: CongressDateValidationFieldKey.abstractSubmissionDeadline,
                                    isIllogical: illogicalDateFieldKeys.contains(CongressDateValidationFieldKey.abstractSubmissionDeadline),
                                    width: Self.detailDateFieldWidth
                                )
                                congressDateField(
                                    title: language.text("Late abstract deadline", "Sen abstractdeadline"),
                                    text: binding(\.lateAbstractSubmissionDeadline),
                                    uncertain: boolBinding(\.lateAbstractSubmissionDeadlineUncertain),
                                    dateKeyPath: \.lateAbstractSubmissionDeadline,
                                    fieldKey: CongressDateValidationFieldKey.lateAbstractSubmissionDeadline,
                                    isIllogical: illogicalDateFieldKeys.contains(CongressDateValidationFieldKey.lateAbstractSubmissionDeadline),
                                    width: Self.detailDateFieldWidth
                                )
                            }

                            HStack(alignment: .top, spacing: 12) {
                                congressTextField(
                                    title: language.text("Venue", "Plats"),
                                    placeholder: language.text("Venue", "Plats"),
                                    keyPath: \.venue,
                                    fieldKey: "venue",
                                    width: 220
                                )

                                congressTextField(
                                    title: language.text("City", "Ort"),
                                    placeholder: language.text("City", "Ort"),
                                    keyPath: \.city,
                                    fieldKey: "city",
                                    width: 220
                                )

                                congressCountryField
                            }

                            congressLinkField
                        }
                        .frame(width: 654, alignment: .leading)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(key: CongressDetailFieldsHeightPreferenceKey.self, value: proxy.size.height)
                            }
                        )

                        Group {
                            if showsDeferredMiniMap {
                                CongressMiniMapView(
                                    title: draft.title.nonEmpty ?? row.title,
                                    venue: draft.venue,
                                    city: draft.city,
                                    country: draft.country,
                                    language: language,
                                    mapHeight: detailFieldsHeight
                                )
                            } else {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(AppPalette.secondaryCardSurface)
                                    .overlay(
                                        Image(systemName: "map")
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    )
                                    .frame(height: detailFieldsHeight)
                            }
                        }
                        .frame(minWidth: 320, idealWidth: 380, maxWidth: .infinity, alignment: .top)
                    }
                    .onPreferenceChange(CongressDetailFieldsHeightPreferenceKey.self) { height in
                        guard height > 0 else { return }
                        detailFieldsHeight = max(220, height)
                    }
                }

                if !isEditingLocked || !displayedParticipantNames.isEmpty {
                    participationPanel
                }

                if currentUserParticipatesInDraft && (!isEditingLocked || hasVisibleCongressPlanningData) {
                    planningPanel
                }

                if !isEditingLocked || !linkedContributions.isEmpty {
                    CongressPanel(title: language.text("Abstracts", "Abstract")) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                AppTableHeaderText(text: language.text("\(linkedContributions.count) linked abstracts", "\(linkedContributions.count) kopplade abstract"))
                                Spacer()
                                if !isEditingLocked {
                                    Button {
                                        addContribution()
                                    } label: {
                                        Text(language.text("Add abstract", "Lägg till abstract"))
                                    }
                                    .appAddButtonStyle()
                                }
                            }

                            if linkedContributions.isEmpty {
                                Text(language.text("No abstracts linked to this congress yet.", "Inga abstract är kopplade till den här kongressen ännu."))
                                    .font(appFont(.secondary))
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(linkedContributions) { contribution in
                                        contributionButton(contribution)
                                        if contribution.id != linkedContributions.last?.id {
                                            Divider()
                                        }
                                    }
                                }
                                .background(AppPalette.secondaryCardSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(AppPalette.border.opacity(0.65), lineWidth: 1)
                                )
                            }
                        }
                    }
                }

                if let selectedContribution {
                    CVConferenceContributionDetailView(
                        store: store,
                        contribution: selectedContribution,
                        showsCongressField: false,
                        showsTaskList: false,
                        usesAbstractTerminology: true,
                        isEditingLocked: isEditingLocked
                    )
                        .frame(minHeight: 680)
                        .background(AppPalette.detailPanelSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .id(selectedContribution.id)

                    if !isEditingLocked || CentralTaskListSection.hasIncompleteTasks(
                        store: store,
                        linkKind: .conferenceContribution,
                        targetID: selectedContribution.id
                    ) {
                        CongressPanel(
                            title: language.text("Abstract task list", "Uppgiftslista för abstract"),
                            titleActionTitle: isEditingLocked ? nil : language.text("Add task", "Lägg till uppgift"),
                            titleAction: {
                                CentralTaskListSection.addTask(store: store, linkKind: .conferenceContribution, targetID: selectedContribution.id)
                            }
                        ) {
                            CentralTaskListSection(
                                store: store,
                                linkKind: .conferenceContribution,
                                targetID: selectedContribution.id,
                                language: language,
                                reminderOptions: ProjectTaskReminder.allCases,
                                isReadOnly: isEditingLocked,
                                showsAddButton: false
                            )
                        }
                    }
                }

                if !isEditingLocked || hasVisibleCongressTasks {
                    CongressPanel(
                        title: language.text("Task list", "Uppgiftslista"),
                        titleActionTitle: isEditingLocked ? nil : language.text("Add task", "Lägg till uppgift"),
                        titleAction: {
                            CentralTaskListSection.addTask(store: store, linkKind: .congress, targetID: draft.id, ownerID: row.organizationID)
                        }
                    ) {
                        CentralTaskListSection(
                            store: store,
                            linkKind: .congress,
                            targetID: draft.id,
                            ownerID: row.organizationID,
                            language: language,
                            reminderOptions: congressTaskReminderOptions,
                            isReadOnly: isEditingLocked,
                            showsAddButton: false
                        )
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppPalette.detailPanelSurface)
        .flushPendingAutosaveOnTextEnd(requestImmediateAutosave)
        .onDisappear {
            guard !isDeletingCongress else { return }
            forcedPersistTask?.cancel()
            persistAutosaveIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                requestImmediateAutosave()
            }
        }
        .onAppear {
            materializeLegacyHotelRowsIfNeeded()
            materializeCalendarLinkedTravelFlightsIfNeeded(schedulePersistence: true)
            materializeCalendarLinkedTravelHotelsIfNeeded(schedulePersistence: true)
            if selectedContributionID == nil {
                selectedContributionID = row.primaryContributionID
            }
            scheduleDeferredMiniMap()
        }
        .onReceive(
            store.$metadata.map { $0.calendarTravelRecords ?? [] }.removeDuplicates().dropFirst()
        ) { _ in
            // Deferred: @Published emits at willSet and the materializer
            // reads the store's committed state.
            DispatchQueue.main.async {
                materializeCalendarLinkedTravelFlightsIfNeeded(schedulePersistence: true)
            }
        }
        .onReceive(
            store.$metadata.map { $0.calendarAccommodationRecords ?? [] }.removeDuplicates().dropFirst()
        ) { _ in
            DispatchQueue.main.async {
                materializeCalendarLinkedTravelHotelsIfNeeded(schedulePersistence: true)
            }
        }
        .onChange(of: row.congress) { oldValue, newValue in
            syncDraftFromRow(newValue)
            if oldValue.title != newValue.title
                || oldValue.venue != newValue.venue
                || oldValue.city != newValue.city
                || oldValue.country != newValue.country {
                scheduleDeferredMiniMap()
            }
        }
        .onChange(of: row.congress.travelFlights) { _, newValue in
            mergeTravelFlightsIntoDraft(newValue)
        }
    }

    private func scheduleDeferredMiniMap() {
        showsDeferredMiniMap = false
        let rowID = row.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard row.id == rowID else { return }
            showsDeferredMiniMap = true
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                if isEditingLocked {
                    Text(draft.title.trimmedOrNil ?? row.title.nonEmpty ?? language.text("Congress name", "Kongressnamn"))
                        .appTypography(.pageTitle)
                        .foregroundStyle(AppPalette.appText)
                        .lineLimit(1...2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(
                        "",
                        text: binding(\.title),
                        prompt: Text(row.title.nonEmpty ?? language.text("Congress name", "Kongressnamn")),
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .appTypography(.pageTitle)
                    .lineLimit(1...2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .undoRevealPulse(
                        triggerID: store.undoRevealRequest?.id,
                        isActive: undoRevealIsActive(fieldKey: "title"),
                        cornerRadius: 6
                    )
                }
                Spacer()
                congressEditorLockButton
                if canDeleteCongressRow && !isEditingLocked {
                    AppDestructiveActionButton(
                        title: language.text("Delete", "Ta bort"),
                        help: language.text("Delete congress", "Ta bort kongress")
                        // No cancelTitle: requestDeleteCongress() shows its own alert.
                    ) {
                        requestDeleteCongress()
                    }
                }
            }
        }
    }

    private var canDeleteCongressRow: Bool {
        switch row.source {
        case .organizationCongress, .draft:
            return true
        case .contribution:
            return false
        }
    }

    private var congressTaskReminderOptions: [ProjectTaskReminder] {
        [.none, .manualFollowUp, .congressStart, .congressEnd, .abstractDeadline, .lateAbstractDeadline]
    }

    private var hasVisibleCongressTasks: Bool {
        CentralTaskListSection.hasIncompleteTasks(
            store: store,
            linkKind: .congress,
            targetID: draft.id,
            ownerID: row.organizationID
        )
    }

    private var hasVisibleCongressPlanningData: Bool {
        !persistedOrganizationCongressFlights(from: draft.travelFlights).isEmpty
            || !persistedOrganizationCongressHotels(from: organizationCongressHotelsForPersistence(draft)).isEmpty
            || draft.congressFeeSEK.trimmedOrNil != nil
            || draft.congressFeePaid
            || !draft.fundingApplicationIDs.compactMap(\.trimmedOrNil).isEmpty
    }

    private var visibleTravelFlights: [OrganizationCongressFlight] {
        isEditingLocked
            ? persistedOrganizationCongressFlights(from: draft.travelFlights)
            : draft.travelFlights
    }

    private var visibleTravelHotels: [OrganizationCongressHotel] {
        isEditingLocked
            ? persistedOrganizationCongressHotels(from: organizationCongressHotelsForPersistence(draft))
            : draft.travelHotels
    }

    private var shouldShowTravelSection: Bool {
        !isEditingLocked || !visibleTravelFlights.isEmpty
    }

    private var shouldShowHotelSection: Bool {
        !isEditingLocked || !visibleTravelHotels.isEmpty
    }

    private var hasVisibleCongressFeeData: Bool {
        draft.congressFeeSEK.trimmedOrNil != nil || draft.congressFeePaid
    }

    private var hasVisibleFundingApplications: Bool {
        !draft.fundingApplicationIDs.compactMap(\.trimmedOrNil).isEmpty
    }

    private var shouldShowCongressFeeAndFundingSection: Bool {
        !isEditingLocked || hasVisibleCongressFeeData || hasVisibleFundingApplications
    }

    private var organizationOptions: [String] {
        store.organizations
            .map { $0.displayName(for: language) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var congressEditorLockButton: some View {
        AppEditorLockButton(isLocked: isEditingLocked, language: language) {
            toggleEditingLock()
        }
        .accessibilityLabel(
            Text(
                isEditingLocked
                    ? language.text("Unlock editing", "Lås upp redigering")
                    : language.text("Lock editing", "Lås redigering")
            )
        )
    }

    private func toggleEditingLock() {
        let nextValue = !isEditingLocked
        if !nextValue {
            draft.isEditingLocked = false
            persistAutosaveIfNeeded()
            return
        }
        NSApp.keyWindow?.makeFirstResponder(nil)
        draft.isEditingLocked = true
        clearParticipantEditingState()
        persistAutosaveIfNeeded()
    }

    private func shouldShowCongressField(_ value: String?) -> Bool {
        AppLockedFieldVisibility.shouldShow(isLocked: isEditingLocked, value: value)
    }

    private func lockedCongressValueText(_ value: String?) -> some View {
        AppLockedInlineValueText(text: value)
    }

    @ViewBuilder
    private func congressFieldLabelText(_ text: String) -> some View {
        AppFieldLabelText(text: text)
    }

    private func localizedCongressCountry(_ value: String?) -> String? {
        guard let trimmed = value?.trimmedOrNil else { return nil }
        return language.localizedCountry(trimmed)
    }

    @ViewBuilder
    private var organizationSelectionField: some View {
        if shouldShowCongressField(organizationText) {
            VStack(alignment: .leading, spacing: isEditingLocked ? 2 : 6) {
                congressFieldLabelText(language.text("Organization", "Organisation"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    if isEditingLocked {
                        lockedCongressValueText(organizationText)
                    } else {
                        AutocompleteSelectionField(
                            text: $organizationText,
                            options: organizationOptions,
                            placeholder: language.text("Organization", "Organisation"),
                            onCommit: commitOrganizationSelection,
                            onSelect: { selectedName in
                                organizationText = selectedName
                                commitOrganizationSelection()
                            },
                            showsSuggestionsWithoutQuery: true
                        )
                    }

                    if !isEditingLocked || selectedOrganizationFromText != nil {
                        AppDestinationActionButton(
                            kind: .app,
                            language: language,
                            title: language.text("Open organization", "Öppna organisation"),
                            fontSize: 12,
                            width: 42,
                            height: 28,
                            tint: selectedOrganizationFromText == nil ? Color.secondary.opacity(0.55) : AppPalette.linkAction,
                            isEnabled: selectedOrganizationFromText != nil
                        ) {
                            openSelectedOrganization()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func congressTextField(
        title: String,
        placeholder: String,
        keyPath: WritableKeyPath<OrganizationCongress, String>,
        fieldKey: String,
        width: CGFloat
    ) -> some View {
        if shouldShowCongressField(draft[keyPath: keyPath]) {
            VStack(alignment: .leading, spacing: isEditingLocked ? 2 : 6) {
                congressFieldLabelText(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                AppLockableField(isLocked: isEditingLocked, lockedText: draft[keyPath: keyPath]) {
                    TextField(placeholder, text: binding(keyPath))
                        .appTextInputChrome()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: width, alignment: .leading)
            .undoRevealPulse(
                triggerID: store.undoRevealRequest?.id,
                isActive: undoRevealIsActive(fieldKey: fieldKey),
                cornerRadius: 8
            )
        }
    }

    @ViewBuilder
    private var congressCountryField: some View {
        if shouldShowCongressField(draft.country) {
            VStack(alignment: .leading, spacing: isEditingLocked ? 2 : 6) {
                congressFieldLabelText(language.text("Country", "Land"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                AppLockableField(isLocked: isEditingLocked, lockedText: localizedCongressCountry(draft.country)) {
                    CountryPickerField(selection: binding(\.country), language: language, width: 190)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 190, alignment: .leading)
            .undoRevealPulse(
                triggerID: store.undoRevealRequest?.id,
                isActive: undoRevealIsActive(fieldKey: "country"),
                cornerRadius: 8
            )
        }
    }

    @ViewBuilder
    private var congressLinkField: some View {
        if shouldShowCongressField(draft.link) {
            HStack(spacing: 8) {
                AppLockableField(isLocked: isEditingLocked, lockedText: draft.link) {
                    TextField(language.text("Link", "Länk"), text: binding(\.link))
                        .appTextInputChrome()
                }
                if !isEditingLocked || normalizedWebLinkURL(draft.link) != nil {
                    AppDestinationActionButton(
                        kind: .web,
                        language: language,
                        title: language.text("Open link", "Öppna länk"),
                        fontSize: 12,
                        width: 42,
                        height: 28,
                        tint: normalizedWebLinkURL(draft.link) == nil ? Color.secondary.opacity(0.55) : AppPalette.linkAction,
                        isEnabled: normalizedWebLinkURL(draft.link) != nil
                    ) {
                        if let url = normalizedWebLinkURL(draft.link) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .undoRevealPulse(
                triggerID: store.undoRevealRequest?.id,
                isActive: undoRevealIsActive(fieldKey: "link"),
                cornerRadius: 8
            )
        }
    }

    private var fundingApplicationOptions: [String] {
        fundingApplicationCandidates
            .sorted {
                fundingApplicationLabel($0).localizedStandardCompare(fundingApplicationLabel($1)) == .orderedAscending
            }
            .map(fundingApplicationLabel)
    }

    private var fundingApplicationCandidates: [GrantApplication] {
        store.applications.filter(\.isGranted)
    }

    private var participationPanel: some View {
        let participantNameFieldWidth: CGFloat = ResearcherNameFieldMetrics.compactWidth
        let participantLinkColumnWidth: CGFloat = 34
        let participantTrashColumnWidth: CGFloat = 28
        return CongressPanel(title: language.text("Participation", "Medverkan")) {
            VStack(alignment: .leading, spacing: isEditingLocked ? 6 : AutocompleteSelectionMetrics.rowSpacing) {
                if !displayedParticipantNames.isEmpty {
                    VStack(alignment: .leading, spacing: isEditingLocked ? 3 : AutocompleteSelectionMetrics.rowSpacing) {
                        ForEach(displayedParticipantNames, id: \.self) { name in
                            HStack(spacing: 8) {
                                if !isEditingLocked {
                                    ReorderHandle(itemID: name, draggedItemID: $draggedParticipantName, language: language)
                                    participantNameField(for: name, width: participantNameFieldWidth)
                                    participantLinkButton(for: name, width: participantLinkColumnWidth)
                                    AppInlineDeleteButton(
                                        title: language.text("Delete participant", "Ta bort deltagare"),
                                        width: participantTrashColumnWidth
                                    ) {
                                        removeParticipant(named: name)
                                    }
                                } else {
                                    participantNameControl(for: name, width: participantNameFieldWidth)
                                }
                            }
                            .frame(minHeight: isEditingLocked ? 22 : AutocompleteSelectionMetrics.fieldMinHeight, alignment: .center)
                            .onDrop(of: [UTType.plainText], delegate: StringReorderDropDelegate(
                                targetID: name,
                                items: $draft.participantNames,
                                draggedItemID: $draggedParticipantName,
                                onReorder: {
                                    draft.participantNames = normalizedParticipantNames(draft.participantNames)
                                    scheduleAutosave()
                                }
                            ))
                        }
                    }
                }

                if !isEditingLocked {
                    HStack(spacing: 8) {
                        Color.clear.frame(width: 20, height: 20)
                        AutocompleteSelectionField(
                            text: $pendingParticipantText,
                            options: participantOptions,
                            excludedOptions: Set(displayedParticipantNames),
                            placeholder: language.text("Add person", "Lägg till individ"),
                            onCommit: addPendingParticipant,
                            onSelect: { selectedName in
                                pendingParticipantText = selectedName
                                addPendingParticipant()
                            },
                            showsSuggestionsWithoutQuery: true
                        )
                        .frame(width: participantNameFieldWidth, alignment: .leading)
                        .id(participantFieldResetID)
                        GroupMailButton(
                            addresses: store.groupMailAddresses(
                                authorIDs: draft.participantAuthorIDs,
                                presentedNames: displayedParticipantNames
                            ),
                            language: language
                        )
                        Color.clear.frame(width: participantLinkColumnWidth, height: 20)
                        Color.clear.frame(width: participantTrashColumnWidth, height: 20)
                    }
                } else {
                    HStack {
                        Spacer()
                        GroupMailButton(
                            addresses: store.groupMailAddresses(
                                authorIDs: draft.participantAuthorIDs,
                                presentedNames: displayedParticipantNames
                            ),
                            language: language
                        )
                    }
                }
            }
            .undoRevealPulse(
                triggerID: store.undoRevealRequest?.id,
                isActive: undoRevealIsActive(fieldKey: "participants"),
                cornerRadius: 8
            )
        }
    }

    @ViewBuilder
    private func participantNameField(for name: String, width: CGFloat) -> some View {
        AutocompleteSelectionField(
            text: participantBinding(for: name),
            options: participantOptions,
            excludedOptions: Set(displayedParticipantNames.filter {
                !CongressesWorkspaceView.congressSamePersonText($0, name)
            }),
            placeholder: language.text("Person", "Person"),
            onCommit: {
                scheduleAutosave()
            },
            showsSuggestionsWithoutQuery: true
        )
        .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private func participantNameControl(for name: String, width: CGFloat) -> some View {
        if let author = participantAuthor(for: name) {
            Button(action: { store.openRoute(for: author) }) {
                HStack(spacing: 8) {
                    Image(systemName: "person")
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(appFont(.body).weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(language.text("Open researcher", "Öppna forskare"))
            .frame(width: width, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "person")
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(appFont(.body).weight(.medium))
                    .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
        }
    }

    @ViewBuilder
    private func participantLinkButton(for name: String, width: CGFloat) -> some View {
        if let author = participantAuthor(for: name) {
            AppRouteLinkButton(
                title: language.text("Open researcher", "Öppna forskare"),
                language: language,
                width: width
            ) {
                store.openRoute(for: author)
            }
        } else {
            Color.clear
                .frame(width: width, height: 20)
        }
    }

    private var planningPanel: some View {
        CongressPanel(title: language.text("Travel planning", "Reseplanering")) {
            VStack(alignment: .leading, spacing: isEditingLocked ? 10 : 16) {
                if shouldShowTravelSection {
                    VStack(alignment: .leading, spacing: isEditingLocked ? 5 : 10) {
                        if !isEditingLocked {
                            HStack {
                                Spacer()
                                Button {
                                    draft.travelFlights.append(OrganizationCongressFlight())
                                    scheduleAutosave()
                                } label: {
                                    Text(language.text("Add travel", "Lägg till resa"))
                                }
                                .appAddButtonStyle()
                            }
                        }

                        if visibleTravelFlights.isEmpty {
                            Text(language.text("No travel rows added yet.", "Inga resor tillagda ännu."))
                                .font(appFont(.secondary))
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                VStack(alignment: .leading, spacing: isEditingLocked ? 1 : 6) {
                                    flightHeaderRow
                                    ForEach(visibleTravelFlights) { flight in
                                        if isEditingLocked {
                                            lockedFlightRow(flight)
                                        } else {
                                            flightEditor(flightID: flight.id)
                                        }
                                    }
                                }
                                .frame(minWidth: 1068, alignment: .leading)
                            }
                        }
                    }
                }

                if shouldShowHotelSection {
                    hotelPlanningSection
                }

                if shouldShowCongressFeeAndFundingSection {
                    HStack(alignment: .top, spacing: 12) {
                        if !isEditingLocked || hasVisibleCongressFeeData {
                            VStack(alignment: .leading, spacing: isEditingLocked ? 2 : 6) {
                                AppFieldAlignedTableHeaderText(text: language.text("Congress fee (SEK)", "Kongressavgift (kr)"))
                                if isEditingLocked {
                                    if draft.congressFeeSEK.trimmedOrNil != nil {
                                        lockedCongressValueText(draft.congressFeeSEK)
                                    }
                                    if draft.congressFeePaid {
                                        lockedCongressValueText(language.text("Paid", "Betald"))
                                    }
                                } else {
                                    TextField("SEK", text: binding(\.congressFeeSEK))
                                        .appTextInputChrome()
                                    Toggle(
                                        language.text("Paid", "Betald"),
                                        isOn: boolBinding(\.congressFeePaid)
                                    )
                                    .appCheckboxStyle()
                                }
                            }
                            .frame(width: 180)
                        }

                        if !isEditingLocked || hasVisibleFundingApplications {
                            VStack(alignment: .leading, spacing: isEditingLocked ? 4 : 8) {
                                AppTableHeaderText(text: language.text("Paying grants", "Anslag som betalar"))

                                if !draft.fundingApplicationIDs.isEmpty {
                                    ForEach(draft.fundingApplicationIDs, id: \.self) { applicationID in
                                        HStack(spacing: 8) {
                                            Text(fundingApplicationLabel(forID: applicationID))
                                                .font(appFont(.secondary))
                                                .lineLimit(1)
                                            Spacer()
                                            if let application = store.application(id: applicationID) {
                                                AppDestinationActionButton(
                                                    kind: .app,
                                                    language: language,
                                                    title: language.text("Open application", "Öppna ansökan"),
                                                    fontSize: 12
                                                ) {
                                                    store.openRoute(for: application)
                                                }
                                            }
                                            if !isEditingLocked {
                                                AppInlineDeleteButton(
                                                    title: language.text("Remove funding application", "Ta bort finansieringsansökan")
                                                ) {
                                                    draft.fundingApplicationIDs.removeAll { $0 == applicationID }
                                                    scheduleAutosave()
                                                }
                                            }
                                        }
                                        .padding(.horizontal, isEditingLocked ? 0 : 8)
                                        .padding(.vertical, isEditingLocked ? 0 : 5)
                                        .background(
                                            isEditingLocked
                                                ? Color.clear
                                                : AppPalette.secondaryCardSurface,
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        )
                                    }
                                }

                                if !isEditingLocked {
                                    HStack(spacing: 8) {
                                        AutocompleteSelectionField(
                                            text: $pendingFundingApplicationText,
                                            options: fundingApplicationOptions,
                                            excludedOptions: Set(draft.fundingApplicationIDs.map(fundingApplicationLabel(forID:))),
                                            placeholder: language.text("Add grant", "Lägg till anslag"),
                                            onCommit: addPendingFundingApplication,
                                            onSelect: { selectedName in
                                                pendingFundingApplicationText = selectedName
                                                addPendingFundingApplication()
                                            },
                                            showsSuggestionsWithoutQuery: true
                                        )
                                        Button(language.text("Add", "Lägg till")) {
                                            addPendingFundingApplication()
                                        }
                                        .appAddButtonStyle()
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private var hotelPlanningSection: some View {
        VStack(alignment: .leading, spacing: isEditingLocked ? 5 : 10) {
            if !isEditingLocked {
                HStack {
                    Spacer()
                    Button {
                        materializeLegacyHotelRowsIfNeeded()
                        draft.travelHotels.append(OrganizationCongressHotel())
                        scheduleAutosave()
                    } label: {
                        Text(language.text("Add hotel row", "Lägg till hotellrad"))
                    }
                    .appAddButtonStyle()
                }
            }

            if visibleTravelHotels.isEmpty {
                Text(language.text("No hotel rows added yet.", "Inga hotellrader tillagda ännu."))
                    .font(appFont(.secondary))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: isEditingLocked ? 1 : 6) {
                        hotelHeaderRow
                        ForEach(visibleTravelHotels) { hotel in
                            if isEditingLocked {
                                lockedHotelRow(hotel)
                            } else {
                                hotelEditor(hotelID: hotel.id)
                            }
                        }
                    }
                    .frame(minWidth: 792, alignment: .leading)
                }
            }
        }
    }

    private func flightEditor(flightID: String) -> some View {
        let revealDate = calendarRevealDateForFlight(flightID)
        return HStack(alignment: .center, spacing: 6) {
            AppMenuSelectionField(
                selection: flightModeBinding(flightID),
                options: CalendarTravelMode.allCases.map { ($0.localizedName(language: language), $0) }
            )
            .frame(width: 96)
            .allowsHitTesting(!isEditingLocked)

            TextField(language.text("From city", "Från ort"), text: flightBinding(flightID, \.fromCity))
                .appTextInputChrome()
                .frame(width: 112)
                .allowsHitTesting(!isEditingLocked)

            CountryPickerField(selection: flightBinding(flightID, \.fromCountry), language: language, width: 128)
                .allowsHitTesting(!isEditingLocked)

            flightDateField(text: flightBinding(flightID, \.fromDate))
                .frame(width: 112)
                .allowsHitTesting(!isEditingLocked)

            flightTimeField(text: flightBinding(flightID, \.fromTime))
                .frame(width: 72)
                .allowsHitTesting(!isEditingLocked)

            TextField(language.text("To city", "Till ort"), text: flightBinding(flightID, \.toCity))
                .appTextInputChrome()
                .frame(width: 112)
                .allowsHitTesting(!isEditingLocked)

            CountryPickerField(selection: flightBinding(flightID, \.toCountry), language: language, width: 128)
                .allowsHitTesting(!isEditingLocked)

            flightDateField(text: flightBinding(flightID, \.toDate))
                .frame(width: 112)
                .allowsHitTesting(!isEditingLocked)

            flightTimeField(text: flightBinding(flightID, \.toTime))
                .frame(width: 72)
                .allowsHitTesting(!isEditingLocked)

            calendarRowLinkButton(isEnabled: revealDate != nil) {
                openFlightInCalendar(flightID: flightID, date: revealDate)
            }

            if !isEditingLocked {
                AppInlineDeleteButton(
                    title: language.text("Remove travel row", "Ta bort reserad"),
                    width: 24
                ) {
                    removeCalendarTravelRecordIfLinked(flightID)
                    draft.travelFlights.removeAll { $0.id == flightID }
                    scheduleAutosave()
                }
                .frame(height: 28)
            } else {
                Color.clear
                    .frame(width: 24, height: 28)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AppPalette.secondaryCardSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppPalette.border.opacity(0.55), lineWidth: 1)
        )
    }

    private func lockedFlightRow(_ flight: OrganizationCongressFlight) -> some View {
        let revealDate = DateParsers.isoDay.date(from: DateParsers.canonicalizedDayInput(flight.fromDate))
        return HStack(alignment: .center, spacing: 6) {
            lockedPlanningCell(flight.mode.localizedName(language: language), width: 96)
            lockedPlanningCell(flight.fromCity, width: 112)
            lockedPlanningCell(localizedPlanningCountry(flight.fromCountry), width: 128)
            lockedPlanningCell(flight.fromDate, width: 112)
            lockedPlanningCell(flight.fromTime, width: 72)
            lockedPlanningCell(flight.toCity, width: 112)
            lockedPlanningCell(localizedPlanningCountry(flight.toCountry), width: 128)
            lockedPlanningCell(flight.toDate, width: 112)
            lockedPlanningCell(flight.toTime, width: 72)
            calendarRowLinkButton(isEnabled: revealDate != nil, height: 20) {
                openFlightInCalendar(flightID: flight.id, date: revealDate)
            }
            Color.clear.frame(width: 24, height: 20)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 0)
    }

    private var flightHeaderRow: some View {
        HStack(alignment: .center, spacing: 6) {
            flightColumnHeader(language.text("Mode", "Färdsätt"), width: 96)
            flightColumnHeader(language.text("From city", "Från ort"), width: 112)
            flightColumnHeader(language.text("From country", "Från land"), width: 128)
            flightColumnHeader(language.text("From date", "Från datum"), width: 112)
            flightColumnHeader(language.text("From time", "Tid från"), width: 72)
            flightColumnHeader(language.text("To city", "Till ort"), width: 112)
            flightColumnHeader(language.text("To country", "Till land"), width: 128)
            flightColumnHeader(language.text("To date", "Till datum"), width: 112)
            flightColumnHeader(language.text("To time", "Tid till"), width: 72)
            Color.clear.frame(width: 54)
        }
        .padding(.horizontal, 8)
    }

    private func flightColumnHeader(_ title: String, width: CGFloat) -> some View {
        AppTableHeaderText(text: title)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
    }

    private func flightDateField(text: Binding<String>) -> some View {
        CommitDateFieldWithTodayButton(
            placeholder: language.datePlaceholder,
            text: text,
            formatter: DateParsers.canonicalizedDayInput,
            updatesContinuously: false,
            width: 112,
            showsTodayButton: false
        )
        .frame(width: 112)
    }

    private func flightTimeField(text: Binding<String>) -> some View {
        CommitFormattingTextField(
            placeholder: "HH:MM",
            text: text,
            formatter: normalizedCalendarTimeInput,
            updatesContinuously: false
        )
        .frame(width: 72)
        .frame(minHeight: 18)
        .appTextInputChrome()
    }

    private var hotelHeaderRow: some View {
        HStack(alignment: .center, spacing: 8) {
            hotelColumnHeader(language.text("Hotel", "Hotell"), width: 220)
            hotelColumnHeader(language.text("Hotel from", "Hotell från"), width: 130)
            hotelColumnHeader(language.text("From time", "Tid från"), width: 96)
            hotelColumnHeader(language.text("Hotel to", "Hotell till"), width: 130)
            hotelColumnHeader(language.text("To time", "Tid till"), width: 96)
            Color.clear.frame(width: 56)
        }
        .padding(.horizontal, 8)
    }

    private func hotelEditor(hotelID: String) -> some View {
        let revealDate = calendarRevealDateForHotel(hotelID)
        return HStack(alignment: .center, spacing: 8) {
            TextField(language.text("Hotel name", "Hotellnamn"), text: hotelBinding(hotelID, \.hotelName))
                .appTextInputChrome()
                .frame(width: 220)
                .allowsHitTesting(!isEditingLocked)

            hotelDateField(text: hotelBinding(hotelID, \.fromDate))
                .frame(width: 130)
                .allowsHitTesting(!isEditingLocked)

            hotelTimeField(text: hotelBinding(hotelID, \.fromTime))
                .frame(width: 96)
                .allowsHitTesting(!isEditingLocked)

            hotelDateField(text: hotelBinding(hotelID, \.toDate))
                .frame(width: 130)
                .allowsHitTesting(!isEditingLocked)

            hotelTimeField(text: hotelBinding(hotelID, \.toTime))
                .frame(width: 96)
                .allowsHitTesting(!isEditingLocked)

            calendarRowLinkButton(isEnabled: revealDate != nil) {
                openHotelInCalendar(hotelID: hotelID, date: revealDate)
            }

            if !isEditingLocked {
                AppInlineDeleteButton(
                    title: language.text("Remove hotel row", "Ta bort hotellrad"),
                    width: 24
                ) {
                    removeCalendarAccommodationRecordIfLinked(hotelID)
                    draft.travelHotels.removeAll { $0.id == hotelID }
                    syncLegacyHotelFieldsFromRows(&draft)
                    scheduleAutosave()
                }
                .frame(height: 28)
            } else {
                Color.clear
                    .frame(width: 24, height: 28)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AppPalette.secondaryCardSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppPalette.border.opacity(0.55), lineWidth: 1)
        )
    }

    private func lockedHotelRow(_ hotel: OrganizationCongressHotel) -> some View {
        let revealDate = DateParsers.isoDay.date(from: DateParsers.canonicalizedDayInput(hotel.fromDate))
            ?? DateParsers.isoDay.date(from: DateParsers.canonicalizedDayInput(hotel.toDate))
        return HStack(alignment: .center, spacing: 8) {
            lockedPlanningCell(hotel.hotelName, width: 220)
            lockedPlanningCell(hotel.fromDate, width: 130)
            lockedPlanningCell(hotel.fromTime, width: 96)
            lockedPlanningCell(hotel.toDate, width: 130)
            lockedPlanningCell(hotel.toTime, width: 96)
            calendarRowLinkButton(isEnabled: revealDate != nil, height: 20) {
                openHotelInCalendar(hotelID: hotel.id, date: revealDate)
            }
            Color.clear.frame(width: 24, height: 20)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 0)
    }

    private func lockedPlanningCell(_ value: String, width: CGFloat) -> some View {
        AppLockedInlineValueText(text: value.trimmedOrNil, lineLimit: 1)
            .frame(width: width, alignment: .leading)
            .frame(minHeight: 20, alignment: .leading)
    }

    private func localizedPlanningCountry(_ value: String) -> String {
        value.trimmedOrNil.map { language.localizedCountry($0) } ?? ""
    }

    private func hotelColumnHeader(_ title: String, width: CGFloat) -> some View {
        AppTableHeaderText(text: title)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
    }

    private func hotelDateField(text: Binding<String>) -> some View {
        CommitDateFieldWithTodayButton(
            placeholder: language.datePlaceholder,
            text: text,
            formatter: DateParsers.canonicalizedDayInput,
            updatesContinuously: false,
            width: 130,
            showsTodayButton: false
        )
        .frame(width: 130)
    }

    private func hotelTimeField(text: Binding<String>) -> some View {
        CommitFormattingTextField(
            placeholder: "HH:MM",
            text: text,
            formatter: normalizedCalendarTimeInput,
            updatesContinuously: false
        )
        .frame(width: 96)
        .frame(minHeight: 18)
        .appTextInputChrome()
    }

    private func calendarRowLinkButton(isEnabled: Bool, height: CGFloat = 28, action: @escaping () -> Void) -> some View {
        AppDestinationActionButton(
            kind: .app,
            language: language,
            title: language.text("Show in calendar", "Visa i kalendern"),
            fontSize: 12,
            width: 42,
            height: height,
            tint: isEnabled ? AppPalette.linkAction : Color.secondary.opacity(0.55),
            isEnabled: isEnabled,
            action: action
        )
    }

    private func calendarRevealDateForFlight(_ flightID: String) -> Date? {
        guard let flight = draft.travelFlights.first(where: { $0.id == flightID }) else { return nil }
        return DateParsers.isoDay.date(from: DateParsers.canonicalizedDayInput(flight.fromDate))
    }

    private func calendarRevealDateForHotel(_ hotelID: String) -> Date? {
        guard let hotel = draft.travelHotels.first(where: { $0.id == hotelID }) else { return nil }
        return DateParsers.isoDay.date(from: DateParsers.canonicalizedDayInput(hotel.fromDate))
            ?? DateParsers.isoDay.date(from: DateParsers.canonicalizedDayInput(hotel.toDate))
    }

    private func congressCalendarRevealDate(for keyPath: WritableKeyPath<OrganizationCongress, String>) -> Date? {
        DateParsers.isoDay.date(from: DateParsers.canonicalizedDayInput(draft[keyPath: keyPath]))
    }

    private func openCongressDateInCalendar(dateKeyPath: WritableKeyPath<OrganizationCongress, String>) {
        guard let date = congressCalendarRevealDate(for: dateKeyPath) else { return }
        persistAutosaveIfNeeded()
        store.revealCalendarWorkspace(
            on: date,
            eventSource: .congress(organizationID: row.organizationID, congressID: row.congressID)
        )
    }

    private func openFlightInCalendar(flightID: String, date: Date?) {
        guard let date else { return }
        persistAutosaveIfNeeded()
        store.revealCalendarWorkspace(on: date, eventSource: .travel(flightID))
    }

    private func openHotelInCalendar(hotelID: String, date: Date?) {
        guard let date else { return }
        persistAutosaveIfNeeded()
        store.revealCalendarWorkspace(on: date, eventSource: .accommodation(hotelID))
    }

    private func removeCalendarTravelRecordIfLinked(_ flightID: String) {
        let records = store.calendarTravelRecords
        guard records.contains(where: { $0.id == flightID }) else { return }
        store.autosaveCalendarTravelRecords(records.filter { $0.id != flightID })
    }

    private func removeCalendarAccommodationRecordIfLinked(_ hotelID: String) {
        let records = store.calendarAccommodationRecords
        guard records.contains(where: { $0.id == hotelID }) else { return }
        store.autosaveCalendarAccommodationRecords(records.filter { $0.id != hotelID })
    }

    private func contributionButton(_ contribution: CVConferenceContribution) -> some View {
        let isSelected = selectedContribution?.id == contribution.id
        return Button {
            selectedContributionID = contribution.id
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle)
                        .font(appFont(.body).weight(.semibold))
                        .foregroundStyle(AppPalette.appText)
                        .lineLimit(1)
                    Text([contribution.localizedName(language: language).nonEmpty, contribution.localizedProjectName(language: language).nonEmpty].compactMap { $0 }.joined(separator: " - "))
                        .font(appFont(.secondary))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(contributionDateText(contribution))
                    .font(appFont(.secondary).weight(.medium))
                    .foregroundStyle(.secondary)
                CongressMiniBadge(
                    text: contribution.effectiveStatus.displayName(language: language),
                    tone: AppStatusTones.conferenceContribution(contribution.effectiveStatus)
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(isSelected ? AppPalette.activeTabSurface.opacity(0.16) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func binding(_ keyPath: WritableKeyPath<OrganizationCongress, String>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { newValue in
                guard !isEditingLocked else { return }
                let previousFrom = draft.from
                draft[keyPath: keyPath] = newValue
                if keyPath == \OrganizationCongress.from,
                   let shiftedTo = shiftedDateRangeEnd(
                       previousStart: previousFrom,
                       newStart: newValue,
                       currentEnd: draft.to
                   ) {
                    draft.to = shiftedTo
                }
                clearUncertaintyFlagsForBlankDates()
                scheduleAutosave()
            }
        )
    }

    private func flightBinding(_ flightID: String, _ keyPath: WritableKeyPath<OrganizationCongressFlight, String>) -> Binding<String> {
        Binding(
            get: {
                draft.travelFlights.first(where: { $0.id == flightID })?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                guard !isEditingLocked else { return }
                guard let index = draft.travelFlights.firstIndex(where: { $0.id == flightID }) else { return }
                draft.travelFlights[index][keyPath: keyPath] = newValue
                scheduleAutosave()
            }
        )
    }

    private func flightModeBinding(_ flightID: String) -> Binding<CalendarTravelMode> {
        Binding(
            get: {
                draft.travelFlights.first(where: { $0.id == flightID })?.mode ?? .flight
            },
            set: { newValue in
                guard !isEditingLocked else { return }
                guard let index = draft.travelFlights.firstIndex(where: { $0.id == flightID }) else { return }
                draft.travelFlights[index].mode = newValue
                scheduleAutosave()
            }
        )
    }

    private func hotelBinding(_ hotelID: String, _ keyPath: WritableKeyPath<OrganizationCongressHotel, String>) -> Binding<String> {
        Binding(
            get: {
                draft.travelHotels.first(where: { $0.id == hotelID })?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                guard !isEditingLocked else { return }
                guard let index = draft.travelHotels.firstIndex(where: { $0.id == hotelID }) else { return }
                draft.travelHotels[index][keyPath: keyPath] = newValue
                scheduleAutosave()
            }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<OrganizationCongress, Bool>) -> Binding<Bool> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { newValue in
                guard !isEditingLocked else { return }
                draft[keyPath: keyPath] = newValue
                clearUncertaintyFlagsForBlankDates()
                scheduleAutosave()
            }
        )
    }

    @ViewBuilder
    private func congressDateField(
        title: String,
        text: Binding<String>,
        uncertain: Binding<Bool>,
        dateKeyPath: WritableKeyPath<OrganizationCongress, String>,
        fieldKey: String,
        isIllogical: Bool = false,
        width: CGFloat
    ) -> some View {
        let value = draft[keyPath: dateKeyPath]
        if shouldShowCongressField(value) {
            let invalidFill = AppPalette.shadeRed.opacity(0.38)
            let invalidStroke = AppPalette.vividRed.opacity(0.68)
            VStack(alignment: .leading, spacing: isEditingLocked ? 2 : 6) {
                congressFieldLabelText(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    if isEditingLocked {
                        lockedCongressValueText(lockedCongressDateText(value, isUncertain: uncertain.wrappedValue))
                            .frame(width: width, alignment: .leading)
                    } else {
                        ZStack(alignment: .topTrailing) {
                            let hasDate = value.trimmedOrNil != nil
                            CommitDateFieldWithTodayButton(
                                placeholder: language.datePlaceholder,
                                text: text,
                                formatter: DateParsers.canonicalizedDayInput,
                                updatesContinuously: false,
                                width: width,
                                showsTodayButton: false,
                                fill: isIllogical ? invalidFill : AppPalette.fieldSurface,
                                stroke: isIllogical ? invalidStroke : AppPalette.subtleBorder,
                                contextMenuItems: [
                                    CommitFormattingTextFieldContextMenuItem(
                                        title: uncertain.wrappedValue
                                            ? language.text("Certain", "Säkert")
                                            : language.text("Uncertain", "Osäkert"),
                                        isEnabled: hasDate
                                    ) {
                                        uncertain.wrappedValue.toggle()
                                    }
                                ]
                            )
                            .frame(width: width)
                            .calendarDateStatusOutline(isUncertain: uncertain.wrappedValue)
                            .contextMenu {
                                if hasDate {
                                    Button(
                                        uncertain.wrappedValue
                                            ? language.text("Certain", "Säkert")
                                            : language.text("Uncertain", "Osäkert")
                                    ) {
                                        uncertain.wrappedValue.toggle()
                                    }
                                } else {
                                    Button(language.text("Uncertain", "Osäkert")) {}
                                        .disabled(true)
                                }
                            }

                            if uncertain.wrappedValue {
                                Text("?")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(AppPalette.statusText(.warning))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule(style: .continuous).fill(AppPalette.cardSurface))
                                    .padding(.top, 4)
                                    .padding(.trailing, 4)
                            }
                        }
                    }

                    if !isEditingLocked || congressCalendarRevealDate(for: dateKeyPath) != nil {
                        calendarRowLinkButton(isEnabled: congressCalendarRevealDate(for: dateKeyPath) != nil) {
                            openCongressDateInCalendar(dateKeyPath: dateKeyPath)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: width + 46, alignment: .leading)
            .undoRevealPulse(
                triggerID: store.undoRevealRequest?.id,
                isActive: undoRevealIsActive(fieldKey: fieldKey),
                cornerRadius: 8
            )
            .help(isIllogical ? language.text("Illogical date combination", "Ologisk datumkombination") : "")
        }
    }

    private func lockedCongressDateText(_ value: String, isUncertain: Bool) -> String? {
        guard let value = value.trimmedOrNil else { return nil }
        guard isUncertain else { return value }
        return "\(value) (?)"
    }

    private func plainCongressDateField(
        title: String,
        text: Binding<String>,
        width: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AppFieldLabelText(text: title)
            CommitDateFieldWithTodayButton(
                placeholder: language.datePlaceholder,
                text: text,
                formatter: DateParsers.canonicalizedDayInput,
                updatesContinuously: false,
                width: width,
                showsTodayButton: false
            )
            .frame(width: width)
        }
        .frame(width: width, alignment: .leading)
    }

    private func plainCongressTimeField(
        title: String,
        text: Binding<String>,
        width: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AppFieldLabelText(text: title)
            CommitFormattingTextField(
                placeholder: "HH:MM",
                text: text,
                formatter: normalizedCalendarTimeInput,
                updatesContinuously: false
            )
            .frame(width: width)
            .frame(minHeight: 18)
            .appTextInputChrome()
        }
        .frame(width: width, alignment: .leading)
    }

    private func clearUncertaintyFlagsForBlankDates() {
        if draft.from.trimmedOrNil == nil { draft.fromUncertain = false }
        if draft.to.trimmedOrNil == nil { draft.toUncertain = false }
        if draft.abstractSubmissionDeadline.trimmedOrNil == nil { draft.abstractSubmissionDeadlineUncertain = false }
        if draft.lateAbstractSubmissionDeadline.trimmedOrNil == nil { draft.lateAbstractSubmissionDeadlineUncertain = false }
    }

    private func scheduleAutosave() {
        guard !isDeletingCongress else { return }
        let snapshot = currentSnapshot()
        AutosaveCoordinator.schedule(&autosaveTask, after: 0.7) {
            persist(snapshot)
        }
    }

    private func persistAutosaveIfNeeded() {
        guard !isDeletingCongress else { return }
        AutosaveCoordinator.flush(&autosaveTask) {
            persist(currentSnapshot())
        }
    }

    private func requestImmediateAutosave() {
        guard !isDeletingCongress else { return }
        AutosaveCoordinator.requestImmediate(&forcedPersistTask, after: 0.05) {
            persistAutosaveIfNeeded()
        }
    }

    private func currentSnapshot() -> OrganizationCongress {
        var snapshot = draft
        snapshot.id = effectiveCongressID()
        snapshot.venue = snapshot.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.city = snapshot.city.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.country = snapshot.country.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.travelFlights = persistedOrganizationCongressFlights(from: snapshot.travelFlights)
        snapshot.travelHotels = persistedOrganizationCongressHotels(from: organizationCongressHotelsForPersistence(snapshot))
        syncLegacyHotelFieldsFromRows(&snapshot)
        snapshot.fundingApplicationIDs = Array(
            NSOrderedSet(array: snapshot.fundingApplicationIDs.compactMap(\.trimmedOrNil))
        ) as? [String] ?? snapshot.fundingApplicationIDs.compactMap(\.trimmedOrNil)
        snapshot.tasks = persistedOrganizationCongressTasks(from: snapshot.tasks)
        snapshot.participantNames = normalizedParticipantNames(snapshot.participantNames)
        snapshot.participantAuthorIDs = normalizedParticipantAuthorIDs(
            existingIDs: snapshot.participantAuthorIDs,
            names: snapshot.participantNames
        )
        return snapshot
    }

    private func requestDeleteCongress() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        if case .draft = row.source {
            beginCongressDeletion()
            removeDraftCongress(row.congressID)
            selectedCongressID = nil
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = language.text("Delete congress?", "Ta bort kongress?")
        alert.informativeText = language.text(
            "The congress row will be removed from the organization. Linked contributions and calendar entries are kept, and the deletion can be undone.",
            "Kongressraden tas bort från organisationen. Kopplade abstract och kalenderposter behålls, och borttagningen kan ångras."
        )
        alert.addButton(withTitle: language.text("Delete", "Ta bort"))
        alert.addButton(withTitle: language.text("Cancel", "Avbryt"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        beginCongressDeletion()
        deletePersistedCongress()
    }

    private func beginCongressDeletion() {
        isDeletingCongress = true
        autosaveTask?.cancel()
        autosaveTask = nil
        forcedPersistTask?.cancel()
        forcedPersistTask = nil
    }

    private func deletePersistedCongress() {
        guard case .organizationCongress = row.source,
              let organization else { return }
        let remainingCongresses = persistedOrganizationCongresses(
            from: organization.congresses.filter { $0.id != row.congressID }
        )
        autosaveOrganization(
            organization,
            congresses: remainingCongresses,
            actionName: language.text("Delete congress", "Ta bort kongress")
        )
        selectedCongressID = nil
    }

    private func addPendingParticipant() {
        guard let rawName = pendingParticipantText.trimmedOrNil else { return }
        let participantName = participantOptions.first {
            $0.caseInsensitiveCompare(rawName) == .orderedSame
        } ?? rawName
        if !draft.participantNames.contains(where: { CongressesWorkspaceView.congressSamePersonText($0, participantName) }) {
            draft.participantNames.append(participantName)
            draft.participantNames = normalizedParticipantNames(draft.participantNames)
            draft.participantAuthorIDs = normalizedParticipantAuthorIDs(
                existingIDs: draft.participantAuthorIDs,
                names: draft.participantNames
            )
            scheduleAutosave()
        }
        pendingParticipantText = ""
        participantFieldResetID = UUID()
    }

    private func participantBinding(for originalName: String) -> Binding<String> {
        Binding(
            get: {
                draft.participantNames.first {
                    CongressesWorkspaceView.congressSamePersonText($0, originalName)
                } ?? originalName
            },
            set: { newValue in
                updateParticipant(named: originalName, to: newValue)
            }
        )
    }

    private func updateParticipant(named originalName: String, to newValue: String) {
        guard let replacementName = resolvedParticipantName(from: newValue) else {
            removeParticipant(named: originalName)
            return
        }

        let originalAuthorIDs = draft.participantAuthorIDs
        let oldAuthorID = participantAuthor(for: originalName)?.id
        let replacementAuthorID = participantAuthor(for: replacementName)?.id

        guard let index = draft.participantNames.firstIndex(where: {
            CongressesWorkspaceView.congressSamePersonText($0, originalName)
        }) else {
            if !draft.participantNames.contains(where: {
                CongressesWorkspaceView.congressSamePersonText($0, replacementName)
            }) {
                draft.participantNames.append(replacementName)
            }
            draft.participantNames = normalizedParticipantNames(draft.participantNames)
            draft.participantAuthorIDs = normalizedParticipantAuthorIDs(
                existingIDs: originalAuthorIDs,
                names: draft.participantNames
            )
            return
        }

        let alreadyExists = draft.participantNames.enumerated().contains { offset, name in
            offset != index && CongressesWorkspaceView.congressSamePersonText(name, replacementName)
        }
        if alreadyExists {
            draft.participantNames.remove(at: index)
        } else {
            draft.participantNames[index] = replacementName
        }

        draft.participantNames = normalizedParticipantNames(draft.participantNames)
        var retainedAuthorIDs = draft.participantAuthorIDs.compactMap(\.trimmedOrNil)
        if let oldAuthorID, oldAuthorID != replacementAuthorID {
            retainedAuthorIDs.removeAll { $0 == oldAuthorID }
        }
        draft.participantAuthorIDs = normalizedParticipantAuthorIDs(
            existingIDs: retainedAuthorIDs,
            names: draft.participantNames
        )
    }

    private func resolvedParticipantName(from rawName: String) -> String? {
        guard let trimmed = rawName.trimmedOrNil else { return nil }
        return participantOptions.first {
            $0.caseInsensitiveCompare(trimmed) == .orderedSame
        } ?? trimmed
    }

    private func participantAuthor(for name: String) -> PublicationAuthor? {
        store.publicationAuthor(matchingPresentedName: name)
    }

    private func isEditingParticipant(_ name: String) -> Bool {
        guard let editingParticipantOriginalName else { return false }
        return CongressesWorkspaceView.congressSamePersonText(editingParticipantOriginalName, name)
    }

    private func startEditingParticipant(_ name: String) {
        editingParticipantOriginalName = name
        editingParticipantText = name
    }

    private func clearParticipantEditingState() {
        editingParticipantOriginalName = nil
        editingParticipantText = ""
    }

    private func commitParticipantEdit(replacing originalName: String) {
        guard isEditingParticipant(originalName) else { return }
        guard let rawReplacement = editingParticipantText.trimmedOrNil else {
            clearParticipantEditingState()
            return
        }
        let replacementName = participantOptions.first {
            $0.caseInsensitiveCompare(rawReplacement) == .orderedSame
        } ?? rawReplacement

        let originalNames = draft.participantNames
        let originalAuthorIDs = draft.participantAuthorIDs
        let oldAuthorID = participantAuthor(for: originalName)?.id
        let replacementAuthorID = participantAuthor(for: replacementName)?.id

        if let index = draft.participantNames.firstIndex(where: {
            CongressesWorkspaceView.congressSamePersonText($0, originalName)
        }) {
            draft.participantNames[index] = replacementName
        } else {
            draft.participantNames.append(replacementName)
        }

        draft.participantNames = normalizedParticipantNames(draft.participantNames)
        var retainedAuthorIDs = draft.participantAuthorIDs.compactMap(\.trimmedOrNil)
        if let oldAuthorID, oldAuthorID != replacementAuthorID {
            retainedAuthorIDs.removeAll { $0 == oldAuthorID }
        }
        draft.participantAuthorIDs = normalizedParticipantAuthorIDs(
            existingIDs: retainedAuthorIDs,
            names: draft.participantNames
        )

        clearParticipantEditingState()
        if draft.participantNames != originalNames || draft.participantAuthorIDs != originalAuthorIDs {
            scheduleAutosave()
        }
    }

    private func removeParticipant(named name: String) {
        let originalNames = draft.participantNames
        let originalAuthorIDs = draft.participantAuthorIDs
        draft.participantNames.removeAll { CongressesWorkspaceView.congressSamePersonText($0, name) }
        if let authorID = store.publicationAuthor(matchingPresentedName: name)?.id {
            draft.participantAuthorIDs.removeAll { $0 == authorID }
        }
        if isEditingParticipant(name) {
            clearParticipantEditingState()
        }
        if draft.participantNames != originalNames || draft.participantAuthorIDs != originalAuthorIDs {
            scheduleAutosave()
        }
    }

    private func normalizedParticipantNames(_ names: [String]) -> [String] {
        Array(NSOrderedSet(array: names.compactMap(\.trimmedOrNil))) as? [String] ?? names.compactMap(\.trimmedOrNil)
    }

    private func normalizedParticipantAuthorIDs(existingIDs: [String], names: [String]) -> [String] {
        var ids = existingIDs.compactMap(\.trimmedOrNil)
        for name in names.compactMap(\.trimmedOrNil) {
            guard let authorID = store.publicationAuthor(matchingPresentedName: name)?.id else { continue }
            ids.append(authorID)
        }
        return Array(NSOrderedSet(array: ids)) as? [String] ?? ids
    }

    private func normalizedTaskRows(_ tasks: [ProjectTaskItem], placeholderID: String? = nil) -> [ProjectTaskItem] {
        let retainedPlaceholderID = tasks.first(where: { $0.isEmpty })?.id ?? placeholderID ?? UUID().uuidString
        return persistedOrganizationCongressTasks(from: tasks) + [ProjectTaskItem(id: retainedPlaceholderID)]
    }

    private func materializeLegacyHotelRowsIfNeeded() {
        guard draft.travelHotels.isEmpty else { return }
        draft.travelHotels = persistedOrganizationCongressHotels(from: organizationCongressHotelsForPersistence(draft))
        syncLegacyHotelFieldsFromRows(&draft)
    }

    private func materializeCalendarLinkedTravelFlightsIfNeeded(schedulePersistence: Bool) {
        let linkedFlights = calendarLinkedTravelFlights
        guard !linkedFlights.isEmpty else { return }
        let didMergeFlights = mergeTravelFlightsIntoDraft(linkedFlights)
        let didMaterializeParticipant = materializeCurrentUserParticipantForLinkedTravelIfNeeded()
        if schedulePersistence && (didMergeFlights || didMaterializeParticipant) {
            scheduleAutosave()
        }
    }

    private func materializeCalendarLinkedTravelHotelsIfNeeded(schedulePersistence: Bool) {
        let linkedHotels = calendarLinkedTravelHotels
        guard !linkedHotels.isEmpty else { return }
        let didMergeHotels = mergeTravelHotelsIntoDraft(linkedHotels)
        let didMaterializeParticipant = materializeCurrentUserParticipantForLinkedTravelIfNeeded()
        if schedulePersistence && (didMergeHotels || didMaterializeParticipant) {
            scheduleAutosave()
        }
    }

    @discardableResult
    private func mergeTravelFlightsIntoDraft(_ flights: [OrganizationCongressFlight]) -> Bool {
        var didChange = false
        for flight in persistedOrganizationCongressFlights(from: flights) {
            if let index = draft.travelFlights.firstIndex(where: { $0.id == flight.id }) {
                if draft.travelFlights[index] != flight {
                    draft.travelFlights[index] = flight
                    didChange = true
                }
            } else {
                draft.travelFlights.append(flight)
                didChange = true
            }
        }
        if didChange {
            draft.travelFlights = persistedOrganizationCongressFlights(from: draft.travelFlights)
        }
        return didChange
    }

    @discardableResult
    private func mergeTravelHotelsIntoDraft(_ hotels: [OrganizationCongressHotel]) -> Bool {
        var didChange = false
        for hotel in persistedOrganizationCongressHotels(from: hotels) {
            if let index = draft.travelHotels.firstIndex(where: { $0.id == hotel.id }) {
                if draft.travelHotels[index] != hotel {
                    draft.travelHotels[index] = hotel
                    didChange = true
                }
            } else {
                draft.travelHotels.append(hotel)
                didChange = true
            }
        }
        if didChange {
            draft.travelHotels = persistedOrganizationCongressHotels(from: draft.travelHotels)
            syncLegacyHotelFieldsFromRows(&draft)
        }
        return didChange
    }

    @discardableResult
    private func materializeCurrentUserParticipantForLinkedTravelIfNeeded() -> Bool {
        let originalCongress = draft
        if let currentUserName = currentUserAuthor?.displayName.trimmedOrNil {
            if !draft.participantNames.contains(where: {
                CongressesWorkspaceView.congressSamePersonText($0, currentUserName)
            }) {
                draft.participantNames.append(currentUserName)
                draft.participantNames = normalizedParticipantNames(draft.participantNames)
            }
            if let currentUserID = currentUserAuthor?.id,
               !draft.participantAuthorIDs.contains(currentUserID) {
                draft.participantAuthorIDs.append(currentUserID)
                draft.participantAuthorIDs = normalizedParticipantAuthorIDs(
                    existingIDs: draft.participantAuthorIDs,
                    names: draft.participantNames
                )
            }
        }
        return draft != originalCongress
    }

    private func travelFlightSortOrder(_ lhs: OrganizationCongressFlight, _ rhs: OrganizationCongressFlight) -> Bool {
        let leftKey = [lhs.fromDate, lhs.fromTime, lhs.toDate, lhs.toTime, lhs.fromCity, lhs.toCity].joined(separator: "|")
        let rightKey = [rhs.fromDate, rhs.fromTime, rhs.toDate, rhs.toTime, rhs.fromCity, rhs.toCity].joined(separator: "|")
        return leftKey.localizedStandardCompare(rightKey) == .orderedAscending
    }

    private func syncLegacyHotelFieldsFromRows(_ congress: inout OrganizationCongress) {
        congress.travelHotels = persistedOrganizationCongressHotels(from: congress.travelHotels)
        guard let primaryHotel = congress.travelHotels.first else {
            congress.hotelName = ""
            congress.hotelFrom = ""
            congress.hotelFromTime = ""
            congress.hotelTo = ""
            congress.hotelToTime = ""
            return
        }
        congress.hotelName = primaryHotel.hotelName
        congress.hotelFrom = primaryHotel.fromDate
        congress.hotelFromTime = primaryHotel.fromTime
        congress.hotelTo = primaryHotel.toDate
        congress.hotelToTime = primaryHotel.toTime
    }

    @discardableResult
    private func materializeLegacyCurrentUserParticipantIfNeeded() -> Bool {
        false
    }

    private func syncLegacyAttendanceFlag(_ congress: inout OrganizationCongress) {
    }

    private func persist(_ congress: OrganizationCongress) {
        guard !isDeletingCongress else { return }
        guard let targetOrganization = selectedOrganizationFromText else { return }
        var snapshot = congress
        snapshot.id = effectiveCongressID()
        guard !snapshot.isEmpty else { return }
        let updatesSameOrganizationRow = row.source == .organizationCongress && targetOrganization.id == row.organizationID
        let updatesMaterializedDraftRow: Bool = {
            guard case .draft = row.source else { return false }
            return targetOrganization.congresses.contains { $0.id == snapshot.id }
        }()
        if let originalOrganization = organization,
           originalOrganization.id != targetOrganization.id,
           row.source == .organizationCongress {
            let remainingCongresses = persistedOrganizationCongresses(
                from: originalOrganization.congresses.filter { $0.id != row.congressID }
            )
            autosaveOrganization(originalOrganization, congresses: remainingCongresses)
        }

        var congresses = targetOrganization.congresses
        if !updatesSameOrganizationRow && !updatesMaterializedDraftRow && congresses.contains(where: { $0.id == snapshot.id }) {
            snapshot.id = uniqueCongressID(basedOn: snapshot.id, in: congresses)
        }
        if let index = congresses.firstIndex(where: { $0.id == snapshot.id }) {
            congresses[index] = snapshot
        } else {
            congresses.append(snapshot)
        }
        let persistedCongresses = persistedOrganizationCongresses(from: congresses)
        guard persistedCongresses != targetOrganization.congresses ||
                linkedContributions.contains(where: {
                    $0.congressOrganizationID != targetOrganization.id || $0.congressID != snapshot.id
                }) else { return }
        let previousCongress = targetOrganization.congresses.first { $0.id == snapshot.id }
        autosaveOrganization(
            targetOrganization,
            congresses: persistedCongresses,
            actionName: congressEditActionName(from: previousCongress, to: snapshot)
        )
        relinkContributions(toOrganizationID: targetOrganization.id, congressID: snapshot.id)
        let newRowID = CongressesWorkspaceView.rowID(organizationID: targetOrganization.id, congressID: snapshot.id)
        if row.source == .draft {
            DispatchQueue.main.async {
                if selectedCongressID == row.id || selectedCongressID == nil || selectedCongressID == newRowID {
                    selectedCongressID = newRowID
                }
                removeDraftCongress(row.congressID)
            }
        } else if (selectedCongressID == row.id || selectedCongressID == nil) && selectedCongressID != newRowID {
            DispatchQueue.main.async {
                if selectedCongressID == row.id || selectedCongressID == nil {
                    selectedCongressID = newRowID
                }
            }
        }
    }

    private func autosaveOrganization(
        _ organization: OrganizationRecord,
        congresses: [OrganizationCongress],
        actionName: String? = nil
    ) {
        store.autosaveOrganization(
            id: organization.id,
            nameSv: organization.nameSv,
            nameEn: organization.nameEn,
            addressLine: organization.addressLine,
            postalCode: organization.postalCode,
            city: organization.city,
            country: organization.country,
            category: organization.category,
            roles: organization.roles,
            note: organization.note,
            websiteURL: organization.websiteURL,
            phoneNumber: organization.phoneNumber,
            organizationNumber: organization.organizationNumber,
            vatNumber: organization.vatNumber,
            employerContacts: organization.employerContacts,
            flag: organization.flag,
            membershipFrom: organization.membershipFrom,
            membershipTo: organization.membershipTo,
            congresses: congresses,
            projectTasks: organization.projectTasks,
            salaryCalculator: organization.salaryCalculator,
            actionName: actionName ?? language.text("Edit congress", "Redigera kongress")
        )
    }

    private func congressEditActionName(from previous: OrganizationCongress?, to next: OrganizationCongress) -> String {
        guard let fieldKey = changedCongressFieldKey(from: previous, to: next) else {
            return language.text("Edit congress", "Redigera kongress")
        }
        switch fieldKey {
        case "title":
            return language.text("Edit congress title", "Redigera kongresstitel")
        case "from", "to", "abstractSubmissionDeadline", "lateAbstractSubmissionDeadline":
            return language.text("Edit congress date", "Redigera kongressdatum")
        case "venue":
            return language.text("Edit congress venue", "Redigera plats på kongress")
        case "city":
            return language.text("Edit congress city", "Redigera ort på kongress")
        case "country":
            return language.text("Edit congress country", "Redigera land på kongress")
        case "link":
            return language.text("Edit congress link", "Redigera kongresslänk")
        case "participants":
            return language.text("Edit congress participating researchers", "Redigera medverkande forskare på kongress")
        case "funding":
            return language.text("Edit congress funding", "Redigera kongressfinansiering")
        case "travel":
            return language.text("Edit congress travel planning", "Redigera reseplanering för kongress")
        case "tasks":
            return language.text("Edit congress task list", "Redigera uppgiftslista för kongress")
        case "isEditingLocked":
            return next.isEditingLocked
                ? language.text("Lock congress", "Lås kongress")
                : language.text("Unlock congress", "Lås upp kongress")
        default:
            return language.text("Edit congress", "Redigera kongress")
        }
    }

    private func changedCongressFieldKey(from previous: OrganizationCongress?, to next: OrganizationCongress) -> String? {
        guard let previous else { return nil }
        if previous.title != next.title { return "title" }
        if previous.from != next.from || previous.fromUncertain != next.fromUncertain { return "from" }
        if previous.to != next.to || previous.toUncertain != next.toUncertain { return "to" }
        if previous.abstractSubmissionDeadline != next.abstractSubmissionDeadline
            || previous.abstractSubmissionDeadlineUncertain != next.abstractSubmissionDeadlineUncertain {
            return "abstractSubmissionDeadline"
        }
        if previous.lateAbstractSubmissionDeadline != next.lateAbstractSubmissionDeadline
            || previous.lateAbstractSubmissionDeadlineUncertain != next.lateAbstractSubmissionDeadlineUncertain {
            return "lateAbstractSubmissionDeadline"
        }
        if previous.venue != next.venue { return "venue" }
        if previous.city != next.city { return "city" }
        if previous.country != next.country { return "country" }
        if previous.link != next.link { return "link" }
        if previous.participantNames != next.participantNames
            || previous.participantAuthorIDs != next.participantAuthorIDs {
            return "participants"
        }
        if previous.fundingApplicationIDs != next.fundingApplicationIDs
            || previous.congressFeeSEK != next.congressFeeSEK {
            return "funding"
        }
        if previous.travelFlights != next.travelFlights
            || previous.travelHotels != next.travelHotels
            || previous.hotelName != next.hotelName
            || previous.hotelFrom != next.hotelFrom
            || previous.hotelFromTime != next.hotelFromTime
            || previous.hotelTo != next.hotelTo
            || previous.hotelToTime != next.hotelToTime {
            return "travel"
        }
        if previous.tasks != next.tasks { return "tasks" }
        if previous.isHiddenOnMap != next.isHiddenOnMap { return "map" }
        if previous.isEditingLocked != next.isEditingLocked { return "isEditingLocked" }
        return nil
    }

    private func effectiveCongressID() -> String {
        row.congressID.trimmedOrNil ?? draft.id.trimmedOrNil ?? "contribution-\(row.primaryContributionID ?? UUID().uuidString)"
    }

    private func uniqueCongressID(basedOn rawID: String, in congresses: [OrganizationCongress]) -> String {
        let base = rawID.trimmedOrNil ?? UUID().uuidString
        let usedIDs = Set(congresses.map(\.id))
        if !usedIDs.contains(base) {
            return base
        }
        if UUID(uuidString: base) != nil {
            var candidate = UUID().uuidString
            while usedIDs.contains(candidate) {
                candidate = UUID().uuidString
            }
            return candidate
        }
        var counter = 2
        while true {
            let candidate = "\(base)-\(counter)"
            if !usedIDs.contains(candidate) {
                return candidate
            }
            counter += 1
        }
    }

    private func organizationMatching(name: String) -> OrganizationRecord? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let exactID = store.organization(id: trimmed) {
            return exactID
        }
        if let exactName = store.organization(matchingName: trimmed) {
            return exactName
        }
        return store.organizations.first { organization in
            organization.displayName(for: language).caseInsensitiveCompare(trimmed) == .orderedSame
                || organization.nameSv.caseInsensitiveCompare(trimmed) == .orderedSame
                || organization.nameEn.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    private func commitOrganizationSelection() {
        guard let targetOrganization = organizationMatching(name: organizationText) else { return }
        organizationText = targetOrganization.displayName(for: language)
        persist(currentSnapshot())
    }

    private func openSelectedOrganization() {
        guard let targetOrganization = selectedOrganizationFromText else { return }
        store.openRoute(for: targetOrganization)
    }

    private func relinkContributions(toOrganizationID organizationID: String, congressID: String) {
        for contribution in linkedContributions {
            var updated = contribution
            updated.congressOrganizationID = organizationID
            updated.congressID = congressID
            updated.congressLink = draft.link
            if updated.from.trimmedOrNil == nil {
                updated.from = draft.from
            }
            if updated.to.trimmedOrNil == nil {
                updated.to = draft.to
            }
            if updated.meetingCity.trimmedOrNil == nil {
                updated.meetingCity = draft.city
            }
            if updated.meetingCountry.trimmedOrNil == nil {
                updated.meetingCountry = draft.country
            }
            store.autosaveCVConferenceContribution(updated)
        }
    }

    private func fundingApplicationLabel(_ application: GrantApplication) -> String {
        let grantName = store.localizedGrantName(for: application, language: language).nonEmpty
            ?? application.grantName.nonEmpty
            ?? language.text("Untitled grant", "Namnlöst anslag")
        let applicationName = application.applicationTitle?.trimmedOrNil.flatMap {
            $0.caseInsensitiveCompare(grantName) == .orderedSame ? nil : $0
        }
        let amount = fundingApplicationAmountText(application)
        let title = [grantName, applicationName]
            .compactMap { $0?.trimmedOrNil }
            .joined(separator: " - ")
        let organization = application.organization.nonEmpty
        let year = application.appliedYear?.trimmedOrNil
            ?? application.appliedOn?.trimmedOrNil.map { String($0.prefix(4)) }
            ?? application.grantedOn?.trimmedOrNil.map { String($0.prefix(4)) }
        let detail = [organization, year, amount].compactMap { $0?.trimmedOrNil }.joined(separator: " - ")
        return detail.isEmpty ? title : "\(title) (\(detail))"
    }

    private func fundingApplicationAmountText(_ application: GrantApplication) -> String? {
        if application.grantedAmountValue != nil {
            return store.formattedGrantAmountWithSEKApproximation(application.grantedAmountValue, for: application)
        }
        return application.grantedAmount?.trimmedOrNil
    }

    private func fundingApplicationLabel(forID applicationID: String) -> String {
        store.application(id: applicationID).map(fundingApplicationLabel)
            ?? language.text("Missing grant", "Saknat anslag")
    }

    private func applicationMatchingFundingText(_ text: String) -> GrantApplication? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let byID = store.application(id: trimmed),
           byID.isGranted {
            return byID
        }
        return fundingApplicationCandidates.first { fundingApplicationLabel($0) == trimmed }
    }

    private func addPendingFundingApplication() {
        guard let application = applicationMatchingFundingText(pendingFundingApplicationText) else { return }
        if !draft.fundingApplicationIDs.contains(application.id) {
            draft.fundingApplicationIDs.append(application.id)
            scheduleAutosave()
        }
        pendingFundingApplicationText = ""
    }

    private func addContribution() {
        persistAutosaveIfNeeded()
        let id = store.addCVConferenceContribution()
        var contribution = store.cvConferenceContributions.first(where: { $0.id == id }) ?? CVConferenceContribution(id: id)
        let targetOrganization = selectedOrganizationFromText
        contribution.congressOrganizationID = targetOrganization?.id
        contribution.congressID = effectiveCongressID()
        contribution.congressLink = draft.link
        contribution.from = draft.from
        contribution.to = draft.to
        contribution.meetingCity = draft.city
        contribution.meetingCountry = draft.country
        contribution.meetingSv = draft.title
        contribution.meetingEn = draft.title
        if contribution.submissionClosesOn.trimmedOrNil == nil {
            contribution.submissionClosesOn = draft.lateAbstractSubmissionDeadline.nonEmpty ?? draft.abstractSubmissionDeadline
        }
        store.autosaveCVConferenceContribution(contribution)
        selectedContributionID = id
    }

    private func contributionDateText(_ contribution: CVConferenceContribution) -> String {
        switch (contribution.from.nonEmpty, contribution.to.nonEmpty) {
        case let (.some(from), .some(to)) where from != to:
            return "\(from)-\(to)"
        case let (.some(from), _):
            return from
        case let (_, .some(to)):
            return to
        default:
            return contribution.publicationYear.nonEmpty ?? "-"
        }
    }

    private func contributionSort(_ lhs: CVConferenceContribution, _ rhs: CVConferenceContribution) -> Bool {
        let leftDate = lhs.from.nonEmpty ?? lhs.to.nonEmpty ?? lhs.publicationYear
        let rightDate = rhs.from.nonEmpty ?? rhs.to.nonEmpty ?? rhs.publicationYear
        if leftDate != rightDate {
            return leftDate.localizedStandardCompare(rightDate) == .orderedAscending
        }
        return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
    }
}

private struct CongressMiniBadge: View {
    let text: String
    var isPositive: Bool = false
    /// Round 17: the shared status tone (wins over `isPositive`).
    var tone: AppStatusTone? = nil

    var body: some View {
        AppSemanticStatusBadge(
            text: text,
            colors: tone.map { AppBadgeColors.status($0) } ?? (isPositive ? AppBadgeColors.saveSolid : AppBadgeColors.neutralCard),
            size: .compact,
            horizontalPadding: 7,
            verticalPadding: 3
        )
    }
}


private struct CongressDetailFieldsHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct CongressMiniMapView: View {
    let title: String
    let venue: String
    let city: String
    let country: String
    let language: AppLanguage
    let mapHeight: CGFloat

    private static let southAmericanCountryKeys: Set<String> = [
        "argentina",
        "bolivia",
        "brazil",
        "brasilien",
        "chile",
        "colombia",
        "ecuador",
        "french guiana",
        "franska guyana",
        "guyana",
        "paraguay",
        "peru",
        "suriname",
        "uruguay",
        "venezuela"
    ]

    @State private var mapPosition: MapCameraPosition = .region(CongressMapModel.defaultMapRegion)
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var resolvedQuery = ""

    private var query: String {
        [venue.trimmedOrNil, city.trimmedOrNil, country.trimmedOrNil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private var cityFallbackQuery: String {
        [city.trimmedOrNil, country.trimmedOrNil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private var markerTitle: String {
        title.trimmedOrNil ?? city.trimmedOrNil ?? language.text("Congress", "Kongress")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if query.isEmpty {
                Text(language.text("Add venue, city, or country to show a map.", "Lägg till plats, ort eller land för att visa karta."))
                    .font(appFont(.secondary))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: mapHeight)
                    .background(AppPalette.secondaryCardSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ZStack {
                    Map(position: $mapPosition) {
                        if let coordinate {
                            Marker(markerTitle, coordinate: coordinate)
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic, emphasis: .muted))

                    if coordinate == nil {
                        ProgressView()
                            .controlSize(.small)
                            .padding(8)
                            .background(AppPalette.cardSurface.opacity(0.85), in: Capsule(style: .continuous))
                    }
                }
                .frame(height: mapHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppPalette.border.opacity(0.65), lineWidth: 1)
                )
                .task(id: query) {
                    await resolveLocationIfNeeded()
                }
            }
        }
    }

    private func resolveLocationIfNeeded() async {
        let currentQuery = query
        guard !currentQuery.isEmpty, currentQuery != resolvedQuery else { return }
        await MainActor.run {
            coordinate = nil
            resolvedQuery = currentQuery
        }
        let geocoder = CLGeocoder()
        let primaryCoordinate = await geocodedCoordinate(for: currentQuery, geocoder: geocoder)
        let fallbackQuery = cityFallbackQuery
        let fallbackCoordinate = fallbackQuery.isEmpty || fallbackQuery == currentQuery
            ? nil
            : await geocodedCoordinate(for: fallbackQuery, geocoder: geocoder)
        let nextCoordinate: CLLocationCoordinate2D?
        if let primaryCoordinate,
           let fallbackCoordinate,
           shouldPreferCityFallback(primaryCoordinate: primaryCoordinate, cityCoordinate: fallbackCoordinate) {
            nextCoordinate = fallbackCoordinate
        } else {
            nextCoordinate = primaryCoordinate ?? fallbackCoordinate
        }

        guard let nextCoordinate else {
            return
        }
        await MainActor.run {
            coordinate = nextCoordinate
            mapPosition = .region(continentRegion(for: nextCoordinate))
        }
    }

    private func geocodedCoordinate(for query: String, geocoder: CLGeocoder) async -> CLLocationCoordinate2D? {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let placemarks = try? await geocoder.geocodeAddressString(query)
        return placemarks?.first?.location?.coordinate
    }

    private func shouldPreferCityFallback(
        primaryCoordinate: CLLocationCoordinate2D,
        cityCoordinate: CLLocationCoordinate2D
    ) -> Bool {
        guard venue.trimmedOrNil != nil, city.trimmedOrNil != nil else { return false }
        let primaryLocation = CLLocation(latitude: primaryCoordinate.latitude, longitude: primaryCoordinate.longitude)
        let cityLocation = CLLocation(latitude: cityCoordinate.latitude, longitude: cityCoordinate.longitude)
        return primaryLocation.distance(from: cityLocation) > 100_000
    }

    private func continentRegion(for coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        let latitude = coordinate.latitude
        let longitude = coordinate.longitude

        if Self.southAmericanCountryKeys.contains(Self.regionCountryKey(country)) {
            return wideRegion(centeredOn: coordinate, latitudeDelta: 76, longitudeDelta: 76)
        }

        if (34...72).contains(latitude), (-25...45).contains(longitude) {
            return wideRegion(centeredOn: coordinate, latitudeDelta: 42, longitudeDelta: 65)
        }

        if (-36...38).contains(latitude), (-20...55).contains(longitude) {
            return wideRegion(centeredOn: coordinate, latitudeDelta: 76, longitudeDelta: 82)
        }

        if (5...72).contains(latitude), (-170 ... -50).contains(longitude) {
            return wideRegion(centeredOn: coordinate, latitudeDelta: 68, longitudeDelta: 125)
        }

        if (-56...13).contains(latitude), (-92 ... -30).contains(longitude) {
            return wideRegion(centeredOn: coordinate, latitudeDelta: 76, longitudeDelta: 76)
        }

        if (-50...0).contains(latitude), (110...180).contains(longitude) {
            return wideRegion(centeredOn: coordinate, latitudeDelta: 52, longitudeDelta: 82)
        }

        if (-10...82).contains(latitude), (45...180).contains(longitude) {
            return wideRegion(centeredOn: coordinate, latitudeDelta: 92, longitudeDelta: 142)
        }

        return wideRegion(centeredOn: coordinate, latitudeDelta: 55, longitudeDelta: 75)
    }

    private static func regionCountryKey(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func wideRegion(
        centeredOn coordinate: CLLocationCoordinate2D,
        latitudeDelta: CLLocationDegrees,
        longitudeDelta: CLLocationDegrees
    ) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }
}

private typealias CongressPanel<Content: View> = AppDividerPanel<Content>
