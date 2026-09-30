import SwiftUI

// Shared yearly statistics for a doctoral candidate, used by the Doktorander
// workspace (record hero and detail tables). The former statistics-area page
// "Statistik · Doktorander" was removed; these numbers now live in the
// Doktorander workspace itself.

struct DoctoralStatisticsYearRow: Identifiable, Equatable {
    let year: Int
    var courseCount: Int = 0
    var completedCourseCredits: Double = 0
    var plannedCourseCredits: Double = 0
    var publicationCount: Int = 0
    var impactFactorTotal: Double = 0
    var impactFactorCount: Int = 0
    var norwegianLevel1Count: Int = 0
    var norwegianLevel2Count: Int = 0
    var norwegianOtherCount: Int = 0
    var completedSupervisionHours: Double = 0
    var plannedSupervisionHours: Double = 0

    var id: Int { year }

    var courseCredits: Double {
        completedCourseCredits + plannedCourseCredits
    }

    var supervisionHours: Double {
        completedSupervisionHours + plannedSupervisionHours
    }

    var averageImpactFactor: Double? {
        guard impactFactorCount > 0 else { return nil }
        return impactFactorTotal / Double(impactFactorCount)
    }
}

func doctoralStatisticsYearRows(
    candidate: DoctoralCandidateRecord,
    publications: [PublicationRecord],
    journalForPublication: (PublicationRecord) -> PublicationJournal?,
    referenceDate: Date = Date()
) -> [DoctoralStatisticsYearRow] {
    var rows: [Int: DoctoralStatisticsYearRow] = [:]

    func ensureYear(_ year: Int?) {
        guard let year, (1900...2200).contains(year), rows[year] == nil else { return }
        rows[year] = DoctoralStatisticsYearRow(year: year)
    }

    for course in candidate.courses where !course.isEmpty {
        let year = Int(course.year.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? course.completedOn.flatMap(doctoralStatisticsYear(from:))
        ensureYear(year)
        guard let year else { continue }
        rows[year]?.courseCount += 1
        let credits = GrantParsing.numericValue(from: course.credits) ?? 0
        if course.completedOn?.trimmedOrNil != nil {
            rows[year]?.completedCourseCredits += credits
        } else {
            rows[year]?.plannedCourseCredits += credits
        }
    }

    for publication in publications {
        let year = publication.yearValue
        ensureYear(year)
        guard let year else { continue }
        rows[year]?.publicationCount += 1

        let journal = journalForPublication(publication)
        let impactFactorRaw = journal?
            .preferredMetric(
                for: [.clarivateScieJIF, .clarivateEsciJIF],
                publicationYear: year
            )?
            .value
            ?? publication.jifCurrent
        if let impactFactor = GrantParsing.numericValue(from: impactFactorRaw) {
            rows[year]?.impactFactorTotal += impactFactor
            rows[year]?.impactFactorCount += 1
        }

        let norwegianRaw = journal?
            .preferredMetric(for: [.norwegianList], publicationYear: year)?
            .value
            ?? publication.norwegianCurrent
        switch doctoralStatisticsNorwegianLevel(norwegianRaw) {
        case 1:
            rows[year]?.norwegianLevel1Count += 1
        case 2:
            rows[year]?.norwegianLevel2Count += 1
        default:
            rows[year]?.norwegianOtherCount += 1
        }
    }

    // Round 12: hours in proportion to days (the one rule, see
    // `DoctoralSupervisionPeriod.termShares`); days up to today are
    // completed, the rest planned.
    for period in candidate.supervisionPeriods where !period.isEmpty {
        guard let hoursPerSemester = period.hoursPerTermValue else { continue }
        for share in DoctoralSupervisionPeriod.termShares(from: period.from, to: period.to, referenceDate: referenceDate) {
            ensureYear(share.year)
            rows[share.year]?.completedSupervisionHours += share.fractionUntilReference * hoursPerSemester
            rows[share.year]?.plannedSupervisionHours += (share.fraction - share.fractionUntilReference) * hoursPerSemester
        }
    }

    let boundaryYears = [
        doctoralStatisticsYear(from: candidate.admissionDate),
        doctoralStatisticsYear(from: candidate.disputationDate),
        doctoralStatisticsYear(from: candidate.plannedDisputationDate),
    ].compactMap { $0 }.filter { (1900...2200).contains($0) }
    if let first = boundaryYears.min(), let last = boundaryYears.max(), last - first <= 20 {
        for year in first...last {
            ensureYear(year)
        }
    }

    return rows.values.sorted { $0.year < $1.year }
}

/// One half-year of supervision on the doctoral timeline: the hours of every
/// supervision period that covers it (in proportion to days), and how many of
/// them are confirmed in Retendo. Round 12 (user decision 2026-09-30): a
/// semester with any period not confirmed needs attention (red mark),
/// whether it has ended, is running or lies ahead.
struct DoctoralSupervisionSemesterBlock: Identifiable, Equatable {
    let year: Int
    /// 1 = spring (Jan–Jun), 2 = autumn (Jul–Dec).
    let half: Int
    var hours: Double = 0
    var confirmedHours: Double = 0
    var hasEnded: Bool = false
    var hasUnconfirmedPeriod: Bool = false

    var id: String { "\(year)-\(half)" }
    var isFullyConfirmed: Bool { !hasUnconfirmedPeriod && hours > 0 }
    var needsConfirmation: Bool { hasUnconfirmedPeriod }
    /// Start of the semester as a fractional year (2025.0 or 2025.5).
    var startFraction: Double { Double(year) + (half == 1 ? 0 : 0.5) }
}

func doctoralSupervisionSemesterBlocks(
    periods: [DoctoralSupervisionPeriod],
    referenceDate: Date = Date()
) -> [DoctoralSupervisionSemesterBlock] {
    let today = Calendar.current.startOfDay(for: referenceDate)
    var blocks: [DoctoralStatisticsSemester: DoctoralSupervisionSemesterBlock] = [:]
    for period in periods where !period.isEmpty {
        // A period without hours still shows (and turns red if unconfirmed).
        let hoursPerSemester = period.hoursPerTermValue ?? 0
        for share in DoctoralSupervisionPeriod.termShares(from: period.from, to: period.to, referenceDate: referenceDate) {
            let semester = DoctoralStatisticsSemester(year: share.year, half: share.half)
            var block = blocks[semester] ?? DoctoralSupervisionSemesterBlock(year: share.year, half: share.half)
            let hours = share.fraction * hoursPerSemester
            block.hours += hours
            if period.confirmedInRetendo {
                block.confirmedHours += hours
            } else {
                block.hasUnconfirmedPeriod = true
            }
            block.hasEnded = share.termEnd < today
            blocks[semester] = block
        }
    }
    return blocks.values.sorted { ($0.year, $0.half) < ($1.year, $1.half) }
}

private func doctoralParsedDay(_ raw: String?) -> Date? {
    guard let raw = raw?.trimmedOrNil else { return nil }
    return DateParsers.isoDay.date(from: DateParsers.canonicalizedDayInput(raw))
}

/// When work on a paper first began: the earliest date stored on it (status
/// history, work status, submissions). Nil when the paper has no dates.
func doctoralPaperStartDate(_ publication: PublicationRecord) -> Date? {
    var raws: [String?] = publication.statusTimeline.map(\.date)
    raws += [publication.workflowStatusDate, publication.currentSubmissionDate, publication.statusDate]
    raws += publication.previousAttempts.map(\.submittedOn)
    return raws.compactMap(doctoralParsedDay).min()
}

/// The day a published paper came out: its "Published" status date, else
/// the e-pub date. Nil for papers that are not published or have no date.
func doctoralPaperPublishedDate(_ publication: PublicationRecord) -> Date? {
    guard publication.isPublished else { return nil }
    let statusDates = publication.statusTimeline
        .filter { PublicationStatus.fromStored($0.status) == .published }
        .compactMap { doctoralParsedDay($0.date) }
    if let date = statusDates.min() { return date }
    if let date = doctoralParsedDay(publication.epubDate) { return date }
    if PublicationStatus.fromStored(publication.statusLabel) == .published {
        return doctoralParsedDay(publication.statusDate)
    }
    return nil
}

private struct DoctoralStatisticsSemester: Hashable {
    let year: Int
    let half: Int
}

private func doctoralStatisticsSemesters(from startDate: Date, to endDate: Date) -> Set<DoctoralStatisticsSemester> {
    let start = min(startDate, endDate)
    let end = max(startDate, endDate)
    var result = Set<DoctoralStatisticsSemester>()
    var cursor = start
    while cursor <= end {
        let year = Calendar.current.component(.year, from: cursor)
        let month = Calendar.current.component(.month, from: cursor)
        result.insert(DoctoralStatisticsSemester(year: year, half: month <= 6 ? 1 : 2))
        guard let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: cursor) else { break }
        cursor = nextMonth
    }
    return result
}

private func doctoralStatisticsNorwegianLevel(_ raw: String) -> Int? {
    let normalized = raw
        .replacingOccurrences(of: " (uncertain)", with: "")
        .replacingOccurrences(of: " (osäkert)", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: ",", with: ".")
    guard let value = Double(normalized) else { return nil }
    return Int(value.rounded())
}

private func doctoralStatisticsYear(from raw: String) -> Int? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if let date = DateParsers.isoDay.date(from: trimmed) {
        return Calendar.current.component(.year, from: date)
    }
    return Int(trimmed.prefix(4))
}

func doctoralStatisticsNumber(_ value: Double, language: AppLanguage) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = " "
    formatter.decimalSeparator = language == .english ? "." : ","
    formatter.maximumFractionDigits = value.rounded() == value ? 0 : 1
    formatter.minimumFractionDigits = 0
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}
