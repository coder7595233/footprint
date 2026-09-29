import AppKit
import Foundation

struct PublicationHeartLungfondenExportConfiguration: Hashable {
    static let defaultBaseYearWindow = 5
    static let baseYearWindowRange = 1...15

    var includeCompensableTime: Bool = false
    var sortOrder: PublicationExportSortOrder = .oldestFirst
    /// Number of years back the list covers (Hjärt-Lungfonden asks for 5).
    var baseYearWindow: Int = 5

    var yearWindow: Int {
        let base = min(max(baseYearWindow, Self.baseYearWindowRange.lowerBound), Self.baseYearWindowRange.upperBound)
        return includeCompensableTime ? base + 1 : base
    }
}

struct PublicationTemplateExportDocument: Encodable {
    let title: String
    let highlightName: String
    let underlinedNames: [String]
    let sections: [PublicationAMASection]
    let citationIndentTwips: Int?
    let citationTabStopTwips: Int?
    var headerText: String = ""
    var footerText: String = ""
    var includePageNumbers: Bool = false
    var fontFamily: String = ""
    var fontSizeHalfPoints: Int?
    var titleFontSizeHalfPoints: Int?
    var sectionFontSizeHalfPoints: Int?
    var headerFooterFontSizeHalfPoints: Int?
    var pageWidthTwips: Int?
    var pageHeightTwips: Int?
    var pageSizeCode: Int?
}

private func exportPreviewDateString(for language: AppLanguage) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: language == .swedish ? "sv_SE" : "en_US")
    formatter.dateStyle = .long
    return formatter.string(from: Date())
}

extension GrantDataStore {
    func publicationHeartLungfondenPreviewDocument(
        configuration: PublicationHeartLungfondenExportConfiguration,
        layout: ExportDocumentLayoutOptions = ExportDocumentLayoutOptions(currentDatePlacement: .none, includePageNumbers: false)
    ) -> PublicationTemplateExportDocument {
        let dateRange = heartLungfondenDateRange(configuration: configuration)
        let sections = heartLungfondenSections(configuration: configuration)
        var payload = PublicationTemplateExportDocument(
            title: "Publikationsförteckning - Hjärt-Lungfonden (\(dateRange.startText) - \(dateRange.endText))",
            highlightName: currentUserAuthor()?.name ?? "",
            underlinedNames: [],
            sections: sections,
            citationIndentTwips: 567,
            citationTabStopTwips: 567
        )
        payload.fontFamily = "Times New Roman"
        payload.fontSizeHalfPoints = 24
        payload.titleFontSizeHalfPoints = 32
        payload.sectionFontSizeHalfPoints = 28
        payload.headerFooterFontSizeHalfPoints = 24
        payload.pageWidthTwips = 11906
        payload.pageHeightTwips = 16838
        payload.pageSizeCode = 9
        let dateText = exportPreviewDateString(for: language)
        switch layout.currentDatePlacement {
        case .none:
            payload.headerText = ""
            payload.footerText = ""
        case .header:
            payload.headerText = dateText
            payload.footerText = ""
        case .footer:
            payload.headerText = ""
            payload.footerText = dateText
        }
        payload.includePageNumbers = layout.includePageNumbers
        return payload
    }

    @discardableResult
    func exportPublicationsHeartLungfondenDocument(
        configuration: PublicationHeartLungfondenExportConfiguration,
        to destinationURL: URL,
        layout: ExportDocumentLayoutOptions = ExportDocumentLayoutOptions(currentDatePlacement: .none, includePageNumbers: false)
    ) -> Bool {
        do {
            let sections = heartLungfondenSections(configuration: configuration)
            let hasItems = sections.contains { !$0.items.isEmpty }
            guard hasItems else {
                notice = StoreNotice(
                    message: language.text(
                        "There are no eligible publications for the selected Hjärt-Lungfonden period.",
                        "Det finns inga publikationer som kan exporteras för vald Hjärt-Lungfonden-period."
                    ),
                    tone: .info
                )
                loadError = nil
                return false
            }

            let payload = publicationHeartLungfondenPreviewDocument(configuration: configuration, layout: layout)
            try Self.renderHeartLungfondenDocument(payload, to: destinationURL)

            notice = StoreNotice(
                message: language.text(
                    "Exported Hjärt-Lungfonden publication document to \(destinationURL.lastPathComponent).",
                    "Exporterade Hjärt-Lungfonden-publikationsdokument till \(destinationURL.lastPathComponent)."
                ),
                tone: .success
            )
            loadError = nil
            return true
        } catch {
            loadError = error.localizedDescription
            notice = StoreNotice(
                message: language.text(
                    "Hjärt-Lungfonden publication export failed.",
                    "Export av Hjärt-Lungfonden-publikationslista misslyckades."
                ),
                tone: .error
            )
            return false
        }
    }

    func heartLungfondenDateRangeDescription(configuration: PublicationHeartLungfondenExportConfiguration) -> String {
        let dateRange = heartLungfondenDateRange(configuration: configuration)
        return "\(dateRange.startText) - \(dateRange.endText)"
    }

    private func heartLungfondenSections(
        configuration: PublicationHeartLungfondenExportConfiguration
    ) -> [PublicationAMASection] {
        let eligible = publicationRecords
            .filter { heartLungfondenEligibility(for: $0, configuration: configuration) != nil }
            .sorted {
                heartLungfondenSortOrder(
                    $0,
                    $1,
                    oldestFirst: configuration.sortOrder == .oldestFirst
                )
            }

        let originalItems = heartLungfondenNumberedItems(
            eligible.compactMap { publication -> PublicationAMAItem? in
                guard heartLungfondenEligibility(for: publication, configuration: configuration) == .original else {
                    return nil
                }
                return heartLungfondenCitationItem(for: publication)
            }
        )

        let otherItems = heartLungfondenNumberedItems(
            eligible.compactMap { publication -> PublicationAMAItem? in
                guard heartLungfondenEligibility(for: publication, configuration: configuration) == .other else {
                    return nil
                }
                return heartLungfondenCitationItem(for: publication)
            }
        )

        return [
            PublicationAMASection(
                title: "Originalarbeten",
                items: originalItems
            ),
            PublicationAMASection(
                title: "Andra arbeten",
                items: otherItems
            ),
        ]
    }

    private func heartLungfondenEligibility(
        for publication: PublicationRecord,
        configuration: PublicationHeartLungfondenExportConfiguration
    ) -> HeartLungfondenSectionKind? {
        let status = PublicationStatus.fromStored(publication.statusLabel)
        guard status == .published || status == .accepted else {
            return nil
        }
        guard let referenceDate = heartLungfondenReferenceDate(for: publication) else {
            return nil
        }

        let dateRange = heartLungfondenDateRange(configuration: configuration)
        guard referenceDate >= dateRange.startDate && referenceDate <= dateRange.endDate else {
            return nil
        }

        let type = publication.publicationType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if type.contains("abstract") {
            return nil
        }

        if publication.isPeerReviewed && heartLungfondenPublicationTypeBucket(for: publication) == .original {
            return .original
        }
        return .other
    }

    private func heartLungfondenPublicationTypeBucket(for publication: PublicationRecord) -> HeartLungfondenPublicationTypeBucket {
        let type = publication.publicationType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if type.contains("review") {
            return .other
        }
        if type.contains("protocol") || type.contains("research letter") || type.contains("editorial") {
            return .other
        }
        if type.contains("book chapter") || type.contains("chapter") {
            return .other
        }
        return .original
    }

    private func heartLungfondenCitationItem(for publication: PublicationRecord) -> PublicationAMAItem {
        let authors = heartLungfondenAuthorList(for: publication)
        let title = publication.title.nonEmpty ?? language.text("Untitled", "Utan titel")
        let journal = linkedJournal(of: publication)?.name.nonEmpty
            ?? linkedJournal(of: publication)?.abbreviatedName.nonEmpty
            ?? publication.journal.nonEmpty
            ?? ""
        let tail = heartLungfondenTail(for: publication)

        let plain = PublicationCitationFormatting.terminated(
            PublicationCitationFormatting.joinedSegments([authors, title, journal, tail])
        )

        return PublicationAMAItem(
            authors: authors,
            title: title,
            journal: journal,
            tail: tail,
            note: "",
            plain: plain,
            sourceID: "publication-\(publication.id)"
        )
    }

    private func heartLungfondenAuthorList(for publication: PublicationRecord) -> String {
        let authors = publication.authorNames.map(heartLungfondenAuthorDisplay)
        guard authors.count > 20 else {
            return authors.map(\.name).joined(separator: ", ")
        }

        let firstTwo = authors.prefix(2).map(\.name)
        let lastTwo = authors.suffix(2).map(\.name)
        let visibleAuthors = firstTwo + lastTwo
        let positionText: String
        if let currentIndex = authors.firstIndex(where: \.isCurrentUser) {
            positionText = " [egen position: \(currentIndex + 1) av \(authors.count)]"
        } else {
            positionText = ""
        }
        return visibleAuthors.joined(separator: ", ") + ", ..." + positionText
    }

    private func heartLungfondenAuthorDisplay(for authorName: String) -> HeartLungfondenAuthorDisplay {
        if let author = publicationAuthor(matchingPresentedName: authorName),
           let presentedName = author.presentedNameVariant(matching: authorName) {
            return HeartLungfondenAuthorDisplay(
                name: heartLungfondenFormattedAuthor(
                    lastName: presentedName.lastName,
                    firstName: presentedName.firstName,
                    fallbackName: presentedName.displayName
                ),
                isCurrentUser: isCurrentUserAuthor(author) || isCurrentUserPresentedName(authorName)
            )
        }

        return HeartLungfondenAuthorDisplay(
            name: heartLungfondenFormattedAuthorFromName(authorName),
            isCurrentUser: isCurrentUserPresentedName(authorName)
        )
    }

    private func heartLungfondenTail(for publication: PublicationRecord) -> String {
        let status = PublicationStatus.fromStored(publication.statusLabel)

        if status == .published {
            var bibliographic = publication.year.nonEmpty ?? ""
            if let volume = publication.volume.nonEmpty {
                bibliographic += bibliographic.isEmpty ? volume : ";\(volume)"
                if let issue = publication.issue.nonEmpty {
                    bibliographic += "(\(issue))"
                }
                if let pageRange = publication.pageRange.nonEmpty {
                    bibliographic += ":\(pageRange)"
                } else if let articleNumber = publication.articleNumber.nonEmpty {
                    bibliographic += ":\(articleNumber)"
                }
            } else if let year = publication.year.nonEmpty, let articleNumber = publication.articleNumber.nonEmpty {
                bibliographic = "\(year):\(articleNumber)"
            }
            return bibliographic
        }

        var parts: [String] = []
        if let year = publication.year.nonEmpty {
            parts.append(year)
        }
        parts.append("Accepterad för publikation")
        return parts.joined(separator: ". ")
    }

    private func heartLungfondenReferenceDate(for publication: PublicationRecord) -> Date? {
        if let statusDate = publication.statusDate?.nonEmpty.flatMap(DateParsers.isoDay.date(from:)) {
            return statusDate
        }
        if let year = publication.year.nonEmpty,
           let yearDate = DateParsers.isoDay.date(from: "\(year)-01-01") {
            return yearDate
        }
        return publication.currentSubmissionDate?.nonEmpty.flatMap(DateParsers.isoDay.date(from:))
    }

    private func heartLungfondenSortOrder(
        _ lhs: PublicationRecord,
        _ rhs: PublicationRecord,
        oldestFirst: Bool
    ) -> Bool {
        let leftDate = heartLungfondenReferenceDate(for: lhs) ?? .distantPast
        let rightDate = heartLungfondenReferenceDate(for: rhs) ?? .distantPast
        if leftDate != rightDate {
            return oldestFirst ? leftDate < rightDate : leftDate > rightDate
        }
        if lhs.sortYear != rhs.sortYear {
            return oldestFirst ? lhs.sortYear < rhs.sortYear : lhs.sortYear > rhs.sortYear
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private func heartLungfondenDateRange(
        configuration: PublicationHeartLungfondenExportConfiguration
    ) -> HeartLungfondenDateRange {
        let calendar = Calendar(identifier: .gregorian)
        let endDate = calendar.startOfDay(for: Date())
        let currentYear = calendar.component(.year, from: endDate)
        let startYear = currentYear - configuration.yearWindow
        let startDate = calendar.date(from: DateComponents(year: startYear, month: 1, day: 1)) ?? endDate
        return HeartLungfondenDateRange(
            startDate: startDate,
            endDate: endDate,
            startText: DateParsers.isoDay.string(from: startDate),
            endText: DateParsers.isoDay.string(from: endDate)
        )
    }

    private func heartLungfondenNumberedItems(_ items: [PublicationAMAItem]) -> [PublicationAMAItem] {
        items.enumerated().map { index, item in
            PublicationAMAItem(
                authors: "\(index + 1).\t\(item.authors)",
                title: item.title,
                journal: item.journal,
                tail: item.tail,
                note: item.note,
                plain: "\(index + 1).\t\(item.plain)",
                sourceID: item.sourceID
            )
        }
    }

    private func heartLungfondenFormattedAuthor(lastName: String, firstName: String, fallbackName: String) -> String {
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveLast = last.isEmpty ? fallbackName : last
        let initials = firstName
            .split(whereSeparator: { !$0.isLetter })
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined()
        return initials.isEmpty ? effectiveLast : "\(effectiveLast) \(initials)"
    }

    private func heartLungfondenFormattedAuthorFromName(_ fullName: String) -> String {
        let particles = ["af", "al", "da", "de", "del", "der", "di", "du", "la", "le", "van", "von"]
        let parts = fullName.split(separator: " ").map(String.init)
        guard let last = parts.last else { return fullName }

        var lastNameParts = [last]
        var index = parts.count - 2
        while index >= 0 {
            let candidate = parts[index].lowercased()
            if particles.contains(candidate) {
                lastNameParts.insert(parts[index], at: 0)
                index -= 1
            } else {
                break
            }
        }

        let firstNameParts = Array(parts.prefix(index + 1))
        return heartLungfondenFormattedAuthor(
            lastName: lastNameParts.joined(separator: " "),
            firstName: firstNameParts.joined(separator: " "),
            fallbackName: fullName
        )
    }

    func heartLungfondenExportDestinationURL(fileName: String) -> URL {
        let directory = exportDirectoryURL
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(heartLungfondenSanitizedFileNameComponent(fileName))
    }

    @discardableResult
    func openHeartLungfondenExportedFileIfAvailable(_ url: URL) -> Bool {
        guard !Self.suppressesAutomaticExportOpening else { return true }
        guard loadError == nil, FileManager.default.fileExists(atPath: url.path) else { return false }
        guard NSWorkspace.shared.open(url) else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return false
        }
        return true
    }

    private func heartLungfondenSanitizedFileNameComponent(_ raw: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let pieces = raw.components(separatedBy: forbidden)
        let joined = pieces.joined(separator: " ")
        let collapsed = joined.replacingOccurrences(of: #"[\s]+"#, with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func templateBundledResourceURL(named fileName: String, subdirectory: String? = nil) throws -> URL {
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("Footprint_Footprint.bundle", isDirectory: true),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Footprint_Footprint.bundle", isDirectory: true),
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("Footprint_Footprint.bundle", isDirectory: true),
            Bundle.main.resourceURL?.appendingPathComponent("GrantDesk_GrantDesk.bundle", isDirectory: true),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("GrantDesk_GrantDesk.bundle", isDirectory: true),
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("GrantDesk_GrantDesk.bundle", isDirectory: true),
            Bundle.main.resourceURL,
        ]

        for baseURL in candidates.compactMap({ $0 }) {
            let candidate = subdirectory.map {
                baseURL.appendingPathComponent($0, isDirectory: true).appendingPathComponent(fileName)
            } ?? baseURL.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        throw NSError(domain: "Footprint", code: 7, userInfo: [
            NSLocalizedDescriptionKey: "Missing bundled resource \(fileName).",
        ])
    }
}

private struct HeartLungfondenDateRange {
    let startDate: Date
    let endDate: Date
    let startText: String
    let endText: String
}

private struct HeartLungfondenAuthorDisplay {
    let name: String
    let isCurrentUser: Bool
}

private enum HeartLungfondenSectionKind {
    case original
    case other
}

private enum HeartLungfondenPublicationTypeBucket {
    case original
    case other
}
