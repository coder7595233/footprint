import Foundation

/// F1b: the name an attached PDF is shown under, built from the record it
/// belongs to instead of the file name it happened to have when it was
/// chosen. Only the displayed text changes: stored data, stored paths and
/// file names on disk are left as they are. The original file name stays
/// available (tooltip in the app, own column in the export list).
///
/// Every label ends in ".pdf" so it reads like a file name. `nil` means the
/// record has nothing to build a label from; callers then show the original
/// file name as before.
enum AttachmentLabels {
    static func publication(_ publication: PublicationRecord, language: AppLanguage) -> String? {
        guard let title = cleaned(publication.title) else { return nil }
        let year = publication.yearValue.map(String.init) ?? yearPrefix(of: publication.epubDate)
        return pdfLabel(title + (year.map { " (\($0))" } ?? ""))
    }

    static func reviewCertificate(_ entry: CVReviewEntry, language: AppLanguage) -> String? {
        let subject: String?
        switch entry.category {
        case .journalReview:
            subject = cleaned(entry.journalName) ?? cleaned(entry.displayTitle)
        default:
            subject = cleaned(entry.displayTitle)
        }
        let round = cleaned(entry.reviewRound)
        let date = cleaned(entry.date) ?? cleaned(entry.acceptedDate)
        let details = [subject, round, date].compactMap { $0 }
        guard !details.isEmpty, subject != nil || date != nil else { return nil }
        let prefix = language.text("Review certificate", "Granskningsintyg")
        return pdfLabel(prefix + " – " + details.joined(separator: " "))
    }

    static func conferenceContribution(_ contribution: CVConferenceContribution, language: AppLanguage) -> String? {
        let title = cleaned(contribution.titleSv) ?? cleaned(contribution.titleEn)
        guard let title else { return nil }
        let year = cleaned(contribution.publicationYear) ?? yearPrefix(of: contribution.from)
        return pdfLabel(title + (year.map { " (\($0))" } ?? ""))
    }

    static func mediaAppearance(_ appearance: CVMediaAppearance, language: AppLanguage) -> String? {
        let title = cleaned(appearance.titleSv) ?? cleaned(appearance.titleEn)
            ?? cleaned(appearance.descriptionSv) ?? cleaned(appearance.descriptionEn)
        guard let title else { return nil }
        let date = cleaned(appearance.publicationDate) ?? cleaned(appearance.date)
        let prefix = language.text("Media", "Media")
        return pdfLabel(prefix + " – " + title + (date.map { " \($0)" } ?? ""))
    }

    static func doctoralDocument(
        _ document: DoctoralCandidateDocument,
        candidateName: String,
        language: AppLanguage
    ) -> String? {
        guard let title = cleaned(document.title) else { return nil }
        let name = cleaned(candidateName)
        let date = cleaned(document.date)
        let text = (name.map { "\($0) – " } ?? "") + title + (date.map { " \($0)" } ?? "")
        return pdfLabel(text)
    }

    /// Collapses line breaks and repeated spaces and trims the text.
    static func cleaned(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    private static func yearPrefix(of raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return nil }
        let prefix = String(trimmed.prefix(4))
        guard let year = Int(prefix), (1900...2200).contains(year) else { return nil }
        return prefix
    }

    private static func pdfLabel(_ text: String) -> String {
        // "/" and ":" cannot be part of a file name on macOS; show them as "-".
        let safe = text
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: " -")
        let collapsed = cleaned(safe) ?? safe
        if collapsed.lowercased().hasSuffix(".pdf") {
            return collapsed
        }
        return collapsed + ".pdf"
    }
}
