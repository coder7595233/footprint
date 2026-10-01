import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum StatisticsDashboardTab: String, CaseIterable, Identifiable {
    case grants
    case publications
    case teaching
    case activities

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .grants:
            return language.text("Grants", "Anslag")
        case .publications:
            return language.text("Publications", "Publikationer")
        case .teaching:
            return language.text("Teaching", "Undervisning")
        case .activities:
            return language.text("Activities", "Aktiviteter")
        }
    }

    var systemImage: String {
        switch self {
        case .grants: return "banknote"
        case .publications: return "doc.text"
        case .teaching: return "person.2"
        case .activities: return "calendar"
        }
    }
}

private enum StatisticsActivityMetric: String, CaseIterable, Identifiable {
    case shareOfActivities
    case shareOfAllTime
    case shareOfFullTimeEmployment
    case hours

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .shareOfActivities: return language.text("Share of activities", "Andel av aktiviteter")
        case .shareOfAllTime: return language.text("Share of all time", "Andel av all tid")
        case .shareOfFullTimeEmployment: return language.text("Share of full-time employment", "Andel av heltidstjänst")
        case .hours: return language.text("Hours", "Timmar")
        }
    }

    var systemImage: String {
        switch self {
        case .shareOfActivities: return "chart.pie"
        case .shareOfAllTime: return "clock"
        case .shareOfFullTimeEmployment: return "briefcase"
        case .hours: return "clock.badge.checkmark"
        }
    }

    var isShare: Bool {
        self != .hours
    }
}

func statisticsTeachingYearSliderRange(currentYear: Int, dataYears: Set<Int>) -> ClosedRange<Int> {
    let lowerBound = currentYear - 1
    let upperBound = max(lowerBound, currentYear, dataYears.max() ?? currentYear)
    return lowerBound...upperBound
}

func statisticsLinkedProjectHoursByYear(
    _ hoursByYear: [Int: [String: Double]],
    excludingUnlinkedKey unlinkedKey: String
) -> [Int: Double] {
    hoursByYear.mapValues { values in
        values.reduce(0) { total, item in
            item.key == unlinkedKey ? total : total + item.value
        }
    }
}

func statisticsTeachingVisibleThroughYear(
    currentYear: Int,
    dataYears: Set<Int>,
    selectedYear: Int?
) -> Int {
    let range = statisticsTeachingYearSliderRange(currentYear: currentYear, dataYears: dataYears)
    let requestedYear = selectedYear ?? currentYear
    return min(max(requestedYear, range.lowerBound), range.upperBound)
}

func statisticsTeachingVisibleYears(from dataYears: Set<Int>, through upperYear: Int) -> [String] {
    let visibleDataYears = dataYears.filter { $0 <= upperYear }
    guard let firstYear = visibleDataYears.min() else { return [] }
    return Array(firstYear...upperYear).map(String.init)
}

/// One amount group (Settings > Beloppsgrupper) in the grant statistics:
/// how many applications fall in it, how many of them were granted and the
/// granted amount (in SEK).
struct GrantAmountBucketSummary: Equatable {
    let bucket: ApplicationAmountBucket
    var applicationCount: Int
    var grantedCount: Int
    var grantedAmount: Double
}

/// Counts the applications per amount group, in the order below, between,
/// above. `grantedAmount` is only added up for granted applications.
func grantAmountBucketSummaries(
    applications: [GrantApplication],
    bucket: (GrantApplication) -> ApplicationAmountBucket,
    isGranted: (GrantApplication) -> Bool,
    grantedAmount: (GrantApplication) -> Double
) -> [GrantAmountBucketSummary] {
    var summaries = ApplicationAmountBucket.allCases.map { bucketCase in
        GrantAmountBucketSummary(bucket: bucketCase, applicationCount: 0, grantedCount: 0, grantedAmount: 0)
    }
    for application in applications {
        let applicationBucket = bucket(application)
        guard let index = summaries.firstIndex(where: { $0.bucket == applicationBucket }) else { continue }
        summaries[index].applicationCount += 1
        if isGranted(application) {
            summaries[index].grantedCount += 1
            summaries[index].grantedAmount += grantedAmount(application)
        }
    }
    return summaries
}

struct StatisticsView: View {
    @ObservedObject var store: GrantDataStore
    let isActive: Bool
    @State private var drilldownSelection: StatisticsDrilldownSelection?
    @State private var selectedStatisticsTab: StatisticsDashboardTab = .grants
    @State private var showOnlyLeadGrantApplications = true
    @State private var teachingVisibleThroughYear: Int?
    @State private var activityMetric: StatisticsActivityMetric = .shareOfActivities
    @State private var activityStatisticsCache = StatisticsActivityStatisticsCache()
    @State private var showStatisticsContent = false
    @State private var statisticsContentRevealTask: DispatchWorkItem?

    private let compactStatsValueColumnWidth: CGFloat = 50
    private let amountBucketValueColumnWidth: CGFloat = 100
    private let statisticsCardHorizontalPadding: CGFloat = 8

    init(store: GrantDataStore, isActive: Bool, initialTab: StatisticsDashboardTab = .grants) {
        self.store = store
        self.isActive = isActive
        // Developer convenience: FOOTPRINT_STATISTICS_TAB preselects a
        // statistics area, used by headless screenshot verification.
        if let override = ProcessInfo.processInfo.environment["FOOTPRINT_STATISTICS_TAB"],
           let tab = StatisticsDashboardTab(rawValue: override) {
            _selectedStatisticsTab = State(initialValue: tab)
        } else {
            _selectedStatisticsTab = State(initialValue: initialTab)
        }
    }

    private var currentCalendarYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private var teachingDataYears: Set<Int> {
        Set(teachingHoursByYear.keys)
    }

    private var teachingYearSliderRange: ClosedRange<Int> {
        statisticsTeachingYearSliderRange(
            currentYear: currentCalendarYear,
            dataYears: teachingDataYears
        )
    }

    private var effectiveTeachingVisibleThroughYear: Int {
        statisticsTeachingVisibleThroughYear(
            currentYear: currentCalendarYear,
            dataYears: teachingDataYears,
            selectedYear: teachingVisibleThroughYear
        )
    }

    private var teachingVisibleThroughYearSliderBinding: Binding<Double> {
        Binding(
            get: { Double(effectiveTeachingVisibleThroughYear) },
            set: { newValue in
                teachingVisibleThroughYear = statisticsTeachingVisibleThroughYear(
                    currentYear: currentCalendarYear,
                    dataYears: teachingDataYears,
                    selectedYear: Int(newValue.rounded())
                )
            }
        )
    }

    @ViewBuilder
    private func statisticsAreaNavigation(language: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(StatisticsDashboardTab.allCases) { tab in
                RenewedRailTabButton(
                    title: tab.title(language: language),
                    symbolName: tab.systemImage,
                    isSelected: selectedStatisticsTab == tab
                ) {
                    selectedStatisticsTab = tab
                }

                if tab == .activities, selectedStatisticsTab == .activities {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(StatisticsActivityMetric.allCases) { metric in
                            activityMetricNavigationButton(metric, language: language)
                        }
                    }
                    .padding(.leading, 18)
                    .padding(.top, 2)
                    .padding(.bottom, 2)
                }

            }
        }
    }

    private func activityMetricNavigationButton(
        _ metric: StatisticsActivityMetric,
        language: AppLanguage
    ) -> some View {
        let isSelected = activityMetric == metric
        return Button {
            activityMetric = metric
        } label: {
            HStack(spacing: 8) {
                Image(systemName: metric.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16, height: 16)
                Text(metric.title(language: language))
                    .font(appFont(.body).weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(isSelected ? AppPalette.mainMenuSelectionText : AppPalette.appText.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? AppPalette.mainMenuSelectionSurface.opacity(0.78) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(metric.title(language: language))
    }

    private func requiredStatisticsCardWidth(firstColumnWidth: CGFloat, entryCount: Int) -> CGFloat {
        let valueColumns = CGFloat(entryCount + 1) * compactStatsValueColumnWidth
        return firstColumnWidth + valueColumns + statisticsCardHorizontalPadding
    }

    var body: some View {
        Group {
            if isActive {
                activeStatisticsContent
                    .onAppear {
                        store.appendPerformanceDiagnostic("statistics-view-active")
                        scheduleStatisticsContentReveal(reason: "appear")
                    }
            } else {
                Color.clear
                    .background(Color.clear)
            }
        }
        .onChange(of: isActive) { _, active in
            store.appendPerformanceDiagnostic(
                String(
                    format: "statistics-active-changed active=%@",
                    active ? "yes" : "no"
                )
            )
            if active {
                scheduleStatisticsContentReveal(reason: "became-active")
            } else {
                statisticsContentRevealTask?.cancel()
                statisticsContentRevealTask = nil
                showStatisticsContent = false
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var activeStatisticsContent: some View {
        let language = store.language
        let minimumStatisticsColumnWidth: CGFloat = 320

        return PersistentSplitView(
            defaultsKey: "StatisticsWorkspaceSplit",
            defaultFraction: 0.23,
            sidebarMinimumWidth: 250,
            sidebarMaximumWidth: 360,
            detailMinimumWidth: 520
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AppPanelHeadingText(text: language.text("Statistics area", "Statistikområde"))
                    statisticsAreaNavigation(language: language)

                    if selectedStatisticsTab == .grants {
                        Toggle(language.text("Only where I am main applicant", "Endast där jag är huvudsökande"), isOn: $showOnlyLeadGrantApplications)
                            .appCheckboxStyle()
                    }
                    if selectedStatisticsTab == .teaching {
                        teachingVisibleThroughYearControl(language: language)
                    }
                }
                .padding(16)
            }
        } detail: {
            GeometryReader { proxy in
                let availableContentWidth = max(0, proxy.size.width - 28)
                ScrollView(.vertical) {
                    Group {
                        if showStatisticsContent {
                        let statisticsGridWidth = statisticsContentWidth(
                            for: selectedStatisticsTab,
                            availableContentWidth: availableContentWidth,
                            minimumStatisticsColumnWidth: minimumStatisticsColumnWidth
                        )
                        HStack(alignment: .top, spacing: 14) {
                            ScrollView(.horizontal) {
                                VStack(alignment: .leading, spacing: 26) {
                                    StatisticsPageHeader(
                                        kicker: language.text("Statistics", "Statistik") + " · " + selectedStatisticsTab.title(language: language),
                                        title: selectedStatisticsTab.title(language: language)
                                    )
                                    statisticsTabContent(
                                        language: language,
                                        minimumStatisticsColumnWidth: minimumStatisticsColumnWidth
                                    )
                                }
                                .frame(minWidth: statisticsGridWidth, alignment: .topLeading)
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .background(
                                TabPerformanceReporter(isActive: isActive) {
                                    store.appendPerformanceDiagnostic("statistics-content-visible tab=\(selectedStatisticsTab.rawValue)")
                                }
                            )

                            if let drilldown = statisticsDrilldownContent(language: language) {
                                StatisticsDrilldownCard(
                                    language: language,
                                    title: drilldown.title,
                                    subtitle: drilldown.subtitle,
                                    items: drilldown.items,
                                    onItemTap: { item in
                                        if let source = item.calendarSource {
                                            store.openCalendarLinkedEvent(source: source)
                                            return
                                        }
                                        guard let destination = item.destination, let recordID = item.recordID else { return }
                                        store.route = AppRoute(recordID: recordID, destination: destination)
                                    }
                                )
                                .frame(width: 360, alignment: .topLeading)
                            }
                        }
                        } else {
                            statisticsDeferredPlaceholder(language: language)
                        }
                    }
                    .padding(14)
                    .frame(minWidth: proxy.size.width, alignment: .topLeading)
                }
            }
        }
        .background(Color.clear)
        .onChange(of: selectedStatisticsTab) { _, _ in
            drilldownSelection = nil
            scheduleStatisticsContentReveal(reason: "tab-change")
        }
        .onChange(of: showOnlyLeadGrantApplications) { _, _ in
            drilldownSelection = nil
            scheduleStatisticsContentReveal(reason: "lead-filter-change")
        }
        .onChange(of: teachingVisibleThroughYear) { _, _ in
            drilldownSelection = nil
            scheduleStatisticsContentReveal(reason: "teaching-year-change")
        }
    }

    private func scheduleStatisticsContentReveal(reason: String) {
        statisticsContentRevealTask?.cancel()
        showStatisticsContent = false
        guard isActive else { return }
        let task = DispatchWorkItem {
            let startedAt = CFAbsoluteTimeGetCurrent()
            showStatisticsContent = true
            statisticsContentRevealTask = nil
            store.appendPerformanceDiagnostic(
                String(
                    format: "statistics-content-reveal reason=%@ total_ms=%.2f",
                    reason,
                    (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
                )
            )
        }
        statisticsContentRevealTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: task)
    }

    private func statisticsDeferredPlaceholder(language: AppLanguage) -> some View {
        HStack(spacing: 8) {
            AppLoadingLabel(
                language: language,
                title: language.text("Loading statistics…", "Laddar statistik…")
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppPalette.cardSurface))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppPalette.subtleBorder, lineWidth: 1))
    }

    private func teachingVisibleThroughYearControl(language: AppLanguage) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(language.text("Show through", "Visa till och med"))
                .font(appFont(.secondary).weight(.medium))
                .foregroundStyle(AppPalette.appText.opacity(0.86))
            Slider(
                value: teachingVisibleThroughYearSliderBinding,
                in: Double(teachingYearSliderRange.lowerBound)...Double(teachingYearSliderRange.upperBound),
                step: 1
            )
            .frame(minWidth: 120, maxWidth: .infinity)
            .layoutPriority(1)
            Text(String(effectiveTeachingVisibleThroughYear))
                .font(appFont(.secondary).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(AppPalette.appText)
                .frame(width: 44, alignment: .center)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppPalette.fieldSurface)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(AppPalette.subtleBorder, lineWidth: 1)
                )
        }
    }

    private func statisticsContentWidth(
        for tab: StatisticsDashboardTab,
        availableContentWidth: CGFloat,
        minimumStatisticsColumnWidth: CGFloat
    ) -> CGFloat {
        let width = switch tab {
        case .grants:
            grantStatisticsColumnWidth(minimumStatisticsColumnWidth: minimumStatisticsColumnWidth)
        case .publications:
            publicationStatisticsColumnWidth(minimumStatisticsColumnWidth: minimumStatisticsColumnWidth)
        case .teaching:
            teachingStatisticsColumnWidth(minimumStatisticsColumnWidth: minimumStatisticsColumnWidth)
        case .activities:
            activityStatisticsColumnWidth(minimumStatisticsColumnWidth: minimumStatisticsColumnWidth)
        }
        return max(availableContentWidth, width)
    }

    private func grantStatisticsColumnWidth(minimumStatisticsColumnWidth: CGFloat) -> CGFloat {
        max(
            minimumStatisticsColumnWidth,
            max(
                max(
                    requiredStatisticsCardWidth(firstColumnWidth: 150, entryCount: grantCountChartEntries.count),
                    requiredStatisticsCardWidth(firstColumnWidth: 150, entryCount: grantAmountChartEntries.count)
                ),
                150 + CGFloat(ApplicationAmountBucket.allCases.count + 1) * amountBucketValueColumnWidth + statisticsCardHorizontalPadding
            )
        )
    }

    private func publicationStatisticsColumnWidth(minimumStatisticsColumnWidth: CGFloat) -> CGFloat {
        max(
            minimumStatisticsColumnWidth,
            publicationStatisticsLeftColumnWidth(minimumStatisticsColumnWidth: minimumStatisticsColumnWidth)
                + 14
                + publicationStatisticsRightColumnWidth(minimumStatisticsColumnWidth: minimumStatisticsColumnWidth)
        )
    }

    private func publicationStatisticsLeftColumnWidth(minimumStatisticsColumnWidth: CGFloat) -> CGFloat {
        max(
            minimumStatisticsColumnWidth,
            max(
                requiredStatisticsCardWidth(firstColumnWidth: 145, entryCount: publicationCountChartEntries.count),
                requiredStatisticsCardWidth(firstColumnWidth: 145, entryCount: publicationIndependenceChartEntries.count)
            )
        )
    }

    private func publicationStatisticsRightColumnWidth(minimumStatisticsColumnWidth: CGFloat) -> CGFloat {
        max(
            minimumStatisticsColumnWidth,
            max(
                requiredStatisticsCardWidth(firstColumnWidth: 145, entryCount: citationChartEntries.count),
                requiredStatisticsCardWidth(firstColumnWidth: 145, entryCount: publicationYears.count)
            )
        )
    }

    private func teachingStatisticsColumnWidth(minimumStatisticsColumnWidth: CGFloat) -> CGFloat {
        max(
            minimumStatisticsColumnWidth,
            requiredStatisticsCardWidth(firstColumnWidth: 145, entryCount: teachingHoursChartEntries.count)
        )
    }

    private func activityStatisticsColumnWidth(minimumStatisticsColumnWidth: CGFloat) -> CGFloat {
        max(
            minimumStatisticsColumnWidth,
            requiredStatisticsCardWidth(firstColumnWidth: 175, entryCount: activityYears.count)
        )
    }

    @ViewBuilder
    private func statisticsTabContent(
        language: AppLanguage,
        minimumStatisticsColumnWidth: CGFloat
    ) -> some View {
        switch selectedStatisticsTab {
        case .grants:
            VStack(alignment: .leading, spacing: 14) {
                StatisticsStackedChartTableCard(
                    title: language.text("Number of grants", "Antal anslag"),
                    entries: grantCountChartEntries,
                    rows: grantCountTableRows(language: language),
                    totalColumnTitle: language.text("Total", "Totalt"),
                    firstColumnWidth: 150,
                    valueColumnWidth: compactStatsValueColumnWidth,
                    legend: [
                        (ApplicationOutcome.granted.heading(language), .green),
                        (ApplicationOutcome.awaitingDecision.heading(language), .yellow),
                        (ApplicationOutcome.declined.heading(language), .red),
                    ],
                    onCellTap: { rowKey, columnIndex in
                        drilldownSelection = StatisticsDrilldownSelection(kind: .grantCount, rowKey: rowKey, columnIndex: columnIndex)
                    }
                )

                StatisticsStackedChartTableCard(
                    title: language.text("Grant sums (MSEK)", "Summa anslag (mkr)"),
                    entries: grantAmountChartEntries,
                    rows: grantAmountTableRows(language: language),
                    totalColumnTitle: language.text("Total", "Totalt"),
                    firstColumnWidth: 150,
                    valueColumnWidth: compactStatsValueColumnWidth,
                    legend: [
                        (ApplicationOutcome.granted.heading(language), .green),
                        (ApplicationOutcome.awaitingDecision.heading(language), .yellow),
                        (ApplicationOutcome.declined.heading(language), .red),
                    ],
                    onCellTap: { rowKey, columnIndex in
                        drilldownSelection = StatisticsDrilldownSelection(kind: .grantAmount, rowKey: rowKey, columnIndex: columnIndex)
                    }
                )

                StatisticsHeatTableCard(
                    title: language.text("Amount groups", "Beloppsgrupper"),
                    columnTitles: amountBucketColumnTitles(language: language),
                    rows: grantAmountBucketTableRows(language: language),
                    firstColumnWidth: 150,
                    valueColumnWidth: amountBucketValueColumnWidth
                )
            }
            .frame(
                width: grantStatisticsColumnWidth(minimumStatisticsColumnWidth: minimumStatisticsColumnWidth),
                alignment: .topLeading
            )
        case .publications:
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    StatisticsStackedChartTableCard(
                        title: language.text("Published publications", "Publicerade publikationer"),
                        entries: publicationCountChartEntries,
                        rows: publicationTypeTableRows(language: language),
                        totalColumnTitle: language.text("Total", "Totalt"),
                        firstColumnWidth: 145,
                        valueColumnWidth: compactStatsValueColumnWidth,
                        legend: [
                            (language.text("Original", "Original"), .green),
                            (language.text("Review articles", "Översiktsartiklar"), .yellow),
                            (language.text("Others", "Övrigt"), .red),
                        ],
                        onCellTap: { rowKey, columnIndex in
                            drilldownSelection = StatisticsDrilldownSelection(kind: .publicationType, rowKey: rowKey, columnIndex: columnIndex)
                        }
                    )

                    StatisticsStackedChartTableCard(
                        title: language.text("Independent vs dependent publications", "Oberoende respektive beroende publikationer"),
                        entries: publicationIndependenceChartEntries,
                        rows: publicationIndependenceTableRows(language: language),
                        totalColumnTitle: language.text("Total", "Totalt"),
                        firstColumnWidth: 145,
                        valueColumnWidth: compactStatsValueColumnWidth,
                        legend: [
                            (language.text("Independent", "Oberoende"), .green),
                            (language.text("Dependent", "Beroende"), .yellow),
                        ],
                        onCellTap: { rowKey, columnIndex in
                            drilldownSelection = StatisticsDrilldownSelection(kind: .publicationIndependence, rowKey: rowKey, columnIndex: columnIndex)
                        }
                    )
                }
                .frame(
                    width: publicationStatisticsLeftColumnWidth(minimumStatisticsColumnWidth: minimumStatisticsColumnWidth),
                    alignment: .topLeading
                )

                VStack(alignment: .leading, spacing: 14) {
                    StatisticsStackedChartTableCard(
                        title: language.text("Citations", "Citeringar"),
                        entries: citationChartEntries,
                        rows: citationTableRows(language: language),
                        totalColumnTitle: language.text("Total", "Totalt"),
                        firstColumnWidth: 145,
                        valueColumnWidth: compactStatsValueColumnWidth,
                        legend: [
                            (language.text("External citations", "Externa citeringar"), .green),
                            (language.text("Self-citations", "Självciteringar"), .orange),
                        ],
                        onCellTap: { rowKey, columnIndex in
                            drilldownSelection = StatisticsDrilldownSelection(kind: .citation, rowKey: rowKey, columnIndex: columnIndex)
                        }
                    )

                    StatisticsHeatTableCard(
                        title: language.text("Journal impact factor (JIF) by publication year", "Journal impact factor (JIF) per publikationsår"),
                        columnTitles: publicationYears + [language.text("Total", "Totalt")],
                        rows: publicationJIFTableRows(language: language),
                        firstColumnWidth: 145,
                        valueColumnWidth: compactStatsValueColumnWidth,
                        showsChart: true
                    )
                }
                .frame(
                    width: publicationStatisticsRightColumnWidth(minimumStatisticsColumnWidth: minimumStatisticsColumnWidth),
                    alignment: .topLeading
                )
            }
            .frame(
                width: publicationStatisticsColumnWidth(minimumStatisticsColumnWidth: minimumStatisticsColumnWidth),
                alignment: .topLeading
            )
        case .teaching:
            VStack(alignment: .leading, spacing: 14) {
                StatisticsStackedChartTableCard(
                    title: language.text("Teaching hours", "Undervisningstimmar"),
                    entries: teachingHoursChartEntries,
                    rows: teachingHoursTableRows(language: language),
                    totalColumnTitle: language.text("Total", "Totalt"),
                    firstColumnWidth: 145,
                    valueColumnWidth: compactStatsValueColumnWidth,
                    legend: [
                        (language.text("Doctoral level", "Doktoral nivå"), .green),
                        (language.text("Clinical teaching", "Klinisk undervisning"), .red),
                        (language.text("Other teaching", "Övrig undervisning"), .yellow),
                    ],
                    futureDividerColumnIndex: teachingFutureDividerIndex,
                    futureDividerColor: AppPalette.todayMarker,
                    futureDividerWidth: 3,
                    onCellTap: { rowKey, columnIndex in
                        drilldownSelection = StatisticsDrilldownSelection(kind: .teachingHours, rowKey: rowKey, columnIndex: columnIndex)
                    }
                )
            }
            .frame(
                width: teachingStatisticsColumnWidth(minimumStatisticsColumnWidth: minimumStatisticsColumnWidth),
                alignment: .topLeading
            )
        case .activities:
            VStack(alignment: .leading, spacing: 14) {
                activityStatisticsCard(
                    title: language.text("Activity types", "Aktivitetstyper") + " — " + activityMetric.title(language: language).lowercased(),
                    entries: activityTypeChartEntries,
                    rows: activityTypeTableRows(language: language),
                    language: language,
                    drilldownKind: .activityType,
                    chartSegmentRowKeys: activityTypeKeys
                )
                activityStatisticsCard(
                    title: language.text("Projects", "Projekt") + " — " + activityMetric.title(language: language).lowercased(),
                    entries: activityProjectChartEntries,
                    rows: activityProjectTableRows(language: language),
                    language: language,
                    drilldownKind: .activityProject,
                    chartSegmentRowKeys: activityProjectKeys
                )
            }
            .frame(
                width: activityStatisticsColumnWidth(minimumStatisticsColumnWidth: minimumStatisticsColumnWidth),
                alignment: .topLeading
            )
        }
    }

    private var activityStatisticsSnapshot: StatisticsActivityStatisticsSnapshot {
        activityStatisticsCache.snapshot(for: store)
    }

    private var activityStatisticsRecords: [StatisticsActivityRecord] {
        activityStatisticsSnapshot.records
    }

    private var activityYears: [Int] {
        activityStatisticsSnapshot.years
    }

    private var activityTypeKeys: [String] {
        activityStatisticsSnapshot.activityTypeKeys
    }

    private var activityProjectKeys: [String] {
        let keys = activityStatisticsSnapshot.activityProjectKeys
        guard activityMetric == .shareOfActivities else { return keys }
        return keys.filter { $0 != activityUnlinkedProjectName }
    }

    private var activityUnlinkedProjectName: String {
        store.language.text("Unlinked", "Ej kopplat till projekt")
    }

    private var activityLinkedProjectHoursByYear: [Int: Double] {
        statisticsLinkedProjectHoursByYear(
            activityStatisticsSnapshot.activityProjectHoursByYear,
            excludingUnlinkedKey: activityUnlinkedProjectName
        )
    }

    private func activityStatisticsCard(
        title: String,
        entries: [StatisticsStackedEntry],
        rows: [StatisticsHeatRow],
        language: AppLanguage,
        drilldownKind: StatisticsTableKind,
        chartSegmentRowKeys: [String]
    ) -> some View {
        StatisticsStackedChartTableCard(
            title: title,
            entries: entries,
            rows: rows,
            totalColumnTitle: language.text("Total", "Totalt"),
            firstColumnWidth: 175,
            valueColumnWidth: compactStatsValueColumnWidth,
            legend: [],
            showsChartTotals: activityMetric != .shareOfActivities,
            onCellTap: { rowKey, columnIndex in
                drilldownSelection = StatisticsDrilldownSelection(kind: drilldownKind, rowKey: rowKey, columnIndex: columnIndex)
            },
            onChartSegmentTap: { columnIndex, segmentIndex in
                guard chartSegmentRowKeys.indices.contains(segmentIndex) else { return }
                drilldownSelection = StatisticsDrilldownSelection(kind: drilldownKind, rowKey: chartSegmentRowKeys[segmentIndex], columnIndex: columnIndex)
            }
        )
    }

    private func statisticsCalendarActivityTint(_ category: String) -> StatisticsTint {
        let hex = store.calendarMeetingCategoryColorHex(named: category) ?? "4C72B0"
        return StatisticsTint(hexString: hex)
    }

    private func activityTypeTint(for key: String) -> StatisticsTint {
        activityStatisticsSnapshot.activityTypeTints[key] ?? .blue
    }

    private func activityProjectTint(for key: String) -> StatisticsTint {
        activityProjectTints[key] ?? .blue
    }

    private var activityProjectTints: [String: StatisticsTint] {
        activityStatisticsSnapshot.activityProjectTints
    }

    private func activityChartEntries(
        keys: [String],
        hoursByYear: [Int: [String: Double]],
        shareDenominatorHoursByYear: [Int: Double]? = nil,
        tint: (String) -> StatisticsTint
    ) -> [StatisticsStackedEntry] {
        activityYears.map { year in
            let totalHours = activityStatisticsSnapshot.totalHoursByYear[year] ?? 0
            let metricDenominatorHours = shareDenominatorHoursByYear?[year] ?? totalHours
            let segments = keys.map { category in
                let value = hoursByYear[year]?[category] ?? 0
                let chartValue = activityMetricValue(hours: value, year: year, totalActivityHours: metricDenominatorHours)
                return StatisticsStackedSegment(value: chartValue, tint: tint(category))
            }
            let totalValue = activityMetricValue(
                hours: shareDenominatorHoursByYear == nil ? totalHours : metricDenominatorHours,
                year: year,
                totalActivityHours: metricDenominatorHours
            )
            let shareTotal = shareDenominatorHoursByYear != nil && metricDenominatorHours <= 0
                ? 0
                : max(100, totalValue)
            return StatisticsStackedEntry(
                label: String(year),
                total: activityMetric.isShare ? shareTotal : totalHours,
                totalText: activityMetric == .shareOfActivities
                    ? ""
                    : (activityMetric.isShare ? activityPercentString(totalValue) : activityHoursString(totalHours)),
                segments: segments
            )
        }
    }

    private var activityTypeChartEntries: [StatisticsStackedEntry] {
        activityChartEntries(keys: activityTypeKeys, hoursByYear: activityStatisticsSnapshot.activityTypeHoursByYear, tint: activityTypeTint)
    }

    private var activityProjectChartEntries: [StatisticsStackedEntry] {
        activityChartEntries(
            keys: activityProjectKeys,
            hoursByYear: activityStatisticsSnapshot.activityProjectHoursByYear,
            shareDenominatorHoursByYear: activityMetric == .shareOfActivities ? activityLinkedProjectHoursByYear : nil,
            tint: activityProjectTint
        )
    }

    private func activityTableRows(
        keys: [String],
        hoursByYear: [Int: [String: Double]],
        shareDenominatorHoursByYear: [Int: Double]? = nil,
        language: AppLanguage,
        tint: (String) -> StatisticsTint
    ) -> [StatisticsHeatRow] {
        let valuesByKey = keys.map { category in
            activityYears.map { year in
                let totalHours = activityStatisticsSnapshot.totalHoursByYear[year] ?? 0
                let metricDenominatorHours = shareDenominatorHoursByYear?[year] ?? totalHours
                let value = hoursByYear[year]?[category] ?? 0
                return activityMetricValue(hours: value, year: year, totalActivityHours: metricDenominatorHours)
            }
        }
        let totals = activityYears.map { year in
            let totalHours = activityStatisticsSnapshot.totalHoursByYear[year] ?? 0
            let metricDenominatorHours = shareDenominatorHoursByYear?[year] ?? totalHours
            return activityMetricValue(
                hours: shareDenominatorHoursByYear == nil ? totalHours : metricDenominatorHours,
                year: year,
                totalActivityHours: metricDenominatorHours
            )
        }
        let formatter: (Double) -> String = activityMetric.isShare
            ? activityPercentString
            : { activityHoursString($0) }
        let categoryRows = keys.enumerated().map { index, category in
            let categoryHours = activityYears.reduce(0) { partialResult, year in
                partialResult + (hoursByYear[year]?[category] ?? 0)
            }
            return StatisticsHeatRow(
                key: category,
                title: category,
                values: valuesByKey[index] + [
                    activityAggregateMetricValue(
                        hours: categoryHours,
                        shareDenominatorHoursByYear: shareDenominatorHoursByYear
                    )
                ],
                formatter: formatter,
                palette: tint(category)
            )
        }
        guard activityMetric != .shareOfActivities else {
            return categoryRows
        }
        return categoryRows + [
            StatisticsHeatRow(
                key: "total",
                title: language.text("Total", "Totalt"),
                values: totals + [activityAggregateMetricValue(hours: activityStatisticsSnapshot.totalHoursByYear.values.reduce(0, +))],
                formatter: formatter,
                palette: .blue,
                dividerAbove: true
            )
        ]
    }

    private func activityTypeTableRows(language: AppLanguage) -> [StatisticsHeatRow] {
        activityTableRows(keys: activityTypeKeys, hoursByYear: activityStatisticsSnapshot.activityTypeHoursByYear, language: language, tint: activityTypeTint)
    }

    private func activityProjectTableRows(language: AppLanguage) -> [StatisticsHeatRow] {
        activityTableRows(
            keys: activityProjectKeys,
            hoursByYear: activityStatisticsSnapshot.activityProjectHoursByYear,
            shareDenominatorHoursByYear: activityMetric == .shareOfActivities ? activityLinkedProjectHoursByYear : nil,
            language: language,
            tint: activityProjectTint
        )
    }

    private func activityHoursString(_ value: Double) -> String {
        Self.groupedIntegerString(value.rounded())
    }

    private func activityPercentString(_ value: Double) -> String {
        "\(Int(value.rounded())) %"
    }

    private func activityMetricValue(hours: Double, year: Int, totalActivityHours: Double) -> Double {
        guard activityMetric.isShare else { return hours }
        let denominator = activityMetricDenominator(for: year, totalActivityHours: totalActivityHours)
        return denominator > 0 ? hours / denominator * 100 : 0
    }

    private func activityAggregateMetricValue(
        hours: Double,
        shareDenominatorHoursByYear: [Int: Double]? = nil
    ) -> Double {
        guard activityMetric.isShare else { return hours }
        let denominator = activityYears.reduce(0) { partialResult, year in
            let yearHours = activityStatisticsSnapshot.totalHoursByYear[year] ?? 0
            let metricDenominatorHours = shareDenominatorHoursByYear?[year] ?? yearHours
            return partialResult + activityMetricDenominator(for: year, totalActivityHours: metricDenominatorHours)
        }
        return denominator > 0 ? hours / denominator * 100 : 0
    }

    private func activityMetricDenominator(for year: Int, totalActivityHours: Double) -> Double {
        switch activityMetric {
        case .shareOfActivities:
            return totalActivityHours
        case .shareOfAllTime:
            return 365 * 24
        case .shareOfFullTimeEmployment:
            return activityFullTimeHours(in: year)
        case .hours:
            return 1
        }
    }

    private func activityFullTimeHours(in year: Int) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "sv_SE")
        guard let firstDay = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let dayRange = calendar.range(of: .day, in: .year, for: firstDay) else {
            return 0
        }
        let redDays = Set(
            HolidayCalendarBuilder.holidays(for: [.sweden], year: year, calendar: calendar)
                .map { calendar.startOfDay(for: $0.date) }
        )
        let workingDays = dayRange.reduce(into: 0) { count, day in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) else { return }
            let normalizedDate = calendar.startOfDay(for: date)
            if !calendar.isDateInWeekend(normalizedDate), !redDays.contains(normalizedDate) {
                count += 1
            }
        }
        return Double(max(0, workingDays - 31) * 8)
    }

    private var grantYears: [String] {
        continuousStatisticsYears(from: Set(filteredGrantApplications.map(\.statsYear)))
    }

    private var filteredGrantApplications: [GrantApplication] {
        store.applications.filter {
            grantStatus(for: $0) != nil && (!showOnlyLeadGrantApplications || isCurrentUserFirstApplicant($0))
        }
    }

    private var publishedPublications: [PublicationRecord] {
        store.publications.filter {
            $0.isPublished && $0.isPeerReviewed
        }
    }

    private var publicationYears: [String] {
        continuousStatisticsYears(from: Set(publishedPublications.compactMap { $0.year.nonEmpty }))
    }

    private func grantCountTableRows(language: AppLanguage) -> [StatisticsHeatRow] {
        let waiting = grantYears.map { year in
            Double(filteredGrantApplications.filter { $0.statsYear == year && grantStatus(for: $0) == .waiting }.count)
        }
        let granted = grantYears.map { year in
            Double(filteredGrantApplications.filter { $0.statsYear == year && grantStatus(for: $0) == .granted }.count)
        }
        let rejected = grantYears.map { year in
            Double(filteredGrantApplications.filter { $0.statsYear == year && grantStatus(for: $0) == .rejected }.count)
        }
        let waitingTotal = waiting.reduce(0, +)
        let grantedTotal = granted.reduce(0, +)
        let rejectedTotal = rejected.reduce(0, +)
        let totals = zip(zip(waiting, granted), rejected).map { pair in
            pair.0.0 + pair.0.1 + pair.1
        }
        let grandTotal = totals.reduce(0, +)

        return [
            StatisticsHeatRow(key: "waiting", title: ApplicationOutcome.awaitingDecision.heading(language), values: waiting + [waitingTotal], formatter: { Self.groupedIntegerString($0) }, palette: .yellow),
            StatisticsHeatRow(key: "granted", title: ApplicationOutcome.granted.heading(language), values: granted + [grantedTotal], formatter: { Self.groupedIntegerString($0) }, palette: .green),
            StatisticsHeatRow(key: "rejected", title: ApplicationOutcome.declined.heading(language), values: rejected + [rejectedTotal], formatter: { Self.groupedIntegerString($0) }, palette: .red),
            StatisticsHeatRow(key: "total", title: language.text("Total", "Totalt"), values: totals + [grandTotal], formatter: { Self.groupedIntegerString($0) }, palette: .blue, dividerAbove: true),
        ]
    }

    private func publicationTypeTableRows(language: AppLanguage) -> [StatisticsHeatRow] {
        let originals = publicationYears.map { year in
            Double(publishedPublications.filter { $0.year == year && publicationTypeBucket(for: $0) == .original }.count)
        }
        let reviews = publicationYears.map { year in
            Double(publishedPublications.filter { $0.year == year && publicationTypeBucket(for: $0) == .review }.count)
        }
        let others = publicationYears.map { year in
            Double(publishedPublications.filter { $0.year == year && publicationTypeBucket(for: $0) == .other }.count)
        }
        let totals = zip(zip(originals, reviews), others).map { pair in
            pair.0.0 + pair.0.1 + pair.1
        }

        return [
            StatisticsHeatRow(key: "original", title: language.text("Original", "Original"), values: originals + [originals.reduce(0, +)], formatter: { Self.groupedIntegerString($0) }, palette: .green),
            StatisticsHeatRow(key: "review", title: language.text("Review articles", "Översiktsartiklar"), values: reviews + [reviews.reduce(0, +)], formatter: { Self.groupedIntegerString($0) }, palette: .yellow),
            StatisticsHeatRow(key: "other", title: language.text("Others", "Övrigt"), values: others + [others.reduce(0, +)], formatter: { Self.groupedIntegerString($0) }, palette: .red),
            StatisticsHeatRow(key: "total", title: language.text("Total", "Totalt"), values: totals + [totals.reduce(0, +)], formatter: { Self.groupedIntegerString($0) }, palette: .blue, dividerAbove: true),
        ]
    }

    private func publicationIndependenceTableRows(language: AppLanguage) -> [StatisticsHeatRow] {
        let independent = publicationYears.map { year in
            Double(publishedPublications.filter { $0.year == year && publicationIsIndependent($0) }.count)
        }
        let dependent = publicationYears.map { year in
            Double(publishedPublications.filter { $0.year == year && !publicationIsIndependent($0) }.count)
        }
        let totals = zip(independent, dependent).map(+)

        return [
            StatisticsHeatRow(key: "independent", title: language.text("Independent", "Oberoende"), values: independent + [independent.reduce(0, +)], formatter: { Self.groupedIntegerString($0) }, palette: .green),
            StatisticsHeatRow(key: "dependent", title: language.text("Dependent", "Beroende"), values: dependent + [dependent.reduce(0, +)], formatter: { Self.groupedIntegerString($0) }, palette: .yellow),
            StatisticsHeatRow(key: "total", title: language.text("Total", "Totalt"), values: totals + [totals.reduce(0, +)], formatter: { Self.groupedIntegerString($0) }, palette: .blue, dividerAbove: true),
        ]
    }

    private func publicationJIFTableRows(language: AppLanguage) -> [StatisticsHeatRow] {
        let yearlyValues = publicationYears.map { publicationJIFValues(for: $0) }
        let averages = yearlyValues.map { values -> Double in
            guard !values.isEmpty else { return 0 }
            return values.reduce(0, +) / Double(values.count)
        }
        let totals = yearlyValues.map { $0.reduce(0, +) }
        let allValues = yearlyValues.flatMap { $0 }
        let totalAverage = allValues.isEmpty ? 0 : allValues.reduce(0, +) / Double(allValues.count)
        let totalJIF = allValues.reduce(0, +)
        let emptyIndexes = Set(yearlyValues.enumerated().compactMap { index, values in
            values.isEmpty ? index : nil
        })
        let totalIndex = publicationYears.count
        let allEmptyIndexes = allValues.isEmpty ? emptyIndexes.union([totalIndex]) : emptyIndexes

        return [
            StatisticsHeatRow(
                key: "averageJIF",
                title: language.text("Average JIF", "Genomsnittligt JIF"),
                values: averages + [totalAverage],
                formatter: { groupedJIFString($0, language: language) },
                palette: .blue,
                emptyValueIndexes: allEmptyIndexes
            ),
            StatisticsHeatRow(
                key: "totalJIF",
                title: language.text("Total JIF", "Totalt JIF"),
                values: totals + [totalJIF],
                formatter: { groupedJIFString($0, language: language) },
                palette: .blue,
                emptyValueIndexes: allEmptyIndexes
            ),
        ]
    }

    private func publicationJIFValues(for year: String) -> [Double] {
        publishedPublications
            .filter { $0.year == year }
            .compactMap(publicationJIFValue)
    }

    private func publicationJIFValue(for publication: PublicationRecord) -> Double? {
        guard let journal = store.linkedJournal(of: publication),
              let metric = journal.preferredMetric(
                for: [.clarivateScieJIF, .clarivateEsciJIF],
                publicationYear: publication.yearValue
              ) else {
            return nil
        }
        return statisticsJIFNumericValue(metric.value)
    }

    private func statisticsJIFNumericValue(_ raw: String) -> Double? {
        Double(raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    private func grantAmountTableRows(language: AppLanguage) -> [StatisticsHeatRow] {
        let granted = grantYears.map { year in
            filteredGrantApplications
                .filter { $0.statsYear == year && grantStatus(for: $0) == .granted }
                .map(grantStatisticsAmount(for:))
                .reduce(0, +) / 1_000_000
        }
        let waiting = grantYears.map { year in
            filteredGrantApplications
                .filter { $0.statsYear == year && grantStatus(for: $0) == .waiting }
                .map(grantStatisticsAmount(for:))
                .reduce(0, +) / 1_000_000
        }
        let rejected = grantYears.map { year in
            filteredGrantApplications
                .filter { $0.statsYear == year && grantStatus(for: $0) == .rejected }
                .map(grantStatisticsAmount(for:))
                .reduce(0, +) / 1_000_000
        }
        let totals = zip(zip(granted, waiting), rejected).map { pair in
            pair.0.0 + pair.0.1 + pair.1
        }

        return [
            StatisticsHeatRow(key: "granted", title: ApplicationOutcome.granted.heading(language), values: granted + [granted.reduce(0, +)], formatter: { groupedDecimal2String($0, language: language) }, palette: .green),
            StatisticsHeatRow(key: "waiting", title: ApplicationOutcome.awaitingDecision.heading(language), values: waiting + [waiting.reduce(0, +)], formatter: { groupedDecimal2String($0, language: language) }, palette: .yellow),
            StatisticsHeatRow(key: "rejected", title: ApplicationOutcome.declined.heading(language), values: rejected + [rejected.reduce(0, +)], formatter: { groupedDecimal2String($0, language: language) }, palette: .red),
            StatisticsHeatRow(key: "total", title: language.text("Total", "Totalt"), values: totals + [totals.reduce(0, +)], formatter: { groupedDecimal2String($0, language: language) }, palette: .blue, dividerAbove: true),
        ]
    }

    /// Settings > Beloppsgrupper: per amount group the number of applications,
    /// how many were granted and the granted sum, with the same filter (own
    /// or all applications) and SEK conversion as the tables above.
    private func amountBucketColumnTitles(language: AppLanguage) -> [String] {
        let settings = store.workflowDefaultSettings
        let bucketTitles: [String] = ApplicationAmountBucket.allCases.map { settings.amountBucketLabel($0) }
        return bucketTitles + [language.text("Total", "Totalt")]
    }

    private func grantAmountBucketTableRows(language: AppLanguage) -> [StatisticsHeatRow] {
        let settings = store.workflowDefaultSettings
        let summaries = grantAmountBucketSummaries(
            applications: filteredGrantApplications,
            // Grouped on the amount in SEK, like the sums; a foreign amount
            // used to be grouped on its own number (€200 000 as < 250 k).
            bucket: { settings.amountBucket(for: store.grantStatisticsAmountInSEK(for: $0, amount: $0.preferredBudgetAmountValue)) },
            isGranted: { grantStatus(for: $0) == .granted },
            grantedAmount: { grantStatisticsAmount(for: $0) }
        )
        let applicationCounts = summaries.map { Double($0.applicationCount) }
        let grantedCounts = summaries.map { Double($0.grantedCount) }
        let grantedSums = summaries.map { $0.grantedAmount / 1_000_000 }
        return [
            StatisticsHeatRow(key: "applications", title: language.text("Applications", "Ansökningar"), values: applicationCounts + [applicationCounts.reduce(0, +)], formatter: { Self.groupedIntegerString($0) }, palette: .blue),
            StatisticsHeatRow(key: "granted", title: ApplicationOutcome.granted.heading(language), values: grantedCounts + [grantedCounts.reduce(0, +)], formatter: { Self.groupedIntegerString($0) }, palette: .green),
            StatisticsHeatRow(key: "grantedAmount", title: language.text("Granted (MSEK)", "Beviljat (mkr)"), values: grantedSums + [grantedSums.reduce(0, +)], formatter: { AmountFormatter.decimal($0, language: language) }, palette: .green),
        ]
    }

    private func citationTableRows(language: AppLanguage) -> [StatisticsHeatRow] {
        let externalValues = citationYears.map { year in
            Double(
                publishedPublications
                    .flatMap(\.citationYears)
                    .filter { $0.year == year }
                    .map(\.countValue)
                    .reduce(0, +)
            )
        }
        let selfCitationValues = citationYears.map { year in
            Double(
                publishedPublications
                    .flatMap(\.citationYears)
                    .filter { $0.year == year }
                    .map(\.selfCitationCountValue)
                    .reduce(0, +)
            )
        }
        let totalValues = zip(externalValues, selfCitationValues).map { $0 + $1 }
        return [
            StatisticsHeatRow(key: "externalCitations", title: language.text("External citations", "Externa citeringar"), values: externalValues + [externalValues.reduce(0, +)], formatter: { Self.groupedIntegerString($0) }, palette: .green),
            StatisticsHeatRow(key: "selfCitations", title: language.text("Self-citations", "Självciteringar"), values: selfCitationValues + [selfCitationValues.reduce(0, +)], formatter: { Self.groupedIntegerString($0) }, palette: .orange),
            StatisticsHeatRow(key: "total", title: language.text("Total citations", "Citeringar totalt"), values: totalValues + [totalValues.reduce(0, +)], formatter: { Self.groupedIntegerString($0) }, palette: .blue, dividerAbove: true)
        ]
    }

    private var grantCountChartEntries: [StatisticsStackedEntry] {
        grantYears.map { year in
            let granted = Double(filteredGrantApplications.filter { $0.statsYear == year && grantStatus(for: $0) == .granted }.count)
            let waiting = Double(filteredGrantApplications.filter { $0.statsYear == year && grantStatus(for: $0) == .waiting }.count)
            let rejected = Double(filteredGrantApplications.filter { $0.statsYear == year && grantStatus(for: $0) == .rejected }.count)
            let total = granted + waiting + rejected
            return StatisticsStackedEntry(
                label: year,
                total: total,
                totalText: Self.groupedIntegerString(total),
                segments: [
                    StatisticsStackedSegment(value: granted, tint: .green),
                    StatisticsStackedSegment(value: waiting, tint: .yellow),
                    StatisticsStackedSegment(value: rejected, tint: .red),
                ]
            )
        }
    }

    private var grantAmountChartEntries: [StatisticsStackedEntry] {
        grantYears.map { year in
            let granted = filteredGrantApplications
                .filter { $0.statsYear == year && grantStatus(for: $0) == .granted }
                .map(grantStatisticsAmount(for:))
                .reduce(0, +) / 1_000_000
            let waiting = filteredGrantApplications
                .filter { $0.statsYear == year && grantStatus(for: $0) == .waiting }
                .map(grantStatisticsAmount(for:))
                .reduce(0, +) / 1_000_000
            let rejected = filteredGrantApplications
                .filter { $0.statsYear == year && grantStatus(for: $0) == .rejected }
                .map(grantStatisticsAmount(for:))
                .reduce(0, +) / 1_000_000
            let total = granted + waiting + rejected
            return StatisticsStackedEntry(
                label: year,
                total: total,
                totalText: groupedDecimal2String(total, language: store.language),
                segments: [
                    StatisticsStackedSegment(value: granted, tint: .green),
                    StatisticsStackedSegment(value: waiting, tint: .yellow),
                    StatisticsStackedSegment(value: rejected, tint: .red),
                ]
            )
        }
    }

    private var publicationCountChartEntries: [StatisticsStackedEntry] {
        publicationYears.map { year in
            let originals = Double(publishedPublications.filter { $0.year == year && publicationTypeBucket(for: $0) == .original }.count)
            let reviews = Double(publishedPublications.filter { $0.year == year && publicationTypeBucket(for: $0) == .review }.count)
            let others = Double(publishedPublications.filter { $0.year == year && publicationTypeBucket(for: $0) == .other }.count)
            let total = originals + reviews + others
            return StatisticsStackedEntry(
                label: year,
                total: total,
                totalText: Self.groupedIntegerString(total),
                segments: [
                    StatisticsStackedSegment(value: originals, tint: .green),
                    StatisticsStackedSegment(value: reviews, tint: .yellow),
                    StatisticsStackedSegment(value: others, tint: .red),
                ]
            )
        }
    }

    private var publicationIndependenceChartEntries: [StatisticsStackedEntry] {
        publicationYears.map { year in
            let independent = Double(publishedPublications.filter { $0.year == year && publicationIsIndependent($0) }.count)
            let dependent = Double(publishedPublications.filter { $0.year == year && !publicationIsIndependent($0) }.count)
            let total = independent + dependent
            return StatisticsStackedEntry(
                label: year,
                total: total,
                totalText: Self.groupedIntegerString(total),
                segments: [
                    StatisticsStackedSegment(value: independent, tint: .green),
                    StatisticsStackedSegment(value: dependent, tint: .yellow),
                ]
            )
        }
    }

    private var citationYears: [String] {
        continuousStatisticsYears(
            from: Set(
                publishedPublications
                    .flatMap(\.citationYears)
                    .compactMap { $0.year.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.year.trimmingCharacters(in: .whitespacesAndNewlines) }
            )
        )
    }

    private var citationChartEntries: [StatisticsStackedEntry] {
        citationYears.map { year in
            let external = Double(
                publishedPublications
                    .flatMap(\.citationYears)
                    .filter { $0.year == year }
                    .map(\.countValue)
                    .reduce(0, +)
            )
            let selfCitations = Double(
                publishedPublications
                    .flatMap(\.citationYears)
                    .filter { $0.year == year }
                    .map(\.selfCitationCountValue)
                    .reduce(0, +)
            )
            let total = external + selfCitations
            return StatisticsStackedEntry(
                label: year,
                total: total,
                totalText: Self.groupedIntegerString(total),
                segments: [
                    StatisticsStackedSegment(value: external, tint: .green),
                    StatisticsStackedSegment(value: selfCitations, tint: .orange),
                ]
            )
        }
    }

    private var teachingHoursByYear: [Int: TeachingYearHours] {
        let contextsByID = Dictionary(firstWinsKeysWithValues: store.teachingCourses.map { ($0.id, $0) })
        let doctoralSourceAssignmentIDs = Set(store.doctoralCandidates.flatMap(\.sourceAssignmentIDs))
        var result: [Int: TeachingYearHours] = [:]

        for assignment in store.teachingAssignments {
            if doctoralSourceAssignmentIDs.contains(assignment.id) {
                continue
            }
            let context = assignment.contextID.flatMap { contextsByID[$0] }
            let isDoctoralReport =
                assignment.reportCategory == .doctoralCourseTeaching ||
                assignment.reportCategory == .doctoralPrincipalSupervision ||
                assignment.reportCategory == .doctoralAssistantSupervision
            let isDoctoral = isDoctoralReport || context?.level == .doctoral || context?.contextType == .doctoralEducation
            let isClinical = context?.contextType == .clinicalTeaching

            for period in assignment.periods where !period.isEmpty {
                guard let startDate = period.from.nonEmpty.flatMap(DateParsers.isoDay.date(from:)) else { continue }
                let endDate = period.to.nonEmpty.flatMap(DateParsers.isoDay.date(from:)) ?? Calendar.current.startOfDay(for: Date())
                let hoursPerTerm = GrantParsing.numericValue(from: period.hoursPerTerm) ?? 0
                guard hoursPerTerm > 0 else { continue }

                var terms = Set<String>()
                collectStatisticsTeachingTerms(from: startDate, to: endDate, into: &terms)
                let termsByYear = Dictionary(grouping: terms) { term in
                    Int(String(term.split(separator: "-").first ?? "")) ?? 0
                }

                for (year, yearTerms) in termsByYear where year > 0 {
                    let addedHours = Double(yearTerms.count) * hoursPerTerm
                    var existing = result[year] ?? TeachingYearHours()
                    if isDoctoral {
                        existing.doctoral += addedHours
                    } else if isClinical {
                        existing.clinical += addedHours
                    } else {
                        existing.other += addedHours
                    }
                    result[year] = existing
                }
            }
        }

        for candidate in store.doctoralCandidates {
            // Round 12: hours in proportion to days (one rule everywhere).
            for period in candidate.supervisionPeriods where !period.isEmpty {
                guard let hoursPerTerm = period.hoursPerTermValue else { continue }
                for share in DoctoralSupervisionPeriod.termShares(from: period.from, to: period.to, referenceDate: Date()) {
                    var existing = result[share.year] ?? TeachingYearHours()
                    existing.doctoral += share.fraction * hoursPerTerm
                    result[share.year] = existing
                }
            }
        }

        return result
    }

    private var teachingYears: [String] {
        statisticsTeachingVisibleYears(
            from: teachingDataYears,
            through: effectiveTeachingVisibleThroughYear
        )
    }

    private var teachingFutureDividerIndex: Int? {
        guard effectiveTeachingVisibleThroughYear > currentCalendarYear else { return nil }
        guard let currentIndex = teachingYears.firstIndex(of: String(currentCalendarYear)) else { return nil }
        let dividerIndex = currentIndex + 1
        return dividerIndex < teachingYears.count ? dividerIndex : nil
    }

    private var teachingHoursChartEntries: [StatisticsStackedEntry] {
        teachingYears.map { year in
            let yearNumber = Int(year) ?? 0
            let values = teachingHoursByYear[yearNumber] ?? TeachingYearHours()
            let total = values.doctoral + values.clinical + values.other
            return StatisticsStackedEntry(
                label: year,
                total: total,
                totalText: groupedHoursString(total, language: store.language),
                segments: [
                    StatisticsStackedSegment(value: values.doctoral, tint: .green),
                    StatisticsStackedSegment(value: values.clinical, tint: .red),
                    StatisticsStackedSegment(value: values.other, tint: .yellow),
                ]
            )
        }
    }

    private func teachingHoursTableRows(language: AppLanguage) -> [StatisticsHeatRow] {
        let doctoral = teachingYears.map { year in
            teachingHoursByYear[Int(year) ?? 0]?.doctoral ?? 0
        }
        let clinical = teachingYears.map { year in
            teachingHoursByYear[Int(year) ?? 0]?.clinical ?? 0
        }
        let other = teachingYears.map { year in
            teachingHoursByYear[Int(year) ?? 0]?.other ?? 0
        }
        let totals = zip(zip(doctoral, clinical), other).map { $0.0.0 + $0.0.1 + $0.1 }

        return [
            StatisticsHeatRow(key: "doctoral", title: language.text("Doctoral level", "Doktoral nivå"), values: doctoral + [doctoral.reduce(0, +)], formatter: { groupedHoursString($0, language: language) }, palette: .green),
            StatisticsHeatRow(key: "clinical", title: language.text("Clinical teaching", "Klinisk undervisning"), values: clinical + [clinical.reduce(0, +)], formatter: { groupedHoursString($0, language: language) }, palette: .red),
            StatisticsHeatRow(key: "other", title: language.text("Other teaching", "Övrig undervisning"), values: other + [other.reduce(0, +)], formatter: { groupedHoursString($0, language: language) }, palette: .yellow),
            StatisticsHeatRow(key: "total", title: language.text("Total", "Totalt"), values: totals + [totals.reduce(0, +)], formatter: { groupedHoursString($0, language: language) }, palette: .blue, dividerAbove: true),
        ]
    }

    private func statisticsDrilldownContent(language: AppLanguage) -> StatisticsDrilldownContent? {
        guard let selection = drilldownSelection else { return nil }
        switch selection.kind {
        case .grantCount, .grantAmount:
            return grantDrilldownContent(for: selection, language: language)
        case .publicationType, .publicationIndependence, .citation:
            return publicationDrilldownContent(for: selection, language: language)
        case .teachingHours:
            return teachingDrilldownContent(for: selection, language: language)
        case .activityType, .activityProject:
            return activityDrilldownContent(for: selection, language: language)
        }
    }

    private func activityDrilldownContent(for selection: StatisticsDrilldownSelection, language: AppLanguage) -> StatisticsDrilldownContent {
        let selectedYear = activityYears.indices.contains(selection.columnIndex) ? activityYears[selection.columnIndex] : nil
        let unlinked = language.text("Unlinked", "Ej kopplat till projekt")
        let matchingIDs = Set(activityStatisticsRecords.compactMap { record -> String? in
            guard selectedYear == nil || record.year == selectedYear else { return nil }
            switch selection.kind {
            case .activityType:
                return record.activityType == selection.rowKey ? record.meetingID : nil
            case .activityProject:
                return (record.projectName ?? unlinked) == selection.rowKey ? record.meetingID : nil
            default:
                return nil
            }
        })
        let meetings = store.calendarMeetingRecords
            .filter { matchingIDs.contains($0.id) }
            .sorted { $0.date == $1.date ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : $0.date < $1.date }
        let items = meetings.map { meeting in
            StatisticsDrilldownItem(
                id: meeting.id,
                title: meeting.title.nonEmpty ?? language.text("Untitled activity", "Namnlös aktivitet"),
                subtitle: [meeting.date, calendarMeetingCategoryDisplayName(meeting.meetingType, language: language)].filter { !$0.isEmpty }.joined(separator: " · "),
                detail: activityHoursString(Double(statisticsActivityDurationMinutes(meeting) ?? 0) / 60) + " h",
                recordID: nil,
                destination: nil,
                calendarSource: .meeting(meeting.id)
            )
        }
        let base = selection.kind == .activityType
            ? language.text("Activities", "Aktiviteter")
            : language.text("Project activities", "Projektaktiviteter")
        let yearLabel = selectedYear.map(String.init) ?? language.text("Total", "Totalt")
        return StatisticsDrilldownContent(
            title: drilldownTitle(base: base, rowLabel: selection.rowKey, yearLabel: yearLabel),
            subtitle: language.text("\(items.count) activities", "\(items.count) aktiviteter"),
            items: items
        )
    }

    private func grantDrilldownContent(for selection: StatisticsDrilldownSelection, language: AppLanguage) -> StatisticsDrilldownContent {
        let selectedYear = statisticsYear(for: selection.columnIndex, years: grantYears)
        let matching = filteredGrantApplications
            .filter { application in
                (selectedYear == nil || application.statsYear == selectedYear) && grantMatchesRowKey(application, rowKey: selection.rowKey)
            }
            // Organization first, then name. The old `a < b && c < d` was not a
            // valid ordering and could shuffle rows between redraws.
            .sorted {
                statisticsDrilldownOrganizationThenNameOrder(
                    lhsOrganization: $0.organization,
                    lhsName: $0.grantName,
                    rhsOrganization: $1.organization,
                    rhsName: $1.grantName
                )
            }

        let totalAmount = matching
            .map(grantStatisticsAmount(for:))
            .reduce(0, +)
        let totalAmountText = AmountFormatter.millions(totalAmount, language: store.language)

        let items = matching.map { application in
            StatisticsDrilldownItem(
                id: application.id,
                title: store.localizedGrantName(for: application, language: language).nonEmpty ?? language.text("Untitled grant", "Namnlöst anslag"),
                subtitle: [store.organizationLabel(for: application, language: language), application.statsYear, language.localizedStatus(application.resultLabel)].filter { !$0.isEmpty }.joined(separator: " · "),
                detail: AmountFormatter.millions(grantStatisticsAmount(for: application), language: store.language),
                recordID: application.id,
                destination: .applications
            )
        }

        return StatisticsDrilldownContent(
            title: drilldownTitle(
                base: selection.kind == .grantAmount ? language.text("Grant sums", "Summor anslag") : language.text("Grants", "Anslag"),
                rowLabel: grantRowLabel(for: selection.rowKey, language: language),
                yearLabel: drilldownYearLabel(for: selection.columnIndex, years: grantYears, language: language)
            ),
            subtitle: language.text("\(items.count) records · total \(totalAmountText)", "\(items.count) poster · summa \(totalAmountText)"),
            items: items
        )
    }

    private func publicationDrilldownContent(for selection: StatisticsDrilldownSelection, language: AppLanguage) -> StatisticsDrilldownContent {
        let drilldownYears = selection.kind == .citation ? citationYears : publicationYears
        let selectedYear = statisticsYear(for: selection.columnIndex, years: drilldownYears)
        let matching = publishedPublications
            .filter { publication in
                if selection.kind == .citation {
                    return publicationMatchesRowKey(publication, selection: selection)
                }
                return (selectedYear == nil || publication.year == selectedYear) && publicationMatchesRowKey(publication, selection: selection)
            }
            .sorted {
                if $0.year != $1.year {
                    return $0.year.localizedStandardCompare($1.year) == .orderedAscending
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }

        let items = matching.map { publication in
            let detail: String?
            if selection.kind == .citation {
                if let selectedYear {
                    let yearCount = publicationCitationCount(publication, rowKey: selection.rowKey, year: selectedYear)
                    detail = Self.groupedIntegerString(Double(yearCount))
                } else {
                    detail = Self.groupedIntegerString(Double(publicationCitationCount(publication, rowKey: selection.rowKey)))
                }
            } else {
                detail = publication.doi.nonEmpty ?? publication.pmid.nonEmpty
            }
            return StatisticsDrilldownItem(
                id: publication.id,
                title: publication.title.nonEmpty ?? language.text("Untitled", "Utan titel"),
                subtitle: [publication.journal.nonEmpty, store.projectLabel(for: publication, language: language).nonEmpty, publication.year.nonEmpty].compactMap { $0 }.joined(separator: " · "),
                detail: detail,
                recordID: publication.id,
                destination: .publications
            )
        }

        return StatisticsDrilldownContent(
            title: drilldownTitle(
                base: publicationDrilldownBaseTitle(for: selection.kind, language: language),
                rowLabel: publicationRowLabel(for: selection.rowKey, kind: selection.kind, language: language),
                yearLabel: drilldownYearLabel(for: selection.columnIndex, years: drilldownYears, language: language)
            ),
            subtitle: language.text("\(items.count) publications", "\(items.count) publikationer"),
            items: items
        )
    }

    private func teachingDrilldownContent(for selection: StatisticsDrilldownSelection, language: AppLanguage) -> StatisticsDrilldownContent {
        let selectedYear = statisticsYear(for: selection.columnIndex, years: teachingYears).flatMap(Int.init)
        let contextsByID = Dictionary(firstWinsKeysWithValues: store.teachingCourses.map { ($0.id, $0) })
        let doctoralSourceAssignmentIDs = Set(store.doctoralCandidates.flatMap(\.sourceAssignmentIDs))

        let assignmentItems = store.teachingAssignments.compactMap { assignment -> StatisticsDrilldownItem? in
            if doctoralSourceAssignmentIDs.contains(assignment.id) {
                return nil
            }
            let context = assignment.contextID.flatMap { contextsByID[$0] }
            let isDoctoralReport =
                assignment.reportCategory == .doctoralCourseTeaching ||
                assignment.reportCategory == .doctoralPrincipalSupervision ||
                assignment.reportCategory == .doctoralAssistantSupervision
            let isDoctoral = isDoctoralReport || context?.level == .doctoral || context?.contextType == .doctoralEducation
            let isClinical = context?.contextType == .clinicalTeaching
            guard teachingMatchesRowKey(isDoctoral: isDoctoral, isClinical: isClinical, rowKey: selection.rowKey) else { return nil }

            let hours = assignmentStatisticsHours(assignment, selectedYear: selectedYear)
            guard hours > 0 else { return nil }

            let title = [assignment.activityName.nonEmpty, context?.localizedName(language: language).nonEmpty]
                .compactMap { $0 }
                .joined(separator: ", ")
                .nonEmpty ?? language.text("Untitled assignment", "Namnlöst uppdrag")
            let roleText = assignment.roles.map { statisticsTeachingRoleName($0, language: language) }.joined(separator: ", ").nonEmpty
            let subtitle = [roleText, statisticsAssignmentYearLabel(assignment).nonEmpty].compactMap { $0 }.joined(separator: " · ")
            return StatisticsDrilldownItem(
                id: assignment.id,
                title: title,
                subtitle: subtitle,
                detail: groupedHoursString(hours, language: store.language) + " h",
                recordID: assignment.id,
                destination: .teaching
            )
        }
        let doctoralCandidateItems = store.doctoralCandidates.compactMap { candidate -> StatisticsDrilldownItem? in
            guard selection.rowKey == "doctoral" || selection.rowKey == "total" else { return nil }

            // Round 12: hours in proportion to days (one rule everywhere).
            let hours = candidate.supervisionPeriods.reduce(0.0) { partial, period in
                guard let hoursPerTerm = period.hoursPerTermValue else { return partial }
                let shares = DoctoralSupervisionPeriod.termShares(from: period.from, to: period.to, referenceDate: Date())
                    .filter { share in selectedYear.map { share.year == $0 } ?? visibleTeachingYearNumbers.contains(share.year) }
                return partial + shares.reduce(0) { $0 + $1.fraction * hoursPerTerm }
            }
            guard hours > 0 else { return nil }

            return StatisticsDrilldownItem(
                id: "doctoral-\(candidate.id)",
                title: candidate.candidateName.nonEmpty ?? language.text("Unnamed doctoral candidate", "Namnlös doktorand"),
                subtitle: language.text("Doctoral supervision", "Doktorandhandledning"),
                detail: groupedHoursString(hours, language: store.language) + " h",
                recordID: candidate.id,
                destination: nil
            )
        }
        let items = (assignmentItems + doctoralCandidateItems)
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        return StatisticsDrilldownContent(
            title: drilldownTitle(
                base: language.text("Teaching assignments", "Undervisningsuppdrag"),
                rowLabel: teachingRowLabel(for: selection.rowKey, language: language),
                yearLabel: drilldownYearLabel(for: selection.columnIndex, years: teachingYears, language: language)
            ),
            subtitle: language.text("\(items.count) assignments", "\(items.count) uppdrag"),
            items: items
        )
    }

    private func drilldownTitle(base: String, rowLabel: String, yearLabel: String) -> String {
        [base, rowLabel, yearLabel].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func drilldownYearLabel(for columnIndex: Int, years: [String], language: AppLanguage) -> String {
        statisticsYear(for: columnIndex, years: years) ?? language.text("Total", "Totalt")
    }

    private func statisticsYear(for columnIndex: Int, years: [String]) -> String? {
        years.indices.contains(columnIndex) ? years[columnIndex] : nil
    }

    private func grantMatchesRowKey(_ application: GrantApplication, rowKey: String) -> Bool {
        switch rowKey {
        case "waiting":
            return grantStatus(for: application) == .waiting
        case "granted":
            return grantStatus(for: application) == .granted
        case "rejected":
            return grantStatus(for: application) == .rejected
        case "total":
            return grantStatus(for: application) != nil
        default:
            return false
        }
    }

    private func publicationMatchesRowKey(_ publication: PublicationRecord, selection: StatisticsDrilldownSelection) -> Bool {
        switch selection.kind {
        case .publicationType:
            switch selection.rowKey {
            case "original":
                return publicationTypeBucket(for: publication) == .original
            case "review":
                return publicationTypeBucket(for: publication) == .review
            case "other":
                return publicationTypeBucket(for: publication) == .other
            case "total":
                return true
            default:
                return false
            }
        case .publicationIndependence:
            switch selection.rowKey {
            case "independent":
                return publicationIsIndependent(publication)
            case "dependent":
                return !publicationIsIndependent(publication)
            case "total":
                return true
            default:
                return false
            }
        case .citation:
            switch selection.rowKey {
            case "externalCitations":
                if let selectedYear = statisticsYear(for: selection.columnIndex, years: citationYears) {
                    return publication.citationYears.contains { $0.year == selectedYear && $0.countValue > 0 }
                }
                return publication.citationYears.contains { $0.countValue > 0 }
            case "selfCitations":
                if let selectedYear = statisticsYear(for: selection.columnIndex, years: citationYears) {
                    return publication.citationYears.contains { $0.year == selectedYear && $0.selfCitationCountValue > 0 }
                }
                return publication.citationYears.contains { $0.selfCitationCountValue > 0 }
            case "total":
                if let selectedYear = statisticsYear(for: selection.columnIndex, years: citationYears) {
                    return publication.citationYears.contains { $0.year == selectedYear && $0.totalCitationCountValue > 0 }
                }
                return publication.citationYears.contains { $0.totalCitationCountValue > 0 }
            default:
                return false
            }
        default:
            return false
        }
    }

    private func publicationCitationCount(_ publication: PublicationRecord, rowKey: String, year: String? = nil) -> Int {
        let entries = publication.citationYears.filter { entry in
            year == nil || entry.year == year
        }
        switch rowKey {
        case "externalCitations":
            return entries.map(\.countValue).reduce(0, +)
        case "selfCitations":
            return entries.map(\.selfCitationCountValue).reduce(0, +)
        case "total":
            return entries.map(\.totalCitationCountValue).reduce(0, +)
        default:
            return 0
        }
    }

    private func teachingMatchesRowKey(isDoctoral: Bool, isClinical: Bool, rowKey: String) -> Bool {
        switch rowKey {
        case "doctoral":
            return isDoctoral
        case "clinical":
            return !isDoctoral && isClinical
        case "other":
            return !isDoctoral && !isClinical
        case "total":
            return true
        default:
            return false
        }
    }

    private func assignmentStatisticsHours(_ assignment: TeachingAssignment, selectedYear: Int?) -> Double {
        assignment.periods.reduce(0) { partial, period in
            guard let startDate = period.from.nonEmpty.flatMap(DateParsers.isoDay.date(from:)) else { return partial }
            let today = Calendar.current.startOfDay(for: Date())
            let storedEnd = period.to.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
            // An open-ended period that has not started yet counts nothing
            // (its start and today used to be swapped, counting this term).
            if storedEnd == nil, startDate > today { return partial }
            let endDate = storedEnd ?? today
            let hoursPerTerm = GrantParsing.numericValue(from: period.hoursPerTerm) ?? 0
            guard hoursPerTerm > 0 else { return partial }
            var terms = Set<String>()
            collectStatisticsTeachingTerms(from: startDate, to: endDate, into: &terms)
            let count = terms.filter { term in
                guard let year = statisticsTeachingYear(from: term) else { return false }
                return selectedYear.map { year == $0 } ?? visibleTeachingYearNumbers.contains(year)
            }.count
            return partial + (Double(count) * hoursPerTerm)
        }
    }

    private var visibleTeachingYearNumbers: Set<Int> {
        Set(teachingYears.compactMap(Int.init))
    }

    private func statisticsTeachingYear(from term: String) -> Int? {
        Int(String(term.split(separator: "-").first ?? ""))
    }

    private func statisticsAssignmentYearLabel(_ assignment: TeachingAssignment) -> String {
        let filledPeriods = assignment.periods.filter { !$0.isEmpty }
        if assignment.periods.contains(where: { $0.from.nonEmpty != nil && $0.to.nonEmpty == nil }),
           let startYear = filledPeriods.first?.from.nonEmpty.flatMap(yearComponent(from:)) {
            return "\(startYear) – "
        }
        let firstFrom = filledPeriods.first?.from.nonEmpty
        let lastTo = filledPeriods.last?.to.nonEmpty
        let startYear = firstFrom.flatMap(yearComponent(from:))
        let endYear = lastTo.flatMap(yearComponent(from:))
        switch (startYear, endYear) {
        case let (start?, end?) where start != end:
            return "\(start)-\(end)"
        case let (start?, _):
            return "\(start)"
        case let (_, end?):
            return "\(end)"
        default:
            return ""
        }
    }

    private func yearComponent(from text: String) -> Int? {
        guard let date = DateParsers.isoDay.date(from: text) else { return nil }
        return Calendar.current.component(.year, from: date)
    }

    private func grantRowLabel(for rowKey: String, language: AppLanguage) -> String {
        switch rowKey {
        case "waiting": return ApplicationOutcome.awaitingDecision.heading(language)
        case "granted": return ApplicationOutcome.granted.heading(language)
        case "rejected": return ApplicationOutcome.declined.heading(language)
        case "total": return language.text("Total", "Totalt")
        default: return rowKey
        }
    }

    private func publicationRowLabel(for rowKey: String, kind: StatisticsTableKind, language: AppLanguage) -> String {
        switch kind {
        case .publicationType:
            switch rowKey {
            case "original": return language.text("Original", "Original")
            case "review": return language.text("Review articles", "Översiktsartiklar")
            case "other": return language.text("Others", "Övrigt")
            case "total": return language.text("Total", "Totalt")
            default: return rowKey
            }
        case .publicationIndependence:
            switch rowKey {
            case "independent": return language.text("Independent", "Oberoende")
            case "dependent": return language.text("Dependent", "Beroende")
            case "total": return language.text("Total", "Totalt")
            default: return rowKey
            }
        case .citation:
            switch rowKey {
            case "externalCitations": return language.text("External citations", "Externa citeringar")
            case "selfCitations": return language.text("Self-citations", "Självciteringar")
            case "total": return language.text("Total citations", "Citeringar totalt")
            default: return rowKey
            }
        default:
            return rowKey
        }
    }

    private func publicationDrilldownBaseTitle(for kind: StatisticsTableKind, language: AppLanguage) -> String {
        switch kind {
        case .publicationIndependence:
            return language.text("Publication independence", "Publikationers beroendegrad")
        case .citation:
            return language.text("Citations", "Citeringar")
        default:
            return language.text("Publications", "Publikationer")
        }
    }

    private func teachingRowLabel(for rowKey: String, language: AppLanguage) -> String {
        switch rowKey {
        case "doctoral": return language.text("Doctoral level", "Doktoral nivå")
        case "clinical": return language.text("Clinical teaching", "Klinisk undervisning")
        case "other": return language.text("Other teaching", "Övrig undervisning")
        case "total": return language.text("Total", "Totalt")
        default: return rowKey
        }
    }

    private func statisticsTeachingRoleName(_ role: TeachingAssignmentRole, language: AppLanguage) -> String {
        store.teachingRoleDisplayName(role, language: language)
    }

    private func grantStatus(for application: GrantApplication) -> GrantStatisticsStatus? {
        let status = application.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        switch status {
        case "Väntar svar":
            return .waiting
        case "Beviljat":
            return .granted
        case "Avslag":
            return .rejected
        default:
            return nil
        }
    }

    private func grantStatisticsAmount(for application: GrantApplication) -> Double {
        let amount: Double?
        switch grantStatus(for: application) {
        case .granted:
            amount = application.grantedAmountValue ?? application.appliedAmountValue ?? application.preferredBudgetAmountValue
        case .waiting, .rejected:
            amount = application.appliedAmountValue ?? application.preferredBudgetAmountValue
        case nil:
            return 0
        }
        return store.grantStatisticsAmountInSEK(for: application, amount: amount)
    }

    private func publicationTypeBucket(for publication: PublicationRecord) -> PublicationStatisticsBucket {
        let type = publication.publicationType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if type == "protocol" || type == "research letter" {
            return .other
        }
        if type.contains("review") {
            return .review
        }
        return .original
    }

    private func publicationIsIndependent(_ publication: PublicationRecord) -> Bool {
        let normalized = publication.independence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "yes" || normalized == "independent" || normalized == "oberoende"
    }

    private var currentStatisticsYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    private func isCurrentUserFirstApplicant(_ application: GrantApplication) -> Bool {
        // F13d: the main applicant by id link first, the written name as fallback.
        store.isCurrentUserFirstPerson(ids: application.coApplicantAuthorIDs, names: application.coApplicants)
    }

    private func continuousStatisticsYears(from rawYears: Set<String>) -> [String] {
        let years = rawYears.compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }.sorted()
        guard let firstYear = years.first else { return [] }
        let endYear = max(currentStatisticsYear, years.last ?? currentStatisticsYear)
        return Array(firstYear...endYear).map(String.init)
    }

    private func collectStatisticsTeachingTerms(from startDate: Date, to endDate: Date, into terms: inout Set<String>) {
        let start = min(startDate, endDate)
        let end = max(startDate, endDate)
        var cursor = start
        while cursor <= end {
            let year = Calendar.current.component(.year, from: cursor)
            let month = Calendar.current.component(.month, from: cursor)
            let half = month <= 6 ? 1 : 2
            terms.insert("\(year)-\(half)")
            guard let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = nextMonth
        }
        // Stepping a month at a time from the start day can pass the end
        // day's month (15 May + 2 months = 15 Jul > 10 Jul); the end's own
        // term always counts, as in the teaching merits and annual report.
        let endYear = Calendar.current.component(.year, from: end)
        let endHalf = Calendar.current.component(.month, from: end) <= 6 ? 1 : 2
        terms.insert("\(endYear)-\(endHalf)")
    }

    private static func integerString(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    private static func groupedIntegerString(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: Int(value.rounded()))) ?? integerString(value)
    }

    private func groupedDecimalString(_ value: Double, language: AppLanguage) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = language == .english ? "." : ","
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func groupedHoursString(_ value: Double, language: AppLanguage) -> String {
        value.rounded() == value ? Self.groupedIntegerString(value) : groupedDecimalString(value, language: language)
    }

    private func groupedDecimal2String(_ value: Double, language: AppLanguage) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = language == .english ? "." : ","
        let absoluteValue = abs(value)
        if absoluteValue >= 100 {
            formatter.maximumFractionDigits = 0
        } else if absoluteValue >= 10 {
            formatter.maximumFractionDigits = 1
        } else {
            formatter.maximumFractionDigits = 2
        }
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func groupedJIFString(_ value: Double, language: AppLanguage) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = language == .english ? "." : ","
        let oneDecimalRoundedValue = (abs(value) * 10).rounded() / 10
        let usesDecimal = oneDecimalRoundedValue < 10
        formatter.maximumFractionDigits = usesDecimal ? 1 : 0
        formatter.minimumFractionDigits = usesDecimal ? 1 : 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private enum GrantStatisticsStatus {
    case waiting
    case granted
    case rejected
}

private enum PublicationStatisticsBucket {
    case original
    case review
    case other
}

private struct TeachingYearHours {
    var doctoral: Double = 0
    var clinical: Double = 0
    var other: Double = 0
}

private struct StatisticsActivityRecord {
    let meetingID: String
    let year: Int
    let activityType: String
    let activityTint: StatisticsTint
    let projectName: String?
    let hours: Double
}

private struct StatisticsActivityStatisticsSnapshot {
    let records: [StatisticsActivityRecord]
    let years: [Int]
    let activityTypeKeys: [String]
    let activityProjectKeys: [String]
    let totalHoursByYear: [Int: Double]
    let activityTypeHoursByYear: [Int: [String: Double]]
    let activityProjectHoursByYear: [Int: [String: Double]]
    let activityTypeTints: [String: StatisticsTint]
    let activityProjectTints: [String: StatisticsTint]
}

@MainActor
private final class StatisticsActivityStatisticsCache {
    private var calendarContentGeneration: Int?
    private var language: AppLanguage?
    private var cachedSnapshot: StatisticsActivityStatisticsSnapshot?

    func snapshot(for store: GrantDataStore) -> StatisticsActivityStatisticsSnapshot {
        if calendarContentGeneration == store.calendarContentGeneration,
           language == store.language,
           let cachedSnapshot {
            return cachedSnapshot
        }

        let projectNames = Dictionary(firstWinsKeysWithValues: store.projects.map { ($0.id, $0.displayName(for: store.language)) })
        let unlinkedProjectName = store.language.text("Unlinked", "Ej kopplat till projekt")
        let unknownProjectName = store.language.text("Unknown project", "Okänt projekt")
        var records: [StatisticsActivityRecord] = []
        var totalHoursByYear: [Int: Double] = [:]
        var activityTypeHoursByYear: [Int: [String: Double]] = [:]
        var activityProjectHoursByYear: [Int: [String: Double]] = [:]
        var activityTypeTints: [String: StatisticsTint] = [:]

        func append(_ record: StatisticsActivityRecord) {
            records.append(record)
            totalHoursByYear[record.year, default: 0] += record.hours
            activityTypeHoursByYear[record.year, default: [:]][record.activityType, default: 0] += record.hours
            let projectName = record.projectName ?? unlinkedProjectName
            activityProjectHoursByYear[record.year, default: [:]][projectName, default: 0] += record.hours
            if activityTypeTints[record.activityType] == nil {
                activityTypeTints[record.activityType] = record.activityTint
            }
        }

        for meeting in store.calendarMeetingRecords {
            guard let date = DateParsers.isoDay.date(from: meeting.date),
                  let minutes = statisticsActivityDurationMinutes(meeting),
                  minutes > 0 else { continue }
            let year = Calendar.current.component(.year, from: date)
            let activityType = calendarMeetingCategoryDisplayName(meeting.meetingType, language: store.language)
            let activityTint = StatisticsTint(hexString: store.calendarMeetingCategoryColorHex(named: meeting.meetingType) ?? "4C72B0")
            let projectIDs = Array(Set((meeting.projectIDs + [meeting.projectID].compactMap { $0 }).compactMap(\.trimmedOrNil)))
            guard !projectIDs.isEmpty else {
                append(
                    StatisticsActivityRecord(
                        meetingID: meeting.id,
                        year: year,
                        activityType: activityType,
                        activityTint: activityTint,
                        projectName: nil,
                        hours: Double(minutes) / 60
                    )
                )
                continue
            }
            let hoursPerProject = Double(minutes) / 60 / Double(projectIDs.count)
            for projectID in projectIDs {
                append(
                    StatisticsActivityRecord(
                        meetingID: meeting.id,
                        year: year,
                        activityType: activityType,
                        activityTint: activityTint,
                        projectName: projectNames[projectID] ?? unknownProjectName,
                        hours: hoursPerProject
                    )
                )
            }
        }

        let activityTypeKeys = sortedKeys(for: activityTypeHoursByYear)
        let activityProjectKeys = sortedKeys(for: activityProjectHoursByYear)
        let activityProjectTints = projectTints(for: activityProjectHoursByYear, keys: activityProjectKeys)
        let snapshot = StatisticsActivityStatisticsSnapshot(
            records: records,
            years: totalHoursByYear.keys.sorted(),
            activityTypeKeys: activityTypeKeys,
            activityProjectKeys: activityProjectKeys,
            totalHoursByYear: totalHoursByYear,
            activityTypeHoursByYear: activityTypeHoursByYear,
            activityProjectHoursByYear: activityProjectHoursByYear,
            activityTypeTints: activityTypeTints,
            activityProjectTints: activityProjectTints
        )
        calendarContentGeneration = store.calendarContentGeneration
        language = store.language
        cachedSnapshot = snapshot
        return snapshot
    }

    private func sortedKeys(for hoursByYear: [Int: [String: Double]]) -> [String] {
        var hoursByKey: [String: Double] = [:]
        for values in hoursByYear.values {
            for (key, hours) in values {
                hoursByKey[key, default: 0] += hours
            }
        }
        return hoursByKey.keys.sorted { lhs, rhs in
            let lhsHours = hoursByKey[lhs] ?? 0
            let rhsHours = hoursByKey[rhs] ?? 0
            return lhsHours == rhsHours
                ? lhs.localizedStandardCompare(rhs) == .orderedAscending
                : lhsHours > rhsHours
        }
    }

    private func projectTints(for hoursByYear: [Int: [String: Double]], keys: [String]) -> [String: StatisticsTint] {
        let palette = [0x4C72B0, 0xDD8452, 0x55A868, 0xC44E52, 0x8172B2, 0x937860, 0xDA8BC3, 0x8C8C8C, 0xCCB974, 0x64B5CD]
        let ranges: [(key: String, first: Int, last: Int)] = keys.map { key in
            let years = hoursByYear.compactMap { year, values in values[key] == nil ? nil : year }
            return (key: key, first: years.min() ?? 0, last: years.max() ?? 0)
        }.sorted { lhs, rhs in
            lhs.first == rhs.first
                ? lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
                : lhs.first < rhs.first
        }
        var assignments: [String: StatisticsTint] = [:]
        var active: [(last: Int, paletteIndex: Int)] = []
        for range in ranges {
            active.removeAll { $0.last < range.first }
            let occupied = Set(active.map(\.paletteIndex))
            let index = palette.indices.first(where: { !occupied.contains($0) }) ?? (assignments.count % palette.count)
            assignments[range.key] = .custom(palette[index])
            active.append((range.last, index))
        }
        return assignments
    }
}

private func statisticsActivityDurationMinutes(_ meeting: CalendarMeetingRecord) -> Int? {
    let timeParts = { (raw: String) -> Int? in
        let parts = normalizedCalendarTimeInput(raw).split(separator: ":")
        guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
        return hours * 60 + minutes
    }
    guard let start = timeParts(meeting.startTime), let end = timeParts(meeting.endTime), end > start else { return nil }
    return end - start
}

private enum StatisticsTint: Equatable {
    case green
    case yellow
    case orange
    case red
    case blue
    case custom(Int)

    init(hexString: String) {
        let normalized = hexString.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        self = Int(normalized, radix: 16).map(StatisticsTint.custom) ?? .blue
    }

    // Round 16: the named tints are the shared status colours (green done,
    // yellow pending, orange warning, red negative), so charts follow dark
    // mode and the colours chosen in Settings. Blue is a category colour
    // (Settings' neutral colour), not a status.
    private var statusTone: AppStatusTone? {
        switch self {
        case .green: return .done
        case .yellow: return .pending
        case .orange: return .warning
        case .red: return .negative
        case .blue, .custom: return nil
        }
    }

    var bottomColor: Color {
        if let tone = statusTone {
            return Color(nsColor: NSColor(name: nil) { _ in
                let dark = AppAppearanceRegistry.usesDarkPalette()
                return AppPalette.statusFillNSColor(tone, dark: dark).withAlphaComponent(dark ? 0.34 : 0.55)
            })
        }
        let usesDarkPalette = AppAppearanceRegistry.usesDarkPalette()
        switch self {
        case let .custom(hex):
            return Color(hex: hex).opacity(usesDarkPalette ? 0.34 : 0.24)
        default:
            return Color(nsColor: NSColor(name: nil) { _ in
                let dark = AppAppearanceRegistry.usesDarkPalette()
                return AppAppearanceRegistry.semanticColor(.neutral, shaded: true, useDarkPalette: dark).withAlphaComponent(dark ? 0.34 : 1)
            })
        }
    }

    var topColor: Color {
        if let tone = statusTone {
            return AppPalette.statusFill(tone)
        }
        switch self {
        case let .custom(hex):
            return Color(hex: hex).opacity(0.82)
        default:
            return AppPalette.vividBlue
        }
    }

    func fillColor(opacity: Double = 1) -> Color {
        topColor.opacity(opacity)
    }
}

private struct StatisticsHeatRow {
    let key: String
    let title: String
    let values: [Double]
    let formatter: (Double) -> String
    var palette: StatisticsTint = .blue
    var cellPalettes: [StatisticsTint]? = nil
    var emptyValueIndexes: Set<Int> = []
    var dividerAbove: Bool = false

    /// A "Totalt" row is emphasized: bold figures, an ink rule above and a
    /// double rule below (editorial style).
    var isTotal: Bool { dividerAbove }
}

private struct StatisticsHeatCellData: Identifiable {
    let id: Int
    let value: Double
    let tint: StatisticsTint
}

/// Hairline under a data row; ink double rule under a "Totalt" row.
@ViewBuilder
private func statisticsRowBottomRule(isTotal: Bool) -> some View {
    if isTotal {
        VStack(spacing: 1) {
            Rectangle().fill(StatisticsEditorialStyle.ink).frame(height: 1)
            Rectangle().fill(StatisticsEditorialStyle.ink).frame(height: 1)
        }
    } else {
        Rectangle().fill(StatisticsEditorialStyle.hairline).frame(height: 1)
    }
}

/// Small-caps-styled gray column header (years, "Totalt").
private func statisticsColumnHeaderText(_ title: String) -> some View {
    Text(title)
        .font(appFont(.tableHeader))
        .tracking(0.4)
        .foregroundStyle(.secondary)
        .lineLimit(1)
}

private struct StatisticsStackedChartTableCard: View {
    let title: String
    let entries: [StatisticsStackedEntry]
    let rows: [StatisticsHeatRow]
    let totalColumnTitle: String
    let firstColumnWidth: CGFloat
    let valueColumnWidth: CGFloat
    let legend: [(String, StatisticsTint)]
    var showsChartTotals = true
    var futureDividerColumnIndex: Int? = nil
    var futureDividerColor: Color = .red
    var futureDividerWidth: CGFloat = 3
    var onCellTap: ((String, Int) -> Void)? = nil
    var onChartSegmentTap: ((Int, Int) -> Void)? = nil
    private let chartHeight: CGFloat = 292
    private let headerHeight: CGFloat = 34
    private let rowHeight: CGFloat = 28
    private let dividerHeight: CGFloat = 7

    private var scrollTrigger: String {
        entries.map(\.label).joined(separator: "|") + "-\(rows.count)"
    }

    private var maxTotal: Double {
        entries.map(\.total).max() ?? 0
    }

    private var futureDividerX: CGFloat? {
        guard let futureDividerColumnIndex, futureDividerColumnIndex > 0 else { return nil }
        return (CGFloat(futureDividerColumnIndex) * valueColumnWidth) - (futureDividerWidth / 2)
    }

    private var scrollableContentHeight: CGFloat {
        chartHeight + headerHeight + 4 + CGFloat(rows.count) * rowHeight + CGFloat(rows.filter { $0.dividerAbove }.count) * dividerHeight
    }

    private func maxValue(for palette: StatisticsTint) -> Double {
        rows
            .flatMap { row in
                row.values.enumerated().compactMap { index, value in
                    let cellPalette: StatisticsTint
                    if let rowCellPalettes = row.cellPalettes, rowCellPalettes.indices.contains(index) {
                        cellPalette = rowCellPalettes[index]
                    } else {
                        cellPalette = row.palette
                    }
                    return cellPalette == palette ? value : nil
                }
            }
            .max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppPalette.titleSpacing + 4) {
            StatisticsSerifTitleText(text: title)
            HStack(alignment: .top, spacing: 0) {
                fixedLabelColumn
                ScrollViewReader { reader in
                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 0) {
                                scrollableChartRow
                                scrollableHeaderRow
                                Rectangle()
                                    .fill(StatisticsEditorialStyle.ink)
                                    .frame(height: 1)
                                    .padding(.bottom, 3)

                                ForEach(Array(rows.enumerated()), id: \.offset) { item in
                                    let row = item.element
                                    if row.dividerAbove {
                                        Color.clear
                                            .frame(height: dividerHeight)
                                    }
                                    HStack(spacing: 0) {
                                        valueCells(for: row)
                                    }
                                }
                                Color.clear
                                    .frame(width: 1, height: 1)
                                    .id("statistics-trailing")
                            }
                            if let futureDividerX {
                                Rectangle()
                                    .fill(futureDividerColor)
                                    .frame(width: futureDividerWidth, height: scrollableContentHeight)
                                    .offset(x: futureDividerX)
                            }
                        }
                    }
                    .onAppear {
                        scrollToTrailing(reader)
                    }
                    .onChange(of: scrollTrigger) { _, _ in
                        scrollToTrailing(reader)
                    }
                }
            }
            if !legend.isEmpty {
                StatisticsLegend(items: legend, leadingInset: firstColumnWidth)
            }
        }
        .padding(.vertical, 2)
    }

    private var fixedLabelColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(width: firstColumnWidth, height: chartHeight)
            Color.clear
                .frame(width: firstColumnWidth, height: headerHeight)
            Rectangle()
                .fill(StatisticsEditorialStyle.ink)
                .frame(width: firstColumnWidth, height: 1)
                .padding(.bottom, 3)

            ForEach(Array(rows.enumerated()), id: \.offset) { item in
                let row = item.element
                if row.dividerAbove {
                    Color.clear
                        .frame(width: firstColumnWidth, height: dividerHeight)
                }
                Text(row.title)
                    .font(appFont(.body).weight(row.isTotal ? .semibold : .regular))
                    .foregroundStyle(AppPalette.appText)
                    .frame(width: firstColumnWidth, height: rowHeight, alignment: .leading)
                    .lineLimit(1)
                    .overlay(alignment: .top) {
                        if row.isTotal {
                            Rectangle().fill(StatisticsEditorialStyle.ink).frame(height: 1)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        statisticsRowBottomRule(isTotal: row.isTotal)
                    }
            }
        }
    }

    private var scrollableChartRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.offset) { entryIndex, entry in
                VStack(spacing: 5) {
                    if showsChartTotals {
                        Text(entry.totalText)
                            .font(appFont(.body))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    VStack(spacing: 2) {
                        Spacer(minLength: 0)
                        // Reversed so the first-listed series sits at the bottom
                        // of the stack (the editorial reading order).
                        ForEach(Array(entry.segments.enumerated().reversed()), id: \.offset) { segmentIndex, segment in
                            if segment.value > 0 {
                                Button {
                                    onChartSegmentTap?(entryIndex, segmentIndex)
                                } label: {
                                    Rectangle()
                                        .fill(segment.tint.fillColor())
                                        .frame(height: segmentHeight(segment.value, total: entry.total))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .frame(width: valueColumnWidth, height: barHeight(for: entry.total))
                }
            }

            Color.clear
                .frame(width: valueColumnWidth)
        }
        .frame(height: chartHeight, alignment: .bottom)
        .padding(.horizontal, 1)
    }

    private var scrollableHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                statisticsColumnHeaderText(entry.label)
                    .frame(width: valueColumnWidth, height: headerHeight)
            }
            statisticsColumnHeaderText(totalColumnTitle)
                .frame(width: valueColumnWidth, height: headerHeight)
        }
    }

    @ViewBuilder
    private func valueCells(for row: StatisticsHeatRow) -> some View {
        let cells = row.values.enumerated().map { index, value in
            StatisticsHeatCellData(
                id: index,
                value: value,
                tint: row.cellPalettes?[safe: index] ?? row.palette
            )
        }
        ForEach(cells) { cell in
            Button {
                onCellTap?(row.key, cell.id)
            } label: {
                let isEmpty = row.emptyValueIndexes.contains(cell.id)
                let isTotalColumn = cell.id == row.values.count - 1
                Text(isEmpty ? "–" : row.formatter(cell.value))
                    .font(appFont(.body).weight(row.isTotal || isTotalColumn ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(AppPalette.appText)
                    .frame(width: valueColumnWidth, height: 28)
                    .contentShape(Rectangle())
                    .overlay(alignment: .top) {
                        if row.isTotal {
                            Rectangle().fill(StatisticsEditorialStyle.ink).frame(height: 1)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        statisticsRowBottomRule(isTotal: row.isTotal)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private func barHeight(for total: Double) -> CGFloat {
        guard maxTotal > 0 else { return 8 }
        return max(8, CGFloat(total / maxTotal) * 225)
    }

    private func segmentHeight(_ value: Double, total: Double) -> CGFloat {
        guard total > 0 else { return 0 }
        return max(0, CGFloat(value / total) * barHeight(for: total))
    }

    private func scrollToTrailing(_ reader: ScrollViewProxy) {
        DispatchQueue.main.async {
            reader.scrollTo("statistics-trailing", anchor: .trailing)
        }
    }
}

private enum StatisticsTableKind {
    case grantCount
    case grantAmount
    case publicationType
    case publicationIndependence
    case citation
    case teachingHours
    case activityType
    case activityProject
}

private struct StatisticsDrilldownSelection {
    let kind: StatisticsTableKind
    let rowKey: String
    let columnIndex: Int
}

private struct StatisticsDrilldownItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let detail: String?
    let recordID: String?
    let destination: AppRoute.Destination?
    var calendarSource: CalendarWorkspaceEventSource? = nil
}

private struct StatisticsDrilldownContent {
    let title: String
    let subtitle: String?
    let items: [StatisticsDrilldownItem]
}

private struct StatisticsDrilldownCard: View {
    let language: AppLanguage
    let title: String
    let subtitle: String?
    let items: [StatisticsDrilldownItem]
    var onItemTap: ((StatisticsDrilldownItem) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Rectangle()
                    .fill(AppPalette.border)
                    .frame(height: 1)
                AppPanelHeadingText(text: title)
                if let subtitle = subtitle?.nonEmpty {
                    AppRecordSubtitleText(text: subtitle)
                }
            }

            if items.isEmpty {
                AppCompactEmptyListLabel(title: language.text("No records", "Inga poster"))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Rectangle()
                                .fill(AppPalette.border.opacity(0.65))
                                .frame(height: 1)
                        }
                        Button {
                            onItemTap?(item)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    AppCompactRowTitleText(text: item.title, lineLimit: 2)
                                    if let subtitle = item.subtitle?.nonEmpty {
                                        AppRecordSubtitleText(text: subtitle)
                                    }
                                }
                                Spacer(minLength: 8)
                                if let detail = item.detail?.nonEmpty {
                                    Text(detail)
                                        .font(appFont(.body).weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct StatisticsHeatTableCard: View {
    let title: String
    let columnTitles: [String]
    let rows: [StatisticsHeatRow]
    var firstColumnWidth: CGFloat = 190
    var valueColumnWidth: CGFloat = 70
    var valueColumnWidths: [CGFloat]? = nil
    var showsChart = false

    private let chartMetricHeight: CGFloat = 124
    private let chartMetricSpacing: CGFloat = 8
    private let chartBottomSpacing: CGFloat = 10
    private let headerHeight: CGFloat = 34
    private let rowHeight: CGFloat = 28
    private let dividerHeight: CGFloat = 7

    private var scrollTrigger: String {
        columnTitles.joined(separator: "|") + "-\(rows.map(\.key).joined(separator: "|"))"
    }

    private var chartRows: [StatisticsHeatRow] {
        showsChart ? rows : []
    }

    private var chartColumnCount: Int {
        max(0, columnTitles.count - 1)
    }

    private func maxValue(for palette: StatisticsTint) -> Double {
        rows
            .flatMap { row in
                row.values.enumerated().compactMap { index, value in
                    let cellPalette: StatisticsTint
                    if let rowCellPalettes = row.cellPalettes, rowCellPalettes.indices.contains(index) {
                        cellPalette = rowCellPalettes[index]
                    } else {
                        cellPalette = row.palette
                    }
                    return cellPalette == palette ? value : nil
                }
            }
            .max() ?? 0
    }

    private func widthForColumn(_ index: Int) -> CGFloat {
        if let valueColumnWidths, valueColumnWidths.indices.contains(index) {
            return valueColumnWidths[index]
        }
        return valueColumnWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppPalette.titleSpacing) {
            StatisticsSerifTitleText(text: title)
            HStack(alignment: .top, spacing: 0) {
                fixedLabelColumn
                ScrollViewReader { reader in
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            if showsChart {
                                VStack(alignment: .leading, spacing: chartMetricSpacing) {
                                    ForEach(Array(chartRows.enumerated()), id: \.offset) { _, row in
                                        chartCells(for: row)
                                    }
                                }
                                .padding(.bottom, chartBottomSpacing)
                            }

                            scrollableHeaderRow
                            Rectangle()
                                .fill(StatisticsEditorialStyle.ink)
                                .frame(height: 1)
                                .padding(.bottom, 3)

                            ForEach(Array(rows.enumerated()), id: \.offset) { item in
                                let row = item.element
                                if row.dividerAbove {
                                    Color.clear
                                        .frame(height: dividerHeight)
                                }
                                HStack(spacing: 0) {
                                    valueCells(for: row)
                                }
                            }

                            Color.clear
                                .frame(width: 1, height: 1)
                                .id("statistics-trailing")
                        }
                    }
                    .onAppear {
                        scrollToTrailing(reader)
                    }
                    .onChange(of: scrollTrigger) { _, _ in
                        scrollToTrailing(reader)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var fixedLabelColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsChart {
                VStack(alignment: .leading, spacing: chartMetricSpacing) {
                    ForEach(Array(chartRows.enumerated()), id: \.offset) { _, row in
                        Text(row.title)
                            .font(appFont(.body))
                            .foregroundStyle(AppPalette.appText)
                            .frame(width: firstColumnWidth, height: chartMetricHeight, alignment: .leading)
                            .lineLimit(1)
                    }
                }
                .padding(.bottom, chartBottomSpacing)
            }

            Color.clear
                .frame(width: firstColumnWidth, height: headerHeight)
            Rectangle()
                .fill(StatisticsEditorialStyle.ink)
                .frame(width: firstColumnWidth, height: 1)
                .padding(.bottom, 3)

            ForEach(Array(rows.enumerated()), id: \.offset) { item in
                let row = item.element
                if row.dividerAbove {
                    Color.clear
                        .frame(width: firstColumnWidth, height: dividerHeight)
                }
                Text(row.title)
                    .font(appFont(.body).weight(row.isTotal ? .semibold : .regular))
                    .foregroundStyle(AppPalette.appText)
                    .frame(width: firstColumnWidth, height: rowHeight, alignment: .leading)
                    .lineLimit(1)
                    .overlay(alignment: .top) {
                        if row.isTotal {
                            Rectangle().fill(StatisticsEditorialStyle.ink).frame(height: 1)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        statisticsRowBottomRule(isTotal: row.isTotal)
                    }
            }
        }
    }

    private var scrollableHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(columnTitles.enumerated()), id: \.offset) { index, title in
                statisticsColumnHeaderText(title)
                    .frame(width: widthForColumn(index), height: headerHeight)
            }
        }
    }

    @ViewBuilder
    private func chartCells(for row: StatisticsHeatRow) -> some View {
        let cells = row.values.enumerated().map { index, value in
            StatisticsHeatCellData(
                id: index,
                value: value,
                tint: row.cellPalettes?[safe: index] ?? row.palette
            )
        }
        let maxValue = row.values.enumerated().compactMap { index, value in
            row.emptyValueIndexes.contains(index) || index >= chartColumnCount ? nil : value
        }
        .max() ?? 0

        HStack(alignment: .bottom, spacing: 0) {
            ForEach(cells) { cell in
                let isChartColumn = cell.id < chartColumnCount
                let isEmpty = row.emptyValueIndexes.contains(cell.id)
                let barHeight = isChartColumn ? chartBarHeight(for: cell.value, maxValue: maxValue) : 0
                VStack(spacing: 5) {
                    Text(isChartColumn ? (isEmpty ? "–" : row.formatter(cell.value)) : "")
                        .font(appFont(.body).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if isChartColumn, !isEmpty, cell.value > 0 {
                            Rectangle()
                                .fill(cell.tint.fillColor())
                                .frame(height: chartBarHeight(for: cell.value, maxValue: maxValue))
                        }
                    }
                    .padding(.horizontal, 4)
                    .frame(width: widthForColumn(cell.id), height: barHeight)
                }
                .frame(width: widthForColumn(cell.id), height: chartMetricHeight, alignment: .bottom)
            }
        }
    }

    @ViewBuilder
    private func valueCells(for row: StatisticsHeatRow) -> some View {
        let cells = row.values.enumerated().map { index, value in
            StatisticsHeatCellData(
                id: index,
                value: value,
                tint: row.cellPalettes?[safe: index] ?? row.palette
            )
        }
        ForEach(cells) { cell in
            let isEmpty = row.emptyValueIndexes.contains(cell.id)
            let isTotalColumn = cell.id == row.values.count - 1
            Text(isEmpty ? "–" : row.formatter(cell.value))
                .font(appFont(.body).weight(row.isTotal || isTotalColumn ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(AppPalette.appText)
                .frame(width: widthForColumn(cell.id), height: 28)
                .overlay(alignment: .top) {
                    if row.isTotal {
                        Rectangle().fill(StatisticsEditorialStyle.ink).frame(height: 1)
                    }
                }
                .overlay(alignment: .bottom) {
                    statisticsRowBottomRule(isTotal: row.isTotal)
                }
        }
    }

    private func chartBarHeight(for value: Double, maxValue: Double) -> CGFloat {
        guard maxValue > 0 else { return 8 }
        return max(8, CGFloat(value / maxValue) * 86)
    }

    private func scrollToTrailing(_ reader: ScrollViewProxy) {
        DispatchQueue.main.async {
            reader.scrollTo("statistics-trailing", anchor: .trailing)
        }
    }
}

private struct StatisticsStackedSegment {
    let value: Double
    let tint: StatisticsTint
}

private struct StatisticsStackedEntry {
    let label: String
    let total: Double
    let totalText: String
    let segments: [StatisticsStackedSegment]
}




private struct StatisticsLegend: View {
    let items: [(String, StatisticsTint)]
    var leadingInset: CGFloat = 0

    var body: some View {
        if items.count > 1 {
            HStack(spacing: 18) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 7) {
                        Rectangle()
                            .fill(item.1.fillColor())
                            .frame(width: 10, height: 10)
                        Text(item.0)
                            .font(appFont(.secondary))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .padding(.leading, leadingInset)
        }
    }
}



private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
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
