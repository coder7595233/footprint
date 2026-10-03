import Foundation

/// Which field a row in the Data view's "Missing fields" list stands for.
/// The visible text stays in `MissingFieldIssue.missingFields`; the key lets
/// the Data view offer a text box for the field and search buttons for it.
/// The raw values are stored in the hidden-warnings list, so they must not
/// change.
enum DataQualityFieldKey: String, CaseIterable, Codable, Hashable, Sendable {
    // Researchers
    case researcherFirstName
    case researcherLastName
    case researcherTitle
    case researcherPosition
    case researcherDegree
    case researcherORCID
    case researcherORCIDFormat
    case researcherORCIDCheckDigit
    case researcherPrimaryOrganization
    case researcherPrimaryCountry
    case researcherPrimaryEmail
    case researcherGender
    // Publications
    case publicationTitle
    case publicationJournal
    case publicationYear
    case publicationAuthors
    case publicationDOIFormat
    case publicationPMIDFormat
    // Organizations
    case organizationWebsiteFormat
    // Journals
    case journalName
    case journalISSN
    case journalURLFormat
    case journalSubmissionPortalFormat
    // Projects
    case projectSwedishName
    // Applications
    case applicationFunder
    case applicationTitle
    // Doctoral candidates
    case doctoralCandidateName
    case doctoralInstitution

    /// The field already holds a value that is wrong (not missing): emptying
    /// the box is then a valid fix.
    var correctsExistingValue: Bool {
        switch self {
        case .researcherORCIDFormat,
             .researcherORCIDCheckDigit,
             .publicationDOIFormat,
             .publicationPMIDFormat,
             .organizationWebsiteFormat,
             .journalURLFormat,
             .journalSubmissionPortalFormat:
            return true
        default:
            return false
        }
    }

    var isORCID: Bool {
        self == .researcherORCID || self == .researcherORCIDFormat || self == .researcherORCIDCheckDigit
    }

    var isPublicationIdentifier: Bool {
        self == .publicationDOIFormat || self == .publicationPMIDFormat
    }
}

/// What a search is about: a person, a publication, an organization or a
/// journal. Only what is already known is filled in.
struct DataQualitySearchSubject: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case person
        case publication
        case organization
        case journal
    }

    var kind: Kind
    /// Person: first name(s), possibly with a middle name or initial.
    var firstName: String = ""
    /// Person: last name.
    var lastName: String = ""
    /// Person: the full display name (used when first and last name are not
    /// split). Others: the title or name.
    var name: String = ""
    /// Person: the organization the person belongs to, when known.
    var organization: String = ""
}

/// One search button next to a missing field.
struct DataQualitySearchLink: Equatable, Identifiable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case google
        case orcid
        case pubmed
        case crossref
    }

    let kind: Kind
    /// What is searched for, shown in the button's tooltip only.
    let query: String
    let url: URL

    var id: String { kind.rawValue }
}

/// Builds the web searches offered for a missing field. Pure functions with
/// no app state, so they can be tested on their own.
///
/// Google's documented operators are used: an exact phrase in quotes, OR in
/// capitals between alternatives. AND is not used (Google ignores it).
/// Google reads at most 32 words, so queries are kept short.
enum DataQualitySearchQuery {
    static let googleWordLimit = 32
    /// A long title is cut to this many words before it is quoted.
    static let maximumPhraseWords = 20

    // MARK: Building blocks

    /// Text in quotes for an exact-phrase search. Quote marks inside the text
    /// are removed and whitespace is collapsed. Nil for empty text.
    static func phrase(_ text: String) -> String? {
        let words = words(in: text.replacingOccurrences(of: "\"", with: " "))
        guard !words.isEmpty else { return nil }
        return "\"" + words.prefix(maximumPhraseWords).joined(separator: " ") + "\""
    }

    /// "(a OR b OR c)"; a single term is returned as it is.
    static func anyOf(_ terms: [String]) -> String? {
        let cleaned = terms.compactMap { term -> String? in
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard !cleaned.isEmpty else { return nil }
        if cleaned.count == 1 { return cleaned[0] }
        return "(" + cleaned.joined(separator: " OR ") + ")"
    }

    /// The person's name as a search term: "First Last". When the stored
    /// first name also holds a middle name or initial, both forms are
    /// searched: ("First Last" OR "First M. Last"), and the full stored form
    /// too when the middle name is written out.
    static func personTerm(firstName: String, lastName: String, fullName: String = "") -> String? {
        var givenWords = words(in: firstName.replacingOccurrences(of: "\"", with: " "))
        var familyWords = words(in: lastName.replacingOccurrences(of: "\"", with: " "))
        if givenWords.isEmpty && familyWords.isEmpty {
            let all = words(in: fullName.replacingOccurrences(of: "\"", with: " "))
            guard !all.isEmpty else { return nil }
            if all.count == 1 { return phrase(all[0]) }
            givenWords = Array(all.dropLast())
            familyWords = [all[all.count - 1]]
        }
        let family = familyWords.joined(separator: " ")
        guard givenWords.count > 1, !family.isEmpty else {
            return phrase((givenWords + familyWords).joined(separator: " "))
        }
        let given = givenWords[0]
        let middle = Array(givenWords.dropFirst())
        let initials = middle.map(initial(of:)).joined(separator: " ")
        var forms: [String] = []
        for form in [
            "\(given) \(family)",
            "\(given) \(initials) \(family)",
            "\(givenWords.joined(separator: " ")) \(family)",
        ] {
            if let quoted = phrase(form), !forms.contains(quoted) {
                forms.append(quoted)
            }
        }
        return anyOf(forms)
    }

    /// "B" or "B." or "Britt" gives "B."; "Britt-Marie" gives "B.".
    static func initial(of word: String) -> String {
        guard let first = word.first(where: { $0.isLetter }) else { return word }
        return String(first).uppercased() + "."
    }

    static func wordCount(_ query: String) -> Int {
        words(in: query).count
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Joins the parts with spaces. Parts after the first are dropped from
    /// the end until the query fits Google's word limit.
    static func joined(_ parts: [String?]) -> String? {
        var kept = parts.compactMap { part -> String? in
            guard let part, !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return part
        }
        guard !kept.isEmpty else { return nil }
        while kept.count > 1, wordCount(kept.joined(separator: " ")) > googleWordLimit {
            kept.removeLast()
        }
        return kept.joined(separator: " ")
    }

    // MARK: Queries

    /// The main search term for the subject: the person's name, or the
    /// title or name in quotes.
    static func subjectTerm(_ subject: DataQualitySearchSubject) -> String? {
        switch subject.kind {
        case .person:
            return personTerm(firstName: subject.firstName, lastName: subject.lastName, fullName: subject.name)
        case .publication, .organization, .journal:
            return phrase(subject.name)
        }
    }

    /// The Google query for one missing field, or nil when nothing is known
    /// to search with.
    static func googleQuery(
        field: DataQualityFieldKey?,
        fieldLabel: String,
        subject: DataQualitySearchSubject
    ) -> String? {
        guard let base = subjectTerm(subject) else { return nil }
        let organization = phrase(subject.organization)
        switch field {
        case .researcherTitle?, .researcherPosition?:
            return joined([
                base,
                organization,
                anyOf(["professor", "docent", "lektor", "postdoc", "forskare", "\"associate professor\"", "researcher"]),
            ])
        case .researcherDegree?:
            return joined([
                base,
                anyOf(["examen", "utbildning", "degree", "education", "MD", "PhD", "MSc"]),
            ])
        case .researcherORCID?, .researcherORCIDFormat?, .researcherORCIDCheckDigit?:
            return joined([base, "orcid"])
        case .researcherPrimaryEmail?:
            return joined([
                base,
                organization,
                anyOf(["e-post", "email", "kontakt", "contact"]),
            ])
        case .researcherPrimaryOrganization?, .researcherPrimaryCountry?:
            return joined([
                base,
                organization,
                anyOf(["universitet", "university", "sjukhus", "hospital", "affiliation"]),
            ])
        case .organizationWebsiteFormat?:
            return joined([base, anyOf(["webbplats", "website"])])
        case .publicationDOIFormat?:
            return joined([base, "doi"])
        case .publicationPMIDFormat?:
            return joined([base, anyOf(["pmid", "pubmed"])])
        case .journalISSN?:
            return joined([base, "ISSN"])
        case .journalURLFormat?:
            return joined([base, anyOf(["journal", "website", "webbplats"])])
        case .journalSubmissionPortalFormat?:
            return joined([base, anyOf(["submission", "\"submit manuscript\""])])
        case .doctoralInstitution?:
            return joined([base, organization, anyOf(["doktorand", "\"doctoral student\"", "\"PhD student\""])])
        default:
            let label = words(in: fieldLabel.replacingOccurrences(of: "\"", with: " ")).joined(separator: " ")
            return joined([base, organization, label.isEmpty ? nil : label])
        }
    }

    /// Every search offered for one missing field: Google always (when the
    /// subject is known), ORCID's own search for a researcher's ORCID, and
    /// PubMed and Crossref for a publication's DOI or PMID.
    static func links(
        field: DataQualityFieldKey?,
        fieldLabel: String,
        subject: DataQualitySearchSubject
    ) -> [DataQualitySearchLink] {
        var links: [DataQualitySearchLink] = []
        if let query = googleQuery(field: field, fieldLabel: fieldLabel, subject: subject),
           let url = googleURL(query: query) {
            links.append(DataQualitySearchLink(kind: .google, query: query, url: url))
        }
        if let field, field.isORCID, subject.kind == .person {
            let name = plainPersonName(subject)
            if !name.isEmpty, let url = orcidSearchURL(name: name) {
                links.append(DataQualitySearchLink(kind: .orcid, query: name, url: url))
            }
        }
        if let field, field.isPublicationIdentifier, subject.kind == .publication {
            let title = words(in: subject.name).joined(separator: " ")
            if !title.isEmpty {
                if let url = pubMedSearchURL(term: title) {
                    links.append(DataQualitySearchLink(kind: .pubmed, query: title, url: url))
                }
                if let url = crossrefSearchURL(query: title) {
                    links.append(DataQualitySearchLink(kind: .crossref, query: title, url: url))
                }
            }
        }
        return links
    }

    /// "First Last" without quotes or middle names, for ORCID's own search.
    static func plainPersonName(_ subject: DataQualitySearchSubject) -> String {
        let given = words(in: subject.firstName).first ?? ""
        let family = words(in: subject.lastName).joined(separator: " ")
        let combined = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
        if !combined.isEmpty { return combined }
        return words(in: subject.name).joined(separator: " ")
    }

    // MARK: URLs

    /// Characters left as they are in a query value. "+", "&", "=", "#",
    /// "?" and "/" are encoded too: a plain "+" would read as a space.
    private static let queryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=#?/")
        return allowed
    }()

    static func encodedQueryValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? ""
    }

    static func url(base: String, queryItems: [(name: String, value: String)]) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        components.percentEncodedQueryItems = queryItems.map {
            URLQueryItem(name: $0.name, value: encodedQueryValue($0.value))
        }
        return components.url
    }

    static func googleURL(query: String) -> URL? {
        url(base: "https://www.google.com/search", queryItems: [(name: "q", value: query)])
    }

    static func orcidSearchURL(name: String) -> URL? {
        url(base: "https://orcid.org/orcid-search/search", queryItems: [(name: "searchQuery", value: name)])
    }

    static func pubMedSearchURL(term: String) -> URL? {
        url(base: "https://pubmed.ncbi.nlm.nih.gov/", queryItems: [(name: "term", value: term)])
    }

    static func crossrefSearchURL(query: String) -> URL? {
        url(
            base: "https://search.crossref.org/search/works",
            queryItems: [(name: "q", value: query), (name: "from_ui", value: "yes")]
        )
    }
}
