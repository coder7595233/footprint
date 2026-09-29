import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum PublicationDraftThreeWayMerge {
    static func merge(
        baseline: PublicationRecord,
        draft: PublicationRecord,
        current: PublicationRecord
    ) -> PublicationRecord? {
        guard baseline.id == draft.id, draft.id == current.id else { return nil }
        guard let baselineObject = object(from: baseline),
              let draftObject = object(from: draft),
              var currentObject = object(from: current) else {
            return nil
        }

        for key in Set(baselineObject.keys).union(draftObject.keys) {
            let baselineValue = baselineObject[key]
            let draftValue = draftObject[key]
            if jsonValuesAreEqual(baselineValue, draftValue) {
                continue
            }
            let currentValue = currentObject[key]
            if jsonValuesAreEqual(currentValue, draftValue) {
                continue
            }
            guard jsonValuesAreEqual(currentValue, baselineValue) else {
                return nil
            }
            if let draftValue {
                currentObject[key] = draftValue
            } else {
                currentObject.removeValue(forKey: key)
            }
        }

        guard JSONSerialization.isValidJSONObject(currentObject),
              let data = try? JSONSerialization.data(withJSONObject: currentObject) else {
            return nil
        }
        return try? JSONDecoder().decode(PublicationRecord.self, from: data)
    }

    private static func object(from publication: PublicationRecord) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(publication),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func jsonValuesAreEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            if let lhs = lhs as? String, let rhs = rhs as? String {
                return lhs == rhs
            }
            if let lhs = lhs as? NSNumber, let rhs = rhs as? NSNumber {
                return lhs == rhs
            }
            if lhs is NSNull, rhs is NSNull {
                return true
            }
            if let lhs = lhs as? [Any], let rhs = rhs as? [Any] {
                return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy(jsonValuesAreEqual)
            }
            if let lhs = lhs as? [String: Any], let rhs = rhs as? [String: Any] {
                return lhs.keys == rhs.keys && lhs.keys.allSatisfy {
                    jsonValuesAreEqual(lhs[$0], rhs[$0])
                }
            }
            return false
        default:
            return false
        }
    }
}

private struct PublicationEditorRankingSnapshot {
    var scieJIFMetric: PublicationMetricValue?
    var scieJIFColor: Color?
    var scieJCIMetric: PublicationMetricValue?
    var scieJCIColor: Color?
    var esciJIFMetric: PublicationMetricValue?
    var esciJIFColor: Color?
    var esciJCIMetric: PublicationMetricValue?
    var esciJCIColor: Color?
    var sjrMetric: PublicationMetricValue?
    var sjrColor: Color?
    var norwegianMetric: PublicationMetricValue?
    var norwegianColor: Color?

    static let empty = PublicationEditorRankingSnapshot()
}

struct PublicationSubmissionEditorRow: Identifiable, Hashable {
    var id: String
    var journal: String
    var submittedDate: String?
    var rejectedDate: String?
    var acceptedDate: String?
    var publishedDate: String?

    init(
        id: String = UUID().uuidString,
        journal: String = "",
        submittedDate: String? = nil,
        rejectedDate: String? = nil,
        acceptedDate: String? = nil,
        publishedDate: String? = nil
    ) {
        self.id = id
        self.journal = journal
        self.submittedDate = submittedDate
        self.rejectedDate = rejectedDate
        self.acceptedDate = acceptedDate
        self.publishedDate = publishedDate
    }

    var trimmedJournal: String {
        journal.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasAnyDate: Bool {
        !allStatusesWithDates.isEmpty
    }

    var isEmpty: Bool {
        trimmedJournal.isEmpty && !hasAnyDate
    }

    var supportsManualOrdering: Bool {
        trimmedJournal.nonEmpty != nil && !hasAnyDate
    }

    var latestStatus: PublicationStatus? {
        publicationLatestStatusInfo(for: self)?.status
    }

    var latestDateString: String? {
        publicationLatestStatusInfo(for: self)?.date
    }

    var allStatusesWithDates: [(PublicationStatus, String)] {
        [
            (.submitted, submittedDate),
            (.rejected, rejectedDate),
            (.accepted, acceptedDate),
            (.published, publishedDate),
        ]
        .compactMap { status, date in
            guard let date = date?.trimmingCharacters(in: .whitespacesAndNewlines), !date.isEmpty else { return nil }
            return (status, date)
        }
    }

    var hasRejectedDate: Bool {
        rejectedDate?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var hasAcceptedOrPublishedDate: Bool {
        acceptedDate?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || publishedDate?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var persistedStatusEntries: [PublicationStatusEntry] {
        if hasAnyDate {
            return allStatusesWithDates.map { status, date in
                PublicationStatusEntry(status: status.rawValue, journal: trimmedJournal, date: date)
            }
        }
        guard let journal = trimmedJournal.nonEmpty else { return [] }
        return [PublicationStatusEntry(status: PublicationStatus.inPreparation.rawValue, journal: journal, date: nil)]
    }

    func date(for status: PublicationStatus) -> String? {
        switch status {
        case .submitted:
            return submittedDate
        case .rejected:
            return rejectedDate
        case .accepted:
            return acceptedDate
        case .published:
            return publishedDate
        case .planned, .inPreparation:
            return nil
        }
    }

    mutating func setDate(_ value: String?, for status: PublicationStatus) {
        switch status {
        case .submitted:
            submittedDate = value
        case .rejected:
            rejectedDate = value
            if value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                acceptedDate = nil
                publishedDate = nil
            }
        case .accepted:
            acceptedDate = value
            if value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                rejectedDate = nil
            }
        case .published:
            publishedDate = value
            if value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                rejectedDate = nil
            }
        case .planned, .inPreparation:
            break
        }
    }
}

private func publicationUsesCrossJournalSameDayTieBreak(_ lhsJournal: String, _ rhsJournal: String) -> Bool {
    let leftJournal = lhsJournal.trimmingCharacters(in: .whitespacesAndNewlines)
    let rightJournal = rhsJournal.trimmingCharacters(in: .whitespacesAndNewlines)
    return !leftJournal.isEmpty && !rightJournal.isEmpty && leftJournal != rightJournal
}

func publicationLatestStatusInfo(for row: PublicationSubmissionEditorRow) -> (status: PublicationStatus, date: String)? {
    row.allStatusesWithDates
        .sorted { lhs, rhs in
            let leftDate = DateParsers.isoDay.date(from: lhs.1) ?? .distantPast
            let rightDate = DateParsers.isoDay.date(from: rhs.1) ?? .distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            if lhs.0.sortRank != rhs.0.sortRank {
                return lhs.0.sortRank > rhs.0.sortRank
            }
            return false
        }
        .first
}

func publicationLatestStatusEntry(for row: PublicationSubmissionEditorRow) -> PublicationStatusEntry? {
    guard let latest = publicationLatestStatusInfo(for: row) else { return nil }
    return PublicationStatusEntry(status: latest.status.rawValue, journal: row.trimmedJournal, date: latest.date)
}

private func publicationCurrentStatusEntryShouldReplace(
    candidate: PublicationStatusEntry,
    candidateOffset: Int,
    current: PublicationStatusEntry,
    currentOffset: Int
) -> Bool {
    let candidateDate = candidate.date.flatMap { DateParsers.isoDay.date(from: $0) } ?? .distantPast
    let currentDate = current.date.flatMap { DateParsers.isoDay.date(from: $0) } ?? .distantPast
    if candidateDate != currentDate {
        return candidateDate > currentDate
    }

    let candidateStatus = PublicationStatus.fromStored(candidate.status)
    let currentStatus = PublicationStatus.fromStored(current.status)
    let useCrossJournalTieBreak = publicationUsesCrossJournalSameDayTieBreak(candidate.journal, current.journal)
    let candidateRank = useCrossJournalTieBreak
        ? publicationCurrentStatusTieBreakRank(candidateStatus)
        : candidateStatus.sortRank
    let currentRank = useCrossJournalTieBreak
        ? publicationCurrentStatusTieBreakRank(currentStatus)
        : currentStatus.sortRank
    if candidateRank != currentRank {
        return candidateRank > currentRank
    }

    return candidateOffset < currentOffset
}

func publicationEffectiveStatusEntry(from rows: [PublicationSubmissionEditorRow]) -> PublicationStatusEntry? {
    rows.enumerated().reduce(into: Optional<(offset: Int, entry: PublicationStatusEntry)>.none) { best, candidate in
        guard let candidateEntry = publicationLatestStatusEntry(for: candidate.element) else { return }
        guard let currentBest = best else {
            best = (offset: candidate.offset, entry: candidateEntry)
            return
        }
        if publicationCurrentStatusEntryShouldReplace(
            candidate: candidateEntry,
            candidateOffset: candidate.offset,
            current: currentBest.entry,
            currentOffset: currentBest.offset
        ) {
            best = (offset: candidate.offset, entry: candidateEntry)
        }
    }?.entry
}

private func orderedSubmissionRows(_ rows: [PublicationSubmissionEditorRow]) -> [PublicationSubmissionEditorRow] {
    let originalIndices = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($1.id, $0) })
    return rows.sorted { lhs, rhs in
        let leftGroup = submissionRowSortGroup(lhs)
        let rightGroup = submissionRowSortGroup(rhs)
        if leftGroup != rightGroup {
            return leftGroup < rightGroup
        }

        if leftGroup == 0 {
            let leftDate = lhs.latestDateString.flatMap { DateParsers.isoDay.date(from: $0) } ?? .distantPast
            let rightDate = rhs.latestDateString.flatMap { DateParsers.isoDay.date(from: $0) } ?? .distantPast
            if leftDate != rightDate {
                return leftDate < rightDate
            }
        }

        return (originalIndices[lhs.id] ?? 0) < (originalIndices[rhs.id] ?? 0)
    }
}

private func submissionRowSortGroup(_ row: PublicationSubmissionEditorRow) -> Int {
    if row.isEmpty {
        return 2
    }
    if row.hasAnyDate {
        return 0
    }
    return 1
}

private struct SubmissionRowDropModifier: ViewModifier {
    let row: PublicationSubmissionEditorRow
    @Binding var submissionRows: [PublicationSubmissionEditorRow]
    @Binding var draggedSubmissionRowID: String?
    var isEnabled: Bool = true
    let onReorder: () -> Void

    func body(content: Content) -> some View {
        if isEnabled, row.supportsManualOrdering {
            content.onDrop(
                of: [UTType.plainText],
                delegate: IdentifiedReorderDropDelegate(
                    targetID: row.id,
                    items: $submissionRows,
                    draggedItemID: $draggedSubmissionRowID,
                    onReorder: onReorder
                )
            )
        } else {
            content
        }
    }
}

func publicationDerivedSubmissionRows(from statusTimeline: [PublicationStatusEntry]) -> [PublicationSubmissionEditorRow] {
    var rows: [PublicationSubmissionEditorRow] = []

    let timeline = statusTimeline.enumerated().sorted { lhs, rhs in
        let leftEntry = lhs.element
        let rightEntry = rhs.element
        let leftHasDate = leftEntry.date?.trimmedOrNil != nil
        let rightHasDate = rightEntry.date?.trimmedOrNil != nil

        if leftHasDate != rightHasDate {
            return leftHasDate && !rightHasDate
        }

        if leftHasDate {
            let leftDate = leftEntry.date.flatMap { DateParsers.isoDay.date(from: $0) } ?? .distantPast
            let rightDate = rightEntry.date.flatMap { DateParsers.isoDay.date(from: $0) } ?? .distantPast
            if leftDate != rightDate {
                return leftDate < rightDate
            }
            let leftStatus = PublicationStatus.fromStored(leftEntry.status)
            let rightStatus = PublicationStatus.fromStored(rightEntry.status)
            if leftStatus.sortRank != rightStatus.sortRank {
                return leftStatus.sortRank < rightStatus.sortRank
            }
        }

        return lhs.offset < rhs.offset
    }

    for (_, entry) in timeline {
        let status = PublicationStatus.fromStored(entry.status)
        let targetJournal = entry.journal.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = matchingDerivedSubmissionRowIndex(for: targetJournal, status: status, date: entry.date, in: rows) {
            rows[index].setDate(entry.date, for: status)
            if rows[index].journal.isEmpty {
                rows[index].journal = targetJournal
            }
        } else {
            var row = PublicationSubmissionEditorRow(journal: targetJournal)
            row.setDate(entry.date, for: status)
            rows.append(row)
        }
    }

    return rows
}

func derivedSubmissionRows(for record: PublicationRecord) -> [PublicationSubmissionEditorRow] {
    var rows = publicationDerivedSubmissionRows(from: record.statusTimeline)

    for attempt in record.previousAttempts {
        let journal = attempt.journal.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = rows.firstIndex(where: {
            $0.journal == journal
                && (
                    ($0.rejectedDate == attempt.rejectedOn && attempt.rejectedOn?.nonEmpty != nil)
                    || ($0.submittedDate == attempt.submittedOn && attempt.submittedOn?.nonEmpty != nil)
                )
        }) {
            if rows[index].submittedDate == nil {
                rows[index].submittedDate = attempt.submittedOn
            }
            if rows[index].rejectedDate == nil {
                rows[index].rejectedDate = attempt.rejectedOn
            }
        } else if journal.nonEmpty != nil || attempt.submittedOn != nil || attempt.rejectedOn != nil {
            rows.append(PublicationSubmissionEditorRow(journal: journal, submittedDate: attempt.submittedOn, rejectedDate: attempt.rejectedOn))
        }
    }

    if rows.isEmpty, record.journal.nonEmpty != nil || record.statusDate?.nonEmpty != nil {
        var row = PublicationSubmissionEditorRow(journal: record.journal)
        let status = PublicationStatus.fromStored(record.status)
        if [.submitted, .rejected, .accepted, .published].contains(status) {
            row.setDate(record.statusDate, for: status)
        }
        rows.append(row)
    }

    return orderedSubmissionRows(rows)
}

func matchingDerivedSubmissionRowIndex(for journal: String, status: PublicationStatus, date: String?, in rows: [PublicationSubmissionEditorRow]) -> Int? {
    if date?.trimmedOrNil == nil && (status == .planned || status == .inPreparation) {
        return nil
    }

    if let date = date?.trimmedOrNil,
       let exactIndex = rows.indices.reversed().first(where: { index in
           let row = rows[index]
           if !journal.isEmpty, !row.journal.isEmpty, row.journal != journal {
               return false
           }
           return row.date(for: status) == date
       }) {
        return exactIndex
    }

    return rows.indices.reversed().first { index in
        let row = rows[index]
        if !journal.isEmpty, !row.journal.isEmpty, row.journal != journal {
            return false
        }
        guard row.date(for: status) == nil else {
            return false
        }
        switch status {
        case .submitted:
            return row.rejectedDate == nil && row.acceptedDate == nil && row.publishedDate == nil
        case .rejected:
            return row.acceptedDate == nil && row.publishedDate == nil
        case .accepted:
            return row.publishedDate == nil
        case .published:
            return true
        case .planned, .inPreparation:
            return true
        }
    }
}



private struct PublicationReferenceCopySheet: View {
    @ObservedObject var store: GrantDataStore
    let publication: PublicationRecord
    @Binding var options: PublicationExportOptions
    @Environment(\.dismiss) private var dismiss
    @State private var includeAllAuthors = false

    private var language: AppLanguage { store.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.text("Copy reference", "Kopiera referens"))
                .appTypography(.pageTitle)

            Form {
                Toggle(language.text("Show all author names (no et al)", "Visa alla författarnamn (ingen et al)"), isOn: $includeAllAuthors)
                    .appCheckboxStyle()

                Stepper(
                    "\(language.text("Author names before et al", "Författarnamn före et al")): \(options.authorCountBeforeEtAl)",
                    value: $options.authorCountBeforeEtAl,
                    in: 1...50
                )
                .disabled(includeAllAuthors)

                Toggle(language.text("Always show my name", "Visa alltid mitt namn"), isOn: $options.alwaysShowOwnName)
                    .appCheckboxStyle()
                    .disabled(includeAllAuthors)

                if AppRuntime.usesRenewedChrome {
                    HStack {
                        Text(language.text("Journal names", "Tidskriftsnamn"))
                        Spacer()
                        AppMenuSelectionField(
                            selection: $options.journalNameMode,
                            options: [
                                (language.text("Abbreviated", "Förkortade"), PublicationJournalNameMode.abbreviated),
                                (language.text("Full", "Hela"), PublicationJournalNameMode.full)
                            ],
                            placeholder: nil
                        )
                        .frame(width: 180)
                        if options.journalNameMode == .abbreviated {
                            AppMenuSelectionField(
                                selection: $options.journalShortNameStyle,
                                options: PublicationJournalShortNameStyle.allCases.map {
                                    ($0.displayName(language: language), $0)
                                },
                                placeholder: nil
                            )
                            .frame(width: 220)
                        }
                    }
                } else {
                    HStack {
                        Picker(language.text("Journal names", "Tidskriftsnamn"), selection: $options.journalNameMode) {
                            Text(language.text("Abbreviated", "Förkortade")).tag(PublicationJournalNameMode.abbreviated)
                            Text(language.text("Full", "Hela")).tag(PublicationJournalNameMode.full)
                        }
                        if options.journalNameMode == .abbreviated {
                            Picker(language.text("Short name source", "Kortnamnskälla"), selection: $options.journalShortNameStyle) {
                                ForEach(PublicationJournalShortNameStyle.allCases) { style in
                                    Text(style.displayName(language: language)).tag(style)
                                }
                            }
                        }
                    }
                }

                Toggle(language.text("Include PMID", "Inkludera PMID"), isOn: $options.includePMID)
                    .appCheckboxStyle()
                Toggle(language.text("Include DOI", "Inkludera DOI"), isOn: $options.includeDOI)
                    .appCheckboxStyle()
                Toggle(language.text("Include Epub date", "Inkludera Epub-datum"), isOn: $options.includeEpubDate)
                    .appCheckboxStyle()
                Toggle(language.text("Include publication date", "Inkludera publikationsdatum"), isOn: $options.includePublicationDate)
                    .appCheckboxStyle()
                Toggle(language.text("Bold my name", "Fetmarkera mitt namn"), isOn: $options.boldOwnName)
                    .appCheckboxStyle()
                Toggle(language.text("Underline doctoral thesis main supervisor", "Stryk under huvudhandledare i doktorsavhandling"), isOn: $options.underlineDoctoralMainSupervisor)
                    .appCheckboxStyle()
                Toggle(language.text("Underline doctoral thesis co-supervisor", "Stryk under bihandledare i doktorsavhandling"), isOn: coSupervisorUnderlineBinding)
                    .appCheckboxStyle()
                PublicationMetricYearOptionRow(
                    title: language.text("Include Clarivate JIF (SCIE/ESCI)", "Inkludera Clarivate JIF (SCIE/ESCI)"),
                    isOn: $options.includeClarivateSCIEJIF,
                    yearMode: $options.impactFactorYearMode,
                    language: language
                )
                PublicationMetricYearOptionRow(
                    title: language.text("Include quartile", "Inkludera kvartil"),
                    isOn: $options.includeQuartile,
                    yearMode: $options.quartileYearMode,
                    language: language
                )
                PublicationMetricYearOptionRow(
                    title: language.text("Include Norwegian list", "Inkludera norska listan"),
                    isOn: $options.includeNorwegianList,
                    yearMode: $options.norwegianListYearMode,
                    language: language
                )
                Toggle(language.text("Include citations", "Inkludera citations"), isOn: $options.includeCitations)
                    .appCheckboxStyle()
            }
            .formStyle(.grouped)

            FootprintDialogActions(
                cancelTitle: language.text("Cancel", "Avbryt"),
                primaryTitle: language.text("Copy", "Kopiera"),
                cancelAction: { dismiss() },
                primaryAction: {
                    var effectiveOptions = options
                    if includeAllAuthors {
                        effectiveOptions.authorCountBeforeEtAl = max(1000, publication.authorNames.count + 20)
                    }
                    options = effectiveOptions
                    store.copyAMACitation(for: publication, options: effectiveOptions)
                    dismiss()
                }
            )
        }
        .padding(18)
        .frame(minWidth: 520, minHeight: 460)
        .onAppear {
            includeAllAuthors = options.authorCountBeforeEtAl >= publication.authorNames.count && publication.authorNames.count > 0
        }
    }

    private var coSupervisorUnderlineBinding: Binding<Bool> {
        let coSupervisorName = store.cvOtherPublications
            .first(where: \.isDoctoralThesis)?
            .coSupervisor
            .trimmedOrNil
        return Binding(
            get: {
                guard let coSupervisorName else { return false }
                let key = PublicationDerivation.normalizedName(coSupervisorName)
                return options.underlinedNames.contains {
                    PublicationDerivation.normalizedName($0) == key
                }
            },
            set: { isOn in
                guard let coSupervisorName else { return }
                let key = PublicationDerivation.normalizedName(coSupervisorName)
                if isOn {
                    if !options.underlinedNames.contains(where: {
                        PublicationDerivation.normalizedName($0) == key
                    }) {
                        options.underlinedNames.append(coSupervisorName)
                    }
                } else {
                    options.underlinedNames.removeAll {
                        PublicationDerivation.normalizedName($0) == key
                    }
                }
            }
        )
    }
}

private struct PublicationCreditStatementCopySheet: View {
    @ObservedObject var store: GrantDataStore
    let publication: PublicationRecord
    @Binding var options: PublicationCreditStatementOptions
    @Environment(\.dismiss) private var dismiss

    private var language: AppLanguage { store.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.text("Custom CRediT statement", "Skräddarsydd CRediT-text"))
                .appTypography(.pageTitle)

            Form {
                if AppRuntime.usesRenewedChrome {
                    HStack {
                        Text(language.text("Name format", "Namnformat"))
                        Spacer()
                        AppMenuSelectionField(
                            selection: $options.nameFormat,
                            options: [
                                (
                                    language.text("Full name", "Fullständigt namn"),
                                    PublicationCreditStatementNameFormat.fullName
                                ),
                                (
                                    language.text("Initials", "Initialer"),
                                    PublicationCreditStatementNameFormat.initials
                                ),
                                (
                                    language.text("First initial + surname", "Förnamnsinitial + efternamn"),
                                    PublicationCreditStatementNameFormat.firstInitialAndLastName
                                ),
                            ],
                            placeholder: nil
                        )
                        .frame(width: 240)
                    }
                } else {
                    Picker(language.text("Name format", "Namnformat"), selection: $options.nameFormat) {
                        Text(language.text("Full name", "Fullständigt namn")).tag(PublicationCreditStatementNameFormat.fullName)
                        Text(language.text("Initials", "Initialer")).tag(PublicationCreditStatementNameFormat.initials)
                        Text(language.text("First initial + surname", "Förnamnsinitial + efternamn")).tag(PublicationCreditStatementNameFormat.firstInitialAndLastName)
                    }
                }

                Toggle(
                    language.text("Include contribution level in parentheses, e.g. (lead)", "Inkludera bidragsnivå inom parentes, t.ex. (lead)"),
                    isOn: $options.includeContributionParentheses
                )
                .appCheckboxStyle()
            }
            .formStyle(.grouped)

            FootprintDialogActions(
                cancelTitle: language.text("Cancel", "Avbryt"),
                primaryTitle: language.text("Copy", "Kopiera"),
                cancelAction: { dismiss() },
                primaryAction: {
                    store.copyPublicationCreditStatement(for: publication, options: options)
                    dismiss()
                }
            )
        }
        .padding(18)
        .frame(minWidth: 520, minHeight: 260)
    }
}

/// Small flag glyph used as language chooser (Swedish / English).
struct PublicationExportFlagGlyph: View {
    let flagLanguage: AppLanguage

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            if flagLanguage == .swedish {
                ZStack {
                    Color(red: 0.0, green: 0.36, blue: 0.75)
                    Rectangle()
                        .fill(Color(red: 1.0, green: 0.8, blue: 0.01))
                        .frame(width: w * 0.17)
                        .position(x: w * 0.37, y: h / 2)
                    Rectangle()
                        .fill(Color(red: 1.0, green: 0.8, blue: 0.01))
                        .frame(height: h * 0.26)
                        .position(x: w / 2, y: h / 2)
                }
            } else {
                let diagonal = Angle(radians: Double(atan2(h, w)))
                ZStack {
                    Color(red: 0.0, green: 0.13, blue: 0.41)
                    Group {
                        Rectangle().fill(Color.white).frame(width: w * 2, height: h * 0.30).rotationEffect(diagonal)
                        Rectangle().fill(Color.white).frame(width: w * 2, height: h * 0.30).rotationEffect(-diagonal)
                        Rectangle().fill(Color(red: 0.78, green: 0.06, blue: 0.18)).frame(width: w * 2, height: h * 0.12).rotationEffect(diagonal)
                        Rectangle().fill(Color(red: 0.78, green: 0.06, blue: 0.18)).frame(width: w * 2, height: h * 0.12).rotationEffect(-diagonal)
                    }
                    .position(x: w / 2, y: h / 2)
                    Rectangle().fill(Color.white).frame(width: w * 0.34).position(x: w / 2, y: h / 2)
                    Rectangle().fill(Color.white).frame(height: h * 0.46).position(x: w / 2, y: h / 2)
                    Rectangle().fill(Color(red: 0.78, green: 0.06, blue: 0.18)).frame(width: w * 0.20).position(x: w / 2, y: h / 2)
                    Rectangle().fill(Color(red: 0.78, green: 0.06, blue: 0.18)).frame(height: h * 0.28).position(x: w / 2, y: h / 2)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(Color.black.opacity(0.22), lineWidth: 0.5)
        )
    }
}

/// A clickable flag: exports (or selects) a language with one click.
struct PublicationExportFlagButton: View {
    let flagLanguage: AppLanguage
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PublicationExportFlagGlyph(flagLanguage: flagLanguage)
                .frame(width: 26, height: 18)
                .shadow(color: Color.black.opacity(0.20), radius: 1, x: 0, y: 0.5)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(isSelected ? AppPalette.linkAction : Color.clear, lineWidth: 2)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(flagLanguage == .swedish ? "Svenska" : "English")
        .accessibilityLabel(flagLanguage == .swedish ? "Svenska" : "English")
    }
}

/// One segment in the export icon strip. With `flagAction` set, hovering
/// swaps the icon for the two language flags — each a one-click export;
/// clicking elsewhere in the segment runs `action` (export in app language).
/// Without `flagAction` a click just runs `action` (opens a dialog).
struct ExportIconSegment: View {
    let systemImage: String
    let title: String
    let help: String
    var isEnabled = true
    var flagAction: ((AppLanguage) -> Void)? = nil
    let action: () -> Void

    @State private var isHovered = false

    private var showsFlags: Bool {
        isHovered && isEnabled && flagAction != nil
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppPalette.appText)
                    .opacity(showsFlags ? 0 : 1)
                if showsFlags, let flagAction {
                    HStack(spacing: 6) {
                        PublicationExportFlagButton(flagLanguage: .swedish) { flagAction(.swedish) }
                        PublicationExportFlagButton(flagLanguage: .english) { flagAction(.english) }
                    }
                }
            }
            .frame(height: 20)

            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minWidth: 74)
        .background(isHovered && isEnabled ? AppPalette.linkAction.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isEnabled else { return }
            action()
        }
        .onHover { isHovered = $0 }
        .opacity(isEnabled ? 1 : 0.4)
        .help(help)
    }
}

/// Author-export dialog: the included columns are shown directly as a
/// reorderable checklist (standard template preselected), the language is a
/// flag choice, and "Mall: Editorial Manager" rewrites the selection to that
/// template. What you see is exactly what the workbook contains.
struct AuthorExportCustomSheet: View {
    @ObservedObject var store: GrantDataStore
    @Binding var configuration: SubmissionAuthorExportConfiguration
    /// Runs the actual export — the sheet is shared by the publication and
    /// project editors, which export to different targets.
    let exportAction: (SubmissionAuthorExportConfiguration) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var orderedColumns: [SubmissionAuthorExportColumn] = []
    @State private var includedColumns: Set<SubmissionAuthorExportColumn> = []
    @State private var exportLanguage: AppLanguage = .english

    private var language: AppLanguage { store.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.text("Export author details", "Exportera författaruppgifter"))
                .appTypography(.pageTitle)

            HStack(spacing: 10) {
                AppFieldLabelText(text: language.text("Language", "Språk"))
                // The unselected language is clearly dimmed so the active
                // choice reads at a glance.
                PublicationExportFlagButton(flagLanguage: .swedish, isSelected: exportLanguage == .swedish) {
                    exportLanguage = .swedish
                }
                .opacity(exportLanguage == .swedish ? 1 : 0.5)
                PublicationExportFlagButton(flagLanguage: .english, isSelected: exportLanguage == .english) {
                    exportLanguage = .english
                }
                .opacity(exportLanguage == .english ? 1 : 0.5)

                Spacer()

                Button(language.text("Template: Editorial Manager", "Mall: Editorial Manager")) {
                    applyTemplate(SubmissionAuthorExportColumn.editorialManagerTemplateColumns)
                    exportLanguage = .english
                }
                .buttonStyle(.bordered)

                Button(language.text("Template: Standard", "Mall: Standard")) {
                    applyTemplate(SubmissionAuthorExportColumn.standardTemplateColumns)
                }
                .buttonStyle(.bordered)
            }

            Text(language.text(
                "Checked columns are exported in list order. Drag rows to reorder.",
                "Ikryssade kolumner exporteras i listans ordning. Dra rader för att sortera om."
            ))
            .appTypography(.secondary)
            .foregroundStyle(.secondary)

            List {
                ForEach(orderedColumns, id: \.self) { column in
                    HStack(spacing: 8) {
                        Toggle(
                            store.submissionAuthorExportColumnLabel(column),
                            isOn: Binding(
                                get: { includedColumns.contains(column) },
                                set: { selected in
                                    if selected {
                                        includedColumns.insert(column)
                                    } else {
                                        includedColumns.remove(column)
                                    }
                                }
                            )
                        )
                        .appCheckboxStyle()

                        Spacer()

                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .opacity(includedColumns.contains(column) ? 1 : 0.55)
                }
                .onMove { source, destination in
                    orderedColumns.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            FootprintDialogActions(
                cancelTitle: language.text("Cancel", "Avbryt"),
                primaryTitle: language.text("Export", "Exportera"),
                isPrimaryDisabled: includedColumns.isEmpty,
                cancelAction: { dismiss() },
                primaryAction: {
                    var next = configuration
                    next.mode = .custom
                    next.exportLanguage = exportLanguage
                    next.includedColumns = includedColumns
                    next.columnOrder = orderedColumns
                    configuration = next
                    exportAction(next)
                    dismiss()
                }
            )
        }
        .padding(18)
        .frame(minWidth: 560, minHeight: 620)
        .onAppear {
            applyTemplate(SubmissionAuthorExportColumn.standardTemplateColumns)
            // Author details are almost always submitted to English-language
            // journals — English is the default regardless of app language.
            exportLanguage = .english
        }
    }

    /// Puts the template's columns first (checked, in template order) and the
    /// remaining columns after (unchecked), so everything stays reachable.
    private func applyTemplate(_ template: [SubmissionAuthorExportColumn]) {
        let remainder = (SubmissionAuthorExportColumn.customSelectableColumns
            + SubmissionAuthorExportColumn.creditRoleColumns)
            .filter { !template.contains($0) }
        orderedColumns = template + remainder
        includedColumns = Set(template)
    }
}

private struct PublicationPresentationRow: Identifiable, Equatable {
    let id: String
    let meetingID: String
    let displayDate: Date
    let dateText: String
    let activity: String
    let organization: String
    let implementation: String
}


struct PublicationEditorView: View {
    @AppStorage("FootprintShowsInlineStatistics") private var showsInlineStatistics = true
    @ObservedObject var store: GrantDataStore
    @Environment(\.scenePhase) private var scenePhase
    let publication: PublicationRecord
    let metricDistributionCache: PublicationMetricDistributionCache
    let isActive: Bool
    let onEditorAppear: ((String) -> Void)?
    let onEditorReady: ((String) -> Void)?

    @State private var draft: PublicationRecord
    @State private var submissionRows: [PublicationSubmissionEditorRow]
    @State private var workflowStatus: PublicationWorkflowStatus?
    @State private var workflowStatusDate: String
    @State private var publicationTasks: [PublicationTaskItem]
    @State private var showCompletedPublicationTasks = false
    @State private var autosaveTask: DispatchWorkItem?
    @State private var forcedPersistTask: DispatchWorkItem?
    @State private var submissionRowsSyncTask: DispatchWorkItem?
    @State private var pendingSubmissionJournalRowID: String?
    @State private var pendingSubmissionJournalName = ""
    @State private var pendingAuthorName = ""
    @State private var draggedSubmissionRowID: String?
    @State private var draggedAuthorName: String?
    @State private var authorIdentity: StableStringDraftListState
    @State private var showsCreditRoleSheet = false
    @State private var showsCreditStatementSheet = false
    @State private var creditStatementOptions = PublicationCreditStatementOptions()
    @State private var showsAuthorExportCustomSheet = false
    @State private var authorExportConfiguration = SubmissionAuthorExportConfiguration(mode: .custom)
    @State private var showsReferenceCopySheet = false
    @State private var referenceCopyOptions = PublicationExportOptions()
    @State private var isFinalPDFDropTarget = false
    @State private var showsFinalPDFPreview = true
    @State private var loadedFinalPDFData: Data?
    @State private var loadedFinalPDFPath: String?
    @State private var exportedFinalPDFURL: URL?
    @State private var suppressDraftAutosave = false
    @State private var resolvedJournal: PublicationJournal?
    @State private var rankingSnapshot = PublicationEditorRankingSnapshot.empty
    @State private var derivedRefreshTask: DispatchWorkItem?
    @State private var needsRankingRefresh = false
    @State private var needsFundingRefresh = false
    @State private var needsPDFPreviewRefresh = false
    @State private var needsForcedPDFPreviewRefresh = false
    @State private var cachedFundingApplications: [GrantApplication]
    @State private var cachedAuthorOptions: [String]
    @State private var cachedJournalOptions: [String]
    @State private var editorAppearedAt: CFAbsoluteTime?
    @State private var reportedSectionKeys = Set<String>()
    @State private var showDeferredSections = false
    @State private var deferredSectionsTask: DispatchWorkItem?
    @State private var isEditingLocked = false
    private let addNewToken = "__add_new__"

    @State private var hasReportedReady = false

    init(
        store: GrantDataStore,
        publication: PublicationRecord,
        metricDistributionCache: PublicationMetricDistributionCache,
        isActive: Bool = true,
        onEditorAppear: ((String) -> Void)? = nil,
        onEditorReady: ((String) -> Void)? = nil
    ) {
        let initialSubmissionRows = Self.normalizedSubmissionRows(store.publicationSubmissionRows(for: publication))
        let initialResolvedJournal = Self.resolveJournal(for: publication, submissionRows: initialSubmissionRows, store: store)
        self.store = store
        self.publication = publication
        self.metricDistributionCache = metricDistributionCache
        self.isActive = isActive
        self.onEditorAppear = onEditorAppear
        self.onEditorReady = onEditorReady
        _draft = State(initialValue: publication)
        _authorIdentity = State(initialValue: StableStringDraftListState(values: publication.authorNames))
        _submissionRows = State(initialValue: initialSubmissionRows)
        _workflowStatus = State(initialValue: publication.workflowStatus)
        _workflowStatusDate = State(initialValue: publication.workflowStatusDate ?? "")
        _publicationTasks = State(initialValue: Self.normalizedPublicationTasks(publication.publicationTasks))
        _cachedFundingApplications = State(initialValue: store.grantedApplications(for: publication))
        _cachedAuthorOptions = State(initialValue: store.publicationAuthorOptionNames)
        _cachedJournalOptions = State(initialValue: store.publicationJournalOptionNames)
        _loadedFinalPDFPath = State(initialValue: publication.finalPDFPath?.trimmedOrNil)
        _resolvedJournal = State(initialValue: initialResolvedJournal)
        _rankingSnapshot = State(initialValue: .empty)
        _isEditingLocked = State(initialValue: publication.isEditingLocked)
    }

    private var language: AppLanguage { store.language }

    private var hasChanges: Bool {
        pendingDraft != publication
    }

    private var pendingDraft: PublicationRecord {
        var pending = draft
        pending.workflowStatus = workflowStatus
        pending.workflowStatusDate = workflowStatusDate.trimmedOrNil
        pending.publicationTasks = publicationTasks.filter { !$0.isEmpty }
        pending.isEditingLocked = isEditingLocked
        return pending
    }

    private var currentStatus: PublicationStatus {
        PublicationStatus.fromStored(draft.statusLabel)
    }

    private var illogicalPublicationEditorDateKeys: Set<String> {
        illogicalPublicationDateFieldKeys(for: pendingDraft, workflowStatusDate: workflowStatusDate)
    }

    private var activePublicationTaskIndices: [Int] {
        publicationTasks.indices.filter {
            !publicationTasks[$0].isCompleted
        }
    }

    private var visibleActivePublicationTaskIndices: [Int] {
        activePublicationTaskIndices.filter {
            !isEditingLocked || !publicationTasks[$0].isEmpty
        }
    }

    private var completedPublicationTaskIndices: [Int] {
        publicationTasks.indices.filter { !publicationTasks[$0].isEmpty && publicationTasks[$0].isCompleted }
    }

    private var hasVisiblePublicationTasks: Bool {
        publicationTasks.contains { !$0.isEmpty }
    }

    private var shouldShowPublicationTaskList: Bool {
        showDeferredSections && (
            !isEditingLocked || CentralTaskListSection.hasIncompleteTasks(
                store: store,
                linkKind: .publication,
                targetID: publication.id
            )
        )
    }

    private var showsWorkflowSection: Bool {
        currentStatus == .inPreparation
    }

    private var shouldShowReviewRegistrationRow: Bool {
        draft.isSystematicReview || draft.hasReviewRegistrationMetadata
    }

    private var showsEthicsExportButton: Bool {
        currentStatus == .inPreparation || currentStatus == .submitted
    }

    private var hasDefinedCreditRoles: Bool {
        draft.hasDefinedCreditRoles
    }

    private var fundingApplications: [GrantApplication] {
        cachedFundingApplications
    }

    private var presentationRows: [PublicationPresentationRow] {
        let publicationID = publication.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !publicationID.isEmpty else { return [] }
        let presentationCategoryKey = calendarMeetingCategoryFilterKey(for: "Presentation")

        return store.calendarMeetingRecords.compactMap { meeting -> PublicationPresentationRow? in
            guard meeting.publicationIDs.compactMap(\.trimmedOrNil).contains(publicationID),
                  calendarMeetingCategoryFilterKey(for: meeting.meetingType) == presentationCategoryKey,
                  let displayDate = DateParsers.isoDay.date(from: meeting.date) else {
                return nil
            }

            return PublicationPresentationRow(
                id: meeting.id,
                meetingID: meeting.id,
                displayDate: displayDate,
                dateText: DateParsers.isoDay.string(from: displayDate),
                activity: meeting.title.nonEmpty ?? calendarMeetingCategoryDisplayName(meeting.meetingType, language: language),
                organization: presentationOrganizationText(for: meeting, language: language),
                implementation: presentationImplementationText(for: meeting, language: language)
            )
        }
    }

    private var selectedJournalSubmissionPortalURL: URL? {
        resolvedJournal?.submissionPortalLinkURL
    }

    private var selectedJournalHomeURL: URL? {
        resolvedJournal?.journalHomeURL
    }

    private var selectedJournalDisplayName: String? {
        resolvedJournal?.name.nonEmpty
            ?? draft.journal.trimmedOrNil
            ?? submissionRows.last(where: { $0.journal.nonEmpty != nil })?.journal.trimmedOrNil
    }

    private var authorOptions: [String] {
        cachedAuthorOptions
    }

    private var journalOptions: [String] {
        cachedJournalOptions
    }

    private func authorOptionDisplayName(_ name: String, language: AppLanguage) -> String {
        let base = name
        guard isHistoricalAuthorOption(name) else { return base }
        return "\(base) (\(language.text("previous", "tidigare")))"
    }

    private func isHistoricalAuthorOption(_ name: String) -> Bool {
        store.publicationAuthor(named: name) == nil && store.publicationAuthor(matchingPresentedName: name) != nil
    }

    private func excludedAuthorOptions(excluding retainedIndex: Int? = nil) -> Set<String> {
        Set(draft.authorNames.enumerated().flatMap { index, name -> [String] in
            if retainedIndex == index {
                return []
            }
            guard let author = store.publicationAuthor(matchingPresentedName: name) else {
                return name.trimmedOrNil.map { [$0] } ?? []
            }
            return author.presentedNameCandidates
        })
    }

    var body: some View {
        let base = AnyView(
            editorContent(language: language)
                .background(AppPalette.detailPanelSurface)
                .sheet(isPresented: $showsCreditRoleSheet) {
                    PublicationCreditRolesSheet(
                        publication: $draft,
                        language: language,
                        store: store
                    )
                }
                .sheet(isPresented: $showsReferenceCopySheet) {
                    PublicationReferenceCopySheet(
                        store: store,
                        publication: pendingDraft,
                        options: $referenceCopyOptions
                    )
                }
                .sheet(isPresented: $showsCreditStatementSheet) {
                    PublicationCreditStatementCopySheet(
                        store: store,
                        publication: pendingDraft,
                        options: $creditStatementOptions
                    )
                }
                .sheet(isPresented: $showsAuthorExportCustomSheet) {
                    let exportTarget = pendingDraft
                    AuthorExportCustomSheet(
                        store: store,
                        configuration: $authorExportConfiguration,
                        exportAction: { configuration in
                            store.exportSubmissionWorkbookToDefaultLocation(for: exportTarget, configuration: configuration)
                        }
                    )
                }
        )
        let persistence = AnyView(
            base
                .onAppear {
                    if isActive {
                        handleEditorAppear()
                        scheduleDerivedRefresh(rankings: true, funding: false, pdfPreview: showsFinalPDFPreview, forcePDFPreview: false)
                    } else {
                        showDeferredSections = false
                    }
                }
                .onDisappear {
                    handleEditorDisappear()
                }
                .onChange(of: publication) { oldValue, newValue in
                    handlePublicationChange(from: oldValue, to: newValue)
                }
                .onChange(of: draft) { _, _ in
                    guard !suppressDraftAutosave else { return }
                    scheduleAutosave()
                }
                .onChange(of: publicationTasks) { _, newValue in
                    handlePublicationTasksChange(newValue)
                }
                .onChange(of: draft.authorNames) { oldValue, newValue in
                    syncAuthorDependentAssignments(previousAuthorNames: oldValue, newAuthorNames: newValue)
                }
                .flushPendingAutosaveOnTextEnd(requestImmediatePersist)
                .onChange(of: scenePhase) { _, newValue in
                    if newValue != .active {
                        requestImmediatePersist()
                    }
                }
        )
        let derived = AnyView(
            persistence
                .onChange(of: draft.journal) { _, _ in
                    scheduleDerivedRefresh(rankings: true)
                }
                .onChange(of: draft.year) { _, _ in
                    scheduleDerivedRefresh(rankings: true)
                }
                .onChange(of: draft.statusTimeline) { _, _ in
                    scheduleDerivedRefresh(rankings: true)
                }
                .onChange(of: submissionRows) { _, _ in
                    scheduleDerivedRefresh(rankings: true)
                }
                .onChange(of: store.journals) { _, _ in
                    refreshJournalOptions()
                    scheduleDerivedRefresh(rankings: true)
                }
                .onChange(of: store.coauthors) { _, _ in
                    refreshAuthorOptions()
                }
                .onChange(of: store.applications) { _, _ in
                    scheduleDerivedRefresh(funding: true)
                }
                .onChange(of: draft.projectName) { _, _ in
                    scheduleDerivedRefresh(funding: true)
                }
                .onChange(of: draft.finalPDFPath) { _, _ in
                    scheduleDerivedRefresh(pdfPreview: true, forcePDFPreview: true)
                }
                .onChange(of: showsFinalPDFPreview) { _, _ in
                    scheduleDerivedRefresh(pdfPreview: true, forcePDFPreview: true)
                }
                .onChange(of: workflowStatus) { oldValue, newValue in
                    if oldValue != newValue, newValue != nil {
                        workflowStatusDate = DateParsers.isoDay.string(from: Calendar.current.startOfDay(for: Date()))
                    }
                    scheduleAutosave()
                }
                .onChange(of: workflowStatusDate) { _, _ in
                    scheduleAutosave()
                }
        )
        return derived
            .onChange(of: isActive) { _, active in
                if active {
                    handleEditorAppear()
                    scheduleDerivedRefresh(
                        rankings: true,
                        funding: showDeferredSections,
                        pdfPreview: showsFinalPDFPreview,
                        forcePDFPreview: true
                    )
                } else {
                    derivedRefreshTask?.cancel()
                    derivedRefreshTask = nil
                    deferredSectionsTask?.cancel()
                    deferredSectionsTask = nil
                    showDeferredSections = false
                    requestImmediatePersist()
                }
            }
            .floatingDocumentContent(
                id: "publication-document-\(publication.id)",
                title: language.text("Publication document", "Publikationsdokument"),
                isAvailable: isActive
            ) {
                PublicationDocumentPanelContent(store: store, publicationID: publication.id)
            }
    }

    @ViewBuilder
    private func editorContent(language: AppLanguage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(alignment: .center, spacing: 8) {
                        if isEditingLocked {
                            Text(draft.title.trimmedOrNil ?? language.text("Publication title", "Publikationstitel"))
                                .appTypography(.pageTitle)
                                .foregroundStyle(AppPalette.appText)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            TextField(language.text("Publication title", "Publikationstitel"), text: binding(\.title), axis: .vertical)
                                .appTypography(.pageTitle)
                                .textFieldStyle(.plain)
                                .lineLimit(2)
                        }
                        if let doiURL = draft.doiURL {
                            Link(destination: doiURL) {
                                AppInlineLinkLabel(title: "DOI")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppPalette.linkAction)
                        }
                        if let pmidURL = draft.pmidURL {
                            Link(destination: pmidURL) {
                                AppInlineLinkLabel(title: "PMID")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppPalette.linkAction)
                        }
                        if PublicationStatus.fromStored(draft.statusLabel) == .submitted,
                           let submissionPortalURL = selectedJournalSubmissionPortalURL {
                            Link(destination: submissionPortalURL) {
                                AppInlineLinkLabel(title: language.text("Submission portal", "Inskickningsportal"))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppPalette.linkAction)
                        }
                        if !isEditingLocked, let resolvedJournal {
                            AppDestinationActionButton(
                                kind: .app,
                                language: language,
                                title: language.text("Open journal", "Öppna tidskrift"),
                                fontSize: 12
                            ) {
                                store.openRoute(for: resolvedJournal)
                            }
                        }
                        if !isEditingLocked, let selectedJournalHomeURL {
                            AppDestinationURLLink(
                                kind: .web,
                                language: language,
                                destination: selectedJournalHomeURL,
                                fontSize: 12,
                                showsTitle: true
                            )
                        }
                    }
	                    Spacer()
	                    publicationEditorLockButton(language: language)
	                    if !isEditingLocked {
	                        DeleteActionButton(
	                            title: language.text("Delete", "Ta bort"),
	                            cancelTitle: language.text("Cancel", "Avbryt")
	                        ) {
	                            store.deletePublication(id: publication.id)
	                        }
	                    }
                }
                .frame(minHeight: 42)
                .onAppear {
                    reportSectionReadyIfNeeded("header")
                }

                // Projekt row directly under the title; the export menus
                // stack to its right instead of reserving their own band.
                HStack(alignment: .top, spacing: 16) {
                PublicationCompactPanel(title: "", usesInnerSurface: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            if shouldShowPublicationFieldInCurrentLockState(draft.projectName) {
                                compactField(language.text("Project", "Projekt"), width: 220) {
                                HStack(spacing: 6) {
                                    publicationMenuField(
                                        selection: Binding<String?>(
                                            // "Alla kopplingar via id": the linked project's current name.
                                            get: { draft.projectID.flatMap { store.project(id: $0)?.nameSv } ?? draft.projectName },
                                            set: { newValue in
                                                guard newValue != addNewToken else {
                                                    store.beginAddingProject(fromPublicationID: draft.id)
                                                    return
                                                }
                                                draft.projectName = newValue
                                                draft.projectID = newValue.flatMap { store.project(named: $0)?.id }
                                                if draft.authorNames.isEmpty,
                                                   let projectName = newValue,
                                                   let collaborators = store.project(named: projectName)?.collaboratorNames,
                                                   !collaborators.isEmpty {
                                                    authorIdentity.reconcileExternal(collaborators)
                                                    draft.authorNames = collaborators
                                                }
                                            }
                                        ),
                                        options: [(language.text("No project", "Inget projekt"), String?.none),
                                                  (language.text("Add new", "Lägg till ny"), Optional(addNewToken))]
                                            + store.projects
                                            .map { project in
                                                let projectTitle = language == .swedish ? project.nameSv : (project.nameEn.nonEmpty ?? project.nameSv)
                                                return (projectTitle, Optional(project.nameSv))
                                            }
                                            .sorted { lhs, rhs in
                                                lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
                                        },
                                        placeholder: language.text("No project", "Inget projekt")
                                    )

                                    let selectedProject = store.linkedProject(of: draft)
                                    if !isEditingLocked || selectedProject != nil {
                                        AppDestinationActionButton(
                                            kind: .app,
                                            language: language,
                                            title: language.text("Open project", "Öppna projekt"),
                                            fontSize: 12,
                                            tint: selectedProject == nil ? Color.secondary.opacity(0.55) : AppPalette.linkAction,
                                            isEnabled: selectedProject != nil
                                        ) {
                                            guard let selectedProject else { return }
                                            store.openRoute(for: selectedProject)
                                        }
                                        .focusable(false)
                                    }
                                }
                            }
                            }
                            if shouldShowPublicationFieldInCurrentLockState(draft.publicationType) {
                                compactField(language.text("Type", "Typ"), width: 180) {
                                publicationMenuField(
                                    selection: binding(\.publicationType),
                                    options: [(language.text("Select type", "Välj typ"), "")]
                                        + publicationTypeOptions.map { (localizedPublicationType($0, language: language), $0) },
                                    placeholder: language.text("Select type", "Välj typ")
                                )
                            }
                            }
                            if shouldShowPublicationFieldInCurrentLockState(draft.year) {
                                compactField(language.text("Year", "År"), width: 90) {
                                publicationSurfaceTextField(
                                    "2025",
                                    text: binding(\.year),
                                    formatter: AppFieldParsers.canonicalYear,
                                    state: AppFieldValidators.optionalYear(draft.year, language: language).state,
                                    updatesContinuously: false
                                )
                            }
                            }
                            compactField(language.text("Peer review", "Granskning"), width: 150) {
                                if isEditingLocked {
                                    lockedPublicationValueText(draft.isPeerReviewed ? language.text("Yes", "Ja") : language.text("No", "Nej"))
                                } else {
                                    Toggle(language.text("Peer reviewed", "Expertgranskad"), isOn: boolBinding(\.isPeerReviewed))
                                        .appCheckboxStyle()
                                }
                            }
                        }

                        if shouldShowReviewRegistrationRow {
                            HStack(spacing: 10) {
                                compactField(language.text("Registry", "Register"), width: 190) {
                                    publicationMenuField(
                                        selection: binding(\.reviewRegistrationRegistry),
                                        options: [(language.text("Select registry", "Välj register"), "")]
                                            + PublicationReviewRegistrationRegistry.allCases.map { ($0.rawValue, $0.rawValue) },
                                        placeholder: language.text("Select registry", "Välj register")
                                    )
                                }

                                compactField(language.text("Registration ID", "Registrerings-ID"), width: 220) {
                                    publicationSurfaceTextField(
                                        language.text("Registration ID", "Registrerings-ID"),
                                        text: binding(\.reviewRegistrationID),
                                        updatesContinuously: false
                                    )
                                }

                                compactField(language.text("Registration date", "Registreringsdatum"), width: 174) {
                                    HStack(spacing: 8) {
                                        publicationSurfaceTextField(
                                            "YYYY-MM-DD",
                                            text: binding(\.reviewRegistrationDate),
                                            formatter: DateParsers.canonicalizedDayInput,
                                            state: AppFieldValidators.optionalDate(draft.reviewRegistrationDate, language: language).state,
                                            updatesContinuously: false
                                        )
                                        .frame(width: 132)

                                        if let registrationURL = draft.reviewRegistrationURL {
                                            AppDestinationURLLink(
                                                kind: .web,
                                                language: language,
                                                destination: registrationURL,
                                                title: language.text("Open registration", "Öppna registrering"),
                                                fontSize: 12,
                                                width: 24,
                                                height: 24
                                            )
                                        }
                                    }
                                }
                            }
                        }

                    }
                    // Line the Projekt/Typ/År fields up with the shared
                    // 40 pt content edge of the author and journal lists.
                    .padding(.leading, 40)
                }
                .onAppear {
                    reportSectionReadyIfNeeded("metadata")
                }

                Spacer(minLength: 16)

                exportButtons(language: language)
                }

                if showsWorkflowSection && (!isEditingLocked || hasVisibleLockedWorkflowFields) {
                    PublicationCompactPanel(title: language.text("Workflow", "Arbetsgång"), usesInnerSurface: false) {
                        publicationWorkflowContent(language: language)
                            .padding(.leading, 40)
                    }
                    .onAppear {
                        reportSectionReadyIfNeeded("workflow")
                    }
                }

                PublicationCompactPanel(title: language.text("Authors", "Författare"), usesInnerSurface: false) {
                    VStack(alignment: .leading, spacing: isEditingLocked ? 4 : 8) {
                            HStack(alignment: .top, spacing: 24) {
                                authorPickerArea(language: language)
                                if !isEditingLocked {
                                    authorSideActionColumn(language: language)
                                        // Line up with the first author field,
                                        // below the Corr. header row.
                                        .padding(.top, 18 + AutocompleteSelectionMetrics.rowSpacing)
                                }
                                if showsInlineStatistics {
                                    // Fixed width so the block is identical for
                                    // every record, locked or open, with at
                                    // least ~1 cm of air on its left.
                                    Spacer(minLength: 28)
                                    ContributorCompositionInlineSection(
                                        store: store,
                                        contributorNames: draft.authorNames,
                                        language: language
                                    )
                                    .frame(width: 480, alignment: .topLeading)
                                }
                            }

                        if isEditingLocked && (draft.sharedFirstAuthorship || draft.sharedLastAuthorship) {
                            HStack(spacing: 14) {
                                if draft.sharedFirstAuthorship {
                                    Text(language.text("Shared first authorship", "Delad förstaförfattare"))
                                        .appTypography(.secondary)
                                        .foregroundStyle(AppPalette.appText)
                                }
                                if draft.sharedLastAuthorship {
                                    Text(language.text("Shared last authorship", "Delad sistaförfattare"))
                                        .appTypography(.secondary)
                                        .foregroundStyle(AppPalette.appText)
                                }
                                Spacer()
                            }
                        }
                    }
                }
                .onAppear {
                    reportSectionReadyIfNeeded("authors")
                }

                PublicationCompactPanel(title: language.text("Status", "Status"), usesInnerSurface: false) {
                    publicationSubmissionGrid(language: language)
                }
                .onAppear {
                    reportSectionReadyIfNeeded("status")
                }

                if showDeferredSections && showsBibliographyAndCitations {
                    if !isEditingLocked || hasVisibleLockedBibliographyFields {
                    PublicationCompactPanel(title: language.text("Bibliography", "Bibliografi"), usesInnerSurface: false) {
                        VStack(alignment: .leading, spacing: 8) {
	                            HStack(spacing: 10) {
	                                if shouldShowPublicationFieldInCurrentLockState(draft.volume) {
	                                    compactField(language.text("Volume", "Volym"), width: 72) {
	                                    publicationSurfaceTextField(language.text("Volume", "Volym"), text: binding(\.volume))
	                                }
                                }
                                if shouldShowPublicationFieldInCurrentLockState(draft.issue) {
                                    compactField(language.text("Issue", "Nummer/häfte"), width: 116) {
                                    publicationSurfaceTextField(language.text("Issue", "Nummer/häfte"), text: binding(\.issue))
                                }
                                }
                                if shouldShowPublicationFieldInCurrentLockState(draft.pageRange) {
                                    compactField(language.text("Pages", "Sidnummer"), width: 104) {
                                    publicationSurfaceTextField(language.text("Pages", "Sidnummer"), text: binding(\.pageRange))
                                }
                                }
                                if shouldShowPublicationFieldInCurrentLockState(draft.articleNumber) {
                                    compactField(language.text("Article number", "Artikelnummer"), width: 136) {
	                                    publicationSurfaceTextField(language.text("Article number", "Artikelnummer"), text: binding(\.articleNumber))
	                                }
	                                }
	                                if shouldShowPublicationFieldInCurrentLockState(bibliographyPublishedDateValue) {
	                                    compactField(language.text("Publication date", "Publiceringsdatum"), width: 108) {
	                                    publicationSurfaceTextField(
	                                        "YYYY-MM-DD",
	                                        text: bibliographyPublishedDateBinding(),
	                                        formatter: DateParsers.canonicalizedDayInput,
	                                        state: AppFieldValidators.optionalDate(bibliographyPublishedDateValue, language: language).state,
	                                        updatesContinuously: false
	                                    )
	                                }
	                                }
	                                if shouldShowPublicationFieldInCurrentLockState(draft.epubDate) {
	                                    compactField(language.text("Epub date", "Epub-datum"), width: 100) {
	                                    publicationSurfaceTextField(
                                        "YYYY-MM-DD",
                                        text: binding(\.epubDate),
                                        formatter: DateParsers.canonicalizedDayInput,
                                        updatesContinuously: false
	                                    )
	                                }
	                                }
	                                	                                if shouldShowPublicationFieldInCurrentLockState(draft.doi) {
	                                    compactField("DOI", width: 200) {
	                                    HStack(spacing: 8) {
	                                        publicationSurfaceTextField(
	                                            "DOI",
	                                            text: binding(\.doi),
	                                            formatter: AppFieldParsers.canonicalDOI,
	                                            state: AppFieldValidators.optionalDOI(draft.doi, language: language).state,
	                                            updatesContinuously: false
	                                        )
	                                        if let doiURL = draft.doiURL {
	                                            AppDestinationURLLink(
	                                                kind: .web,
	                                                language: language,
	                                                destination: doiURL,
	                                                fontSize: 12
	                                            )
	                                        }
	                                    }
	                                }
	                                }
	                                if shouldShowPublicationFieldInCurrentLockState(draft.pmid) {
	                                    compactField("PMID", width: 116) {
	                                    HStack(spacing: 8) {
                                        publicationSurfaceTextField(
                                            "PMID",
                                            text: binding(\.pmid),
                                            formatter: AppFieldParsers.canonicalPMID,
                                            state: AppFieldValidators.optionalPMID(draft.pmid, language: language).state,
                                            updatesContinuously: false
                                        )
                                        if let pmidURL = draft.pmidURL {
                                            AppDestinationURLLink(
                                                kind: .web,
                                                language: language,
                                                destination: pmidURL,
                                                fontSize: 12
                                            )
                                        }
	                                    }
	                                }
	                                }
	                                Spacer()
	                            }
                        }
                    }
                    .onAppear {
                        reportSectionReadyIfNeeded("bibliography")
                    }
                    }

                    PublicationCompactPanel(title: language.text("Citations", "Citeringar"), usesInnerSurface: false) {
                        VStack(alignment: .leading, spacing: 8) {
                            ScrollView(.horizontal, showsIndicators: true) {
                                VStack(alignment: .leading, spacing: 6) {
                                    citationHeaderRow(language: language)
                                    citationEditorRow(
                                        title: language.text("External citations", "Externa citeringar"),
                                        kind: .regular
                                    )
                                    citationEditorRow(
                                        title: language.text("Self-citations", "Självciteringar"),
                                        kind: .selfCitation
                                    )
                                    Divider()
                                    citationTotalRow(language: language)
                                }
                            }
                        }
                    }
                    .onAppear {
                        reportSectionReadyIfNeeded("citations")
                    }
                }

                if shouldShowPublicationTaskList {
                    PublicationCompactPanel(
                        title: language.text("Task list", "Uppgiftslista"),
                        usesInnerSurface: false,
                        titleActionTitle: isEditingLocked ? nil : language.text("Add task", "Lägg till uppgift"),
                        titleAction: {
                            CentralTaskListSection.addTask(store: store, linkKind: .publication, targetID: publication.id)
                        }
                    ) {
                        publicationTaskListContent(language: language)
                    }
                    .onAppear {
                        reportSectionReadyIfNeeded("tasks")
                    }
                }

                if showDeferredSections && !fundingApplications.isEmpty {
                    PublicationCompactPanel(title: language.text("Funding grants", "Finansierande anslag"), usesInnerSurface: false) {
                        fundingApplicationsContent(language: language)
                    }
                    .onAppear {
                        reportSectionReadyIfNeeded("funding")
                    }
                }

                if showDeferredSections && !presentationRows.isEmpty {
                    PublicationCompactPanel(title: language.text("Presentations", "Presentationer"), usesInnerSurface: false) {
                        presentationRowsContent(language: language)
                    }
                    .onAppear {
                        reportSectionReadyIfNeeded("presentations")
                    }
                }

                if showDeferredSections {
                    publicationActivitiesSection(language: language)
                }

                if showDeferredSections && showsBibliographyAndCitations {
                    PublicationCompactPanel(title: "", usesInnerSurface: false) {
                        finalPDFSection
                    }
                    .onAppear {
                        reportSectionReadyIfNeeded("pdf")
                    }
                }
            }
            .appDetailWorkspacePadding()
        }
    }

    /// Upcoming and completed activities linked to the publication, with the
    /// compact activity statistics to the right of the lists.
    @ViewBuilder
    private func publicationActivitiesSection(language: AppLanguage) -> some View {
        let meetingSummary = calendarMeetingHoursSummary(
            store: store,
            scope: .publication(publication.id)
        )
        let hasMeetings = meetingSummary.completedMeetingCount + meetingSummary.plannedMeetingCount > 0
        let rows = calendarLinkedEventRows(
            store: store,
            language: language,
            scope: .publication(publication.id),
            includesTasks: false,
            includesPastEvents: true
        )
        let todayStart = Calendar.current.startOfDay(for: Date())
        let upcoming = rows
            .filter { $0.displayDate >= todayStart }
            .sorted { $0.displayDate < $1.displayDate }
        let past = rows
            .filter { $0.displayDate < todayStart }
            .sorted { $0.displayDate > $1.displayDate }

        if !rows.isEmpty || hasMeetings {
            PublicationCompactPanel(title: language.text("Activities", "Aktiviteter"), usesInnerSurface: false) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        if !upcoming.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                AppFieldLabelText(text: language.text("Upcoming", "Kommande"))
                                CalendarLinkedEventList(
                                    store: store,
                                    language: language,
                                    rows: upcoming,
                                    usesSingleLineRows: true,
                                    usesCompactResearcherRows: true
                                )
                            }
                        }

                        if !past.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                AppFieldLabelText(text: language.text("Completed", "Genomförda"))
                                CalendarLinkedEventList(
                                    store: store,
                                    language: language,
                                    rows: past,
                                    usesSingleLineRows: true,
                                    usesCompactResearcherRows: true
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    if showsInlineStatistics, hasMeetings {
                        CalendarMeetingCompactStatisticsSection(
                            summary: meetingSummary,
                            language: language
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
        }
    }

    private func handleEditorAppear() {
        editorAppearedAt = CFAbsoluteTimeGetCurrent()
        reportedSectionKeys.removeAll()
        showDeferredSections = false
        onEditorAppear?(publication.id)
        reportEditorReadyIfNeeded()
        scheduleDeferredSections()
    }

    private func handleEditorDisappear() {
        autosaveTask?.cancel()
        forcedPersistTask?.cancel()
        submissionRowsSyncTask?.cancel()
        derivedRefreshTask?.cancel()
        derivedRefreshTask = nil
        deferredSectionsTask?.cancel()
        deferredSectionsTask = nil
        // Flush while this editor still owns the current baseline. A delayed
        // teardown write can otherwise race deletion, undo/import, or a newer
        // editor and resurrect an obsolete snapshot.
        persist(baseline: publication, silently: true)
    }

    private func publicationEditorLockButton(language: AppLanguage) -> some View {
        AppEditorLockButton(isLocked: isEditingLocked, language: language, action: toggleEditingLock)
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
        if isEditingLocked {
            draft.isEditingLocked = nextValue
            isEditingLocked = nextValue
            requestImmediatePersist()
            return
        }
        NSApp.keyWindow?.makeFirstResponder(nil)
        draft.isEditingLocked = nextValue
        isEditingLocked = nextValue
        requestImmediatePersist()
    }

    private func handlePublicationChange(from oldValue: PublicationRecord, to newValue: PublicationRecord) {
        if newValue.id != draft.id {
            autosaveTask?.cancel()
            forcedPersistTask?.cancel()
            derivedRefreshTask?.cancel()
            derivedRefreshTask = nil
            deferredSectionsTask?.cancel()
            deferredSectionsTask = nil
            persist(baseline: oldValue, silently: true)
            let seedStartedAt = CFAbsoluteTimeGetCurrent()
            let nextSubmissionRows = Self.normalizedSubmissionRows(store.publicationSubmissionRows(for: newValue))
            let nextResolvedJournal = Self.resolveJournal(for: newValue, submissionRows: nextSubmissionRows, store: store)
            let nextRankingSnapshot = Self.makeRankingSnapshot(
                resolvedJournal: nextResolvedJournal,
                publicationYear: newValue.yearValue,
                metricDistributionCache: metricDistributionCache
            )
            authorIdentity.reconcileExternal(newValue.authorNames)
            draft = newValue
            isEditingLocked = newValue.isEditingLocked
            submissionRows = nextSubmissionRows
            workflowStatus = newValue.workflowStatus
            workflowStatusDate = newValue.workflowStatusDate ?? ""
            publicationTasks = Self.normalizedPublicationTasks(newValue.publicationTasks)
            cachedFundingApplications = store.grantedApplications(for: newValue)
            cachedAuthorOptions = store.publicationAuthorOptionNames
            cachedJournalOptions = store.publicationJournalOptionNames
            resolvedJournal = nextResolvedJournal
            rankingSnapshot = nextRankingSnapshot
            pendingSubmissionJournalRowID = nil
            showsFinalPDFPreview = true
            loadedFinalPDFPath = newValue.finalPDFPath?.trimmedOrNil
            loadedFinalPDFData = nil
            editorAppearedAt = CFAbsoluteTimeGetCurrent()
            reportedSectionKeys.removeAll()
            showDeferredSections = false
            if isActive {
                scheduleDeferredSections()
            }
            let diagnostic = String(
                format: "publication-editor-reseed publication=%@ reseed_ms=%.2f",
                newValue.title,
                (CFAbsoluteTimeGetCurrent() - seedStartedAt) * 1000
            )
            store.appendPerformanceDiagnostic(diagnostic)
            return
        }

        autosaveTask?.cancel()
        forcedPersistTask?.cancel()
        submissionRowsSyncTask?.cancel()

        let nextSubmissionRows = Self.normalizedSubmissionRows(store.publicationSubmissionRows(for: newValue))
        let nextResolvedJournal = Self.resolveJournal(for: newValue, submissionRows: nextSubmissionRows, store: store)
        let nextRankingSnapshot = Self.makeRankingSnapshot(
            resolvedJournal: nextResolvedJournal,
            publicationYear: newValue.yearValue,
            metricDistributionCache: metricDistributionCache
        )

        suppressDraftAutosave = true
        authorIdentity.reconcileExternal(newValue.authorNames)
        draft = newValue
        isEditingLocked = newValue.isEditingLocked
        submissionRows = nextSubmissionRows
        if workflowStatus != newValue.workflowStatus {
            workflowStatus = newValue.workflowStatus
        }
        if workflowStatusDate != (newValue.workflowStatusDate ?? "") {
            workflowStatusDate = newValue.workflowStatusDate ?? ""
        }
        let normalizedTasks = Self.normalizedPublicationTasks(newValue.publicationTasks)
        if publicationTasks != normalizedTasks {
            publicationTasks = normalizedTasks
        }
        cachedFundingApplications = store.grantedApplications(for: newValue)
        resolvedJournal = nextResolvedJournal
        rankingSnapshot = nextRankingSnapshot
        loadedFinalPDFPath = newValue.finalPDFPath?.trimmedOrNil
        suppressDraftAutosave = false
        scheduleDerivedRefresh(rankings: true, funding: showDeferredSections, pdfPreview: true, forcePDFPreview: true)

        if let returnedJournal = newValue.journal.nonEmpty,
           let pendingSubmissionJournalRowID,
           pendingSubmissionJournalRowID == "append" {
            commitPendingSubmissionJournal(returnedJournal)
            self.pendingSubmissionJournalRowID = nil
            scheduleSubmissionRowsSync()
        } else if let returnedJournal = newValue.journal.nonEmpty,
                  let pendingSubmissionJournalRowID,
                  let index = submissionRows.firstIndex(where: { $0.id == pendingSubmissionJournalRowID }) {
            submissionRows[index].journal = returnedJournal
            self.pendingSubmissionJournalRowID = nil
            scheduleSubmissionRowsSync()
        }
    }

    /// The export corner: an icon strip under an "Exportera" heading.
    /// Simple exports run directly via hover flags (or in the app language on
    /// a plain click); author details and CRediT open their dialogs.
    @ViewBuilder
    private func exportButtons(language: AppLanguage) -> some View {
        if currentStatus == .published || currentStatus == .accepted {
            Menu(language.text("Copy reference", "Kopiera referens")) {
                Button(language.text("According to AMA", "Enligt AMA")) {
                    store.copyAMACitation(for: pendingDraft)
                }
                Button(language.text("Custom…", "Custom…")) {
                    showsReferenceCopySheet = true
                }
            }
            .menuStyle(.borderedButton)
            .fixedSize()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                AppTableHeaderText(text: language.text("Export", "Exportera"))

                HStack(spacing: 0) {
                    ExportIconSegment(
                        systemImage: "list.bullet.rectangle",
                        title: language.text("Journal list", "Tidskriftslista"),
                        help: language.text(
                            "Copy the journal list — hover for language, click for the app language",
                            "Kopiera tidskriftslistan — hovra för språk, klicka för appens språk"
                        ),
                        isEnabled: !visibleSubmissionRows.allSatisfy { $0.trimmedJournal.isEmpty },
                        flagAction: { exportJournalList(language: $0) }
                    ) {
                        exportJournalList(language: store.language)
                    }

                    if showsEthicsExportButton {
                        Divider().frame(height: 34)
                        ExportIconSegment(
                            systemImage: "checkmark.shield",
                            title: language.text("Ethics approval", "Etiktillstånd"),
                            help: language.text(
                                "Copy the ethics statement — hover for language, click for the app language",
                                "Kopiera etiktexten — hovra för språk, klicka för appens språk"
                            ),
                            flagAction: { exportEthicsStatement(language: $0) }
                        ) {
                            exportEthicsStatement(language: store.language)
                        }
                    }

                    Divider().frame(height: 34)
                    ExportIconSegment(
                        systemImage: "person.2",
                        title: language.text("Author details", "Författaruppgifter"),
                        help: language.text("Export author details…", "Exportera författaruppgifter…")
                    ) {
                        showsAuthorExportCustomSheet = true
                    }

                    if hasDefinedCreditRoles {
                        Divider().frame(height: 34)
                        ExportIconSegment(
                            systemImage: "checklist",
                            title: "CRediT",
                            help: language.text("Copy CRediT statement…", "Kopiera CRediT-text…")
                        ) {
                            showsCreditStatementSheet = true
                        }
                    }

                    if store.canExportFundingStatement(for: pendingDraft) {
                        Divider().frame(height: 34)
                        ExportIconSegment(
                            systemImage: "banknote",
                            title: "Funding",
                            help: language.text(
                                "Copy the funding statement, largest funding first — hover for language",
                                "Kopiera funding statement, största funding först — hovra för språk"
                            ),
                            flagAction: { exportFundingStatement(language: $0) }
                        ) {
                            exportFundingStatement(language: store.language)
                        }
                    }
                }
                .background(AppPalette.fieldSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppPalette.subtleBorder, lineWidth: 1)
                )
            }
            .fixedSize()
        }
    }

    private func exportJournalList(language: AppLanguage) {
        store.copyPublicationJournalList(
            journalNames: visibleSubmissionRows.compactMap { $0.trimmedJournal.nonEmpty },
            publicationYear: draft.yearValue,
            languageMode: language == .swedish ? .swedish : .english
        )
    }

    private func exportEthicsStatement(language: AppLanguage) {
        store.copyPublicationEthicsStatement(
            for: pendingDraft,
            languageMode: language == .swedish ? .swedish : .english
        )
    }

    private func exportFundingStatement(language: AppLanguage) {
        store.copyFundingStatement(
            for: pendingDraft,
            languageMode: language == .swedish ? .swedish : .english,
            sortMode: .largestFundingFirst
        )
    }

    /// Shared-authorship toggles, CRediT and group mail as one vertical
    /// column placed immediately right of the author list.
    private func authorSideActionColumn(language: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(language.text("Shared first authorship", "Delad förstaförfattare"), isOn: boolBinding(\.sharedFirstAuthorship))
                .appCheckboxStyle()
                .disabled(draft.authorNames.count < 2)
            Toggle(language.text("Shared last authorship", "Delad sistaförfattare"), isOn: boolBinding(\.sharedLastAuthorship))
                .appCheckboxStyle()
                .disabled(draft.authorNames.count < 2)
            Button(language.text("Define CRediT roles", "Definiera CRediT-roller")) {
                showsCreditRoleSheet = true
            }
            .buttonStyle(.bordered)
            .disabled(draft.authorNames.isEmpty)
            GroupMailButton(
                addresses: store.groupMailAddresses(presentedNames: draft.authorNames),
                language: language
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func authorProjectCollaboratorButtons(language: AppLanguage) -> some View {
        HStack(spacing: 8) {
            Button(language.text("Replace with…", "Ersätt med…")) {
                replaceAuthorsWithProjectCollaborators()
            }
            .buttonStyle(.bordered)
            .disabled(linkedProject == nil)
            .help(language.text("Replace with project collaborators", "Ersätt med projektmedarbetare"))

            Button(language.text("Complete with project collaborators", "Komplettera med projektmedarbetare")) {
                appendMissingAuthorsFromProjectCollaborators()
            }
            .buttonStyle(.bordered)
            .disabled(linkedProject == nil || !hasMissingProjectCollaborators)
        }
    }

    @ViewBuilder
    private func authorPickerArea(language: AppLanguage) -> some View {
        if isEditingLocked {
            lockedAuthorPickerArea(language: language)
        } else {
            // 34 + the 6 pt column spacing puts the name fields at the shared
            // 40 pt content edge (matching the submission grid's handle +
            // status-stripe gutter and the Projekt/Status fields).
            let authorHandleWidth: CGFloat = 34
            let correspondingColumnWidth: CGFloat = 34
            let sharedMarkerWidth: CGFloat = 10
            let authorLinkColumnWidth: CGFloat = 24
            let authorTrashColumnWidth: CGFloat = 28
            let authorNameFieldWidth: CGFloat = ResearcherNameFieldMetrics.compactWidth * 0.8
            let authorRowHeight: CGFloat = AutocompleteSelectionMetrics.fieldMinHeight
            let authorRowSpacing: CGFloat = AutocompleteSelectionMetrics.rowSpacing
            let authorColumnSpacing: CGFloat = 6

            AppEditablePersonTable {
                VStack(alignment: .leading, spacing: authorRowSpacing) {
                    if !draft.authorNames.isEmpty {
                        HStack(spacing: authorColumnSpacing) {
                            Color.clear
                                .frame(width: authorHandleWidth, height: 18)

                            Color.clear
                                .frame(width: authorNameFieldWidth, height: 18)

                            AppTableHeaderText(text: "Corr.")
                                .fixedSize()
                                .frame(width: correspondingColumnWidth, alignment: .center)
                                .help(language.text("Corresponding author", "Korresponderande författare"))

                            Color.clear
                                .frame(width: sharedMarkerWidth, height: 18)

                            Color.clear
                                .frame(width: authorLinkColumnWidth, height: 18)

                            Color.clear
                                .frame(width: authorTrashColumnWidth, height: 18)
                        }
                    }

                    ForEach(authorIdentity.rows(for: draft.authorNames)) { row in
                        let index = row.index
                        HStack(spacing: authorColumnSpacing) {
                            ReorderHandle(itemID: row.id, draggedItemID: $draggedAuthorName, language: language)
                                .frame(width: authorHandleWidth, height: authorRowHeight, alignment: .leading)
                            AutocompleteSelectionField(
                                text: authorBinding(at: index),
                                options: authorOptions,
                                excludedOptions: excludedAuthorOptions(excluding: index),
                                placeholder: displayedAuthorName(at: index, language: language),
                                addNewTitle: language.text("Add new", "Lägg till ny"),
                                display: { authorOptionDisplayName($0, language: language) },
                                onCommit: {
                                    scheduleAutosave()
                                },
                                onAddNew: {
                                    store.beginAddingPublicationAuthor(fromPublicationID: draft.id, at: index)
                                },
                                usesTransparentFieldStyle: false,
                                appliesChrome: true
                            )
                            .frame(width: authorNameFieldWidth, height: authorRowHeight, alignment: .leading)

                            Toggle(isOn: correspondingAuthorBinding(at: index)) {
                                EmptyView()
                            }
                                .appCheckboxStyle()
                                .help(language.text("Corresponding author", "korresponderande författare"))
                                .accessibilityLabel(Text(language.text("Corresponding author", "korresponderande författare")))
                                .frame(width: correspondingColumnWidth, height: authorRowHeight, alignment: .center)

                            if !sharedAuthorshipMarker(at: index).isEmpty {
                                Text(sharedAuthorshipMarker(at: index))
                                    .font(.system(size: 14, weight: .bold))
                                    .frame(width: sharedMarkerWidth, height: authorRowHeight, alignment: .center)
                            } else {
                                Color.clear
                                    .frame(width: sharedMarkerWidth, height: authorRowHeight)
                            }

                            if let author = store.publicationAuthor(matchingPresentedName: draft.authorNames[index]) {
                                AppRouteLinkButton(
                                    title: language.text("Open researcher", "Öppna forskare"),
                                    language: language,
                                    width: authorLinkColumnWidth,
                                    height: authorRowHeight
                                ) {
                                    store.openRoute(for: author)
                                }
                            } else {
                                Color.clear
                                    .frame(width: authorLinkColumnWidth, height: authorRowHeight)
                            }

                            inlineTrashButton {
                                authorIdentity.remove(at: index)
                                draft.authorNames.remove(at: index)
                            }
                            .frame(width: authorTrashColumnWidth, height: authorRowHeight, alignment: .center)
                        }
                        .frame(height: authorRowHeight, alignment: .center)
                        .onDrop(of: [UTType.plainText], delegate: StableStringReorderDropDelegate(
                            targetID: row.id,
                            items: $draft.authorNames,
                            identity: authorIdentity,
                            draggedItemID: $draggedAuthorName
                        ))
                    }
                    HStack(spacing: authorColumnSpacing) {
                        Color.clear
                            .frame(width: authorHandleWidth, height: authorRowHeight)

                        AutocompleteSelectionField(
                            text: $pendingAuthorName,
                            options: authorOptions,
                            excludedOptions: excludedAuthorOptions(),
                            placeholder: language.text("Add author", "Lägg till författare"),
                            addNewTitle: language.text("Add new", "Lägg till ny"),
                            display: { authorOptionDisplayName($0, language: language) },
                            onCommit: {
                                commitPendingAuthor()
                            },
                            onSelect: { selectedName in
                                commitPendingAuthor(selectedName)
                            },
                            onAddNew: {
                                store.beginAddingPublicationAuthor(fromPublicationID: draft.id, at: draft.authorNames.count)
                            },
                            usesTransparentFieldStyle: false,
                            appliesChrome: true
                        )
                        .frame(width: authorNameFieldWidth, height: authorRowHeight, alignment: .leading)
                    }
                    .frame(height: authorRowHeight, alignment: .center)

                    if currentStatus.showsProjectCollaboratorAuthorButtons {
                        HStack(spacing: authorColumnSpacing) {
                            Color.clear
                                .frame(width: authorHandleWidth, height: authorRowHeight)

                            authorProjectCollaboratorButtons(language: language)
                        }
                        .frame(height: authorRowHeight, alignment: .center)
                    }
                }
            }
        }
    }

    private func lockedAuthorPickerArea(language: AppLanguage) -> some View {
        let showsAuthorLinkColumn = draft.authorNames.contains {
            store.publicationAuthor(matchingPresentedName: $0) != nil
        }
        let authorNameFieldWidth: CGFloat = ResearcherNameFieldMetrics.compactWidth * 1.2

        return AppEditablePersonTable {
            VStack(alignment: .leading, spacing: 4) {
                if draft.authorNames.isEmpty {
                    AppMetadataText(text: language.text("No authors", "Inga författare"))
                        .padding(.vertical, 6)
                } else {
                    ForEach(Array(draft.authorNames.indices), id: \.self) { index in
                        HStack(spacing: 8) {
                            AppPersonNameText(
                                name: lockedDisplayedAuthorBaseName(at: index, language: language),
                                details: lockedDisplayedAuthorDetails(at: index, language: language),
                                isCurrentUser: store.isCurrentUserPresentedName(draft.authorNames[index])
                            )
                                .textSelection(.enabled)
                                .frame(width: authorNameFieldWidth, alignment: .leading)
                                .frame(minHeight: 22, alignment: .leading)

                            if showsAuthorLinkColumn {
                                if let author = store.publicationAuthor(matchingPresentedName: draft.authorNames[index]) {
                                    AppRouteLinkButton(
                                        title: language.text("Open researcher", "Öppna forskare"),
                                        language: language,
                                        width: 34
                                    ) {
                                        store.openRoute(for: author)
                                    }
                                } else {
                                    Color.clear.frame(width: 34, height: 20)
                                }
                            }
                        }
                    }
                }
                GroupMailButton(
                    addresses: store.groupMailAddresses(presentedNames: draft.authorNames),
                    language: language
                )
                .padding(.top, 4)
            }
            // Locked rows have no handle/stripe gutter — pad to the shared
            // 40 pt content edge instead.
            .padding(.leading, 40)
        }
    }

    private func persist(silently: Bool = true) {
        persist(baseline: publication, silently: silently)
    }

    private func persist(baseline: PublicationRecord, silently: Bool = true) {
        autosaveTask?.cancel()
        let snapshot = pendingDraft
        guard snapshot != baseline else { return }
        guard let current = store.publication(id: baseline.id) else {
            return
        }
        let candidate: PublicationRecord
        if current == baseline {
            candidate = snapshot
        } else if let merged = PublicationDraftThreeWayMerge.merge(
            baseline: baseline,
            draft: snapshot,
            current: current
        ) {
            candidate = merged
            store.appendPerformanceDiagnostic(
                "publication-editor-three-way-merge publication=\(baseline.id)"
            )
        } else {
            store.notice = StoreNotice(
                message: language.text(
                    "Publication changes were not saved because the record changed elsewhere. Reopen it and review the newer version.",
                    "Publikationsändringarna sparades inte eftersom posten ändrades på annat håll. Öppna den igen och granska den nyare versionen."
                ),
                tone: .error
            )
            return
        }
        guard candidate != current else { return }
        if silently {
            store.autosavePublication(candidate)
        } else {
            store.savePublication(candidate, silently: false)
        }
    }

    private var finalPDFSection: some View {
        let pdfSurfaceFill = (!isEditingLocked && isFinalPDFDropTarget)
            ? AppPalette.activeTabSurface.opacity(0.18)
            : AppPalette.secondaryCardSurface
        let pdfBorderStyle = isEditingLocked
            ? StrokeStyle(lineWidth: 1)
            : StrokeStyle(lineWidth: 1.5, dash: [7, 5])
        let pdfBorderColor = (!isEditingLocked && isFinalPDFDropTarget)
            ? AppPalette.linkAction
            : AppPalette.border

        return Group {
            if hasFinalPDFAttachment, finalPDFPreviewIsAvailable {
                // Free-standing preview window: no title row, no hide
                // control — just one full A4 page, centered, with the open
                // button (and edit actions when unlocked) on its right.
                HStack(alignment: .top, spacing: 12) {
                    AppPDFDocumentView(pdfURL: resolvedFinalPDFURL, pdfData: finalPDFData)
                        .frame(width: 760, height: 1090)
                        .background(
                            RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                                .fill(AppPalette.fieldSurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                                .stroke(AppPalette.border, lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 8) {
                        if let label = finalPDFDisplayLabel ?? finalPDFFilename {
                            Text(label)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(4)
                                .frame(maxWidth: 220, alignment: .leading)
                                .help(finalPDFOriginalFilenameHelp)
                        }

                        Button(language.text("Open PDF", "Öppna PDF")) {
                            openFinalPDF()
                        }
                        .buttonStyle(.bordered)

                        if !isEditingLocked {
                            Button(language.text("Replace…", "Ersätt…")) {
                                chooseFinalPDF()
                            }
                            .buttonStyle(.bordered)

                            Button(language.text("Remove", "Ta bort")) {
                                removeFinalPDFAttachment()
                            }
                            .buttonStyle(.bordered)
                            .help(language.text("Remove publication PDF", "Ta bort publikations-PDF"))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isFinalPDFDropTarget, perform: handleFinalPDFDrop)
            } else {
                AppPDFAttachmentControl(
                    language: language,
                    filename: finalPDFFilename,
                    displayLabel: finalPDFDisplayLabel,
                    placeholder: language.text("Drop PDF here", "Släpp PDF här"),
                    hasAttachment: hasFinalPDFAttachment,
                    isAvailable: finalPDFPreviewIsAvailable != false,
                    isEditingLocked: isEditingLocked,
                    style: .prominent,
                    showsLeadingIcon: true,
                    removeTitle: language.text("Remove publication PDF", "Ta bort publikations-PDF"),
                    chooseAction: chooseFinalPDF,
                    openAction: openFinalPDF,
                    removeAction: removeFinalPDFAttachment
                )
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                        .fill(pdfSurfaceFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppPalette.mediumCornerRadius, style: .continuous)
                        .strokeBorder(style: pdfBorderStyle)
                        .foregroundStyle(pdfBorderColor)
                )
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isFinalPDFDropTarget, perform: handleFinalPDFDrop)
            }
        }
    }

    private func removeFinalPDFAttachment() {
        draft.finalPDFFilename = nil
        draft.finalPDFPath = nil
        loadedFinalPDFPath = nil
        loadedFinalPDFData = nil
        scheduleAutosave()
    }

    private var finalPDFURL: URL? {
        guard let path = draft.finalPDFPath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { return nil }
        return GrantDataStore.absoluteAttachmentURL(fromStored: path)
    }

    private var resolvedFinalPDFURL: URL? {
        GrantDataStore.resolvePublicationPDFURL(
            publicationID: draft.id,
            finalPDFPath: draft.finalPDFPath,
            finalPDFFilename: finalPDFFilename
        )
    }

    private var finalPDFFilename: String? {
        draft.finalPDFFilename ?? finalPDFURL?.lastPathComponent
    }

    /// F1b: the PDF is shown under a name built from the publication; the
    /// original file name is kept as the tooltip.
    private var finalPDFDisplayLabel: String? {
        AttachmentLabels.publication(draft, language: language)
    }

    private var finalPDFOriginalFilenameHelp: String {
        guard finalPDFDisplayLabel != nil, let original = finalPDFFilename?.trimmedOrNil else { return "" }
        return language.text("Original file name: \(original)", "Ursprungligt filnamn: \(original)")
    }

    private var hasFinalPDFAttachment: Bool {
        finalPDFFilename != nil || finalPDFURL != nil
    }

    private var finalPDFData: Data? {
        loadedFinalPDFData
    }

    private var finalPDFPreviewIsAvailable: Bool {
        if resolvedFinalPDFURL != nil {
            return true
        }
        return finalPDFData != nil
    }

    private func handleFinalPDFDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !isEditingLocked else { return false }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            let resolvedURL: URL?
            if let data = item as? Data {
                resolvedURL = NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL?
            } else if let url = item as? URL {
                resolvedURL = url
            } else {
                resolvedURL = nil
            }
            DispatchQueue.main.async {
                guard let resolvedURL else {
                    store.reportFileActionFailure(
                        language.text("Could not attach the dropped publication PDF.", "Kunde inte bifoga den släppta publikations-PDF-filen."),
                        error: error ?? CocoaError(.fileReadUnknown)
                    )
                    return
                }
                setFinalPDF(from: resolvedURL)
            }
        }
        return true
    }

    private func chooseFinalPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = language.text("Choose", "Välj")
        panel.title = language.text("Choose final PDF", "Välj slutlig PDF")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setFinalPDF(from: url)
    }

    private func setFinalPDF(from url: URL) {
        do {
            let data = try loadPDFDataForUserAction(from: url)
            let managedURL = try GrantDataStore.persistManagedPublicationPDF(
                data: data,
                forPublicationID: draft.id
            )
            draft.finalPDFFilename = url.lastPathComponent
            draft.finalPDFPath = GrantDataStore.portableAttachmentPath(for: managedURL)
            loadedFinalPDFPath = managedURL.path
            loadedFinalPDFData = data
        } catch {
            store.reportFileActionFailure(
                language.text("Could not attach the publication PDF.", "Kunde inte bifoga publikations-PDF-filen."),
                error: error
            )
            return
        }
        scheduleAutosave()
    }

    private func openFinalPDF() {
        if let resolvedFinalPDFURL {
            store.openFileForUserAction(
                resolvedFinalPDFURL,
                failureMessage: language.text("Could not open the publication PDF.", "Kunde inte öppna publikations-PDF-filen.")
            )
            return
        }
        guard let data = finalPDFData else {
            store.reportFileActionFailure(
                language.text("Could not open the publication PDF.", "Kunde inte öppna publikations-PDF-filen."),
                error: CocoaError(.fileNoSuchFile)
            )
            return
        }
        let filename = finalPDFFilename ?? "publication.pdf"
        let targetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: targetURL, options: .atomic)
            exportedFinalPDFURL = targetURL
            store.openFileForUserAction(
                targetURL,
                failureMessage: language.text("Could not open the publication PDF.", "Kunde inte öppna publikations-PDF-filen.")
            )
        } catch {
            store.reportFileActionFailure(
                language.text("Could not open the publication PDF.", "Kunde inte öppna publikations-PDF-filen."),
                error: error
            )
        }
    }

    private func refreshFinalPDFPreview(force: Bool = false) {
        guard showsFinalPDFPreview else {
            loadedFinalPDFPath = resolvedFinalPDFURL?.path ?? draft.finalPDFPath?.trimmedOrNil
            loadedFinalPDFData = nil
            return
        }

        let nextPath = resolvedFinalPDFURL?.path ?? draft.finalPDFPath?.trimmedOrNil
        if !force, loadedFinalPDFPath == nextPath {
            return
        }

        loadedFinalPDFPath = nextPath
        guard let nextPath else {
            loadedFinalPDFData = nil
            return
        }

        let pathSnapshot = nextPath
        let url = URL(fileURLWithPath: pathSnapshot)
        DispatchQueue.global(qos: .userInitiated).async {
            let data = try? Data(contentsOf: url)
            DispatchQueue.main.async {
                guard loadedFinalPDFPath == pathSnapshot else { return }
                if let data, !data.isEmpty {
                    loadedFinalPDFData = data
                } else {
                    loadedFinalPDFData = nil
                }
            }
        }
    }

    private func refreshResolvedJournalAndRankings() {
        let nextResolvedJournal = Self.resolveJournal(for: draft, submissionRows: submissionRows, store: store)
        resolvedJournal = nextResolvedJournal
        rankingSnapshot = Self.makeRankingSnapshot(
            resolvedJournal: nextResolvedJournal,
            publicationYear: draft.yearValue,
            metricDistributionCache: metricDistributionCache
        )
    }

    private func reportEditorReadyIfNeeded() {
        guard !hasReportedReady else { return }
        hasReportedReady = true
        DispatchQueue.main.async {
            onEditorReady?(publication.id)
        }
    }

    private func scheduleDeferredSections() {
        deferredSectionsTask?.cancel()
        guard isActive else {
            showDeferredSections = false
            return
        }
        let task = DispatchWorkItem {
            showDeferredSections = true
            deferredSectionsTask = nil
            scheduleDerivedRefresh(funding: true)
            store.appendPerformanceDiagnostic("publication-deferred-sections-ready publication=\(publication.title)")
        }
        deferredSectionsTask = task
        DispatchQueue.main.async(execute: task)
    }

    private func reportSectionReadyIfNeeded(_ sectionKey: String) {
        guard !reportedSectionKeys.contains(sectionKey),
              let editorAppearedAt else { return }
        reportedSectionKeys.insert(sectionKey)
        let duration = (CFAbsoluteTimeGetCurrent() - editorAppearedAt) * 1000
        store.appendPerformanceDiagnostic(
            String(
                format: "publication-section-ready publication=%@ section=%@ section_ms=%.2f",
                publication.title,
                sectionKey,
                duration
            )
        )
    }

    private static func resolveJournal(
        for publication: PublicationRecord,
        submissionRows: [PublicationSubmissionEditorRow],
        store: GrantDataStore
    ) -> PublicationJournal? {
        let candidates = [
            publication.journal,
            submissionRows.last(where: { $0.journal.nonEmpty != nil })?.journal ?? "",
            publication.statusTimeline
                .sorted(by: {
                    let lhs = $0.date.flatMap { DateParsers.isoDay.date(from: $0) } ?? Date.distantPast
                    let rhs = $1.date.flatMap { DateParsers.isoDay.date(from: $0) } ?? Date.distantPast
                    return lhs > rhs
                })
                .first(where: { $0.journal.nonEmpty != nil })?
                .journal ?? ""
        ]

        // "Alla kopplingar via id": the publication's linked journal first.
        if let linked = store.publicationJournal(id: publication.journalID) {
            return linked
        }
        return candidates.compactMap { store.publicationJournal(named: $0) }.first
    }

    private static func makeRankingSnapshot(
        resolvedJournal: PublicationJournal?,
        publicationYear: Int?,
        metricDistributionCache: PublicationMetricDistributionCache
    ) -> PublicationEditorRankingSnapshot {
        guard let resolvedJournal else {
            return .empty
        }

        func color(for metric: PublicationMetricValue?) -> Color? {
            metricDistributionCache.backgroundColor(for: metric, publicationYear: publicationYear)
        }

        let scieJIFMetric = resolvedJournal.metric(for: .clarivateScieJIF, publicationYear: publicationYear)
        let scieJCIMetric = resolvedJournal.metric(for: .clarivateScieJCI, publicationYear: publicationYear)
        let esciJIFMetric = resolvedJournal.metric(for: .clarivateEsciJIF, publicationYear: publicationYear)
        let esciJCIMetric = resolvedJournal.metric(for: .clarivateEsciJCI, publicationYear: publicationYear)
        let sjrMetric = resolvedJournal.metric(for: .scimagoSJR, publicationYear: publicationYear)
        let norwegianMetric = resolvedJournal.metric(for: .norwegianList, publicationYear: publicationYear)

        return PublicationEditorRankingSnapshot(
            scieJIFMetric: scieJIFMetric,
            scieJIFColor: color(for: scieJIFMetric),
            scieJCIMetric: scieJCIMetric,
            scieJCIColor: color(for: scieJCIMetric),
            esciJIFMetric: esciJIFMetric,
            esciJIFColor: color(for: esciJIFMetric),
            esciJCIMetric: esciJCIMetric,
            esciJCIColor: color(for: esciJCIMetric),
            sjrMetric: sjrMetric,
            sjrColor: color(for: sjrMetric),
            norwegianMetric: norwegianMetric,
            norwegianColor: color(for: norwegianMetric)
        )
    }

    private func scheduleDerivedRefresh(
        rankings: Bool = false,
        funding: Bool = false,
        pdfPreview: Bool = false,
        forcePDFPreview: Bool = false
    ) {
        needsRankingRefresh = needsRankingRefresh || rankings
        needsFundingRefresh = needsFundingRefresh || funding
        needsPDFPreviewRefresh = needsPDFPreviewRefresh || pdfPreview
        needsForcedPDFPreviewRefresh = needsForcedPDFPreviewRefresh || forcePDFPreview
        guard isActive else { return }

        derivedRefreshTask?.cancel()
        let task = DispatchWorkItem {
            let refreshRankings = needsRankingRefresh
            let refreshFunding = needsFundingRefresh
            let refreshPDF = needsPDFPreviewRefresh
            let forcePDF = needsForcedPDFPreviewRefresh

            needsRankingRefresh = false
            needsFundingRefresh = false
            needsPDFPreviewRefresh = false
            needsForcedPDFPreviewRefresh = false
            derivedRefreshTask = nil

            if refreshFunding {
                refreshFundingApplications()
            }
            if refreshRankings {
                refreshResolvedJournalAndRankings()
            }
            if refreshPDF {
                refreshFinalPDFPreview(force: forcePDF)
            }
        }
        derivedRefreshTask = task
        let delay: TimeInterval = needsRankingRefresh || needsFundingRefresh ? 0.24 : 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    private func refreshAuthorOptions() {
        cachedAuthorOptions = store.publicationAuthorOptionNames
    }

    private func refreshJournalOptions() {
        cachedJournalOptions = store.publicationJournalOptionNames
    }

    private func refreshFundingApplications() {
        cachedFundingApplications = store.grantedApplications(for: pendingDraft)
    }

    private func inlineTrashButton(action: @escaping () -> Void) -> some View {
        AppIconDeleteButton(
            title: language.text("Delete", "Ta bort"),
            font: .system(size: 12, weight: .semibold),
            width: 28,
            action: action
        )
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let task = DispatchWorkItem { persist() }
        autosaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: task)
    }

    private func requestImmediatePersist() {
        guard !suppressDraftAutosave else { return }
        forcedPersistTask?.cancel()
        let task = DispatchWorkItem {
            forcedPersistTask = nil
            persist()
        }
        forcedPersistTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: task)
    }

    private func handlePublicationTasksChange(_ newValue: [PublicationTaskItem]) {
        let normalized = Self.normalizedPublicationTasks(newValue)
        if normalized != newValue {
            publicationTasks = normalized
            return
        }
        scheduleAutosave()
    }

    @ViewBuilder
    private func citationHeaderRow(language: AppLanguage) -> some View {
        HStack(spacing: 8) {
            Text("")
                .frame(width: 150)
            ForEach(citationDisplayYears, id: \.self) { year in
                citationHeaderCell(year: year)
            }
            AppTableHeaderText(text: language.text("Total", "Totalt"))
                .frame(width: 72)
        }
    }

    @ViewBuilder
    private func citationEditorRow(title: String, kind: CitationInputKind) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .appTypography(.body)
                .frame(width: 150, alignment: .leading)
            ForEach(citationDisplayYears, id: \.self) { year in
                TextField("0", text: citationYearCountBinding(year, kind: kind))
                    .font(appFont(.body))
                    .appTextInputChrome()
                    .frame(width: 72)
            }
            Text(String(editorCitationTotal(kind: kind)))
                .appTypography(.tableHeader)
                .frame(width: 72)
        }
    }

    @ViewBuilder
    private func citationTotalRow(language: AppLanguage) -> some View {
        HStack(spacing: 8) {
            AppTableHeaderText(text: language.text("Total citations", "Citeringar totalt"))
                .frame(width: 150, alignment: .leading)
            ForEach(citationDisplayYears, id: \.self) { year in
                Text(String(editorCitationTotal(year: year)))
                    .appTypography(.tableHeader)
                    .frame(width: 72)
            }
            Text(String(editorCitationTotal))
                .appTypography(.tableHeader)
                .frame(width: 72)
        }
    }

    @ViewBuilder
    private func citationHeaderCell(year: Int) -> some View {
        AppTableHeaderText(text: String(year))
            .frame(width: 72)
    }

    private func publicationWorkflowContent(language: AppLanguage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if !isEditingLocked || workflowStatus != nil {
                compactField(language.text("Status", "Status"), width: 240) {
                publicationMenuField(
                    selection: Binding<PublicationWorkflowStatus?>(
                        get: { workflowStatus },
                        set: { workflowStatus = $0 }
                    ),
                    options: [(language.text("Select status", "Välj status"), PublicationWorkflowStatus?.none)]
                        + PublicationWorkflowStatus.allCases.map { ($0.displayName(language: language), Optional($0)) },
                    placeholder: language.text("Select status", "Välj status")
                )
            }
            }

            if shouldShowPublicationFieldInCurrentLockState(workflowStatusDate) {
                compactField(language.text("Date", "Datum"), width: 164) {
                OptionalDateField(
                    dateString: Binding(
                        get: { workflowStatusDate },
                        set: { workflowStatusDate = DateParsers.canonicalizedDayInput($0) }
                    ),
                    language: language,
                    isIllogical: illogicalPublicationEditorDateKeys.contains(PublicationDateValidationFieldKey.workflowStatusDate),
                    isDisabled: isEditingLocked
                )
            }
            }
            Spacer()
        }
    }

    private func publicationTaskListContent(language: AppLanguage) -> some View {
        CentralTaskListSection(
            store: store,
            linkKind: .publication,
            targetID: publication.id,
            language: language,
            reminderOptions: ProjectTaskReminder.allCases,
            isReadOnly: isEditingLocked,
            showsAddButton: false
        )
    }

    private func fundingApplicationsContent(language: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                presentationHeaderText(language.text("Grant provider", "Anslagsgivare"), alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                presentationHeaderText(language.text("Case number", "Diarienummer"), width: 160, alignment: .leading)
                presentationHeaderText(language.text("Granted amount", "Beviljat belopp"), width: 140, alignment: .trailing)
            }
            Divider()

            ForEach(fundingApplications, id: \.id) { application in
                Button(action: { store.openRoute(for: application) }) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(store.organizationLabel(for: application, language: language))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(application.appliedCaseNumber?.trimmedOrNil ?? "—")
                            .foregroundStyle(.secondary)
                            .frame(width: 160, alignment: .leading)
                        Text(store.formattedGrantAmountWithSEKApproximation(application.grantedAmountValue, for: application))
                            .foregroundStyle(.secondary)
                            .frame(width: 140, alignment: .trailing)
                    }
                    .font(appFont(.body))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func presentationRowsContent(language: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                presentationHeaderText(language.text("Date", "Datum"), width: 96, alignment: .leading)
                presentationHeaderText(language.text("Activity", "Aktivitet"), width: 220, alignment: .leading)
                presentationHeaderText(language.text("Organization", "Organisation"), width: 220, alignment: .leading)
                presentationHeaderText(
                    language.text("Implementation (Comment, Place, Country)", "Genomförande (Kommentar, Plats, Land)"),
                    alignment: .leading
                )
                presentationHeaderText("", width: 88, alignment: .trailing)
            }
            Divider()

            ForEach(presentationRows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Button {
                        store.revealCalendarWorkspace(on: row.displayDate, eventSource: .meeting(row.meetingID))
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(row.dateText)
                                .font(appFont(.body))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 96, alignment: .leading)
                            Text(row.activity)
                                .font(appFont(.body))
                                .lineLimit(2)
                                .frame(width: 220, alignment: .leading)
                            Text(row.organization)
                                .font(appFont(.body))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .frame(width: 220, alignment: .leading)
                            Text(row.implementation)
                                .font(appFont(.body))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.revealCalendarWorkspace(on: row.displayDate, eventSource: .meeting(row.meetingID))
                    } label: {
                        Label(language.text("Calendar", "Kalender"), systemImage: "calendar")
                            .appTypography(.tableHeader)
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(AppPalette.linkAction)
                    }
                    .buttonStyle(.plain)
                    .help(language.text("Open in calendar", "Öppna i kalendern"))
                    .frame(width: 88, alignment: .trailing)
                }
            }
        }
    }

    private func presentationHeaderText(_ text: String, width: CGFloat? = nil, alignment: Alignment = .leading) -> some View {
        Text(text)
            .font(appFont(.fieldLabel))
            .foregroundStyle(AppPalette.appText)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
    }

    private func presentationOrganizationText(for meeting: CalendarMeetingRecord, language: AppLanguage) -> String {
        let labels = meeting.organizationIDs.compactMap { organizationID in
            store.organization(id: organizationID)?.displayName(for: language)
        }
        let uniqueLabels = Array(NSOrderedSet(array: labels.compactMap(\.trimmedOrNil))) as? [String]
            ?? labels.compactMap(\.trimmedOrNil)
        return uniqueLabels.joined(separator: ", ").trimmedOrNil ?? "—"
    }

    private func presentationImplementationText(for meeting: CalendarMeetingRecord, language: AppLanguage) -> String {
        let meetingMode = CalendarMeetingMode(rawValue: meeting.meetingMode)
        let modeText = meetingMode == .physical ? nil : meetingMode?.localizedName(language: language)
        let placeText = formattedCalendarPlace(
            city: meeting.place,
            country: meeting.country,
            language: language,
            countryDisplayMode: store.calendarCountryDisplayMode
        ).trimmedOrNil
        let parts = [
            modeText?.trimmedOrNil,
            meeting.detail.trimmedOrNil,
            placeText
        ].compactMap { $0 }
        return parts.joined(separator: " · ").trimmedOrNil ?? "—"
    }

    private static func normalizedPublicationTasks(_ tasks: [PublicationTaskItem]) -> [PublicationTaskItem] {
        normalizedPublicationTaskItems(tasks)
    }

    private func binding(_ keyPath: WritableKeyPath<PublicationRecord, String>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { draft[keyPath: keyPath] = $0 }
        )
    }

private func publicationSurfaceTextField(
        _ placeholder: String,
        text: Binding<String>,
        formatter: @escaping (String) -> String = { $0 },
        state: AppFieldVisualState = .normal,
        updatesContinuously: Bool = true
) -> some View {
        AppLockableField(
            isLocked: isEditingLocked,
            lockedText: text.wrappedValue,
            state: state
        ) {
                CommitFormattingTextField(
                    placeholder: placeholder,
                    text: text,
                    formatter: formatter,
                    updatesContinuously: updatesContinuously,
                    showsRenewedSurface: false,
                    isBordered: false,
                    visualState: state
                )
                .frame(minHeight: 18)
                .appTextInputChrome(fill: state.fill, stroke: state.stroke)
                .appExplicitInvalidFieldChrome(state)
                .help(state.helpText ?? "")
        }
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<PublicationRecord, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = $0.trimmedOrNil }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<PublicationRecord, Bool>) -> Binding<Bool> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { draft[keyPath: keyPath] = $0 }
        )
    }

    private func authorBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard draft.authorNames.indices.contains(index) else { return "" }
                return draft.authorNames[index]
            },
            set: { newValue in
                let trimmed = newValue.trimmedOrNil
                if draft.authorNames.indices.contains(index) {
                    if let trimmed {
                        authorIdentity.updateValue(at: index, to: trimmed)
                        draft.authorNames[index] = trimmed
                    } else {
                        authorIdentity.remove(at: index)
                        draft.authorNames.remove(at: index)
                    }
                }
            }
        )
    }

    private var linkedProject: ProjectRecord? {
        store.linkedProject(of: draft)
    }

    private var linkedProjectCollaboratorNames: [String] {
        uniquedAuthorNames(linkedProject?.collaboratorNames ?? [])
    }

    private var hasMissingProjectCollaborators: Bool {
        let currentNames = Set(
            draft.authorNames
                .map(authorIdentityKey)
                .filter { !$0.isEmpty }
        )
        return linkedProjectCollaboratorNames.contains { !currentNames.contains(authorIdentityKey($0)) }
    }

    private func normalizedAuthorName(_ name: String) -> String {
        normalizedCreditAuthorName(name)
    }

    private func authorIdentityKey(_ name: String) -> String {
        if let authorID = store.publicationAuthor(matchingPresentedName: name)?.id {
            return "author:\(authorID)"
        }
        let normalized = normalizedAuthorName(name)
        return normalized.isEmpty ? "" : "name:\(normalized)"
    }

    private func uniquedAuthorNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.compactMap(\.trimmedOrNil).filter { name in
            let key = authorIdentityKey(name)
            guard !key.isEmpty else { return false }
            return seen.insert(key).inserted
        }
    }

    private func commitPendingAuthor(_ selectedName: String? = nil) {
        guard let trimmed = (selectedName ?? pendingAuthorName).trimmedOrNil else { return }
        let candidateKey = authorIdentityKey(trimmed)
        guard !draft.authorNames.contains(where: { authorIdentityKey($0) == candidateKey }) else {
            pendingAuthorName = ""
            return
        }
        authorIdentity.append(value: trimmed)
        draft.authorNames.append(trimmed)
        pendingAuthorName = ""
        scheduleAutosave()
    }

    private func replaceAuthorsWithProjectCollaborators() {
        guard linkedProject != nil else { return }
        let updated = linkedProjectCollaboratorNames
        guard draft.authorNames != updated else { return }
        pendingAuthorName = ""
        authorIdentity.reconcileExternal(updated)
        draft.authorNames = updated
        scheduleAutosave()
    }

    private func appendMissingAuthorsFromProjectCollaborators() {
        guard linkedProject != nil else { return }
        let existingNames = Set(
            draft.authorNames
                .map(authorIdentityKey)
                .filter { !$0.isEmpty }
        )
        let missingNames = linkedProjectCollaboratorNames.filter {
            !existingNames.contains(authorIdentityKey($0))
        }
        guard !missingNames.isEmpty else { return }
        pendingAuthorName = ""
        missingNames.forEach { authorIdentity.append(value: $0) }
        draft.authorNames += missingNames
        scheduleAutosave()
    }

    private func displayedAuthorName(at index: Int, language: AppLanguage) -> String {
        guard draft.authorNames.indices.contains(index) else {
            return language.text("Select author", "Välj författare")
        }
        let authorName = draft.authorNames[index]
        return authorName + sharedAuthorshipMarker(at: index)
    }

    private func lockedDisplayedAuthorBaseName(at index: Int, language: AppLanguage) -> String {
        guard draft.authorNames.indices.contains(index) else {
            return language.text("Select author", "Välj författare")
        }
        return draft.authorNames[index] + sharedAuthorshipMarker(at: index)
    }

    private func lockedDisplayedAuthorDetails(at index: Int, language: AppLanguage) -> [String] {
        guard draft.authorNames.indices.contains(index) else { return [] }
        let authorName = draft.authorNames[index]
        if draft.isCorrespondingAuthor(named: authorName) {
            return [language.text("Corresponding author", "korresponderande författare")]
        }
        return []
    }

    private func sharedAuthorshipMarker(at index: Int) -> String {
        if draft.sharedFirstAuthorship && index < min(2, draft.authorNames.count) {
            return "*"
        }
        if draft.sharedLastAuthorship && index >= max(0, draft.authorNames.count - 2) {
            return "*"
        }
        return ""
    }

    private func correspondingAuthorBinding(at index: Int) -> Binding<Bool> {
        Binding(
            get: {
                guard draft.authorNames.indices.contains(index) else { return false }
                return draft.isCorrespondingAuthor(named: draft.authorNames[index])
            },
            set: { isSelected in
                guard draft.authorNames.indices.contains(index) else { return }
                draft.setCorrespondingAuthor(
                    named: draft.authorNames[index],
                    isSelected: isSelected
                )
            }
        )
    }

    private func creditRoleBinding(for authorName: String, role: PublicationCreditRole) -> Binding<Bool> {
        Binding(
            get: {
                draft.creditRoles(forAuthorName: authorName).contains(role)
            },
            set: { isSelected in
                var roles = draft.creditRoles(forAuthorName: authorName)
                if isSelected {
                    roles.insert(role)
                } else {
                    roles.remove(role)
                }
                draft.setCreditRoles(roles, forAuthorName: authorName)
            }
        )
    }

    private func syncAuthorDependentAssignments(previousAuthorNames: [String], newAuthorNames: [String]) {
        syncCorrespondingAuthorSelection(previousAuthorNames: previousAuthorNames, newAuthorNames: newAuthorNames)
        syncCreditRoleAssignments(previousAuthorNames: previousAuthorNames, newAuthorNames: newAuthorNames)
    }

    private func syncCorrespondingAuthorSelection(previousAuthorNames: [String], newAuthorNames: [String]) {
        guard previousAuthorNames != newAuthorNames,
              let previousCorrespondingAuthor = draft.correspondingAuthorName?.trimmedOrNil else { return }

        let normalizedPreviousCorrespondingAuthor = normalizedAuthorName(previousCorrespondingAuthor)
        guard !normalizedPreviousCorrespondingAuthor.isEmpty else {
            draft.correspondingAuthorName = nil
            return
        }

        if let matchingAuthor = newAuthorNames.first(where: {
            normalizedAuthorName($0) == normalizedPreviousCorrespondingAuthor
        }) {
            draft.correspondingAuthorName = matchingAuthor
            return
        }

        if previousAuthorNames.count == newAuthorNames.count,
           let previousIndex = previousAuthorNames.firstIndex(where: {
               normalizedAuthorName($0) == normalizedPreviousCorrespondingAuthor
           }),
           newAuthorNames.indices.contains(previousIndex) {
            draft.correspondingAuthorName = newAuthorNames[previousIndex].trimmedOrNil
            return
        }

        draft.correspondingAuthorName = nil
    }

    private func syncCreditRoleAssignments(previousAuthorNames: [String], newAuthorNames: [String]) {
        guard previousAuthorNames != newAuthorNames else { return }

        let previousAssignments = draft.creditRoleAssignments
        let normalizedNewNames = Set(newAuthorNames.map(normalizedCreditAuthorName))
        struct AssignmentState {
            var roles: Set<PublicationCreditRole>
            var contributions: [PublicationCreditRole: PublicationCreditRoleContribution]
        }
        var stateByNormalizedName = [String: AssignmentState]()

        for assignment in previousAssignments {
            let normalizedName = normalizedCreditAuthorName(assignment.authorName)
            guard !normalizedName.isEmpty else { continue }
            let contributions = assignment.roleContributions.reduce(into: [PublicationCreditRole: PublicationCreditRoleContribution]()) { partialResult, entry in
                partialResult[entry.role] = entry.contribution
            }
            stateByNormalizedName[normalizedName] = AssignmentState(
                roles: Set(assignment.roles),
                contributions: contributions
            )
        }

        var rebuiltAssignments: [PublicationCreditAssignment] = []
        rebuiltAssignments.reserveCapacity(newAuthorNames.count)

        for (index, newAuthorName) in newAuthorNames.enumerated() {
            let normalizedNewName = normalizedCreditAuthorName(newAuthorName)
            guard !normalizedNewName.isEmpty else { continue }

            var state = stateByNormalizedName[normalizedNewName]
            if state?.roles.isEmpty ?? true,
               previousAuthorNames.indices.contains(index) {
                let previousNameAtIndex = previousAuthorNames[index]
                let normalizedPreviousName = normalizedCreditAuthorName(previousNameAtIndex)
                if !normalizedPreviousName.isEmpty,
                   !normalizedNewNames.contains(normalizedPreviousName) {
                    state = stateByNormalizedName[normalizedPreviousName]
                }
            }

            let roles = state?.roles ?? []
            guard !roles.isEmpty else { continue }
            let roleContributions = (state?.contributions ?? [:])
                .filter { roles.contains($0.key) }
                .map { key, value in
                    PublicationCreditRoleContributionEntry(role: key, contribution: value)
                }
                .sorted { $0.role.sortIndex < $1.role.sortIndex }
            rebuiltAssignments.append(
                PublicationCreditAssignment(
                    authorName: newAuthorName,
                    roles: Array(roles).sorted { $0.sortIndex < $1.sortIndex },
                    roleContributions: roleContributions
                )
            )
        }

        if draft.creditRoleAssignments != rebuiltAssignments {
            draft.creditRoleAssignments = rebuiltAssignments
        }
    }

    private var citationDisplayYears: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        let startYear = min(draft.yearValue ?? currentYear, currentYear)
        return Array(startYear...currentYear)
    }

    private var showsBibliographyAndCitations: Bool {
        submissionRows.contains { row in
            row.acceptedDate?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                || row.publishedDate?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    private var hasVisibleLockedBibliographyFields: Bool {
        [
            draft.volume,
            draft.issue,
            draft.pageRange,
            draft.articleNumber,
            bibliographyPublishedDateValue,
            draft.doi,
            draft.epubDate,
            draft.pmid
        ].contains { $0.trimmedOrNil != nil }
    }

    private var hasVisibleLockedWorkflowFields: Bool {
        workflowStatus != nil || workflowStatusDate.trimmedOrNil != nil
    }

    private enum CitationInputKind: Equatable {
        case regular
        case selfCitation
    }

    private func citationYearCountBinding(_ year: Int, kind: CitationInputKind) -> Binding<String> {
        Binding(
            get: {
                guard let entry = draft.citationYears.first(where: { $0.year == String(year) }) else {
                    return ""
                }
                switch kind {
                case .regular:
                    return entry.count
                case .selfCitation:
                    return entry.selfCitationCount
                }
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if let index = draft.citationYears.firstIndex(where: { $0.year == String(year) }) {
                    switch kind {
                    case .regular:
                        draft.citationYears[index].count = trimmed
                    case .selfCitation:
                        draft.citationYears[index].selfCitationCount = trimmed
                    }
                    if draft.citationYears[index].count.trimmedOrNil == nil &&
                        draft.citationYears[index].selfCitationCount.trimmedOrNil == nil {
                        draft.citationYears.remove(at: index)
                    }
                } else if !trimmed.isEmpty {
                    draft.citationYears.append(
                        PublicationCitationYear(
                            year: String(year),
                            count: kind == .regular ? trimmed : "",
                            selfCitationCount: kind == .selfCitation ? trimmed : ""
                        )
                    )
                }
                draft.normalize()
                draft.citations = String(editorCitationTotal)
            }
        )
    }

    private func editorCitationTotal(kind: CitationInputKind) -> Int {
        switch kind {
        case .regular:
            return draft.citationYears.map(\.countValue).reduce(0, +)
        case .selfCitation:
            return draft.citationYears.map(\.selfCitationCountValue).reduce(0, +)
        }
    }

    private func editorCitationTotal(year: Int) -> Int {
        draft.citationYears
            .first(where: { $0.year == String(year) })?
            .totalCitationCountValue ?? 0
    }

    private var editorCitationTotal: Int {
        draft.citationYears.map(\.totalCitationCountValue).reduce(0, +)
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

    private func localizedPositionValue(_ value: String, language: AppLanguage) -> String {
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

    private func localizedYesNoValue(_ value: String, language: AppLanguage) -> String {
        switch value {
        case "Yes":
            language.text("Yes", "Ja")
        case "No":
            language.text("No", "Nej")
        default:
            "–"
        }
    }

    private func localizedGeographyValue(_ value: String, language: AppLanguage) -> String {
        switch value {
        case "International":
            language.text("International", "Internationell")
        case "National":
            language.text("National", "Nationell")
        default:
            "–"
        }
    }

    private func localizedPhDValue(_ value: String, language: AppLanguage) -> String {
        switch value {
        case "After":
            language.text("After", "Efter")
        case "Before":
            language.text("Before", "Före")
        default:
            "–"
        }
    }

    @ViewBuilder
    private func publicationMenuField<Value: Hashable>(
        selection: Binding<Value>,
        options: [(label: String, value: Value)],
        placeholder: String? = nil,
        width: CGFloat? = nil
    ) -> some View {
        if isEditingLocked {
            lockedPublicationValueText(
                options.first(where: { $0.value == selection.wrappedValue })?.label ?? placeholder
            )
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : width, alignment: .leading)
        } else {
            Group {
                if AppRuntime.usesRenewedChrome {
                AppMenuSelectionField(selection: selection, options: options, placeholder: placeholder)
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
        }
    }

    private func lockedPublicationValueText(_ value: String?) -> some View {
        AppLockedInlineValueText(text: value)
    }

    private func shouldShowPublicationFieldInCurrentLockState(_ value: String?) -> Bool {
        AppLockedFieldVisibility.shouldShow(isLocked: isEditingLocked, value: value)
    }

    @ViewBuilder
    private func publicationSubmissionGrid(language: AppLanguage) -> some View {
        // The reorder gutter is reserved in locked mode too, so the journal
        // fields sit at the shared 40 pt content edge in both modes.
        let reorderColumnWidth: CGFloat = 20
        let statusSpacing: CGFloat = isEditingLocked ? 6 : 6
        let metricsSpacing: CGFloat = 4
        let statusMarkerColumnWidth: CGFloat = 8
        let journalColumnWidth: CGFloat = isEditingLocked ? 420 : 280
        let dateColumnWidth: CGFloat = isEditingLocked ? 104 : 162
        let jifColumnWidth: CGFloat = 56
        let quartileColumnWidth: CGFloat = 56
        let norwegianColumnWidth: CGFloat = 52
        let linksColumnWidth: CGFloat = 60
        let rowHeight: CGFloat = isEditingLocked ? 26 : AppPalette.fieldMinHeight
        let rowVerticalPadding: CGFloat = isEditingLocked ? 1 : 0
        let coloredGroupWidth: CGFloat = statusMarkerColumnWidth + journalColumnWidth + (dateColumnWidth * 3) + (statusSpacing * 4)
        VStack(alignment: .leading, spacing: isEditingLocked ? 4 : 5) {
            VStack(alignment: .leading, spacing: isEditingLocked ? 4 : 3) {
                HStack(alignment: .center, spacing: statusSpacing) {
                    Color.clear.frame(width: reorderColumnWidth)
                    HStack(alignment: .center, spacing: statusSpacing) {
                        Color.clear.frame(width: statusMarkerColumnWidth, height: 1)
                        submissionHeaderCell(language.text("Journal", "Tidskrift"), width: journalColumnWidth)
                        submissionHeaderCell(language.text("Submitted", "Inskickad"), width: dateColumnWidth)
                        submissionHeaderCell(language.text("Rejected", "Refuserad"), width: dateColumnWidth)
                        submissionHeaderCell(language.text("Accepted", "Accepterad"), width: dateColumnWidth)
                    }
                    .frame(width: coloredGroupWidth, alignment: .leading)

                    HStack(alignment: .center, spacing: metricsSpacing) {
                        submissionHeaderCell("JIF", width: jifColumnWidth)
                        submissionHeaderCell(language.text("Quartile", "Kvartil"), width: quartileColumnWidth)
                        submissionHeaderCell(language.text("Norw", "Norw"), width: norwegianColumnWidth)
                        submissionHeaderCell(language.text("Links", "Länkar"), width: linksColumnWidth)
                        if !isEditingLocked {
                            Color.clear.frame(width: 28)
                        }
                    }
                }

                ForEach(Array(visibleSubmissionRows.enumerated()), id: \.element.id) { visibleIndex, row in
                    let jifMetric = submissionMetric(for: row, kinds: [.clarivateScieJIF, .clarivateEsciJIF])
                    let norwegianMetric = submissionMetric(for: row, kinds: [.norwegianList])
                    HStack(alignment: .center, spacing: statusSpacing) {
                        if !isEditingLocked {
                            submissionReorderHandle(for: row, width: reorderColumnWidth)
                        } else {
                            Color.clear.frame(width: reorderColumnWidth, height: rowHeight)
                        }
                        HStack(alignment: .center, spacing: statusSpacing) {
                            submissionStatusMarker(for: row)
                                .frame(width: statusMarkerColumnWidth, height: rowHeight)
                            submissionJournalAutocompleteField(rowID: row.id, language: language, fallbackIndex: visibleIndex)
                                .frame(width: journalColumnWidth, height: rowHeight, alignment: .leading)
                            submissionDateCell(rowID: row.id, status: .submitted)
                                .frame(width: dateColumnWidth, height: rowHeight, alignment: .leading)
                            if row.hasAcceptedOrPublishedDate {
                                Color.clear.frame(width: dateColumnWidth, height: rowHeight)
                            } else {
                                submissionDateCell(rowID: row.id, status: .rejected)
                                    .frame(width: dateColumnWidth, height: rowHeight, alignment: .leading)
                            }
                            if row.hasRejectedDate {
                                Color.clear.frame(width: dateColumnWidth, height: rowHeight)
                            } else {
                                submissionDateCell(rowID: row.id, status: .accepted)
                                    .frame(width: dateColumnWidth, height: rowHeight, alignment: .leading)
                            }
                        }
                        .frame(width: coloredGroupWidth, alignment: .leading)
                        .padding(.vertical, rowVerticalPadding)
                        HStack(alignment: .center, spacing: metricsSpacing) {
                            submissionMetricCell(metric: jifMetric, width: jifColumnWidth)
                            // Quartile from the same ranking that provides JIF.
                            PublicationQuartileBadge(metric: jifMetric)
                                .frame(width: quartileColumnWidth, alignment: .leading)
                            submissionMetricCell(metric: norwegianMetric, width: norwegianColumnWidth)
                            submissionJournalLinkCell(for: row, width: linksColumnWidth)
                            if !isEditingLocked {
                                submissionDeleteButton(for: row)
                            }
                        }
                    }
                    .modifier(
                        SubmissionRowDropModifier(
                            row: row,
                            submissionRows: $submissionRows,
                            draggedSubmissionRowID: $draggedSubmissionRowID,
                            isEnabled: !isEditingLocked,
                            onReorder: { scheduleSubmissionRowsSync() }
                        )
                    )
                }
            }
        }
    }

    private var sortedSubmissionRows: [PublicationSubmissionEditorRow] {
        orderedSubmissionRows(submissionRows)
    }

    private var visibleSubmissionRows: [PublicationSubmissionEditorRow] {
        isEditingLocked ? sortedSubmissionRows.filter { !$0.isEmpty } : sortedSubmissionRows
    }

    private func submissionHeaderCell(_ title: String, width: CGFloat) -> some View {
        AppTableHeaderText(text: title)
            .frame(width: width, alignment: .leading)
    }

    /// Status stripe left of the journal name — the app's standard leading
    /// color marker: green for accepted, red for rejected, yellow for
    /// submitted without a further decision.
    @ViewBuilder
    private func submissionStatusMarker(for row: PublicationSubmissionEditorRow) -> some View {
        if let status = submissionStatusMarkerStatus(for: row) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(status.color)
                .padding(.vertical, 3)
                .help(status.help)
        } else {
            Color.clear
        }
    }

    private func submissionStatusMarkerStatus(for row: PublicationSubmissionEditorRow) -> (color: Color, help: String)? {
        if row.hasAcceptedOrPublishedDate {
            return (AppPalette.shadeGreen, language.text("Accepted", "Accepterad"))
        }
        if row.hasRejectedDate {
            return (AppPalette.shadeRed, language.text("Rejected", "Refuserad"))
        }
        if row.submittedDate?.trimmedOrNil != nil {
            return (AppPalette.shadeYellow, language.text("Submitted", "Inskickad"))
        }
        return nil
    }

    private func submissionMetricCell(metric: PublicationMetricValue?, width: CGFloat) -> some View {
        PublicationMetricValueBadge(
            metric: metric,
            backgroundColor: metricDistributionCache.backgroundColor(for: metric, publicationYear: draft.yearValue)
        )
        .frame(width: width, alignment: .leading)
    }

    private func submissionDeleteButton(for row: PublicationSubmissionEditorRow) -> some View {
        AppIconDeleteButton(
            title: language.text("Delete", "Ta bort"),
            font: .system(size: 12, weight: .semibold),
            width: 28
        ) {
            submissionRows.removeAll { $0.id == row.id }
            scheduleSubmissionRowsSync()
        }
    }

    private func submissionReorderHandle(for row: PublicationSubmissionEditorRow, width: CGFloat) -> some View {
        Group {
            if row.supportsManualOrdering {
                ReorderHandle(itemID: row.id, draggedItemID: $draggedSubmissionRowID, language: language)
            } else {
                Color.clear
            }
        }
        .frame(width: width, height: 26, alignment: .center)
    }

    @ViewBuilder
    private func submissionJournalLinkCell(for row: PublicationSubmissionEditorRow, width: CGFloat) -> some View {
        if let journal = store.linkedJournal(ofSubmissionJournalName: row.journal, in: draft) {
            HStack(spacing: 6) {
                AppDestinationActionButton(
                    kind: .app,
                    language: language,
                    title: language.text("Open journal", "Öppna tidskrift"),
                    fontSize: 12
                ) {
                    store.openRoute(for: journal)
                }

                if let url = journal.journalHomeURL {
                    AppDestinationURLLink(
                        kind: .web,
                        language: language,
                        destination: url,
                        fontSize: 12,
                        showsTitle: false
                    )
                }
            }
            .frame(width: width, alignment: .leading)
        } else {
            Color.clear
                .frame(width: width, height: 18)
        }
    }

    private func submissionDateCell(rowID: String, status: PublicationStatus) -> some View {
        OptionalDateField(
            dateString: submissionDateBinding(for: rowID, status: status),
            language: store.language,
            usesTransparentFieldStyle: false,
            isCompact: false,
            isIllogical: submissionDateIsIllogical(rowID: rowID, status: status),
            isDisabled: isEditingLocked
        )
    }

    private func submissionDateIsIllogical(rowID: String, status: PublicationStatus) -> Bool {
        guard let row = submissionRows.first(where: { $0.id == rowID }) else { return false }
        let fieldKeys = illogicalPublicationSubmissionDateFieldKeys(for: row)
        switch status {
        case .submitted:
            let isCurrentSubmission = row.submittedDate?.trimmedOrNil == draft.currentSubmissionDate?.trimmedOrNil
            return fieldKeys.contains(PublicationSubmissionDateValidationFieldKey.submittedDate)
                || (isCurrentSubmission && illogicalPublicationEditorDateKeys.contains(PublicationDateValidationFieldKey.currentSubmissionDate))
        case .rejected:
            return fieldKeys.contains(PublicationSubmissionDateValidationFieldKey.rejectedDate)
        case .accepted:
            return fieldKeys.contains(PublicationSubmissionDateValidationFieldKey.acceptedDate)
        case .published:
            return fieldKeys.contains(PublicationSubmissionDateValidationFieldKey.publishedDate)
        case .planned, .inPreparation:
            return false
        }
    }

    private func submissionJournalAutocompleteField(rowID: String, language: AppLanguage, fallbackIndex: Int) -> some View {
        Group {
            if isEditingLocked {
                lockedPublicationValueText(submissionRows.first(where: { $0.id == rowID })?.journal)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                AutocompleteSelectionField(
                    text: Binding(
                        get: { submissionRows.first(where: { $0.id == rowID })?.journal ?? "" },
                        set: { newValue in
                            guard let index = submissionRows.firstIndex(where: { $0.id == rowID }) else { return }
                            submissionRows[index].journal = newValue
                            scheduleSubmissionRowsSync()
                        }
                    ),
                    options: journalOptions,
                    placeholder: language.text("Select journal", "Välj tidskrift"),
                    addNewTitle: language.text("Add new", "Lägg till ny"),
                    display: { $0 },
                    onCommit: {
                        scheduleSubmissionRowsSync()
                    },
                    onAddNew: {
                        pendingSubmissionJournalRowID = rowID
                        store.beginAddingPublicationJournal(fromPublicationID: draft.id, atStatusIndex: fallbackIndex)
                    },
                    usesTransparentFieldStyle: false,
                    appliesChrome: true
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func submissionMetric(for row: PublicationSubmissionEditorRow, kinds: [JournalRankingKind]) -> PublicationMetricValue? {
        guard !row.journal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return store.linkedJournal(ofSubmissionJournalName: row.journal, in: draft)?.preferredMetric(for: kinds, publicationYear: draft.yearValue)
    }

    private func submissionDateBinding(for rowID: String, status: PublicationStatus) -> Binding<String> {
        Binding(
            get: { submissionRows.first(where: { $0.id == rowID })?.date(for: status) ?? "" },
            set: { newValue in
                guard let index = submissionRows.firstIndex(where: { $0.id == rowID }) else { return }
                let normalized = DateParsers.canonicalizedDayInput(newValue).trimmedOrNil
                submissionRows[index].setDate(normalized, for: status)
                scheduleSubmissionRowsSync()
            }
        )
    }

    private var bibliographyPublishedDateValue: String {
        submissionRows.first { $0.publishedDate?.trimmedOrNil != nil }?.publishedDate ?? ""
    }

    private func bibliographyPublishedDateBinding() -> Binding<String> {
        Binding(
            get: { bibliographyPublishedDateValue },
            set: { newValue in
                setBibliographyPublishedDate(newValue)
            }
        )
    }

    private func setBibliographyPublishedDate(_ newValue: String) {
        let normalized = DateParsers.canonicalizedDayInput(newValue).trimmedOrNil
        if let index = submissionRows.firstIndex(where: { $0.publishedDate?.trimmedOrNil != nil }) {
            submissionRows[index].setDate(normalized, for: .published)
            scheduleSubmissionRowsSync()
            return
        }

        guard let normalized else { return }
        if let currentJournal = draft.journal.trimmedOrNil,
           let index = submissionRows.firstIndex(where: { $0.trimmedJournal == currentJournal }) {
            submissionRows[index].setDate(normalized, for: .published)
        } else if let index = submissionRows.firstIndex(where: { !$0.isEmpty }) {
            submissionRows[index].setDate(normalized, for: .published)
        } else {
            var row = PublicationSubmissionEditorRow(journal: draft.journal.trimmedOrNil ?? "")
            row.setDate(normalized, for: .published)
            submissionRows.append(row)
        }
        scheduleSubmissionRowsSync()
    }

    private func commitPendingSubmissionJournal(_ selectedName: String? = nil) {
        guard let trimmed = (selectedName ?? pendingSubmissionJournalName).trimmedOrNil else { return }
        submissionRows.append(PublicationSubmissionEditorRow(journal: trimmed))
        pendingSubmissionJournalName = ""
        scheduleSubmissionRowsSync()
    }

    private func syncDraftFromSubmissionRows() {
        let cleanedRows = submissionRows
            .map { row in
                var copy = row
                copy.journal = copy.journal.trimmingCharacters(in: .whitespacesAndNewlines)
                copy.submittedDate = copy.submittedDate?.trimmedOrNil
                copy.rejectedDate = copy.rejectedDate?.trimmedOrNil
                copy.acceptedDate = copy.acceptedDate?.trimmedOrNil
                copy.publishedDate = copy.publishedDate?.trimmedOrNil
                return copy
            }
        let persistedRows = cleanedRows.filter { !$0.isEmpty }
        let normalizedRows = Self.normalizedSubmissionRows(persistedRows)

        submissionRows = normalizedRows

        // "Alla kopplingar via id": an earlier journal keeps its link while
        // its text still names the linked journal.
        let previousAttemptJournalIDs = draft.previousAttempts.reduce(into: [String: String]()) { result, attempt in
            if let journalID = attempt.journalID?.trimmedOrNil {
                result[GrantDataStore.normalizedIDLinkName(attempt.journal)] = journalID
            }
        }
        draft.previousAttempts = persistedRows.compactMap { row in
            guard row.rejectedDate != nil else { return nil }
            return PublicationAttempt(
                journal: row.journal,
                journalID: submissionJournalID(
                    for: row.journal,
                    keeping: previousAttemptJournalIDs[GrantDataStore.normalizedIDLinkName(row.journal)]
                ),
                submittedOn: row.submittedDate,
                rejectedOn: row.rejectedDate
            )
        }

        draft.statusTimeline = persistedRows.flatMap(\.persistedStatusEntries)

        suppressDraftAutosave = true

        if let anchor = effectivePublicationStatusAnchor(from: persistedRows) {
            draft.status = anchor.status.rawValue
            draft.journal = anchor.row.journal
            draft.statusDate = anchor.row.date(for: anchor.status)
            draft.currentSubmissionDate = anchor.status == .submitted ? anchor.row.submittedDate : nil
        } else if let plannedRow = persistedRows.first(where: { $0.trimmedJournal.nonEmpty != nil }) {
            draft.status = PublicationStatus.inPreparation.rawValue
            draft.journal = plannedRow.journal
            draft.statusDate = nil
            draft.currentSubmissionDate = nil
        } else {
            draft.status = PublicationStatus.inPreparation.rawValue
            draft.journal = ""
            draft.statusDate = nil
            draft.currentSubmissionDate = nil
        }
        draft.journalID = submissionJournalID(for: draft.journal, keeping: draft.journalID)

        draft.normalize()
        suppressDraftAutosave = false
        scheduleAutosave()
    }

    /// "Alla kopplingar via id": the journal a submission row's text points
    /// to. The link the publication already has is kept while the text still
    /// names that journal (its name, abbreviation or ISSN); other text is
    /// linked to the journal it names, and free text gets no link.
    private func submissionJournalID(for journalText: String, keeping existingID: String?) -> String? {
        guard let trimmed = journalText.trimmedOrNil else { return nil }
        if let existingID = existingID?.trimmedOrNil,
           let existing = store.publicationJournal(id: existingID) {
            let key = GrantDataStore.normalizedIDLinkName(trimmed)
            let linkedNames = [existing.name, existing.abbreviatedName, existing.issnLTWAAbbreviatedName, existing.issn, existing.eissn]
            if linkedNames.contains(where: { !$0.isEmpty && GrantDataStore.normalizedIDLinkName($0) == key }) {
                return existingID
            }
        }
        return store.publicationJournal(named: trimmed)?.id
    }

    private func scheduleSubmissionRowsSync() {
        submissionRowsSyncTask?.cancel()
        let task = DispatchWorkItem {
            syncDraftFromSubmissionRows()
        }
        submissionRowsSyncTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
    }

    private func effectivePublicationStatusAnchor(from rows: [PublicationSubmissionEditorRow]) -> (row: PublicationSubmissionEditorRow, status: PublicationStatus)? {
        rows
            .enumerated()
            .flatMap { rowOffset, row in
                row.allStatusesWithDates.map { status, date in
                    (rowOffset: rowOffset, row: row, status: status, date: date)
                }
            }
            .sorted { lhs, rhs in
                let leftDate = DateParsers.isoDay.date(from: lhs.date) ?? .distantPast
                let rightDate = DateParsers.isoDay.date(from: rhs.date) ?? .distantPast
                if leftDate != rightDate {
                    return leftDate > rightDate
                }
                let leftTieBreak = publicationCurrentStatusTieBreakRank(lhs.status)
                let rightTieBreak = publicationCurrentStatusTieBreakRank(rhs.status)
                if leftTieBreak != rightTieBreak {
                    return leftTieBreak > rightTieBreak
                }
                return lhs.rowOffset < rhs.rowOffset
            }
            .first
            .map { ($0.row, $0.status) }
    }

    private static func normalizedSubmissionRows(_ rows: [PublicationSubmissionEditorRow]) -> [PublicationSubmissionEditorRow] {
        var result = rows.filter { !$0.isEmpty }
        result.append(PublicationSubmissionEditorRow())
        return result
    }

}

private struct OptionalDateField: View {
    let dateString: Binding<String>
    var language: AppLanguage = .swedish
    var usesTransparentFieldStyle: Bool = false
    var isCompact: Bool = false
    var isIllogical: Bool = false
    var isDisabled: Bool = false
    var todayButtonHorizontalPadding: CGFloat? = nil
    var todayButtonMinWidth: CGFloat? = nil
    // 88 pt truncated the YYYY-MM-DD placeholder; 100 shows it in full.
    private var fieldWidth: CGFloat { isCompact ? 86 : 100 }
    private var horizontalPadding: CGFloat { isCompact ? 6 : 8 }
    private var verticalPadding: CGFloat { isCompact ? 0 : 4 }
    private var minHeight: CGFloat { isCompact ? 22 : AppPalette.fieldMinHeight }
    private var visualState: AppFieldVisualState {
        isIllogical
            ? .invalid(language.text("Illogical date combination", "Ologisk datumkombination"))
            : .normal
    }

    var body: some View {
        Group {
            if isDisabled {
                if let value = dateString.wrappedValue.trimmedOrNil {
                    AppLockedInlineValueText(text: value, isInvalid: isIllogical)
                        .frame(width: fieldWidth, alignment: .leading)
                        .help(isIllogical ? language.text("Illogical date combination", "Ologisk datumkombination") : "")
                } else {
                    Color.clear
                        .frame(width: fieldWidth, height: 18)
                }
            } else {
                AppDateField(
                    placeholder: "YYYY-MM-DD",
                    text: dateString,
                    width: fieldWidth,
                    height: minHeight,
                    showsTodayButton: true,
                    language: language,
                    state: visualState,
                    horizontalPadding: horizontalPadding,
                    verticalPadding: verticalPadding,
                    fill: AppPalette.fieldSurface,
                    stroke: AppPalette.subtleBorder,
                    todayButtonFill: AppPalette.fieldSurface,
                    todayButtonHorizontalPadding: todayButtonHorizontalPadding,
                    todayButtonIsCompact: isCompact,
                    todayButtonMinWidth: todayButtonMinWidth
                )
            }
        }
    }
}


private struct PublicationRankingBadge: View {
    let title: String
    let metric: PublicationMetricValue?
    let language: AppLanguage
    var showsQuartile: Bool = true
    var backgroundColor: Color? = nil

    var body: some View {
        HStack(spacing: 8) {
            AppFieldLabelText(text: title)
                .frame(width: 74, alignment: .trailing)
            PublicationMetricValueBadge(metric: metric, backgroundColor: backgroundColor)
                .frame(width: 66, alignment: .leading)
            if showsQuartile {
                PublicationQuartileBadge(metric: metric)
                    .frame(width: 50, alignment: .leading)
            }
            if metric?.flagsUncertainty == true {
                AppBadgeText(text: language.text("uncertain", "osäkert"))
            }
            Spacer(minLength: 0)
        }
    }
}

private struct PublicationCreditRolesSheet: View {
    @Binding var publication: PublicationRecord
    let language: AppLanguage
    @ObservedObject var store: GrantDataStore

    @Environment(\.dismiss) private var dismiss
    @State private var hoveredRole: PublicationCreditRole?
    @State private var horizontalScrollOffset: CGFloat = 0

    private let rowHeight: CGFloat = 26
    private let headerHeight: CGFloat = 118
    private let outerPadding: CGFloat = 14
    private let roleColumnSpacing: CGFloat = 4
    private let definitionPanelHeight: CGFloat = 62

    private enum CreditCellSelection: String, CaseIterable, Identifiable {
        case none
        case x
        case lead
        case equal
        case supporting

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(language.text("Define CRediT roles", "Definiera CRediT-roller"))
                    .appTypography(.sectionTitle)
                Spacer()
                Button(language.text("Done", "Klar")) {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            Text(language.text("Choose contribution roles for each author. Use X, lead, equal, or sup. per role. Hover over a role header to see its definition.", "Välj bidragsroller för varje författare. Använd X, lead, equal eller sup. per roll. Hovra över en rollrubrik för att se definitionen."))
                .appTypography(.secondary)
                .foregroundStyle(.secondary)

            creditDefinitionPanel

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 0) {
                    authorHeaderCell
                    SyncedHorizontalScrollView(
                        offsetX: $horizontalScrollOffset,
                        showsIndicators: false
                    ) {
                        headerRolesRow
                    }
                    .frame(height: headerHeight)
                }

                Divider()

                ScrollView(.vertical, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 0) {
                        authorRowsColumn
                        SyncedHorizontalScrollView(
                            offsetX: $horizontalScrollOffset,
                            showsIndicators: true
                        ) {
                            roleBodyRows
                        }
                    }
                }
                .frame(height: tableBodyHeight)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppPalette.fieldSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppPalette.subtleBorder, lineWidth: 1)
            )
        }
        .padding(outerPadding)
        .frame(width: popupWidth, height: popupHeight)
        .background(AppPalette.detailPanelSurface)
    }

    private var authorHeaderCell: some View {
        HStack(spacing: 0) {
            AppTableHeaderText(text: language.text("Author", "Författare"))
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            Spacer(minLength: 0)
        }
        .frame(width: authorColumnWidth, height: headerHeight, alignment: .bottomLeading)
        .background(AppPalette.fieldSurface)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppPalette.subtleBorder)
                .frame(width: 1)
        }
    }

    private var headerRolesRow: some View {
        HStack(alignment: .bottom, spacing: roleColumnSpacing) {
            ForEach(PublicationCreditRole.allCases) { role in
                PublicationCreditRoleHeaderCell(
                    role: role,
                    width: roleColumnWidth(for: role),
                    height: headerHeight,
                    onHoverChanged: { isHovering in
                        hoveredRole = isHovering ? role : (hoveredRole == role ? nil : hoveredRole)
                    }
                )
            }
        }
        .padding(.horizontal, 12)
        .frame(height: headerHeight, alignment: .bottomLeading)
        .background(AppPalette.fieldSurface)
    }

    private var authorRowsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(publication.authorNames.enumerated()), id: \.offset) { _, authorName in
                HStack(spacing: 0) {
                    AppPersonNameText(
                        name: authorName,
                        isCurrentUser: store.isCurrentUserPresentedName(authorName)
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                }
                .frame(width: authorColumnWidth, height: rowHeight, alignment: .leading)
                Divider()
            }
        }
        .frame(width: authorColumnWidth, alignment: .leading)
        .background(AppPalette.fieldSurface)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppPalette.subtleBorder)
                .frame(width: 1)
        }
    }

    private var roleBodyRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(publication.authorNames.enumerated()), id: \.offset) { _, authorName in
                HStack(alignment: .center, spacing: roleColumnSpacing) {
                    ForEach(PublicationCreditRole.allCases) { role in
                        Picker("", selection: roleCellSelectionBinding(for: authorName, role: role)) {
                            Text("–").tag(CreditCellSelection.none)
                            Text("X").tag(CreditCellSelection.x)
                            Text("lead").tag(CreditCellSelection.lead)
                            Text("equal").tag(CreditCellSelection.equal)
                            Text("sup.").tag(CreditCellSelection.supporting)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: roleColumnWidth(for: role), height: rowHeight, alignment: .leading)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: rowHeight)
                Divider()
            }
        }
        .background(AppPalette.fieldSurface)
    }

    private var creditDefinitionPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let hoveredRole {
                Text(hoveredRole.shortLabel)
                    .appTypography(.tableHeader)
                Text(hoveredRole.definition)
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text(" ")
                    .appTypography(.tableHeader)
                Text(language.text("Hover over a CRediT role header to show its definition here.", "Hovra över en CRediT-roll för att visa definitionen här."))
                    .appTypography(.secondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: definitionPanelHeight, alignment: .topLeading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppPalette.cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppPalette.subtleBorder, lineWidth: 1)
        )
    }

    private func roleColumnWidth(for role: PublicationCreditRole) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let textWidth = ceil((role.shortLabel as NSString).size(withAttributes: [.font: font]).width)
        let textHeight = ceil(font.ascender - font.descender)
        let angle = CGFloat.pi / 3
        let horizontalFootprint = abs(cos(angle)) * textWidth + abs(sin(angle)) * textHeight
        let pickerFont = NSFont.systemFont(ofSize: 13, weight: .regular)
        let pickerTextWidth = ceil(("equal" as NSString).size(withAttributes: [.font: pickerFont]).width)
        let pickerWidth = pickerTextWidth + 36
        return max(pickerWidth, ceil(horizontalFootprint) + 8)
    }

    private func roleCellSelectionBinding(
        for authorName: String,
        role: PublicationCreditRole
    ) -> Binding<CreditCellSelection> {
        Binding(
            get: {
                let hasRole = publication.creditRoles(forAuthorName: authorName).contains(role)
                guard hasRole else { return .none }
                guard let contribution = publication.creditRoleContribution(forAuthorName: authorName, role: role) else {
                    return .x
                }
                switch contribution {
                case .lead:
                    return .lead
                case .equal:
                    return .equal
                case .supporting:
                    return .supporting
                }
            },
            set: { selection in
                var roles = publication.creditRoles(forAuthorName: authorName)
                switch selection {
                case .none:
                    roles.remove(role)
                    publication.setCreditRoles(roles, forAuthorName: authorName)
                case .x:
                    roles.insert(role)
                    publication.setCreditRoles(roles, forAuthorName: authorName)
                    publication.setCreditRoleContribution(nil, forAuthorName: authorName, role: role)
                case .lead:
                    roles.insert(role)
                    publication.setCreditRoles(roles, forAuthorName: authorName)
                    publication.setCreditRoleContribution(.lead, forAuthorName: authorName, role: role)
                case .equal:
                    roles.insert(role)
                    publication.setCreditRoles(roles, forAuthorName: authorName)
                    publication.setCreditRoleContribution(.equal, forAuthorName: authorName, role: role)
                case .supporting:
                    roles.insert(role)
                    publication.setCreditRoles(roles, forAuthorName: authorName)
                    publication.setCreditRoleContribution(.supporting, forAuthorName: authorName, role: role)
                }
            }
        )
    }

    private var authorColumnWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: .regular)
        let widestName = publication.authorNames
            .map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }
            .max() ?? 0
        let headerWidth = ceil((language.text("Author", "Författare") as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).width)
        return max(44, ceil(max(widestName, headerWidth)) + 2)
    }

    private var rolesAreaWidth: CGFloat {
        let columnWidths = PublicationCreditRole.allCases.map(roleColumnWidth(for:))
        let spacing = CGFloat(max(PublicationCreditRole.allCases.count - 1, 0)) * roleColumnSpacing
        return columnWidths.reduce(0, +) + spacing + 24
    }

    private var tableBodyHeight: CGFloat {
        let bodyRowsHeight = CGFloat(publication.authorNames.count) * (rowHeight + 1)
        return min(max(bodyRowsHeight + 2, 120), 720)
    }

    private var popupWidth: CGFloat {
        let contentWidth = authorColumnWidth + rolesAreaWidth + (outerPadding * 2)
        return min(max(contentWidth, 920), 1500)
    }

    private var popupHeight: CGFloat {
        let fixedChrome: CGFloat = 30 + 14 + 18 + 14 + definitionPanelHeight + 14 + headerHeight + 1
        return min(max((outerPadding * 2) + fixedChrome + tableBodyHeight, 420), 980)
    }
}

@MainActor
private struct SyncedHorizontalScrollView<Content: View>: NSViewRepresentable {
    @Binding var offsetX: CGFloat
    let showsIndicators: Bool
    let content: Content

    init(offsetX: Binding<CGFloat>, showsIndicators: Bool, @ViewBuilder content: () -> Content) {
        self._offsetX = offsetX
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(offsetX: $offsetX)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = showsIndicators
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let hostingView = NSHostingView(rootView: AnyView(content))
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: documentView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
        ])

        scrollView.documentView = documentView
        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.attach(scrollView: scrollView, hostingView: hostingView)
        context.coordinator.updateOffsetIfNeeded()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.hostingView?.rootView = AnyView(content)
        context.coordinator.hostingView?.layoutSubtreeIfNeeded()
        context.coordinator.updateDocumentFrame()
        scrollView.hasHorizontalScroller = showsIndicators
        context.coordinator.updateOffsetIfNeeded()
    }

    @MainActor
    final class Coordinator: NSObject {
        @Binding private var offsetX: CGFloat
        weak var scrollView: NSScrollView?
        weak var hostingView: NSHostingView<AnyView>?
        private var isUpdating = false

        init(offsetX: Binding<CGFloat>) {
            self._offsetX = offsetX
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func attach(scrollView: NSScrollView, hostingView: NSHostingView<AnyView>) {
            self.scrollView = scrollView
            self.hostingView = hostingView
            updateDocumentFrame()
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleBoundsChangeNotification(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        func updateDocumentFrame() {
            guard let scrollView, let documentView = scrollView.documentView, let hostingView else { return }
            let fittingSize = hostingView.fittingSize
            hostingView.frame = CGRect(origin: .zero, size: fittingSize)
            documentView.frame = CGRect(origin: .zero, size: fittingSize)
        }

        func updateOffsetIfNeeded() {
            guard let scrollView else { return }
            let current = scrollView.contentView.bounds.origin.x
            guard abs(current - offsetX) > 0.5 else { return }
            isUpdating = true
            scrollView.contentView.scroll(to: NSPoint(x: max(0, offsetX), y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isUpdating = false
        }

        @objc private func handleBoundsChangeNotification(_ notification: Notification) {
            handleBoundsChange()
        }

        private func handleBoundsChange() {
            guard let scrollView, !isUpdating else { return }
            let newOffset = scrollView.contentView.bounds.origin.x
            guard abs(newOffset - offsetX) > 0.5 else { return }
            offsetX = newOffset
        }
    }
}

private struct PublicationCreditRoleHeaderCell: View {
    let role: PublicationCreditRole
    let width: CGFloat
    let height: CGFloat
    let onHoverChanged: (Bool) -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
            Text(role.shortLabel)
                .font(.system(size: 12, weight: .semibold))
                .fixedSize()
                .rotationEffect(.degrees(-60), anchor: .bottomLeading)
                .offset(x: width / 2, y: -2)
        }
        .frame(width: width, height: height, alignment: .bottomLeading)
        .contentShape(Rectangle())
        .onHover(perform: onHoverChanged)
        .help(role.definition)
    }
}
