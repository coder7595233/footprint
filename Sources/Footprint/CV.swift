import AppKit
import Foundation

private func localizedCVContent(language: AppLanguage, swedish: String, english: String) -> String {
    let swedishValue = swedish.trimmingCharacters(in: .whitespacesAndNewlines)
    let englishValue = english.trimmingCharacters(in: .whitespacesAndNewlines)
    if language == .swedish {
        return swedishValue.nonEmpty ?? englishValue
    }
    return englishValue.nonEmpty ?? swedishValue
}

enum CVItemKind: String, Codable, Hashable, Identifiable, CaseIterable {
    case conferenceContribution
    case mediaAppearance
    case review
    case otherPublication

    var id: String { rawValue }
}

struct CVRichTextRun: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var text: String
    var bold: Bool = false
    var italic: Bool = false
    var underline: Bool = false

    var isEmpty: Bool {
        text.isEmpty
    }
}

struct CVRichTextParagraph: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var runs: [CVRichTextRun] = []

    var plainText: String {
        runs.map(\.text).joined()
    }

    var isEmpty: Bool {
        plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct CVRichTextDocument: Codable, Hashable {
    var paragraphs: [CVRichTextParagraph] = []

    init(paragraphs: [CVRichTextParagraph] = []) {
        self.paragraphs = paragraphs
    }

    init(plainText: String) {
        let pieces = plainText.components(separatedBy: "\n")
        self.paragraphs = pieces.map { text in
            CVRichTextParagraph(runs: [CVRichTextRun(text: text)])
        }
        if self.paragraphs.isEmpty {
            self.paragraphs = [CVRichTextParagraph()]
        }
    }

    var plainText: String {
        paragraphs.map(\.plainText).joined(separator: "\n")
    }

    var isEmpty: Bool {
        plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    mutating func normalize() {
        paragraphs = paragraphs.map { paragraph in
            CVRichTextParagraph(
                id: paragraph.id,
                runs: paragraph.runs.filter { !$0.text.isEmpty }
            )
        }
        if paragraphs.isEmpty {
            paragraphs = [CVRichTextParagraph()]
        }
    }

    func attributedString(baseFontSize: CGFloat = 13) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseFont = NSFont.systemFont(ofSize: baseFontSize)
        let boldFont = NSFont.boldSystemFont(ofSize: baseFontSize)
        let italicBase = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
        let boldItalic = NSFontManager.shared.convert(boldFont, toHaveTrait: .italicFontMask)

        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
            for run in paragraph.runs {
                let font: NSFont
                switch (run.bold, run.italic) {
                case (true, true):
                    font = boldItalic
                case (true, false):
                    font = boldFont
                case (false, true):
                    font = italicBase
                case (false, false):
                    font = baseFont
                }
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.labelColor
                ]
                if run.underline {
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                result.append(NSAttributedString(string: run.text, attributes: attributes))
            }
            if paragraphIndex < paragraphs.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor.labelColor
                ]))
            }
        }

        if result.length == 0 {
            result.append(NSAttributedString(string: "", attributes: [
                .font: baseFont,
                .foregroundColor: NSColor.labelColor
            ]))
        }
        RichTextBulletLayout.applyParagraphStyles(to: result, baseFontSize: baseFontSize)
        return result
    }

    static func from(_ attributedString: NSAttributedString) -> CVRichTextDocument {
        let fullText = attributedString.string
        if fullText.isEmpty {
            return CVRichTextDocument(paragraphs: [CVRichTextParagraph()])
        }

        var paragraphs: [CVRichTextParagraph] = []
        var currentRuns: [CVRichTextRun] = []

        attributedString.enumerateAttributes(in: NSRange(location: 0, length: attributedString.length)) { attributes, range, _ in
            let substring = (fullText as NSString).substring(with: range)
            let font = attributes[.font] as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let isBold = traits.contains(.bold)
            let isItalic = traits.contains(.italic)
            let underlineValue = (attributes[.underlineStyle] as? NSNumber)?.intValue ?? 0
            let isUnderline = underlineValue != 0

            let parts = substring.components(separatedBy: "\n")
            for (index, part) in parts.enumerated() {
                if !part.isEmpty {
                    currentRuns.append(
                        CVRichTextRun(
                            text: part,
                            bold: isBold,
                            italic: isItalic,
                            underline: isUnderline
                        )
                    )
                }
                if index < parts.count - 1 {
                    paragraphs.append(CVRichTextParagraph(runs: currentRuns))
                    currentRuns = []
                }
            }
        }

        if !currentRuns.isEmpty || paragraphs.isEmpty {
            paragraphs.append(CVRichTextParagraph(runs: currentRuns))
        }

        var document = CVRichTextDocument(paragraphs: paragraphs)
        document.normalize()
        return document
    }
}

/// Hanging indentation for "• " bullet lines in the rich text editors:
/// wrapped lines start under the first letter after the bullet, not under
/// the bullet itself. Applied deterministically on both the freshly built
/// attributed string and after every edit, so editor content and the
/// document-derived string always compare equal.
enum RichTextBulletLayout {
    static let bulletPrefix = "• "

    static func applyParagraphStyles(to text: NSMutableAttributedString, baseFontSize: CGFloat = 13) {
        let string = text.string as NSString
        guard string.length > 0 else { return }
        let font = NSFont.systemFont(ofSize: baseFontSize)
        // Deeper levels start where the previous level's wrapped text starts.
        let levelStep = (bulletPrefix as NSString)
            .size(withAttributes: [.font: font])
            .width
        var location = 0
        while location < string.length {
            let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
            let style = NSMutableParagraphStyle()
            let line = string.substring(with: lineRange)
            if let level = ProtocolMarkup.bulletLevel(ofLine: line) {
                let prefixWidth = (ProtocolMarkup.bulletPrefix(forLevel: level) as NSString)
                    .size(withAttributes: [.font: font])
                    .width
                style.firstLineHeadIndent = CGFloat(level - 1) * levelStep
                style.headIndent = style.firstLineHeadIndent + prefixWidth
            }
            text.addAttribute(.paragraphStyle, value: style, range: lineRange)
            guard lineRange.length > 0 else { break }
            location = NSMaxRange(lineRange)
        }
    }
}

struct CVPersonalResume: Codable, Hashable, Identifiable {
    var id: String = "personal-resume"
    var contentSv: CVRichTextDocument = CVRichTextDocument(paragraphs: [CVRichTextParagraph()])
    var contentEn: CVRichTextDocument = CVRichTextDocument(paragraphs: [CVRichTextParagraph()])

    enum CodingKeys: String, CodingKey {
        case id
        case contentSv
        case contentEn
        case plainTextSv
        case plainTextEn
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "personal-resume"
        if let decodedSv = try container.decodeIfPresent(CVRichTextDocument.self, forKey: .contentSv) {
            contentSv = decodedSv
        } else {
            let plainSv = try container.decodeIfPresent(String.self, forKey: .plainTextSv) ?? ""
            contentSv = CVRichTextDocument(plainText: plainSv)
        }
        if let decodedEn = try container.decodeIfPresent(CVRichTextDocument.self, forKey: .contentEn) {
            contentEn = decodedEn
        } else {
            let plainEn = try container.decodeIfPresent(String.self, forKey: .plainTextEn) ?? ""
            contentEn = CVRichTextDocument(plainText: plainEn)
        }
        normalize()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(contentSv, forKey: .contentSv)
        try container.encode(contentEn, forKey: .contentEn)
    }

    mutating func normalize() {
        contentSv.normalize()
        contentEn.normalize()
    }

    func localizedContent(language: AppLanguage) -> CVRichTextDocument {
        language == .swedish ? contentSv : contentEn
    }

    mutating func setLocalizedContent(_ value: CVRichTextDocument, language: AppLanguage) {
        if language == .swedish {
            contentSv = value
        } else {
            contentEn = value
        }
        normalize()
    }
}

enum CVDocumentExportStyle: String, Codable, Hashable, CaseIterable {
    case own
    case liu
    case vetenskapsradet
}

enum CVVROutputSourceKind: String, Codable, Hashable {
    case publication
    case conferenceContribution
    case otherPublication
}

enum CVVROutputCategory: String, Codable, Hashable, CaseIterable, Identifiable {
    case peerReviewedOriginalArticle
    case peerReviewedConferenceContribution
    case peerReviewedEditedVolume
    case peerReviewedResearchReviewArticle
    case peerReviewedBookOrBookChapter
    case peerReviewedArtisticWork
    case peerReviewedOther
    case nonPeerReviewedArtisticWork
    case nonPeerReviewedPublication
    case nonPeerReviewedPreprint
    case nonPeerReviewedOther

    var id: String { rawValue }

    var isPeerReviewed: Bool {
        switch self {
        case .peerReviewedOriginalArticle,
                .peerReviewedConferenceContribution,
                .peerReviewedEditedVolume,
                .peerReviewedResearchReviewArticle,
                .peerReviewedBookOrBookChapter,
                .peerReviewedArtisticWork,
                .peerReviewedOther:
            return true
        case .nonPeerReviewedArtisticWork,
                .nonPeerReviewedPublication,
                .nonPeerReviewedPreprint,
                .nonPeerReviewedOther:
            return false
        }
    }

    var sortOrder: Int {
        switch self {
        case .peerReviewedOriginalArticle: return 0
        case .peerReviewedConferenceContribution: return 1
        case .peerReviewedEditedVolume: return 2
        case .peerReviewedResearchReviewArticle: return 3
        case .peerReviewedBookOrBookChapter: return 4
        case .peerReviewedArtisticWork: return 5
        case .peerReviewedOther: return 6
        case .nonPeerReviewedArtisticWork: return 0
        case .nonPeerReviewedPublication: return 1
        case .nonPeerReviewedPreprint: return 2
        case .nonPeerReviewedOther: return 3
        }
    }

    func localizedLabel(language: AppLanguage) -> String {
        switch self {
        case .peerReviewedOriginalArticle:
            return language.text("Original articles", "Originalartiklar")
        case .peerReviewedConferenceContribution:
            return language.text("Conference contributions", "Konferensbidrag")
        case .peerReviewedEditedVolume:
            return language.text("Edited volumes", "Samlingsverk")
        case .peerReviewedResearchReviewArticle:
            return language.text("Research review articles", "Forskningsöversiktsartiklar")
        case .peerReviewedBookOrBookChapter:
            return language.text("Books and book chapters", "Böcker och bokkapitel")
        case .peerReviewedArtisticWork, .nonPeerReviewedArtisticWork:
            return language.text("Artistic work", "Konstnärligt arbete")
        case .peerReviewedOther, .nonPeerReviewedOther:
            return language.text("Other outputs", "Andra outputs")
        case .nonPeerReviewedPublication:
            return language.text(
                "Publications including popular science books/presentations",
                "Publikationer inklusive populärvetenskapliga böcker/presentationer"
            )
        case .nonPeerReviewedPreprint:
            return language.text("Preprints", "Preprints")
        }
    }

    var vetenskapsradetHeading: String {
        switch self {
        case .peerReviewedOriginalArticle:
            return "Originalartiklar (Original articles)"
        case .peerReviewedConferenceContribution:
            return "Konferensbidrag (Conference contributions), vars resultat inte finns i andra publikationer"
        case .peerReviewedEditedVolume:
            return "Samlingsverk (Edited volumes)"
        case .peerReviewedResearchReviewArticle:
            return "Forskningsöversiktsartiklar (Research review articles)"
        case .peerReviewedBookOrBookChapter:
            return "Böcker och bokkapitel (Books and book chapters)"
        case .peerReviewedArtisticWork, .nonPeerReviewedArtisticWork:
            return "Konstnärligt arbete (Artistic work)"
        case .peerReviewedOther, .nonPeerReviewedOther:
            return "Andra outputs (Other outputs), som inte ryms under någon av ovanstående rubriker. Notera att immaterialrätt anges i ansökans cv-del."
        case .nonPeerReviewedPublication:
            return "Publikationer inklusive populärvetenskapliga böcker/presentationer (Publications including popular science books/presentations)"
        case .nonPeerReviewedPreprint:
            return "Preprints (Preprints)"
        }
    }
}

struct CVVROutputCandidate: Hashable, Identifiable {
    var id: String
    var sourceKind: CVVROutputSourceKind
    var sourceID: String
    var category: CVVROutputCategory
    var authorsText: String
    var title: String
    var journalText: String
    var citation: String
    var noteSuggestion: String
    var yearText: String
    var sortDate: String
    var latestImpactFactorValue: Double = 0
    var latestNorwegianLevelValue: Double = 0
    var impactFactorText: String = ""
    var norwegianLevelText: String = ""
}

struct CVVRSelectedOutput: Hashable, Identifiable {
    var candidate: CVVROutputCandidate
    var note: String

    var id: String { candidate.id }
}

extension CVVROutputCandidate {
    var filterSearchText: String {
        [
            authorsText,
            title,
            journalText,
            yearText,
        ].joined(separator: " ")
    }

    func rankingSummary(language: AppLanguage) -> String? {
        let parts = [
            impactFactorText.nonEmpty.map { "IF \($0)" },
            norwegianLevelText.nonEmpty.map {
                language.text("Norwegian list \($0)", "Norska listan \($0)")
            },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }
}

struct CVVROutputFilterOptions: Hashable {
    var searchText: String = ""
    var minimumImpactFactor: Double = 0
    var includedNorwegianLevels: Set<Int> = []

    func matches(_ candidate: CVVROutputCandidate) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            let foldedQuery = query.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "sv_SE")
            )
            let foldedSearchBlob = candidate.filterSearchText.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "sv_SE")
            )
            guard foldedSearchBlob.contains(foldedQuery) else { return false }
        }

        if max(minimumImpactFactor, 0) > 0,
           candidate.latestImpactFactorValue < minimumImpactFactor {
            return false
        }

        if !includedNorwegianLevels.isEmpty {
            let norwegianLevel = Int(candidate.latestNorwegianLevelValue.rounded())
            guard includedNorwegianLevels.contains(norwegianLevel) else { return false }
        }

        return true
    }
}

enum PublicationJournalNameMode: String, Codable, Hashable, CaseIterable, Identifiable {
    case abbreviated
    case full

    var id: String { rawValue }
}

enum PublicationJournalShortNameStyle: String, Codable, Hashable, CaseIterable, Identifiable {
    case nlm
    case issnLTWA

    var id: String { rawValue }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .nlm:
            return language.text("Short name NLM", "Kortnamn NLM")
        case .issnLTWA:
            return language.text("Short name ISSN LTWA", "Kortnamn ISSN LTWA")
        }
    }
}

enum PublicationExportSortOrder: String, Codable, Hashable, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }
}

enum PublicationMetricYearMode: String, Codable, Hashable, CaseIterable, Identifiable {
    case publicationYear
    case latestAvailable

    var id: String { rawValue }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .publicationYear:
            return language.text("Publication year", "Publikationsåret")
        case .latestAvailable:
            return language.text("Latest registered year", "Senaste registrerade året")
        }
    }
}

enum ExportDatePlacement: String, Codable, Hashable, CaseIterable, Identifiable {
    case none
    case header
    case footer

    var id: String { rawValue }
}

struct ExportDocumentLayoutOptions: Codable, Hashable {
    var currentDatePlacement: ExportDatePlacement = .header
    var includePageNumbers: Bool = true
}

enum CVExportSectionKey: String, Codable, Hashable, CaseIterable, Identifiable {
    case contactDetails
    case personalResume
    case doctoralThesis
    case degreesAndLicenses
    case courses
    case currentPositions
    case pastPositions
    case teaching
    case grants
    case originalArticles
    case reviewArticles
    case protocolArticles
    case manuscriptsInWriting
    case submittedManuscripts
    case acceptedManuscripts
    case otherPublications
    case conferenceContributions
    case media
    case reviews
    case currentAssociationMemberships

    var id: String { rawValue }

    static var defaultIncludedSections: Set<CVExportSectionKey> {
        Set(allCases.filter { $0 != .currentAssociationMemberships })
    }
}

enum CVReviewCategory: String, Codable, CaseIterable, Hashable {
    case journalReview
    case grantProposalReview
    case doctoralExamination
    case otherExpertAssignment

    func localizedTitle(_ language: AppLanguage) -> String {
        switch self {
        case .journalReview:
            return language.text("Article review", "Granskning av artikel")
        case .grantProposalReview:
            return language.text("Grant application review", "Granskning av anslagsansökan")
        case .doctoralExamination:
            return language.text("PhD examination", "Disputationsuppdrag")
        case .otherExpertAssignment:
            return language.text("Other expert assignment", "Övrigt sakkunniguppdrag")
        }
    }
}

enum CVReviewWorkflowStatus: Hashable {
    case completed
    case accepted
    case overdue

    func localizedTitle(_ language: AppLanguage) -> String {
        switch self {
        case .completed:
            return language.text("Completed", "Slutfört")
        case .accepted:
            return language.text("Accepted", "Accepterat")
        case .overdue:
            return language.text("Overdue", "Försenat")
        }
    }
}

enum PublicationExportSectionKey: String, Codable, Hashable, CaseIterable, Identifiable {
    case publishedOriginalArticles
    case publishedReviewArticles
    case publishedProtocolArticles
    case publishedNonPeerReviewedPublications
    case articlesInReview
    case articlesInWriting

    var id: String { rawValue }
}

struct PublicationExportOptions: Codable, Hashable {
    var authorCountBeforeEtAl: Int = 3
    /// When the list is cut with "et al", keep extending it until the user's own
    /// name is included.
    var alwaysShowOwnName: Bool = true
    var journalNameMode: PublicationJournalNameMode = .abbreviated
    var journalShortNameStyle: PublicationJournalShortNameStyle = .nlm
    var includeNonPeerReviewedPublications: Bool = false
    var includePMID: Bool = false
    var includeDOI: Bool = false
    var includeEpubDate: Bool = false
    var includePublicationDate: Bool = false
    var boldOwnName: Bool = true
    var includeClarivateSCIEJIF: Bool = false
    var impactFactorYearMode: PublicationMetricYearMode = .publicationYear
    var includeQuartile: Bool = false
    var quartileYearMode: PublicationMetricYearMode = .publicationYear
    var includeNorwegianList: Bool = false
    var norwegianListYearMode: PublicationMetricYearMode = .publicationYear
    var includeCitations: Bool = false
    var underlineDoctoralMainSupervisor: Bool = false
    var underlinedNames: [String] = []
    var sortOrder: PublicationExportSortOrder = .newestFirst
    /// Round 12: the language of the export the citations are written for
    /// (status words, "citeringar"). Set while exporting, never saved; nil
    /// means the app's language.
    var exportLanguage: AppLanguage? = nil

    enum CodingKeys: String, CodingKey {
        case authorCountBeforeEtAl
        case alwaysShowOwnName
        case journalNameMode
        case journalShortNameStyle
        case includeNonPeerReviewedPublications
        case includePMID
        case includeDOI
        case includeEpubDate
        case includePublicationDate
        case boldOwnName
        case includeClarivateSCIEJIF
        case impactFactorYearMode
        case includeQuartile
        case quartileYearMode
        case includeNorwegianList
        case norwegianListYearMode
        case includeCitations
        case underlineDoctoralMainSupervisor
        case underlineKarinRadholm
        case underlinedNames
        case sortOrder
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authorCountBeforeEtAl = try container.decodeIfPresent(Int.self, forKey: .authorCountBeforeEtAl) ?? 3
        alwaysShowOwnName = try container.decodeIfPresent(Bool.self, forKey: .alwaysShowOwnName) ?? true
        journalNameMode = try container.decodeIfPresent(PublicationJournalNameMode.self, forKey: .journalNameMode) ?? .abbreviated
        journalShortNameStyle = try container.decodeIfPresent(PublicationJournalShortNameStyle.self, forKey: .journalShortNameStyle) ?? .nlm
        includeNonPeerReviewedPublications = try container.decodeIfPresent(Bool.self, forKey: .includeNonPeerReviewedPublications) ?? false
        includePMID = try container.decodeIfPresent(Bool.self, forKey: .includePMID) ?? false
        includeDOI = try container.decodeIfPresent(Bool.self, forKey: .includeDOI) ?? false
        includeEpubDate = try container.decodeIfPresent(Bool.self, forKey: .includeEpubDate) ?? false
        includePublicationDate = try container.decodeIfPresent(Bool.self, forKey: .includePublicationDate) ?? false
        boldOwnName = try container.decodeIfPresent(Bool.self, forKey: .boldOwnName) ?? true
        includeClarivateSCIEJIF = try container.decodeIfPresent(Bool.self, forKey: .includeClarivateSCIEJIF) ?? false
        impactFactorYearMode = Self.decodeMetricYearMode(container, forKey: .impactFactorYearMode)
        includeQuartile = try container.decodeIfPresent(Bool.self, forKey: .includeQuartile) ?? false
        quartileYearMode = Self.decodeMetricYearMode(container, forKey: .quartileYearMode)
        includeNorwegianList = try container.decodeIfPresent(Bool.self, forKey: .includeNorwegianList) ?? false
        norwegianListYearMode = Self.decodeMetricYearMode(container, forKey: .norwegianListYearMode)
        includeCitations = try container.decodeIfPresent(Bool.self, forKey: .includeCitations) ?? false
        underlineDoctoralMainSupervisor =
            try container.decodeIfPresent(Bool.self, forKey: .underlineDoctoralMainSupervisor)
            ?? container.decodeIfPresent(Bool.self, forKey: .underlineKarinRadholm)
            ?? false
        underlinedNames = try container.decodeIfPresent([String].self, forKey: .underlinedNames) ?? []
        sortOrder = try container.decodeIfPresent(PublicationExportSortOrder.self, forKey: .sortOrder) ?? .newestFirst
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(authorCountBeforeEtAl, forKey: .authorCountBeforeEtAl)
        try container.encode(alwaysShowOwnName, forKey: .alwaysShowOwnName)
        try container.encode(journalNameMode, forKey: .journalNameMode)
        try container.encode(journalShortNameStyle, forKey: .journalShortNameStyle)
        try container.encode(includeNonPeerReviewedPublications, forKey: .includeNonPeerReviewedPublications)
        try container.encode(includePMID, forKey: .includePMID)
        try container.encode(includeDOI, forKey: .includeDOI)
        try container.encode(includeEpubDate, forKey: .includeEpubDate)
        try container.encode(includePublicationDate, forKey: .includePublicationDate)
        try container.encode(boldOwnName, forKey: .boldOwnName)
        try container.encode(includeClarivateSCIEJIF, forKey: .includeClarivateSCIEJIF)
        try container.encode(impactFactorYearMode, forKey: .impactFactorYearMode)
        try container.encode(includeQuartile, forKey: .includeQuartile)
        try container.encode(quartileYearMode, forKey: .quartileYearMode)
        try container.encode(includeNorwegianList, forKey: .includeNorwegianList)
        try container.encode(norwegianListYearMode, forKey: .norwegianListYearMode)
        try container.encode(includeCitations, forKey: .includeCitations)
        try container.encode(underlineDoctoralMainSupervisor, forKey: .underlineDoctoralMainSupervisor)
        try container.encode(underlinedNames, forKey: .underlinedNames)
        try container.encode(sortOrder, forKey: .sortOrder)
    }

    private static func decodeMetricYearMode(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> PublicationMetricYearMode {
        (try? container.decodeIfPresent(PublicationMetricYearMode.self, forKey: key)) ?? .publicationYear
    }
}

enum CVConferenceContributionStatus: String, Codable, Hashable, CaseIterable, Identifiable {
    case planned
    case accepted
    case presented
    case rejected

    var id: String { rawValue }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .planned:
            return fixedDropdownText("cvConferenceContribution.status.planned", language: language, english: "Planned", swedish: "Planerat")
        case .accepted:
            return fixedDropdownText("cvConferenceContribution.status.accepted", language: language, english: "Accepted", swedish: "Accepterad")
        case .presented:
            return fixedDropdownText("cvConferenceContribution.status.presented", language: language, english: "Presented", swedish: "Presenterad")
        case .rejected:
            return fixedDropdownText("cvConferenceContribution.status.rejected", language: language, english: "Rejected", swedish: "Refuserad")
        }
    }
}

enum CVConferenceSubmissionOutcome: String, Codable, Hashable, CaseIterable, Identifiable {
    case granted
    case declined

    var id: String { rawValue }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .granted:
            return fixedDropdownText("cvConferenceContribution.submissionOutcome.granted", language: language, english: "Accepted", swedish: "Accepterad")
        case .declined:
            return fixedDropdownText("cvConferenceContribution.submissionOutcome.declined", language: language, english: "Rejected", swedish: "Refuserad")
        }
    }
}

struct CVConferenceContribution: Codable, Hashable, Identifiable {
    var id: String
    var status: CVConferenceContributionStatus
    var from: String
    var to: String
    var titleSv: String
    var titleEn: String
    var nameSv: String
    var nameEn: String
    var contributorNames: [String]
    var contributorAuthorIDs: [String]
    var presentedBy: String
    var presentedByAuthorID: String?
    var publicationYear: String
    var projectNameSv: String
    var projectNameEn: String
    /// F13: the project by id; the project names above are kept for display.
    var projectID: String?
    var congressOrganizationID: String?
    var congressID: String?
    var congressLink: String
    var submissionAppliedOn: String
    var submissionClosesOn: String
    var submissionDecisionExpectedOn: String
    var submissionDecisionOn: String
    var submissionOutcome: CVConferenceSubmissionOutcome?
    var meetingSv: String
    var meetingEn: String
    var meetingCity: String
    var meetingCountry: String
    var journalID: String?
    var journalName: String
    var journalVolume: String
    var journalIssue: String
    var journalPages: String
    var journalArticleNumber: String
    var journalDOI: String
    var journalPMID: String
    var pdfFilename: String?
    var pdfPath: String?
    var commentsSv: String
    var commentsEn: String
    var tasks: [PublicationTaskItem]

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case from
        case to
        case title
        case titleSv
        case titleEn
        case name
        case nameSv
        case nameEn
        case contributorNames
        case contributorAuthorIDs
        case presentedBy
        case presentedByAuthorID
        case publicationYear
        case projectName
        case projectNameSv
        case projectNameEn
        case projectID
        case congressOrganizationID
        case congressID
        case congressLink
        case submissionAppliedOn
        case submissionClosesOn
        case submissionDecisionExpectedOn
        case submissionDecisionOn
        case submissionOutcome
        case meeting
        case meetingSv
        case meetingEn
        case meetingCity
        case meetingCountry
        case journalID
        case journalName
        case journalVolume
        case journalIssue
        case journalPages
        case journalArticleNumber
        case journalDOI
        case journalPMID
        case pdfFilename
        case pdfPath
        case comments
        case commentsSv
        case commentsEn
        case tasks
        case publicationData
        case publicationDataSv
        case publicationDataEn
    }

    init(
        id: String = UUID().uuidString,
        status: CVConferenceContributionStatus = .planned,
        from: String = "",
        to: String = "",
        title: String = "",
        name: String = "",
        contributorNames: [String] = [],
        contributorAuthorIDs: [String] = [],
        presentedBy: String = "",
        presentedByAuthorID: String? = nil,
        publicationYear: String = "",
        projectName: String = "",
        congressOrganizationID: String? = nil,
        congressID: String? = nil,
        congressLink: String = "",
        submissionAppliedOn: String = "",
        submissionClosesOn: String = "",
        submissionDecisionExpectedOn: String = "",
        submissionDecisionOn: String = "",
        submissionOutcome: CVConferenceSubmissionOutcome? = nil,
        meeting: String = "",
        meetingCity: String = "",
        meetingCountry: String = "",
        journalID: String? = nil,
        journalName: String = "",
        journalVolume: String = "",
        journalIssue: String = "",
        journalPages: String = "",
        journalArticleNumber: String = "",
        journalDOI: String = "",
        journalPMID: String = "",
        pdfFilename: String? = nil,
        pdfPath: String? = nil,
        comments: String = "",
        tasks: [PublicationTaskItem] = []
    ) {
        self.id = id
        self.status = status
        self.from = from
        self.to = to
        self.titleSv = title
        self.titleEn = title
        self.nameSv = name
        self.nameEn = name
        self.contributorNames = contributorNames
        self.contributorAuthorIDs = contributorAuthorIDs
        self.presentedBy = presentedBy
        self.presentedByAuthorID = presentedByAuthorID
        self.publicationYear = publicationYear
        self.projectNameSv = projectName
        self.projectNameEn = projectName
        self.congressOrganizationID = congressOrganizationID
        self.congressID = congressID
        self.congressLink = congressLink
        self.submissionAppliedOn = submissionAppliedOn
        self.submissionClosesOn = submissionClosesOn
        self.submissionDecisionExpectedOn = submissionDecisionExpectedOn
        self.submissionDecisionOn = submissionDecisionOn
        self.submissionOutcome = submissionOutcome
        self.meetingSv = meeting
        self.meetingEn = meeting
        self.meetingCity = meetingCity
        self.meetingCountry = meetingCountry
        self.journalID = journalID
        self.journalName = journalName
        self.journalVolume = journalVolume
        self.journalIssue = journalIssue
        self.journalPages = journalPages
        self.journalArticleNumber = journalArticleNumber
        self.journalDOI = journalDOI
        self.journalPMID = journalPMID
        self.pdfFilename = pdfFilename
        self.pdfPath = pdfPath
        self.commentsSv = comments
        self.commentsEn = comments
        self.tasks = tasks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyTitle = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        let legacyName = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        let legacyMeeting = try container.decodeIfPresent(String.self, forKey: .meeting) ?? ""
        let legacyPublicationData = try container.decodeIfPresent(String.self, forKey: .publicationData) ?? ""
        let contributorNames = try container.decodeIfPresent([String].self, forKey: .contributorNames)
        let decodedFrom = try container.decodeIfPresent(String.self, forKey: .from) ?? ""
        let decodedTo = try container.decodeIfPresent(String.self, forKey: .to) ?? ""
        let decodedYear = try container.decodeIfPresent(String.self, forKey: .publicationYear) ?? ""
        let decodedJournalName = try container.decodeIfPresent(String.self, forKey: .journalName) ?? ""
        let inferredStatus = Self.inferredStatus(
            explicit: try container.decodeIfPresent(CVConferenceContributionStatus.self, forKey: .status)
        )
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            status: inferredStatus,
            from: decodedFrom,
            to: decodedTo,
            title: legacyTitle,
            name: legacyName,
            contributorNames: contributorNames ?? [],
            contributorAuthorIDs: try container.decodeIfPresent([String].self, forKey: .contributorAuthorIDs) ?? [],
            presentedBy: try container.decodeIfPresent(String.self, forKey: .presentedBy) ?? "",
            presentedByAuthorID: try container.decodeIfPresent(String.self, forKey: .presentedByAuthorID),
            publicationYear: decodedYear,
            projectName: try container.decodeIfPresent(String.self, forKey: .projectName) ?? "",
            congressOrganizationID: try container.decodeIfPresent(String.self, forKey: .congressOrganizationID),
            congressID: try container.decodeIfPresent(String.self, forKey: .congressID),
            congressLink: try container.decodeIfPresent(String.self, forKey: .congressLink) ?? "",
            submissionAppliedOn: try container.decodeIfPresent(String.self, forKey: .submissionAppliedOn) ?? "",
            submissionClosesOn: try container.decodeIfPresent(String.self, forKey: .submissionClosesOn) ?? "",
            submissionDecisionExpectedOn: try container.decodeIfPresent(String.self, forKey: .submissionDecisionExpectedOn) ?? "",
            submissionDecisionOn: try container.decodeIfPresent(String.self, forKey: .submissionDecisionOn) ?? "",
            submissionOutcome: try container.decodeIfPresent(CVConferenceSubmissionOutcome.self, forKey: .submissionOutcome),
            meeting: legacyMeeting,
            meetingCity: try container.decodeIfPresent(String.self, forKey: .meetingCity) ?? "",
            meetingCountry: try container.decodeIfPresent(String.self, forKey: .meetingCountry) ?? "",
            journalID: try container.decodeIfPresent(String.self, forKey: .journalID),
            journalName: decodedJournalName,
            journalVolume: try container.decodeIfPresent(String.self, forKey: .journalVolume) ?? "",
            journalIssue: try container.decodeIfPresent(String.self, forKey: .journalIssue) ?? "",
            journalPages: try container.decodeIfPresent(String.self, forKey: .journalPages) ?? "",
            journalArticleNumber: try container.decodeIfPresent(String.self, forKey: .journalArticleNumber) ?? "",
            journalDOI: try container.decodeIfPresent(String.self, forKey: .journalDOI) ?? "",
            journalPMID: try container.decodeIfPresent(String.self, forKey: .journalPMID) ?? "",
            pdfFilename: try container.decodeIfPresent(String.self, forKey: .pdfFilename),
            pdfPath: try container.decodeIfPresent(String.self, forKey: .pdfPath),
            comments: legacyPublicationData,
            tasks: try container.decodeIfPresent([PublicationTaskItem].self, forKey: .tasks) ?? []
        )
        self.titleSv = try container.decodeIfPresent(String.self, forKey: .titleSv) ?? self.titleSv
        self.titleEn = try container.decodeIfPresent(String.self, forKey: .titleEn) ?? self.titleEn
        self.nameSv = try container.decodeIfPresent(String.self, forKey: .nameSv) ?? self.nameSv
        self.nameEn = try container.decodeIfPresent(String.self, forKey: .nameEn) ?? self.nameEn
        self.projectNameSv = try container.decodeIfPresent(String.self, forKey: .projectNameSv) ?? self.projectNameSv
        self.projectNameEn = try container.decodeIfPresent(String.self, forKey: .projectNameEn) ?? self.projectNameEn
        self.projectID = try container.decodeIfPresent(String.self, forKey: .projectID)
        self.meetingSv = try container.decodeIfPresent(String.self, forKey: .meetingSv) ?? self.meetingSv
        self.meetingEn = try container.decodeIfPresent(String.self, forKey: .meetingEn) ?? self.meetingEn
        let decodedCommentsSv = try container.decodeIfPresent(String.self, forKey: .commentsSv)
        let decodedLegacyCommentsSv = try container.decodeIfPresent(String.self, forKey: .publicationDataSv)
        let decodedCommentsEn = try container.decodeIfPresent(String.self, forKey: .commentsEn)
        let decodedLegacyCommentsEn = try container.decodeIfPresent(String.self, forKey: .publicationDataEn)
        self.commentsSv = decodedCommentsSv ?? decodedLegacyCommentsSv ?? self.commentsSv
        self.commentsEn = decodedCommentsEn ?? decodedLegacyCommentsEn ?? self.commentsEn
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(status, forKey: .status)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encode(titleSv, forKey: .titleSv)
        try container.encode(titleEn, forKey: .titleEn)
        try container.encode(nameSv, forKey: .nameSv)
        try container.encode(nameEn, forKey: .nameEn)
        try container.encode(contributorNames, forKey: .contributorNames)
        if !contributorAuthorIDs.isEmpty {
            try container.encode(contributorAuthorIDs, forKey: .contributorAuthorIDs)
        }
        try container.encode(presentedBy, forKey: .presentedBy)
        try container.encodeIfPresent(presentedByAuthorID, forKey: .presentedByAuthorID)
        try container.encode(publicationYear, forKey: .publicationYear)
        try container.encode(projectNameSv, forKey: .projectNameSv)
        try container.encode(projectNameEn, forKey: .projectNameEn)
        try container.encodeIfPresent(projectID, forKey: .projectID)
        try container.encodeIfPresent(congressOrganizationID, forKey: .congressOrganizationID)
        try container.encodeIfPresent(congressID, forKey: .congressID)
        try container.encode(congressLink, forKey: .congressLink)
        try container.encode(submissionAppliedOn, forKey: .submissionAppliedOn)
        try container.encode(submissionClosesOn, forKey: .submissionClosesOn)
        try container.encode(submissionDecisionExpectedOn, forKey: .submissionDecisionExpectedOn)
        try container.encode(submissionDecisionOn, forKey: .submissionDecisionOn)
        try container.encodeIfPresent(submissionOutcome, forKey: .submissionOutcome)
        try container.encode(meetingSv, forKey: .meetingSv)
        try container.encode(meetingEn, forKey: .meetingEn)
        try container.encode(meetingCity, forKey: .meetingCity)
        try container.encode(meetingCountry, forKey: .meetingCountry)
        try container.encodeIfPresent(journalID, forKey: .journalID)
        try container.encode(journalName, forKey: .journalName)
        try container.encode(journalVolume, forKey: .journalVolume)
        try container.encode(journalIssue, forKey: .journalIssue)
        try container.encode(journalPages, forKey: .journalPages)
        try container.encode(journalArticleNumber, forKey: .journalArticleNumber)
        try container.encode(journalDOI, forKey: .journalDOI)
        try container.encode(journalPMID, forKey: .journalPMID)
        try container.encodeIfPresent(pdfFilename, forKey: .pdfFilename)
        try container.encodeIfPresent(pdfPath, forKey: .pdfPath)
        try container.encode(commentsSv, forKey: .commentsSv)
        try container.encode(commentsEn, forKey: .commentsEn)
        try container.encode(tasks, forKey: .tasks)
    }

    mutating func normalize() {
        from = DateParsers.canonicalizedDayInput(from)
        to = DateParsers.canonicalizedDayInput(to)
        titleSv = titleSv.trimmingCharacters(in: .whitespacesAndNewlines)
        titleEn = titleEn.trimmingCharacters(in: .whitespacesAndNewlines)
        nameSv = nameSv.trimmingCharacters(in: .whitespacesAndNewlines)
        nameEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        contributorNames = Array(NSOrderedSet(array: contributorNames.compactMap { $0.trimmedOrNil })) as? [String] ?? []
        if !contributorNames.isEmpty {
            // F3: the stored author strings are always derived from the list.
            let joinedContributors = contributorNames.joined(separator: ", ")
            nameSv = joinedContributors
            nameEn = joinedContributors
        }
        status = derivedStatus()
        if contributorNames.isEmpty {
            let legacy = (nameSv.nonEmpty ?? nameEn.nonEmpty)
            if let legacy {
                contributorNames = [legacy]
            }
        }
        contributorAuthorIDs = Array(NSOrderedSet(array: contributorAuthorIDs.compactMap(\.trimmedOrNil))) as? [String] ?? []
        presentedBy = presentedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        presentedByAuthorID = presentedByAuthorID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        publicationYear = publicationYear.trimmingCharacters(in: .whitespacesAndNewlines)
        projectNameSv = projectNameSv.trimmingCharacters(in: .whitespacesAndNewlines)
        projectNameEn = projectNameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        projectID = projectID?.trimmedOrNil
        congressOrganizationID = congressOrganizationID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        congressID = congressID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        congressLink = congressLink.trimmingCharacters(in: .whitespacesAndNewlines)
        submissionAppliedOn = DateParsers.canonicalizedDayInput(submissionAppliedOn)
        submissionClosesOn = DateParsers.canonicalizedDayInput(submissionClosesOn)
        submissionDecisionExpectedOn = DateParsers.canonicalizedDayInput(submissionDecisionExpectedOn)
        submissionDecisionOn = DateParsers.canonicalizedDayInput(submissionDecisionOn)
        meetingSv = meetingSv.trimmingCharacters(in: .whitespacesAndNewlines)
        meetingEn = meetingEn.trimmingCharacters(in: .whitespacesAndNewlines)
        meetingCity = meetingCity.trimmingCharacters(in: .whitespacesAndNewlines)
        meetingCountry = meetingCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        journalID = journalID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        journalName = journalName.trimmingCharacters(in: .whitespacesAndNewlines)
        journalVolume = journalVolume.trimmingCharacters(in: .whitespacesAndNewlines)
        journalIssue = journalIssue.trimmingCharacters(in: .whitespacesAndNewlines)
        journalPages = journalPages.trimmingCharacters(in: .whitespacesAndNewlines)
        journalArticleNumber = journalArticleNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        journalDOI = journalDOI.trimmingCharacters(in: .whitespacesAndNewlines)
        journalPMID = journalPMID.trimmingCharacters(in: .whitespacesAndNewlines)
        pdfFilename = pdfFilename?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        pdfPath = pdfPath?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        commentsSv = commentsSv.trimmingCharacters(in: .whitespacesAndNewlines)
        commentsEn = commentsEn.trimmingCharacters(in: .whitespacesAndNewlines)
        tasks = tasks
            .map {
                var task = $0
                task.normalize()
                return task
            }
            .filter { !$0.isEmpty }
    }

    var isEmpty: Bool {
        status == .planned &&
        from.nonEmpty == nil &&
            to.nonEmpty == nil &&
            titleSv.nonEmpty == nil &&
            titleEn.nonEmpty == nil &&
            nameSv.nonEmpty == nil &&
            nameEn.nonEmpty == nil &&
            contributorNames.isEmpty &&
            contributorAuthorIDs.isEmpty &&
            presentedBy.nonEmpty == nil &&
            presentedByAuthorID == nil &&
            publicationYear.nonEmpty == nil &&
            projectName.nonEmpty == nil &&
            congressOrganizationID == nil &&
            congressID == nil &&
            congressLink.nonEmpty == nil &&
            submissionAppliedOn.nonEmpty == nil &&
            submissionClosesOn.nonEmpty == nil &&
            submissionDecisionExpectedOn.nonEmpty == nil &&
            submissionDecisionOn.nonEmpty == nil &&
            submissionOutcome == nil &&
            meetingSv.nonEmpty == nil &&
            meetingEn.nonEmpty == nil &&
            meetingCity.nonEmpty == nil &&
            meetingCountry.nonEmpty == nil &&
            journalName.nonEmpty == nil &&
            journalVolume.nonEmpty == nil &&
            journalIssue.nonEmpty == nil &&
            journalPages.nonEmpty == nil &&
            journalArticleNumber.nonEmpty == nil &&
            journalDOI.nonEmpty == nil &&
            journalPMID.nonEmpty == nil &&
            pdfFilename?.trimmedOrNil == nil &&
            pdfPath?.trimmedOrNil == nil &&
            commentsSv.nonEmpty == nil &&
            commentsEn.nonEmpty == nil &&
            tasks.isEmpty
    }

    var displayTitle: String {
        titleSv.nonEmpty ?? titleEn.nonEmpty ?? contributorNames.first ?? nameSv.nonEmpty ?? nameEn.nonEmpty ?? meetingSv.nonEmpty ?? meetingEn.nonEmpty ?? id
    }

    func localizedTitle(language: AppLanguage) -> String {
        localizedCVContent(language: language, swedish: titleSv, english: titleEn)
    }

    func localizedName(language: AppLanguage) -> String {
        if !contributorNames.isEmpty {
            return contributorNames.joined(separator: ", ")
        }
        return localizedCVContent(language: language, swedish: nameSv, english: nameEn)
    }

    func localizedMeeting(language: AppLanguage) -> String {
        localizedCVContent(language: language, swedish: meetingSv, english: meetingEn)
    }

    var projectName: String {
        get { projectNameSv.nonEmpty ?? projectNameEn }
        set {
            projectNameSv = newValue
            projectNameEn = newValue
        }
    }

    func localizedProjectName(language: AppLanguage) -> String {
        localizedCVContent(language: language, swedish: projectNameSv, english: projectNameEn)
    }

    func localizedPublicationData(language: AppLanguage) -> String {
        localizedCVContent(language: language, swedish: commentsSv, english: commentsEn)
    }

    mutating func setLocalizedTitle(_ value: String, language: AppLanguage) {
        if language == .swedish {
            titleSv = value
        } else {
            titleEn = value
        }
    }

    mutating func setLocalizedName(_ value: String, language: AppLanguage) {
        if language == .swedish {
            nameSv = value
        } else {
            nameEn = value
        }
    }

    mutating func setLocalizedProjectName(_ value: String, language: AppLanguage) {
        if language == .swedish {
            projectNameSv = value
        } else {
            projectNameEn = value
        }
    }

    mutating func setLocalizedMeeting(_ value: String, language: AppLanguage) {
        if language == .swedish {
            meetingSv = value
        } else {
            meetingEn = value
        }
    }

    mutating func setLocalizedPublicationData(_ value: String, language: AppLanguage) {
        if language == .swedish {
            commentsSv = value
        } else {
            commentsEn = value
        }
    }

    func localizedComments(language: AppLanguage) -> String {
        localizedCVContent(language: language, swedish: commentsSv, english: commentsEn)
    }

    var effectiveStatus: CVConferenceContributionStatus {
        if submissionOutcome == .declined {
            return .rejected
        }
        if submissionOutcome == .granted {
            return status == .presented ? .presented : .accepted
        }
        return status
    }

    var isRejected: Bool {
        effectiveStatus == .rejected
    }

    var isAcceptedOrPresented: Bool {
        submissionOutcome == .granted || status == .presented
    }

    /// Round 12 (user decision 2026-09-30): the CV and the annual report list
    /// only contributions that are submitted (awaiting a decision) or
    /// accepted/presented. Planned, not yet submitted and rejected ones are
    /// left out.
    var isCVReportable: Bool {
        switch effectiveStatus {
        case .accepted, .presented:
            return true
        case .planned:
            return submissionAppliedOn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .rejected:
            return false
        }
    }

    mutating func setLocalizedComments(_ value: String, language: AppLanguage) {
        if language == .swedish {
            commentsSv = value
        } else {
            commentsEn = value
        }
    }

    private static func inferredStatus(
        explicit: CVConferenceContributionStatus?
    ) -> CVConferenceContributionStatus {
        if let explicit {
            return explicit
        }
        return .planned
    }
}

struct CVMediaAttachment: Codable, Hashable, Identifiable {
    var id: String
    var filename: String
    var storedFilename: String

    init(id: String = UUID().uuidString, filename: String, storedFilename: String) {
        self.id = id
        self.filename = filename
        self.storedFilename = storedFilename
    }
}

struct CVMediaAppearance: Codable, Hashable, Identifiable {
    var id: String
    var authorID: String?
    var authorIDs: [String]
    var projectIDs: [String]
    var publicationIDs: [String]
    var applicationIDs: [String]
    var date: String
    var publicationDate: String
    var startTime: String
    var endTime: String
    var meetingMode: String
    var place: String
    var country: String
    var titleSv: String
    var titleEn: String
    var descriptionSv: String
    var descriptionEn: String
    var link: String
    var pdfFilename: String?
    var pdfPath: String?
    var languageSv: String
    var languageEn: String
    var attachments: [CVMediaAttachment]
    var isEditingLocked: Bool
    var languages: [String]
    var comment: String

    enum CodingKeys: String, CodingKey {
        case id
        case authorID
        case authorIDs
        case projectIDs
        case publicationIDs
        case applicationIDs
        case date
        case publicationDate
        case startTime
        case endTime
        case meetingMode
        case place
        case country
        case title
        case titleSv
        case titleEn
        case description
        case descriptionSv
        case descriptionEn
        case link
        case pdfFilename
        case pdfPath
        case languageOption
        case languageSv
        case languageEn
        case attachments
        case isEditingLocked
        case languages
        case comment
    }

    init(
        id: String = UUID().uuidString,
        authorID: String? = nil,
        authorIDs: [String] = [],
        projectIDs: [String] = [],
        publicationIDs: [String] = [],
        applicationIDs: [String] = [],
        date: String = "",
        publicationDate: String = "",
        startTime: String = "",
        endTime: String = "",
        meetingMode: String = "",
        place: String = "",
        country: String = "",
        title: String = "",
        description: String = "",
        link: String = "",
        pdfFilename: String? = nil,
        pdfPath: String? = nil,
        language: String = "",
        comment: String = ""
    ) {
        self.id = id
        self.authorID = authorID
        self.authorIDs = authorIDs.isEmpty ? [authorID].compactMap { $0 } : authorIDs
        self.projectIDs = projectIDs
        self.publicationIDs = publicationIDs
        self.applicationIDs = applicationIDs
        self.date = date
        self.publicationDate = publicationDate
        self.startTime = startTime
        self.endTime = endTime
        self.meetingMode = meetingMode
        self.place = place
        self.country = country
        self.titleSv = title
        self.titleEn = title
        self.descriptionSv = description
        self.descriptionEn = description
        self.link = link
        self.pdfFilename = pdfFilename
        self.pdfPath = pdfPath
        self.languageSv = language
        self.languageEn = language
        self.attachments = []
        self.isEditingLocked = false
        self.languages = language.isEmpty ? [] : [language]
        self.comment = comment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyTitle = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        let legacyDescription = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        let legacyLanguage: String = {
            if let value = try? container.decodeIfPresent(String.self, forKey: .languageSv), !value.isEmpty {
                return value
            }
            if let option = try? container.decodeIfPresent(String.self, forKey: .languageOption) {
                switch option {
                case "Swedish":
                    return "Swedish"
                case "English":
                    return "English"
                default:
                    return option
                }
            }
            return ""
        }()
        let legacyDate = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            authorID: try container.decodeIfPresent(String.self, forKey: .authorID),
            date: legacyDate,
            publicationDate: try container.decodeIfPresent(String.self, forKey: .publicationDate) ?? legacyDate,
            startTime: try container.decodeIfPresent(String.self, forKey: .startTime) ?? "",
            endTime: try container.decodeIfPresent(String.self, forKey: .endTime) ?? "",
            meetingMode: try container.decodeIfPresent(String.self, forKey: .meetingMode) ?? "",
            place: try container.decodeIfPresent(String.self, forKey: .place) ?? "",
            country: try container.decodeIfPresent(String.self, forKey: .country) ?? "",
            title: legacyTitle.nonEmpty ?? legacyDescription,
            description: legacyDescription,
            link: try container.decodeIfPresent(String.self, forKey: .link) ?? "",
            pdfFilename: try container.decodeIfPresent(String.self, forKey: .pdfFilename),
            pdfPath: try container.decodeIfPresent(String.self, forKey: .pdfPath),
            language: legacyLanguage
        )
        self.titleSv = try container.decodeIfPresent(String.self, forKey: .titleSv) ?? self.titleSv
        self.titleEn = try container.decodeIfPresent(String.self, forKey: .titleEn) ?? self.titleEn
        self.descriptionSv = try container.decodeIfPresent(String.self, forKey: .descriptionSv) ?? self.descriptionSv
        self.descriptionEn = try container.decodeIfPresent(String.self, forKey: .descriptionEn) ?? self.descriptionEn
        self.languageSv = try container.decodeIfPresent(String.self, forKey: .languageSv) ?? self.languageSv
        self.languageEn = try container.decodeIfPresent(String.self, forKey: .languageEn) ?? self.languageEn
        self.attachments = try container.decodeIfPresent([CVMediaAttachment].self, forKey: .attachments) ?? []
        self.isEditingLocked = try container.decodeIfPresent(Bool.self, forKey: .isEditingLocked) ?? false
        self.languages = try container.decodeIfPresent([String].self, forKey: .languages)
            ?? Self.normalizedLanguageCodes([self.languageSv, self.languageEn])
        self.authorIDs = try container.decodeIfPresent([String].self, forKey: .authorIDs)
            ?? [self.authorID].compactMap { $0 }
        self.projectIDs = try container.decodeIfPresent([String].self, forKey: .projectIDs) ?? []
        self.publicationIDs = try container.decodeIfPresent([String].self, forKey: .publicationIDs) ?? []
        self.applicationIDs = try container.decodeIfPresent([String].self, forKey: .applicationIDs) ?? []
        self.comment = try container.decodeIfPresent(String.self, forKey: .comment) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(authorID, forKey: .authorID)
        try container.encode(authorIDs, forKey: .authorIDs)
        try container.encode(projectIDs, forKey: .projectIDs)
        try container.encode(publicationIDs, forKey: .publicationIDs)
        try container.encode(applicationIDs, forKey: .applicationIDs)
        try container.encode(date, forKey: .date)
        try container.encode(publicationDate, forKey: .publicationDate)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(meetingMode, forKey: .meetingMode)
        try container.encode(place, forKey: .place)
        try container.encode(country, forKey: .country)
        try container.encode(titleSv, forKey: .titleSv)
        try container.encode(titleEn, forKey: .titleEn)
        try container.encode(descriptionSv, forKey: .descriptionSv)
        try container.encode(descriptionEn, forKey: .descriptionEn)
        try container.encode(link, forKey: .link)
        try container.encodeIfPresent(pdfFilename, forKey: .pdfFilename)
        try container.encodeIfPresent(pdfPath, forKey: .pdfPath)
        try container.encode(languageSv, forKey: .languageSv)
        try container.encode(languageEn, forKey: .languageEn)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(isEditingLocked, forKey: .isEditingLocked)
        try container.encode(languages, forKey: .languages)
        try container.encode(comment, forKey: .comment)
    }

    mutating func normalize() {
        authorID = authorID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        authorIDs = Self.normalizedIDs(authorIDs)
        authorID = authorIDs.first
        projectIDs = Self.normalizedIDs(projectIDs)
        publicationIDs = Self.normalizedIDs(publicationIDs)
        applicationIDs = Self.normalizedIDs(applicationIDs)
        date = DateParsers.canonicalizedDayInput(date)
        publicationDate = DateParsers.canonicalizedDayInput(publicationDate)
        startTime = normalizedCalendarTimeInput(startTime)
        endTime = normalizedCalendarTimeInput(endTime)
        meetingMode = meetingMode.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedMode = CalendarMeetingMode.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(meetingMode) == .orderedSame
        }) {
            meetingMode = normalizedMode.rawValue
        } else {
            meetingMode = ""
        }
        place = place.trimmingCharacters(in: .whitespacesAndNewlines)
        country = GrantParsing.canonicalCountryName(country)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if meetingMode == CalendarMeetingMode.online.rawValue {
            place = ""
            country = ""
        }
        titleSv = titleSv.trimmingCharacters(in: .whitespacesAndNewlines)
        titleEn = titleEn.trimmingCharacters(in: .whitespacesAndNewlines)
        descriptionSv = descriptionSv.trimmingCharacters(in: .whitespacesAndNewlines)
        descriptionEn = descriptionEn.trimmingCharacters(in: .whitespacesAndNewlines)
        link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        pdfFilename = pdfFilename?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        pdfPath = pdfPath?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        languageSv = languageSv.trimmingCharacters(in: .whitespacesAndNewlines)
        languageEn = languageEn.trimmingCharacters(in: .whitespacesAndNewlines)
        languages = Self.normalizedLanguageCodes(languages)
        comment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedIDs(_ values: [String]) -> [String] {
        Array(NSOrderedSet(array: values.compactMap(\.trimmedOrNil))) as? [String]
            ?? values.compactMap(\.trimmedOrNil)
    }

    private static func normalizedLanguageCodes(_ values: [String]) -> [String] {
        Array(Set(values.compactMap { raw -> String? in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return MediaLanguageOption.canonicalCode(for: value, options: MediaLanguageOption.builtInOptions) ?? value.nonEmpty
        })).sorted()
    }

    var isEmpty: Bool {
        date.nonEmpty == nil &&
            publicationDate.nonEmpty == nil &&
            startTime.nonEmpty == nil &&
            endTime.nonEmpty == nil &&
            meetingMode.nonEmpty == nil &&
            place.nonEmpty == nil &&
            country.nonEmpty == nil &&
            titleSv.nonEmpty == nil &&
            titleEn.nonEmpty == nil &&
            descriptionSv.nonEmpty == nil &&
            descriptionEn.nonEmpty == nil &&
            link.nonEmpty == nil &&
            pdfFilename?.trimmedOrNil == nil &&
            pdfPath?.trimmedOrNil == nil &&
            languageSv.nonEmpty == nil &&
            languageEn.nonEmpty == nil &&
            projectIDs.isEmpty &&
            publicationIDs.isEmpty &&
            applicationIDs.isEmpty &&
            comment.nonEmpty == nil
    }

    var displayTitle: String {
        titleSv.nonEmpty ?? titleEn.nonEmpty ?? descriptionSv.nonEmpty ?? descriptionEn.nonEmpty ?? link.nonEmpty ?? id
    }

    func localizedTitle(language: AppLanguage) -> String {
        localizedCVContent(language: language, swedish: titleSv, english: titleEn)
    }

    func localizedDescription(language: AppLanguage) -> String {
        localizedCVContent(language: language, swedish: descriptionSv, english: descriptionEn)
    }

    func localizedLanguage(language: AppLanguage) -> String {
        localizedCVContent(language: language, swedish: languageSv, english: languageEn)
    }

    mutating func setLocalizedDescription(_ value: String, language: AppLanguage) {
        if language == .swedish {
            descriptionSv = value
        } else {
            descriptionEn = value
        }
    }

    mutating func setLocalizedTitle(_ value: String, language: AppLanguage) {
        if language == .swedish {
            titleSv = value
        } else {
            titleEn = value
        }
    }

    mutating func setLocalizedLanguage(_ value: String, language: AppLanguage) {
        if language == .swedish {
            languageSv = value
        } else {
            languageEn = value
        }
    }
}

struct CVReviewEntry: Codable, Hashable, Identifiable {
    var id: String
    var authorID: String?
    var categoryRaw: String
    var acceptedDate: String
    var deadlineDate: String
    var date: String
    var journalName: String
    /// F13: the journal by id; `journalName` is its name, kept for display.
    var journalID: String?
    var organizationName: String
    /// "Alla kopplingar via id": the organization by id; `organizationName`
    /// is its name, kept for display (and the only value for older rows and
    /// for organizations that are not in the organization list).
    var organizationID: String?
    var programName: String
    var subjectTitle: String
    var personName: String
    var roleName: String
    var reference: String
    /// F8: review round (first review, R1, R2 …) so that one manuscript can have several rows.
    var reviewRound: String
    var commentSv: String
    var commentEn: String
    var certificateFilename: String?
    var certificatePDFData: Data?
    var certificatePath: String?
    var isEditingLocked: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case authorID
        case categoryRaw
        case acceptedDate
        case deadlineDate
        case date
        case journalName
        case journalID
        case organizationName
        case organizationID
        case programName
        case subjectTitle
        case personName
        case roleName
        case reference
        case reviewRound
        case comment
        case commentSv
        case commentEn
        case certificateFilename
        case certificatePDFData
        case certificatePath
        case isEditingLocked
    }

    init(
        id: String = UUID().uuidString,
        authorID: String? = nil,
        category: CVReviewCategory = .journalReview,
        acceptedDate: String = "",
        deadlineDate: String = "",
        date: String = "",
        journalName: String = "",
        journalID: String? = nil,
        organizationName: String = "",
        organizationID: String? = nil,
        programName: String = "",
        subjectTitle: String = "",
        personName: String = "",
        roleName: String = "",
        reference: String = "",
        reviewRound: String = "",
        comment: String = "",
        isEditingLocked: Bool = false
    ) {
        self.id = id
        self.authorID = authorID
        self.categoryRaw = category.rawValue
        self.acceptedDate = acceptedDate
        self.deadlineDate = deadlineDate
        self.date = date
        self.journalName = journalName
        self.journalID = journalID
        self.organizationName = organizationName
        self.organizationID = organizationID
        self.programName = programName
        self.subjectTitle = subjectTitle
        self.personName = personName
        self.roleName = roleName
        self.reference = reference
        self.reviewRound = reviewRound
        self.commentSv = comment
        self.commentEn = comment
        self.certificateFilename = nil
        self.certificatePDFData = nil
        self.certificatePath = nil
        self.isEditingLocked = isEditingLocked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyComment = try container.decodeIfPresent(String.self, forKey: .comment) ?? ""
        let decodedJournal = try container.decodeIfPresent(String.self, forKey: .journalName) ?? ""
        let inferredCategory: CVReviewCategory = {
            if let raw = try? container.decodeIfPresent(String.self, forKey: .categoryRaw),
               let value = CVReviewCategory(rawValue: raw) {
                return value
            }
            return decodedJournal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .grantProposalReview : .journalReview
        }()
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            authorID: try container.decodeIfPresent(String.self, forKey: .authorID),
            category: inferredCategory,
            acceptedDate: try container.decodeIfPresent(String.self, forKey: .acceptedDate) ?? "",
            deadlineDate: try container.decodeIfPresent(String.self, forKey: .deadlineDate) ?? "",
            date: try container.decodeIfPresent(String.self, forKey: .date) ?? "",
            journalName: decodedJournal,
            journalID: try container.decodeIfPresent(String.self, forKey: .journalID),
            organizationName: try container.decodeIfPresent(String.self, forKey: .organizationName) ?? "",
            organizationID: try container.decodeIfPresent(String.self, forKey: .organizationID),
            programName: try container.decodeIfPresent(String.self, forKey: .programName) ?? "",
            subjectTitle: try container.decodeIfPresent(String.self, forKey: .subjectTitle) ?? "",
            personName: try container.decodeIfPresent(String.self, forKey: .personName) ?? "",
            roleName: try container.decodeIfPresent(String.self, forKey: .roleName) ?? "",
            reference: try container.decodeIfPresent(String.self, forKey: .reference) ?? "",
            reviewRound: try container.decodeIfPresent(String.self, forKey: .reviewRound) ?? "",
            comment: legacyComment,
            isEditingLocked: try container.decodeIfPresent(Bool.self, forKey: .isEditingLocked) ?? false
        )
        self.commentSv = try container.decodeIfPresent(String.self, forKey: .commentSv) ?? self.commentSv
        self.commentEn = try container.decodeIfPresent(String.self, forKey: .commentEn) ?? self.commentEn
        self.certificateFilename = try container.decodeIfPresent(String.self, forKey: .certificateFilename)
        self.certificatePDFData = try container.decodeIfPresent(Data.self, forKey: .certificatePDFData)
        self.certificatePath = try container.decodeIfPresent(String.self, forKey: .certificatePath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(authorID, forKey: .authorID)
        try container.encode(categoryRaw, forKey: .categoryRaw)
        try container.encode(acceptedDate, forKey: .acceptedDate)
        try container.encode(deadlineDate, forKey: .deadlineDate)
        try container.encode(date, forKey: .date)
        try container.encode(journalName, forKey: .journalName)
        try container.encodeIfPresent(journalID, forKey: .journalID)
        try container.encode(organizationName, forKey: .organizationName)
        try container.encodeIfPresent(organizationID, forKey: .organizationID)
        try container.encode(programName, forKey: .programName)
        try container.encode(subjectTitle, forKey: .subjectTitle)
        try container.encode(personName, forKey: .personName)
        try container.encode(roleName, forKey: .roleName)
        try container.encode(reference, forKey: .reference)
        try container.encode(reviewRound, forKey: .reviewRound)
        try container.encode(commentSv, forKey: .commentSv)
        try container.encode(commentEn, forKey: .commentEn)
        try container.encodeIfPresent(certificateFilename, forKey: .certificateFilename)
        try container.encodeIfPresent(certificatePDFData, forKey: .certificatePDFData)
        try container.encodeIfPresent(certificatePath, forKey: .certificatePath)
        try container.encode(isEditingLocked, forKey: .isEditingLocked)
    }

    var category: CVReviewCategory {
        get { CVReviewCategory(rawValue: categoryRaw) ?? .journalReview }
        set { categoryRaw = newValue.rawValue }
    }

    mutating func normalize() {
        authorID = authorID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        acceptedDate = DateParsers.canonicalizedDayInput(acceptedDate)
        deadlineDate = DateParsers.canonicalizedDayInput(deadlineDate)
        date = DateParsers.canonicalizedDayInput(date)
        categoryRaw = category.rawValue
        journalName = journalName.trimmingCharacters(in: .whitespacesAndNewlines)
        journalID = journalID?.trimmedOrNil
        organizationName = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        organizationID = organizationID?.trimmedOrNil
        programName = programName.trimmingCharacters(in: .whitespacesAndNewlines)
        subjectTitle = subjectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        personName = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        roleName = roleName.trimmingCharacters(in: .whitespacesAndNewlines)
        reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        reviewRound = reviewRound.trimmingCharacters(in: .whitespacesAndNewlines)
        commentSv = commentSv.trimmingCharacters(in: .whitespacesAndNewlines)
        commentEn = commentEn.trimmingCharacters(in: .whitespacesAndNewlines)
        certificateFilename = certificateFilename?.trimmedOrNil
        if certificatePDFData?.isEmpty == true {
            certificatePDFData = nil
        }
        certificatePath = certificatePath?.trimmedOrNil
    }

    var isEmpty: Bool {
        date.nonEmpty == nil &&
            acceptedDate.nonEmpty == nil &&
            deadlineDate.nonEmpty == nil &&
            journalName.nonEmpty == nil &&
            organizationName.nonEmpty == nil &&
            programName.nonEmpty == nil &&
            subjectTitle.nonEmpty == nil &&
            personName.nonEmpty == nil &&
            roleName.nonEmpty == nil &&
            reference.nonEmpty == nil &&
            commentSv.nonEmpty == nil &&
            commentEn.nonEmpty == nil &&
            certificateFilename?.nonEmpty == nil &&
            certificatePDFData == nil &&
            certificatePath?.nonEmpty == nil
    }

    var displayTitle: String {
        switch category {
        case .journalReview:
            return subjectTitle.nonEmpty ?? journalName.nonEmpty ?? reference.nonEmpty ?? id
        case .grantProposalReview:
            return organizationName.nonEmpty ?? programName.nonEmpty ?? reference.nonEmpty ?? id
        case .doctoralExamination:
            return personName.nonEmpty ?? subjectTitle.nonEmpty ?? organizationName.nonEmpty ?? reference.nonEmpty ?? id
        case .otherExpertAssignment:
            return subjectTitle.nonEmpty ?? roleName.nonEmpty ?? organizationName.nonEmpty ?? reference.nonEmpty ?? id
        }
    }

    var listTitle: String {
        switch category {
        case .journalReview:
            let title = [subjectTitle.nonEmpty, journalName.nonEmpty, reviewRound.nonEmpty]
                .compactMap { $0 }
                .joined(separator: " - ")
            return title.nonEmpty ?? reference.nonEmpty ?? id
        case .grantProposalReview:
            return organizationName.nonEmpty ?? reference.nonEmpty ?? id
        case .doctoralExamination:
            return organizationName.nonEmpty ?? personName.nonEmpty ?? reference.nonEmpty ?? id
        case .otherExpertAssignment:
            return organizationName.nonEmpty ?? roleName.nonEmpty ?? reference.nonEmpty ?? id
        }
    }

    func localizedComment(language: AppLanguage) -> String {
        localizedCVContent(language: language, swedish: commentSv, english: commentEn)
    }

    var isCompleted: Bool {
        date.trimmedOrNil != nil
    }

    var isAccepted: Bool {
        acceptedDate.trimmedOrNil != nil
    }

    var hasDeadline: Bool {
        deadlineDate.trimmedOrNil != nil
    }

    func workflowStatus(referenceDate: Date = Date(), calendar: Calendar = .current) -> CVReviewWorkflowStatus? {
        if isCompleted {
            return .completed
        }
        guard isAccepted else { return nil }
        if let deadline = deadlineDay(calendar: calendar),
           deadline < calendar.startOfDay(for: referenceDate) {
            return .overdue
        }
        return .accepted
    }

    func deadlineDay(calendar: Calendar = .current) -> Date? {
        deadlineDate.trimmedOrNil
            .flatMap(DateParsers.isoDay.date(from:))
            .map { calendar.startOfDay(for: $0) }
    }

    mutating func setLocalizedComment(_ value: String, language: AppLanguage) {
        if language == .swedish {
            commentSv = value
        } else {
            commentEn = value
        }
    }
}

struct CVOtherPublicationEntry: Codable, Hashable, Identifiable {
    var id: String
    var date: String
    var categorySv: String
    var categoryEn: String
    var authors: String
    var titleSv: String
    var titleEn: String
    var outletSv: String
    var outletEn: String
    var publisherShortName: String
    var publicationDataSv: String
    var publicationDataEn: String
    var city: String
    var doi: String
    var languageSv: String
    var languageEn: String
    var mainSupervisor: String
    var coSupervisor: String

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case category
        case categorySv
        case categoryEn
        case authors
        case title
        case titleSv
        case titleEn
        case outlet
        case outletSv
        case outletEn
        case publisherShortName
        case publicationData
        case publicationDataSv
        case publicationDataEn
        case city
        case doi
        case language
        case languageSv
        case languageEn
        case mainSupervisor
        case coSupervisor
    }

    init(
        id: String = UUID().uuidString,
        date: String = "",
        category: String = "",
        authors: String = "",
        title: String = "",
        outlet: String = "",
        publisherShortName: String = "",
        publicationData: String = "",
        city: String = "",
        doi: String = "",
        language: String = "",
        mainSupervisor: String = "",
        coSupervisor: String = ""
    ) {
        self.id = id
        self.date = date
        self.categorySv = category
        self.categoryEn = category
        self.authors = authors
        self.titleSv = title
        self.titleEn = title
        self.outletSv = outlet
        self.outletEn = outlet
        self.publisherShortName = publisherShortName
        self.publicationDataSv = publicationData
        self.publicationDataEn = publicationData
        self.city = city
        self.doi = doi
        self.languageSv = language
        self.languageEn = language
        self.mainSupervisor = mainSupervisor
        self.coSupervisor = coSupervisor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            date: try container.decodeIfPresent(String.self, forKey: .date) ?? "",
            category: try container.decodeIfPresent(String.self, forKey: .category) ?? "",
            authors: try container.decodeIfPresent(String.self, forKey: .authors) ?? "",
            title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
            outlet: try container.decodeIfPresent(String.self, forKey: .outlet) ?? "",
            publisherShortName: try container.decodeIfPresent(String.self, forKey: .publisherShortName) ?? "",
            publicationData: try container.decodeIfPresent(String.self, forKey: .publicationData) ?? ""
        )
        self.categorySv = try container.decodeIfPresent(String.self, forKey: .categorySv) ?? self.categorySv
        self.categoryEn = try container.decodeIfPresent(String.self, forKey: .categoryEn) ?? self.categoryEn
        self.titleSv = try container.decodeIfPresent(String.self, forKey: .titleSv) ?? self.titleSv
        self.titleEn = try container.decodeIfPresent(String.self, forKey: .titleEn) ?? self.titleEn
        self.outletSv = try container.decodeIfPresent(String.self, forKey: .outletSv) ?? self.outletSv
        self.outletEn = try container.decodeIfPresent(String.self, forKey: .outletEn) ?? self.outletEn
        self.publicationDataSv = try container.decodeIfPresent(String.self, forKey: .publicationDataSv) ?? self.publicationDataSv
        self.publicationDataEn = try container.decodeIfPresent(String.self, forKey: .publicationDataEn) ?? self.publicationDataEn
        self.city = try container.decodeIfPresent(String.self, forKey: .city) ?? ""
        self.doi = try container.decodeIfPresent(String.self, forKey: .doi) ?? ""
        let legacyLanguage = try container.decodeIfPresent(String.self, forKey: .language) ?? ""
        self.languageSv = try container.decodeIfPresent(String.self, forKey: .languageSv) ?? legacyLanguage
        self.languageEn = try container.decodeIfPresent(String.self, forKey: .languageEn) ?? legacyLanguage
        self.mainSupervisor = try container.decodeIfPresent(String.self, forKey: .mainSupervisor) ?? ""
        self.coSupervisor = try container.decodeIfPresent(String.self, forKey: .coSupervisor) ?? ""
        if isDoctoralThesis {
            hydrateLegacyDoctoralThesisFieldsIfNeeded()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(categorySv, forKey: .categorySv)
        try container.encode(categoryEn, forKey: .categoryEn)
        try container.encode(authors, forKey: .authors)
        try container.encode(titleSv, forKey: .titleSv)
        try container.encode(titleEn, forKey: .titleEn)
        try container.encode(outletSv, forKey: .outletSv)
        try container.encode(outletEn, forKey: .outletEn)
        try container.encode(publisherShortName, forKey: .publisherShortName)
        try container.encode(publicationDataSv, forKey: .publicationDataSv)
        try container.encode(publicationDataEn, forKey: .publicationDataEn)
        try container.encode(city, forKey: .city)
        try container.encode(doi, forKey: .doi)
        try container.encode(languageSv, forKey: .languageSv)
        try container.encode(languageEn, forKey: .languageEn)
        try container.encode(mainSupervisor, forKey: .mainSupervisor)
        try container.encode(coSupervisor, forKey: .coSupervisor)
    }

    mutating func normalize() {
        date = DateParsers.canonicalizedDayInput(date)
        categorySv = categorySv.trimmingCharacters(in: .whitespacesAndNewlines)
        categoryEn = categoryEn.trimmingCharacters(in: .whitespacesAndNewlines)
        authors = authors.trimmingCharacters(in: .whitespacesAndNewlines)
        titleSv = titleSv.trimmingCharacters(in: .whitespacesAndNewlines)
        titleEn = titleEn.trimmingCharacters(in: .whitespacesAndNewlines)
        outletSv = outletSv.trimmingCharacters(in: .whitespacesAndNewlines)
        outletEn = outletEn.trimmingCharacters(in: .whitespacesAndNewlines)
        publisherShortName = publisherShortName.trimmingCharacters(in: .whitespacesAndNewlines)
        publicationDataSv = publicationDataSv.trimmingCharacters(in: .whitespacesAndNewlines)
        publicationDataEn = publicationDataEn.trimmingCharacters(in: .whitespacesAndNewlines)
        city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        doi = doi.trimmingCharacters(in: .whitespacesAndNewlines)
        languageSv = languageSv.trimmingCharacters(in: .whitespacesAndNewlines)
        languageEn = languageEn.trimmingCharacters(in: .whitespacesAndNewlines)
        mainSupervisor = mainSupervisor.trimmingCharacters(in: .whitespacesAndNewlines)
        coSupervisor = coSupervisor.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool {
        date.nonEmpty == nil &&
        categorySv.nonEmpty == nil &&
        categoryEn.nonEmpty == nil &&
        authors.nonEmpty == nil &&
        titleSv.nonEmpty == nil &&
        titleEn.nonEmpty == nil &&
        outletSv.nonEmpty == nil &&
        outletEn.nonEmpty == nil &&
        publisherShortName.nonEmpty == nil &&
        city.nonEmpty == nil &&
        doi.nonEmpty == nil &&
        languageSv.nonEmpty == nil &&
        languageEn.nonEmpty == nil &&
        mainSupervisor.nonEmpty == nil &&
        coSupervisor.nonEmpty == nil &&
        publicationDataSv.nonEmpty == nil &&
        publicationDataEn.nonEmpty == nil
    }

    var displayTitle: String {
        titleSv.nonEmpty ?? titleEn.nonEmpty ?? authors.nonEmpty ?? id
    }

    func localizedCategory(language: AppLanguage) -> String {
        localizedCVContent(language: language, swedish: categorySv, english: categoryEn)
    }

    func localizedTitle(language: AppLanguage) -> String {
        localizedCVContent(language: language, swedish: titleSv, english: titleEn)
    }

    func localizedOutlet(language: AppLanguage) -> String {
        localizedCVContent(language: language, swedish: outletSv, english: outletEn)
    }

    func localizedPublicationData(language: AppLanguage) -> String {
        localizedCVContent(language: language, swedish: publicationDataSv, english: publicationDataEn)
    }

    func localizedLanguage(language: AppLanguage) -> String {
        localizedCVContent(language: language, swedish: languageSv, english: languageEn)
    }

    var doiURL: URL? {
        normalizedIdentifierURL(raw: doi, kind: .doi)
    }

    mutating func setLocalizedCategory(_ value: String, language: AppLanguage) {
        if language == .swedish { categorySv = value } else { categoryEn = value }
    }

    mutating func setLocalizedTitle(_ value: String, language: AppLanguage) {
        if language == .swedish { titleSv = value } else { titleEn = value }
    }

    mutating func setLocalizedOutlet(_ value: String, language: AppLanguage) {
        if language == .swedish { outletSv = value } else { outletEn = value }
    }

    mutating func setLocalizedPublicationData(_ value: String, language: AppLanguage) {
        if language == .swedish { publicationDataSv = value } else { publicationDataEn = value }
    }

    mutating func setLocalizedLanguage(_ value: String, language: AppLanguage) {
        if language == .swedish { languageSv = value } else { languageEn = value }
    }

    var isDoctoralThesis: Bool {
        let categories = [
            categorySv.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            categoryEn.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
        ]
        return categories.contains("doctoral thesis") || categories.contains("doktorsavhandling")
    }

    private mutating func hydrateLegacyDoctoralThesisFieldsIfNeeded() {
        if doi.nonEmpty == nil, let extracted = Self.firstMatch(in: publicationDataSv.nonEmpty ?? publicationDataEn, pattern: #"(?i)doi:\s*([^\s]+)"#) {
            doi = extracted.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        }

        if mainSupervisor.nonEmpty == nil, let extracted = Self.firstMatch(in: publicationDataSv.nonEmpty ?? publicationDataEn, pattern: #"(?i)(?:main supervisor|huvudhandledare):\s*([^.]+)"#) {
            mainSupervisor = extracted.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if coSupervisor.nonEmpty == nil, let extracted = Self.firstMatch(in: publicationDataSv.nonEmpty ?? publicationDataEn, pattern: #"(?i)(?:co-supervisor|bihandledare):\s*([^.]+)"#) {
            coSupervisor = extracted.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if languageSv.nonEmpty == nil && languageEn.nonEmpty == nil {
            let legacyText = [publicationDataSv, publicationDataEn].joined(separator: " ").lowercased()
            if legacyText.contains("english") || legacyText.contains("engelska") {
                languageSv = "Engelska"
                languageEn = "English"
            } else if legacyText.contains("swedish") || legacyText.contains("svenska") {
                languageSv = "Svenska"
                languageEn = "Swedish"
            }
        }

        let source = outletSv.nonEmpty ?? outletEn.nonEmpty ?? ""
        if publisherShortName.nonEmpty == nil,
           let range = source.range(of: "[short name:", options: [.caseInsensitive, .backwards]),
           let closingBracket = source[range.upperBound...].firstIndex(of: "]") {
            let shortName = source[range.upperBound..<closingBracket]
                .trimmingCharacters(in: CharacterSet(charactersIn: " :]"))
            if shortName.nonEmpty != nil {
                publisherShortName = shortName
                let cleaned = source[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if outletSv == source {
                    outletSv = cleaned
                }
                if outletEn == source {
                    outletEn = cleaned
                }
            }
        }

        if city.nonEmpty == nil {
            if let range = source.range(of: ",", options: .backwards) {
                let candidate = source[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate.nonEmpty != nil {
                    city = candidate
                    let trimmedOutlet = source[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                    if outletSv == source {
                        outletSv = trimmedOutlet
                    }
                    if outletEn == source {
                        outletEn = trimmedOutlet
                    }
                }
            }
        }
    }

    private static func firstMatch(in text: String?, pattern: String) -> String? {
        guard let text, let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[valueRange])
    }
}

struct CVExportSection: Codable, Hashable {
    var title: String
    var layoutKind: String = "default"
    var headers: [String] = []
    var rows: [[String]] = []
    var paragraphs: [String] = []
    var richParagraphs: [CVExportRichTextParagraph] = []
    var items: [String] = []
    var itemSourceIDs: [String]? = nil
    var subsections: [CVExportSubsection] = []
}

struct CVExportSubsection: Codable, Hashable {
    var title: String
    var paragraphs: [String] = []
    var richParagraphs: [CVExportRichTextParagraph] = []
    /// Horizontal statistic bars; rendered as CSS bars in HTML/PDF and as
    /// fixed-layout shaded tables in the DOCX export.
    var bars: [CVExportStatisticBar] = []
    var items: [String] = []
    var itemSourceIDs: [String]? = nil
    var amaItems: [PublicationAMAItem] = []
    var vrItems: [CVExportVRItem] = []
}

struct CVExportStatisticBar: Codable, Hashable {
    var label: String
    var valueText: String
    /// 0...1 share of the full bar track width.
    var fraction: Double
    /// Six-digit hex without leading '#'.
    var colorHex: String
}

struct CVExportVRItem: Codable, Hashable {
    var citation: String
    var note: String = ""
    var sourceID: String? = nil
}

struct CVExportRichTextRun: Codable, Hashable {
    var text: String
    var bold: Bool = false
    var italic: Bool = false
    var underline: Bool = false
}

struct CVExportRichTextParagraph: Codable, Hashable {
    var runs: [CVExportRichTextRun]
}

struct CVExportDocument: Codable, Hashable {
    var style: String = "own"
    var exportLanguage: String = AppLanguage.english.rawValue
    var highlightName: String = ""
    var title: String
    var subtitle: String
    /// Rendered right-aligned on the same line as the title (e.g. the
    /// generation date of a project document).
    var titleTrailingText: String = ""
    var summaryLines: [String]
    var summaryRichParagraphs: [CVExportRichTextParagraph] = []
    var sections: [CVExportSection]
    var headerText: String = ""
    var footerText: String = ""
    var includePageNumbers: Bool = false
    /// Tightens table row padding in the HTML preview/PDF; the DOCX tables
    /// are single-spaced already.
    var compactTables: Bool = false
}
