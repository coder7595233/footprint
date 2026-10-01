import SwiftUI

struct OrganizationDetailHeader: View {
    @Binding var nameSv: String
    @Binding var nameEn: String
    let language: AppLanguage
    let websiteDestinationURL: URL?
    let deleteAction: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                AppInlineTitleTextField(
                    placeholder: language == .swedish ? language.text("Swedish name", "Svenskt namn") : language.text("English name", "Engelskt namn"),
                    text: language == .swedish ? $nameSv : $nameEn,
                    font: appNSFont(.pageTitle),
                    minHeight: 30
                )

                AppInlineTitleTextField(
                    placeholder: language == .swedish ? language.text("English name", "Engelskt namn") : language.text("Swedish name", "Svenskt namn"),
                    text: language == .swedish ? $nameEn : $nameSv,
                    font: appNSFont(.body),
                    textColor: .secondaryLabelColor,
                    minHeight: 18
                )
            }
            Spacer()
            if let websiteDestinationURL {
                AppDestinationURLLink(
                    kind: .web,
                    language: language,
                    destination: websiteDestinationURL,
                    fontSize: 12,
                    showsTitle: true
                )
            }
            DeleteActionButton(
                title: language.text("Delete", "Ta bort"),
                cancelTitle: language.text("Cancel", "Avbryt"),
                action: deleteAction
            )
        }
        .padding(.bottom, 2)
    }
}

struct OrganizationGrantDashboardPanel: View {
    enum Mode {
        case fundManager
        case grantProvider
    }

    @ObservedObject var store: GrantDataStore
    let title: String
    let mode: Mode
    @Binding var isExpanded: Bool
    let showDeferredContent: Bool
    let applications: [GrantApplication]
    let displayedApplications: [GrantApplication]
    let language: AppLanguage
    let dashboardTitle: String
    let placeholderTitle: String
    var scopeLabel: String? = nil
    let segmentTapAction: (GrantOutcomeSegmentKind) -> Void
    let openApplication: (GrantApplication) -> Void

    @State private var sortColumn: OrganizationGrantApplicationSortColumn = .decision
    @State private var sortAscending = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CollapsibleSectionHeader(title: title, isExpanded: $isExpanded)

            if isExpanded {
                if showDeferredContent {
                    OrganizationCompactGrantStatsRow(
                        store: store,
                        applications: applications,
                        language: language,
                        segmentTapAction: segmentTapAction
                    )

                    if let scopeLabel {
                        HStack(spacing: 8) {
                            Text(language.text("Scope:", "Nivå:"))
                                .font(appFont(.panelTitle).weight(.bold))
                            Text(scopeLabel)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }

                    OrganizationCompactGrantApplicationsTable(
                        store: store,
                        mode: mode,
                        title: dashboardTitle,
                        applications: displayedApplications,
                        language: language,
                        sortColumn: $sortColumn,
                        sortAscending: $sortAscending,
                        openApplication: openApplication
                    )
                } else {
                    OrganizationDeferredPanelPlaceholder(title: placeholderTitle)
                }
            }
        }
    }
}

private enum OrganizationGrantApplicationSortColumn: Hashable {
    case status
    case project
    case provider
    case manager
    case grant
    case decision
    case amount

    var defaultAscending: Bool {
        switch self {
        case .amount:
            return false
        case .status, .project, .provider, .manager, .grant, .decision:
            return true
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .status:
            return language.text("Status", "Status")
        case .project:
            return language.text("Project", "Projekt")
        case .provider:
            return language.text("Grant provider", "Anslagsgivare")
        case .manager:
            return language.text("Fund manager", "Medelsförvaltare")
        case .grant:
            return language.text("Grant", "Anslag")
        case .decision:
            return language.text("Decision", "Beslut")
        case .amount:
            return language.text("Amount", "Summa")
        }
    }
}

private struct OrganizationCompactGrantStatsSegment: Identifiable {
    let kind: GrantOutcomeSegmentKind
    let applications: [GrantApplication]
    let amount: Double
    let percentage: Int
    let text: String
    let hoverText: String

    var id: GrantOutcomeSegmentKind { kind }
}

private struct OrganizationCompactGrantStatsRow: View {
    @ObservedObject var store: GrantDataStore
    let applications: [GrantApplication]
    let language: AppLanguage
    let segmentTapAction: (GrantOutcomeSegmentKind) -> Void

    private var segments: [OrganizationCompactGrantStatsSegment] {
        let relevant = applications.filter { !$0.isToApplyStatus }
        let rejected = relevant.filter {
            let status = $0.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            return status == "Avslag" || status == "Tillbakadragen"
        }
        let waiting = relevant.filter { $0.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines) == "Väntar svar" }
        let granted = relevant.filter(\.isGranted)
        let buckets: [(GrantOutcomeSegmentKind, [GrantApplication])] = [
            (.rejected, rejected),
            (.waiting, waiting),
            (.granted, granted)
        ]
        let amountsByKind = Dictionary(firstWinsKeysWithValues: buckets.map { kind, rows in
            (kind, rows.reduce(0) { $0 + statsAmount(for: $1, kind: kind) })
        })
        let total = amountsByKind.values.reduce(0, +)

        return buckets.compactMap { kind, rows in
            guard !rows.isEmpty else { return nil }
            let amount = amountsByKind[kind] ?? 0
            let percentage = total > 0 ? Int((amount / total * 100).rounded()) : 0
            return OrganizationCompactGrantStatsSegment(
                kind: kind,
                applications: rows,
                amount: amount,
                percentage: percentage,
                text: segmentText(amount: amount, percentage: percentage),
                hoverText: hoverText(for: rows, kind: kind, amount: amount, percentage: percentage)
            )
        }
    }

    var body: some View {
        if segments.isEmpty {
            AppCompactEmptyListLabel(title: language.text("No submitted, declined or granted applications yet", "Inga ansökta, avslagna eller beviljade anslag än"))
        } else {
            HStack(spacing: 8) {
                ForEach(segments) { segment in
                    Button(action: { segmentTapAction(segment.kind) }) {
                        Text(segment.text)
                            .font(appFont(.body).weight(.bold))
                            .foregroundStyle(AppPalette.semanticOnColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                LinearGradient(
                                    colors: [segment.kind.startColor, segment.kind.endColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous)
                                    .stroke(AppPalette.border.opacity(0.5), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: AppPalette.smallCornerRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(segment.hoverText)
                }
            }
        }
    }

    private func statsAmount(for application: GrantApplication, kind: GrantOutcomeSegmentKind) -> Double {
        let amount: Double?
        switch kind {
        case .rejected, .waiting:
            amount = application.appliedAmountValue ?? application.preferredBudgetAmountValue
        case .granted:
            amount = application.grantedAmountValue ?? application.appliedAmountValue
        }
        return store.grantStatisticsAmountInSEK(for: application, amount: amount)
    }

    private func segmentText(amount: Double, percentage: Int) -> String {
        "\(CurrencyFormatter.format(amount, code: "SEK", language: language)) (\(percentage) %)"
    }

    private func hoverText(
        for applications: [GrantApplication],
        kind: GrantOutcomeSegmentKind,
        amount: Double,
        percentage: Int
    ) -> String {
        var lines = [
            kind.title(language: language),
            segmentText(amount: amount, percentage: percentage)
        ]

        if kind == .granted, let remainingText = aggregateRemainingText(for: applications) {
            lines.append(remainingText)
        }

        lines.append(language.text("Included grants:", "Anslag som ingår:"))
        lines += applications
            .sorted { compactGrantTitle($0).localizedStandardCompare(compactGrantTitle($1)) == .orderedAscending }
            .map { application in
                let line = [
                    compactProjectTitle(application),
                    compactProviderTitle(application),
                    compactGrantTitle(application),
                    rowAmountText(for: application)
                ]
                .compactMap { $0.nonEmpty }
                .joined(separator: " · ")
                return "- \(line)"
            }

        return lines.joined(separator: "\n")
    }

    private func aggregateRemainingText(for applications: [GrantApplication]) -> String? {
        let rows = applications.filter { store.effectiveRemainingGrantedAmountValue(for: $0) != nil }
        guard !rows.isEmpty else { return nil }
        let total = rows.reduce(0) {
            $0 + store.grantStatisticsAmountInSEK(
                for: $1,
                amount: store.effectiveRemainingGrantedAmountValue(for: $1)
            )
        }
        let amount = CurrencyFormatter.format(total, code: "SEK", language: language)
            + store.unconvertedAmountSuffix(for: rows.map { ($0, store.effectiveRemainingGrantedAmountValue(for: $0)) })
        return language.text("Of which \(amount) remains.", "Varav \(amount) kvarvarande medel.")
    }

    private func compactProjectTitle(_ application: GrantApplication) -> String {
        store.projectLabel(for: application, language: language)
            ?? language.text("No project", "Saknar projekt")
    }

    private func compactProviderTitle(_ application: GrantApplication) -> String {
        store.organizationLabel(for: application, language: language)
    }

    private func compactGrantTitle(_ application: GrantApplication) -> String {
        store.localizedGrantName(for: application, language: language).nonEmpty
            ?? language.text("Untitled grant", "Namnlöst anslag")
    }

    private func rowAmountText(for application: GrantApplication) -> String {
        store.formattedGrantAmountWithSEKApproximation(rowAmountValue(for: application), for: application)
    }

    private func rowAmountValue(for application: GrantApplication) -> Double? {
        if application.isToApplyStatus {
            return application.maximumTotalAmountValue
                ?? application.maximumAmountValue
                ?? application.approximateAmountValue
        }
        return application.appliedAmountValue ?? application.preferredBudgetAmountValue
    }
}

private struct OrganizationCompactGrantApplicationRow: Identifiable {
    let application: GrantApplication
    let status: String
    let statusRank: Int
    let project: String
    let provider: String
    let manager: String
    let grant: String
    let decisionText: String
    let decisionSortDate: Date?
    let amountText: String
    let amountSortValue: Double
    let isCurrentUserFirstApplicant: Bool

    var id: String { application.id }
}

private struct OrganizationCompactGrantApplicationsTable: View {
    @ObservedObject var store: GrantDataStore
    let mode: OrganizationGrantDashboardPanel.Mode
    let title: String
    let applications: [GrantApplication]
    let language: AppLanguage
    @Binding var sortColumn: OrganizationGrantApplicationSortColumn
    @Binding var sortAscending: Bool
    let openApplication: (GrantApplication) -> Void

    private let statusWidth: CGFloat = 112
    private let projectWidth: CGFloat = 170
    private let organizationWidth: CGFloat = 190
    private let grantMinWidth: CGFloat = 350
    private let decisionWidth: CGFloat = 86
    private let amountWidth: CGFloat = 170

    private var organizationColumn: OrganizationGrantApplicationSortColumn {
        mode == .grantProvider ? .manager : .provider
    }

    private var contentMinWidth: CGFloat {
        statusWidth + projectWidth + organizationWidth + grantMinWidth + decisionWidth + amountWidth
    }

    private var rows: [OrganizationCompactGrantApplicationRow] {
        applications.map(makeRow).sorted(by: rowSortOrder)
    }

    var body: some View {
        AppCompactReferenceTable(
            title: title,
            isEmpty: rows.isEmpty,
            emptyTitle: language.text("No records", "Inga poster"),
            contentMinWidth: contentMinWidth
        ) {
            headerRow
        } rows: {
            ForEach(rows) { row in
                AppCompactReferenceRowButton(action: { openApplication(row.application) }) {
                    applicationRow(row)
                }
                .help(hoverText(for: row))
                if row.id != rows.last?.id {
                    Divider()
                        .overlay(AppPalette.subtleBorder)
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            headerCell(.status, width: statusWidth)
            headerCell(.project, width: projectWidth)
            headerCell(organizationColumn, width: organizationWidth)
            headerCell(.grant, width: nil, minWidth: grantMinWidth, maxWidth: .infinity)
            headerCell(.decision, width: decisionWidth)
            headerCell(.amount, width: amountWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    private func applicationRow(_ row: OrganizationCompactGrantApplicationRow) -> some View {
        HStack(spacing: 0) {
            statusBadge(for: row)
                .frame(width: statusWidth, alignment: .leading)
            tableText(row.project, width: projectWidth)
            tableText(organizationText(for: row), width: organizationWidth)
            tableText(row.grant, width: nil, minWidth: grantMinWidth, maxWidth: .infinity)
            tableText(row.decisionText, width: decisionWidth)
            tableText(row.amountText, width: amountWidth, alignment: .trailing, weight: .semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(appFont(.secondary))
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .italic(!row.isCurrentUserFirstApplicant)
    }

    private func statusBadge(for row: OrganizationCompactGrantApplicationRow) -> some View {
        let colors = statusBadgeColors(for: row.application)
        return AppToneBadge(
            text: row.status,
            size: .compact,
            foreground: colors.foreground,
            background: colors.background,
            stroke: colors.stroke,
            horizontalPadding: 6,
            verticalPadding: 1
        )
    }

    private func headerCell(
        _ column: OrganizationGrantApplicationSortColumn,
        width: CGFloat?,
        minWidth: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        alignment: Alignment = .leading
    ) -> some View {
        AppSortableListHeader(
            title: column.title(language: language),
            ascending: sortColumn == column ? sortAscending : nil,
            width: width,
            minWidth: minWidth,
            maxWidth: maxWidth,
            alignment: alignment,
            resetTitle: language.text("Reset", "Återställ"),
            onToggle: { toggleSort(column) }
        )
    }

    private func tableText(
        _ text: String,
        width: CGFloat?,
        minWidth: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        alignment: Alignment = .leading,
        weight: Font.Weight = .regular
    ) -> some View {
        Text(text)
            .font(appFont(.secondary).weight(weight))
            .foregroundStyle(AppPalette.appText)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: alignment)
            .frame(minWidth: minWidth, maxWidth: maxWidth, alignment: alignment)
    }

    private func toggleSort(_ column: OrganizationGrantApplicationSortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = column.defaultAscending
        }
    }

    private func makeRow(_ application: GrantApplication) -> OrganizationCompactGrantApplicationRow {
        let amountValue = rowAmountValue(for: application)
        let decision = decisionDate(for: application)
        return OrganizationCompactGrantApplicationRow(
            application: application,
            status: language.localizedStatus(application.resultLabel),
            statusRank: statusRank(for: application),
            project: store.projectLabel(for: application, language: language)
                ?? language.text("No project", "Saknar projekt"),
            provider: store.organizationLabel(for: application, language: language),
            manager: store.managerLabel(for: application, language: language) ?? "—",
            grant: store.localizedGrantName(for: application, language: language).nonEmpty
                ?? language.text("Untitled grant", "Namnlöst anslag"),
            decisionText: decisionText(for: application, decision: decision),
            decisionSortDate: decision,
            amountText: store.formattedGrantAmountWithSEKApproximation(amountValue, for: application),
            amountSortValue: store.grantStatisticsAmountInSEK(for: application, amount: amountValue),
            isCurrentUserFirstApplicant: store.isCurrentUserFirstApplicant(application)
        )
    }

    private func statusRank(for application: GrantApplication) -> Int {
        let status = application.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if application.isToApplyStatus {
            return 0
        }
        if status == "Väntar svar" {
            return 1
        }
        if application.isGranted {
            return 2
        }
        if status == "Avslag" || status == "Tillbakadragen" {
            return 3
        }
        return 4
    }

    private func rowAmountValue(for application: GrantApplication) -> Double? {
        if application.isToApplyStatus {
            return application.maximumTotalAmountValue
                ?? application.maximumAmountValue
                ?? application.approximateAmountValue
        }
        return application.appliedAmountValue ?? application.preferredBudgetAmountValue
    }

    private func rowSortOrder(_ lhs: OrganizationCompactGrantApplicationRow, _ rhs: OrganizationCompactGrantApplicationRow) -> Bool {
        let comparison: ComparisonResult
        switch sortColumn {
        case .status:
            if lhs.statusRank != rhs.statusRank {
                return sortAscending ? lhs.statusRank < rhs.statusRank : lhs.statusRank > rhs.statusRank
            }
            comparison = lhs.status.localizedStandardCompare(rhs.status)
        case .project:
            comparison = lhs.project.localizedStandardCompare(rhs.project)
        case .provider:
            comparison = lhs.provider.localizedStandardCompare(rhs.provider)
        case .manager:
            comparison = lhs.manager.localizedStandardCompare(rhs.manager)
        case .grant:
            comparison = lhs.grant.localizedStandardCompare(rhs.grant)
        case .decision:
            if lhs.decisionSortDate != rhs.decisionSortDate {
                switch (lhs.decisionSortDate, rhs.decisionSortDate) {
                case let (.some(left), .some(right)):
                    return sortAscending ? left < right : left > right
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    break
                }
            }
            comparison = lhs.decisionText.localizedStandardCompare(rhs.decisionText)
        case .amount:
            if lhs.amountSortValue != rhs.amountSortValue {
                return sortAscending ? lhs.amountSortValue < rhs.amountSortValue : lhs.amountSortValue > rhs.amountSortValue
            }
            comparison = lhs.grant.localizedStandardCompare(rhs.grant)
        }

        if comparison == .orderedSame {
            return lhs.grant.localizedStandardCompare(rhs.grant) == .orderedAscending
        }
        return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
    }

    private func hoverText(for row: OrganizationCompactGrantApplicationRow) -> String {
        var lines = [
            row.status,
            row.project,
            row.provider,
            row.manager,
            row.grant,
            "\(decisionLabel(for: row.application)): \(row.decisionText)",
            row.amountText
        ]
        if !row.isCurrentUserFirstApplicant {
            lines.append(language.text("You are not main applicant", "Du är inte huvudsökande"))
        }
        if row.application.isGranted {
            let remaining = store.formattedGrantAmountWithSEKApproximation(
                store.effectiveRemainingGrantedAmountValue(for: row.application),
                for: row.application
            )
            lines.append("\(language.text("Remaining", "Kvar")): \(remaining)")
        }
        return lines.joined(separator: "\n")
    }

    private func decisionDate(for application: GrantApplication) -> Date? {
        if isAwaitingDecision(application) {
            return application.decisionExpectedDate
        }
        return application.decisionDate
    }

    private func decisionText(for application: GrantApplication, decision: Date?) -> String {
        if isAwaitingDecision(application) {
            return application.decisionExpectedOn?.nonEmpty ?? formattedDecisionDate(decision)
        }
        return application.resolvedDecisionDateString?.nonEmpty ?? formattedDecisionDate(decision)
    }

    private func formattedDecisionDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return DateParsers.isoDay.string(from: date)
    }

    private func decisionLabel(for application: GrantApplication) -> String {
        isAwaitingDecision(application)
            ? language.text("Decision expected", "Beslut väntas")
            : language.text("Decision", "Beslut")
    }

    private func isAwaitingDecision(_ application: GrantApplication) -> Bool {
        application.resultLabel.trimmingCharacters(in: .whitespacesAndNewlines) == "Väntar svar"
    }

    private func organizationText(for row: OrganizationCompactGrantApplicationRow) -> String {
        mode == .grantProvider ? row.manager : row.provider
    }

    private func statusBadgeColors(for application: GrantApplication) -> (foreground: Color, background: Color, stroke: Color) {
        // Round 16: the shared application status tones.
        let colors = AppBadgeColors.status(store.applicationStatusTone(application))
        return (foreground: colors.foreground, background: colors.background, stroke: colors.stroke)
    }
}

struct OrganizationLinkedResearcherRow: Identifiable, Equatable {
    let author: PublicationAuthor
    let subtitle: String
    let projectCount: Int
    let grantCount: Int
    let publicationCount: Int

    var id: String { author.id }
}

private enum OrganizationLinkedResearcherSortColumn: Hashable {
    case name
    case position
    case careerStage
    case projectCount
    case grantCount
    case publicationCount

    var defaultAscending: Bool {
        switch self {
        case .name, .position, .careerStage:
            return true
        case .projectCount, .grantCount, .publicationCount:
            return false
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .name:
            return language.text("Name", "Namn")
        case .position:
            return language.text("Position", "Position")
        case .careerStage:
            return language.text("Career stage", "Karriärsteg")
        case .projectCount:
            return language.text("Projects", "Projekt")
        case .grantCount:
            return language.text("Grants", "Anslag")
        case .publicationCount:
            return language.text("Publications", "Publikationer")
        }
    }
}

struct OrganizationLinkedResearchersPanel: View {
    let researchers: [OrganizationLinkedResearcherRow]
    let language: AppLanguage
    let openResearcher: (PublicationAuthor) -> Void

    @State private var sortColumn: OrganizationLinkedResearcherSortColumn = .name
    @State private var sortAscending = true

    private let nameWidth: CGFloat = 190
    private let positionWidth: CGFloat = 170
    private let careerStageWidth: CGFloat = 92
    private let projectCountWidth: CGFloat = 74
    private let grantCountWidth: CGFloat = 74
    private let publicationCountWidth: CGFloat = 108

    private var sortedResearchers: [OrganizationLinkedResearcherRow] {
        researchers.sorted(by: rowSortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.text("Linked researchers", "Kopplade forskare"))
                .appTypography(.sectionTitle)
                .foregroundStyle(AppPalette.appText)
                .padding(.top, AppRuntime.usesRenewedChrome ? 8 : 5)

            AppCompactReferenceTable(
                isEmpty: researchers.isEmpty,
                emptyTitle: language.text("No records", "Inga poster"),
                contentMinWidth: nameWidth
                    + positionWidth
                    + careerStageWidth
                    + projectCountWidth
                    + grantCountWidth
                    + publicationCountWidth
            ) {
                headerRow
            } rows: {
                ForEach(sortedResearchers) { row in
                    AppCompactReferenceRowButton(action: { openResearcher(row.author) }) {
                        researcherRow(row)
                    }
                    .help(hoverText(for: row))

                    if row.id != sortedResearchers.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            headerCell(.name, width: nameWidth)
            headerCell(.position, width: positionWidth)
            headerCell(.careerStage, width: careerStageWidth)
            headerCell(.projectCount, width: projectCountWidth, alignment: .trailing)
            headerCell(.grantCount, width: grantCountWidth, alignment: .trailing)
            headerCell(.publicationCount, width: publicationCountWidth, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func researcherRow(_ row: OrganizationLinkedResearcherRow) -> some View {
        HStack(spacing: 0) {
            tableText(row.author.displayName, width: nameWidth)
            tableText(positionText(for: row), width: positionWidth)
            tableText(careerStageText(for: row), width: careerStageWidth)
            tableText("\(row.projectCount)", width: projectCountWidth, alignment: .trailing, weight: .semibold)
            tableText("\(row.grantCount)", width: grantCountWidth, alignment: .trailing, weight: .semibold)
            tableText("\(row.publicationCount)", width: publicationCountWidth, alignment: .trailing, weight: .semibold)
        }
        .font(appFont(.secondary))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private func headerCell(
        _ column: OrganizationLinkedResearcherSortColumn,
        width: CGFloat,
        alignment: Alignment = .leading
    ) -> some View {
        AppSortableListHeader(
            title: column.title(language: language),
            ascending: sortColumn == column ? sortAscending : nil,
            width: width,
            alignment: alignment,
            resetTitle: language.text("Reset", "Återställ"),
            onToggle: { toggleSort(column) }
        )
    }

    private func tableText(
        _ text: String,
        width: CGFloat,
        alignment: Alignment = .leading,
        weight: Font.Weight = .regular
    ) -> some View {
        Text(text)
            .font(appFont(.secondary).weight(weight))
            .foregroundStyle(AppPalette.appText)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: alignment)
    }

    private func toggleSort(_ column: OrganizationLinkedResearcherSortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = column.defaultAscending
        }
    }

    private func rowSortOrder(_ lhs: OrganizationLinkedResearcherRow, _ rhs: OrganizationLinkedResearcherRow) -> Bool {
        let comparison: ComparisonResult
        switch sortColumn {
        case .name:
            comparison = lhs.author.sortName.localizedStandardCompare(rhs.author.sortName)
        case .position:
            if positionValue(for: lhs) != positionValue(for: rhs) {
                switch (positionValue(for: lhs), positionValue(for: rhs)) {
                case let (.some(left), .some(right)):
                    return sortAscending
                        ? left.localizedStandardCompare(right) == .orderedAscending
                        : left.localizedStandardCompare(right) == .orderedDescending
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    break
                }
            }
            comparison = lhs.author.sortName.localizedStandardCompare(rhs.author.sortName)
        case .careerStage:
            if careerStageSortRank(for: lhs) != careerStageSortRank(for: rhs) {
                return sortAscending
                    ? careerStageSortRank(for: lhs) < careerStageSortRank(for: rhs)
                    : careerStageSortRank(for: lhs) > careerStageSortRank(for: rhs)
            }
            comparison = careerStageText(for: lhs).localizedStandardCompare(careerStageText(for: rhs))
        case .projectCount:
            if lhs.projectCount != rhs.projectCount {
                return sortAscending ? lhs.projectCount < rhs.projectCount : lhs.projectCount > rhs.projectCount
            }
            comparison = lhs.author.sortName.localizedStandardCompare(rhs.author.sortName)
        case .grantCount:
            if lhs.grantCount != rhs.grantCount {
                return sortAscending ? lhs.grantCount < rhs.grantCount : lhs.grantCount > rhs.grantCount
            }
            comparison = lhs.author.sortName.localizedStandardCompare(rhs.author.sortName)
        case .publicationCount:
            if lhs.publicationCount != rhs.publicationCount {
                return sortAscending ? lhs.publicationCount < rhs.publicationCount : lhs.publicationCount > rhs.publicationCount
            }
            comparison = lhs.author.sortName.localizedStandardCompare(rhs.author.sortName)
        }

        if comparison == .orderedSame {
            return lhs.author.sortName.localizedStandardCompare(rhs.author.sortName) == .orderedAscending
        }
        return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
    }

    private func positionText(for row: OrganizationLinkedResearcherRow) -> String {
        positionValue(for: row) ?? "—"
    }

    private func positionValue(for row: OrganizationLinkedResearcherRow) -> String? {
        row.author.localizedPosition(language: language).nonEmpty
    }

    private func careerStageText(for row: OrganizationLinkedResearcherRow) -> String {
        row.author.careerStage.rawValue
    }

    private func careerStageSortRank(for row: OrganizationLinkedResearcherRow) -> Int {
        switch row.author.careerStage {
        case .categoryA:
            return 0
        case .categoryB:
            return 1
        case .categoryC:
            return 2
        case .categoryD:
            return 3
        }
    }

    private func hoverText(for row: OrganizationLinkedResearcherRow) -> String {
        var lines = [
            row.author.displayName,
            "\(language.text("Position", "Position")): \(positionText(for: row))",
            "\(language.text("Career stage", "Karriärsteg")): \(careerStageText(for: row))",
            "\(language.text("Projects", "Projekt")): \(row.projectCount)",
            "\(language.text("Grants", "Anslag")): \(row.grantCount)",
            "\(language.text("Publications", "Publikationer")): \(row.publicationCount)"
        ]
        if let subtitle = row.subtitle.nonEmpty {
            lines.append("\(language.text("Relation", "Relation")): \(subtitle)")
        }
        return lines.joined(separator: "\n")
    }
}

struct OrganizationDeferredPanelPlaceholder: View {
    let title: String

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(AppPalette.sidebarPanelSurface.opacity(0.55))
            .frame(height: 120)
            .overlay(
                ProgressView(title)
                    .controlSize(.small)
            )
    }
}

// MARK: - Grant provider: OH rule (round 8)

/// Label of an "OH-regel" choice.
func funderOverheadRuleKindLabel(_ kind: FunderOverheadRuleKind, language: AppLanguage) -> String {
    switch kind {
    case .managerFull:
        return language.text("Fund manager's full OH", "Förvaltarens fulla OH")
    case .cap:
        return language.text("At most … %", "Högst … %")
    case .noOverhead:
        return language.text("No OH", "Ingen OH")
    }
}

/// Round 10: the grant provider's OH as one number, "Godkänd OH, högst"
/// (100 = full, 0 = none; stored as the OH rule), the note "Taket inkluderar
/// lokalkostnad", exceptions for single fund managers, and "Prioriterad
/// förvaltare". All are defaults copied into new records. Everything is
/// saved on the organization as soon as it is changed.
struct OrganizationOverheadRuleSection: View {
    @ObservedObject var store: GrantDataStore
    let organizationID: String
    let language: AppLanguage

    private let percentFieldWidth: CGFloat = 110
    private let managerPickerWidth: CGFloat = 240
    private let deleteActionWidth: CGFloat = 18

    private var organization: OrganizationRecord? {
        store.organization(id: organizationID)
    }

    private var rule: FunderOverheadRule {
        organization?.overheadRule ?? FunderOverheadRule()
    }

    private var exceptions: [FunderOverheadRuleException] {
        organization?.overheadRuleExceptions ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppFieldLabelText(
                text: language.text("Approved OH, at most (%)", "Godkänd OH, högst (%)"),
                help: language.text(
                    "The highest overhead (OH) this grant provider accepts on the money it grants. 100 = full OH, 0 = no OH.",
                    "Den högsta overhead (OH) som den här anslagsgivaren godkänner på medlen den beviljar. 100 = full OH, 0 = ingen OH."
                )
            )
            HStack(alignment: .center, spacing: 10) {
                percentField(text: approvedMaxBinding, placeholder: "100")
                if let percent = rule.approvedMaxPercent, percent > 0, percent < 100 {
                    Toggle(
                        language.text("The cap includes premises costs", "Taket inkluderar lokalkostnad"),
                        isOn: premisesBinding
                    )
                    .appCheckboxStyle()
                }
                Spacer(minLength: 0)
            }

            AppFieldLabelText(text: language.text("Exceptions per fund manager", "Undantag per medelsförvaltare"))
            ForEach(exceptions) { exception in
                exceptionRow(exceptionID: exception.id)
            }
            Button(language.text("Add exception", "Lägg till undantag")) {
                addException()
            }
            .buttonStyle(.borderless)

            AppFieldLabelText(
                text: language.text("Preferred fund manager", "Prioriterad förvaltare"),
                help: language.text(
                    "The fund manager chosen for new records to this grant provider. When a region is the only allowed fund manager, choose the region here.",
                    "Den medelsförvaltare som väljs för nya poster hos den här anslagsgivaren. När bara en region får förvalta väljer du regionen här."
                )
            )
            preferredManagerPicker

            SettingsEffectNote(language.text(
                "Affects: new records under Calls and grants. When the grant provider or the fund manager is chosen in a record, these values are copied into it and can be changed there. A later change here never changes existing records. An exception applies only when that fund manager manages the record. \"The cap includes premises costs\" is a note only. When the fund manager takes more OH than the grant provider accepts, the record shows the co-funding question.",
                "Påverkar: nya poster under Utlysningar och anslag. När anslagsgivaren eller förvaltaren väljs i en post kopieras värdena in i posten och kan ändras där. En senare ändring här ändrar aldrig befintliga poster. Ett undantag gäller bara när just den medelsförvaltaren förvaltar posten. \"Taket inkluderar lokalkostnad\" är bara en anteckning. När förvaltaren tar ut mer OH än anslagsgivaren godkänner visar posten frågan om samfinansiering."
            ))
        }
    }

    private var preferredManagerPicker: some View {
        let selectedID = organization?.preferredFundManagerID ?? ""
        return Picker("", selection: Binding(
            get: { selectedID },
            set: { _ = store.setOrganizationPreferredFundManager(organizationID: organizationID, managerID: $0) }
        )) {
            Text(language.text("Default (from Settings)", "Förval (från Inställningar)")).tag("")
            ForEach(managerOptions(including: selectedID), id: \.id) { option in
                Text(option.label).tag(option.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: managerPickerWidth)
    }

    // MARK: Rows

    @ViewBuilder
    private func exceptionRow(exceptionID: String) -> some View {
        if exceptions.contains(where: { $0.id == exceptionID }) {
            HStack(alignment: .center, spacing: 10) {
                Text(language.text("When", "När"))
                    .appTypography(.body)
                managerPicker(selection: exceptionManagerBinding(exceptionID: exceptionID))
                Text(language.text("manages, at most:", "förvaltar, högst:"))
                    .appTypography(.body)
                percentField(text: exceptionApprovedMaxBinding(exceptionID: exceptionID), placeholder: "100")
                AppIconDeleteButton(
                    title: language.text("Delete exception", "Ta bort undantaget"),
                    width: deleteActionWidth,
                    cancelTitle: language.text("Cancel", "Avbryt"),
                    confirmationTitle: language.text("Delete exception?", "Ta bort undantaget?")
                ) {
                    removeException(exceptionID: exceptionID)
                }
                .frame(height: AppPalette.fieldMinHeight)
                Spacer(minLength: 0)
            }
        }
    }

    private func managerPicker(selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            Text(language.text("Select fund manager", "Välj medelsförvaltare")).tag("")
            ForEach(managerOptions(including: selection.wrappedValue), id: \.id) { option in
                Text(option.label).tag(option.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: managerPickerWidth)
    }

    private func percentField(text: Binding<String>, placeholder: String? = nil) -> some View {
        CommitFormattingTextField(
            placeholder: placeholder ?? language.text("Percent", "Procent"),
            text: text,
            formatter: formatOverheadPercentInput,
            updatesContinuously: false
        )
        .appTextInputChrome()
        .frame(width: percentFieldWidth, alignment: .leading)
    }

    private struct ManagerOptionRow {
        let id: String
        let label: String
    }

    /// The organizations with the role fund manager, found by id. A chosen
    /// organization that no longer has the role is still listed so the row
    /// keeps showing it.
    private func managerOptions(including selectedID: String) -> [ManagerOptionRow] {
        var rows = store.fundManagerOrganizations.map {
            ManagerOptionRow(id: $0.id, label: $0.displayName(for: language))
        }
        if !selectedID.isEmpty, !rows.contains(where: { $0.id == selectedID }) {
            let label = store.organization(id: selectedID)?.displayName(for: language)
                ?? language.text("Removed organization", "Borttagen organisation")
            rows.append(ManagerOptionRow(id: selectedID, label: label))
        }
        return rows
    }

    // MARK: Bindings

    /// "Godkänd OH, högst": one number (100 = full, 0 = none). An empty
    /// field is the standard, full OH.
    private var approvedMaxBinding: Binding<String> {
        Binding(
            get: { organization?.overheadRule == nil ? "" : Self.percentText(rule.approvedMaxPercent) },
            set: { newValue in
                guard let percent = Self.parsedPercent(newValue) else {
                    store.setOrganizationOverheadRule(organizationID: organizationID, rule: nil)
                    return
                }
                store.setOrganizationOverheadRule(
                    organizationID: organizationID,
                    rule: FunderOverheadRule(approvedMaxPercent: percent, keepingPremisesFrom: rule)
                )
            }
        )
    }

    private func exceptionApprovedMaxBinding(exceptionID: String) -> Binding<String> {
        Binding(
            get: { Self.percentText(exceptions.first(where: { $0.id == exceptionID })?.rule.approvedMaxPercent) },
            set: { newValue in
                updateException(exceptionID: exceptionID) { exception in
                    let percent = Self.parsedPercent(newValue) ?? 100
                    exception.rule = FunderOverheadRule(approvedMaxPercent: percent, keepingPremisesFrom: exception.rule)
                }
            }
        )
    }

    private var premisesBinding: Binding<Bool> {
        Binding(
            get: { rule.capIncludesPremises },
            set: { newValue in
                var updated = rule
                updated.capIncludesPremises = newValue
                store.setOrganizationOverheadRule(organizationID: organizationID, rule: updated)
            }
        )
    }

    private func exceptionManagerBinding(exceptionID: String) -> Binding<String> {
        Binding(
            get: { exceptions.first(where: { $0.id == exceptionID })?.managerOrganizationID ?? "" },
            set: { newValue in
                updateException(exceptionID: exceptionID) { $0.managerOrganizationID = newValue }
            }
        )
    }

    // MARK: Changes

    private func updateException(exceptionID: String, mutate: (inout FunderOverheadRuleException) -> Void) {
        var updated = exceptions
        guard let index = updated.firstIndex(where: { $0.id == exceptionID }) else { return }
        mutate(&updated[index])
        store.setOrganizationOverheadRuleExceptions(organizationID: organizationID, exceptions: updated)
    }

    private func addException() {
        var updated = exceptions
        updated.append(FunderOverheadRuleException(managerOrganizationID: ""))
        store.setOrganizationOverheadRuleExceptions(organizationID: organizationID, exceptions: updated)
    }

    private func removeException(exceptionID: String) {
        let updated = exceptions.filter { $0.id != exceptionID }
        store.setOrganizationOverheadRuleExceptions(organizationID: organizationID, exceptions: updated)
    }

    private static func percentText(_ percent: Double?) -> String {
        guard let percent else { return "" }
        return formatOverheadPercentInput(String(percent))
    }

    private static func parsedPercent(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return GrantParsing.numericValue(from: trimmed)
    }
}

// MARK: - Fund manager: own full OH (round 8)

/// "Förvaltarens fulla OH (%)" on a fund manager: used in applications
/// managed by this organization when its salary calculator has no OH
/// periods. Saved on the organization as soon as the field is left.
struct OrganizationManagerOverheadField: View {
    @ObservedObject var store: GrantDataStore
    let organizationID: String
    let language: AppLanguage

    private var hasCalculatorOverheadPeriods: Bool {
        (store.organization(id: organizationID)?.employerSalaryCalculator?.overheadPeriods ?? []).contains { period in
            GrantParsing.numericValue(from: period.value) != nil
                && DateParsers.isoDay.date(from: period.from) != nil
                && DateParsers.isoDay.date(from: period.to) != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AppFieldLabelText(
                text: language.text("OH taken (%)", "OH som tas ut (%)"),
                help: language.text(
                    "The overhead this fund manager wants to take. Copied into records when this fund manager is chosen.",
                    "Den overhead som medelsförvaltaren vill ta ut. Kopieras in i en post när den här förvaltaren väljs."
                )
            )
            CommitFormattingTextField(
                placeholder: language.text("Not set", "Inte angiven"),
                text: percentBinding,
                formatter: formatOverheadPercentInput,
                updatesContinuously: false
            )
            .appTextInputChrome()
            .frame(width: 160, alignment: .leading)
            SettingsEffectNote(language.text(
                "Affects: new records under Calls and grants. When this fund manager is chosen in a record, the value is copied into it and can be changed there; a later change here never changes existing records. When empty, the OH of this year's period in the salary calculator is copied instead\(hasCalculatorOverheadPeriods ? "" : " (none is filled in)").",
                "Påverkar: nya poster under Utlysningar och anslag. När den här förvaltaren väljs i en post kopieras värdet in och kan ändras där; en senare ändring här ändrar aldrig befintliga poster. När fältet är tomt kopieras i stället OH för årets period i lönekalkylen\(hasCalculatorOverheadPeriods ? "" : " (ingen är ifylld)")."
            ))
        }
    }

    private var percentBinding: Binding<String> {
        Binding(
            get: {
                guard let percent = store.organization(id: organizationID)?.managerOverheadPercent else { return "" }
                return formatOverheadPercentInput(String(percent))
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    store.setOrganizationManagerOverheadPercent(organizationID: organizationID, percent: nil)
                } else if let value = GrantParsing.numericValue(from: trimmed) {
                    store.setOrganizationManagerOverheadPercent(organizationID: organizationID, percent: value)
                }
            }
        )
    }
}
