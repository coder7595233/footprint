import SwiftUI

private extension Color {
    init(rgbHex: Int) {
        self.init(
            red: Double((rgbHex >> 16) & 0xFF) / 255.0,
            green: Double((rgbHex >> 8) & 0xFF) / 255.0,
            blue: Double(rgbHex & 0xFF) / 255.0
        )
    }
}

private struct ContributorCompositionSwatch {
    let fill: Color
    let foreground: Color
}


enum ContributorGenderCategory: String, Equatable {
    case male
    case female
    case unknown

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .male:
            language.text("Men", "Män")
        case .female:
            language.text("Women", "Kvinnor")
        case .unknown:
            language.text("Unknown", "Okänt")
        }
    }

    func singularDisplayName(language: AppLanguage) -> String {
        switch self {
        case .male:
            language.text("Man", "Man")
        case .female:
            language.text("Woman", "Kvinna")
        case .unknown:
            language.text("Unknown", "Okänt")
        }
    }
}

enum ContributorPhDCategory: String, Equatable {
    case phd
    case nonPhd
    case unknown

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .phd:
            language.text("PhD", "Disputerade")
        case .nonPhd:
            language.text("No PhD", "Ej disputerade")
        case .unknown:
            language.text("Missing", "Saknas")
        }
    }
}

struct ContributorCompositionPositionSummary: Equatable {
    let name: String
    let gender: ContributorGenderCategory
}

struct ContributorCompositionDistributionEntry: Equatable, Identifiable {
    let label: String
    let count: Int
    let contributorNames: [String]

    init(label: String, count: Int, contributorNames: [String] = []) {
        self.label = label
        self.count = count
        self.contributorNames = contributorNames
    }

    var id: String { label }
}

struct ContributorStatisticRow: Equatable, Identifiable {
    let label: String
    let value: String
    var detail: String?

    var id: String { label }
}

struct ContributorStatisticsTable: Equatable {
    struct Row: Equatable, Identifiable {
        let year: String
        let values: [String]

        var id: String { year }
    }

    let title: String
    let columnTitles: [String]
    let rows: [Row]
}

struct ContributorCompositionSnapshot: Equatable {
    let totalCount: Int
    let resolvedCount: Int
    let firstPosition: ContributorCompositionPositionSummary?
    let lastPosition: ContributorCompositionPositionSummary?
    let genderDistribution: [ContributorCompositionDistributionEntry]
    let phdDistribution: [ContributorCompositionDistributionEntry]
    let careerStageDistribution: [ContributorCompositionDistributionEntry]
    let titleDistribution: [ContributorCompositionDistributionEntry]
    let organizationDistribution: [ContributorCompositionDistributionEntry]
    let countryDistribution: [ContributorCompositionDistributionEntry]

    var unresolvedCount: Int {
        max(0, totalCount - resolvedCount)
    }

    var unknownGenderCount: Int {
        genderDistribution.first(where: {
            normalizedContributorCompositionKey($0.label) == normalizedContributorCompositionKey("unknown")
                || normalizedContributorCompositionKey($0.label) == normalizedContributorCompositionKey("okänt")
        })?.count ?? 0
    }

    init(
        contributorNames: [String],
        language: AppLanguage,
        resolveAuthor: (String) -> PublicationAuthor?
    ) {
        let rows = contributorNames.map { name in
            ContributorCompositionRow(
                presentedName: collapsedContributorCompositionWhitespace(name),
                author: resolveAuthor(name)
            )
        }

        totalCount = rows.count
        resolvedCount = rows.filter { $0.author != nil }.count
        firstPosition = rows.first.map { Self.positionSummary(for: $0) }
        lastPosition = rows.last.map { Self.positionSummary(for: $0) }

        let genderNames = rows.reduce(into: [ContributorGenderCategory: [String]]()) { namesByCategory, row in
            namesByCategory[Self.gender(for: row), default: []].append(row.displayName)
        }
        genderDistribution = Self.genderDistributionEntries(
            namesByCategory: genderNames,
            language: language
        )

        let phdNames = rows.reduce(into: [ContributorPhDCategory: [String]]()) { namesByCategory, row in
            namesByCategory[Self.phdCategory(for: row), default: []].append(row.displayName)
        }
        phdDistribution = Self.phdDistributionEntries(
            namesByCategory: phdNames,
            language: language
        )

        let careerStageNames = rows.reduce(into: [PublicationAuthorCareerStage: [String]]()) { namesByStage, row in
            guard let stage = Self.careerStage(for: row) else { return }
            namesByStage[stage, default: []].append(row.displayName)
        }
        careerStageDistribution = Self.careerStageDistributionEntries(
            namesByStage: careerStageNames,
            missingNames: rows.compactMap { Self.careerStage(for: $0) == nil ? $0.displayName : nil },
            language: language
        )

        titleDistribution = Self.stringDistribution(
            rows.map { (label: Self.titleLabel(for: $0, language: language), contributorName: $0.displayName) },
            unknownLabel: language.text("Missing", "Saknas")
        )
        organizationDistribution = Self.stringDistribution(
            rows.map { (label: Self.organizationLabel(for: $0, language: language), contributorName: $0.displayName) },
            unknownLabel: language.text("Missing", "Saknas")
        )
        countryDistribution = Self.stringDistribution(
            rows.map { (label: Self.countryLabel(for: $0, language: language), contributorName: $0.displayName) },
            unknownLabel: language.text("Missing", "Saknas")
        )
    }

    private struct ContributorCompositionRow {
        let presentedName: String
        let author: PublicationAuthor?

        var displayName: String {
            let resolved = collapsedContributorCompositionWhitespace(author?.displayName ?? "")
            return resolved.isEmpty ? presentedName : resolved
        }
    }

    private static func positionSummary(for row: ContributorCompositionRow) -> ContributorCompositionPositionSummary {
        ContributorCompositionPositionSummary(
            name: row.displayName,
            gender: gender(for: row)
        )
    }

    private static func gender(for row: ContributorCompositionRow) -> ContributorGenderCategory {
        guard let author = row.author else { return .unknown }

        switch author.gender {
        case .female:
            return .female
        case .male:
            return .male
        case .unspecified:
            break
        }

        let candidateFields = [
            author.titleSv,
            author.titleEn,
            author.positionSv,
            author.positionEn
        ]
        .map(normalizedContributorCompositionKey)
        .filter { !$0.isEmpty }

        let femaleTokens = ["fru", "ms", "mrs", "miss", "female", "kvinna"]
        let maleTokens = ["herr", "mr", "mister", "male", "man"]

        for candidate in candidateFields {
            let tokens = Set(candidate.split(separator: " ").map(String.init))
            if !tokens.isDisjoint(with: Set(femaleTokens)) {
                return .female
            }
            if !tokens.isDisjoint(with: Set(maleTokens)) {
                return .male
            }
        }

        return .unknown
    }

    private static func phdCategory(for row: ContributorCompositionRow) -> ContributorPhDCategory {
        guard let author = row.author else { return .unknown }
        return author.hasPhD ? .phd : .nonPhd
    }

    private static func careerStage(for row: ContributorCompositionRow) -> PublicationAuthorCareerStage? {
        row.author?.careerStage
    }

    private static func titleLabel(for row: ContributorCompositionRow, language: AppLanguage) -> String {
        let title = collapsedContributorCompositionWhitespace(row.author?.localizedTitle(language: language) ?? "")
        if !title.isEmpty && !isContributorCompositionHonorific(title) {
            return title
        }

        let position = collapsedContributorCompositionWhitespace(row.author?.localizedPosition(language: language) ?? "")
        if !position.isEmpty {
            return position
        }

        return language.text("Missing", "Saknas")
    }

    private static func organizationLabel(for row: ContributorCompositionRow, language: AppLanguage) -> String {
        let organization = collapsedContributorCompositionWhitespace(
            row.author?.primaryAffiliation?.localizedOrganization(language: language) ?? ""
        )
        return organization.isEmpty ? language.text("Missing", "Saknas") : organization
    }

    private static func countryLabel(for row: ContributorCompositionRow, language: AppLanguage) -> String {
        let country = collapsedContributorCompositionWhitespace(row.author?.primaryAffiliation?.country ?? "")
        let canonicalCountry = GrantParsing.canonicalCountryName(country).trimmingCharacters(in: .whitespacesAndNewlines)
        return canonicalCountry.isEmpty ? language.text("Missing", "Saknas") : language.localizedCountry(canonicalCountry)
    }

    private static func genderDistributionEntries(
        namesByCategory: [ContributorGenderCategory: [String]],
        language: AppLanguage
    ) -> [ContributorCompositionDistributionEntry] {
        [
            ContributorGenderCategory.male,
            ContributorGenderCategory.female,
            ContributorGenderCategory.unknown
        ]
        .compactMap { category in
            let contributorNames = namesByCategory[category] ?? []
            guard !contributorNames.isEmpty else { return nil }
            return ContributorCompositionDistributionEntry(
                label: category.displayName(language: language),
                count: contributorNames.count,
                contributorNames: contributorNames
            )
        }
    }

    private static func phdDistributionEntries(
        namesByCategory: [ContributorPhDCategory: [String]],
        language: AppLanguage
    ) -> [ContributorCompositionDistributionEntry] {
        [
            ContributorPhDCategory.phd,
            ContributorPhDCategory.nonPhd,
            ContributorPhDCategory.unknown
        ]
        .compactMap { category in
            let contributorNames = namesByCategory[category] ?? []
            guard !contributorNames.isEmpty else { return nil }
            return ContributorCompositionDistributionEntry(
                label: category.displayName(language: language),
                count: contributorNames.count,
                contributorNames: contributorNames
            )
        }
    }

    private static func stringDistribution(
        _ values: [(label: String, contributorName: String)],
        unknownLabel: String
    ) -> [ContributorCompositionDistributionEntry] {
        var countsByKey: [String: Int] = [:]
        var displayLabelsByKey: [String: String] = [:]
        var contributorNamesByKey: [String: [String]] = [:]

        for value in values {
            let normalizedValue = collapsedContributorCompositionWhitespace(value.label)
            let displayValue = normalizedValue.isEmpty ? unknownLabel : normalizedValue
            let key = normalizedContributorCompositionKey(displayValue)
            countsByKey[key, default: 0] += 1
            displayLabelsByKey[key] = displayLabelsByKey[key] ?? displayValue
            contributorNamesByKey[key, default: []].append(value.contributorName)
        }

        return countsByKey
            .compactMap { key, count in
                guard let label = displayLabelsByKey[key] else { return nil }
                return ContributorCompositionDistributionEntry(
                    label: label,
                    count: count,
                    contributorNames: contributorNamesByKey[key] ?? []
                )
            }
            .sorted { lhs, rhs in
                if normalizedContributorCompositionKey(lhs.label) == normalizedContributorCompositionKey(unknownLabel) {
                    return false
                }
                if normalizedContributorCompositionKey(rhs.label) == normalizedContributorCompositionKey(unknownLabel) {
                    return true
                }
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
            }
    }

    private static func careerStageDistributionEntries(
        namesByStage: [PublicationAuthorCareerStage: [String]],
        missingNames: [String],
        language: AppLanguage
    ) -> [ContributorCompositionDistributionEntry] {
        var entries: [ContributorCompositionDistributionEntry] = []
        for stage in PublicationAuthorCareerStage.editorDisplayOrder {
            let contributorNames = namesByStage[stage] ?? []
            guard !contributorNames.isEmpty else { continue }
            entries.append(
                ContributorCompositionDistributionEntry(
                    label: stage.rawValue,
                    count: contributorNames.count,
                    contributorNames: contributorNames
                )
            )
        }

        if !missingNames.isEmpty {
            entries.append(
                ContributorCompositionDistributionEntry(
                    label: language.text("Missing", "Saknas"),
                    count: missingNames.count,
                    contributorNames: missingNames
                )
            )
        }

        return entries
    }
}

struct ContributorCompositionPopoverButton: View {
    @ObservedObject var store: GrantDataStore
    let contributorNames: [String]
    let language: AppLanguage
    let title: String
    var statisticRows: [ContributorStatisticRow] = []
    var grantOutcomeApplications: [GrantApplication] = []
    var grantOutcomeAmountValue: ((GrantApplication, Double?) -> Double)? = nil
    var grantOutcomeRemainingAmount: ((GrantApplication) -> Double?)? = nil
    var meetingStatistics: CalendarMeetingHoursSummary?
    var statisticsTable: ContributorStatisticsTable?
    var compositionTitle: String?
    var showsContributorComposition: Bool = true
    var showsPositionGenderSummary: Bool = true
    var showsLastPositionGenderSummary: Bool = true

    private var snapshot: ContributorCompositionSnapshot {
        ContributorCompositionSnapshot(
            contributorNames: contributorNames,
            language: language,
            resolveAuthor: { store.publicationAuthor(matchingPresentedName: $0) }
        )
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .floatingStatisticsContent(
                id: "contributor-composition-\(title)",
                title: title,
                isAvailable: hasStatisticsContent
            ) {
            ContributorCompositionPopover(
                title: title,
                snapshot: snapshot,
                language: language,
                statisticRows: statisticRows,
                grantOutcomeApplications: grantOutcomeApplications,
                grantOutcomeAmountValue: grantOutcomeAmountValue,
                grantOutcomeRemainingAmount: grantOutcomeRemainingAmount,
                meetingStatistics: meetingStatistics,
                statisticsTable: statisticsTable,
                compositionTitle: compositionTitle,
                showsContributorComposition: showsContributorComposition,
                showsPositionGenderSummary: showsPositionGenderSummary,
                showsLastPositionGenderSummary: showsLastPositionGenderSummary,
                openMeeting: { source in
                    store.openCalendarLinkedEvent(source: source)
                }
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
        }
    }

    private var hasStatisticsContent: Bool {
        !statisticRows.isEmpty
            || grantOutcomeApplications.contains { !$0.isToApplyStatus }
            || meetingStatistics != nil
            || (showsContributorComposition && !contributorNames.isEmpty)
    }
}

private let contributorCompositionSharedPaletteHexes = [
    0x4A7BB7,
    0x6EA6CD,
    0x98CAE1,
    0xC2E4EF,
    0xEAECCC,
    0xFEDA8B,
    0xFDB366,
    0xF67E4B,
    0xDD3D2D,
]

private struct ContributorCompositionPopover: View {
    private static let sharedPaletteHexes = contributorCompositionSharedPaletteHexes

    struct BarEntry: Identifiable {
        let label: String
        let count: Int
        let percentage: Double
        let color: Color
        let foregroundColor: Color
        let helpText: String

        var id: String { label }
    }

    let title: String
    let snapshot: ContributorCompositionSnapshot
    let language: AppLanguage
    let statisticRows: [ContributorStatisticRow]
    let grantOutcomeApplications: [GrantApplication]
    let grantOutcomeAmountValue: ((GrantApplication, Double?) -> Double)?
    let grantOutcomeRemainingAmount: ((GrantApplication) -> Double?)?
    let meetingStatistics: CalendarMeetingHoursSummary?
    let statisticsTable: ContributorStatisticsTable?
    let compositionTitle: String?
    let showsContributorComposition: Bool
    let showsPositionGenderSummary: Bool
    let showsLastPositionGenderSummary: Bool
    let openMeeting: (CalendarWorkspaceEventSource) -> Void

    @State private var measuredGenderSectionHeight: CGFloat = 0

    private var summaryText: String {
        let base: String
        if snapshot.unresolvedCount > 0 {
            base = language.text(
                "\(snapshot.totalCount) people • \(snapshot.resolvedCount) matched author cards",
                "\(snapshot.totalCount) personer • \(snapshot.resolvedCount) matchade författarkort"
            )
        } else {
            base = language.text(
                "\(snapshot.totalCount) people",
                "\(snapshot.totalCount) personer"
            )
        }
        let positionDetails: [String]
        if !showsPositionGenderSummary {
            positionDetails = []
        } else if showsLastPositionGenderSummary {
            positionDetails = [
                snapshot.firstPosition.map { language.text("first author: \($0.gender.singularDisplayName(language: language))", "förstaförfattare: \($0.gender.singularDisplayName(language: language))") },
                snapshot.lastPosition.map { language.text("last author: \($0.gender.singularDisplayName(language: language))", "sistaförfattare: \($0.gender.singularDisplayName(language: language))") }
            ].compactMap { $0 }
        } else {
            positionDetails = snapshot.firstPosition.map {
                [language.text("leading position: \($0.gender.singularDisplayName(language: language))", "ledande position: \($0.gender.singularDisplayName(language: language))")]
            } ?? []
        }
        guard !positionDetails.isEmpty else { return base }
        return "\(base) (\(positionDetails.joined(separator: "; ")))"
    }

    private var genderBars: [BarEntry] {
        bars(from: snapshot.genderDistribution, paletteHexes: Self.sharedPaletteHexes)
    }

    private var phdBars: [BarEntry] {
        bars(from: snapshot.phdDistribution, paletteHexes: Self.sharedPaletteHexes)
    }

    private var careerStageBars: [BarEntry] {
        bars(from: snapshot.careerStageDistribution, paletteHexes: Self.sharedPaletteHexes)
    }

    private var titleBars: [BarEntry] {
        bars(from: snapshot.titleDistribution, paletteHexes: Self.sharedPaletteHexes)
    }

    private var organizationBars: [BarEntry] {
        bars(from: snapshot.organizationDistribution, paletteHexes: Self.sharedPaletteHexes)
    }

    private var countryBars: [BarEntry] {
        bars(from: snapshot.countryDistribution, paletteHexes: Self.sharedPaletteHexes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if title != language.text("Statistics", "Statistik") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(appFont(.sectionTitle))
                }
            }
            if meetingStatistics == nil && showsContributorComposition {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summaryText)
                        .font(appFont(.secondary).weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if !statisticRows.isEmpty {
                ContributorStatisticsSummarySection(rows: statisticRows, language: language)
            }

            if let statisticsTable, !statisticsTable.rows.isEmpty {
                ContributorStatisticsTableSection(table: statisticsTable)
            }

            if grantOutcomeApplications.contains(where: { !$0.isToApplyStatus }) {
                ContributorGrantOutcomeSummarySection(
                    applications: grantOutcomeApplications,
                    language: language,
                    amountValue: grantOutcomeAmountValue,
                    remainingAmount: grantOutcomeRemainingAmount
                )
            }

            if let meetingStatistics {
                CalendarMeetingStatisticsSection(
                    summary: meetingStatistics,
                    language: language,
                    openMeeting: openMeeting
                )
                .layoutPriority(3)
            }

            if showsContributorComposition {
                if meetingStatistics != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        StatisticsSectionHeading(text: compositionTitle ?? title)
                        Text(summaryText)
                            .font(appFont(.secondary).weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if snapshot.totalCount == 0 {
                    Text(language.text("No people to summarize yet.", "Inga personer att sammanfatta ännu."))
                        .font(appFont(.body))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ContributorCompositionBarSection(
                            title: language.text("Gender", "Kön"),
                            entries: genderBars
                        )

                        if snapshot.unknownGenderCount > 0 {
                            Text(
                                language.text(
                                    "Gender shows as unknown when it cannot be determined from saved metadata.",
                                    "Kön visas som okänt när det inte går att avgöra från sparad metadata."
                                )
                            )
                            .font(appFont(.secondary))
                            .foregroundStyle(.secondary)
                        }

                        ContributorCompositionBarSection(
                            title: language.text("PhD", "Disputerade"),
                            entries: phdBars
                        )
                        ContributorCompositionBarSection(
                            title: language.text("Career stage", "Karriärsteg"),
                            entries: careerStageBars
                        )
                        ContributorCompositionBarSection(
                            title: language.text("Title", "Titel"),
                            entries: titleBars
                        )
                        ContributorCompositionBarSection(
                            title: language.text("Organization", "Organisation"),
                            entries: organizationBars
                        )
                        ContributorCompositionBarSection(
                            title: language.text("Country", "Land"),
                            entries: countryBars
                        )
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppPalette.detailPanelSurface)
    }

    private func bars(
        from distribution: [ContributorCompositionDistributionEntry],
        paletteHexes: [Int]
    ) -> [BarEntry] {
        distribution.enumerated().map { index, entry in
            let isMissing = normalizedContributorCompositionKey(entry.label) == normalizedContributorCompositionKey(language.text("Missing", "Saknas"))
            let paletteHex = paletteHexes.isEmpty ? 0x0D5F5B : paletteHexes[index % paletteHexes.count]
            let swatch = isMissing
                ? contributorCompositionSwatch(rgbHex: 0x7C8590)
                : contributorCompositionSwatch(rgbHex: paletteHex)
            let percentage = percentage(for: entry.count)
            return BarEntry(
                label: entry.label,
                count: entry.count,
                percentage: percentage,
                color: swatch.fill,
                foregroundColor: swatch.foreground,
                helpText: contributorCompositionTooltip(
                    label: entry.label,
                    count: entry.count,
                    percentage: percentage,
                    contributorNames: entry.contributorNames
                )
            )
        }
    }

    private func percentage(for count: Int) -> Double {
        guard snapshot.totalCount > 0 else { return 0 }
        return Double(count) / Double(snapshot.totalCount)
    }
}

private struct ContributorStatisticsTableSection: View {
    let table: ContributorStatisticsTable

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatisticsSectionHeading(text: table.title)

            VStack(spacing: 0) {
                tableRow(
                    year: table.columnTitles.first ?? "",
                    values: Array(table.columnTitles.dropFirst()),
                    isHeader: true
                )

                ForEach(table.rows) { row in
                    Divider().overlay(AppPalette.subtleBorder)
                    tableRow(year: row.year, values: row.values, isHeader: false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                    .fill(AppPalette.fieldSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                    .stroke(AppPalette.subtleBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous))
        }
    }

    private func tableRow(year: String, values: [String], isHeader: Bool) -> some View {
        HStack(spacing: 8) {
            Text(year)
                .frame(width: 54, alignment: .leading)

            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Text(value)
                    .frame(maxWidth: .infinity, alignment: isHeader ? .leading : .trailing)
            }
        }
        .font(isHeader ? appFont(.tableHeader) : appFont(.secondary).weight(.medium))
        .foregroundStyle(isHeader ? AnyShapeStyle(.secondary) : AnyShapeStyle(AppPalette.appText))
        .monospacedDigit()
        .padding(.horizontal, 10)
        .frame(minHeight: isHeader ? 36 : 34)
        .background(isHeader ? AppPalette.secondaryCardSurface.opacity(0.72) : Color.clear)
    }
}

private struct ContributorGrantOutcomeSummarySection: View {
    let applications: [GrantApplication]
    let language: AppLanguage
    let amountValue: ((GrantApplication, Double?) -> Double)?
    let remainingAmount: ((GrantApplication) -> Double?)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatisticsSectionHeading(text: language.text("Grants", "Anslag"))

            GrantOutcomeDistributionCard(
                applications: applications,
                language: language,
                amountValue: amountValue,
                remainingAmount: remainingAmount,
                compactAmountOnly: false,
                showsFooter: false
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct StatisticsSectionHeading: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(appFont(.statTitle))
            Rectangle()
                .fill(AppPalette.subtleBorder)
                .frame(height: 1)
        }
    }
}

private struct ContributorStatisticsSummarySection: View {
    let rows: [ContributorStatisticRow]
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language.text("Key figures", "Nyckeltal"))
                .font(appFont(.statTitle))

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 132, maximum: 190), spacing: 8, alignment: .leading)
                ],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.label)
                            .font(appFont(.secondary).weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(row.value)
                                .font(appFont(.statValue))
                                .monospacedDigit()
                            if let detail = row.detail?.trimmedOrNil {
                                Text(detail)
                                    .font(appFont(.secondary).weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                            .fill(AppPalette.fieldSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                            .stroke(AppPalette.subtleBorder.opacity(0.8), lineWidth: 1)
                    )
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous).fill(AppPalette.cardSurface))
        .overlay(RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous).stroke(AppPalette.subtleBorder, lineWidth: 1))
    }
}

private struct CalendarMeetingStatisticsSection: View {
    let summary: CalendarMeetingHoursSummary
    let language: AppLanguage
    let openMeeting: (CalendarWorkspaceEventSource) -> Void
    @State private var selectedDistributionTitle: String?
    @State private var selectedMeetingIDs: Set<String> = []

    private var hasMeetingRows: Bool {
        !summary.completedMeetings.isEmpty || !summary.plannedMeetings.isEmpty
    }

    private var activityDistribution: [CalendarActivityDistributionEntry] {
        calendarActivityDistributionEntries(
            minutesByLabel: summary.activityMinutes,
            colorHexes: summary.activityColorHexes,
            localizeLabel: { calendarMeetingCategoryDisplayName($0, language: language) }
        )
    }

    private var meetingModeDistribution: [CalendarActivityDistributionEntry] {
        calendarActivityDistributionEntries(
            minutesByLabel: summary.meetingModeMinutes,
            localizeLabel: { rawMode in
                guard let rawMode = rawMode.trimmedOrNil else {
                    return language.text("Not specified", "Ej angivet")
                }
                return CalendarMeetingMode(rawValue: rawMode)?.localizedName(language: language) ?? rawMode
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatisticsSectionHeading(text: language.text("Activities", "Aktiviteter"))

            if summary.meetingsWithoutDurationCount > 0 {
                Text(calendarMeetingStatisticsMissingDurationText(summary, language: language))
                .font(appFont(.secondary).weight(.medium))
                .foregroundStyle(.secondary)
            }

            if !activityDistribution.isEmpty {
                CalendarActivityDistributionSection(
                    title: language.text("Activity type", "Aktivitetstyp"),
                    entries: activityDistribution,
                    language: language,
                    onEntryTap: { entry in
                        selectDistribution(title: entry.label) { meeting in
                            calendarMeetingCategoryDisplayName(meeting.activityType, language: language) == entry.label
                        }
                    }
                )
            }

            if !meetingModeDistribution.isEmpty {
                CalendarActivityDistributionSection(
                    title: language.text("Meeting type", "Mötestyp"),
                    entries: meetingModeDistribution,
                    language: language,
                    onEntryTap: { entry in
                        selectDistribution(title: entry.label) { meeting in
                            CalendarMeetingMode(rawValue: meeting.meetingMode)?.localizedName(language: language) == entry.label
                        }
                    }
                )
            }

            if let selectedDistributionTitle, !selectedMeetingIDs.isEmpty {
                let meetings = (summary.completedMeetings + summary.plannedMeetings)
                    .filter { selectedMeetingIDs.contains($0.id) }
                CalendarMeetingStatisticsMeetingGroup(
                    title: selectedDistributionTitle,
                    minutes: meetings.compactMap(\.durationMinutes).reduce(0, +),
                    count: meetings.count,
                    meetings: meetings,
                    language: language,
                    openMeeting: openMeeting
                )
            }

            if hasMeetingRows {
                VStack(alignment: .leading, spacing: 10) {
                    CalendarMeetingStatisticsMeetingGroup(
                        title: language.text("Completed activities", "Genomförda aktiviteter"),
                        minutes: summary.completedMinutes,
                        count: summary.completedMeetingCount,
                        meetings: summary.completedMeetings,
                        language: language,
                        openMeeting: openMeeting,
                        startsCollapsed: true
                    )
                    CalendarMeetingStatisticsMeetingGroup(
                        title: language.text("Planned activities", "Planerade aktiviteter"),
                        minutes: summary.plannedMinutes,
                        count: summary.plannedMeetingCount,
                        meetings: summary.plannedMeetings,
                        language: language,
                        openMeeting: openMeeting,
                        startsCollapsed: true
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func selectDistribution(
        title: String,
        matching predicate: (CalendarMeetingStatisticsMeeting) -> Bool
    ) {
        let matches = (summary.completedMeetings + summary.plannedMeetings).filter(predicate)
        let ids = Set(matches.map(\.id))
        if selectedDistributionTitle == title {
            selectedDistributionTitle = nil
            selectedMeetingIDs = []
        } else {
            selectedDistributionTitle = title
            selectedMeetingIDs = ids
        }
    }
}

private struct CalendarActivityDistributionEntry: Identifiable {
    let label: String
    let minutes: Int
    let percentage: Double
    let color: Color
    /// Round 17: dark text on light fills, white on dark fills.
    var foreground: Color = .white.opacity(0.96)

    var id: String { label }
}

private struct CalendarActivityDistributionSection: View {
    let title: String
    let entries: [CalendarActivityDistributionEntry]
    let language: AppLanguage
    var onEntryTap: ((CalendarActivityDistributionEntry) -> Void)? = nil
    @State private var barWidth: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(appFont(.secondary).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 108, height: 38, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                    ForEach(entries) { entry in
                        let width = geometry.size.width * entry.percentage
                        let fitsInside = width >= minimumInlineWidth(for: entry)
                        Button {
                            onEntryTap?(entry)
                        } label: {
                            Rectangle()
                                .fill(entry.color)
                                .frame(width: width)
                                .overlay {
                                if fitsInside {
                                    VStack(spacing: 0) {
                                        Text(entry.label)
                                            .font(appBadgeFont())
                                        Text("\(calendarMeetingStatisticsHoursText(entry.minutes, language: language)) (\(calendarActivityDistributionPercentageText(entry.percentage)))")
                                            .font(appBadgeFont())
                                    }
                                    .foregroundStyle(entry.foreground)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.65)
                                    .padding(.horizontal, 4)
                                }
                                }
                        }
                        .buttonStyle(.plain)
                        .help("\(entry.label): \(calendarMeetingStatisticsHoursText(entry.minutes, language: language)) (\(calendarActivityDistributionPercentageText(entry.percentage)))")
                    }
                }
                    .clipShape(RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous).stroke(AppPalette.subtleBorder, lineWidth: 1))
                    .onAppear { barWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, newWidth in barWidth = newWidth }
                }
                .frame(height: 38)

                let overflowEntries = entries.filter { barWidth * $0.percentage < minimumInlineWidth(for: $0) }
                ForEach(overflowEntries) { entry in
                    HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(entry.color)
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.label)
                            .font(appFont(.secondary).weight(.medium))
                        Text("\(calendarMeetingStatisticsHoursText(entry.minutes, language: language)) (\(calendarActivityDistributionPercentageText(entry.percentage)))")
                            .font(appFont(.secondary).weight(.medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 6)
                    }
                }
            }
        }
    }

    private func minimumInlineWidth(for entry: CalendarActivityDistributionEntry) -> CGFloat {
        max(
            measuredWidth(entry.label, size: appNSFont(.secondary).pointSize, weight: .semibold),
            measuredWidth("\(calendarMeetingStatisticsHoursText(entry.minutes, language: language)) (\(calendarActivityDistributionPercentageText(entry.percentage)))", size: appNSFont(.secondary).pointSize, weight: .bold)
        ) + 12
    }

    private func measuredWidth(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}

private struct CalendarMeetingStatisticsMeetingGroup: View {
    let title: String
    let minutes: Int
    let count: Int
    let meetings: [CalendarMeetingStatisticsMeeting]
    let language: AppLanguage
    let openMeeting: (CalendarWorkspaceEventSource) -> Void
    var startsCollapsed = false
    @State private var isExpanded = false

    var body: some View {
        if !meetings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                let heading = calendarMeetingStatisticsGroupTitle(title: title, minutes: minutes, count: count, language: language)
                if startsCollapsed {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Text(heading)
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppPalette.appText)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(heading)
                        .font(appFont(.statTitle))
                        .foregroundStyle(AppPalette.appText)
                }
                if !startsCollapsed || isExpanded {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(meetings) { meeting in
                            CalendarMeetingStatisticsMeetingRow(
                                meeting: meeting,
                                language: language,
                                openMeeting: openMeeting
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct CalendarMeetingStatisticsMeetingRow: View {
    let meeting: CalendarMeetingStatisticsMeeting
    let language: AppLanguage
    let openMeeting: (CalendarWorkspaceEventSource) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(calendarMeetingStatisticsMeetingTitle(meeting, language: language))
                .font(appFont(.secondary).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(2)

            calendarMeetingStatisticsSeparator

            Text(calendarMeetingStatisticsMeetingTiming(meeting, language: language))
                .font(appFont(.secondary).weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            calendarMeetingStatisticsSeparator

            Text(calendarMeetingStatisticsMeetingModeText(meeting, language: language))
                .font(appFont(.secondary).weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            calendarMeetingStatisticsSeparator

            Text(calendarMeetingStatisticsParticipantText(meeting, language: language))
                .font(appFont(.secondary).weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Spacer(minLength: 8)

            Button {
                openMeeting(meeting.source)
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16, height: 16)
                    .foregroundStyle(AppPalette.linkAction)
            }
            .buttonStyle(.plain)
            .help(language.text("Open in calendar", "Öppna i kalendern"))
            .accessibilityLabel(language.text("Open in calendar", "Öppna i kalendern"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                .fill(AppPalette.fieldSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                .stroke(AppPalette.subtleBorder, lineWidth: 1)
        )
        .help(calendarMeetingStatisticsMeetingHelpText(meeting, language: language))
    }

    private var calendarMeetingStatisticsSeparator: some View {
        Text("•")
            .font(appFont(.secondary))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
    }
}


private struct ContributorCompositionBarSection: View {
    let title: String
    let entries: [ContributorCompositionPopover.BarEntry]
    @State private var barWidth: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(appFont(.secondary).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 108, height: 38, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                    .fill(AppPalette.fieldSurface)
                    .overlay {
                        HStack(spacing: 0) {
                            ForEach(entries) { entry in
                                let segmentWidth = geometry.size.width * entry.percentage
                                let fitsInside = segmentWidth >= minimumInlineWidth(for: entry)
                                Rectangle()
                                    .fill(entry.color)
                                    .frame(width: segmentWidth)
                                    .help(entry.helpText)
                                    .overlay {
                                        if fitsInside {
                                            VStack(spacing: 0) {
                                                Text(entry.label)
                                                    .font(appBadgeFont())
                                                Text(contributorCompositionSegmentLabel(count: entry.count, percentage: entry.percentage))
                                                    .font(appBadgeFont())
                                            }
                                            .foregroundStyle(entry.foregroundColor)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.6)
                                            .allowsTightening(true)
                                            .padding(.horizontal, 3)
                                        }
                                    }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                            .stroke(AppPalette.subtleBorder, lineWidth: 1)
                    )
                    .onAppear { barWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, newWidth in barWidth = newWidth }
            }
            .frame(height: 38)

            let overflowEntries = entries.filter { barWidth * $0.percentage < minimumInlineWidth(for: $0) }
            if !overflowEntries.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(overflowEntries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(entry.color)
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.label)
                                .appTypography(.tableHeader)
                                .lineLimit(2)
                            Text(contributorCompositionSegmentLabel(count: entry.count, percentage: entry.percentage))
                                .font(appFont(.secondary).weight(.medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                }
            }
        }
        }
    }

    private func minimumInlineWidth(for entry: ContributorCompositionPopover.BarEntry) -> CGFloat {
        // Measured with the same size as the secondary text role used in the bar.
        let titleFont = NSFont.systemFont(ofSize: appNSFont(.secondary).pointSize, weight: .semibold)
        let valueFont = NSFont.systemFont(ofSize: appNSFont(.secondary).pointSize, weight: .bold)
        let titleWidth = ceil((entry.label as NSString).size(withAttributes: [.font: titleFont]).width)
        let value = contributorCompositionSegmentLabel(count: entry.count, percentage: entry.percentage)
        let valueWidth = ceil((value as NSString).size(withAttributes: [.font: valueFont]).width)
        return max(titleWidth, valueWidth) + 12
    }
}

private func collapsedContributorCompositionWhitespace(_ value: String) -> String {
    value
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func isContributorCompositionHonorific(_ value: String) -> Bool {
    let normalized = normalizedContributorCompositionKey(value)
    return [
        "fru",
        "herr",
        "mr",
        "mrs",
        "ms",
        "miss",
        "mister"
    ].contains(normalized)
}

func normalizedContributorCompositionKey(_ value: String) -> String {
    collapsedContributorCompositionWhitespace(value).lowercased()
}

private func contributorCompositionCompactPercentageString(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
}

private func contributorCompositionSegmentLabel(count: Int, percentage: Double) -> String {
    "\(count) (\(contributorCompositionCompactPercentageString(percentage)))"
}

private func contributorCompositionTooltip(
    label: String,
    count: Int,
    percentage: Double,
    contributorNames: [String]
) -> String {
    let header = "\(label): \(contributorCompositionSegmentLabel(count: count, percentage: percentage))"
    guard !contributorNames.isEmpty else { return header }
    return ([header] + contributorNames).joined(separator: "\n")
}

private func calendarMeetingStatisticsHoursText(_ minutes: Int, language: AppLanguage) -> String {
    guard minutes > 0 else { return "0 h" }
    return "\(Int((Double(minutes) / 60).rounded())) h"
}

private func calendarMeetingStatisticsMeetingCountText(_ count: Int, language: AppLanguage) -> String {
    if count == 1 {
        return language.text("1 activity", "1 aktivitet")
    }
    return language.text("\(count) activities", "\(count) aktiviteter")
}

private func calendarMeetingStatisticsGroupTitle(
    title: String,
    minutes: Int,
    count: Int,
    language: AppLanguage
) -> String {
    "\(title) (\(calendarMeetingStatisticsHoursText(minutes, language: language)), \(calendarMeetingStatisticsMeetingCountText(count, language: language)))"
}

private func calendarMeetingStatisticsMissingDurationText(
    _ summary: CalendarMeetingHoursSummary,
    language: AppLanguage
) -> String {
    if language == .swedish {
        let parts = [
            calendarMeetingStatisticsSwedishMissingDurationPart(
                count: summary.completedMeetingsWithoutDurationCount,
                isCompleted: true
            ),
            calendarMeetingStatisticsSwedishMissingDurationPart(
                count: summary.plannedMeetingsWithoutDurationCount,
                isCompleted: false
            ),
        ]
        .compactMap { $0 }
        return "Saknar komplett start- och sluttid: \(parts.joined(separator: ", "))."
    }

    let parts = [
        calendarMeetingStatisticsEnglishMissingDurationPart(
            count: summary.completedMeetingsWithoutDurationCount,
            isCompleted: true
        ),
        calendarMeetingStatisticsEnglishMissingDurationPart(
            count: summary.plannedMeetingsWithoutDurationCount,
            isCompleted: false
        ),
    ]
    .compactMap { $0 }
    return "Missing complete start and end times: \(parts.joined(separator: ", "))."
}

private func calendarMeetingStatisticsSwedishMissingDurationPart(
    count: Int,
    isCompleted: Bool
) -> String? {
    guard count > 0 else { return nil }
    if isCompleted {
        return count == 1 ? "1 genomförd aktivitet" : "\(count) genomförda aktiviteter"
    }
    return count == 1 ? "1 ej genomförd aktivitet" : "\(count) ej genomförda aktiviteter"
}

private func calendarMeetingStatisticsEnglishMissingDurationPart(
    count: Int,
    isCompleted: Bool
) -> String? {
    guard count > 0 else { return nil }
    if isCompleted {
        return count == 1 ? "1 completed activity" : "\(count) completed activities"
    }
    return count == 1 ? "1 not completed activity" : "\(count) not completed activities"
}

private func calendarMeetingStatisticsMeetingTitle(
    _ meeting: CalendarMeetingStatisticsMeeting,
    language: AppLanguage
) -> String {
    meeting.title.trimmedOrNil ?? language.text("Meeting", "Möte")
}

private func calendarMeetingStatisticsMeetingTiming(
    _ meeting: CalendarMeetingStatisticsMeeting,
    language: AppLanguage
) -> String {
    var timing = calendarMeetingStatisticsDateText(meeting.displayDate, language: language)
    if let timeRange = timeRangeText(start: meeting.startTime, end: meeting.endTime).trimmedOrNil {
        timing += " \(timeRange)"
    }
    if let durationMinutes = meeting.durationMinutes {
        timing += " (\(calendarMeetingStatisticsHoursText(durationMinutes, language: language)))"
    }
    return timing
}

private func calendarMeetingStatisticsMeetingModeText(
    _ meeting: CalendarMeetingStatisticsMeeting,
    language: AppLanguage
) -> String {
    guard let rawMode = meeting.meetingMode.trimmedOrNil else {
        return language.text("Not specified", "Ej angivet")
    }
    if let mode = CalendarMeetingMode.allCases.first(where: { mode in
        mode.rawValue.caseInsensitiveCompare(rawMode) == .orderedSame
            || mode.localizedName(language: .swedish).caseInsensitiveCompare(rawMode) == .orderedSame
            || mode.localizedName(language: .english).caseInsensitiveCompare(rawMode) == .orderedSame
    }) {
        return mode.localizedName(language: language)
    }
    return rawMode
}

private func calendarMeetingStatisticsParticipantText(
    _ meeting: CalendarMeetingStatisticsMeeting,
    language: AppLanguage
) -> String {
    let names = meeting.participantNames.compactMap(\.trimmedOrNil)
    guard !names.isEmpty else {
        return language.text("No participants", "Inga medverkande")
    }
    return names.joined(separator: ", ")
}

private func calendarMeetingStatisticsMeetingHelpText(
    _ meeting: CalendarMeetingStatisticsMeeting,
    language: AppLanguage
) -> String {
    [
        calendarMeetingStatisticsMeetingTitle(meeting, language: language),
        calendarMeetingStatisticsMeetingTiming(meeting, language: language),
        calendarMeetingStatisticsMeetingModeText(meeting, language: language),
        calendarMeetingStatisticsParticipantText(meeting, language: language),
    ]
    .compactMap(\.trimmedOrNil)
    .joined(separator: " • ")
}

private func calendarMeetingStatisticsDateText(_ date: Date, language: AppLanguage) -> String {
    // Round 17: shared format; Swedish months stay lowercase ("1 okt. 2026").
    AppTimestampFormatter.dayMonthYear(date, language: language)
}

private func calendarActivityDistributionEntries(
    minutesByLabel: [String: Int],
    colorHexes: [String: CalendarActivityColorHexPair] = [:],
    localizeLabel: (String) -> String
) -> [CalendarActivityDistributionEntry] {
    let totalMinutes = minutesByLabel.values.reduce(0, +)
    guard totalMinutes > 0 else { return [] }
    // Fallback when no colour is chosen in Settings (and for meeting types).
    let palette: [Int] = [0x4A7AB8, 0x6EA6CC, 0xFAB366, 0xD65A4A, 0x6B9E75, 0x8C73B8]
    return minutesByLabel
        .filter { $0.value > 0 }
        .sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return localizeLabel($0.key).localizedStandardCompare(localizeLabel($1.key)) == .orderedAscending
        }
        .enumerated()
        .map { index, item -> CalendarActivityDistributionEntry in
            let fallback = calendarActivityNSColor(hex: palette[index % palette.count])
            let pair = colorHexes[item.key]
            let light = calendarActivityNSColor(hexString: pair?.light) ?? fallback
            let dark = calendarActivityNSColor(hexString: pair?.dark ?? pair?.light) ?? light
            return CalendarActivityDistributionEntry(
                label: localizeLabel(item.key),
                minutes: item.value,
                percentage: Double(item.value) / Double(totalMinutes),
                color: dynamicColor(light: light, dark: dark),
                foreground: dynamicColor(
                    light: calendarActivityContrastingText(on: light),
                    dark: calendarActivityContrastingText(on: dark)
                )
            )
        }
}

private func calendarActivityNSColor(hex: Int) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

private func calendarActivityNSColor(hexString: String?) -> NSColor? {
    guard let raw = hexString?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: ""),
          raw.count == 6,
          let value = Int(raw, radix: 16) else {
        return nil
    }
    return calendarActivityNSColor(hex: value)
}

/// Dark text on light fills and white text on dark fills.
private func calendarActivityContrastingText(on fill: NSColor) -> NSColor {
    guard let srgb = fill.usingColorSpace(.sRGB) else { return NSColor.white }
    let luminance = 0.2126 * srgb.redComponent + 0.7152 * srgb.greenComponent + 0.0722 * srgb.blueComponent
    return luminance > 0.55
        ? NSColor(srgbRed: 0.12, green: 0.14, blue: 0.16, alpha: 1)
        : NSColor(white: 1, alpha: 0.96)
}

private func calendarActivityDistributionPercentageText(_ value: Double) -> String {
    "\(Int((value * 100).rounded())) %"
}

private func contributorCompositionSwatch(rgbHex: Int) -> ContributorCompositionSwatch {
    let red = Double((rgbHex >> 16) & 0xFF) / 255.0
    let green = Double((rgbHex >> 8) & 0xFF) / 255.0
    let blue = Double(rgbHex & 0xFF) / 255.0
    let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    return ContributorCompositionSwatch(
        fill: Color(rgbHex: rgbHex),
        foreground: luminance > 0.62 ? Color.black.opacity(0.82) : Color.white.opacity(0.96)
    )
}

/// Sunken chrome for the inline statistics blocks: a barely-darker recessed
/// fill with an inner shadow.
private struct InlineStatisticsSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                    .fill(
                        dynamicColor(
                            light: NSColor(calibratedWhite: 0.0, alpha: 0.03),
                            dark: NSColor(calibratedWhite: 0.0, alpha: 0.10)
                        )
                    )
                    .overlay(
                        // Approximated inner shadow: a blurred stroke nudged
                        // downward and masked to the shape.
                        RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                            .stroke(Color.black.opacity(0.10), lineWidth: 1.5)
                            .blur(radius: 1.4)
                            .offset(y: 1)
                            .mask(RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                            .stroke(AppPalette.subtleBorder.opacity(0.6), lineWidth: 1)
                    )
            )
    }
}

extension View {
    /// Wraps an inline statistics block in the shared sunken, hover-undimmed
    /// statistics chrome.
    func inlineStatisticsSurface() -> some View {
        modifier(InlineStatisticsSurfaceModifier())
    }
}

/// One compact statistics row: a small title and one thin segmented bar whose
/// segments carry their own label and percentage ("Män (71 %)"). Everything
/// that does not fit inside a segment lives in its hover tooltip, so the row
/// never needs a legend and always stays a single line.
struct CompactStatisticBarRow: View {
    struct Segment: Identifiable {
        let label: String
        let fraction: Double
        let color: Color
        let foregroundColor: Color
        let helpText: String
        /// When set, the segment fills with the app's stats-card gradient
        /// (color → endColor) instead of a flat color.
        var endColor: Color? = nil

        var id: String { label }

        var displayText: String {
            "\(label) (\(Int((fraction * 100).rounded())) %)"
        }
    }

    let title: String
    let segments: [Segment]

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(appFont(.body))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            GeometryReader { geometry in
                let totalFraction = max(segments.reduce(0) { $0 + $1.fraction }, 0.0001)
                HStack(spacing: 1) {
                    ForEach(segments) { segment in
                        // .help needs a plainly hit-testable shape: attach it
                        // to a filled Rectangle (like the popover bars do) and
                        // give it an explicit content shape — a clipped ZStack
                        // rooted in a bare LinearGradient never showed the
                        // tooltip.
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [segment.color, segment.endColor ?? segment.color],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay {
                                Text(segment.displayText)
                                    .font(appFont(.body))
                                    .foregroundStyle(segment.foregroundColor)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .padding(.horizontal, AppPalette.textFieldHorizontalPadding)
                                    .padding(.vertical, AppPalette.textFieldVerticalPadding)
                                    .clipped()
                            }
                            .frame(width: max(5, geometry.size.width * segment.fraction / totalFraction))
                            .contentShape(Rectangle())
                            .help(segment.helpText)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(AppPalette.subtleBorder, lineWidth: 1)
                )
            }
            .frame(height: AppPalette.fieldMinHeight)
        }
    }
}

extension CompactStatisticBarRow.Segment {
    /// Convenience for callers outside this file: builds the segment from an
    /// RGB hex, deriving a readable foreground color from its luminance.
    init(label: String, fraction: Double, rgbHex: Int, helpText: String) {
        let swatch = contributorCompositionSwatch(rgbHex: rgbHex)
        self.init(
            label: label,
            fraction: fraction,
            color: swatch.fill,
            foregroundColor: swatch.foreground,
            helpText: helpText
        )
    }
}

/// Inline contributor composition as compact one-line rows, embedded under
/// the collaborator list in project detail. Hover a segment for the counted
/// people and exact numbers.
struct ContributorCompositionInlineSection: View {
    @ObservedObject var store: GrantDataStore
    let contributorNames: [String]
    let language: AppLanguage

    var body: some View {
        let snapshot = ContributorCompositionSnapshot(
            contributorNames: contributorNames,
            language: language,
            resolveAuthor: { store.publicationAuthor(matchingPresentedName: $0) }
        )
        if snapshot.totalCount > 0 {
            VStack(alignment: .leading, spacing: 4) {
                compactRow(title: language.text("Gender", "Kön"), distribution: snapshot.genderDistribution, snapshot: snapshot)
                compactRow(title: language.text("PhD", "Disputerade"), distribution: snapshot.phdDistribution, snapshot: snapshot)
                compactRow(title: language.text("Career stage", "Karriärsteg"), distribution: snapshot.careerStageDistribution, snapshot: snapshot)
                compactRow(title: language.text("Title", "Titel"), distribution: snapshot.titleDistribution, snapshot: snapshot)
                compactRow(title: language.text("Organization", "Organisation"), distribution: snapshot.organizationDistribution, snapshot: snapshot)
                compactRow(title: language.text("Country", "Land"), distribution: snapshot.countryDistribution, snapshot: snapshot)
            }
            .inlineStatisticsSurface()
        }
    }

    @ViewBuilder
    private func compactRow(
        title: String,
        distribution: [ContributorCompositionDistributionEntry],
        snapshot: ContributorCompositionSnapshot
    ) -> some View {
        let segments = contributorCompositionCompactSegments(
            distribution,
            totalCount: snapshot.totalCount,
            language: language
        )
        if !segments.isEmpty {
            CompactStatisticBarRow(title: title, segments: segments)
        }
    }
}

private func contributorCompositionCompactSegments(
    _ distribution: [ContributorCompositionDistributionEntry],
    totalCount: Int,
    language: AppLanguage
) -> [CompactStatisticBarRow.Segment] {
    guard totalCount > 0 else { return [] }
    return distribution.enumerated().compactMap { index, entry in
        guard entry.count > 0 else { return nil }
        let isMissing = normalizedContributorCompositionKey(entry.label)
            == normalizedContributorCompositionKey(language.text("Missing", "Saknas"))
        let paletteHex = contributorCompositionSharedPaletteHexes[index % contributorCompositionSharedPaletteHexes.count]
        let swatch = contributorCompositionSwatch(rgbHex: isMissing ? 0x7C8590 : paletteHex)
        let percentage = Double(entry.count) / Double(totalCount)
        return CompactStatisticBarRow.Segment(
            label: entry.label,
            fraction: percentage,
            color: swatch.fill,
            foregroundColor: swatch.foreground,
            helpText: contributorCompositionTooltip(
                label: entry.label,
                count: entry.count,
                percentage: percentage,
                contributorNames: entry.contributorNames
            )
        )
    }
}

/// Compact outcome rows for a set of grant applications: the status mix
/// (Väntar svar / Beviljade / Avslagna / Övriga) and the granted total split
/// into spent vs remaining. Renders nothing when the set is empty; used
/// inline in project detail and in the grant editor's Statistik section.
struct GrantOutcomeCompactRows: View {
    @ObservedObject var store: GrantDataStore
    let applications: [GrantApplication]
    let language: AppLanguage
    var title: String? = nil

    var body: some View {
        let relevant = applications.filter { !$0.isToApplyStatus }
        let granted = relevant.filter(\.isGranted)
        let waiting = relevant.filter { $0.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines) == "Väntar svar" }
        let rejected = relevant.filter { $0.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines) == "Avslag" }
        // Round 17: withdrawn applications get their own grey segment.
        let withdrawn = relevant.filter { AppStatusTones.isWithdrawn(resultLabel: $0.resultLabel) }
        let others = relevant.filter { application in
            !application.isGranted
                && !["Väntar svar", "Avslag", "Tillbakadragen"].contains(application.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if !relevant.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if let title {
                    Text(title)
                        .font(appFont(.tableHeader))
                        .padding(.bottom, 2)
                }

                CompactStatisticBarRow(
                    title: language.text("Status", "Status"),
                    segments: [
                        statusSegment(label: ApplicationOutcome.awaitingDecision.heading(language), matching: waiting, total: relevant.count, color: AppPalette.statsCardPendingStart, endColor: AppPalette.statsCardPendingEnd, usesGrantedAmount: false),
                        statusSegment(label: ApplicationOutcome.granted.heading(language), matching: granted, total: relevant.count, color: AppPalette.statsCardGrantedStart, endColor: AppPalette.statsCardGrantedEnd, usesGrantedAmount: true),
                        statusSegment(label: ApplicationOutcome.declined.heading(language), matching: rejected, total: relevant.count, color: AppPalette.statsCardDeclinedStart, endColor: AppPalette.statsCardDeclinedEnd, usesGrantedAmount: false),
                        statusSegment(label: ApplicationOutcome.withdrawn.heading(language), matching: withdrawn, total: relevant.count, color: AppPalette.statusFill(.inactive), endColor: nil, usesGrantedAmount: false),
                        statusSegment(label: language.text("Other", "Övriga"), matching: others, total: relevant.count, color: AppPalette.statusFill(.inactive), endColor: nil, usesGrantedAmount: false),
                    ].compactMap { $0 }
                )

                let grantedSEK = granted.reduce(0.0) { partial, application in
                    partial + store.grantStatisticsAmountInSEK(for: application, amount: application.grantedAmountValue ?? application.appliedAmountValue)
                }
                let spentSEK = granted.reduce(0.0) { partial, application in
                    guard let grantedAmount = application.grantedAmountValue else { return partial }
                    let remaining = store.effectiveRemainingGrantedAmountValue(for: application) ?? grantedAmount
                    return partial + store.grantStatisticsAmountInSEK(for: application, amount: max(0, grantedAmount - remaining))
                }
                if grantedSEK > 0 {
                    let remainingSEK = max(0, grantedSEK - spentSEK)
                    CompactStatisticBarRow(
                        title: language.text("Granted", "Beviljat"),
                        segments: [
                            CompactStatisticBarRow.Segment(
                                label: language.text("Spent", "Utnyttjat"),
                                fraction: spentSEK / grantedSEK,
                                color: AppPalette.statsCardGrantedStart,
                                foregroundColor: AppPalette.semanticOnColor,
                                helpText: "\(language.text("Spent", "Utnyttjat")): \(inlineStatisticsSEKText(spentSEK, language: language))",
                                endColor: AppPalette.statsCardGrantedEnd
                            ),
                            CompactStatisticBarRow.Segment(
                                label: language.text("Remaining", "Kvar"),
                                fraction: remainingSEK / grantedSEK,
                                color: AppPalette.shadeGreen,
                                foregroundColor: AppPalette.semanticOnColor,
                                helpText: "\(language.text("Remaining", "Kvar")): \(inlineStatisticsSEKText(remainingSEK, language: language))"
                            ),
                        ].filter { $0.fraction > 0 }
                    )
                }
            }
            .inlineStatisticsSurface()
        }
    }

    private func statusSegment(
        label: String,
        matching applications: [GrantApplication],
        total: Int,
        color: Color,
        endColor: Color?,
        usesGrantedAmount: Bool
    ) -> CompactStatisticBarRow.Segment? {
        guard !applications.isEmpty, total > 0 else { return nil }
        let amountSEK = applications.reduce(0.0) { partial, application in
            let amount = usesGrantedAmount
                ? (application.grantedAmountValue ?? application.appliedAmountValue)
                : (application.appliedAmountValue ?? application.preferredBudgetAmountValue)
            return partial + store.grantStatisticsAmountInSEK(for: application, amount: amount)
        }
        let countText = applications.count == 1
            ? language.text("1 application", "1 ansökan")
            : language.text("\(applications.count) applications", "\(applications.count) ansökningar")
        var helpText = "\(label): \(countText)"
        if amountSEK > 0 {
            helpText += " · \(inlineStatisticsSEKText(amountSEK, language: language))"
        }
        return CompactStatisticBarRow.Segment(
            label: label,
            fraction: Double(applications.count) / Double(total),
            color: color,
            foregroundColor: AppPalette.semanticOnColor,
            helpText: helpText,
            endColor: endColor
        )
    }
}

func inlineStatisticsSEKText(_ value: Double, language: AppLanguage) -> String {
    // Round 16: shared formatter ("kr" in Swedish, "SEK" in English).
    AmountFormatter.sek(value, language: language)
}

/// Inline activity statistics as compact one-line rows: completed/planned
/// status, activity-type and meeting-type distributions. Hover a segment for
/// hours and exact numbers.
struct CalendarMeetingCompactStatisticsSection: View {
    let summary: CalendarMeetingHoursSummary
    let language: AppLanguage

    @ViewBuilder
    var body: some View {
        if summary.completedMeetingCount + summary.plannedMeetingCount > 0 {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            statusRow

            distributionRow(
                title: language.text("Activity type", "Aktivitetstyp"),
                entries: calendarActivityDistributionEntries(
                    minutesByLabel: summary.activityMinutes,
                    colorHexes: summary.activityColorHexes,
                    localizeLabel: { calendarMeetingCategoryDisplayName($0, language: language) }
                )
            )

            distributionRow(
                title: language.text("Meeting type", "Mötestyp"),
                entries: calendarActivityDistributionEntries(
                    minutesByLabel: summary.meetingModeMinutes,
                    localizeLabel: { rawMode in
                        guard let rawMode = rawMode.trimmedOrNil else {
                            return language.text("Not specified", "Ej angivet")
                        }
                        return CalendarMeetingMode(rawValue: rawMode)?.localizedName(language: language) ?? rawMode
                    }
                )
            )

            if summary.meetingsWithoutDurationCount > 0 {
                Text(calendarMeetingStatisticsMissingDurationText(summary, language: language))
                    .font(appFont(.secondary))
                    .foregroundStyle(.secondary)
            }
        }
        .inlineStatisticsSurface()
    }

    @ViewBuilder
    private var statusRow: some View {
        let total = summary.completedMeetingCount + summary.plannedMeetingCount
        if total > 0 {
            CompactStatisticBarRow(
                title: language.text("Status", "Status"),
                segments: [
                    CompactStatisticBarRow.Segment(
                        label: language.text("Completed", "Genomförda"),
                        fraction: Double(summary.completedMeetingCount) / Double(total),
                        // Round 17: completed = done (green); planned has no
                        // status yet = no fill (the bar's border shows it).
                        color: AppPalette.statusFill(.done),
                        foregroundColor: AppPalette.statusOnFill,
                        helpText: "\(language.text("Completed", "Genomförda")): \(calendarMeetingStatisticsMeetingCountText(summary.completedMeetingCount, language: language)) · \(calendarMeetingStatisticsHoursText(summary.completedMinutes, language: language))"
                    ),
                    CompactStatisticBarRow.Segment(
                        label: language.text("Planned", "Planerade"),
                        fraction: Double(summary.plannedMeetingCount) / Double(total),
                        color: AppPalette.fieldSurface,
                        foregroundColor: AppPalette.appText,
                        helpText: "\(language.text("Planned", "Planerade")): \(calendarMeetingStatisticsMeetingCountText(summary.plannedMeetingCount, language: language)) · \(calendarMeetingStatisticsHoursText(summary.plannedMinutes, language: language))"
                    ),
                ].filter { $0.fraction > 0 }
            )
        }
    }

    @ViewBuilder
    private func distributionRow(title: String, entries: [CalendarActivityDistributionEntry]) -> some View {
        if !entries.isEmpty {
            CompactStatisticBarRow(
                title: title,
                segments: entries.map { entry in
                    CompactStatisticBarRow.Segment(
                        label: entry.label,
                        fraction: entry.percentage,
                        color: entry.color,
                        foregroundColor: entry.foreground,
                        helpText: "\(entry.label): \(calendarMeetingStatisticsHoursText(entry.minutes, language: language)) (\(calendarActivityDistributionPercentageText(entry.percentage)))"
                    )
                }
            )
        }
    }
}
