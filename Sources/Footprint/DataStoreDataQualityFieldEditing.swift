import Foundation

/// The Data view's "Missing fields" cards: which flagged fields can be typed
/// in directly, saving them through each record's own autosave (so undo,
/// renamed references and saving to disk work as in the record's editor),
/// and what is already known about the record for the context line and the
/// web searches.
extension GrantDataStore {
    /// A flagged field that can be typed in directly in the Data view.
    struct DataQualityEditableField: Equatable {
        /// What the field holds now (empty when it is missing).
        let value: String
        /// The record is locked for editing: the box is shown greyed out and
        /// only Open is offered.
        let isLocked: Bool
    }

    /// Nil when the field is not a plain text field (a list, a date, a
    /// choice or a link to another record): it is then opened in the
    /// record's own editor instead.
    func dataQualityEditableField(
        for issue: MissingFieldIssue,
        field: MissingFieldIssue.Field
    ) -> DataQualityEditableField? {
        guard let key = field.key else { return nil }
        switch key {
        case .researcherFirstName,
             .researcherLastName,
             .researcherTitle,
             .researcherPosition,
             .researcherDegree,
             .researcherORCID,
             .researcherORCIDFormat,
             .researcherORCIDCheckDigit,
             .researcherPrimaryEmail:
            guard issue.destination == .people,
                  let author = publicationAuthor(id: issue.recordID),
                  let value = dataQualityAuthorValue(author, key: key) else {
                return nil
            }
            return DataQualityEditableField(value: value, isLocked: false)
        case .publicationTitle,
             .publicationYear,
             .publicationDOIFormat,
             .publicationPMIDFormat:
            guard issue.destination == .publications,
                  let publication = publication(id: issue.recordID) else {
                return nil
            }
            let value: String
            switch key {
            case .publicationTitle: value = publication.title
            case .publicationYear: value = publication.year
            case .publicationDOIFormat: value = publication.doi
            default: value = publication.pmid
            }
            return DataQualityEditableField(value: value, isLocked: publication.isEditingLocked)
        case .organizationWebsiteFormat:
            guard issue.destination == .organizations,
                  let organization = organization(id: issue.recordID) else {
                return nil
            }
            return DataQualityEditableField(value: organization.websiteURL, isLocked: false)
        case .journalName,
             .journalISSN,
             .journalURLFormat,
             .journalSubmissionPortalFormat:
            guard issue.destination == .journals,
                  let journal = publicationJournal(id: issue.recordID) else {
                return nil
            }
            let value: String
            switch key {
            case .journalName: value = journal.name
            case .journalISSN: value = journal.issn
            case .journalURLFormat: value = journal.journalURL
            default: value = journal.submissionPortalURL
            }
            return DataQualityEditableField(value: value, isLocked: false)
        case .projectSwedishName:
            guard issue.destination == .projects,
                  let project = project(id: issue.recordID) else {
                return nil
            }
            return DataQualityEditableField(value: project.nameSv, isLocked: project.isEditingLocked)
        case .applicationTitle:
            guard issue.destination == .applications,
                  let application = application(id: issue.recordID) else {
                return nil
            }
            return DataQualityEditableField(value: application.applicationTitle ?? "", isLocked: application.isEditingLocked)
        case .doctoralInstitution:
            guard issue.destination == .doctoralCandidates,
                  let candidate = doctoralCandidates.first(where: { $0.id == issue.recordID }) else {
                return nil
            }
            return DataQualityEditableField(value: candidate.institution, isLocked: candidate.isEditingLocked)
        case .researcherPrimaryOrganization,
             .researcherPrimaryCountry,
             .researcherGender,
             .publicationJournal,
             .publicationAuthors,
             .applicationFunder,
             .doctoralCandidateName:
            // Linked to other records or chosen from a list: opened in the
            // record's own editor.
            return nil
        }
    }

    /// Researchers' title, position and degree exist in Swedish and
    /// English; the box edits the language the app is shown in.
    private func dataQualityAuthorValue(_ author: PublicationAuthor, key: DataQualityFieldKey) -> String? {
        let swedish = language == .swedish
        switch key {
        case .researcherFirstName: return author.firstName
        case .researcherLastName: return author.lastName
        case .researcherTitle: return swedish ? author.titleSv : author.titleEn
        case .researcherPosition: return swedish ? author.positionSv : author.positionEn
        case .researcherDegree: return swedish ? author.degreeSv : author.degreeEn
        case .researcherORCID, .researcherORCIDFormat, .researcherORCIDCheckDigit: return author.orcid
        case .researcherPrimaryEmail:
            // Only when the researcher has an affiliation row to put it on.
            guard let primary = author.affiliations.firstIndex(where: \.isPrimary) ?? author.affiliations.indices.first else {
                return nil
            }
            return author.affiliations[primary].email
        default: return nil
        }
    }

    /// Saves one field typed in the Data view. Leading and trailing spaces
    /// are removed; DOI and PMID are written in their plain form (no
    /// doi.org/ prefix) like the publication editor does. An empty box only
    /// clears a value that was flagged as wrong; a missing field is never
    /// "saved" as empty. Locked records are left untouched.
    func saveDataQualityField(_ issue: MissingFieldIssue, field: MissingFieldIssue.Field, value rawValue: String) {
        guard let key = field.key,
              let current = dataQualityEditableField(for: issue, field: field),
              !current.isLocked else {
            return
        }
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch key {
        case .publicationDOIFormat:
            value = AppFieldParsers.canonicalDOI(value)
        case .publicationPMIDFormat:
            value = AppFieldParsers.canonicalPMID(value)
        default:
            break
        }
        guard value != current.value.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        guard !value.isEmpty || key.correctsExistingValue else { return }

        switch key {
        case .researcherFirstName,
             .researcherLastName,
             .researcherTitle,
             .researcherPosition,
             .researcherDegree,
             .researcherORCID,
             .researcherORCIDFormat,
             .researcherORCIDCheckDigit,
             .researcherPrimaryEmail:
            guard var author = publicationAuthor(id: issue.recordID) else { return }
            let previousName = author.name
            let swedish = language == .swedish
            switch key {
            case .researcherFirstName: author.firstName = value
            case .researcherLastName: author.lastName = value
            case .researcherTitle:
                if swedish { author.titleSv = value } else { author.titleEn = value }
            case .researcherPosition:
                if swedish { author.positionSv = value } else { author.positionEn = value }
            case .researcherDegree:
                if swedish { author.degreeSv = value } else { author.degreeEn = value }
            case .researcherPrimaryEmail:
                guard let primary = author.affiliations.firstIndex(where: \.isPrimary) ?? author.affiliations.indices.first else {
                    return
                }
                author.affiliations[primary].email = value
            default:
                author.orcid = value
            }
            autosavePublicationAuthor(author, previousName: previousName)
        case .publicationTitle,
             .publicationYear,
             .publicationDOIFormat,
             .publicationPMIDFormat:
            guard var publication = publication(id: issue.recordID) else { return }
            switch key {
            case .publicationTitle: publication.title = value
            case .publicationYear: publication.year = value
            case .publicationDOIFormat: publication.doi = value
            default: publication.pmid = value
            }
            autosavePublication(publication)
        case .organizationWebsiteFormat:
            guard let organization = organization(id: issue.recordID) else { return }
            autosaveOrganization(
                id: organization.id,
                nameSv: organization.nameSv,
                nameEn: organization.nameEn,
                addressLine: organization.addressLine,
                postalCode: organization.postalCode,
                city: organization.city,
                country: organization.country,
                category: organization.category,
                roles: organization.roles,
                note: organization.note,
                websiteURL: value,
                phoneNumber: organization.phoneNumber,
                organizationNumber: organization.organizationNumber,
                vatNumber: organization.vatNumber,
                employerContacts: organization.employerContacts,
                flag: organization.flag,
                membershipFrom: organization.membershipFrom,
                membershipTo: organization.membershipTo,
                congresses: organization.congresses,
                projectTasks: organization.projectTasks,
                salaryCalculator: organization.salaryCalculator,
                actionName: language.text("Edit website", "Redigera hemsida")
            )
        case .journalName,
             .journalISSN,
             .journalURLFormat,
             .journalSubmissionPortalFormat:
            guard var journal = publicationJournal(id: issue.recordID) else { return }
            let previousName = journal.name
            switch key {
            case .journalName: journal.name = value
            case .journalISSN: journal.issn = value
            case .journalURLFormat: journal.journalURL = value
            default: journal.submissionPortalURL = value
            }
            autosavePublicationJournal(journal, previousName: previousName)
        case .projectSwedishName:
            guard var project = project(id: issue.recordID) else { return }
            let previousID = project.id
            project.nameSv = value
            autosaveProjectRecord(project, previousID: previousID)
        case .applicationTitle:
            guard var application = application(id: issue.recordID) else { return }
            application.applicationTitle = value
            autosave(application: application)
        case .doctoralInstitution:
            guard var candidate = doctoralCandidates.first(where: { $0.id == issue.recordID }) else { return }
            candidate.institution = value
            candidate.institutionID = nil
            autosaveDoctoralCandidate(candidate)
        case .researcherPrimaryOrganization,
             .researcherPrimaryCountry,
             .researcherGender,
             .publicationJournal,
             .publicationAuthors,
             .applicationFunder,
             .doctoralCandidateName:
            return
        }
    }

    /// A short line with what is already known about the record, shown under
    /// its name: for a researcher the organization, position and ORCID; for
    /// a publication the journal, year and first author.
    func dataQualityContextLine(for issue: MissingFieldIssue) -> String {
        let parts: [String?]
        switch issue.destination {
        case .people:
            guard let author = publicationAuthor(id: issue.recordID) else { return issue.subtitle }
            parts = [
                author.primaryAffiliation?.organization.nonEmpty,
                author.localizedPosition(language: language).nonEmpty ?? author.position.nonEmpty,
                author.orcid.nonEmpty.map { "ORCID \($0)" },
            ]
        case .publications:
            guard let publication = publication(id: issue.recordID) else { return issue.subtitle }
            parts = [
                publication.journal.nonEmpty,
                publication.year.nonEmpty,
                publication.authorNames.first?.nonEmpty,
            ]
        case .organizations:
            guard let organization = organization(id: issue.recordID) else { return issue.subtitle }
            parts = [
                organization.city.nonEmpty,
                organization.country.nonEmpty,
                organization.websiteURL.nonEmpty,
            ]
        case .journals:
            guard let journal = publicationJournal(id: issue.recordID) else { return issue.subtitle }
            parts = [
                journal.publisher.nonEmpty,
                journal.issn.nonEmpty.map { "ISSN \($0)" },
                journal.eissn.nonEmpty.map { "eISSN \($0)" },
            ]
        default:
            return issue.subtitle
        }
        let line = parts.compactMap { $0 }.joined(separator: " · ")
        return line.nonEmpty ?? issue.subtitle
    }

    /// What the web searches for this record start from; nil for records
    /// that only exist in the app (applications, projects, teaching), where
    /// a web search would not help.
    func dataQualitySearchSubject(for issue: MissingFieldIssue) -> DataQualitySearchSubject? {
        switch issue.destination {
        case .people:
            guard let author = publicationAuthor(id: issue.recordID) else { return nil }
            return DataQualitySearchSubject(
                kind: .person,
                firstName: author.firstName,
                lastName: author.lastName,
                name: author.displayName,
                organization: author.primaryAffiliation?.organization ?? ""
            )
        case .publications:
            guard let publication = publication(id: issue.recordID),
                  publication.title.trimmedOrNil != nil else {
                return nil
            }
            return DataQualitySearchSubject(kind: .publication, name: publication.title)
        case .organizations:
            guard let organization = organization(id: issue.recordID) else { return nil }
            return DataQualitySearchSubject(kind: .organization, name: organization.nameSv.nonEmpty ?? organization.nameEn)
        case .journals:
            guard let journal = publicationJournal(id: issue.recordID),
                  journal.name.trimmedOrNil != nil else {
                return nil
            }
            return DataQualitySearchSubject(kind: .journal, name: journal.name)
        case .doctoralCandidates:
            guard let candidate = doctoralCandidates.first(where: { $0.id == issue.recordID }),
                  candidate.candidateName.trimmedOrNil != nil else {
                return nil
            }
            return DataQualitySearchSubject(kind: .person, name: candidate.candidateName)
        default:
            return nil
        }
    }

    /// The search buttons for one flagged field (empty when there is nothing
    /// to search with).
    func dataQualitySearchLinks(for issue: MissingFieldIssue, field: MissingFieldIssue.Field) -> [DataQualitySearchLink] {
        guard let subject = dataQualitySearchSubject(for: issue) else { return [] }
        // A missing name cannot be searched for by that name.
        if field.key == .journalName || field.key == .publicationTitle || field.key == .doctoralCandidateName {
            return []
        }
        return DataQualitySearchQuery.links(field: field.key, fieldLabel: field.label, subject: subject)
    }
}
