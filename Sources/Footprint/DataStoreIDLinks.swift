import Foundation

/// "Alla kopplingar via id": the one place that answers "which record does
/// this row point to?" for organizations, fund managers, projects, journals
/// and teaching institutions. The stored id decides. The written name is only
/// used for rows that have no id yet (older data), or whose id points to a
/// record that no longer exists. The name stays the display text of the row.
extension GrantDataStore {
    // MARK: - Generic rule

    /// The record a row points to, for code that keeps both an id and a
    /// written name and rewrites the name from the record (the save paths).
    /// The id decides, with two exceptions that keep editing by name working:
    /// an empty name clears the link, and a name that clearly names another
    /// record (the user picked another one by name) moves the link there. A
    /// name that names nothing keeps the id (for example an old name left
    /// behind after a rename).
    static func idFirstLinkedRecord<Record>(
        id: String?,
        name: String?,
        byID: (String) -> Record?,
        byName: (String) -> Record?,
        recordID: (Record) -> String,
        recordNames: (Record) -> [String]
    ) -> Record? {
        guard let name = name?.trimmedOrNil else { return nil }
        guard let id = id?.trimmedOrNil, let linked = byID(id) else {
            return byName(name)
        }
        let nameKey = normalizedIDLinkName(name)
        if recordNames(linked).contains(where: { normalizedIDLinkName($0) == nameKey }) {
            return linked
        }
        if let named = byName(name), recordID(named) != recordID(linked) {
            return named
        }
        return linked
    }

    /// The form names are compared in when a row's name is checked against
    /// the record its id points to (trimmed, case and accents ignored).
    nonisolated static func normalizedIDLinkName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "sv_SE"))
    }

    // MARK: - Organizations

    /// The organization a row points to: by id first, by name only for rows
    /// without a (working) id.
    func linkedOrganization(id: String?, name: String?) -> OrganizationRecord? {
        if let id = id?.trimmedOrNil, let linked = organization(id: id) {
            return linked
        }
        // Round 11: by name only when exactly one organization has it.
        return uniqueOrganization(matchingName: name)
    }

    /// The one organization whose Swedish or English name is this text
    /// (trimmed, case and accents ignored); nil when none or several match.
    /// Used when an older row is given its id, so that a name shared by two
    /// organizations never picks one of them by chance.
    func uniqueOrganization(matchingName name: String?) -> OrganizationRecord? {
        guard let trimmed = name?.trimmedOrNil else { return nil }
        let key = Self.normalizedIDLinkName(trimmed)
        let matches = organizations.filter { organization in
            [organization.nameSv, organization.nameEn].contains { candidate in
                !candidate.isEmpty && Self.normalizedIDLinkName(candidate) == key
            }
        }
        return matches.count == 1 ? matches.first : nil
    }

    /// Round 11: the one fund manager with this name; nil when none or
    /// several match, so a shared name never links a row to the wrong one.
    func uniqueManager(matchingName name: String?) -> ManagerOption? {
        guard let trimmed = name?.trimmedOrNil else { return nil }
        let key = Self.normalizedIDLinkName(trimmed)
        let matches = managers.filter { manager in
            [manager.nameSv, manager.nameEn].contains { candidate in
                !candidate.isEmpty && Self.normalizedIDLinkName(candidate) == key
            }
        }
        return matches.count == 1 ? matches.first : nil
    }

    /// Round 11: the one project with this name; nil when none or several
    /// match.
    func uniqueProject(named name: String?) -> ProjectRecord? {
        guard let trimmed = name?.trimmedOrNil else { return nil }
        let key = Self.normalizedIDLinkName(trimmed)
        let matches = projects.filter { project in
            [project.nameSv, project.nameEn].contains { candidate in
                !candidate.isEmpty && Self.normalizedIDLinkName(candidate) == key
            }
        }
        return matches.count == 1 ? matches.first : nil
    }

    /// The grant provider of an application.
    func linkedFunder(of application: GrantApplication) -> OrganizationRecord? {
        linkedOrganization(id: application.organizationID, name: application.organization)
    }

    /// The fund manager of an application.
    func linkedFundManager(of application: GrantApplication) -> ManagerOption? {
        if let id = application.applicationManagerID?.trimmedOrNil, let linked = manager(id: id) {
            return linked
        }
        // Round 11: by name only when exactly one fund manager has it.
        return uniqueManager(matchingName: application.applicationManager)
    }

    /// The institution of a course or programme.
    func linkedInstitution(of course: TeachingCourse) -> OrganizationRecord? {
        linkedOrganization(id: course.institutionID, name: course.institution)
    }

    /// The institution of a teaching component (moment).
    func linkedInstitution(of component: TeachingComponent) -> OrganizationRecord? {
        linkedOrganization(id: component.institutionID, name: component.institution)
    }

    /// The institution of a doctoral student.
    func linkedInstitution(of candidate: DoctoralCandidateRecord) -> OrganizationRecord? {
        linkedOrganization(id: candidate.institutionID, name: candidate.institution)
    }

    /// The institution a course is grouped and filtered under in the
    /// teaching views: the linked organization's Swedish name, or the
    /// written text for a course without a link.
    func teachingInstitutionKey(for course: TeachingCourse) -> String {
        linkedInstitution(of: course)?.nameSv.trimmedOrNil ?? course.institution.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The institution a teaching component is grouped and filtered under.
    func teachingInstitutionKey(for component: TeachingComponent) -> String {
        linkedInstitution(of: component)?.nameSv.trimmedOrNil ?? component.institution.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The organization of a review assignment (grant reviews, examinations,
    /// expert assignments, …).
    func linkedOrganization(of review: CVReviewEntry) -> OrganizationRecord? {
        linkedOrganization(id: review.organizationID, name: review.organizationName)
    }

    /// The organization shown for a row: its name in the app's language when
    /// the row points to an organization, otherwise the written text. Same
    /// wording as `organizationLabel(for:language:)`.
    func organizationLabel(id: String?, name: String, language: AppLanguage) -> String {
        guard let linked = linkedOrganization(id: id, name: name) else { return name }
        return language == .swedish ? linked.nameSv : (linked.nameEn.nonEmpty ?? linked.nameSv)
    }

    /// The grant provider's name in the app's language.
    func organizationLabel(for application: GrantApplication, language: AppLanguage) -> String {
        organizationLabel(id: application.organizationID, name: application.organization, language: language)
    }

    /// A course's institution in the app's language.
    func organizationLabel(for course: TeachingCourse, language: AppLanguage) -> String {
        organizationLabel(id: course.institutionID, name: course.institution, language: language)
    }

    /// A course's institution in the app's language; "" when there is no course.
    func organizationLabel(forCourse course: TeachingCourse?, language: AppLanguage) -> String {
        guard let course else { return "" }
        return organizationLabel(for: course, language: language)
    }

    /// A teaching component's institution in the app's language.
    func organizationLabel(for component: TeachingComponent, language: AppLanguage) -> String {
        organizationLabel(id: component.institutionID, name: component.institution, language: language)
    }

    /// A doctoral student's institution in the app's language.
    func organizationLabel(for candidate: DoctoralCandidateRecord, language: AppLanguage) -> String {
        organizationLabel(id: candidate.institutionID, name: candidate.institution, language: language)
    }

    /// The fund manager's name in the app's language, or the written text.
    func managerLabel(for application: GrantApplication, language: AppLanguage) -> String? {
        guard let linked = linkedFundManager(of: application) else {
            return application.applicationManager?.trimmedOrNil
        }
        return language == .swedish ? linked.nameSv : (linked.nameEn.nonEmpty ?? linked.nameSv)
    }

    /// The grant provider's stored (Swedish) name as the application shows
    /// it: the linked organization's current name, or the written text for an
    /// application that points to no organization.
    func funderName(for application: GrantApplication) -> String {
        linkedFunder(of: application)?.nameSv.trimmedOrNil ?? application.organization
    }

    /// The key the grant-provider index files an application under: the
    /// linked organization's Swedish name, or the written text for an
    /// application that points to no organization.
    func linkedOrganizationKey(for application: GrantApplication) -> String? {
        linkedFunder(of: application)?.nameSv.trimmedOrNil ?? application.organization.trimmedOrNil
    }

    /// The key the fund-manager index files an application under.
    func linkedManagerKey(for application: GrantApplication) -> String? {
        linkedFundManager(of: application)?.nameSv.trimmedOrNil ?? application.applicationManager?.trimmedOrNil
    }

    /// True when the application's grant provider is this organization.
    func applicationIsFunded(_ application: GrantApplication, by organization: OrganizationRecord) -> Bool {
        if let linked = linkedFunder(of: application) {
            return linked.id == organization.id
        }
        return false
    }

    /// True when the application's fund manager is this organization.
    func applicationIsManaged(_ application: GrantApplication, by organization: OrganizationRecord) -> Bool {
        if let linked = linkedFundManager(of: application) {
            return linked.id == organization.id
        }
        return false
    }

    /// The applications an organization gave (grant provider), decided by
    /// the applications' links.
    func applications(forOrganization organization: OrganizationRecord) -> [GrantApplication] {
        applications(forOrganizationName: organization.nameSv).filter { applicationIsFunded($0, by: organization) }
    }

    /// The applications an organization manages (fund manager), decided by
    /// the applications' links.
    func managedApplications(forOrganization organization: OrganizationRecord) -> [GrantApplication] {
        applications(forManagerName: organization.nameSv).filter { applicationIsManaged($0, by: organization) }
    }

    // MARK: - Projects

    /// The project a row points to: by id first, by name only for rows
    /// without a (working) id.
    func linkedProject(id: String?, name: String?) -> ProjectRecord? {
        if let id = id?.trimmedOrNil, let linked = project(id: id) {
            return linked
        }
        return project(named: name)
    }

    /// The project of an application.
    func linkedProject(of application: GrantApplication) -> ProjectRecord? {
        linkedProject(id: application.projectID, name: application.projectType)
    }

    /// The project of a publication.
    func linkedProject(of publication: PublicationRecord) -> ProjectRecord? {
        linkedProject(id: publication.projectID, name: publication.projectName)
    }

    /// The project of a conference contribution (the Swedish or English
    /// project name is only used when the contribution has no id).
    func linkedProject(of contribution: CVConferenceContribution) -> ProjectRecord? {
        if let id = contribution.projectID?.trimmedOrNil, let linked = project(id: id) {
            return linked
        }
        return project(named: contribution.projectNameSv) ?? project(named: contribution.projectNameEn)
    }

    /// The key the project indexes file an application under: the linked
    /// project's Swedish name, or the written text when it points to none.
    func linkedProjectKey(for application: GrantApplication) -> String? {
        linkedProject(of: application)?.nameSv.trimmedOrNil ?? application.projectType?.trimmedOrNil
    }

    /// The key the project indexes file a publication under.
    func linkedProjectKey(for publication: PublicationRecord) -> String? {
        linkedProject(of: publication)?.nameSv.trimmedOrNil ?? publication.projectName?.trimmedOrNil
    }

    /// The project shown for an application in the app's language, or the
    /// written text; nil when the application has no project.
    func projectLabel(for application: GrantApplication, language: AppLanguage) -> String? {
        guard let linked = linkedProject(of: application) else {
            return application.projectType?.trimmedOrNil
        }
        return language == .swedish ? (linked.nameSv.nonEmpty ?? linked.nameEn) : (linked.nameEn.nonEmpty ?? linked.nameSv)
    }

    /// The project shown for a publication in the app's language, or the
    /// written text; nil when the publication has no project.
    func projectLabel(for publication: PublicationRecord, language: AppLanguage) -> String? {
        guard let linked = linkedProject(of: publication) else {
            return publication.projectName?.trimmedOrNil
        }
        return language == .swedish ? (linked.nameSv.nonEmpty ?? linked.nameEn) : (linked.nameEn.nonEmpty ?? linked.nameSv)
    }

    /// True when the application belongs to this project.
    func applicationBelongs(_ application: GrantApplication, to project: ProjectRecord) -> Bool {
        linkedProject(of: application)?.id == project.id
    }

    /// True when the publication belongs to this project.
    func publicationBelongs(_ publication: PublicationRecord, to project: ProjectRecord) -> Bool {
        linkedProject(of: publication)?.id == project.id
    }

    /// True when the conference contribution belongs to this project.
    func contributionBelongs(_ contribution: CVConferenceContribution, to project: ProjectRecord) -> Bool {
        linkedProject(of: contribution)?.id == project.id
    }

    // MARK: - Journals

    /// The journal a row points to: by id first, by name (or ISSN) only for
    /// rows without a (working) id.
    func linkedJournal(id: String?, name: String?) -> PublicationJournal? {
        if let id = id?.trimmedOrNil, let linked = publicationJournal(id: id) {
            return linked
        }
        guard let name = name?.trimmedOrNil else { return nil }
        return publicationJournal(named: name)
    }

    /// The journal of a publication.
    func linkedJournal(of publication: PublicationRecord) -> PublicationJournal? {
        linkedJournal(id: publication.journalID, name: publication.journal)
    }

    /// The journal of an earlier submission of a publication.
    func linkedJournal(of attempt: PublicationAttempt) -> PublicationJournal? {
        linkedJournal(id: attempt.journalID, name: attempt.journal)
    }

    /// The journal a conference contribution was published in.
    func linkedJournal(of contribution: CVConferenceContribution) -> PublicationJournal? {
        linkedJournal(id: contribution.journalID, name: contribution.journalName)
    }

    /// The journal of a journal review.
    func linkedJournal(of review: CVReviewEntry) -> PublicationJournal? {
        linkedJournal(id: review.journalID, name: review.journalName)
    }

    /// The journal of one submission row (current or earlier journal of a
    /// publication). The row only carries the journal's name, so the
    /// publication's own links are used first: its current journal, then the
    /// earlier attempt with that name.
    func linkedJournal(ofSubmissionJournalName journalName: String, in publication: PublicationRecord) -> PublicationJournal? {
        let key = Self.normalizedIDLinkName(journalName)
        guard !key.isEmpty else { return nil }
        if Self.normalizedIDLinkName(publication.journal) == key,
           let journal = linkedJournal(of: publication) {
            return journal
        }
        if let attempt = publication.previousAttempts.first(where: { Self.normalizedIDLinkName($0.journal) == key }),
           let journal = linkedJournal(of: attempt) {
            return journal
        }
        return publicationJournal(named: journalName)
    }
}
