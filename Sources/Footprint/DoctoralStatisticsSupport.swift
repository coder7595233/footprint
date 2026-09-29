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

    for period in candidate.supervisionPeriods where !period.isEmpty {
        guard let startDate = period.from.nonEmpty.flatMap(DateParsers.isoDay.date(from:)) else { continue }
        let endDate = period.to.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
            ?? Calendar.current.startOfDay(for: Date())
        let hoursPerSemester = GrantParsing.numericValue(from: period.hoursPerSemester) ?? 0
        guard hoursPerSemester > 0 else { continue }
        let semesters = doctoralStatisticsSemesters(from: startDate, to: endDate)
        let today = Calendar.current.startOfDay(for: referenceDate)
        for semester in semesters {
            ensureYear(semester.year)
            let endComponents = DateComponents(
                year: semester.year,
                month: semester.half == 1 ? 6 : 12,
                day: semester.half == 1 ? 30 : 31
            )
            let semesterEnd = Calendar.current.date(from: endComponents) ?? today
            if semesterEnd < today {
                rows[semester.year]?.completedSupervisionHours += hoursPerSemester
            } else {
                rows[semester.year]?.plannedSupervisionHours += hoursPerSemester
            }
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
