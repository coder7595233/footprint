import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

private func interpolatedRankingColor(from start: NSColor, to end: NSColor, fraction: Double) -> Color {
    let clamped = max(0, min(1, fraction))
    let blended = start.blended(withFraction: clamped, of: end) ?? end
    return Color(nsColor: blended)
}

private func medianValue(for values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}

private func journalMetricNumericValue(_ raw: String, kind: JournalRankingKind) -> Double? {
    switch kind {
    case .norwegianList:
        return PublicationJournal.norwegianRankValue(for: raw)
    case .clarivateScieJIF, .clarivateScieJCI, .clarivateEsciJIF, .clarivateEsciJCI, .scimagoSJR:
        return Double(raw.replacingOccurrences(of: ",", with: "."))
    }
}

@MainActor
@ViewBuilder
func publicationMenuField<Value: Hashable>(
    selection: Binding<Value>,
    options: [(label: String, value: Value)],
    placeholder: String? = nil,
    width: CGFloat? = nil,
    fill: Color = AppPalette.fieldSurface,
    stroke: Color = AppPalette.subtleBorder,
    foregroundColor: Color? = nil,
    minHeight: CGFloat = AppPalette.fieldMinHeight,
    verticalPadding: CGFloat = AppPalette.textFieldVerticalPadding
) -> some View {
    if AppRuntime.usesRenewedChrome {
        AppMenuSelectionField(
            selection: selection,
            options: options,
            placeholder: placeholder,
            fill: fill,
            stroke: stroke,
            foregroundColor: foregroundColor,
            minHeight: minHeight,
            verticalPadding: verticalPadding
        )
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : width, alignment: .leading)
    } else {
        Picker("", selection: selection) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Text(option.label).tag(option.value)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .formKeyboardNavigable()
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : width, alignment: .leading)
    }
}

private func rankingBackgroundColor(currentValue: Double, values: [Double], kind: JournalRankingKind) -> Color {
    let minColor = AppPalette.vividRed
    let midColor = AppPalette.vividYellow
    let maxColor = AppPalette.vividGreen
    let minNSColor = AppAppearanceRegistry.semanticColor(.negative, shaded: false)
    let midNSColor = AppAppearanceRegistry.semanticColor(.inProgress, shaded: false)
    let maxNSColor = AppAppearanceRegistry.semanticColor(.positive, shaded: false)

    if kind == .norwegianList {
        switch Int(currentValue.rounded()) {
        case 2:
            return maxColor
        case 1:
            return midColor
        default:
            return minColor
        }
    }

    guard
        let minimum = values.min(),
        let maximum = values.max(),
        let median = medianValue(for: values)
    else {
        return AppPalette.fieldSurface
    }

    if maximum <= minimum {
        return maxColor
    }

    if currentValue <= median {
        guard median > minimum else { return midColor }
        let fraction = (currentValue - minimum) / (median - minimum)
        return interpolatedRankingColor(
            from: minNSColor,
            to: midNSColor,
            fraction: fraction
        )
    }

    guard maximum > median else { return midColor }
    let fraction = (currentValue - median) / (maximum - median)
    return interpolatedRankingColor(
        from: midNSColor,
        to: maxNSColor,
        fraction: fraction
    )
}

private func rankingDisplayColor(for metric: PublicationMetricValue?, in journals: [PublicationJournal], publicationYear: Int? = nil) -> Color? {
    guard let metric, let currentValue = journalMetricNumericValue(metric.value, kind: metric.kind) else {
        return nil
    }
    let values = journals.flatMap { journal in
        journal
            .metric(for: metric.kind, publicationYear: publicationYear)
            .flatMap { journalMetricNumericValue($0.value, kind: metric.kind) }
            .map { [$0] } ?? []
    }
    guard !values.isEmpty else { return nil }
    return rankingBackgroundColor(currentValue: currentValue, values: values, kind: metric.kind)
}

private struct JournalMetricDistributionSummary {
    private var valuesByKind: [JournalRankingKind: [Double]] = [:]

    init(journals: [PublicationJournal], publicationYear: Int? = nil) {
        var valuesByKind: [JournalRankingKind: [Double]] = [:]
        for journal in journals {
            for kind in JournalRankingKind.allCases {
                guard let metric = journal.metric(for: kind, publicationYear: publicationYear),
                      let value = journalMetricNumericValue(metric.value, kind: kind) else {
                    continue
                }
                valuesByKind[kind, default: []].append(value)
            }
        }
        self.valuesByKind = valuesByKind
    }

    func backgroundColor(for metric: PublicationMetricValue?) -> Color? {
        guard let metric,
              let currentValue = journalMetricNumericValue(metric.value, kind: metric.kind),
              let values = valuesByKind[metric.kind],
              !values.isEmpty else {
            return nil
        }
        return rankingBackgroundColor(currentValue: currentValue, values: values, kind: metric.kind)
    }
}

private struct JournalRankingEditorDistributionCache {
    private var valuesByKey: [String: [Double]] = [:]

    init() {}

    init(journals: [PublicationJournal]) {
        var valuesByKey: [String: [Double]] = [:]
        for journal in journals {
            for row in journal.rankingRows {
                let categoryKey = row.kind == .scimagoSJR
                    ? (row.category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "")
                    : ""
                for metric in row.yearlyMetrics {
                    guard let value = journalMetricNumericValue(metric.value, kind: row.kind) else { continue }
                    let key = Self.makeKey(kind: row.kind, category: categoryKey, year: metric.year)
                    valuesByKey[key, default: []].append(value)
                }
            }
        }
        self.valuesByKey = valuesByKey
    }

    func values(for kind: JournalRankingKind, category: String?, year: Int) -> [Double] {
        let categoryKey = kind == .scimagoSJR
            ? (category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "")
            : ""
        return valuesByKey[Self.makeKey(kind: kind, category: categoryKey, year: year)] ?? []
    }

    private static func makeKey(kind: JournalRankingKind, category: String, year: Int) -> String {
        "\(kind.rawValue)|\(category)|\(year)"
    }
}

struct PublicationMetricDistributionCache {
    private var valuesByKey: [String: [Double]] = [:]

    init() {}

    init(journals: [PublicationJournal]) {
        var valuesByKey: [String: [Double]] = [:]
        for journal in journals {
            for row in journal.rankingRows {
                for metric in row.yearlyMetrics {
                    guard let value = journalMetricNumericValue(metric.value, kind: row.kind) else { continue }
                    valuesByKey[Self.makeKey(kind: row.kind, year: metric.year), default: []].append(value)
                }
            }
        }
        self.valuesByKey = valuesByKey
    }

    func backgroundColor(for metric: PublicationMetricValue?, publicationYear: Int?) -> Color? {
        guard let metric,
              let publicationYear,
              let currentValue = journalMetricNumericValue(metric.value, kind: metric.kind),
              let values = valuesByKey[Self.makeKey(kind: metric.kind, year: publicationYear)],
              !values.isEmpty else {
            return nil
        }
        return rankingBackgroundColor(currentValue: currentValue, values: values, kind: metric.kind)
    }

    private static func makeKey(kind: JournalRankingKind, year: Int) -> String {
        "\(kind.rawValue)|\(year)"
    }
}

func formattedRankingMetricValue(_ metric: PublicationMetricValue) -> String {
    switch metric.kind {
    case .clarivateScieJIF, .clarivateScieJCI, .clarivateEsciJIF, .clarivateEsciJCI, .scimagoSJR:
        guard let value = Double(metric.value.replacingOccurrences(of: ",", with: ".")) else { return metric.value }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? metric.value
    case .norwegianList:
        let trimmed = metric.value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed == "X" ? "X" : trimmed
    }
}

private struct PublicationJournalListRow: Identifiable {
    let id: String
    let name: String
    let categoryText: String
    let categories: [String]
    let categorySet: Set<String>
    let filterSearchBlob: String
    let normalizedFilterSearchBlob: String
    let extendedFilterSearchBlob: String
    let normalizedExtendedFilterSearchBlob: String
    let searchBlob: String
    let normalizedSearchBlob: String
    let latestImpactFactorValue: Double
    let latestNorwegianLevelValue: Double
    let hasPreviousSubmission: Bool
    let hasPreviousPublication: Bool
    let jifMetric: PublicationMetricValue?
    let jifBackgroundColor: Color?
    let norwegianMetric: PublicationMetricValue?
    let norwegianBackgroundColor: Color?
    let acceptanceText: String
    let acceptanceSortValue: Double
}

struct JournalAcceptanceStats: Equatable {
    var submittedCount = 0
    var publishedCount = 0

    var percentage: Int {
        guard submittedCount > 0 else { return 0 }
        return Int((Double(publishedCount) / Double(submittedCount) * 100).rounded())
    }

    var sortValue: Double {
        guard submittedCount > 0 else { return -1 }
        return Double(percentage) + (Double(publishedCount) / 10_000)
    }

    var displayText: String {
        "\(publishedCount)/\(submittedCount) (\(percentage)%)"
    }
}

struct JournalLinkedPublicationEntry: Identifiable {
    let id: String
    let publicationID: String
    let title: String
    let status: PublicationStatus
    let dateText: String

    var priorityRank: Int {
        switch status {
        case .published, .accepted:
            return 0
        case .submitted:
            return 1
        case .rejected:
            return 2
        case .planned, .inPreparation:
            return 3
        }
    }

    var sortDate: Date {
        DateParsers.isoDay.date(from: dateText) ?? .distantPast
    }
}

func journalAcceptanceStatsByName(publications: [PublicationRecord]) -> [String: JournalAcceptanceStats] {
    var counts: [String: JournalAcceptanceStats] = [:]
    var seenSubmissionKeys = Set<String>()
    var seenPublishedKeys = Set<String>()

    for publication in publications {
        for row in derivedSubmissionRows(for: publication) {
            let journalName = row.journal.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !journalName.isEmpty else { continue }
            let rowKey = [
                publication.id,
                journalName,
                row.submittedDate ?? "",
                row.rejectedDate ?? "",
                row.acceptedDate ?? "",
                row.publishedDate ?? "",
            ].joined(separator: "|")

            if seenSubmissionKeys.insert(rowKey).inserted, row.latestStatus != nil {
                counts[journalName, default: JournalAcceptanceStats()].submittedCount += 1
            }
            if row.publishedDate?.nonEmpty != nil, seenPublishedKeys.insert(rowKey).inserted {
                counts[journalName, default: JournalAcceptanceStats()].publishedCount += 1
            }
        }
    }

    return counts
}

func linkedJournalPublicationEntries(for journalName: String, publications: [PublicationRecord]) -> [JournalLinkedPublicationEntry] {
    let normalizedJournalName = journalName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedJournalName.isEmpty else { return [] }

    var entries: [JournalLinkedPublicationEntry] = []
    var seen = Set<String>()

    for publication in publications {
        for row in derivedSubmissionRows(for: publication) where row.journal == normalizedJournalName {
            guard let resolvedStatus = row.latestStatus,
                  let resolvedDate = row.date(for: resolvedStatus)?.trimmedOrNil else {
                continue
            }

            let key = [publication.id, resolvedStatus.rawValue, resolvedDate, normalizedJournalName].joined(separator: "|")
            guard seen.insert(key).inserted else { continue }

            entries.append(
                JournalLinkedPublicationEntry(
                    id: key,
                    publicationID: publication.id,
                    title: publication.title,
                    status: resolvedStatus,
                    dateText: resolvedDate
                )
            )
        }
    }

    return entries.sorted { lhs, rhs in
        if lhs.priorityRank != rhs.priorityRank {
            return lhs.priorityRank < rhs.priorityRank
        }
        if lhs.sortDate != rhs.sortDate {
            return lhs.sortDate > rhs.sortDate
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}

struct PublicationJournalsView: View {
    private enum JournalListSortColumn: String, Hashable {
        case name
        case jif
        case norwegian
        case acceptance
        case category

        var defaultAscending: Bool {
            switch self {
            case .name, .category:
                return true
            case .jif, .norwegian, .acceptance:
                return false
            }
        }
    }

    private struct JournalListSortCriterion: AppListSortCriterion {
        let column: JournalListSortColumn
        var ascending: Bool
    }

    let store: GrantDataStore
    let newRecordTrigger: Int
    let isActive: Bool
    @WorkspaceFilterState("Journals.Filter.Search") private var searchText = ""
    @WorkspaceFilterState("Journals.Filter.SearchPublisher") private var searchAlsoInPublisher = false
    @WorkspaceFilterState("Journals.Filter.Categories") private var selectedCategories: Set<String> = []
    @WorkspaceFilterState("Journals.Filter.ExcludedCategories") private var excludedCategories: Set<String> = []
    @State private var showingCategoryFilter = false
    @WorkspaceFilterState("Journals.Filter.MinimumJIF") private var minimumJIFValue: Double = 0
    @WorkspaceFilterState("Journals.Filter.Norwegian1") private var includeNorwegianLevel1 = false
    @WorkspaceFilterState("Journals.Filter.Norwegian2") private var includeNorwegianLevel2 = false
    @WorkspaceFilterState("Journals.Filter.PreviouslySubmitted") private var onlyPreviouslySubmitted = false
    @WorkspaceFilterState("Journals.Filter.PreviouslyPublished") private var onlyPreviouslyPublished = false
    @State private var selectedJournalID: String?
    @State private var selectedJournalIDsInOrder: [String] = []
    @State private var journalRows: [PublicationJournalListRow] = []
    @State private var baseFilteredJournalRows: [PublicationJournalListRow] = []
    @State private var filteredJournalRows: [PublicationJournalListRow] = []
    @State private var categoryOptionsCache: [String] = []
    @State private var journalRowCache: [String: PublicationJournalListRow] = [:]
    @State private var journalRowSignatures: [String: PublicationJournalRowSnapshot] = [:]
    @State private var searchRebuildTask: DispatchWorkItem?
    @State private var journalSnapshotRefreshTask: DispatchWorkItem?
    @State private var neighboringWarmTask: DispatchWorkItem?
    @State private var journalDistributionRefreshTask: DispatchWorkItem?
    @State private var journalDistributionBuildToken: UInt = 0
    @State private var pendingInitialDistributionRefresh = false
    @State private var journalRowsBuildGeneration = 0
    @State private var journalRowsAppliedGeneration = 0
    @State private var journalTablePerformanceMode = false
    @State private var lastSearchQuery = SearchFilterQuery(raw: "")
    @State private var lastNonSearchFilterSignature = ""
    @State private var journalsViewMeasurementStartedAt: CFAbsoluteTime?
    @State private var journalTableInitialReadyLogged = false
    @State private var journalDetailInitialReadyLogged = false
    @State private var pendingSelectionMeasurementID: String?
    @State private var pendingSelectionStartedAt: CFAbsoluteTime?
    @State private var journalSelectionCoordinator = AppSelectionCoordinator<String>()
    @State private var journalRankingDistributionCache = JournalRankingEditorDistributionCache()
    @State private var journalMetricDistributionSummary = JournalMetricDistributionSummary(journals: [])
    @State private var journalIdleWarmupTask: DispatchWorkItem?
    @State private var needsJournalSnapshotRefreshWhenActive = false
    @State private var needsJournalFilterRebuildWhenActive = false
    @State private var needsJournalDistributionRefreshWhenActive = false
    @State private var pendingRouteJournalID: String?
    @State private var sortHistory = ListSortPersistence.load(
        defaultsKey: "PublicationJournalsListSort",
        defaultValue: [
            JournalListSortCriterion(column: .norwegian, ascending: false),
            JournalListSortCriterion(column: .jif, ascending: false),
            JournalListSortCriterion(column: .name, ascending: true),
        ]
    )

    private var sortOrder: [KeyPathComparator<PublicationJournalListRow>] {
        var columns = sortHistory.map(\.column)
        for fallbackColumn in [JournalListSortColumn.norwegian, .jif, .name] where !columns.contains(fallbackColumn) {
            columns.append(fallbackColumn)
        }
        return columns.flatMap { column -> [KeyPathComparator<PublicationJournalListRow>] in
            let ascending = sortHistory.first(where: { $0.column == column })?.ascending ?? column.defaultAscending
            let order: SortOrder = ascending ? .forward : .reverse
            switch column {
            case .name:
                return [KeyPathComparator(\.name, order: order)]
            case .jif:
                return [KeyPathComparator(\.latestImpactFactorValue, order: order)]
            case .norwegian:
                return [KeyPathComparator(\.latestNorwegianLevelValue, order: order)]
            case .acceptance:
                return [KeyPathComparator(\.acceptanceSortValue, order: order)]
            case .category:
                return [KeyPathComparator(\.categoryText, order: order)]
            }
        }
    }

    private var categoryOptions: [String] {
        categoryOptionsCache
    }

    private var nonSearchMatchingJournalRows: [PublicationJournalListRow] {
        let categoryFilters = JournalCategoryFilterState(
            includedCategories: selectedCategories,
            excludedCategories: excludedCategories
        )
        return journalRows.filter { journal in
            let matchesCategory = categoryFilters.matches(categorySet: journal.categorySet)
            let matchesMinimum = journal.latestImpactFactorValue >= minimumJIFValue
            let matchesNorwegian = norwegianLevelFilters.isEmpty || norwegianLevelFilters.contains(Int(journal.latestNorwegianLevelValue.rounded()))
            let matchesPreviousSubmission = !onlyPreviouslySubmitted || journal.hasPreviousSubmission
            let matchesPreviousPublication = !onlyPreviouslyPublished || journal.hasPreviousPublication

            return matchesCategory && matchesMinimum && matchesNorwegian && matchesPreviousSubmission && matchesPreviousPublication
        }
    }

    private var maximumJIFValue: Double {
        max(journalRows.map(\.latestImpactFactorValue).max() ?? 0, 1)
    }

    private var norwegianLevelFilters: Set<Int> {
        var filters = Set<Int>()
        if includeNorwegianLevel1 {
            filters.insert(1)
        }
        if includeNorwegianLevel2 {
            filters.insert(2)
        }
        return filters
    }

    private var hasActiveJournalFilters: Bool {
        searchText.nonEmpty != nil
            || searchAlsoInPublisher
            || !selectedCategories.isEmpty
            || !excludedCategories.isEmpty
            || minimumJIFValue > 0
            || includeNorwegianLevel1
            || includeNorwegianLevel2
            || onlyPreviouslySubmitted
            || onlyPreviouslyPublished
    }

    private var journalSearchChangeSignature: String {
        [
            searchText,
            searchAlsoInPublisher ? "publisher" : "journal"
        ].joined(separator: "||")
    }

    private var journalFilterChangeSignature: String {
        [
            selectedCategories.sorted().joined(separator: "|"),
            excludedCategories.sorted().joined(separator: "|"),
            String(format: "%.1f", minimumJIFValue),
            includeNorwegianLevel1 ? "n1" : "",
            includeNorwegianLevel2 ? "n2" : "",
            onlyPreviouslySubmitted ? "submitted" : "",
            onlyPreviouslyPublished ? "published" : "",
            sortHistory.map { "\(String(describing: $0.column)):\($0.ascending ? "1" : "0")" }.joined(separator: "|")
        ].joined(separator: "||")
    }

    private var filteredJournalRowsIDSignature: String {
        filteredJournalRows.map(\.id).joined(separator: "|")
    }

    private var journalSelectionBinding: Binding<String?> {
        Binding(
            get: { selectedJournalID },
            set: { newValue in
                handleJournalSelectionCandidate(newValue)
            }
        )
    }

    private var categoryMenuLabel: String {
        switch (selectedCategories.count, excludedCategories.count) {
        case (0, 0):
            return store.language.text("All categories", "Alla kategorier")
        case (1, 0):
            return selectedCategories.first ?? store.language.text("All categories", "Alla kategorier")
        case (let includedCount, 0):
            return store.language.text("\(includedCount) included", "\(includedCount) inkluderade")
        case (0, 1):
            if let category = excludedCategories.first {
                return store.language.text("Excluding \(category)", "Utesluter \(category)")
            }
            return store.language.text("All categories", "Alla kategorier")
        case (0, let excludedCount):
            return store.language.text("\(excludedCount) excluded", "\(excludedCount) bortvalda")
        case (let includedCount, let excludedCount):
            return store.language.text(
                "\(includedCount) included · \(excludedCount) excluded",
                "\(includedCount) inkluderade · \(excludedCount) bortvalda"
            )
        }
    }

    var body: some View {
        let language = store.language

        PersistentSplitView(layout: .publicationJournals) {
            journalMasterPane(language: language)
        } detail: {
            journalDetailPane(language: language)
        }
        .onDeleteCommand {
            guard let selectedJournalID, let journal = store.publicationJournal(id: selectedJournalID) else { return }
            store.requestKeyboardDeletion(recordTitle: journal.name, isLocked: false) {
                store.deletePublicationJournal(id: journal.id)
            }
        }
    }

    private func journalMasterPane(language: AppLanguage) -> some View {
        AppWorkspaceSidebar {
            journalMasterContent(language: language)
        }
            .onAppear(perform: handleJournalMasterAppear)
            .onReceive(store.$publicationJournalRankingGeneration.dropFirst()) { _ in
                handleJournalRankingGenerationChange()
            }
            .onReceive(store.$publicationJournalRowSnapshotGeneration.dropFirst()) { _ in
                handleJournalRowSnapshotGenerationChange()
            }
            .onChange(of: journalSearchChangeSignature) { _, _ in
                handleJournalSearchTextChange()
            }
            .onChange(of: journalFilterChangeSignature) { _, _ in
                handleJournalImmediateFilterChange()
            }
            .onChange(of: store.route) { _, route in
                handleJournalRouteChange(route)
            }
            .onChange(of: selectedJournalID) { _, id in
                handleSelectedJournalIDChange(id)
            }
            .onChange(of: filteredJournalRowsIDSignature) { _, _ in
                handleFilteredJournalRowsChange()
            }
            .onChange(of: newRecordTrigger) { _, _ in
                handleNewJournalRecordTrigger()
            }
            .onChange(of: isActive) { _, active in
                handleJournalActiveStateChange(active)
            }
            .onDisappear(perform: handleJournalViewDisappear)
    }

    private func journalMasterContent(language: AppLanguage) -> some View {
        return VStack(alignment: .leading, spacing: 10) {
            journalHeader(language: language)
            journalSearchFilterCard(language: language)
            journalResultsTable(language: language)
            ListCountFootnote(displayedCount: filteredJournalRows.count, totalCount: store.journals.count, language: language)
        }
    }

    private func journalHeader(language: AppLanguage) -> some View {
        AppWorkspaceSidebarHeader(
            title: language.text("Journals", "Tidskrifter"),
            actionTitle: language.text("New journal", "Ny tidskrift")
        ) {
                selectedJournalID = store.addPublicationJournal()
        }
        .frame(minHeight: 42)
    }

    @ViewBuilder
    private func journalDetailPane(language: AppLanguage) -> some View {
        if let journal = store.publicationJournal(id: selectedJournalID) {
            PublicationJournalEditorView(
                store: store,
                journal: journal,
                rankingDistributionCache: journalRankingDistributionCache,
                isActive: isActive,
                onEditorAppear: { journalID in
                    guard pendingSelectionMeasurementID == journalID,
                          let pendingSelectionStartedAt else { return }
                    let duration = (CFAbsoluteTimeGetCurrent() - pendingSelectionStartedAt) * 1000
                    let journalName = store.publicationJournal(id: journalID)?.name ?? journal.name
                    store.appendPerformanceDiagnostic(
                        String(
                            format: "journal-selection-appear journal=%@ appear_ms=%.2f",
                            journalName,
                            duration
                        )
                    )
                },
                onEditorReady: { journalID in
                    scheduleInitialJournalDistributionRefreshIfNeeded()
                    guard pendingSelectionMeasurementID == journalID,
                          let pendingSelectionStartedAt else { return }
                    let duration = (CFAbsoluteTimeGetCurrent() - pendingSelectionStartedAt) * 1000
                    let journalName = store.publicationJournal(id: journalID)?.name ?? journal.name
                    store.appendPerformanceDiagnostic(
                        String(
                            format: "journal-selection journal=%@ selection_ms=%.2f",
                            journalName,
                            duration
                        )
                    )
                    releaseJournalSelectionLock(for: journalID)
                    self.pendingSelectionMeasurementID = nil
                    self.pendingSelectionStartedAt = nil
                }
            )
            .id(journal.id)
            .undoRevealPulse(
                triggerID: store.undoRevealRequest?.id,
                isActive: store.undoRevealRequest?.target.matchesWholeRecord(routeDestination: .journals, recordID: journal.id) == true
            )
            .background(
                PublicationPerformanceReporter {
                    reportInitialJournalDetailReadyIfNeeded(kind: "editor")
                }
            )
        } else {
            AppWorkspaceEmptyStateView(
                title: language.text("No journals found", "Inga tidskrifter hittades"),
                subtitle: language.text("Add or search for a journal.", "Lägg till eller sök fram en tidskrift."),
                kind: .publications,
                fillsBackground: true
            )
            .background(
                PublicationPerformanceReporter {
                    reportInitialJournalDetailReadyIfNeeded(kind: "empty")
                }
            )
        }
    }

    private func handleJournalMasterAppear() {
        guard isActive else {
            needsJournalSnapshotRefreshWhenActive = true
            needsJournalFilterRebuildWhenActive = true
            needsJournalDistributionRefreshWhenActive = true
            return
        }
        journalsViewMeasurementStartedAt = CFAbsoluteTimeGetCurrent()
        journalTableInitialReadyLogged = false
        journalDetailInitialReadyLogged = false
        store.appendPerformanceDiagnostic("journals-view appear")
        journalTablePerformanceMode = true
        if selectedJournalID == nil {
            setSelectedJournalID(
                store.lastSelectedRecordID(for: .journals)
                    ?? store.firstPublicationJournalIDForDisplay()
            )
        }
        primeJournalRowsForFirstPaint()
        if hasActiveJournalFilters {
            rebuildFilteredJournalRows(reason: "initial-prime")
        }
        pendingInitialDistributionRefresh = true
        if let route = store.route, route.destination == .journals {
            setSelectedJournalID(route.recordID, armLock: true)
            store.consumeRoute()
        } else if selectedJournalID == nil {
            setSelectedJournalID(store.lastSelectedRecordID(for: .journals) ?? filteredJournalRows.first?.id)
        }
        scheduleJournalIdleWarmup()
    }

    private func handleJournalRankingGenerationChange() {
        guard isActive else {
            needsJournalDistributionRefreshWhenActive = true
            return
        }
        journalTablePerformanceMode = true
        if pendingInitialDistributionRefresh {
            return
        }
        scheduleJournalDistributionRefresh(reason: "ranking-change", delay: 0.45)
    }

    private func handleJournalRowSnapshotGenerationChange() {
        guard isActive else {
            needsJournalSnapshotRefreshWhenActive = true
            needsJournalFilterRebuildWhenActive = true
            return
        }
        scheduleJournalSnapshotRefresh(reason: "snapshot-change")
    }

    private func handleJournalSearchTextChange() {
        guard isActive else {
            needsJournalFilterRebuildWhenActive = true
            return
        }
        scheduleFilteredJournalRowsRebuild()
    }

    private func handleJournalSearchScopeChange() {
        guard isActive else {
            needsJournalFilterRebuildWhenActive = true
            return
        }
        scheduleFilteredJournalRowsRebuild()
    }

    private func handleJournalCategoryFiltersChange() {
        guard isActive else {
            needsJournalFilterRebuildWhenActive = true
            return
        }
        rebuildFilteredJournalRows()
    }

    private func handleJournalImmediateFilterChange() {
        guard isActive else {
            needsJournalFilterRebuildWhenActive = true
            return
        }
        rebuildFilteredJournalRows()
    }

    private func handleJournalRouteChange(_ route: AppRoute?) {
        guard let route, route.destination == .journals else { return }
        guard isActive else {
            pendingRouteJournalID = route.recordID
            store.appendPerformanceDiagnostic("journal-route-deferred id=\(route.recordID)")
            return
        }
        setSelectedJournalID(route.recordID, armLock: true)
        store.consumeRoute()
    }

    private func handleSelectedJournalIDChange(_ id: String?) {
        guard isActive else { return }
        store.handlePendingSelectionReturnIfNeeded(for: id, in: .journals)
        store.rememberSelection(id: id, for: .journals)
        pendingSelectionMeasurementID = id
        pendingSelectionStartedAt = CFAbsoluteTimeGetCurrent()
        scheduleNeighborWarm(around: id)
    }

    private func handleFilteredJournalRowsChange() {
        guard isActive else { return }
        scheduleJournalIdleWarmup()
    }

    private func handleNewJournalRecordTrigger() {
        guard isActive else { return }
        setSelectedJournalID(store.addPublicationJournal(), armLock: true)
    }

    private func handleJournalActiveStateChange(_ active: Bool) {
        if active {
            if needsJournalSnapshotRefreshWhenActive {
                scheduleJournalSnapshotRefresh(reason: "reactivation", delay: 0)
                needsJournalSnapshotRefreshWhenActive = false
            }
            if needsJournalFilterRebuildWhenActive {
                rebuildFilteredJournalRows(reason: "reactivation")
                needsJournalFilterRebuildWhenActive = false
            }
            if needsJournalDistributionRefreshWhenActive {
                scheduleJournalDistributionRefresh(reason: "reactivation", delay: 0.2)
                needsJournalDistributionRefreshWhenActive = false
            }
            if let pendingRouteJournalID {
                setSelectedJournalID(pendingRouteJournalID, armLock: true)
                store.consumeRoute()
                self.pendingRouteJournalID = nil
            } else if let route = store.route, route.destination == .journals {
                setSelectedJournalID(route.recordID, armLock: true)
                store.consumeRoute()
            }
        } else {
            clearJournalFiltersForDeactivationIfNeeded()
            cancelJournalBackgroundTasksForInactiveState()
        }
    }

    private func journalSearchFilterCard(language: AppLanguage) -> some View {
        AppFilterCard {
            VStack(alignment: .leading, spacing: 8) {
                AppFilterRow(
                    showsClearButton: searchText.nonEmpty != nil || searchAlsoInPublisher,
                    clearAction: {
                        searchText = ""
                        searchAlsoInPublisher = false
                    }
                ) {
                    AppSidebarSearchField(
                        placeholder: language.text("Search journals", "Sök tidskrifter"),
                        text: $searchText
                    )

                    AppFilterChip(
                        label: language.text("Search also in publishers", "Sök även i förlag"),
                        isSelected: searchAlsoInPublisher
                    ) {
                        searchAlsoInPublisher.toggle()
                    }
                }

                AppFilterRow(
                    showsClearButton: !selectedCategories.isEmpty || !excludedCategories.isEmpty,
                    clearAction: {
                        selectedCategories.removeAll()
                        excludedCategories.removeAll()
                    }
                ) {
                    journalCategoryFilterMenu(language: language)
                }

                AppFilterRow(
                    showsClearButton: includeNorwegianLevel1 || includeNorwegianLevel2,
                    clearAction: {
                        includeNorwegianLevel1 = false
                        includeNorwegianLevel2 = false
                    }
                ) {
                    AppFilterChip(
                        label: language.text("Norwegian 1", "Norska 1"),
                        isSelected: includeNorwegianLevel1
                    ) {
                        includeNorwegianLevel1.toggle()
                    }
                    AppFilterChip(
                        label: language.text("Norwegian 2", "Norska 2"),
                        isSelected: includeNorwegianLevel2
                    ) {
                        includeNorwegianLevel2.toggle()
                    }
                }

                AppFilterRow(
                    showsClearButton: onlyPreviouslySubmitted || onlyPreviouslyPublished,
                    clearAction: {
                        onlyPreviouslySubmitted = false
                        onlyPreviouslyPublished = false
                    }
                ) {
                    AppFilterChip(
                        label: language.text("Previously submitted to", "Tidigare skickade till"),
                        isSelected: onlyPreviouslySubmitted
                    ) {
                        onlyPreviouslySubmitted.toggle()
                    }
                    AppFilterChip(
                        label: language.text("Previously published in", "Tidigare publicerade i"),
                        isSelected: onlyPreviouslyPublished
                    ) {
                        onlyPreviouslyPublished.toggle()
                    }
                }

                AppFilterRow(
                    showsClearButton: minimumJIFValue > 0,
                    clearAction: { minimumJIFValue = 0 }
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(language.text("Minimum JIF", "Lägst JIF")): \(formattedJournalMetric(minimumJIFValue))")
                            .appTypography(.fieldLabel)
                        Slider(
                            value: Binding(
                                get: { minimumJIFValue },
                                set: { minimumJIFValue = min($0, maximumJIFValue) }
                            ),
                            in: 0...maximumJIFValue,
                            step: 0.1
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                }

                AppFilterClearAllRow(isVisible: hasActiveJournalFilters) {
                    searchText = ""
                    searchAlsoInPublisher = false
                    selectedCategories.removeAll()
                    excludedCategories.removeAll()
                    showingCategoryFilter = false
                    minimumJIFValue = 0
                    includeNorwegianLevel1 = false
                    includeNorwegianLevel2 = false
                    onlyPreviouslySubmitted = false
                    onlyPreviouslyPublished = false
                }
            }
        }
    }

    private func journalCategoryFilterMenu(language: AppLanguage) -> some View {
        Button {
            showingCategoryFilter.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(categoryMenuLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .appMenuChrome(
            horizontalPadding: AppPalette.textFieldHorizontalPadding,
            verticalPadding: AppPalette.textFieldVerticalPadding
        )
        .popover(isPresented: $showingCategoryFilter, arrowEdge: .bottom) {
            journalCategoryFilterPopover(language: language)
        }
    }

    private func journalCategoryFilterPopover(language: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                AppPanelHeadingText(text: language.text("Categories", "Kategorier"))
                Spacer()
                AppFilterResetButton(
                    help: language.text("Clear category filters", "Rensa kategorifilter")
                ) {
                    selectedCategories.removeAll()
                    excludedCategories.removeAll()
                }
                .disabled(selectedCategories.isEmpty && excludedCategories.isEmpty)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(categoryOptions, id: \.self) { category in
                        journalCategoryFilterRow(for: category, language: language)
                    }
                }
            }
            .frame(width: 280, height: 320)
        }
        .padding(12)
    }

    private func journalCategoryFilterRow(for category: String, language: AppLanguage) -> some View {
        let isExcluded = excludedCategories.contains(category)

        return HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { selectedCategories.contains(category) },
                set: { isSelected in
                    if isSelected {
                        excludedCategories.remove(category)
                        selectedCategories.insert(category)
                    } else {
                        selectedCategories.remove(category)
                    }
                }
            )) {
                Text(category)
                    .appTypography(.body)
                    .lineLimit(1)
            }
            .appCheckboxStyle()

            Spacer(minLength: 8)

            Button {
                if isExcluded {
                    excludedCategories.remove(category)
                } else {
                    selectedCategories.remove(category)
                    excludedCategories.insert(category)
                }
            } label: {
                Image(systemName: isExcluded ? "minus.square.fill" : "minus.square")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isExcluded ? AppPalette.actionDelete : Color.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(language.text("Exclude category", "Filtrera bort kategori"))
            .accessibilityLabel(language.text("Exclude category", "Filtrera bort kategori"))
            .accessibilityAddTraits(isExcluded ? .isSelected : [])
        }
    }

    private func cancelJournalBackgroundTasksForInactiveState() {
        searchRebuildTask?.cancel()
        journalSnapshotRefreshTask?.cancel()
        neighboringWarmTask?.cancel()
        journalDistributionRefreshTask?.cancel()
        journalIdleWarmupTask?.cancel()
        journalRowsBuildGeneration &+= 1
    }

    private func clearJournalFiltersForDeactivationIfNeeded() {
        guard !store.shouldRetainListFilters(for: .journals) else { return }
        guard hasActiveJournalFilters else { return }
        searchText = ""
        searchAlsoInPublisher = false
        selectedCategories.removeAll()
        excludedCategories.removeAll()
        showingCategoryFilter = false
        minimumJIFValue = 0
        includeNorwegianLevel1 = false
        includeNorwegianLevel2 = false
        onlyPreviouslySubmitted = false
        onlyPreviouslyPublished = false
        needsJournalFilterRebuildWhenActive = true
    }

    private func handleJournalViewDisappear() {
        searchRebuildTask?.cancel()
        journalSnapshotRefreshTask?.cancel()
        neighboringWarmTask?.cancel()
        journalDistributionRefreshTask?.cancel()
        journalIdleWarmupTask?.cancel()
        journalDistributionBuildToken &+= 1
        journalSelectionCoordinator.clear()
        pendingInitialDistributionRefresh = false
    }

    private func journalResultsTable(language: AppLanguage) -> some View {
        let journalWidth: CGFloat = 300
        let categoryWidth: CGFloat = 150
        let tableMinWidth: CGFloat = journalWidth + 68 + 84 + 118 + categoryWidth + 20
        let orderedIDs = filteredJournalRows.map(\.id)

        return AppListTable(contentWidth: tableMinWidth) {
            HStack(spacing: 0) {
                journalListHeader(language.text("Journal", "Tidskrift"), column: .name)
                    .frame(width: journalWidth, alignment: .leading)
                journalListHeader("JIF", width: 68, column: .jif)
                journalListHeader(language.text("Norw list", "Norw list"), width: 84, column: .norwegian)
                journalListHeader(language.text("Acceptance", "Acceptans"), width: 118, column: .acceptance)
                journalListHeader(language.text("Category", "Kategori"), width: categoryWidth, column: .category)
            }
        } rows: {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(filteredJournalRows) { journal in
                    AppListRowButton(
                        width: tableMinWidth,
                        action: { handleJournalRowSelection(journal.id) },
                        background: { journalListSelectionBackground(for: journal) }
                    ) {
                        HStack(spacing: 0) {
                            Text(journal.name)
                                .appTypography(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: journalWidth, alignment: .leading)

                            PublicationMetricValueBadge(
                                metric: journal.jifMetric,
                                backgroundColor: journalTablePerformanceMode ? nil : journalMetricDistributionSummary.backgroundColor(for: journal.jifMetric),
                                isCompact: true
                            )
                            .frame(width: 68)

                            PublicationMetricValueBadge(
                                metric: journal.norwegianMetric,
                                backgroundColor: journalTablePerformanceMode ? nil : journalMetricDistributionSummary.backgroundColor(for: journal.norwegianMetric),
                                isCompact: true
                            )
                            .frame(width: 84)

                            Text(journal.acceptanceText)
                                .appTypography(.secondary)
                                .lineLimit(1)
                                .frame(width: 118, alignment: .leading)

                            Text(journal.categoryText.isEmpty ? "–" : journal.categoryText)
                                .appTypography(.secondary)
                                .foregroundStyle(journal.categoryText.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: categoryWidth, alignment: .leading)
                        }
                    }
                    .id(journal.id)
                    .contextMenu {
                        journalAddToPublicationMenu(for: journal, language: language)
                    }

                    if journal.id != filteredJournalRows.last?.id {
                        Divider()
                    }
                }
            }
        }
        .background(
            PublicationPerformanceReporter {
                reportInitialJournalTableReadyIfNeeded()
            }
        )
        .appListKeyboardNavigation(
            store: store,
            destination: .journals,
            isEnabled: isActive,
            orderedIDs: orderedIDs,
            selectedID: selectedJournalID,
            onSelect: handleJournalSelectionCandidate
        )
    }

    private func primeJournalRowsForFirstPaint() {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let snapshots = store.cachedPublicationJournalRowSnapshots()
        if store.isPublicationJournalRowSnapshotCacheStale {
            store.preparePublicationJournalRowSnapshots(reason: "journals-prime")
        }
        guard !snapshots.isEmpty else {
            journalRows = []
            baseFilteredJournalRows = []
            filteredJournalRows = []
            categoryOptionsCache = []
            logJournalMeasurement(
                "journals-prime-deferred cached_rows=0 total_ms=%.2f",
                (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            )
            return
        }

        let primeRows = snapshots.map(Self.buildPrimeJournalRow)
        journalRows = primeRows
        let sortedRows = primeRows.sorted(using: sortOrder)
        baseFilteredJournalRows = sortedRows
        filteredJournalRows = sortedRows
        categoryOptionsCache = Array(Set(primeRows.flatMap(\.categories)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        journalRowsAppliedGeneration &+= 1
        lastSearchQuery = SearchFilterQuery(raw: "")
        lastNonSearchFilterSignature = currentNonSearchFilterSignature()
        logJournalMeasurement(
            "journals-prime rows=%d rebuild_ms=%.2f",
            primeRows.count,
            (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        )
    }

    private func scheduleJournalSnapshotRefresh(reason: String, delay: TimeInterval = 0.08) {
        guard isActive else {
            needsJournalSnapshotRefreshWhenActive = true
            needsJournalFilterRebuildWhenActive = true
            return
        }
        journalSnapshotRefreshTask?.cancel()
        let task = DispatchWorkItem {
            rebuildJournalRowsFromSnapshots(reason: reason)
        }
        journalSnapshotRefreshTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    private func rebuildJournalRowsFromSnapshots(reason: String) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        journalRowsBuildGeneration &+= 1
        let generation = journalRowsBuildGeneration
        let snapshots = store.cachedPublicationJournalRowSnapshots()
        if store.isPublicationJournalRowSnapshotCacheStale {
            store.preparePublicationJournalRowSnapshots(reason: reason)
        }
        guard !snapshots.isEmpty else {
            logJournalMeasurement(
                "journals-rows-deferred reason=%@ cached_rows=0 total_ms=%.2f",
                reason,
                (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            )
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let nextRows = snapshots.map(Self.buildPrimeJournalRow)
            let nextCategories = Array(Set(nextRows.flatMap(\.categories)))
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

            DispatchQueue.main.async {
                guard isActive, journalRowsBuildGeneration == generation else { return }
                journalRows = nextRows
                categoryOptionsCache = nextCategories
                journalRowsAppliedGeneration &+= 1
                minimumJIFValue = min(minimumJIFValue, maximumJIFValue)
                rebuildFilteredJournalRows(reason: reason)
                logJournalMeasurement(
                    "journals-rows reason=%@ rows=%d rebuild_ms=%.2f",
                    reason,
                    nextRows.count,
                    (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
                )
            }
        }
    }

    private func scheduleJournalDistributionRefresh(reason: String, delay: TimeInterval) {
        guard isActive else {
            needsJournalDistributionRefreshWhenActive = true
            return
        }
        journalDistributionRefreshTask?.cancel()
        journalDistributionBuildToken &+= 1
        let token = journalDistributionBuildToken
        let journalsSnapshot = store.journals
        let task = DispatchWorkItem {
            DispatchQueue.global(qos: .utility).async {
                let startedAt = CFAbsoluteTimeGetCurrent()
                let rankingCache = JournalRankingEditorDistributionCache(journals: journalsSnapshot)
                let summary = JournalMetricDistributionSummary(journals: journalsSnapshot)
                let duration = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000

                DispatchQueue.main.async {
                    guard journalDistributionBuildToken == token else { return }
                    journalRankingDistributionCache = rankingCache
                    journalMetricDistributionSummary = summary
                    journalTablePerformanceMode = false
                    logJournalMeasurement(
                        "journals-ranking-cache reason=%@ cache_ms=%.2f",
                        reason,
                        duration
                    )
                }
            }
        }
        journalDistributionRefreshTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    private func scheduleInitialJournalDistributionRefreshIfNeeded() {
        guard pendingInitialDistributionRefresh else { return }
        pendingInitialDistributionRefresh = false
        scheduleJournalDistributionRefresh(reason: "initial", delay: 0.22)
    }

    private func rebuildFilteredJournalRows(reason: String = "manual") {
        guard isActive else {
            needsJournalFilterRebuildWhenActive = true
            return
        }
        let startedAt = CFAbsoluteTimeGetCurrent()
        searchRebuildTask?.cancel()
        let searchQuery = SearchFilterQuery(raw: searchText)
        let nonSearchSignature = currentNonSearchFilterSignature()
        let canReusePreviousSearchBase =
            reason == "debounced-search"
            && nonSearchSignature == lastNonSearchFilterSignature
            && searchQuery.isNarrowing(over: lastSearchQuery)

        let baseRows: [PublicationJournalListRow]
        if canReusePreviousSearchBase {
            baseRows = baseFilteredJournalRows
        } else {
            baseRows = nonSearchMatchingJournalRows.sorted(using: sortOrder)
            baseFilteredJournalRows = baseRows
        }

        let candidateRows = canReusePreviousSearchBase ? filteredJournalRows : baseRows
        let rows = searchQuery.isEmpty
            ? baseRows
            : candidateRows.filter { row in
                let haystack = searchAlsoInPublisher
                    ? row.normalizedExtendedFilterSearchBlob
                    : row.normalizedFilterSearchBlob
                return searchQuery.matches(normalizedHaystack: haystack)
            }

        filteredJournalRows = rows
        lastSearchQuery = searchQuery
        lastNonSearchFilterSignature = nonSearchSignature
        if selectedJournalID == nil {
            setSelectedJournalID(rows.first?.id, resignFirstResponder: false)
        } else if store.publicationJournal(id: selectedJournalID) == nil {
            setSelectedJournalID(rows.first?.id, resignFirstResponder: false)
        }
        logJournalMeasurement(
            "journals-filtered reason=%@ rows=%d base_rows=%d incremental=%@ filter_ms=%.2f",
            reason,
            rows.count,
            baseRows.count,
            canReusePreviousSearchBase ? "yes" : "no",
            (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        )
        store.appendPerformanceDiagnostic(
            "journals-query raw=\(searchQuery.raw.debugDescription) included=\(searchQuery.includedTerms) excluded=\(searchQuery.excludedTerms) rows=\(rows.count) first=\(rows.prefix(5).map(\.name))"
        )
    }

    private func scheduleFilteredJournalRowsRebuild() {
        guard isActive else {
            needsJournalFilterRebuildWhenActive = true
            return
        }
        searchRebuildTask?.cancel()
        let task = DispatchWorkItem {
            rebuildFilteredJournalRows(reason: "debounced-search")
        }
        searchRebuildTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: task)
    }

    private func reportInitialJournalTableReadyIfNeeded() {
        guard !journalTableInitialReadyLogged else { return }
        journalTableInitialReadyLogged = true
        logJournalMeasurement("journals-table-ready kind=%@", "table")
    }

    private func reportInitialJournalDetailReadyIfNeeded(kind: String) {
        guard !journalDetailInitialReadyLogged else { return }
        journalDetailInitialReadyLogged = true
        logJournalMeasurement("journals-detail-ready kind=%@", kind)
    }

    private func scheduleNeighborWarm(around id: String?) {
        guard isActive else { return }
        neighboringWarmTask?.cancel()
        let task = DispatchWorkItem {
            warmNeighboringJournalSelections(around: id)
        }
        neighboringWarmTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15, execute: task)
    }

    private func scheduleJournalIdleWarmup() {
        journalIdleWarmupTask?.cancel()
        guard isActive else { return }
        let ids = Array(filteredJournalRows.prefix(24).map(\.id))
        guard !ids.isEmpty else { return }
        let task = DispatchWorkItem {
            guard isActive else { return }
            for id in ids {
                _ = store.publicationJournal(id: id)
                _ = store.publicationJournalDerivedMetrics(id: id)
            }
            store.appendPerformanceDiagnostic(
                String(
                    format: "journals-idle-warm rows=%ld",
                    ids.count
                )
            )
        }
        journalIdleWarmupTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: task)
    }

    private func journalListHeader(_ title: String, width: CGFloat? = nil, column: JournalListSortColumn) -> some View {
        let criterion = sortCriterion(for: column)
        let sortIndex = sortIndex(for: column)
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

    private func toggleSort(_ column: JournalListSortColumn) {
        if let existingIndex = sortHistory.firstIndex(where: { $0.column == column }) {
            if existingIndex == 0 {
                sortHistory[0].ascending.toggle()
            } else {
                let criterion = sortHistory.remove(at: existingIndex)
                sortHistory.insert(criterion, at: 0)
            }
        } else {
            sortHistory.insert(JournalListSortCriterion(column: column, ascending: column.defaultAscending), at: 0)
        }
        ListSortPersistence.save(sortHistory, defaultsKey: "PublicationJournalsListSort")
    }

    private func resetSort() {
        sortHistory = [
            JournalListSortCriterion(column: .norwegian, ascending: false),
            JournalListSortCriterion(column: .jif, ascending: false),
            JournalListSortCriterion(column: .name, ascending: true),
        ]
        ListSortPersistence.save(sortHistory, defaultsKey: "PublicationJournalsListSort")
    }

    private func sortCriterion(for column: JournalListSortColumn) -> JournalListSortCriterion? {
        sortHistory.first(where: { $0.column == column })
    }

    private func sortIndex(for column: JournalListSortColumn) -> Int? {
        sortHistory.firstIndex(where: { $0.column == column })
    }

    private func journalListSelectionBackground(for journal: PublicationJournalListRow) -> some View {
        AppListRowBackground(
            isSelected: journal.id == selectedJournalID || selectedJournalIDsInOrder.contains(journal.id)
        )
    }

    private var unpublishedPublicationsForJournalMenu: [PublicationRecord] {
        store.publications
            .filter { PublicationStatus.fromStored($0.statusLabel) != .published }
            .sorted {
                let left = $0.title.nonEmpty ?? $0.number
                let right = $1.title.nonEmpty ?? $1.number
                return left.localizedStandardCompare(right) == .orderedAscending
            }
    }

    @ViewBuilder
    private func journalAddToPublicationMenu(
        for journal: PublicationJournalListRow,
        language: AppLanguage
    ) -> some View {
        Menu(language.text("Add to publication", "Lägg till publikation")) {
            if unpublishedPublicationsForJournalMenu.isEmpty {
                Button(language.text("No unpublished publications", "Inga opublicerade publikationer")) {}
                    .disabled(true)
            } else {
                ForEach(unpublishedPublicationsForJournalMenu) { publication in
                    Button(publication.title.nonEmpty ?? language.text("Untitled publication", "Namnlös publikation")) {
                        store.addPublicationJournals(
                            journalIDsForContextMenu(clickedJournalID: journal.id),
                            toPublicationID: publication.id
                        )
                    }
                }
            }
        }
    }

    private func journalIDsForContextMenu(clickedJournalID: String) -> [String] {
        if selectedJournalIDsInOrder.contains(clickedJournalID) {
            return selectedJournalIDsInOrder
        }
        return [clickedJournalID]
    }

    private func warmNeighboringJournalSelections(around id: String?) {
        guard let id,
              let selectedIndex = filteredJournalRows.firstIndex(where: { $0.id == id }) else { return }
        let neighborIDs = [selectedIndex - 1, selectedIndex + 1]
            .filter { filteredJournalRows.indices.contains($0) }
            .map { filteredJournalRows[$0].id }
        for neighborID in neighborIDs {
            _ = store.publicationJournalDerivedMetrics(id: neighborID)
        }
    }

    private func currentNonSearchFilterSignature() -> String {
        [
            selectedCategories.sorted().joined(separator: "|"),
            excludedCategories.sorted().joined(separator: "|"),
            String(format: "%.1f", minimumJIFValue),
            includeNorwegianLevel1 ? "1" : "0",
            includeNorwegianLevel2 ? "1" : "0",
            onlyPreviouslySubmitted ? "1" : "0",
            onlyPreviouslyPublished ? "1" : "0",
            searchAlsoInPublisher ? "1" : "0",
            String(journalRowsAppliedGeneration)
        ].joined(separator: "||")
    }

    private func logJournalMeasurement(_ format: String, _ arguments: CVarArg...) {
        let message = String(format: format, arguments: arguments)
        if let startedAt = journalsViewMeasurementStartedAt {
            let sinceEnter = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            store.appendPerformanceDiagnostic(
                String(format: "%@ since_enter_ms=%.2f", message, sinceEnter)
            )
        } else {
            store.appendPerformanceDiagnostic(message)
        }
    }

    nonisolated private static func buildPrimeJournalRow(from snapshot: PublicationJournalRowSnapshot) -> PublicationJournalListRow {
        PublicationJournalListRow(
            id: snapshot.id,
            name: snapshot.name,
            categoryText: snapshot.subtitle,
            categories: snapshot.categories,
            categorySet: snapshot.categorySet,
            filterSearchBlob: snapshot.filterSearchBlob,
            normalizedFilterSearchBlob: snapshot.normalizedFilterSearchBlob,
            extendedFilterSearchBlob: snapshot.extendedFilterSearchBlob,
            normalizedExtendedFilterSearchBlob: snapshot.normalizedExtendedFilterSearchBlob,
            searchBlob: snapshot.filterSearchBlob,
            normalizedSearchBlob: snapshot.normalizedFilterSearchBlob,
            latestImpactFactorValue: snapshot.latestImpactFactorValue,
            latestNorwegianLevelValue: snapshot.latestNorwegianLevelValue,
            hasPreviousSubmission: snapshot.hasPreviousSubmission,
            hasPreviousPublication: snapshot.hasPreviousPublication,
            jifMetric: snapshot.jifMetric,
            jifBackgroundColor: nil,
            norwegianMetric: snapshot.norwegianMetric,
            norwegianBackgroundColor: nil,
            acceptanceText: snapshot.acceptanceText,
            acceptanceSortValue: snapshot.acceptanceSortValue
        )
    }

    private func formattedJournalMetric(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = value.rounded() == value ? 0 : 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }

    private func handleJournalSelectionCandidate(_ newValue: String?) {
        guard journalSelectionCoordinator.accepts(candidate: newValue) else { return }
        selectedJournalIDsInOrder = newValue.map { [$0] } ?? []
        setSelectedJournalID(newValue, armLock: newValue != nil)
    }

    private func handleJournalRowSelection(_ journalID: String) {
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            if let existingIndex = selectedJournalIDsInOrder.firstIndex(of: journalID) {
                selectedJournalIDsInOrder.remove(at: existingIndex)
                let nextID = selectedJournalIDsInOrder.last
                setSelectedJournalID(nextID, armLock: nextID != nil)
            } else {
                if selectedJournalIDsInOrder.isEmpty, let selectedJournalID {
                    selectedJournalIDsInOrder.append(selectedJournalID)
                }
                selectedJournalIDsInOrder.append(journalID)
                setSelectedJournalID(journalID, armLock: true)
            }
            return
        }

        handleJournalSelectionCandidate(journalID)
    }

    private func setSelectedJournalID(_ newValue: String?, armLock: Bool = false, resignFirstResponder: Bool = true) {
        guard selectedJournalID != newValue else {
            if armLock, let newValue {
                armJournalSelectionLock(for: newValue)
            }
            return
        }
        if resignFirstResponder {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        let previousID = selectedJournalID
        selectedJournalID = newValue
        if armLock, let newValue {
            journalSelectionCoordinator.arm(newValue, previousID: previousID)
        } else if newValue == nil {
            journalSelectionCoordinator.clear()
        }
    }

    private func armJournalSelectionLock(for id: String) {
        journalSelectionCoordinator.arm(
            id,
            previousID: journalSelectionCoordinator.previousID
        )
    }

    private func releaseJournalSelectionLock(for id: String) {
        journalSelectionCoordinator.release(ifMatching: id)
    }
}

private struct PublicationPerformanceReporter: View {
    let onAppear: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear(perform: onAppear)
    }
}

private struct PublicationJournalEditorView: View {
    @ObservedObject var store: GrantDataStore
    @Environment(\.scenePhase) private var scenePhase
    let journal: PublicationJournal
    let rankingDistributionCache: JournalRankingEditorDistributionCache
    let isActive: Bool
    let onEditorAppear: ((String) -> Void)?
    let onEditorReady: ((String) -> Void)?

    @State private var draft: PublicationJournal
    @State private var autosaveTask: DispatchWorkItem?
    @State private var forcedPersistTask: DispatchWorkItem?
    @State private var linkedDataRefreshTask: DispatchWorkItem?
    @State private var cachedLinkedPublications: [JournalLinkedPublicationEntry]
    @State private var cachedLinkedConferenceContributions: [CVConferenceContribution]
    @State private var cachedLinkedReviews: [CVReviewEntry]
    @State private var editorAppearedAt: CFAbsoluteTime?
    @State private var hasReportedReady = false
    @State private var showHeavySections = false
    @State private var showLinkedDataSection = false
    @State private var deferredHeavySectionsTask: DispatchWorkItem?
    @State private var deferredLinkedSectionTask: DispatchWorkItem?

    private let editableYears = Array(2019...2027)

    init(
        store: GrantDataStore,
        journal: PublicationJournal,
        rankingDistributionCache: JournalRankingEditorDistributionCache,
        isActive: Bool = true,
        onEditorAppear: ((String) -> Void)? = nil,
        onEditorReady: ((String) -> Void)? = nil
    ) {
        self.store = store
        self.journal = journal
        self.rankingDistributionCache = rankingDistributionCache
        self.isActive = isActive
        self.onEditorAppear = onEditorAppear
        self.onEditorReady = onEditorReady
        _draft = State(initialValue: journal)
        _cachedLinkedPublications = State(initialValue: [])
        _cachedLinkedConferenceContributions = State(initialValue: [])
        _cachedLinkedReviews = State(initialValue: [])
    }

    private var linkedPublications: [JournalLinkedPublicationEntry] {
        cachedLinkedPublications
    }

    private var linkedConferenceContributions: [CVConferenceContribution] {
        cachedLinkedConferenceContributions
    }

    private var linkedReviews: [CVReviewEntry] {
        cachedLinkedReviews
    }

    private var journalHomeURL: URL? {
        draft.journalHomeURL
    }

    private var submissionPortalURL: URL? {
        draft.submissionPortalLinkURL
    }

    var body: some View {
        let language = store.language

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                HStack {
                    AppInlineTitleTextField(
                        placeholder: language.text("Journal name", "Tidskriftsnamn"),
                        text: binding(\.name),
                        font: .systemFont(ofSize: 24, weight: .bold),
                        minHeight: 30
                    )
                    if let journalHomeURL {
                        Link(destination: journalHomeURL) {
                            AppInlineLinkLabel(title: language.text("Journal homepage", "Tidskriftens hemsida"))
                        }
                        .foregroundStyle(AppPalette.linkAction)
                    }
                    if let submissionPortalURL {
                        Link(destination: submissionPortalURL) {
                            AppInlineLinkLabel(title: language.text("Submission portal", "Inskickningsportal"))
                        }
                        .foregroundStyle(AppPalette.linkAction)
                    }
                    Spacer()
                    AppDestructiveActionButton(title: language.text("Delete", "Ta bort")) {
                        store.deletePublicationJournal(id: journal.id)
                    }
                }
                .frame(minHeight: 42)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        compactField(language.text("Short name NLM", "Kortnamn NLM"), width: 190) {
                            TextField(language.text("Short name NLM", "Kortnamn NLM"), text: binding(\.abbreviatedName))
                                .appTextInputChrome()
                        }
                        compactField(language.text("Short name ISSN LTWA", "Kortnamn ISSN LTWA"), width: 220) {
                            TextField(language.text("Short name ISSN LTWA", "Kortnamn ISSN LTWA"), text: issnLTWAAbbreviatedNameBinding)
                                .appTextInputChrome()
                        }
                        compactField("ISSN", width: 170) {
                            TextField("ISSN", text: binding(\.issn, formatter: normalizedJournalISSNInput))
                                .appTextInputChrome()
                        }
                        compactField("eISSN", width: 170) {
                            TextField("eISSN", text: binding(\.eissn, formatter: normalizedJournalISSNInput))
                                .appTextInputChrome()
                        }
                        compactField(language.text("Publisher", "Förlag"), width: 240) {
                            TextField(language.text("Publisher", "Förlag"), text: binding(\.publisher))
                                .appTextInputChrome()
                        }
                        compactField(language.text("Country", "Land"), width: 170) {
                            CountryPickerField(selection: binding(\.country), language: language, width: 170)
                        }
                    }
                    HStack(spacing: 10) {
                        compactField(language.text("Categories", "Kategorier"), width: 360) {
                            TextField(language.text("Categories", "Kategorier"), text: categoriesBinding)
                                .appTextInputChrome()
                        }
                        compactField(language.text("NPI area", "NPI-område"), width: 220) {
                            TextField(language.text("NPI area", "NPI-område"), text: binding(\.npiArea))
                                .appTextInputChrome()
                        }
                        compactField(language.text("Established", "Startår"), width: 120) {
                            AppYearField(text: binding(\.establishedYear), language: language, width: 120)
                        }
                        compactField(language.text("End year", "Slutår"), width: 120) {
                            AppYearField(text: binding(\.discontinuedYear), language: language, width: 120)
                        }
                    }
                    HStack(spacing: 10) {
                        compactField(language.text("Journal homepage", "Tidskriftens hemsida"), width: 360) {
                            TextField(language.text("Journal homepage", "Tidskriftens hemsida"), text: binding(\.journalURL))
                                .appTextInputChrome()
                        }
                        compactField(language.text("Submission portal", "Inskickningsportal"), width: 360) {
                            TextField(language.text("Submission portal", "Inskickningsportal"), text: binding(\.submissionPortalURL))
                                .appTextInputChrome()
                        }
                        Spacer()
                    }
                }
                .padding(.top, 8)

                rankingPanel(language: language)

                linkedPublicationsPanel(language: language)
                linkedReviewsPanel(language: language)
            }
            .padding(14)
            .background(
                PublicationPerformanceReporter {
                    reportEditorReadyIfNeeded()
                }
            )
        }
        .onAppear {
            if isActive {
                handleEditorAppear()
                armDeferredSections()
            } else {
                showHeavySections = false
                showLinkedDataSection = false
            }
        }
        .onChange(of: journal) { oldValue, newValue in
            handleJournalChange(from: oldValue, to: newValue)
        }
        .onChange(of: draft) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: draft.name) { oldValue, newValue in
            syncGeneratedISSNLTWAShortName(oldName: oldValue, newName: newValue)
            guard showLinkedDataSection else { return }
            scheduleLinkedDataRefresh(forJournalID: draft.id, journalName: newValue, reason: "name-change")
        }
        .onReceive(store.$publicationRecords.dropFirst()) { _ in
            guard showLinkedDataSection else { return }
            scheduleLinkedDataRefresh(forJournalID: draft.id, journalName: draft.name, reason: "records-change")
        }
        .onReceive(store.$cvConferenceContributions.dropFirst()) { _ in
            guard showLinkedDataSection else { return }
            scheduleLinkedDataRefresh(forJournalID: draft.id, journalName: draft.name, reason: "conference-change")
        }
        .onReceive(store.$cvReviewEntries.dropFirst()) { _ in
            guard showLinkedDataSection else { return }
            scheduleLinkedDataRefresh(forJournalID: draft.id, journalName: draft.name, reason: "reviews-change")
        }
        .flushPendingAutosaveOnTextEnd(scheduleAutosave)
        .onChange(of: scenePhase) { _, newValue in
            if newValue != .active {
                requestImmediateAutosave()
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                handleEditorAppear()
                armDeferredSections()
            } else {
                linkedDataRefreshTask?.cancel()
                deferredHeavySectionsTask?.cancel()
                deferredLinkedSectionTask?.cancel()
                showHeavySections = false
                showLinkedDataSection = false
                requestImmediateAutosave()
            }
        }
        .onDisappear {
            autosaveTask?.cancel()
            forcedPersistTask?.cancel()
            linkedDataRefreshTask?.cancel()
            deferredHeavySectionsTask?.cancel()
            deferredLinkedSectionTask?.cancel()
            autosave(baseline: journal, completePendingSelection: true)
            store.finalizePendingJournalSelection(id: journal.id)
        }
    }

    private func handleEditorAppear() {
        editorAppearedAt = CFAbsoluteTimeGetCurrent()
        hasReportedReady = false
        onEditorAppear?(draft.id)
        reportEditorReadyIfNeeded()
    }

    private func handleJournalChange(from oldValue: PublicationJournal, to newValue: PublicationJournal) {
        if oldValue.id != newValue.id {
            autosaveTask?.cancel()
            forcedPersistTask?.cancel()
            linkedDataRefreshTask?.cancel()
            deferredHeavySectionsTask?.cancel()
            deferredLinkedSectionTask?.cancel()
            autosave(baseline: oldValue, completePendingSelection: true)
            let reseedStartedAt = CFAbsoluteTimeGetCurrent()
            draft = newValue
            cachedLinkedPublications = []
            cachedLinkedConferenceContributions = []
            cachedLinkedReviews = []
            showHeavySections = false
            showLinkedDataSection = false
            store.appendPerformanceDiagnostic(
                String(
                    format: "journal-editor-reseed journal=%@ reseed_ms=%.2f",
                    newValue.name,
                    (CFAbsoluteTimeGetCurrent() - reseedStartedAt) * 1000
                )
            )
            if isActive {
                handleEditorAppear()
                armDeferredSections()
            } else {
                showHeavySections = false
                showLinkedDataSection = false
            }
            return
        }

        guard draft != newValue else { return }
        draft = newValue
        if showLinkedDataSection {
            scheduleLinkedDataRefresh(forJournalID: newValue.id, journalName: newValue.name, reason: "store-sync")
        }
    }

    private func armDeferredSections() {
        deferredHeavySectionsTask?.cancel()
        deferredLinkedSectionTask?.cancel()
        guard isActive else {
            showHeavySections = false
            showLinkedDataSection = false
            return
        }
        showHeavySections = false
        showLinkedDataSection = false

        let heavyTask = DispatchWorkItem {
            showHeavySections = true
            deferredHeavySectionsTask = nil
            store.appendPerformanceDiagnostic("journal-heavy-sections-ready journal=\(draft.name)")
        }
        deferredHeavySectionsTask = heavyTask
        DispatchQueue.main.async(execute: heavyTask)

        let linkedTask = DispatchWorkItem {
            showLinkedDataSection = true
            deferredLinkedSectionTask = nil
            scheduleLinkedDataRefresh(forJournalID: draft.id, journalName: draft.name, reason: "appear")
            store.appendPerformanceDiagnostic("journal-linked-section-visible journal=\(draft.name)")
        }
        deferredLinkedSectionTask = linkedTask
        DispatchQueue.main.async(execute: linkedTask)
    }

    private func scheduleLinkedDataRefresh(forJournalID journalID: String, journalName: String, reason: String) {
        linkedDataRefreshTask?.cancel()
        guard isActive else { return }
        let task = DispatchWorkItem {
            refreshLinkedData(forJournalID: journalID, journalName: journalName, reason: reason)
        }
        linkedDataRefreshTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: task)
    }

    private func refreshLinkedData(forJournalID journalID: String, journalName: String, reason: String) {
        guard isActive else { return }
        let startedAt = CFAbsoluteTimeGetCurrent()
        let linkedPublications: [JournalLinkedPublicationEntry]
        let linkedConferenceContributions: [CVConferenceContribution]
        let linkedReviews: [CVReviewEntry]

        // "Alla kopplingar via id": what points to the journal, also while
        // its name is being edited.
        linkedPublications = store.linkedJournalEntries(forJournalID: journalID)
        linkedConferenceContributions = store.publishedConferenceContributions(forJournalID: journalID)
        linkedReviews = store.cvReviewEntries.filter {
            guard let reviewJournal = store.linkedJournal(of: $0) else { return false }
            return reviewJournal.id == journalID
        }
        cachedLinkedPublications = linkedPublications
        cachedLinkedConferenceContributions = linkedConferenceContributions
        cachedLinkedReviews = linkedReviews
        store.appendPerformanceDiagnostic(
            String(
                format: "journal-linked-data journal=%@ reason=%@ refresh_ms=%.2f publications=%ld conference=%ld reviews=%ld",
                journalName,
                reason,
                (CFAbsoluteTimeGetCurrent() - startedAt) * 1000,
                linkedPublications.count,
                linkedConferenceContributions.count,
                linkedReviews.count
            )
        )
    }

    private func reportEditorReadyIfNeeded() {
        guard !hasReportedReady else { return }
        hasReportedReady = true
        if let editorAppearedAt {
            store.appendPerformanceDiagnostic(
                String(
                    format: "journal-editor-ready journal=%@ ready_ms=%.2f",
                    draft.name,
                    (CFAbsoluteTimeGetCurrent() - editorAppearedAt) * 1000
                )
            )
        }
        DispatchQueue.main.async {
            onEditorReady?(draft.id)
        }
    }

    private func persist(completePendingSelection: Bool = false) {
        persist(baseline: journal, completePendingSelection: completePendingSelection)
    }

    private func persist(baseline: PublicationJournal, completePendingSelection: Bool = false) {
        autosaveTask?.cancel()
        guard draft != baseline else {
            if completePendingSelection {
                store.finalizePendingJournalSelection(id: baseline.id)
            }
            return
        }
        syncImpactFactorFields()
        store.savePublicationJournal(draft, previousName: baseline.name, completePendingSelection: completePendingSelection)
    }

    private func autosave(baseline: PublicationJournal, completePendingSelection: Bool = false) {
        guard draft != baseline || completePendingSelection else { return }
        syncImpactFactorFields()
        store.autosavePublicationJournal(draft, previousName: baseline.name, completePendingSelection: completePendingSelection)
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let task = DispatchWorkItem { autosave(baseline: journal) }
        autosaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: task)
    }

    private func requestImmediateAutosave() {
        forcedPersistTask?.cancel()
        let task = DispatchWorkItem {
            forcedPersistTask = nil
            autosave(baseline: journal, completePendingSelection: true)
        }
        forcedPersistTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: task)
    }

    private func binding(_ keyPath: WritableKeyPath<PublicationJournal, String>) -> Binding<String> {
        Binding(get: { draft[keyPath: keyPath] }, set: { draft[keyPath: keyPath] = $0 })
    }

    private func binding(_ keyPath: WritableKeyPath<PublicationJournal, String>, formatter: @escaping (String) -> String) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { draft[keyPath: keyPath] = formatter($0) }
        )
    }

    private var issnLTWAAbbreviatedNameBinding: Binding<String> {
        Binding(
            get: { draft.issnLTWAAbbreviatedName.nonEmpty ?? PublicationLTWA.shortName(for: draft.name) },
            set: { draft.issnLTWAAbbreviatedName = $0 }
        )
    }

    private func syncGeneratedISSNLTWAShortName(oldName: String, newName: String) {
        let current = draft.issnLTWAAbbreviatedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousGenerated = PublicationLTWA.shortName(for: oldName)
        guard current.isEmpty || current == previousGenerated else { return }
        draft.issnLTWAAbbreviatedName = PublicationLTWA.shortName(for: newName)
    }

    private var categoriesBinding: Binding<String> {
        Binding(
            get: { draft.categories.joined(separator: ", ") },
            set: { newValue in
                let normalizedCategories = Array(
                    Set(
                        newValue
                            .split(separator: ",")
                            .compactMap { mergedJournalFilterCategory(String($0)) }
                    )
                )
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

                draft.categories = normalizedCategories

                if normalizedCategories.isEmpty {
                    draft.category = ""
                    draft.subcategory = ""
                } else {
                    draft.category = normalizedCategories.first ?? ""
                    draft.subcategory = normalizedCategories.dropFirst().first ?? ""
                }
            }
        )
    }

    @ViewBuilder
    private func rankingPanel(language: AppLanguage) -> some View {
        PublicationCompactPanel(
            title: language.text("Rankings", "Rankingar"),
            usesInnerSurface: false,
            titleTopPadding: 10,
            titleContentSpacing: 4
        ) {
            if showHeavySections {
                AppPublicationJournalStatusTable {
                    VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(draft.rankingRows.enumerated()), id: \.element.id) { index, row in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 10) {
                                compactField(language.text("Type", "Typ"), width: 220) {
                                    publicationMenuField(
                                        selection: rankingKindBinding(for: row.id),
                                        options: JournalRankingKind.allCases.map { (rankingKindLabel($0), $0) }
                                    )
                                }
                                compactField(language.text("Category", "Kategori"), width: 320) {
                                    TextField(language.text("Category", "Kategori"), text: rankingCategoryBinding(for: row.id))
                                        .appTextInputChrome()
                                }
                                Spacer()
                                AppDestructiveActionButton(title: language.text("Delete row", "Ta bort rad")) {
                                    deleteRankingRow(id: row.id)
                                }
                            }

                            ScrollView(.horizontal, showsIndicators: true) {
                                HStack(alignment: .top, spacing: 8) {
                                    ForEach(editableYears, id: \.self) { year in
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(String(year))
                                                .appTypography(.tableHeader)
                                            if row.kind == .norwegianList {
                                                publicationMenuField(
                                                    selection: rankingValueBinding(for: row.id, year: year),
                                                    options: [("–", ""), ("X", "X"), ("0", "0"), ("1", "1"), ("2", "2")],
                                                    placeholder: "–",
                                                    width: 82,
                                                    fill: rankingValueBackground(for: row, year: year),
                                                    stroke: rankingValueStroke(for: row, year: year),
                                                    foregroundColor: rankingValueForeground(for: row, year: year),
                                                    minHeight: 26,
                                                    verticalPadding: 2
                                                )
                                            } else {
                                                RankingMetricEditorField(
                                                    text: rankingValueBinding(for: row.id, year: year),
                                                    kind: row.kind,
                                                    backgroundColor: rankingValueBackground(for: row, year: year)
                                                )
                                                publicationMenuField(
                                                    selection: rankingQuartileBinding(for: row.id, year: year),
                                                    options: [("–", ""), ("Q1", "Q1"), ("Q2", "Q2"), ("Q3", "Q3"), ("Q4", "Q4")],
                                                    placeholder: "–",
                                                    width: 82,
                                                    fill: rankingQuartileBackground(for: row, year: year),
                                                    stroke: rankingQuartileStroke(for: row, year: year),
                                                    foregroundColor: rankingQuartileForeground(for: row, year: year),
                                                    minHeight: 26,
                                                    verticalPadding: 2
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        if index != draft.rankingRows.indices.last {
                            Divider()
                        }
                    }

                    if draft.rankingRows.isEmpty {
                        Text(language.text("No ranking rows yet.", "Inga rankingrader ännu."))
                            .appTypography(.secondary)
                            .foregroundStyle(.primary)
                    }

                    Menu {
                        ForEach(JournalRankingKind.allCases, id: \.self) { kind in
                            Button(rankingKindLabel(kind)) {
                                addRankingRow(kind: kind)
                            }
                        }
                    } label: {
                        Label(language.text("Add ranking row", "Lägg till rankingrad"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, draft.rankingRows.isEmpty ? 0 : 4)
                }
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func linkedPublicationsPanel(language: AppLanguage) -> some View {
        PublicationCompactPanel(title: language.text("Related publications", "Relaterade publikationer"), usesInnerSurface: false) {
            if !showLinkedDataSection {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                AppCompactReferenceList(
                    isEmpty: linkedPublications.isEmpty && linkedConferenceContributions.isEmpty,
                    emptyTitle: language.text("No records", "Inga poster"),
                    rowSpacing: 0
                ) {
                    ForEach(linkedPublications) { publication in
                        Button(action: {
                            if let record = store.publication(id: publication.publicationID) {
                                store.openRoute(for: record)
                            }
                        }) {
                            AppLinkedStatusRow(
                                fill: linkedPublicationStatusFill(for: publication.status),
                                help: publication.status.displayName(language: language)
                            ) {
                                AuthorLinkedTitleDateRow(title: publication.title, dateText: publication.dateText)
                            }
                        }
                        .buttonStyle(.plain)
                        if publication.id != linkedPublications.last?.id || !linkedConferenceContributions.isEmpty {
                            Divider()
                        }
                    }

                    if !linkedConferenceContributions.isEmpty {
                        AppCompactListSectionLabel(title: language.text("Abstracts", "Abstracts"))
                        ForEach(linkedConferenceContributions) { contribution in
                            Button(action: { store.openRoute(for: contribution) }) {
                                AppLinkedStatusRow(fill: nil) {
                                    AuthorLinkedTitleDateRow(
                                        title: contribution.localizedTitle(language: language).nonEmpty ?? contribution.displayTitle,
                                        dateText: contribution.publicationYear.nonEmpty ?? contribution.to.nonEmpty ?? contribution.from
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                            if contribution.id != linkedConferenceContributions.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func linkedReviewsPanel(language: AppLanguage) -> some View {
        PublicationCompactPanel(title: language.text("Related reviews", "Relaterade sakkunniguppdrag"), usesInnerSurface: false) {
            if !showLinkedDataSection {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                AppCompactReferenceList(isEmpty: linkedReviews.isEmpty, emptyTitle: language.text("No records", "Inga poster"), rowSpacing: 0) {
                    ForEach(linkedReviews) { review in
                        Button(action: { store.openRoute(for: review) }) {
                            AppLinkedStatusRow(fill: nil) {
                                AuthorLinkedTitleDateRow(
                                    title: review.displayTitle.nonEmpty ?? language.text("Review assignment", "Sakkunniguppdrag"),
                                    dateText: review.date.nonEmpty ?? "—"
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        if review.id != linkedReviews.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func linkedPublicationStatusFill(for status: PublicationStatus) -> Color {
        switch status {
        case .published, .accepted:
            return AppPalette.shadeGreen
        case .submitted, .planned, .inPreparation:
            return AppPalette.shadeYellow
        case .rejected:
            return AppPalette.shadeRed
        }
    }

    private func rankingKindLabel(_ kind: JournalRankingKind) -> String {
        switch kind {
        case .clarivateScieJIF:
            "Clarivate SCIE JIF"
        case .clarivateScieJCI:
            "Clarivate SCIE JCI"
        case .clarivateEsciJIF:
            "Clarivate ESCI JIF"
        case .clarivateEsciJCI:
            "Clarivate ESCI JCI"
        case .scimagoSJR:
            "SCImago SJR"
        case .norwegianList:
            "Norw list"
        }
    }

    private func addRankingRow(kind: JournalRankingKind) {
        draft.rankingRows.append(JournalRankingRow(kind: kind, category: kind == .scimagoSJR ? "" : nil))
    }

    private func deleteRankingRow(id: String) {
        draft.rankingRows.removeAll { $0.id == id }
    }

    private func rankingKindBinding(for rowID: String) -> Binding<JournalRankingKind> {
        Binding(
            get: { draft.rankingRows.first(where: { $0.id == rowID })?.kind ?? .clarivateScieJIF },
            set: { newValue in
                guard let index = draft.rankingRows.firstIndex(where: { $0.id == rowID }) else { return }
                draft.rankingRows[index].kind = newValue
                if newValue != .scimagoSJR {
                    draft.rankingRows[index].category = nil
                } else if draft.rankingRows[index].category == nil {
                    draft.rankingRows[index].category = ""
                }
            }
        )
    }

    private func rankingCategoryBinding(for rowID: String) -> Binding<String> {
        Binding(
            get: { draft.rankingRows.first(where: { $0.id == rowID })?.category ?? "" },
            set: { newValue in
                guard let index = draft.rankingRows.firstIndex(where: { $0.id == rowID }) else { return }
                draft.rankingRows[index].category = newValue.trimmedOrNil
            }
        )
    }

    private func rankingValueBinding(for rowID: String, year: Int) -> Binding<String> {
        Binding(
            get: {
                guard let row = draft.rankingRows.first(where: { $0.id == rowID }) else { return "" }
                guard let metric = row.yearlyMetrics.first(where: { $0.year == year }) else {
                    return ""
                }
                return metric.value
            },
            set: { newValue in
                updateRankingMetric(rowID: rowID, year: year, value: newValue, quartile: nil)
            }
        )
    }

    private func rankingQuartileBinding(for rowID: String, year: Int) -> Binding<String> {
        Binding(
            get: {
                guard let row = draft.rankingRows.first(where: { $0.id == rowID }),
                      let metric = row.yearlyMetrics.first(where: { $0.year == year }) else { return "" }
                return metric.quartile
            },
            set: { newValue in
                updateRankingMetric(rowID: rowID, year: year, value: nil, quartile: newValue)
            }
        )
    }

    private func rankingValueBackground(for row: JournalRankingRow, year: Int) -> Color {
        if row.kind == .norwegianList,
           let metric = row.yearlyMetrics.first(where: { $0.year == year }),
           let currentValue = metricNumericValue(metric.value, kind: row.kind) {
            switch Int(currentValue.rounded()) {
            case 2:
                return AppPalette.vividGreen
            case 1:
                return AppPalette.vividYellow
            default:
                return AppPalette.vividRed
            }
        }

        let values = rankingDistributionCache.values(for: row.kind, category: row.category, year: year)
        guard
            let currentMetric = row.yearlyMetrics.first(where: { $0.year == year }),
            let currentValue = metricNumericValue(currentMetric.value, kind: row.kind),
            !values.isEmpty
        else {
            return AppPalette.fieldSurface
        }
        return rankingBackgroundColor(currentValue: currentValue, values: values, kind: row.kind)
    }

    private func rankingQuartileBackground(for row: JournalRankingRow, year: Int) -> Color {
        guard
            let metric = row.yearlyMetrics.first(where: { $0.year == year }),
            !metric.quartile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return AppPalette.fieldSurface
        }

        switch metric.quartile {
        case "Q1":
            return AppPalette.vividGreen
        case "Q2":
            return AppPalette.vividYellow
        case "Q3", "Q4":
            return AppPalette.vividRed
        default:
            return AppPalette.fieldSurface
        }
    }

    private func rankingValueForeground(for row: JournalRankingRow, year: Int) -> Color? {
        guard let metric = row.yearlyMetrics.first(where: { $0.year == year }),
              !metric.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return .primary
    }

    private func rankingValueStroke(for row: JournalRankingRow, year: Int) -> Color {
        guard let metric = row.yearlyMetrics.first(where: { $0.year == year }),
              !metric.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AppPalette.subtleBorder
        }
        return rankingValueBackground(for: row, year: year)
    }

    private func rankingQuartileForeground(for row: JournalRankingRow, year: Int) -> Color? {
        guard let metric = row.yearlyMetrics.first(where: { $0.year == year }),
              !metric.quartile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return .primary
    }

    private func rankingQuartileStroke(for row: JournalRankingRow, year: Int) -> Color {
        guard let metric = row.yearlyMetrics.first(where: { $0.year == year }),
              !metric.quartile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AppPalette.subtleBorder
        }
        return rankingQuartileBackground(for: row, year: year)
    }

    private func metricNumericValue(_ raw: String, kind: JournalRankingKind) -> Double? {
        switch kind {
        case .norwegianList:
            return PublicationJournal.norwegianRankValue(for: raw)
        default:
            return Double(raw.replacingOccurrences(of: ",", with: "."))
        }
    }

    private func updateRankingMetric(rowID: String, year: Int, value: String?, quartile: String?) {
        guard let rowIndex = draft.rankingRows.firstIndex(where: { $0.id == rowID }) else { return }
        var row = draft.rankingRows[rowIndex]
        let metricIndex = row.yearlyMetrics.firstIndex(where: { $0.year == year })
        let updatedValue = value ?? (metricIndex.flatMap { row.yearlyMetrics[$0].value } ?? "")
        let updatedQuartile = quartile ?? (metricIndex.flatMap { row.yearlyMetrics[$0].quartile } ?? "")
        let trimmedValue = updatedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuartile = updatedQuartile.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedValue.isEmpty && trimmedQuartile.isEmpty {
            if let metricIndex {
                row.yearlyMetrics.remove(at: metricIndex)
            }
        } else if let metricIndex {
            row.yearlyMetrics[metricIndex].value = trimmedValue
            row.yearlyMetrics[metricIndex].quartile = trimmedQuartile
        } else {
            row.yearlyMetrics.append(JournalYearMetric(year: year, value: trimmedValue, quartile: trimmedQuartile))
        }

        row.yearlyMetrics.sort { $0.year > $1.year }
        draft.rankingRows[rowIndex] = row
    }

    private func syncImpactFactorFields() {
        func jifValue(for year: Int) -> String {
            draft.preferredMetric(for: [.clarivateScieJIF, .clarivateEsciJIF], publicationYear: year)?.value ?? ""
        }
        draft.jif21 = jifValue(for: 2021)
        draft.jif22 = jifValue(for: 2022)
        draft.jif23 = jifValue(for: 2023)
        draft.jif24 = jifValue(for: 2024)
        draft.categories = draft.categories
            .compactMap(mergedJournalFilterCategory)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        draft.category = draft.categories.first ?? ""
        draft.rankingRows.sort { ($0.kind.rawValue, $0.category ?? "") < ($1.kind.rawValue, $1.category ?? "") }
        draft.normalize()
    }
}

private func normalizedJournalISSNInput(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleaned = trimmed
        .uppercased()
        .replacingOccurrences(of: "[^0-9X]", with: "", options: .regularExpression)
    guard cleaned.count == 8 else {
        return trimmed
    }
    return "\(cleaned.prefix(4))-\(cleaned.suffix(4))"
}

private struct RankingMetricEditorField: View {
    let text: Binding<String>
    let kind: JournalRankingKind
    let backgroundColor: Color

    var body: some View {
        CommitFormattingTextField(
            placeholder: "Värde",
            text: text,
            formatter: formattedText,
            showsRenewedSurface: false,
            isBordered: false,
            focusRingType: .none,
            font: .systemFont(ofSize: 13, weight: .semibold),
            visualState: visualState,
            liveVisualState: { liveVisualState(for: $0) }
        )
        .frame(minHeight: 18)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(width: 82)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(visualState == .normal ? AppPalette.border : visualState.stroke, lineWidth: visualState.isInvalid ? 1.4 : 1)
        )
        .help(visualState.helpText ?? "")
    }

    private var visualState: AppFieldVisualState {
        liveVisualState(for: text.wrappedValue)
    }

    private func liveVisualState(for raw: String) -> AppFieldVisualState {
        switch kind {
        case .norwegianList:
            return .normal
        case .clarivateScieJIF, .clarivateScieJCI, .clarivateEsciJIF, .clarivateEsciJCI, .scimagoSJR:
            return AppFieldValidators.optionalNumeric(raw, language: .swedish).state
        }
    }

    private func formattedText(_ raw: String) -> String {
        switch kind {
        case .norwegianList:
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        case .clarivateScieJIF, .clarivateScieJCI, .clarivateEsciJIF, .clarivateEsciJCI, .scimagoSJR:
            guard let value = Double(raw.replacingOccurrences(of: ",", with: ".")) else { return raw }
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 1
            return formatter.string(from: NSNumber(value: value)) ?? raw
        }
    }
}



private enum PublicationJournalStatisticsOutcome: String, CaseIterable, Identifiable {
    case accepted
    case rejected
    case waiting

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .accepted:
            return AppPalette.vividGreen
        case .rejected:
            return AppPalette.vividRed
        case .waiting:
            return AppPalette.vividYellow
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .accepted:
            return language.text("Accepted", "Accepterade")
        case .rejected:
            return language.text("Rejected", "Refuserade")
        case .waiting:
            return language.text("Pending", "Väntar svar")
        }
    }
}

private struct PublicationJournalStatisticsArticleRow: Identifiable {
    let id: String
    let outcome: PublicationJournalStatisticsOutcome
}

private struct PublicationJournalStatisticsView: View {
    @ObservedObject var store: GrantDataStore
    let journal: PublicationJournal
    let language: AppLanguage

    private var rows: [PublicationJournalStatisticsArticleRow] {
        // "Alla kopplingar via id": the publications that point to the journal.
        store.linkedJournalEntries(forJournalID: journal.id)
            .compactMap { entry in
                guard let outcome = publicationJournalStatisticsOutcome(for: entry.status) else { return nil }
                return PublicationJournalStatisticsArticleRow(
                    id: entry.id,
                    outcome: outcome
                )
            }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(journal.name.nonEmpty ?? language.text("Journal", "Tidskrift"))
                        .appTypography(.sectionTitle)
                        .foregroundStyle(AppPalette.appText)
                    Text(language.text("Submission outcomes and ranking development", "Utfall för inskick och rankingutveckling"))
                        .appTypography(.secondary)
                        .foregroundStyle(.secondary)
                }

                PublicationJournalStatisticsCard(
                    rows: rows,
                    language: language
                )

                PublicationJournalRankingChartCard(
                    series: publicationJournalRankingSeries(for: journal),
                    language: language
                )
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(AppPalette.detailPanelSurface)
    }
}

private struct PublicationJournalStatisticsCard: View {
    let rows: [PublicationJournalStatisticsArticleRow]
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.text("Submission outcomes", "Utfall för inskick"))
                .appTypography(.panelTitle)
                .foregroundStyle(AppPalette.appText)

            if rows.isEmpty {
                Text(language.text("No accepted, rejected or pending submissions found for this journal.", "Inga accepterade, refuserade eller väntande inskick hittades för tidskriften."))
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
            } else {
                PublicationJournalStatisticsOutcomeBar(rows: rows, language: language)
            }
        }
        .modifier(AppStatisticCardModifier())
    }
}

private struct PublicationJournalStatisticsOutcomeBar: View {
    let rows: [PublicationJournalStatisticsArticleRow]
    let language: AppLanguage

    private var segments: [(outcome: PublicationJournalStatisticsOutcome, count: Int)] {
        PublicationJournalStatisticsOutcome.allCases.map { outcome in
            (outcome, rows.filter { $0.outcome == outcome }.count)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let widths = segmentWidths(totalWidth: max(proxy.size.width, 1))
            let contentWidth = max(proxy.size.width, widths.reduce(0, +))
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.element.outcome.id) { index, segment in
                        VStack(spacing: 2) {
                            Text(segment.outcome.title(language: language))
                                .appTypography(.tableHeader)
                            Text("\(segment.count)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                        .foregroundStyle(AppPalette.semanticOnColor)
                        .frame(width: widths[index], height: 58)
                        .background(
                            LinearGradient(
                                colors: [
                                    segment.outcome.color.opacity(0.96),
                                    segment.outcome.color.opacity(0.72),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(alignment: .trailing) {
                            if index < segments.count - 1 {
                                Rectangle()
                                    .fill(AppPalette.border.opacity(0.65))
                                    .frame(width: 1)
                            }
                        }
                    }
                }
                .frame(width: contentWidth, alignment: .leading)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(AppPalette.border, lineWidth: 1)
            )
        }
        .frame(height: 58)
    }

    private func segmentWidths(totalWidth: CGFloat) -> [CGFloat] {
        let minimumWidth: CGFloat = 112
        let minimumTotal = minimumWidth * CGFloat(segments.count)
        let totalCount = segments.map(\.count).reduce(0, +)
        guard totalCount > 0 else {
            return Array(repeating: max(totalWidth / CGFloat(segments.count), minimumWidth), count: segments.count)
        }
        guard totalWidth > minimumTotal else {
            return segments.map { segment in
                max(totalWidth * CGFloat(segment.count) / CGFloat(totalCount), minimumWidth)
            }
        }

        let distributableWidth = totalWidth - minimumTotal
        return segments.map { segment in
            minimumWidth + distributableWidth * CGFloat(segment.count) / CGFloat(totalCount)
        }
    }
}

struct PublicationJournalRankingPoint: Identifiable, Equatable {
    let year: Int
    let value: Double

    var id: Int { year }
}

struct PublicationJournalRankingSeries: Identifiable, Equatable {
    enum Metric: String, CaseIterable {
        case jci = "JCI"
        case jif = "JIF"
        case sjr = "SJR"
        case norwegian = "Norwegian"
    }

    let metric: Metric
    let points: [PublicationJournalRankingPoint]

    var id: Metric { metric }

    func title(language: AppLanguage) -> String {
        switch metric {
        case .norwegian:
            return language.text("Norwegian list", "Norska listan")
        default:
            return metric.rawValue
        }
    }

    var color: Color {
        switch metric {
        case .jci: return AppPalette.chartBlue
        case .jif: return AppPalette.chartGreen
        case .sjr: return AppPalette.chartYellow
        case .norwegian: return AppPalette.chartRed
        }
    }
}

func publicationJournalRankingSeries(for journal: PublicationJournal) -> [PublicationJournalRankingSeries] {
    func numericValue(_ raw: String) -> Double? {
        let normalized = raw
            .replacingOccurrences(of: " (uncertain)", with: "")
            .replacingOccurrences(of: " (osäkert)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    func points(for kinds: [JournalRankingKind]) -> [PublicationJournalRankingPoint] {
        var valuesByYear: [Int: Double] = [:]
        for kind in kinds {
            let matchingRows = journal.rankingRows.filter { $0.kind == kind }
            for row in matchingRows {
                for metric in row.yearlyMetrics {
                    guard let value = numericValue(metric.value) else { continue }
                    valuesByYear[metric.year] = max(valuesByYear[metric.year] ?? value, value)
                }
            }
            if !valuesByYear.isEmpty {
                break
            }
        }
        return valuesByYear
            .map { PublicationJournalRankingPoint(year: $0.key, value: $0.value) }
            .sorted { $0.year < $1.year }
    }

    var jifPoints = points(for: [.clarivateScieJIF, .clarivateEsciJIF])
    if jifPoints.isEmpty {
        jifPoints = [
            (2021, journal.jif21),
            (2022, journal.jif22),
            (2023, journal.jif23),
            (2024, journal.jif24),
        ].compactMap { year, raw in
            numericValue(raw).map { PublicationJournalRankingPoint(year: year, value: $0) }
        }
    }

    // Label for a single latest value: the newest year that actually has
    // registered values, not a stored fixed year.
    let metricYear = journal.latestRegisteredMetricsYear
    var jciPoints = points(for: [.clarivateScieJCI, .clarivateEsciJCI])
    if jciPoints.isEmpty, let year = metricYear, let value = numericValue(journal.latestJCI) {
        jciPoints = [PublicationJournalRankingPoint(year: year, value: value)]
    }
    var sjrPoints = points(for: [.scimagoSJR])
    if sjrPoints.isEmpty, let year = metricYear, let value = numericValue(journal.latestSJR) {
        sjrPoints = [PublicationJournalRankingPoint(year: year, value: value)]
    }
    var norwegianPoints = points(for: [.norwegianList])
    if norwegianPoints.isEmpty, let year = metricYear, let value = numericValue(journal.norwegianLevel) {
        norwegianPoints = [PublicationJournalRankingPoint(year: year, value: value)]
    }

    return [
        PublicationJournalRankingSeries(metric: .jci, points: jciPoints),
        PublicationJournalRankingSeries(metric: .jif, points: jifPoints),
        PublicationJournalRankingSeries(metric: .sjr, points: sjrPoints),
        PublicationJournalRankingSeries(metric: .norwegian, points: norwegianPoints),
    ].filter { !$0.points.isEmpty }
}

private struct PublicationJournalRankingChartCard: View {
    let series: [PublicationJournalRankingSeries]
    let language: AppLanguage

    private var years: [Int] {
        Array(Set(series.flatMap { $0.points.map(\.year) })).sorted()
    }

    private var maximumValue: Double {
        let maximum = series.flatMap(\.points).map(\.value).max() ?? 0
        guard maximum > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(maximum)))
        return max(magnitude, ceil(maximum / magnitude) * magnitude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.text("Ranking by year", "Ranking per år"))
                .appTypography(.panelTitle)
                .foregroundStyle(AppPalette.appText)

            if series.isEmpty || years.isEmpty {
                Text(language.text(
                    "No year-based JCI, JIF, SJR or Norwegian list data are registered.",
                    "Ingen årsbaserad data för JCI, JIF, SJR eller norska listan är registrerad."
                ))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 14) {
                    ForEach(series) { item in
                        HStack(spacing: 5) {
                            Capsule()
                                .fill(item.color)
                                .frame(width: 18, height: 3)
                            Text(item.title(language: language))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppPalette.appText)
                        }
                    }
                }

                PublicationJournalRankingLineChart(
                    series: series,
                    years: years,
                    maximumValue: maximumValue,
                    language: language
                )
                .frame(height: 300)
            }
        }
        .modifier(AppStatisticCardModifier())
    }
}

private struct PublicationJournalRankingLineChart: View {
    let series: [PublicationJournalRankingSeries]
    let years: [Int]
    let maximumValue: Double
    let language: AppLanguage

    private let leftInset: CGFloat = 46
    private let rightInset: CGFloat = 18
    private let topInset: CGFloat = 18
    private let bottomInset: CGFloat = 38
    private let gridLineCount = 4

    var body: some View {
        GeometryReader { proxy in
            let plotWidth = max(1, proxy.size.width - leftInset - rightInset)
            let plotHeight = max(1, proxy.size.height - topInset - bottomInset)

            ZStack(alignment: .topLeading) {
                ForEach(0...gridLineCount, id: \.self) { index in
                    let fraction = CGFloat(index) / CGFloat(gridLineCount)
                    let y = topInset + plotHeight * fraction
                    Path { path in
                        path.move(to: CGPoint(x: leftInset, y: y))
                        path.addLine(to: CGPoint(x: leftInset + plotWidth, y: y))
                    }
                    .stroke(AppPalette.subtleBorder.opacity(index == gridLineCount ? 0.9 : 0.55), lineWidth: 1)

                    Text(formattedAxisValue(maximumValue * Double(gridLineCount - index) / Double(gridLineCount)))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: leftInset - 7, alignment: .trailing)
                        .position(x: (leftInset - 7) / 2, y: y)
                }

                ForEach(Array(years.enumerated()), id: \.element) { index, year in
                    let x = xPosition(index: index, plotWidth: plotWidth)
                    Path { path in
                        path.move(to: CGPoint(x: x, y: topInset))
                        path.addLine(to: CGPoint(x: x, y: topInset + plotHeight))
                    }
                    .stroke(AppPalette.subtleBorder.opacity(0.28), lineWidth: 1)

                    Text("\(year)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: x, y: topInset + plotHeight + 18)
                }

                ForEach(series) { item in
                    let visiblePoints = item.points.filter { point in years.contains(point.year) }
                    Path { path in
                        for (index, point) in visiblePoints.enumerated() {
                            let location = pointPosition(
                                point,
                                plotWidth: plotWidth,
                                plotHeight: plotHeight
                            )
                            if index == 0 {
                                path.move(to: location)
                            } else {
                                path.addLine(to: location)
                            }
                        }
                    }
                    .stroke(item.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    ForEach(visiblePoints) { point in
                        let location = pointPosition(point, plotWidth: plotWidth, plotHeight: plotHeight)
                        Circle()
                            .fill(item.color)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(AppPalette.cardSurface, lineWidth: 1.5))
                            .position(location)
                            .help("\(item.title(language: language)) · \(point.year): \(formattedAxisValue(point.value))")
                    }
                }
            }
        }
        .padding(.top, 2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppPalette.secondaryCardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppPalette.subtleBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func xPosition(index: Int, plotWidth: CGFloat) -> CGFloat {
        guard years.count > 1 else { return leftInset + plotWidth / 2 }
        return leftInset + plotWidth * CGFloat(index) / CGFloat(years.count - 1)
    }

    private func pointPosition(
        _ point: PublicationJournalRankingPoint,
        plotWidth: CGFloat,
        plotHeight: CGFloat
    ) -> CGPoint {
        let yearIndex = years.firstIndex(of: point.year) ?? 0
        let x = xPosition(index: yearIndex, plotWidth: plotWidth)
        let normalizedValue = min(max(point.value / maximumValue, 0), 1)
        let y = topInset + plotHeight * CGFloat(1 - normalizedValue)
        return CGPoint(x: x, y: y)
    }

    private func formattedAxisValue(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.decimalSeparator = language == .english ? "." : ","
        formatter.maximumFractionDigits = value < 10 ? 1 : 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private func publicationJournalStatisticsOutcome(for status: PublicationStatus) -> PublicationJournalStatisticsOutcome? {
    switch status {
    case .accepted, .published:
        return .accepted
    case .rejected:
        return .rejected
    case .submitted:
        return .waiting
    case .planned, .inPreparation:
        return nil
    }
}
